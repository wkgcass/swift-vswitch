import SwiftEventLoopCommon
import SwiftVSwitchCHelper
import SwiftVSwitchVirtualServerBase
import VProxyCommon

public class NetStack {
    private let loop: SelectorEventLoop
    private let params: VSwitchParams

    public let arpTable: ArpTable
    public let routeTable: RouteTable
    public let conntrack: Conntrack
    public let ipvs: IPVS
    public private(set) var ipv4 = [IPv4: Set<IfaceEx>]()
    public private(set) var ipv6 = [IPv6: Set<IfaceEx>]()
    public private(set) var dev2ipv4 = [IfaceHandle: Set<IPv4>]()
    public private(set) var dev2ipv6 = [IfaceHandle: Set<IPv6>]()

    init(loop: SelectorEventLoop, params: VSwitchParams) {
        self.loop = loop
        self.params = params
        arpTable = ArpTable(loop: loop, params: params)
        routeTable = RouteTable()!
        conntrack = Conntrack()
        ipvs = IPVS()
    }

    public func addIp(_ ip: (any IP)?, dev: IfaceEx) {
        if let v4 = ip as? IPv4 {
            if !ipv4.keys.contains(v4) {
                ipv4[v4] = Set()
            }
            ipv4[v4]!.insert(dev)

            if !dev2ipv4.keys.contains(dev.iface.handle()) {
                dev2ipv4[dev.iface.handle()] = Set()
            }
            dev2ipv4[dev.iface.handle()]!.insert(v4)
        } else if let v6 = ip as? IPv6 {
            if !ipv6.keys.contains(v6) {
                ipv6[v6] = Set()
            }
            ipv6[v6]!.insert(dev)

            if !dev2ipv6.keys.contains(dev.iface.handle()) {
                dev2ipv6[dev.iface.handle()] = Set()
            }
            dev2ipv6[dev.iface.handle()]!.insert(v6)
        }
    }

    public func removeIp(_ ip: (any IP)?, dev: IfaceEx) {
        if let v4 = ip as? IPv4 {
            if ipv4.keys.contains(v4) {
                ipv4[v4]!.remove(dev)
                if ipv4[v4]!.isEmpty {
                    ipv4.removeValue(forKey: v4)
                }
            }
            if dev2ipv4.keys.contains(dev.handle()) {
                dev2ipv4[dev.handle()]!.remove(v4)
                if dev2ipv4[dev.handle()]!.isEmpty {
                    dev2ipv4.removeValue(forKey: dev.handle())
                }
            }
        } else if let v6 = ip as? IPv6 {
            if ipv6.keys.contains(v6) {
                ipv6[v6]!.remove(dev)
                if ipv6[v6]!.isEmpty {
                    ipv6.removeValue(forKey: v6)
                }
            }
            if dev2ipv6.keys.contains(dev.handle()) {
                dev2ipv6[dev.handle()]!.remove(v6)
                if dev2ipv6[dev.handle()]!.isEmpty {
                    dev2ipv6.removeValue(forKey: dev.handle())
                }
            }
        }
    }

    public func release() {
        arpTable.release()
        ipv4.removeAll()
        ipv6.removeAll()
    }

    // ======== helpers ========

    public func buildNeighborLookup(_ targetIp: any IP, _ iface: IfaceEx) -> PacketBuffer? {
        assert(Logger.lowLevelDebug("trying to build neighbor lookup: target=\(targetIp), iface=\(iface.name)"))

        if let v4 = targetIp as? IPv4 {
            guard let v4ips = dev2ipv4[iface.handle()] else {
                assert(Logger.lowLevelDebug("no source ip for neighbor lookup: \(targetIp) \(iface.name)"))
                return nil
            }
            let src = v4ips.first!
            let buf = RawBufRef()
            let raw = buf.raw().advanced(by: VSwitchReservedHeadroom)
            let p: UnsafeMutablePointer<swvs_compose_eth_arp> = Convert.ptr2mutUnsafe(raw)
            iface.mac.copyInto(&p.pointee.ethhdr.src)
            MacAddress.BROADCAST.copyInto(&p.pointee.ethhdr.dst)
            p.pointee.ethhdr.be_type = BE_ETHER_TYPE_ARP
            p.pointee.arp.be_arp_hardware = BE_ARP_HARDWARE_TYPE_ETHER
            p.pointee.arp.be_arp_protocol = BE_ARP_PROTOCOL_TYPE_IP
            p.pointee.arp.arp_hlen = 6
            p.pointee.arp.arp_plen = 4
            p.pointee.arp.be_arp_opcode = BE_ARP_PROTOCOL_OPCODE_REQ
            iface.mac.copyInto(&p.pointee.arp.arp_sha)
            src.copyInto(&p.pointee.arp.arp_sip)
            v4.copyInto(&p.pointee.arp.arp_tip)

            return PacketBuffer(
                buf: buf,
                pktlen: MemoryLayout<swvs_compose_eth_arp>.stride,
                headroom: VSwitchReservedHeadroom,
                tailroom: VSwitchDefaultPacketBufferSize - MemoryLayout<swvs_compose_eth_arp>.stride - VSwitchReservedHeadroom
            )
        } else {
            let v6 = targetIp as! IPv6
            guard let v6ips = dev2ipv6[iface.handle()] else {
                assert(Logger.lowLevelDebug("no source ip for neighbor lookup: \(targetIp) \(iface.name)"))
                return nil
            }
            let src = v6ips.first!
            let buf = RawBufRef()
            let raw = buf.raw().advanced(by: VSwitchReservedHeadroom)
            let p: UnsafeMutablePointer<swvs_compose_eth_ip6_icmp6_ns_slla> = Convert.ptr2mutUnsafe(raw)
            iface.mac.copyInto(&p.pointee.ethhdr.src)
            MacAddress.BROADCAST.copyInto(&p.pointee.ethhdr.dst)
            p.pointee.ethhdr.be_type = BE_ETHER_TYPE_IPv6
            p.pointee.v6.vtc_flow.0 = 6 << 4
            p.pointee.v6.be_payload_len = Convert.reverseByteOrder(
                UInt16(MemoryLayout<swvs_compose_eth_ip6_icmp6_ns_slla>.stride -
                    MemoryLayout<swvs_ethhdr>.stride -
                    MemoryLayout<swvs_ipv6hdr>.stride))
            p.pointee.v6.next_hdr = IP_PROTOCOL_ICMPv6
            p.pointee.v6.hop_limits = 255
            src.copyInto(&p.pointee.v6.src)
            IPv6_Solicitation_Node_Multicast_Address.copyInto(&p.pointee.v6.dst)
            p.pointee.v6.dst.13 = v6.bytes.13
            p.pointee.v6.dst.14 = v6.bytes.14
            p.pointee.v6.dst.15 = v6.bytes.15
            p.pointee.icmp.type = ICMPv6_PROTOCOL_TYPE_Neighbor_Solicitation
            v6.copyInto(&p.pointee.target)
            p.pointee.opt.type = ICMPv6_OPTION_TYPE_Source_Link_Layer_Address
            p.pointee.opt.len = 1
            iface.mac.copyInto(&p.pointee.opt.addr)

            return PacketBuffer(
                buf: buf,
                pktlen: MemoryLayout<swvs_compose_eth_ip6_icmp6_ns_slla>.stride,
                headroom: VSwitchReservedHeadroom,
                tailroom: VSwitchDefaultPacketBufferSize -
                    MemoryLayout<swvs_compose_eth_ip6_icmp6_ns_slla>.stride - VSwitchReservedHeadroom
            )
        }
    }
}
