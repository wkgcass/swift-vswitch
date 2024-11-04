#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import SwiftEventLoopCommon
import SwiftEventLoopPosix
import Testing
import VProxyCommon

struct TestTCP {
    init() {
        PosixFDs.setup()
    }

    @Test func tcp() throws {
        let selector = try FDProvider.get().openSelector()

        let serverFD = try FDProvider.get().openIPv4Tcp()
        serverFD.configureBlocking(false)
        try serverFD.setOption(SockOpts.SO_REUSEPORT, true)
        try serverFD.bind(GetIPPort(from: "127.0.0.1:29944")!)
        try selector.register(serverFD, ops: EventSet.read(), attachment: nil)

        let clientFD = try FDProvider.get().openIPv4Tcp()
        clientFD.configureBlocking(false)
        try clientFD.connect(GetIPPort(from: "127.0.0.1:29944")!)
        try selector.register(clientFD, ops: EventSet.write(), attachment: nil)
        var clientIsConnected = false

        var selectedEntry: [SelectedEntry] = Arrays.newArray(capacity: 16)
        var buf: [UInt8] = Arrays.newArray(capacity: 1024, uninitialized: true)

        var receivedData = [String](repeating: "", count: 0)

        while true {
            if selector.entries().count == 1 {
                // only the listening fd
                break
            }
            let n = try selector.select(&selectedEntry)
            for i in 0 ... n - 1 {
                let fire = selectedEntry[i]
                if fire.fd.handle() == serverFD.handle() {
                    // accept
                    let accepted = try (fire.fd as! any TcpFD).accept()
                    if accepted == nil {
                        continue
                    }
                    let local = accepted!.localAddress
                    #expect(local.description == "127.0.0.1:29944")
                    accepted!.configureBlocking(false)
                    try selector.register(accepted!, ops: EventSet.read(), attachment: nil)
                    continue
                }
                if fire.fd.handle() == clientFD.handle() {
                    if !clientIsConnected {
                        try (fire.fd as! any TcpFD).finishConnect()
                        clientIsConnected = true

                        let remote = (fire.fd as! any TcpFD).remoteAddress
                        #expect(remote.description == "127.0.0.1:29944")

                        selector.modify(fire.fd, ops: EventSet.read())

                        let dataToSend = "hello"
                        memcpy(&buf, dataToSend, dataToSend.count)
                        _ = try (fire.fd as! any TcpFD).write(buf, len: dataToSend.count)
                    }
                }
                if fire.ready.have(.READABLE) {
                    var len = try fire.fd.read(&buf, len: buf.capacity)
                    if len > 0 {
                        var cchars: [CChar] = Arrays.newArray(capacity: len + 1, uninitialized: true)
                        memcpy(&cchars, buf, len)
                        cchars[len] = 0
                        receivedData.append(String(cString: &cchars))
                    }
                    if len <= 1 {
                        _ = selector.remove(fire.fd)
                        fire.fd.close()
                        continue
                    }
                    len -= 1
                    _ = try fire.fd.write(buf, len: len)
                }
            }
        }
        #expect(receivedData == ["hello", "hell", "hel", "he", "h"])
        _ = selector.remove(serverFD)
        serverFD.close()
        selector.close()
    }
}
