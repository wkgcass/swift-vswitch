import Atomics
import SwiftEventLoopCommon
import SwiftLinkedListAndHash
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

        let entry = global.record(conn: conn)
        conn.__setGlobal(entry)
        conns[tup] = conn
    }

    // the isMigrating field should be already set, and locks should be properly retrieved before calling this function
    public func migrate(anotherConn: Connection, thisNextNode: NodeRef, peer: Connection?, thisDest: Dest? = nil) -> Connection {
        let newConn = Connection(ct: self, isBeforeNat: anotherConn.isBeforeNat, tup: anotherConn.tup, nextNode: thisNextNode)
        newConn.peer = anotherConn.peer
        newConn.state_ = anotherConn.state_
        newConn.dest_ = thisDest // should touch the statistics
        newConn.fastOutput.enabled = anotherConn.fastOutput.enabled
        let newgconn = global.recordNoLock(conn: newConn)
        newConn.__setGlobal(newgconn)

        conns[newConn.tup] = newConn
        anotherConn.ct.sw.loop.runOnLoop {
            anotherConn.destroy(touchConntrack: true, touchPeer: false)
            if let peer {
                peer.peer = newConn
                if !newConn.isBeforeNat { // always use isBeforeNat conn's isMigrating field
                    _ = peer.isMigrating.compareExchange(expected: true, desired: false, ordering: .relaxed)
                }
            }
        }
        return newConn
    }
}

#if GLOBAL_WEAK_CONN_DEBUG
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
    // record the conn in service
    var node = ConnectionServiceListNode()

    private let destroyed_ = ManagedAtomic<Bool>(false)
    public var destroyed: Bool { destroyed_.load(ordering: .relaxed) }
    public let ct: Conntrack
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
    private let isMigrating_: ManagedAtomic<Bool>?
    var isMigrating: ManagedAtomic<Bool> {
        if isBeforeNat { isMigrating_! }
        else { peer!.isMigrating_! }
    }

    public var fastOutput = FastOutput()

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

    public init(ct: Conntrack, isBeforeNat: Bool, tup: PktTuple, nextNode: NodeRef) {
        self.ct = ct
        self.isBeforeNat = isBeforeNat
        self.tup = tup
        self.nextNode = nextNode
        if isBeforeNat {
            isMigrating_ = .init(false)
        } else {
            isMigrating_ = nil
        }
#if GLOBAL_WEAK_CONN_DEBUG
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
            self.node.removeSelf()

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

public struct ConnectionServiceListNode: LinkedListNode {
    public typealias V = Connection
    public var vars = LinkedListNodeVars()
    public static let fieldOffset = 0
    public init() {}
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
    private var map: GeneralLinkedHashMap<GlobalConntrackHash, GlobalConnEntryNode>

    init(params: VSwitchParams) {
        let size = Utils.findNextPowerOf2(params.conntrackGlobalHashSize)
        map = GeneralLinkedHashMap<GlobalConntrackHash, GlobalConnEntryNode>(size)
    }

    public func record(conn: Connection) -> GlobalConnEntry {
        let tup = conn.tup
        let i = map.indexOf(key: tup)
        return map[i].pointee.record(conn)
    }

    public func recordNoLock(conn: Connection) -> GlobalConnEntry {
        let tup = conn.tup
        let i = map.indexOf(key: tup)
        return map[i].pointee.record(conn, lock: false)
    }

    public func lookup(_ tup: PktTuple) -> (Int, GlobalConnEntry, RWLockRef)? {
        let i = map.indexOf(key: tup)
        guard let res = map[i].pointee.lookup(tup) else {
            return nil
        }
        let (e, l) = res
        return (i, e, l)
    }

    public func lookup(_ tup: PktTuple, withLockedIndex locked: Int) -> (Int, GlobalConnEntry, RWLockRef?)? {
        let i = map.indexOf(key: tup)
        if i == locked {
            if let res = map[i].pointee[tup] {
                return (i, res, nil)
            } else {
                return nil
            }
        } else {
            if let res = map[i].pointee.lookup(tup) {
                let (e, l) = res
                return (i, e, l)
            } else {
                return nil
            }
        }
    }

    deinit {
        map.destroy()
    }
}

public struct GlobalConntrackHash: LinkedHashProtocol {
    private var lock_: RWLockRef?
    var lock: RWLockRef { lock_! }
    public var list: LinkedList<GlobalConnEntryNode>

    public mutating func initStruct() {
        lock_ = RWLockRef()
    }

    public mutating func record(_ conn: Connection, lock: Bool = true) -> GlobalConnEntry {
        let entry = GlobalConnEntry(conn, lock: self.lock)

        if lock {
            self.lock.wlock()
        }

        entry.node.insertInto(list: &list)

        if lock {
            self.lock.unlock()
        }

        ENSURE_REFERENCE_COUNTED(entry)
        return entry
    }

    public mutating func lookup(_ tup: PktTuple) -> (GlobalConnEntry, RWLockRef)? {
        lock.rlock()
        for n in list.seq() {
            if n.conn.tup == tup {
                return (n, lock)
            }
        }
        lock.unlock()
        return nil
    }

    public mutating func destroy() {
        list.destroy()
    }
}

public class GlobalConnEntry {
    var node = GlobalConnEntryNode()
    private let lock: RWLockRef
    public let conn: Connection
    private let lastRedirectedFrom = ManagedAtomic<Int>(0)
    private let redirectedCount = ManagedAtomic<Int>(0)

    init(_ conn: Connection, lock: RWLockRef) {
        self.conn = conn
        self.lock = lock
    }

    public func needToMigrate(swIndex: Int) -> Bool {
        if conn.isMigrating.load(ordering: .relaxed) {
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
            let (exchanged, _) = conn.isMigrating.compareExchange(expected: false, desired: true, ordering: .relaxed)
            if exchanged {
                return true
            }
        }
        return false
    }

    public func removeSelf() {
        lock.wlock()
        node.removeSelf()
        lock.unlock()
    }
}

public struct GlobalConnEntryNode: LinkedHashMapEntry {
    public typealias K = PktTuple
    public typealias V = GlobalConnEntry

    public var vars = LinkedListNodeVars()
    public init() {}

    public static let fieldOffset = 0
    public mutating func key() -> K { element().conn.tup }
}
