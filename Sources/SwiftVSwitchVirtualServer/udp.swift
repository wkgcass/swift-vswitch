import SwiftVSwitch

public func udpStateTransfer(clientConn: Connection, serverConn: Connection, isFromClient: Bool) {
    if clientConn.state == .UDP_ESTABLISHED {
        return
    }
    if clientConn.state == .NONE {
        clientConn.state = .UDP_ONE_WAY
        serverConn.state = .UDP_ONE_WAY
    }
    if !isFromClient {
        clientConn.state = .UDP_ESTABLISHED
        serverConn.state = .UDP_ESTABLISHED
    }
}
