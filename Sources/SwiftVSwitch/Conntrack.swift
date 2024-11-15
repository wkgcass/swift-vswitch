import Atomics
import SwiftEventLoopCommon
import SwiftVSwitchVirtualServerBase
import VProxyCommon

public class Conntrack {
    public unowned let sw: VSwitchPerThread
    public let global: GlobalConntrack
    var conns = [PktTuple: Connection]()

    init(sw: VSwitchPerThread, global: GlobalConntrack) {
        self.sw = sw
        self.global = global
    }

    public func lookup(_ tup: PktTuple) -> Connection? {
        return conns[tup]
    }

    public func put(_ tup: PktTuple, _ conn: Connection) {
        let oldConn = conns.removeValue(forKey: tup)
        if let oldConn {
            if let peer = oldConn.peer {
                peer.destroy(touchConntrack: true, touchPeer: false)
            }
            oldConn.destroy(touchConntrack: false, touchPeer: false)
        }

        let entry = global.put(tup: tup, conn: conn)
        conn.__setGlobal(entry)
        conns.updateValue(conn, forKey: tup)
    }

    // called on new event loop (before packet redireced)
    public func migrate(_ conn: Connection) {
        let oldCT = conn.ct
        conns[conn.tup] = conn
        conn.ct = self
        oldCT.sw.loop.runOnLoop {
            oldCT.migrateDone(conn)
        }
    }

    // called on old event loop (after packet redirected)
    private func migrateDone(_ conn: Connection) {
        conns.removeValue(forKey: conn.tup)
        _ = conn.global.isMigrating.compareExchange(expected: true, desired: false, ordering: .relaxed)
    }
}

public class Connection {
    private let destroyed_ = ManagedAtomic<Bool>(false)
    public var destroyed: Bool { destroyed_.load(ordering: .relaxed) }
    public internal(set) var ct: Conntrack
    public var peer: Connection?
    public let isBeforeNat: Bool
    public private(set) var tup: PktTuple
    public var state: ConnState = .NONE
    private var timer: Timer?
    public var nextNode: NodeRef
    public var dest: Dest?
    private var global_: GlobalConnEntry?
    public var global: GlobalConnEntry { global_! }

    private let passedPkts = ManagedAtomic<Int64>(0)
    private var lastCheckedPassedPkts: Int64 = 0

    public var fastOutput = FastOutput()

    public init(ct: Conntrack, isBeforeNat: Bool, tup: PktTuple, nextNode: NodeRef) {
        self.ct = ct
        self.isBeforeNat = isBeforeNat
        self.tup = tup
        self.nextNode = nextNode
    }

    // must be called before putting conn into conntrack
    public func __setGlobal(_ global: GlobalConnEntry) {
        global_ = global
    }

    public func packetPassed() {
        passedPkts.wrappingIncrement(ordering: .relaxed)
        if let peer {
            peer.passedPkts.wrappingIncrement(ordering: .relaxed)
        }
    }

    public func resetTimer(resetPeer: Bool = true) {
        if resetPeer, let peer {
            peer.resetTimer(resetPeer: false)
        }
        if let timer {
            timer.setTimeout(millis: getTimeoutMillis())
            timer.resetTimer()
            return
        }
        timer = Timer(parent: self, timeoutMillis: getTimeoutMillis())
        timer!.start()
    }

    private func getTimeoutMillis() -> Int {
        switch state {
        case .TCP_ESTABLISHED: return 900_000 // TODO: custom config
        case .UDP_ESTABLISHED: return 900_000
        default: return 5000
        }
    }

    public func destroy(touchConntrack: Bool = true, touchPeer: Bool = true) {
        if destroyed {
            return
        }
        destroyed_.store(true, ordering: .relaxed)
        global.removeSelf()

        let timer = timer
        ct.sw.loop.runOnLoop {
            if let timer {
                timer.cancel()
            }
            self.timer = nil

            if touchConntrack {
                self.ct.conns.removeValue(forKey: self.tup)
            }
        }
        if touchPeer, let peer {
            peer.destroy(touchConntrack: touchConntrack, touchPeer: false)
        }
    }

    class Timer: SwiftEventLoopCommon.Timer {
        let parent: Connection
        init(parent: Connection, timeoutMillis: Int) {
            self.parent = parent
            super.init(loop: SelectorEventLoop.current()!, timeoutMillis: timeoutMillis)
        }

        override func cancel() {
            if !parent.destroyed {
                let current = parent.passedPkts.load(ordering: .relaxed)
                if parent.lastCheckedPassedPkts != current {
                    parent.lastCheckedPassedPkts = current
                    resetTimer()
                    return
                }
            }

            parent.timer = nil
            parent.destroy()
        }
    }
}

public enum ConnState {
    case NONE
    case TCP_SYN_SENT
    case TCP_SYN_RECV
    case TCP_ESTABLISHED
    case TCP_FIN_WAIT_1
    case TCP_FIN_WAIT_2
    case TCP_CLOSING
    case TCP_TIME_WAIT
    case TCP_CLOSE
    case TCP_CLOSE_WAIT
    case TCP_LAST_ACK
    case UDP_SINGLE_DIR
    case UDP_ESTABLISHED
}

public struct FastOutput {
    public var enabled: Bool = false
    public var isValid: Bool = false
    public var outdev: IfaceEx?
    public var outSrcMac: MacAddress = .ZERO
    public var outDstMac: MacAddress = .ZERO
}

public class GlobalConntrack {
    private var conns: [GlobalConntrackHash]
    private let modsz: Int
    init(params: VSwitchParams) {
        let size = Utils.findNextPowerOf2(params.conntrackGlobalHashSize)
        modsz = size - 1
        conns = [GlobalConntrackHash](repeating: GlobalConntrackHash(), count: size)
    }

    public func put(tup: PktTuple, conn: Connection) -> GlobalConnEntry {
        let i = tup.hashValue & modsz
        return conns[i].add(conn)
    }

    public func lookup(_ tup: PktTuple) -> (GlobalConnEntry, RWLockRef)? {
        let i = tup.hashValue & modsz
        return conns[i].find(tup)
    }

    deinit {
        for c in conns {
            c.destroy()
        }
    }
}

public struct GlobalConntrackHash {
    var lock: RWLockRef
    var head: GlobalConnEntry

    init() {
        let lock = RWLockRef()
        self.lock = lock
        head = GlobalConnEntry(nil, lock: lock)
        head.next = head
        head.prev = head
    }

    public mutating func add(_ conn: Connection) -> GlobalConnEntry {
        let entry = GlobalConnEntry(conn, lock: lock)

        lock.wlock()
        defer { lock.unlock() }

        let tail = head.prev!
        tail.next = entry
        entry.prev = tail
        entry.next = head
        return entry
    }

    public func find(_ tup: PktTuple) -> (GlobalConnEntry, RWLockRef)? {
        lock.rlock()

        var n = head.next!
        while n !== head {
            if n.conn.tup == tup {
                return (n, lock)
            }
            n = n.next!
        }
        lock.unlock()
        return nil
    }

    public func destroy() {
        // release refcnt
        var n = head
        while n.next != nil {
            let tmp = n.next!
            n.next = nil
            n = tmp
        }
        n = head
        while n.prev != nil {
            let tmp = n.prev!
            n.prev = nil
            n = tmp
        }
    }
}

public class GlobalConnEntry {
    private let lock: RWLockRef
    private let conn_: Connection?
    public var conn: Connection { conn_! }
    public var prev: GlobalConnEntry?
    public var next: GlobalConnEntry?
    private let lastRedirectedFrom = ManagedAtomic<Int>(0)
    private let redirectedCount = ManagedAtomic<Int>(0)
    let isMigrating = ManagedAtomic<Bool>(false)

    init(_ conn: Connection?, lock: RWLockRef) {
        conn_ = conn
        self.lock = lock
    }

    public func needToMigrate(swIndex: Int) -> Bool {
        if isMigrating.load(ordering: .relaxed) {
            return false
        }
        let last = lastRedirectedFrom.load(ordering: .relaxed)
        if last != swIndex {
            _ = lastRedirectedFrom.compareExchange(expected: last, desired: swIndex, ordering: .relaxed)
            redirectedCount.store(0, ordering: .relaxed)
            return false
        }
        let cnt = redirectedCount.load(ordering: .relaxed)
        if cnt > 1024 {
            let (exchanged, _) = isMigrating.compareExchange(expected: false, desired: true, ordering: .relaxed)
            if exchanged {
                return true
            }
        }
        return false
    }

    public func removeSelf() {
        lock.wlock()
        defer { lock.unlock() }
        prev!.next = next
        next!.prev = prev
    }
}
