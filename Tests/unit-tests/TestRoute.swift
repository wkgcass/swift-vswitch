import SwiftVSwitch
import Testing
import VProxyCommon

struct TestRoute {
    @Test func v4route() {
        let v4route = RouteTable()!
        let iface1Ex = IfaceEx(DummyIface(), toBridge: 1)
        let iface2Ex = IfaceEx(DummyIface(), toBridge: 2)
        v4route.addRule(RouteTable.RouteRule(rule: GetNetwork(from: "192.168.3.0/24")!, dev: iface1Ex,
                                             src: GetIP(from: "192.168.3.254")!))
        v4route.addRule(RouteTable.RouteRule(rule: GetNetwork(from: "192.168.4.0/24")!, dev: iface2Ex,
                                             src: GetIP(from: "192.168.4.254")!))

        let notFound = v4route.lookup(ip: GetIP(from: "192.168.1.1"))
        #expect(notFound == nil)
        let rule1 = v4route.lookup(ip: GetIP(from: "192.168.3.1"))
        #expect(rule1 != nil)
        #expect(rule1!.dev.toBridge == 1)
        let rule2 = v4route.lookup(ip: GetIP(from: "192.168.4.1"))
        #expect(rule2 != nil)
        #expect(rule2!.dev.toBridge == 2)

        v4route.delRule(GetNetwork(from: "192.168.3.0/24")!)
        let ruleRm = v4route.lookup(ip: GetIP(from: "192.168.3.1"))
        #expect(ruleRm == nil)
    }

    @Test func v6route() {
        let v6route = RouteTable()!
        let iface1Ex = IfaceEx(DummyIface(), toBridge: 1)
        let iface2Ex = IfaceEx(DummyIface(), toBridge: 2)
        v6route.addRule(RouteTable.RouteRule(rule: GetNetwork(from: "fd00::a:3:0/112")!, dev: iface1Ex,
                                             src: GetIP(from: "fd00::a:3:fe")!))
        v6route.addRule(RouteTable.RouteRule(rule: GetNetwork(from: "fd00::a:4:0/112")!, dev: iface2Ex,
                                             src: GetIP(from: "fd00::a:4:fe")!))

        let notFound = v6route.lookup(ip: GetIP(from: "fd00::a:1:1"))
        #expect(notFound == nil)
        let rule1 = v6route.lookup(ip: GetIP(from: "fd00::a:3:1"))
        #expect(rule1 != nil)
        #expect(rule1!.dev.toBridge == 1)
        let rule2 = v6route.lookup(ip: GetIP(from: "fd00::a:4:1"))
        #expect(rule2 != nil)
        #expect(rule2!.dev.toBridge == 2)

        v6route.delRule(GetNetwork(from: "fd00::a:3:0/112")!)
        let ruleRm = v6route.lookup(ip: GetIP(from: "fd00::a:3:1"))
        #expect(ruleRm == nil)
    }
}
