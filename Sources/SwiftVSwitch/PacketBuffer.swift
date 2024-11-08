#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import SwiftVSwitchCHelper
import VProxyCommon

let PKB_FLAG_HAS_SRC_MAC: UInt8 = 0b0000_0001
let PKB_FLAG_HAS_DST_MAC: UInt8 = 0b0000_0010
let PKB_FLAG_HAS_IP4_SRC: UInt8 = 0b0000_0100
let PKB_FLAG_HAS_IP4_DST: UInt8 = 0b0000_1000
let PKB_FLAG_HAS_IP6_SRC: UInt8 = 0b0001_0000
let PKB_FLAG_HAS_IP6_DST: UInt8 = 0b0010_0000

public class PacketBuffer: CustomStringConvertible {
    public var useOwned: Bool = false

    public unowned var inputIface: IfaceEx? = nil
    public package(set) unowned var bridge: Bridge? = nil
    public package(set) unowned var netstack: NetStack? = nil
    public unowned var outputIface: IfaceEx? = nil

    private var packetArray: [UInt8]? // keep reference to it, or nil if no need to keep ref
    public private(set) var raw: UnsafePointer<UInt8> // pointer to the packet
    public var pktlen: Int
    public private(set) var headroom: Int
    public private(set) var tailroom: Int

    public var csumState: CSumState = .NONE
    private var flags: UInt8 = 0
    private var srcmac_: MacAddress = .init(from: "00:00:00:00:00:00")!
    private var dstmac_: MacAddress = .init(from: "00:00:00:00:00:00")!
    public var vlanState: VlanState = .UNKNOWN
    public private(set) var vlan: UInt16 = 0
    public private(set) var ethertype: UInt16 = 0
    private var ip4Src: IPv4 = .init(from: "0.0.0.0")!
    private var ip4Dst: IPv4 = .init(from: "0.0.0.0")!
    private var ip6Src: IPv6 = .init(from: "::")!
    private var ip6Dst: IPv6 = .init(from: "::")!
    public private(set) var proto: UInt8 = 0
    public private(set) var srcPort: UInt16 = 0
    public private(set) var dstPort: UInt16 = 0
    public private(set) var appLen: UInt16 = 0

    public private(set) var ip: UnsafePointer<UInt8>?
    public private(set) var upper: UnsafePointer<UInt8>?
    public private(set) var app: UnsafePointer<UInt8>?

    public var outputRouteRule: RouteTable.RouteRule? = nil

    public var lengthFromIpToEnd: Int {
        guard let ip else {
            return -1
        }
        return pktlen - (ip - raw)
    }

    public var lengthFromUpperToEnd: Int {
        guard let upper else {
            return -1
        }
        return pktlen - (upper - raw)
    }

    public var lengthFromAppToEnd: Int {
        guard let app else {
            return -1
        }
        return pktlen - (app - raw)
    }

    public var srcmac: MacAddress? {
        if flags & PKB_FLAG_HAS_SRC_MAC != 0 {
            return srcmac_
        } else {
            return nil
        }
    }

    public var dstmac: MacAddress? {
        if flags & PKB_FLAG_HAS_DST_MAC != 0 {
            return dstmac_
        } else {
            return nil
        }
    }

    public var ipSrc: (any IP)? {
        if flags & PKB_FLAG_HAS_IP4_SRC != 0 {
            return ip4Src
        } else if flags & PKB_FLAG_HAS_IP6_SRC != 0 {
            return ip6Src
        } else {
            return nil
        }
    }

    public var ipDst: (any IP)? {
        if flags & PKB_FLAG_HAS_IP4_DST != 0 {
            return ip4Dst
        } else if flags & PKB_FLAG_HAS_IP6_DST != 0 {
            return ip6Dst
        } else {
            return nil
        }
    }

    public var arpOp: UInt8 {
        return UInt8(srcPort & 0xff)
    }

    public var icmpType: UInt8 {
        return UInt8(srcPort & 0xff)
    }

    public var icmpCode: UInt8 {
        return UInt8(dstPort & 0xff)
    }

    public var pingId: UInt16 {
        return dstPort
    }

    public init(packetArray: [UInt8], offset: Int, pktlen: Int, headroom: Int, tailroom: Int) {
        self.packetArray = packetArray
        raw = Convert.mut2ptr(Arrays.getRaw(from: packetArray, offset: offset + headroom))
        self.pktlen = pktlen
        self.headroom = headroom
        self.tailroom = tailroom

        calcPacketInfo()
    }

    public init(raw: UnsafePointer<UInt8>, pktlen: Int, headroom: Int, tailroom: Int) {
        packetArray = nil
        self.raw = raw
        self.pktlen = pktlen
        self.headroom = headroom
        self.tailroom = tailroom

        calcPacketInfo()
    }

    public convenience init(copyFrom: UnsafeRawPointer, pktlen: Int) {
        let array: [UInt8] = Arrays.newArray(capacity: pktlen + 256 + 256)
        let raw = Arrays.getRaw(from: array, offset: 256)
        memcpy(raw, copyFrom, pktlen)
        self.init(packetArray: array, offset: 256, pktlen: pktlen, headroom: 256, tailroom: 256)
    }

    public init(_ other: PacketBuffer) {
        useOwned = other.useOwned
        inputIface = other.inputIface
        bridge = other.bridge
        if let otherPacketArray = other.packetArray {
            packetArray = Arrays.newArray(capacity: otherPacketArray.capacity, uninitialized: true)
            memcpy(&packetArray!, otherPacketArray, otherPacketArray.capacity)
            raw = Convert.mutraw2ptr(&packetArray!)
                .advanced(by: Convert.ptr2mutptr(other.raw) - Arrays.getRaw(from: otherPacketArray))
        } else {
            packetArray = Arrays.newArray(capacity: other.headroom + other.pktlen + other.tailroom, uninitialized: true)
            raw = Convert.mutraw2ptr(&packetArray!).advanced(by: other.headroom)
            memcpy(Convert.ptr2mutraw(raw),
                   other.raw.advanced(by: -other.headroom),
                   other.headroom + other.pktlen + other.tailroom)
        }
        pktlen = other.pktlen
        headroom = other.headroom
        tailroom = other.tailroom
        csumState = other.csumState
        flags = other.flags
        srcmac_ = other.srcmac_
        dstmac_ = other.dstmac_
        vlanState = other.vlanState
        vlan = other.vlan
        ethertype = other.ethertype
        ip4Src = other.ip4Src
        ip4Dst = other.ip4Dst
        ip6Src = other.ip6Src
        ip6Dst = other.ip6Dst
        proto = other.proto
        srcPort = other.srcPort
        dstPort = other.dstPort
        appLen = other.appLen
        if let otherIp = other.ip {
            ip = raw.advanced(by: otherIp - other.raw)
        } else {
            ip = nil
        }
        if let otherUpper = other.upper {
            upper = raw.advanced(by: otherUpper - other.raw)
        } else {
            upper = nil
        }
        if let otherApp = other.app {
            app = raw.advanced(by: otherApp - other.raw)
        } else {
            app = nil
        }
        outputIface = other.outputIface
        outputRouteRule = other.outputRouteRule
    }

    public func occpuyHeadroom(_ n: Int) -> Bool {
        if headroom < n {
            return false
        }
        headroom -= n
        raw = raw.advanced(by: -n)
        pktlen += n
        return true
    }

    public func releaseHeadroom(_ n: Int) -> Bool {
        if pktlen < n {
            return false
        }
        headroom += n
        raw = raw.advanced(by: n)
        pktlen -= n
        return true
    }

    public func occpuyTailroom(_ n: Int) -> Bool {
        if tailroom < n {
            return false
        }
        tailroom -= n
        pktlen += n
        return true
    }

    public func releaseTailroom(_ n: Int) -> Bool {
        if pktlen < n {
            return false
        }
        tailroom += n
        pktlen -= n
        return true
    }

    public func clearPacketInfo() {
        flags = 0
        vlanState = .UNKNOWN
        vlan = 0
        ethertype = 0
        srcPort = 0
        dstPort = 0
        appLen = 0

        ip = nil
        upper = nil
        app = nil
    }

    public func getAs<T>(_ p: UnsafeRawPointer, _ logHint: String = "<?>") -> UnsafeMutablePointer<T>? {
        let len = MemoryLayout<T>.stride
        if Convert.raw2ptr(p) + len - raw > pktlen {
            assert(Logger.lowLevelDebug("pktlen=\(pktlen) not enough for \(logHint)"))
            return nil
        }
        return Convert.raw2mutptr(p)
    }

    public func calcPacketInfo() {
        clearPacketInfo()

        let etherPtr: UnsafeMutablePointer<swvs_ethhdr>? = getAs(raw, "ethernet")
        guard let etherPtr else {
            return
        }

        ethertype = Convert.reverseByteOrder(etherPtr.pointee.be_type)
        dstmac_ = MacAddress(raw: Convert.ptr2ptrUnsafe(etherPtr))
        srcmac_ = MacAddress(raw: Convert.ptr2ptrUnsafe(etherPtr).advanced(by: 6))
        flags |= PKB_FLAG_HAS_DST_MAC
        flags |= PKB_FLAG_HAS_SRC_MAC

        let ipRawPtr: UnsafeRawPointer
        if ethertype == ETHER_TYPE_8021Q {
            let vlanPtr: UnsafeMutablePointer<swvs_vlantag>? = getAs(etherPtr.advanced(by: 1), "vlan tag")
            guard let vlanPtr else {
                return
            }

            vlanState = .HAS_VLAN
            vlan = Convert.reverseByteOrder(vlanPtr.pointee.be_vid)
            ethertype = Convert.reverseByteOrder(vlanPtr.pointee.be_type)

            ipRawPtr = Convert.ptr2raw(vlanPtr.advanced(by: 1))
        } else {
            vlanState = .NO_VLAN
            ipRawPtr = Convert.ptr2raw(etherPtr.advanced(by: 1))
        }

        var upper: UnsafePointer<UInt8>
        if ethertype == ETHER_TYPE_ARP {
            let arpPtr: UnsafeMutablePointer<swvs_arp>? = getAs(ipRawPtr, "arp")
            guard let arpPtr else {
                return
            }

            let expectedPktlen = Convert.ptr2ptrUnsafe(arpPtr) + MemoryLayout<swvs_arp>.stride - raw
            if expectedPktlen < pktlen {
                assert(Logger.lowLevelDebug("shrinks pktlen from \(pktlen) to \(expectedPktlen)"))
                tailroom += pktlen - expectedPktlen
                pktlen = expectedPktlen
            } else {
                assert(Logger.lowLevelDebug("arp packet exactly matches the pktlen"))
            }

            if arpPtr.pointee.be_arp_hardware != BE_ARP_HARDWARE_TYPE_ETHER {
                assert(Logger.lowLevelDebug("arp, expecting hardware_type=ether, but got BE:\(arpPtr.pointee.be_arp_hardware)"))
                return
            }
            if arpPtr.pointee.be_arp_protocol != BE_ARP_PROTOCOL_TYPE_IP {
                assert(Logger.lowLevelDebug("arp, expecting protocol=ip, but got BE:\(arpPtr.pointee.be_arp_protocol)"))
                return
            }
            if arpPtr.pointee.arp_hlen != 6 {
                assert(Logger.lowLevelDebug("arp, expecting hlen=6, but got \(arpPtr.pointee.arp_hlen)"))
                return
            }
            if arpPtr.pointee.arp_plen != 4 {
                assert(Logger.lowLevelDebug("arp, expecting plen=4, but got \(arpPtr.pointee.arp_plen)"))
                return
            }

            ip = Convert.ptr2ptrUnsafe(arpPtr)

            ip4Src = IPv4(raw: &arpPtr.pointee.arp_sip)
            ip4Dst = IPv4(raw: &arpPtr.pointee.arp_tip)
            srcPort = Convert.reverseByteOrder(arpPtr.pointee.be_arp_opcode)
            flags |= PKB_FLAG_HAS_IP4_SRC
            flags |= PKB_FLAG_HAS_IP4_DST

            return
        } else if ethertype == ETHER_TYPE_IPv4 {
            let ipPtr: UnsafeMutablePointer<swvs_ipv4hdr>? = getAs(ipRawPtr, "ipv4")
            guard let ipPtr else {
                return
            }

            let len = Int(ipPtr.pointee.version_ihl & 0x0f) * 4
            if len < 20 {
                assert(Logger.lowLevelDebug("ipv4 len=\(len) < 20"))
                return
            }
            if Convert.raw2ptr(ipRawPtr).advanced(by: len) - raw > pktlen {
                assert(Logger.lowLevelDebug("pktlen=\(pktlen) < ipv4 len=\(len)"))
                return
            }
            let totalLen = Int(Convert.reverseByteOrder(ipPtr.pointee.be_total_length))
            if totalLen < len {
                assert(Logger.lowLevelDebug("totalLen=\(totalLen) < len=\(len)"))
                return
            }
            let expectedPktlen = Convert.raw2ptr(ipRawPtr).advanced(by: totalLen) - raw
            if expectedPktlen > pktlen {
                assert(Logger.lowLevelDebug("totalLen=\(totalLen) will exceed pktlen=\(pktlen)"))
                return
            } else if expectedPktlen < pktlen {
                assert(Logger.lowLevelDebug("shrinks pktlen from \(pktlen) to \(expectedPktlen)"))
                tailroom += pktlen - expectedPktlen
                pktlen = expectedPktlen
            } else {
                assert(Logger.lowLevelDebug("totalLen=\(totalLen) exactly matches the pktlen"))
            }

            ip4Src = IPv4(raw: &ipPtr.pointee.src)
            ip4Dst = IPv4(raw: &ipPtr.pointee.dst)
            flags |= PKB_FLAG_HAS_IP4_SRC
            flags |= PKB_FLAG_HAS_IP4_DST
            ip = Convert.ptr2ptrUnsafe(ipPtr)
            proto = ipPtr.pointee.proto
            upper = Convert.ptr2ptrUnsafe(ipPtr).advanced(by: len)
        } else if ethertype == ETHER_TYPE_IPv6 {
            let ipPtr: UnsafeMutablePointer<swvs_ipv6hdr>? = getAs(ipRawPtr, "ipv6")
            guard let ipPtr else {
                return
            }

            let payloadLen = Int(Convert.reverseByteOrder(ipPtr.pointee.be_payload_len))
            let expectedPktlen = Convert.raw2ptr(ipRawPtr).advanced(by: 40).advanced(by: payloadLen) - raw
            if expectedPktlen > pktlen {
                assert(Logger.lowLevelDebug("payloadLen=\(payloadLen) will exceed pktlen=\(pktlen)"))
                return
            } else if expectedPktlen < pktlen {
                assert(Logger.lowLevelDebug("shrinks pktlen from \(pktlen) to \(expectedPktlen)"))
                tailroom += pktlen - expectedPktlen
                pktlen = expectedPktlen
            } else {
                assert(Logger.lowLevelDebug("payloadLen=\(payloadLen) exactly matches the pktlen"))
            }

            let tup = skipIPv6Headers(ipPtr)
            guard let tup else {
                return
            }

            ip6Src = IPv6(raw: &ipPtr.pointee.src)
            ip6Dst = IPv6(raw: &ipPtr.pointee.dst)
            flags |= PKB_FLAG_HAS_IP6_SRC
            flags |= PKB_FLAG_HAS_IP6_DST
            ip = Convert.ptr2ptrUnsafe(ipPtr)
            (proto, upper) = tup
        } else {
            assert(Logger.lowLevelDebug("ether=\(ethertype) no upper"))
            return
        }

        if proto == IP_PROTOCOL_TCP {
            let tcpPtr: UnsafeMutablePointer<swvs_tcphdr>? = getAs(upper, "tcp")
            guard let tcpPtr else {
                return
            }

            let len = Int((tcpPtr.pointee.data_off >> 4) & 0xf) * 4
            if len < 20 {
                assert(Logger.lowLevelDebug("tcp data_off=\(len) < 20"))
                return
            }
            if Convert.ptr2ptrUnsafe(tcpPtr) + len - raw > pktlen {
                assert(Logger.lowLevelDebug("pktlen=\(pktlen) not enough for tcp len=\(len)"))
                return
            }
            srcPort = Convert.reverseByteOrder(tcpPtr.pointee.be_src_port)
            dstPort = Convert.reverseByteOrder(tcpPtr.pointee.be_dst_port)
            self.upper = upper
            app = Convert.ptr2ptrUnsafe(tcpPtr).advanced(by: len)
            appLen = UInt16(pktlen - (app! - raw))
        } else if proto == IP_PROTOCOL_UDP {
            let udpPtr: UnsafeMutablePointer<swvs_udphdr>? = getAs(upper, "udp")
            guard let udpPtr else {
                return
            }

            let len = Int(Convert.reverseByteOrder(udpPtr.pointee.be_len))
            if len < 8 {
                assert(Logger.lowLevelDebug("udp len=\(len) < 8"))
                return
            }
            let expectedPktlen = Convert.ptr2ptrUnsafe(udpPtr) + len - raw
            if expectedPktlen > pktlen {
                assert(Logger.lowLevelDebug("pktlen=\(pktlen) not enough for udp len=\(len)"))
                return
            } else if expectedPktlen < pktlen {
                assert(Logger.lowLevelDebug("shrink pktlen from \(pktlen) to \(expectedPktlen)"))
                tailroom += pktlen - expectedPktlen
                pktlen = expectedPktlen
            } else {
                assert(Logger.lowLevelDebug("udpLen=\(len) exactly matches the pktlen"))
            }
            srcPort = Convert.reverseByteOrder(udpPtr.pointee.be_src_port)
            dstPort = Convert.reverseByteOrder(udpPtr.pointee.be_dst_port)
            self.upper = upper
            app = Convert.ptr2ptrUnsafe(udpPtr.advanced(by: 1))
            appLen = UInt16(len - 8)
        } else if proto == IP_PROTOCOL_ICMP || proto == IP_PROTOCOL_ICMPv6 {
            let icmpPtr: UnsafeMutablePointer<swvs_icmp_hdr>? = getAs(upper, "icmp{4|6}")
            guard let icmpPtr else {
                return
            }

            srcPort = UInt16(icmpPtr.pointee.type)
            dstPort = UInt16(icmpPtr.pointee.code)
            self.upper = upper
            app = Convert.ptr2ptrUnsafe(icmpPtr.advanced(by: 1))
            appLen = UInt16(pktlen - (app! - raw))
        } else {
            assert(Logger.lowLevelDebug("unknown ip proto \(proto)"))
            return
        }
    }

    private func skipIPv6Headers(_ v6: UnsafePointer<swvs_ipv6hdr>) -> (UInt8, UnsafePointer<UInt8>)? {
        let hdr = v6.pointee.next_hdr
        if !IPv6_needs_next_header.contains(hdr) {
            return (hdr, Convert.ptr2ptrUnsafe(v6.advanced(by: 1)))
        }
        let hdrptr: UnsafePointer<swvs_ipv6nxthdr> = Convert.ptr2ptrUnsafe(v6.advanced(by: 1))
        if Convert.ptr2ptrUnsafe(hdrptr) + 8 - raw > pktlen {
            assert(Logger.lowLevelDebug("pktlen=\(pktlen) not enough for nexthdr \(hdrptr)"))
            return nil
        }
        if Convert.ptr2ptrUnsafe(hdrptr) + 8 + Int(hdrptr.pointee.len) - raw > pktlen {
            assert(Logger.lowLevelDebug("pktlen=\(pktlen) not enough for nexthdr \(hdrptr) len=\(hdrptr.pointee.len)"))
            return nil
        }
        return skipIPv6NextHeaders(hdrptr)
    }

    private func skipIPv6NextHeaders(_ hdrptr: UnsafePointer<swvs_ipv6nxthdr>) -> (UInt8, UnsafePointer<UInt8>)? {
        let p: UnsafePointer<UInt8> = Convert.ptr2ptrUnsafe(hdrptr)
        let nxt = p.advanced(by: Int(8 + hdrptr.pointee.len))
        if !IPv6_needs_next_header.contains(hdrptr.pointee.next_hdr) {
            return (hdrptr.pointee.next_hdr, nxt)
        }
        if Convert.ptr2ptrUnsafe(nxt) + 8 - raw > pktlen {
            assert(Logger.lowLevelDebug("pktlen=\(pktlen) not enough for nexthdr \(nxt)"))
            return nil
        }
        let nxtPtr: UnsafePointer<swvs_ipv6nxthdr> = Convert.ptr2ptrUnsafe(nxt)
        if Convert.raw2ptr(nxt) + 8 + Int(nxtPtr.pointee.len) - raw > pktlen {
            assert(Logger.lowLevelDebug("pktlen=\(pktlen) not enough for nexthdr \(nxt) len=\(hdrptr.pointee.len)"))
            return nil
        }
        return skipIPv6NextHeaders(nxtPtr)
    }

    public var description: String {
        var ret = "PacketBuffer(head=\(headroom),pkt=\(pktlen),tail=\(tailroom),"
        if let inputIface {
            ret += "input=\(inputIface.name),"
        }
        if let dstmac {
            ret += "dl_dst=\(dstmac),"
        }
        if let srcmac {
            ret += "dl_src=\(srcmac),"
        }
        if vlanState == .HAS_VLAN {
            ret += "vlan=\(vlan),"
        }
        if ethertype == ETHER_TYPE_ARP {
            ret += "dl_type=arp(\(ethertype)),"
        } else if ethertype == ETHER_TYPE_IPv4 {
            ret += "dl_type=ip(\(ethertype)),"
        } else if ethertype == ETHER_TYPE_IPv6 {
            ret += "dl_type=ipv6(\(ethertype)),"
        } else {
            ret += "dl_type=\(ethertype),"
        }
        if ethertype == ETHER_TYPE_ARP {
            if let ipSrc {
                ret += "arp_spa=\(ipSrc),"
            }
            if let ipDst {
                ret += "arp_tpa=\(ipDst),"
            }
        } else {
            if let ipSrc {
                ret += "nw_src=\(ipSrc),"
            }
            if let ipDst {
                ret += "nw_dst=\(ipDst),"
            }
        }
        if proto == IP_PROTOCOL_TCP {
            ret += "nw_proto=tcp(\(proto)),"
        } else if proto == IP_PROTOCOL_UDP {
            ret += "nw_proto=udp(\(proto)),"
        } else if proto == IP_PROTOCOL_ICMP {
            ret += "nw_proto=icmp(\(proto)),"
        } else if proto == IP_PROTOCOL_ICMPv6 {
            ret += "nw_proto=icmp6(\(proto)),"
        } else {
            ret += "proto=\(proto),"
        }
        if proto == IP_PROTOCOL_TCP || proto == IP_PROTOCOL_UDP {
            ret += "tp_src=\(srcPort),"
            ret += "tp_dst=\(dstPort),"
        } else if proto == IP_PROTOCOL_ICMP || proto == IP_PROTOCOL_ICMPv6 {
            ret += "icmp_type=\(icmpType),"
            ret += "icmp_code=\(icmpCode),"
        }
        ret += "app=\(appLen),"
        if ret.hasSuffix(",") {
            ret.removeLast()
        }
        ret += ")@\(Unmanaged.passUnretained(self).toOpaque())"
        return ret
    }
}

public enum VlanState {
    case UNKNOWN
    case HAS_VLAN
    case NO_VLAN
    case REMOVED
}

public enum CSumState {
    /**
     * checksum is not verified nor calculated.
     * sw rx: the csum should be validated before processing
     * sw tx: csum must be calculated if the tx iface doesn't support tx offloading
     */
    case NONE
    /**
     * checksum doesn't have to be present.
     * sw rx: pass
     * sw tx: csum must be calculated if the tx iface doesn't support tx offloading
     */
    case UNNECESSARY
    /**
     * checksum is verified or calculated.
     * sw rx: pass
     * sw tx: pass
     */
    case COMPLETE
}
