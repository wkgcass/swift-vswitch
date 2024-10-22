import Testing
import VProxyCommon

struct TestIP {
    @Test func testIPv4() {
        let ip = GetIP(from: "192.168.1.2")
        #expect(ip != nil)
        if let v4 = ip! as? IPv4 {
            #expect(v4.bytes[0] == 192)
            #expect(v4.bytes[1] == 168)
            #expect(v4.bytes[2] == 1)
            #expect(v4.bytes[3] == 2)
            #expect(v4.description == "192.168.1.2")
        } else {
            Issue.record("192.168.1.2 should be ipv4")
        }
    }

    @Test func testIPv6() {
        let ip = GetIP(from: "2001:0:130F::9C0:876A:130B")
        #expect(ip != nil)
        if let v6 = ip! as? IPv6 {
            #expect(v6.description == "2001:0:130f::9c0:876a:130b")
        } else {
            Issue.record("2001:0:130F::9C0:876A:130B should be ipv6")
        }
    }

    @Test func testIPv4Port() {
        let ipport = GetIPPort(from: "192.168.1.2:8080")
        #expect(ipport != nil)
        if let ipv4port = ipport! as? IPv4Port {
            #expect(ipv4port.description == "192.168.1.2:8080")
        } else {
            Issue.record("192.168.1.2:8080 should be ipv4:port")
        }
    }

    @Test func testIPv6Port() {
        let ipport = GetIPPort(from: "2001:0:130F::9C0:876A:130B:8080")
        #expect(ipport != nil)
        if let ipv6port = ipport! as? IPv6Port {
            #expect(ipv6port.description == "[2001:0:130f::9c0:876a:130b]:8080")
        } else {
            Issue.record("[2001:0:130f::9c0:876a:130b]:8080 should be ipv6:port")
        }
    }
}
