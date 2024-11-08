#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import SwiftVSwitchCHelper
import VProxyCommon

public class SimpleHostMimicIface: VirtualIface {
    private var name_: String
    override public var name: String { "simple-host-mimic:\(name_)" }
    public private(set) var ip4 = Set<IPv4>()
    public private(set) var ip6 = Set<IPv6>()

    public init(name: String) {
        name_ = name
        super.init()
    }

    private var packetsToSend: RingBuffer<PacketBuffer> = RingBuffer(capacity: 128)

    override public func dequeue(_ packets: inout [PacketBuffer], off: inout Int) {
        _ = packetsToSend.writeTo { buf, bufoff, buflen in
            var copyLen = packets.count - off
            if copyLen > buflen { copyLen = buflen }
            for i in 0 ..< copyLen {
                packets[off + i] = buf[bufoff + i]
            }
            off += copyLen
            return copyLen
        }
    }

    override public func enqueue(_ pkb: PacketBuffer) -> Bool {
        if packetsToSend.freeSpace() == 0 {
            return false
        }
        guard let ether: UnsafeMutablePointer<swvs_ethhdr> = pkb.getAs(pkb.raw) else {
            return false
        }
        let ifMac = pkb.outputIface!.mac
        pkb.outputIface = nil
        let dstMac = MacAddress(raw: &ether.pointee.dst)
        if dstMac != ifMac && dstMac.isUnicast() {
            assert(Logger.lowLevelDebug("the packet is not for \(name)"))
            return false
        }

        if pkb.ethertype == ETHER_TYPE_ARP {
            assert(Logger.lowLevelDebug("input is arp?"))

            guard let arpRaw = pkb.ip else {
                assert(Logger.lowLevelDebug("not valid arp packet"))
                return false
            }
            if pkb.arpOp != ARP_PROTOCOL_OPCODE_REQ {
                assert(Logger.lowLevelDebug("is not arp req"))
                return false
            }
            let ip = pkb.ipDst as! IPv4
            if !ip4.contains(ip) {
                assert(Logger.lowLevelDebug("target ip \(ip) is not owned by \(name)"))
                return false
            }
            assert(Logger.lowLevelDebug("begin to handle the arp req ..."))

            let arp: UnsafeMutablePointer<swvs_arp> = Convert.ptr2mutUnsafe(arpRaw)

            ifMac.copyInto(&ether.pointee.src)
            pkb.srcmac!.copyInto(&ether.pointee.dst)

            arp.pointee.be_arp_opcode = BE_ARP_PROTOCOL_OPCODE_RESP
            ifMac.copyInto(&arp.pointee.arp_sha)
            ip.copyInto(&arp.pointee.arp_sip)
            pkb.srcmac!.copyInto(&arp.pointee.arp_tha)
            pkb.ipSrc!.copyInto(&arp.pointee.arp_tip)

            pkb.clearPacketInfo(from: .ETHER)
        } else if pkb.ethertype == ETHER_TYPE_IPv4 {
            assert(Logger.lowLevelDebug("input is ipv4?"))

            guard let ipraw = pkb.ip else {
                assert(Logger.lowLevelDebug("not valid ip packet"))
                return false
            }
            if pkb.proto != IP_PROTOCOL_ICMP {
                assert(Logger.lowLevelDebug("is not icmp"))
                return false
            }
            guard let upper = pkb.upper else {
                assert(Logger.lowLevelDebug("not valid icmp"))
                return false
            }
            let icmp: UnsafePointer<swvs_icmp_hdr> = Convert.ptr2ptrUnsafe(upper)
            if icmp.pointee.type != ICMP_PROTOCOL_TYPE_ECHO_REQ {
                assert(Logger.lowLevelDebug("not icmp req (ping)"))
                return false
            }
            if icmp.pointee.code != 0 {
                assert(Logger.lowLevelDebug("icmp req (ping) code is not 0"))
                return false
            }
            assert(Logger.lowLevelDebug("begin to handle the icmp ping ..."))

            let ip: UnsafeMutablePointer<swvs_ipv4hdr> = Convert.ptr2mutUnsafe(ipraw)
            pkb.ipSrc!.copyInto(&ip.pointee.dst)
            pkb.ipDst!.copyInto(&ip.pointee.src)

            let ping: UnsafeMutablePointer<swvs_compose_icmp_echoreq> = Convert.ptr2mutUnsafe(upper)
            ping.pointee.icmp.type = ICMP_PROTOCOL_TYPE_ECHO_RESP

            pkb.srcmac!.copyInto(&ether.pointee.dst)
            ifMac.copyInto(&ether.pointee.src)

            pkb.clearPacketInfo(from: .ETHER)
        } else if pkb.ethertype == ETHER_TYPE_IPv6 {
            assert(Logger.lowLevelDebug("input is ipv6?"))

            guard let ipraw = pkb.ip else {
                assert(Logger.lowLevelDebug("not valid ip packet"))
                return false
            }
            if pkb.proto != IP_PROTOCOL_ICMPv6 {
                assert(Logger.lowLevelDebug("is not icmpv6"))
                return false
            }
            guard let upper = pkb.upper else {
                assert(Logger.lowLevelDebug("not valid icmpv6"))
                return false
            }
            let icmp: UnsafeMutablePointer<swvs_icmp_hdr> = Convert.ptr2mutUnsafe(upper)

            if icmp.pointee.type == ICMPv6_PROTOCOL_TYPE_Neighbor_Solicitation {
                assert(Logger.lowLevelDebug("input is neighbor solicitation?"))

                if icmp.pointee.code != 0 {
                    assert(Logger.lowLevelDebug("icmpv6 neighbor solicitation code is not 0"))
                    return false
                }
                let ndpNil: UnsafeMutablePointer<swvs_compose_icmpv6_ns>? = pkb.getAs(icmp)
                guard let ndp = ndpNil else {
                    assert(Logger.lowLevelDebug("no enough room for neighbor solicitation"))
                    return false
                }
                let target = IPv6(raw: &ndp.pointee.target)
                if !ip6.contains(target) {
                    assert(Logger.lowLevelDebug("target ip \(target) is not owned by \(name)"))
                    return false
                }
                var opt: UnsafeMutablePointer<swvs_icmp_ndp_opt>? = pkb.getAs(ndp.advanced(by: 1))
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
                    return false
                }

                let srcmacInOpt = MacAddress(raw: &slla.pointee.addr)
                if pkb.srcmac != srcmacInOpt {
                    assert(Logger.lowLevelDebug("srcmac is not the same as specified in source-link-layer-address option"))
                    return false
                }

                assert(Logger.lowLevelDebug("begin to handle the icmpv6 ndp-ns ..."))

                ifMac.copyInto(&ether.pointee.src)
                pkb.srcmac!.copyInto(&ether.pointee.dst)

                let ip: UnsafeMutablePointer<swvs_ipv6hdr> = Convert.ptr2mutUnsafe(ipraw)
                pkb.ipSrc!.copyInto(&ip.pointee.dst)
                target.copyInto(&ip.pointee.src)

                let icmpRes: UnsafeMutablePointer<swvs_compose_icmpv6_na_tlla> = Convert.ptr2mutUnsafe(icmp)
                icmpRes.pointee.icmp.type = ICMPv6_PROTOCOL_TYPE_Neighbor_Advertisement
                icmpRes.pointee.icmp.code = 0
                icmpRes.pointee.opt.type = ICMPv6_OPTION_TYPE_Target_Link_Layer_Address
                icmpRes.pointee.opt.len = 1 // 1 * 8 = 8
                icmpRes.pointee.flags = 0b0110_0000
                target.copyInto(&icmpRes.pointee.target)
                ifMac.copyInto(&icmpRes.pointee.opt.addr)

                let lenDelta = pkb.lengthFromUpperToEnd - MemoryLayout<swvs_compose_icmpv6_na_tlla>.stride
                if lenDelta == 0 {
                    assert(Logger.lowLevelDebug("no need to shrink packet total length"))
                } else {
                    assert(Logger.lowLevelDebug("need to shrink packet total length: \(lenDelta)"))
                }
                ip.pointee.be_payload_len = Convert.reverseByteOrder(Convert.reverseByteOrder(
                    ip.pointee.be_payload_len - UInt16(lenDelta)))
            } else if icmp.pointee.type == ICMPv6_PROTOCOL_TYPE_ECHO_REQ {
                assert(Logger.lowLevelDebug("input is icmpv6 ping-req?"))

                if icmp.pointee.code != 0 {
                    assert(Logger.lowLevelDebug("icmpv6 ping code is not 0"))
                    return false
                }

                assert(Logger.lowLevelDebug("begin to handle the icmpv6 ping ..."))

                icmp.pointee.type = ICMPv6_PROTOCOL_TYPE_ECHO_RESP

                let ip: UnsafeMutablePointer<swvs_ipv6hdr> = Convert.ptr2mutUnsafe(ipraw)
                pkb.ipSrc!.copyInto(&ip.pointee.dst)
                pkb.ipDst!.copyInto(&ip.pointee.src)

                pkb.srcmac!.copyInto(&ether.pointee.dst)
                ifMac.copyInto(&ether.pointee.src)
            } else {
                assert(Logger.lowLevelDebug("not ndp-ns nor ping-req"))
                return false
            }

            pkb.clearPacketInfo(from: .ETHER)
        } else {
            assert(Logger.lowLevelDebug("not arp/ipv4/ipv6"))
            return false
        }

        _ = packetsToSend.storeFromNoWrap { buf, off, _ in
            buf[off] = pkb
            return 1
        }
        return true
    }

    public func add(ip: (any IP)?) {
        if let ip = ip as? IPv4 {
            add(ip: ip)
        } else if let ip = ip as? IPv6 {
            add(ip: ip)
        }
    }

    public func del(ip: (any IP)?) {
        if let ip = ip as? IPv4 {
            del(ip: ip)
        } else if let ip = ip as? IPv6 {
            del(ip: ip)
        }
    }

    public func add(ip: IPv4) {
        if ip4.contains(where: { a in a == ip }) {
            return
        }
        ip4.insert(ip)
    }

    public func del(ip: IPv4) {
        ip4.remove(ip)
    }

    public func add(ip: IPv6) {
        if ip6.contains(where: { a in a == ip }) {
            return
        }
        ip6.insert(ip)
    }

    public func del(ip: IPv6) {
        ip6.remove(ip)
    }
}
