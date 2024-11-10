import SwiftVSwitch
import VProxyCommon

public typealias StateTransferRecord = [TcpStateFlag: ConnState]
// (packet from client, packet from server)
public typealias StateTransferTable = [ConnState: (StateTransferRecord, StateTransferRecord)]

public enum TcpStateFlag {
    case SYN
    case FIN
    case RST
    case ACK
}

public nonisolated(unsafe) let tcpStateTransferAsServer: StateTransferTable = [
    .NONE: (
        [
            .SYN: .TCP_SYN_RECV,
        ],
        [:]
    ),
    .TCP_SYN_RECV: (
        [
            .FIN: .TCP_CLOSE,
            .ACK: .TCP_ESTABLISHED,
            .RST: .TCP_CLOSE,
        ],
        [
            .FIN: .TCP_CLOSE,
            .ACK: .TCP_ESTABLISHED, // the dest may already have the connection
            .RST: .TCP_CLOSE,
        ]
    ),
    .TCP_ESTABLISHED: (
        [
            .FIN: .TCP_CLOSE_WAIT,
            .RST: .TCP_CLOSE,
        ],
        [
            .FIN: .TCP_FIN_WAIT_1,
            .RST: .TCP_CLOSE,
        ]
    ),
    .TCP_FIN_WAIT_1: (
        [
            .FIN: .TCP_CLOSING,
            .ACK: .TCP_FIN_WAIT_2,
            .RST: .TCP_CLOSE,
        ],
        [
            .RST: .TCP_CLOSE,
        ]
    ),
    .TCP_FIN_WAIT_2: (
        [
            .FIN: .TCP_TIME_WAIT,
            .RST: .TCP_CLOSE,
        ],
        [
            .RST: .TCP_CLOSE,
        ]
    ),
    .TCP_CLOSING: (
        [
            .RST: .TCP_CLOSE,
        ],
        [
            .ACK: .TCP_TIME_WAIT,
            .RST: .TCP_CLOSE,
        ]
    ),
    .TCP_TIME_WAIT: (
        [
            .SYN: .TCP_SYN_RECV,
            .RST: .TCP_CLOSE,
        ],
        [
            .RST: .TCP_CLOSE,
        ]
    ),
    .TCP_CLOSE: (
        [
            .SYN: .TCP_SYN_RECV,
        ],
        [:]
    ),
    .TCP_CLOSE_WAIT: (
        [
            .RST: .TCP_CLOSE,
        ],
        [
            .FIN: .TCP_LAST_ACK,
            .RST: .TCP_CLOSE,
        ]
    ),
    .TCP_LAST_ACK: (
        [
            .ACK: .TCP_CLOSE,
            .RST: .TCP_CLOSE,
        ],
        [
            .RST: .TCP_CLOSE,
        ]
    ),
]

public nonisolated(unsafe) let tcpStateTransferAsClient: StateTransferTable = [
    .NONE: (
        [
            .SYN: .TCP_SYN_SENT,
        ],
        [:]
    ),
    .TCP_SYN_SENT: (
        [
            .FIN: .TCP_CLOSE,
            .ACK: .TCP_ESTABLISHED,
            .RST: .TCP_CLOSE,
        ],
        [
            .FIN: .TCP_CLOSE,
            .RST: .TCP_CLOSE,
        ]
    ),
    .TCP_ESTABLISHED: (
        [
            .FIN: .TCP_FIN_WAIT_1,
            .RST: .TCP_CLOSE,
        ],
        [
            .FIN: .TCP_CLOSE_WAIT,
            .RST: .TCP_CLOSE,
        ]
    ),
    .TCP_FIN_WAIT_1: (
        [
            .RST: .TCP_CLOSE,
        ],
        [
            .FIN: .TCP_CLOSING,
            .ACK: .TCP_FIN_WAIT_2,
            .RST: .TCP_CLOSE,
        ]
    ),
    .TCP_FIN_WAIT_2: (
        [
            .RST: .TCP_CLOSE,
        ],
        [
            .FIN: .TCP_TIME_WAIT,
            .RST: .TCP_CLOSE,
        ]
    ),
    .TCP_CLOSING: (
        [
            .ACK: .TCP_TIME_WAIT,
            .RST: .TCP_CLOSE,
        ],
        [
            .RST: .TCP_CLOSE,
        ]
    ),
    .TCP_TIME_WAIT: (
        [
            .SYN: .TCP_SYN_SENT,
            .RST: .TCP_CLOSE,
        ],
        [
            .RST: .TCP_CLOSE,
        ]
    ),
    .TCP_CLOSE: (
        [
            .SYN: .TCP_SYN_SENT,
        ],
        [:]
    ),
    .TCP_CLOSE_WAIT: (
        [
            .FIN: .TCP_LAST_ACK,
            .RST: .TCP_CLOSE,
        ],
        [
            .RST: .TCP_CLOSE,
        ]
    ),
    .TCP_LAST_ACK: (
        [
            .RST: .TCP_CLOSE,
        ],
        [
            .ACK: .TCP_CLOSE,
            .RST: .TCP_CLOSE,
        ]
    ),
]

public func tcpStateTransfer(clientConn: Connection, serverConn: Connection, tcpFlags: UInt8, isFromClient: Bool) {
    let flag: TcpStateFlag
    if (tcpFlags & TCP_FLAGS_RST) != 0 {
        flag = .RST
    } else if (tcpFlags & TCP_FLAGS_SYN) != 0 {
        flag = .SYN
    } else if (tcpFlags & TCP_FLAGS_FIN) != 0 {
        flag = .FIN
    } else {
        flag = .ACK
    }

    var clientTransRecord: StateTransferRecord?
    var serverTransRecord: StateTransferRecord?

    var tup = tcpStateTransferAsClient[clientConn.state]
    if tup == nil {
        assert(Logger.lowLevelDebug("unable to find clientTransRecord with state \(clientConn.state)"))
    } else if isFromClient {
        clientTransRecord = tup!.0
    } else {
        clientTransRecord = tup!.1
    }
    tup = tcpStateTransferAsServer[serverConn.state]
    if tup == nil {
        assert(Logger.lowLevelDebug("unable to find serverTransRecord with state \(clientConn.state)"))
    } else if isFromClient {
        serverTransRecord = tup!.0
    } else {
        serverTransRecord = tup!.1
    }

    var clientNewState: ConnState?
    var serverNewState: ConnState?

    if let clientTransRecord {
        clientNewState = clientTransRecord[flag]
        if clientNewState == nil {
            assert(Logger.lowLevelDebug("unable to find client new state with old=\(clientConn.state) isclient=\(isFromClient) and flag=\(flag)"))
        }
    }
    if let serverTransRecord {
        serverNewState = serverTransRecord[flag]
        if serverNewState == nil {
            assert(Logger.lowLevelDebug("unable to find client new state with old=\(serverConn.state) isclient=\(isFromClient) and flag=\(flag)"))
        }
    }

    if let clientNewState {
        assert(Logger.lowLevelDebug("clientState changed \(clientConn.state) -> \(flag)|from=\(isFromClient ? "client" : "server") -> \(clientNewState)"))
        clientConn.state = clientNewState
    }
    if let serverNewState {
        assert(Logger.lowLevelDebug("serverState changed \(serverConn.state) -> \(flag)|from=\(isFromClient ? "client" : "server") -> \(serverNewState)"))
        serverConn.state = serverNewState
    }
}
