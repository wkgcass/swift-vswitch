import Testing
import VProxyCommon

struct TestIP {
    @Test func ipv4() {
        let ip = GetIP(from: "192.168.1.2")
        #expect(ip != nil)
        if let v4 = ip! as? IPv4 {
            #expect(v4.bytes.0 == 192)
            #expect(v4.bytes.1 == 168)
            #expect(v4.bytes.2 == 1)
            #expect(v4.bytes.3 == 2)
            #expect(v4.description == "192.168.1.2")
        } else {
            Issue.record("192.168.1.2 should be ipv4")
        }
    }

    @Test func ipv6() {
        let ip = GetIP(from: "2001:0:130F::9C0:876A:130B")
        #expect(ip != nil)
        if let v6 = ip! as? IPv6 {
            #expect(v6.description == "2001:0:130f::9c0:876a:130b")
        } else {
            Issue.record("2001:0:130F::9C0:876A:130B should be ipv6")
        }
    }

    @Test func ipv4Port() {
        let ipport = GetIPPort(from: "192.168.1.2:8080")
        #expect(ipport != nil)
        if let ipv4port = ipport! as? IPv4Port {
            #expect(ipv4port.description == "192.168.1.2:8080")
        } else {
            Issue.record("192.168.1.2:8080 should be ipv4:port")
        }
    }

    @Test func ipv6Port() {
        let ipport = GetIPPort(from: "2001:0:130F::9C0:876A:130B:8080")
        #expect(ipport != nil)
        if let ipv6port = ipport! as? IPv6Port {
            #expect(ipv6port.description == "[2001:0:130f::9c0:876a:130b]:8080")
        } else {
            Issue.record("[2001:0:130f::9c0:876a:130b]:8080 should be ipv6:port")
        }
    }

    @Test func structLen() {
        #expect(MemoryLayout<IPv4>.size == 4)
        #expect(MemoryLayout<IPv4>.stride == 4)
        #expect(MemoryLayout<IPv4>.alignment == 1)

        #expect(MemoryLayout<IPv6>.size == 16)
        #expect(MemoryLayout<IPv6>.stride == 16)
        #expect(MemoryLayout<IPv6>.alignment == 1)
    }

    @Test func equal() {
        let ip41 = IPv4(from: "1.2.3.4")!
        let ip42 = IPv4(from: "1.2.3.4")!
        #expect(ip41 == ip42)
        let ip43 = IPv4(from: "2.2.3.4")!
        #expect(ip41 != ip43)

        let ip61 = IPv6(from: "fd00::1")!
        let ip62 = IPv6(from: "fd00::1")!
        #expect(ip61 == ip62)
        let ip63 = IPv6(from: "fd00::2")!
        #expect(ip61 != ip63)
    }

    @Test func hashable() {
        var m1 = [IPv4: Int]()
        m1[IPv4(from: "1.2.3.4")!] = 1
        #expect(m1[IPv4(from: "1.2.3.4")!] == 1)

        var m2 = [IPv6: Int]()
        m2[IPv6(from: "fd00::1")!] = 1
        #expect(m2[IPv6(from: "fd00::1")!] == 1)
    }

    @Test func network() {
        let linkLocal = NetworkV6(from: "fe80::/10")!
        #expect(linkLocal.contains(GetIP(from: "fe80::1074:aeff:fea3:eaa2")))
    }

    @Test func ipmask() {
        let ipmaskV4 = GetIPMask(from: "192.168.3.2/24")
        #expect(ipmaskV4 != nil)
        #expect(ipmaskV4!.description == "192.168.3.2/24")
        #expect(ipmaskV4!.network.description == "192.168.3.0/24")

        let ipmaskV6 = GetIPMask(from: "fd00::a:3:2/112")
        #expect(ipmaskV6 != nil)
        #expect(ipmaskV6!.description == "fd00::a:3:2/112")
        #expect(ipmaskV6!.network.description == "fd00::a:3:0/112")
    }
}
