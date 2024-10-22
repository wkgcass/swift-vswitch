#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import SwiftEventLoopCommon
import SwiftEventLoopPosix
import Testing
import VProxyCommon

struct TestUDP {
    init() {
        PosixFDs.setup()
    }

    @Test func testUdp() throws {
        let selector = try FDProvider.get().openSelector()

        let listenUdp = try FDProvider.get().openIPv6Udp()
        try listenUdp.setOption(BuiltInSocketOptions.SO_REUSEPORT, true)
        listenUdp.configureBlocking(false)
        try listenUdp.bind(GetIPPort(from: "[::1]:33445")!)

        let clientUdp = try FDProvider.get().openIPv6Udp()
        clientUdp.configureBlocking(false)
        try clientUdp.connect(GetIPPort(from: "[::1]:33445")!)

        try selector.register(listenUdp, ops: EventSet.read(), attachment: nil)
        try selector.register(clientUdp, ops: EventSet.write(), attachment: nil)

        var selectedEntry: [SelectedEntry] = Arrays.newArray(capacity: 16)
        var buf: [UInt8] = Arrays.newArray(capacity: 1024)
        var clientIsSent = false

        var receivedData = [String](repeating: "", count: 0)

        while true {
            if receivedData.contains("h") {
                break
            }
            let n = try selector.select(&selectedEntry)
            for i in 0 ... n - 1 {
                let fire = selectedEntry[i]
                if fire.fd.handle() == clientUdp.handle() {
                    if !clientIsSent {
                        selector.modify(clientUdp, ops: EventSet.read())

                        let dataToSend = "hello"
                        memcpy(&buf, dataToSend, dataToSend.count)
                        _ = try clientUdp.write(buf, len: dataToSend.count)
                        clientIsSent = true
                    }
                    let len = try fire.fd.read(buf, len: buf.capacity)

                    if len > 0 {
                        var cchars: [CChar] = Arrays.newArray(capacity: len + 1)
                        memcpy(&cchars, buf, len)
                        cchars[len] = 0
                        receivedData.append(String(cString: &cchars))
                    }

                    if len <= 1 {
                        continue
                    }
                    _ = try fire.fd.write(buf, len: len - 1)
                    #expect((fire.fd as! any UdpFD).remoteAddress.description == "[::1]:33445")
                } else {
                    let (len, addr) = try (fire.fd as! any UdpFD).recv(buf, len: buf.capacity)
                    if addr == nil {
                        continue
                    }
                    #expect(addr!.description.starts(with: "[::1]:"))
                    #expect((fire.fd as! any UdpFD).localAddress.description == "[::1]:33445")

                    if len > 0 {
                        var cchars: [CChar] = Arrays.newArray(capacity: len + 1)
                        memcpy(&cchars, buf, len)
                        cchars[len] = 0
                        receivedData.append(String(cString: &cchars))
                    }

                    if len <= 1 {
                        continue
                    }
                    _ = try (fire.fd as! any UdpFD).send(buf, len: len - 1, remote: addr!)
                }
            }
        }
        #expect(receivedData == ["hello", "hell", "hel", "he", "h"])
        _ = selector.remove(listenUdp)
        _ = selector.remove(clientUdp)
        clientUdp.close()
        listenUdp.close()
        selector.close()
    }
}
