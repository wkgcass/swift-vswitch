import VProxyCommon
import SwiftEventLoopCommon

public class Conntrack {
    var conns = [PktTuple: Connection]()

    public func lookup(_ tup: PktTuple) -> Connection? {
        return conns[tup]
    }

    public func put(_ tup: PktTuple, _ conn: Connection) {
        let oldConn = conns.updateValue(conn, forKey: tup)
        guard let oldConn else {
            return
        }
        if let peer = oldConn.peer {
            peer.destroy(touchConntrack: true, touchPeer: false)
        }
        oldConn.destroy(touchConntrack: false, touchPeer: false)
    }
}

public class Connection {
    public let ct: Conntrack
    public var peer: Connection? = nil
    public let isBeforeNat: Bool
    public private(set) var tup: PktTuple
    public var state: ConnState = .NONE
    private var timer: Timer?
    public let nextNode: NodeRef
    public var ud: AnyObject?
    private var destroyed: Bool = false

    public var fastOutput = FastOutput()

    public init(ct: Conntrack, isBeforeNat: Bool, tup: PktTuple, nextNode: NodeRef) {
        self.ct = ct
        self.isBeforeNat = isBeforeNat
        self.tup = tup
        self.nextNode = nextNode
    }

    public func resetTimer(resetPeer: Bool = true) {
        if resetPeer, let peer = self.peer {
            peer.resetTimer(resetPeer: false)
        }
        if let timer = timer {
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
        default: return 5_000
        }
    }

    public func destroy(touchConntrack: Bool, touchPeer: Bool = true) {
        if destroyed {
            return
        }
        destroyed = true

        if let timer = timer {
            timer.cancel()
        }
        timer = nil

        if touchConntrack {
            ct.conns.removeValue(forKey: tup)
        }
        if touchPeer, let peer = self.peer {
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
            parent.timer = nil
            parent.destroy(touchConntrack: true)
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
    public var outdev: IfaceEx? = nil
    public var outSrcMac: MacAddress = MacAddress.ZERO
    public var outDstMac: MacAddress = MacAddress.ZERO
}
