import SwiftEventLoopCommon
import SwiftVSwitchCHelper
import VProxyCommon

public class NetStack {
    public let id: UInt32
    private let loop: SelectorEventLoop
    private let params: VSwitchParams

    public let ips: IPManager
    public let arpTable: ArpTable
    public let routeTable: RouteTable
    public let conntrack: Conntrack
    public let ipvs: IPVS

    init(id: UInt32, sw: VSwitchPerThread, params: VSwitchParams, shared: NetStackShared) {
        self.id = id
        loop = sw.loop
        self.params = params
        ips = IPManager()
        arpTable = ArpTable(loop: loop, params: params)
        routeTable = RouteTable()!
        conntrack = Conntrack(sw: sw, global: shared.globalConntrack)
        ipvs = IPVS()
    }

    public func release() {
        arpTable.release()
    }

    // ======== helpers ========

    public func buildNeighborLookup(_ targetIp: any IP, _ iface: IfaceEx) -> PacketBuffer? {
        assert(Logger.lowLevelDebug("trying to build neighbor lookup: target=\(targetIp), iface=\(iface.name)"))

        if let v4 = targetIp as? IPv4 {
            guard let v4ips = ips.dev2ipv4[iface.handle()] else {
                assert(Logger.lowLevelDebug("no source ip for neighbor lookup: \(targetIp) \(iface.name)"))
                return nil
            }
            let src = v4ips.first!
            let buf = RawBufRef()
            let raw = buf.raw().advanced(by: VSwitchReservedHeadroom)
            let p: UnsafeMutablePointer<swvs_compose_eth_arp> = Unsafe.ptr2mutUnsafe(raw)
            iface.mac.copyInto(&p.pointee.ethhdr.src)
            MacAddress.BROADCAST.copyInto(&p.pointee.ethhdr.dst)
            p.pointee.ethhdr.be_type = BE_ETHER_TYPE_ARP
            p.pointee.arp.be_arp_hardware = BE_ARP_HARDWARE_TYPE_ETHER
            p.pointee.arp.be_arp_protocol = BE_ARP_PROTOCOL_TYPE_IP
            p.pointee.arp.arp_hlen = 6
            p.pointee.arp.arp_plen = 4
            p.pointee.arp.be_arp_opcode = BE_ARP_PROTOCOL_OPCODE_REQ
            iface.mac.copyInto(&p.pointee.arp.arp_sha)
            src.ipv4.copyInto(&p.pointee.arp.arp_sip)
            v4.copyInto(&p.pointee.arp.arp_tip)

            return PacketBuffer(
                buf: buf,
                pktlen: MemoryLayout<swvs_compose_eth_arp>.stride,
                headroom: VSwitchReservedHeadroom,
                tailroom: VSwitchDefaultPacketBufferSize - MemoryLayout<swvs_compose_eth_arp>.stride - VSwitchReservedHeadroom
            )
        } else {
            let v6 = targetIp as! IPv6
            guard let v6ips = ips.dev2ipv6[iface.handle()] else {
                assert(Logger.lowLevelDebug("no source ip for neighbor lookup: \(targetIp) \(iface.name)"))
                return nil
            }
            let src = v6ips.first!
            let buf = RawBufRef()
            let raw = buf.raw().advanced(by: VSwitchReservedHeadroom)
            let p: UnsafeMutablePointer<swvs_compose_eth_ip6_icmp6_ns_slla> = Unsafe.ptr2mutUnsafe(raw)
            iface.mac.copyInto(&p.pointee.ethhdr.src)
            MacAddress.BROADCAST.copyInto(&p.pointee.ethhdr.dst)
            p.pointee.ethhdr.be_type = BE_ETHER_TYPE_IPv6
            p.pointee.v6.vtc_flow.0 = 6 << 4
            p.pointee.v6.be_payload_len = Utils.byteOrderConvert(
                UInt16(MemoryLayout<swvs_compose_eth_ip6_icmp6_ns_slla>.stride -
                    MemoryLayout<swvs_ethhdr>.stride -
                    MemoryLayout<swvs_ipv6hdr>.stride))
            p.pointee.v6.next_hdr = IP_PROTOCOL_ICMPv6
            p.pointee.v6.hop_limits = 255
            src.ipv6.copyInto(&p.pointee.v6.src)
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

public struct NetStackShared {
    public let globalConntrack: GlobalConntrack
}
