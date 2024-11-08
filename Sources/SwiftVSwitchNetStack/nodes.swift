import SwiftVSwitch
import SwiftVSwitchCHelper
import VProxyCommon

public class NetstackNodeManager: NodeManager {
    public init() {
        super.init(DevInput())
        addNode(EthernetInput())
        addNode(ArpInput())
        addNode(ArpReqInput())
        addNode(IPRoute())
        addNode(IPRouteForward())
        addNode(IP4Input())
        addNode(IP6Input())
        addNode(IcmpInput())
        addNode(PingReqInput())
        addNode(Icmp6Input())
        addNode(NdpNsInput())
        addNode(NdpNaInput())
        addNode(IPRouteOutput())
        addNode(IPRouteLinkOutput())
        addNode(EthernetOutput())
    }
}

class DevInput: SwiftVSwitch.DevInput {
    private var ethernetInput = NodeRef("ethernet-input")
    private var ipRoute = NodeRef("ip-route")

    override public func initGraph(mgr: NodeManager) {
        super.initGraph(mgr: mgr)
        mgr.initRef(&ethernetInput)
        mgr.initRef(&ipRoute)
    }

    override public func schedule0(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        if pkb.dstmac != nil {
            return sched.schedule(pkb, to: ethernetInput)
        } else if pkb.ipDst != nil {
            return sched.schedule(pkb, to: ipRoute)
        } else {
            assert(Logger.lowLevelDebug("not ethernet packet nor ip packet, skipping ..."))
            return sched.schedule(pkb, to: drop)
        }
    }
}

class EthernetInput: Node {
    private var arpInput = NodeRef("arp-input")
    private var ip4Input = NodeRef("ip4-input")
    private var ip6Input = NodeRef("ip6-input")

    init() {
        super.init(name: "ethernet-input")
    }

    override func initGraph(mgr: NodeManager) {
        super.initGraph(mgr: mgr)
        mgr.initRef(&arpInput)
        mgr.initRef(&ip4Input)
        mgr.initRef(&ip6Input)
    }

    override func schedule(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        if pkb.dstmac!.isUnicast() && pkb.inputIface!.mac != pkb.dstmac! {
            assert(Logger.lowLevelDebug("mac mismatch, dstmac=\(pkb.dstmac!), iface=\(pkb.inputIface!.mac)"))
            return sched.schedule(pkb, to: drop)
        }
        if pkb.vlanState == .HAS_VLAN {
            // TODO: handle vlan
            assert(Logger.lowLevelDebug("TODO: handle vlan"))
            return sched.schedule(pkb, to: drop)
        }

        let netstackId = pkb.inputIface!.toNetstack
        let netstack = nodeInit.sw.netstacks[netstackId]
        if netstack == nil {
            assert(Logger.lowLevelDebug("netstack \(netstackId) not found"))
            return sched.schedule(pkb, to: drop)
        }
        pkb.netstack = netstack

        if pkb.ethertype == ETHER_TYPE_ARP {
            return sched.schedule(pkb, to: arpInput)
        } else if pkb.ethertype == ETHER_TYPE_IPv4 {
            return sched.schedule(pkb, to: ip4Input)
        } else if pkb.ethertype == ETHER_TYPE_IPv6 {
            return sched.schedule(pkb, to: ip6Input)
        } else {
            assert(Logger.lowLevelDebug("unknown ether_type \(pkb.ethertype)"))
            return sched.schedule(pkb, to: drop)
        }
    }
}

class ArpInput: Node {
    private var arpReqInput = NodeRef("arp-req-input")

    init() {
        super.init(name: "arp-input")
    }

    override func initGraph(mgr: NodeManager) {
        super.initGraph(mgr: mgr)
        mgr.initRef(&arpReqInput)
    }

    override func schedule(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        guard let raw = pkb.ip else {
            assert(Logger.lowLevelDebug("not valid arp packet"))
            return sched.schedule(pkb, to: drop)
        }
        let arp: UnsafeMutablePointer<swvs_arp> = Convert.ptr2mutUnsafe(raw)
        if arp.pointee.be_arp_opcode == BE_ARP_PROTOCOL_OPCODE_REQ ||
            arp.pointee.be_arp_opcode == BE_ARP_PROTOCOL_OPCODE_RESP
        {
            pkb.netstack!.arpTable.record(mac: pkb.srcmac!, ip: pkb.ipSrc!)
        }

        if arp.pointee.be_arp_opcode == BE_ARP_PROTOCOL_OPCODE_REQ {
            return sched.schedule(pkb, to: arpReqInput)
        } else if arp.pointee.be_arp_opcode == BE_ARP_PROTOCOL_OPCODE_RESP {
            return sched.schedule(pkb, to: stolen) // already recorded
        } else {
            assert(Logger.lowLevelDebug("unknown arp opcode BE(\(arp.pointee.be_arp_opcode)"))
            return sched.schedule(pkb, to: drop)
        }
    }
}

class ArpReqInput: Node {
    private var ethernetOutput = NodeRef("ethernet-output")

    init() {
        super.init(name: "arp-req-input")
    }

    override func initGraph(mgr: NodeManager) {
        super.initGraph(mgr: mgr)
        mgr.initRef(&ethernetOutput)
    }

    override func schedule(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        let ether: UnsafeMutablePointer<swvs_ethhdr> = Convert.ptr2mutUnsafe(pkb.raw)
        let arp: UnsafeMutablePointer<swvs_arp> = Convert.ptr2mutUnsafe(pkb.ip!)
        let target = pkb.ipDst as! IPv4
        let ifaces = pkb.netstack!.ipv4[target]
        guard let ifaces else {
            assert(Logger.lowLevelDebug("ip \(target) not found"))
            return sched.schedule(pkb, to: drop)
        }
        if !ifaces.contains(pkb.inputIface!) {
            assert(Logger.lowLevelDebug("ip \(target) is not on iface \(pkb.inputIface!.name)"))
            return sched.schedule(pkb, to: drop)
        }

        pkb.srcmac!.copyInto(&ether.pointee.dst)

        arp.pointee.be_arp_opcode = BE_ARP_PROTOCOL_OPCODE_RESP
        pkb.inputIface!.mac.copyInto(&arp.pointee.arp_sha)
        target.copyInto(&arp.pointee.arp_sip)
        pkb.srcmac!.copyInto(&arp.pointee.arp_tha)
        pkb.ipSrc!.copyInto(&arp.pointee.arp_tip)

        pkb.calcPacketInfo()
        pkb.outputIface = pkb.inputIface
        return sched.schedule(pkb, to: ethernetOutput)
    }
}

class IPRoute: Node {
    private var ip4Input = NodeRef("ip4-input")
    private var ip6Input = NodeRef("ip6-input")
    private var ipRouteForward = NodeRef("ip-route-forward")

    init() {
        super.init(name: "ip-route")
    }

    override func initGraph(mgr: NodeManager) {
        super.initGraph(mgr: mgr)
        mgr.initRef(&ip4Input)
        mgr.initRef(&ip6Input)
        mgr.initRef(&ipRouteForward)
    }

    override func schedule(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        if pkb.ip == nil {
            assert(Logger.lowLevelDebug("not valid packet"))
            return sched.schedule(pkb, to: drop)
        }
        if let v4 = pkb.ipDst as? IPv4 {
            if pkb.netstack!.ipv4[v4] != nil {
                return sched.schedule(pkb, to: ip4Input)
            }
        } else {
            let v6 = pkb.ipDst as! IPv6
            if v6.isMulticast() || pkb.netstack!.ipv6[v6] != nil {
                return sched.schedule(pkb, to: ip6Input)
            }
        }
        let r = pkb.netstack!.routeTable.lookup(ip: pkb.ipDst)
        guard let r else {
            assert(Logger.lowLevelDebug("no ip and no route found: \(pkb.ipDst!)"))
            return sched.schedule(pkb, to: drop)
        }
        pkb.outputRouteRule = r
        return sched.schedule(pkb, to: ipRouteForward)
    }
}

class IP4Input: Node {
    private var icmpInput = NodeRef("icmp-input")

    init() {
        super.init(name: "ip4-input")
    }

    override func initGraph(mgr: NodeManager) {
        super.initGraph(mgr: mgr)
        mgr.initRef(&icmpInput)
    }

    override func schedule(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        if pkb.proto == IP_PROTOCOL_ICMP {
            return sched.schedule(pkb, to: icmpInput)
        } else {
            assert(Logger.lowLevelDebug("unknown proto \(pkb.proto) for ipv4"))
            // TODO: tcp and udp
            return sched.schedule(pkb, to: drop)
        }
    }
}

class IcmpInput: Node {
    private var pingReqInput = NodeRef("ping-req-input")

    init() {
        super.init(name: "icmp-input")
    }

    override func initGraph(mgr: NodeManager) {
        super.initGraph(mgr: mgr)
        mgr.initRef(&pingReqInput)
    }

    override func schedule(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        guard let upper = pkb.upper else {
            assert(Logger.lowLevelDebug("not valid icmp"))
            return sched.schedule(pkb, to: drop)
        }
        let icmp: UnsafePointer<swvs_icmp_hdr> = Convert.ptr2ptrUnsafe(upper)
        if icmp.pointee.type == ICMP_PROTOCOL_TYPE_ECHO_REQ {
            return sched.schedule(pkb, to: pingReqInput)
        } else {
            // TODO: handle other icmp types
            return sched.schedule(pkb, to: drop)
        }
    }
}

class PingReqInput: Node {
    private var ipRouteOutput = NodeRef("ip-route-output")

    init() {
        super.init(name: "ping-req-input")
    }

    override func initGraph(mgr: NodeManager) {
        super.initGraph(mgr: mgr)
        mgr.initRef(&ipRouteOutput)
    }

    override func schedule(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        let icmp: UnsafeMutablePointer<swvs_icmp_hdr> = Convert.ptr2mutUnsafe(pkb.upper!)
        if icmp.pointee.code != 0 {
            assert(Logger.lowLevelDebug("icmp req (ping) code is not 0"))
            return sched.schedule(pkb, to: drop)
        }

        if pkb.ipDst is IPv4 {
            let ip: UnsafeMutablePointer<swvs_ipv4hdr> = Convert.ptr2mutUnsafe(pkb.ip!)
            pkb.ipSrc!.copyInto(&ip.pointee.dst)
            pkb.ipDst!.copyInto(&ip.pointee.src)
            icmp.pointee.type = ICMP_PROTOCOL_TYPE_ECHO_RESP
        } else {
            let ip: UnsafeMutablePointer<swvs_ipv6hdr> = Convert.ptr2mutUnsafe(pkb.ip!)
            pkb.ipSrc!.copyInto(&ip.pointee.dst)
            pkb.ipDst!.copyInto(&ip.pointee.src)
            icmp.pointee.type = ICMPv6_PROTOCOL_TYPE_ECHO_RESP
        }

        pkb.calcPacketInfo()
        return sched.schedule(pkb, to: ipRouteOutput)
    }
}

class IP6Input: Node {
    private var icmp6Input = NodeRef("icmp6-input")

    init() {
        super.init(name: "ip6-input")
    }

    override func initGraph(mgr: NodeManager) {
        super.initGraph(mgr: mgr)
        mgr.initRef(&icmp6Input)
    }

    override func schedule(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        if pkb.ip == nil {
            assert(Logger.lowLevelDebug("not valid ipv6 packet"))
            return sched.schedule(pkb, to: drop)
        }

        if pkb.proto == IP_PROTOCOL_ICMPv6 {
            return sched.schedule(pkb, to: icmp6Input)
        } else {
            assert(Logger.lowLevelDebug("unknown proto \(pkb.proto) for ipv6"))
            // TODO: tcp and udp
            return sched.schedule(pkb, to: drop)
        }
    }
}

class Icmp6Input: Node {
    private var pingReqInput = NodeRef("ping-req-input")
    private var ndpNsInput = NodeRef("ndp-ns-input")
    private var ndpNaInput = NodeRef("ndp-na-input")

    init() {
        super.init(name: "icmp6-input")
    }

    override func initGraph(mgr: NodeManager) {
        super.initGraph(mgr: mgr)
        mgr.initRef(&pingReqInput)
        mgr.initRef(&ndpNsInput)
        mgr.initRef(&ndpNaInput)
    }

    override func schedule(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        guard let upper = pkb.upper else {
            assert(Logger.lowLevelDebug("not valid icmp6 packet"))
            return sched.schedule(pkb, to: drop)
        }

        let icmp6: UnsafeMutablePointer<swvs_icmp_hdr> = Convert.ptr2mutUnsafe(upper)
        if icmp6.pointee.type == ICMPv6_PROTOCOL_TYPE_ECHO_REQ {
            return sched.schedule(pkb, to: pingReqInput)
        } else if icmp6.pointee.type == ICMPv6_PROTOCOL_TYPE_Neighbor_Solicitation {
            return sched.schedule(pkb, to: ndpNsInput)
        } else if icmp6.pointee.type == ICMPv6_PROTOCOL_TYPE_Neighbor_Advertisement {
            return sched.schedule(pkb, to: ndpNaInput)
        } else {
            // TODO: handle other icmpv6 types
            return sched.schedule(pkb, to: drop)
        }
    }
}

class NdpNsInput: Node {
    private var ethernetOutput = NodeRef("ethernet-output")

    init() {
        super.init(name: "ndp-ns-input")
    }

    override func initGraph(mgr: NodeManager) {
        super.initGraph(mgr: mgr)
        mgr.initRef(&ethernetOutput)
    }

    override func schedule(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        if pkb.inputIface!.meta.property.layer != .ETHER {
            assert(Logger.lowLevelDebug("ndp not supported on non-ether iface \(pkb.inputIface!.name)"))
            return sched.schedule(pkb, to: drop)
        }

        guard let icmp: UnsafeMutablePointer<swvs_compose_icmpv6_ns> = pkb.getAs(pkb.upper!) else {
            assert(Logger.lowLevelDebug("not valid ndp ns packet"))
            return sched.schedule(pkb, to: drop)
        }
        if icmp.pointee.icmp.code != 0 {
            assert(Logger.lowLevelDebug("icmpv6 neighbor solicitation code is not 0"))
            return sched.schedule(pkb, to: drop)
        }
        let target = IPv6(raw: &icmp.pointee.target)
        let ifaces = pkb.netstack!.ipv6[target]
        guard let ifaces else {
            assert(Logger.lowLevelDebug("target ip \(target) is not found"))
            return sched.schedule(pkb, to: drop)
        }
        if !ifaces.contains(pkb.inputIface!) {
            assert(Logger.lowLevelDebug("ip \(target) is not on dev \(pkb.inputIface!.name)"))
            return sched.schedule(pkb, to: drop)
        }

        var opt: UnsafeMutablePointer<swvs_icmp_ndp_opt>? = pkb.getAs(icmp.advanced(by: 1))
        var slla: UnsafeMutablePointer<swvs_icmp_ndp_opt_link_layer_addr>? = nil
        while true {
            guard let opt2 = opt else {
                break
            }
            if opt2.pointee.type != ICMPv6_OPTION_TYPE_Source_Link_Layer_Address {
                assert(Logger.lowLevelDebug("opt type is not source-link-layer-address"))

                let inc = Int(opt2.pointee.len) * 8
                if inc == 0 {
                    assert(Logger.lowLevelDebug("invalid icmpv6 opt length"))
                    break
                }
                opt = pkb.getAs(Convert.advance(mut: opt2, inc: inc))
                continue
            }
            if opt2.pointee.len != 1 {
                assert(Logger.lowLevelDebug("opt len is not 1 (1*8 == 2+6)"))
                break
            }
            slla = pkb.getAs(opt2)
            if slla == nil {
                assert(Logger.lowLevelDebug("no enough room for source-link-layer-address option"))
            }
            break
        }
        guard let slla else {
            assert(Logger.lowLevelDebug("source-link-layer-address option not found"))
            return sched.schedule(pkb, to: drop)
        }

        let srcmacInOpt = MacAddress(raw: &slla.pointee.addr)
        if pkb.srcmac != srcmacInOpt {
            assert(Logger.lowLevelDebug("srcmac is not the same as specified in source-link-layer-address option"))
            return sched.schedule(pkb, to: drop)
        }

        assert(Logger.lowLevelDebug("begin to handle the icmpv6 ndp-ns ..."))
        pkb.netstack!.arpTable.record(mac: srcmacInOpt, ip: pkb.ipSrc!)

        let ether: UnsafeMutablePointer<swvs_ethhdr> = Convert.ptr2mutUnsafe(pkb.raw)

        pkb.srcmac!.copyInto(&ether.pointee.dst)

        let ip: UnsafeMutablePointer<swvs_ipv6hdr> = Convert.ptr2mutUnsafe(pkb.ip!)
        pkb.ipSrc!.copyInto(&ip.pointee.dst)
        target.copyInto(&ip.pointee.src)

        let icmpRes: UnsafeMutablePointer<swvs_compose_icmpv6_na_tlla> = Convert.ptr2mutUnsafe(icmp)
        icmpRes.pointee.icmp.type = ICMPv6_PROTOCOL_TYPE_Neighbor_Advertisement
        icmpRes.pointee.icmp.code = 0
        icmpRes.pointee.opt.type = ICMPv6_OPTION_TYPE_Target_Link_Layer_Address
        icmpRes.pointee.opt.len = 1 // 1 * 8 = 8
        icmpRes.pointee.flags = 0b0110_0000
        target.copyInto(&icmpRes.pointee.target)
        pkb.inputIface!.mac.copyInto(&icmpRes.pointee.opt.addr)

        let lenDelta = pkb.lengthFromUpperToEnd - MemoryLayout<swvs_compose_icmpv6_na_tlla>.stride
        if lenDelta == 0 {
            assert(Logger.lowLevelDebug("no need to shrink packet total length"))
        } else {
            assert(Logger.lowLevelDebug("need to shrink packet total length: \(lenDelta)"))
        }
        ip.pointee.be_payload_len = Convert.reverseByteOrder(Convert.reverseByteOrder(
            ip.pointee.be_payload_len - UInt16(lenDelta)))

        pkb.calcPacketInfo()
        pkb.outputIface = pkb.inputIface
        return sched.schedule(pkb, to: ethernetOutput)
    }
}

class NdpNaInput: Node {
    init() {
        super.init(name: "ndp-na-input")
    }

    override func schedule(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        if pkb.inputIface!.meta.property.layer != .ETHER {
            assert(Logger.lowLevelDebug("ndp not supported on non-ether iface \(pkb.inputIface!.name)"))
            return sched.schedule(pkb, to: drop)
        }

        guard let icmp: UnsafeMutablePointer<swvs_compose_icmpv6_ns> = pkb.getAs(pkb.upper!) else {
            assert(Logger.lowLevelDebug("not valid ndp na packet"))
            return sched.schedule(pkb, to: drop)
        }
        if icmp.pointee.icmp.code != 0 {
            assert(Logger.lowLevelDebug("icmpv6 neighbor advertisement code is not 0"))
            return sched.schedule(pkb, to: drop)
        }
        let target = IPv6(raw: &icmp.pointee.target)

        var opt: UnsafeMutablePointer<swvs_icmp_ndp_opt>? = pkb.getAs(icmp.advanced(by: 1))
        var tlla: UnsafeMutablePointer<swvs_icmp_ndp_opt_link_layer_addr>? = nil
        while true {
            guard let opt2 = opt else {
                break
            }
            if opt2.pointee.type != ICMPv6_OPTION_TYPE_Target_Link_Layer_Address {
                assert(Logger.lowLevelDebug("opt type is not target-link-layer-address"))

                let inc = Int(opt2.pointee.len) * 8
                if inc == 0 {
                    assert(Logger.lowLevelDebug("invalid icmpv6 opt length"))
                    break
                }
                opt = pkb.getAs(Convert.advance(mut: opt2, inc: inc))
                continue
            }
            if opt2.pointee.len != 1 {
                assert(Logger.lowLevelDebug("opt len is not 1 (1*8 == 2+6)"))
                break
            }
            tlla = pkb.getAs(opt2)
            if tlla == nil {
                assert(Logger.lowLevelDebug("no enough room for target-link-layer-address option"))
            }
            break
        }
        guard let tlla else {
            assert(Logger.lowLevelDebug("target-link-layer-address option not found"))
            return sched.schedule(pkb, to: drop)
        }

        let srcmacInOpt = MacAddress(raw: &tlla.pointee.addr)
        if pkb.srcmac != srcmacInOpt {
            assert(Logger.lowLevelDebug("srcmac is not the same as specified in target-link-layer-address option"))
            return sched.schedule(pkb, to: drop)
        }

        assert(Logger.lowLevelDebug("begin to handle the icmpv6 ndp-na ..."))
        pkb.netstack!.arpTable.record(mac: srcmacInOpt, ip: target)
        pkb.netstack!.arpTable.record(mac: srcmacInOpt, ip: pkb.ipSrc!)

        return sched.schedule(pkb, to: stolen)
    }
}

class IPRouteOutput: Node {
    private var ipRouteLinkOuput = NodeRef("ip-route-link-output")

    init() {
        super.init(name: "ip-route-output")
    }

    override func initGraph(mgr: NodeManager) {
        super.initGraph(mgr: mgr)
        mgr.initRef(&ipRouteLinkOuput)
    }

    override func schedule(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        guard let r = pkb.netstack!.routeTable.lookup(ip: pkb.ipDst) else {
            assert(Logger.lowLevelDebug("unable to find route to \(pkb.ipDst!)"))
            return sched.schedule(pkb, to: drop)
        }
        pkb.outputRouteRule = r
        return sched.schedule(pkb, to: ipRouteLinkOuput)
    }
}

class IPRouteForward: Node {
    private var ipRouteLinkOutput = NodeRef("ip-route-link-output")

    init() {
        super.init(name: "ip-route-forward")
    }

    override func initGraph(mgr: NodeManager) {
        super.initGraph(mgr: mgr)
        mgr.initRef(&ipRouteLinkOutput)
    }

    override func schedule(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        assert(pkb.outputRouteRule != nil)
        if pkb.ethertype == ETHER_TYPE_IPv4 {
            let ip: UnsafeMutablePointer<swvs_ipv4hdr> = Convert.ptr2mutUnsafe(pkb.ip!)
            if ip.pointee.time_to_live <= 1 {
                assert(Logger.lowLevelDebug("received TTL <= 1 packet: \(pkb)"))
                return sched.schedule(pkb, to: drop)
            }
            ip.pointee.time_to_live -= 1
        } else {
            assert(pkb.ethertype == ETHER_TYPE_IPv6)
            let ip: UnsafeMutablePointer<swvs_ipv6hdr> = Convert.ptr2mutUnsafe(pkb.ip!)
            if ip.pointee.hop_limits <= 1 {
                assert(Logger.lowLevelDebug("received TTL <= 1 packet: \(pkb)"))
                return sched.schedule(pkb, to: drop)
            }
            ip.pointee.hop_limits -= 1
        }
        return sched.schedule(pkb, to: ipRouteLinkOutput)
    }
}

class IPRouteLinkOutput: Node {
    private var devOutput = NodeRef("dev-output")
    private var ethernetOutput = NodeRef("ethernet-output")

    init() {
        super.init(name: "ip-route-link-output")
    }

    override func initGraph(mgr: NodeManager) {
        super.initGraph(mgr: mgr)
        mgr.initRef(&devOutput)
        mgr.initRef(&ethernetOutput)
    }

    override func schedule(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        assert(pkb.outputRouteRule != nil)
        let r = pkb.outputRouteRule!

        let outputIface = r.dev
        if outputIface.meta.property.layer == .IP {
            pkb.outputIface = outputIface
            return sched.schedule(pkb, to: devOutput)
        }
        assert(outputIface.meta.property.layer == .ETHER)

        let lookupMacByIp: any IP
        if r.gateway == nil {
            lookupMacByIp = pkb.ipDst!
        } else {
            lookupMacByIp = r.gateway!
        }

        let mac = pkb.netstack!.arpTable.lookup(ip: lookupMacByIp)
        if let mac {
            assert(Logger.lowLevelDebug("mac for \(lookupMacByIp) already exists: \(mac)"))

            let ether: UnsafeMutablePointer<swvs_ethhdr> = Convert.ptr2mutUnsafe(pkb.raw)
            mac.copyInto(&ether.pointee.dst)
            pkb.outputIface = outputIface
            return sched.schedule(pkb, to: ethernetOutput)
        }

        assert(Logger.lowLevelDebug("need to find mac for ip \(lookupMacByIp)"))
        let newPkb = pkb.netstack!.buildNeighborLookup(lookupMacByIp, r.dev)
        guard let newPkb else {
            return sched.schedule(pkb, to: drop)
        }
        newPkb.outputIface = r.dev
        newPkb.useOwned = true
        return sched.schedule(newPkb, to: ethernetOutput)
    }
}

class EthernetOutput: Node {
    private var devOutput = NodeRef("dev-output")

    init() {
        super.init(name: "ethernet-output")
    }

    override func initGraph(mgr: NodeManager) {
        super.initGraph(mgr: mgr)
        mgr.initRef(&devOutput)
    }

    override func schedule(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        assert(pkb.outputIface != nil)
        let ether: UnsafeMutablePointer<swvs_ethhdr> = Convert.ptr2mutUnsafe(pkb.raw)
        pkb.outputIface!.mac.copyInto(&ether.pointee.src)

        pkb.clearPacketInfo()
        return sched.schedule(pkb, to: devOutput)
    }
}
