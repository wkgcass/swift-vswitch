import ArgumentParser
import SwiftVSwitch
import SwiftVSwitchClient
import SwiftVSwitchControlData
import VProxyCommon

extension Client {
    func runIpvsadmInNetns(_ id: UInt32, _ argv: ArraySlice<String>) async throws {
        guard let first = argv.first else {
            throw IllegalArgumentException("no further commands provided")
        }
        if first == "-A" || first == "--add-service" {
            // TODO:
            throw IllegalArgumentException("TODO")
        } else if first == "-E" || first == "--edit-service" {
            // TODO:
            throw IllegalArgumentException("TODO")
        } else if first == "-D" || first == "--delete-service" {
            // TODO:
            throw IllegalArgumentException("TODO")
        } else if first == "-a" || first == "--add-server" {
            // TODO:
            throw IllegalArgumentException("TODO")
        } else if first == "-e" || first == "--edit-server" {
            // TODO:
            throw IllegalArgumentException("TODO")
        } else if first == "-d" || first == "--delete-server" {
            // TODO:
            throw IllegalArgumentException("TODO")
        } else if first == "-Z" || first == "--zero" {
            // TODO:
            throw IllegalArgumentException("TODO")
        } else if first.hasPrefix("-l") || first.hasPrefix("-L") {
            let res = try IpvsadmShow.parse([String](argv))
            try await res.run(self, netstack: id)
        } else if first == "-h" || first == "--help" {
            print("""
                [ip netns exec] ns<n> ipvsadm -ln
                [ip netns exec] ns<n> ipvsadm -ln <-t|-u> <vs>
                [ip netns exec] ns<n> ipvsadm -A <-t|-u> <vs> [-s sched]
                [ip netns exec] ns<n> ipvsadm -E <-t|-u> <vs> [-s sched]
                [ip netns exec] ns<n> ipvsadm -D <-t|-u> <vs>
                [ip netns exec] ns<n> ipvsadm -a <-t|-u> <vs> -r <rs> -w <weight> <--fullnat|--masquerading>
                [ip netns exec] ns<n> ipvsadm -e <-t|-u> <vs> -r <rs> [-w <weight>]
                [ip netns exec] ns<n> ipvsadm -d <-t|-u> <vs> -r <rs>
            """)
            return
        } else {
            throw IllegalArgumentException("unknown arguments for ipvsadm: \(argv)")
        }
    }
}

struct IpvsadmShow: AsyncParsableCommand {
    @Flag(name: [.customShort("l"), .customShort("L"), .customLong("list")], help: "list the table") var list = false
    @Flag(name: [.customShort("n"), .customLong("numeric")], help: "numeric output of addresses and ports") var numeric = false
    @Flag(name: [.customShort("c"), .customLong("connection")], help: "output of current IPVS connections") var connection = false
    @Option(name: [.customShort("t"), .customLong("tcp-service")], help: "filter tcp services") var tcp: String?
    @Option(name: [.customShort("u"), .customLong("udp-service")], help: "filter udp services") var udp: String?

    func validate() throws {
        if tcp != nil && udp != nil {
            throw ValidationError("-t and -u must not be specified at the same time")
        }
    }

    func run(_ client: Client, netstack: UInt32) async throws {
        let filter = try formatServiceFilter(tcp, udp)

        if connection {
            let conns = if let filter {
                try await client.client.showIPVSConnectionsOfService(netstack: netstack, filter: filter)
            } else {
                try await client.client.showAllIPVSConnections(netstack: netstack)
            }
            printLncTitle()
            for conn in conns {
                printIPVSConn(conn)
            }
        } else {
            let services = if let filter {
                try await client.client.showIpvsService(netstack: netstack, filter: filter)
            } else {
                try await client.client.showAllIpvsServices(netstack: netstack)
            }
            printLnTitle()
            for svc in services {
                printService(svc)
            }
        }
    }

    func printLncTitle() {
        print("IPVS connection entries")
        print("prot expire state       peer_state  cid peer_cid source                                         virtual                                        local                                          destination")
    }

    func printIPVSConn(_ conn: ConnRef) {
        if !conn.isBeforeNat {
            return
        }
        guard let peer = conn.peer else {
            return
        }
        var s = if conn.proto == IP_PROTOCOL_TCP { "tcp" } else { "udp" }
        if s.count < 4 {
            s += String(repeating: " ", count: 4 - s.count)
        }
        var ttl = (conn.ttl / 1000).description
        ttl += "s"
        s += " \(ttl)"
        if ttl.count < 6 {
            s += String(repeating: " ", count: 6 - ttl.count)
        }
        var state = conn.state
        if state.hasPrefix("TCP_") || state.hasPrefix("UDP_") {
            state = String(state.dropFirst(4))
        }
        s += " \(state)"
        if state.count < 11 {
            s += String(repeating: " ", count: 11 - state.count)
        }
        var peerState = peer.state
        if peerState.hasPrefix("TCP_") || peerState.hasPrefix("UDP_") {
            peerState = String(peerState.dropFirst(4))
        }
        s += " \(peerState)"
        if peerState.count < 11 {
            s += String(repeating: " ", count: 11 - peerState.count)
        }
        let cid = conn.cid.description
        s += " \(cid)"
        if cid.count < 3 {
            s += String(repeating: " ", count: 3 - cid.count)
        }
        let peerCid = peer.cid.description
        s += " \(peerCid)"
        if peerCid.count < 8 {
            s += String(repeating: " ", count: 8 - peerCid.count)
        }

        let src = if GetIP(from: conn.src) is IPv6 {
            "[\(conn.src)]:\(conn.srcPort)"
        } else {
            "\(conn.src):\(conn.srcPort)"
        }
        let virtual = if GetIP(from: conn.dst) is IPv6 {
            "[\(conn.dst)]:\(conn.dstPort)"
        } else {
            "\(conn.dst):\(conn.dstPort)"
        }
        let local = if GetIP(from: peer.dst) is IPv6 {
            "[\(peer.dst)]:\(peer.dstPort)"
        } else {
            "\(peer.dst):\(peer.dstPort)"
        }
        let dest = if GetIP(from: peer.src) is IPv6 {
            "[\(peer.src)]:\(peer.srcPort)"
        } else {
            "\(peer.src):\(peer.srcPort)"
        }
        s += " \(src)"
        if src.count < 46 {
            s += String(repeating: " ", count: 46 - src.count)
        }
        s += " \(virtual)"
        if virtual.count < 46 {
            s += String(repeating: " ", count: 46 - virtual.count)
        }
        s += " \(local)"
        if local.count < 46 {
            s += String(repeating: " ", count: 46 - local.count)
        }
        s += " \(dest)"
        if dest.count < 46 {
            s += String(repeating: " ", count: 46 - dest.count)
        }
        print(s)
    }

    func printLnTitle() {
        print("IP Virtual Server")
        print("Prot LocalAddress:Port Scheduler                              Flags")
        print("  -> RemoteAddress:Port                             Forward Weight ActiveConn InActConn")
    }

    func printServiceLine(_ proto: UInt8, _ vip: String, _ port: UInt16, _ sched: String?) {
        let proto = if proto == IP_PROTOCOL_TCP { "TCP" } else { "UDP" }
        let ipport = if GetIP(from: vip) is IPv6 {
            "[\(vip)]:\(port)"
        } else {
            "\(vip):\(port)"
        }
        let sched = switch sched {
        case "weighted-roundrobin": "wrr"
        case "roundrobin": "rr"
        default: sched
        }

        var s = proto
        if proto.count < 4 {
            s += String(repeating: " ", count: 4 - proto.count)
        }
        s += " \(ipport)"
        guard let sched else {
            print(s)
            return
        }
        s += " \(sched)"
        if "\(ipport) \(sched)".count < 46 + 1 + 9 {
            s += String(repeating: " ", count: 46 + 1 + 9 - "\(ipport) \(sched)".count)
        }
        print(s)
    }

    func printService(_ svc: ServiceRef) {
        printServiceLine(svc.proto, svc.vip, svc.port, svc.sched)
        for dest in svc.dests {
            printDest(dest)
        }
    }

    func printDest(_ dest: DestRef) {
        let ipport = if GetIP(from: dest.ip) is IPv6 {
            "[\(dest.ip)]:\(dest.port)"
        } else {
            "\(dest.ip):\(dest.port)"
        }
        let fwd = switch dest.fwd {
        case "fnat": "FullNat"
        default: dest.fwd
        }
        let weight = dest.weight.description
        let active = dest.statistics.activeConns.description
        let inactive = dest.statistics.inactiveConns.description

        var s = "  -> \(ipport)"
        if ipport.count < 46 {
            s += String(repeating: " ", count: 46 - ipport.count)
        }
        s += " \(fwd)"
        if fwd.count < 7 {
            s += String(repeating: " ", count: 7 - fwd.count)
        }
        s += " \(weight)"
        if weight.count < 6 {
            s += String(repeating: " ", count: 6 - weight.count)
        }
        s += " \(active)"
        if active.count < 10 {
            s += String(repeating: " ", count: 10 - active.count)
        }
        s += " \(inactive)"
        if inactive.count < 9 {
            s += String(repeating: " ", count: 9 - inactive.count)
        }
        print(s)
    }
}

func formatServiceFilter(_ tcp: String?, _ udp: String?) throws -> ServiceFilter? {
    if tcp == nil, udp == nil {
        return nil
    } else if let tcp {
        let ipport = GetIPPort(from: tcp)
        guard let ipport else {
            throw ValidationError("-t \(tcp) is invalid")
        }
        return ServiceFilter(proto: IP_PROTOCOL_TCP, vip: ipport.ip.description, port: ipport.port)
    } else {
        let udp = udp!
        let ipport = GetIPPort(from: udp)
        guard let ipport else {
            throw ValidationError("-u \(udp) is invalid")
        }
        return ServiceFilter(proto: IP_PROTOCOL_TCP, vip: ipport.ip.description, port: ipport.port)
    }
}
