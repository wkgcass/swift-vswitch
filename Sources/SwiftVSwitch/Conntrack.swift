import Atomics
import SwiftEventLoopCommon
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

    public func put(_ conn: Connection) {
        let tup = conn.tup
        let oldConn = conns.removeValue(forKey: tup)
        if let oldConn {
            if let peer = oldConn.peer {
                peer.destroy(touchConntrack: true, touchPeer: false)
            }
            oldConn.destroy(touchConntrack: false, touchPeer: false)
        }

        let entry = global.put(conn: conn)
        conn.__setGlobal(entry)
        conns[tup] = conn
    }

    // the isMigrating field should be already set, and locks should be properly retrieved before calling this function
    public func migrate(anotherConn: Connection, thisNextNode: NodeRef, gconnPeer: GlobalConnEntry?, thisDest: Dest? = nil) -> Connection {
        let newConn = Connection(ct: self, isBeforeNat: anotherConn.isBeforeNat, tup: anotherConn.tup, nextNode: thisNextNode)
        newConn.peer = anotherConn.peer
        newConn.state_ = anotherConn.state_
        newConn.dest_ = thisDest // should touch the statistics
        newConn.fastOutput.enabled = anotherConn.fastOutput.enabled
        let newgconn = global.putNoLock(conn: newConn)
        newConn.__setGlobal(newgconn)

        conns[newConn.tup] = newConn
        anotherConn.ct.sw.loop.runOnLoop {
            anotherConn.destroy(touchConntrack: true, touchPeer: false)
            if let gconnPeer {
                gconnPeer.conn.peer = newConn
                _ = gconnPeer.isMigrating.compareExchange(expected: true, desired: false, ordering: .releasing)
            }
        }
        return newConn
    }
}

#if SWVS_DEBUG
public struct WeakConnRef {
    public weak var conn: Connection?

    public nonisolated(unsafe) static var refs = [WeakConnRef](repeating: WeakConnRef(), count: 1_048_576)
    private nonisolated(unsafe) static var off = 0
    public nonisolated(unsafe) static var lock = Lock()
    public static func record(_ conn: Connection) {
        lock.lock()
        let last = off
        while true {
            var next = off + 1
            if next == refs.count {
                next = 0
            }
            if refs[off].conn == nil {
                refs[off].conn = conn
                off = next
                break
            }
            off = next
            if off == last { // not stored
                break
            }
        }
        lock.unlock()
    }
}
#endif

public class Connection {
    private let destroyed_ = ManagedAtomic<Bool>(false)
    public var destroyed: Bool { destroyed_.load(ordering: .relaxed) }
    private let ct_: Conntrack?
    public var ct: Conntrack { ct_! }
    public var peer: Connection?
    public let isBeforeNat: Bool
    public let tup: PktTuple
    var state_: ConnState = .NONE
    public private(set) var timer: Timer?
    public internal(set) var nextNode: NodeRef
    var dest_: Dest?
    private var global_: GlobalConnEntry?
    public var global: GlobalConnEntry { global_! }

    private let passedPkts = ManagedAtomic<Int64>(0)
    private var lastCheckedPassedPkts: Int64 = 0

    public var fastOutput = FastOutput()

    // record the conn in service or other places
    public var ___next_: Connection?
    public var ___prev_: Connection?
    public var next: Connection { ___next_! }
    public var prev: Connection { ___prev_! }

    public var state: ConnState {
        get { state_ }
        set {
            if let dest_ {
                if state_.isActive && !newValue.isActive {
                    dest_.statistics.activeConns -= 1
                    dest_.statistics.inactiveConns += 1
                } else if !state_.isActive && newValue.isActive {
                    dest_.statistics.inactiveConns -= 1
                    dest_.statistics.activeConns += 1
                }
            }
            state_ = newValue
        }
    }

    public var dest: Dest? {
        get { dest_ }
        set {
            if let newValue {
                if state_.isActive {
                    newValue.statistics.activeConns += 1
                } else {
                    newValue.statistics.inactiveConns += 1
                }
            }
            dest_ = newValue
        }
    }

    public init(ct: Conntrack? = nil, isBeforeNat: Bool, tup: PktTuple, nextNode: NodeRef) {
        ct_ = ct
        self.isBeforeNat = isBeforeNat
        self.tup = tup
        self.nextNode = nextNode
#if SWVS_DEBUG
        WeakConnRef.record(self)
#endif
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
        if destroyed {
            return
        }
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

    public func getTimeoutMillis() -> Int {
        switch state_ {
        case .TCP_ESTABLISHED: return 90000 // TODO: custom config
        case .UDP_ESTABLISHED: return 120_000
        default: return 5000
        }
    }

    public func destroy(touchConntrack: Bool, touchPeer: Bool) {
        let (exchanged, _) = destroyed_.compareExchange(expected: false, desired: true, ordering: .relaxed)
        if !exchanged {
            return
        }
        global.removeSelf()

        let timer = timer
        let peer = peer
        ct.sw.loop.runOnLoop {
            self.peer = nil

            if let timer {
                timer.cancel()
            }
            self.timer = nil

            self.global_ = nil
            if let nx = self.___next_, let pr = self.___prev_ {
                nx.___prev_ = pr
                pr.___next_ = nx
            }
            self.___next_ = nil
            self.___prev_ = nil

            if touchConntrack {
                self.ct.conns.removeValue(forKey: self.tup)
            }
        }
        if touchPeer, let peer {
            peer.destroy(touchConntrack: touchConntrack, touchPeer: false)
        }
    }

    public class Timer: SwiftEventLoopCommon.Timer {
        let parent: Connection
        init(parent: Connection, timeoutMillis: Int) {
            self.parent = parent
            super.init(loop: SelectorEventLoop.current()!, timeoutMillis: timeoutMillis)
        }

        override public func cancel() {
            super.cancel()
            if parent.destroyed {
                parent.timer = nil
            } else {
                let current = parent.passedPkts.load(ordering: .relaxed)
                if parent.lastCheckedPassedPkts != current {
                    parent.lastCheckedPassedPkts = current
                    resetTimer()
                    return
                }
                parent.destroy(touchConntrack: true, touchPeer: true)
            }
        }
    }

    deinit {
        if let dest_ {
            if state_.isActive {
                dest_.statistics.activeConns -= 1
            } else {
                dest_.statistics.inactiveConns -= 1
            }
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
    case UDP_ONE_WAY
    case UDP_ESTABLISHED

    public var isActive: Bool {
        return self == .TCP_ESTABLISHED || self == .UDP_ESTABLISHED
    }
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

    public func put(conn: Connection) -> GlobalConnEntry {
        let tup = conn.tup
        let i = tup.hashValue & modsz
        return conns[i].add(conn)
    }

    public func putNoLock(conn: Connection) -> GlobalConnEntry {
        let tup = conn.tup
        let i = tup.hashValue & modsz
        return conns[i].add(conn, lock: false)
    }

    public func lookup(_ tup: PktTuple) -> (GlobalConnEntry, RWLockRef)? {
        let i = tup.hashValue & modsz
        return conns[i].find(tup)
    }

    public func lookupWithLock(_ tup: PktTuple, withLock: PktTuple) -> (GlobalConnEntry, RWLockRef?)? {
        let i = tup.hashValue & modsz
        let locked = withLock.hashValue & modsz
        if i == locked {
            if let res = conns[i].findNoLock(tup) {
                return (res, nil)
            } else {
                return nil
            }
        } else {
            return conns[i].find(tup)
        }
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

    public mutating func add(_ conn: Connection, lock: Bool = true) -> GlobalConnEntry {
        let entry = GlobalConnEntry(conn, lock: self.lock)

        if lock {
            self.lock.wlock()
        }

        let tail = head.prev!
        tail.next = entry
        entry.prev = tail
        entry.next = head
        head.prev = entry

        if lock {
            self.lock.unlock()
        }

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

    public func findNoLock(_ tup: PktTuple) -> GlobalConnEntry? {
        var n = head.next!
        while n !== head {
            if n.conn.tup == tup {
                return n
            }
            n = n.next!
        }
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

    public func setMigrateState() -> Bool {
        let (exchanged, _) = isMigrating.compareExchange(expected: false, desired: true, ordering: .relaxed)
        return exchanged
    }

    public func unsetMigrateState() {
        _ = isMigrating.compareExchange(expected: true, desired: false, ordering: .relaxed)
    }

    public func removeSelf() {
        lock.wlock()
        prev!.next = next
        next!.prev = prev
        next = nil
        prev = nil
        lock.unlock()
    }
}
