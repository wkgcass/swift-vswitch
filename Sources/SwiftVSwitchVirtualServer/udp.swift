import SwiftVSwitch

public func udpStateTransfer(clientConn: Connection, serverConn: Connection, isFromClient: Bool) {
    if clientConn.state == .UDP_ESTABLISHED {
        return
    }
    if clientConn.state == .NONE {
        clientConn.state = .UDP_SINGLE_DIR
        serverConn.state = .UDP_SINGLE_DIR
    }
    if !isFromClient {
        clientConn.state = .UDP_ESTABLISHED
        serverConn.state = .UDP_ESTABLISHED
    }
}
