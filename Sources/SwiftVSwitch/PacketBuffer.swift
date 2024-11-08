#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import SwiftVSwitchCHelper
import VProxyCommon

let PKB_FLAG_NO_ETHER: UInt16 = 0x0001
let PKB_FLAG_ETHER_DONE: UInt16 = 0x0002
let PKB_FLAG_ETHER_FAIL: UInt16 = 0x0004
let PKB_FLAG_IP_DONE: UInt16 = 0x0008
let PKB_FLAG_IP_FAIL: UInt16 = 0x0010
let PKB_FLAG_UPPER_DONE: UInt16 = 0x0020
let PKB_FLAG_UPPER_FAIL: UInt16 = 0x0040

public class PacketBuffer: CustomStringConvertible {
    public var useOwned: Bool = false

    public package(set) unowned var bridge: Bridge? = nil
    public package(set) unowned var netstack: NetStack? = nil

    public unowned var inputIface: IfaceEx? = nil
    public unowned var outputIface: IfaceEx? = nil
    public var outputRouteRule: RouteTable.RouteRule? = nil

    private var packetArray: [UInt8]? // keep reference to it, or nil if no need to keep ref
    public private(set) var raw: UnsafePointer<UInt8> // pointer to the packet
    public var pktlen: Int
    public private(set) var headroom: Int
    public private(set) var tailroom: Int

    public var csumState: CSumState = .NONE
    private var flags: UInt16 = 0
    private var srcmac_ = MacAddress.ZERO
    private var dstmac_ = MacAddress.ZERO
    private var vlanState_: VlanState = .UNKNOWN
    private var vlan_: UInt16 = 0
    private var ethertype_: UInt16 = 0
    private var ip4Src_: IPv4 = .init(from: "0.0.0.0")!
    private var ip4Dst_: IPv4 = .init(from: "0.0.0.0")!
    private var ip6Src_: IPv6 = .init(from: "::")!
    private var ip6Dst_: IPv6 = .init(from: "::")!
    private var proto_: UInt8 = 0
    private var srcPort_: UInt16 = 0
    private var dstPort_: UInt16 = 0
    private var appLen_: UInt16 = 0

    private var ether_: UnsafePointer<UInt8>?
    private var ip_: UnsafePointer<UInt8>?
    private var upper_: UnsafePointer<UInt8>?
    private var app_: UnsafePointer<UInt8>?

    public var hasEthernet: Bool {
        return flags & PKB_FLAG_NO_ETHER == 0
    }

    public var lengthFromIpToEnd: Int {
        if flags & PKB_FLAG_IP_DONE == 0 {
            ensurePktInfo(level: .IP)
        }
        guard let ip_ else {
            return -1
        }
        return pktlen - (ip_ - raw)
    }

    public var lengthFromUpperToEnd: Int {
        if flags & PKB_FLAG_UPPER_DONE == 0 {
            ensurePktInfo(level: .UPPER)
        }
        guard let upper_ else {
            return -1
        }
        return pktlen - (upper_ - raw)
    }

    public var lengthFromAppToEnd: Int {
        if flags & PKB_FLAG_UPPER_DONE == 0 {
            ensurePktInfo(level: .UPPER)
        }
        guard let app_ else {
            return -1
        }
        return pktlen - (app_ - raw)
    }

    public var srcmac: MacAddress? {
        if flags & PKB_FLAG_ETHER_DONE == 0 {
            ensurePktInfo(level: .ETHER)
        }
        if flags & PKB_FLAG_ETHER_FAIL != 0 {
            return nil
        }
        if !hasEthernet {
            return nil
        }
        return srcmac_
    }

    public var dstmac: MacAddress? {
        if flags & PKB_FLAG_ETHER_DONE == 0 {
            ensurePktInfo(level: .ETHER)
        }
        if flags & PKB_FLAG_ETHER_FAIL != 0 {
            return nil
        }
        if !hasEthernet {
            return nil
        }
        return dstmac_
    }

    public var ethertype: UInt16 {
        // real ethertype might be recorded in vlan
        if vlanState_ == .UNKNOWN {
            ensurePktInfo(level: .VLAN)
        }
        if vlanState_ == .INVALID {
            return 0
        }
        return ethertype_
    }

    public var vlanState: VlanState {
        get {
            if vlanState_ == .UNKNOWN {
                ensurePktInfo(level: .VLAN)
            }
            return vlanState_
        }
        set {
            vlanState_ = newValue
        }
    }

    public var vlan: UInt16 {
        if vlanState_ == .UNKNOWN {
            ensurePktInfo(level: .VLAN)
        }
        if vlanState_ != .HAS_VLAN {
            return 0
        }
        return vlan_
    }

    public var ipSrc: (any IP)? {
        if flags & PKB_FLAG_IP_DONE == 0 {
            ensurePktInfo(level: .IP)
        }
        if flags & PKB_FLAG_IP_FAIL != 0 {
            return nil
        }
        if ethertype_ == ETHER_TYPE_IPv4 || ethertype_ == ETHER_TYPE_ARP {
            return ip4Src_
        } else {
            return ip6Src_
        }
    }

    public var ipDst: (any IP)? {
        if flags & PKB_FLAG_IP_DONE == 0 {
            ensurePktInfo(level: .IP)
        }
        if flags & PKB_FLAG_IP_FAIL != 0 {
            return nil
        }
        if ethertype_ == ETHER_TYPE_IPv4 || ethertype_ == ETHER_TYPE_ARP {
            return ip4Dst_
        } else {
            return ip6Dst_
        }
    }

    public var proto: UInt8 {
        if flags & PKB_FLAG_IP_DONE == 0 {
            ensurePktInfo(level: .IP)
        }
        if flags & PKB_FLAG_IP_FAIL != 0 {
            return 0
        }
        return proto_
    }

    public var arpOp: UInt8 {
        if flags & PKB_FLAG_IP_DONE == 0 {
            ensurePktInfo(level: .IP)
        }
        if flags & PKB_FLAG_IP_FAIL != 0 {
            return 0
        }
        return UInt8(srcPort_ & 0xff)
    }

    public var srcPort: UInt16 {
        if flags & PKB_FLAG_UPPER_DONE == 0 {
            ensurePktInfo(level: .UPPER)
        }
        if flags & PKB_FLAG_UPPER_FAIL != 0 {
            return 0
        }
        return srcPort_
    }

    public var dstPort: UInt16 {
        if flags & PKB_FLAG_UPPER_DONE == 0 {
            ensurePktInfo(level: .UPPER)
        }
        if flags & PKB_FLAG_UPPER_FAIL != 0 {
            return 0
        }
        return dstPort_
    }

    public var icmpType: UInt8 {
        if flags & PKB_FLAG_UPPER_DONE == 0 {
            ensurePktInfo(level: .UPPER)
        }
        if flags & PKB_FLAG_UPPER_FAIL != 0 {
            return 0
        }
        return UInt8(srcPort_ & 0xff)
    }

    public var icmpCode: UInt8 {
        if flags & PKB_FLAG_UPPER_DONE == 0 {
            ensurePktInfo(level: .UPPER)
        }
        if flags & PKB_FLAG_UPPER_FAIL != 0 {
            return 0
        }
        return UInt8(dstPort_ & 0xff)
    }

    public var ether: UnsafePointer<UInt8>? {
        if flags & PKB_FLAG_ETHER_DONE == 0 {
            ensurePktInfo(level: .ETHER)
        }
        if flags & PKB_FLAG_ETHER_FAIL != 0 {
            return nil
        }
        return ether_
    }

    public var ip: UnsafePointer<UInt8>? {
        if flags & PKB_FLAG_IP_DONE == 0 {
            ensurePktInfo(level: .IP)
        }
        if flags & PKB_FLAG_IP_FAIL != 0 {
            return nil
        }
        return ip_
    }

    public var upper: UnsafePointer<UInt8>? {
        if flags & PKB_FLAG_UPPER_DONE == 0 {
            ensurePktInfo(level: .UPPER)
        }
        if flags & PKB_FLAG_UPPER_FAIL != 0 {
            return nil
        }
        return upper_
    }

    public var app: UnsafePointer<UInt8>? {
        if flags & PKB_FLAG_UPPER_DONE == 0 {
            ensurePktInfo(level: .UPPER)
        }
        if flags & PKB_FLAG_UPPER_FAIL != 0 {
            return nil
        }
        return app_
    }

    public var appLen: UInt16 {
        if flags & PKB_FLAG_UPPER_DONE == 0 {
            ensurePktInfo(level: .UPPER)
        }
        if flags & PKB_FLAG_UPPER_FAIL != 0 {
            return 0
        }
        return appLen_
    }

    public init(packetArray: [UInt8], offset: Int, pktlen: Int, headroom: Int, tailroom: Int, hasEthernet: Bool = true) {
        self.packetArray = packetArray
        raw = Convert.mut2ptr(Arrays.getRaw(from: packetArray, offset: offset + headroom))
        self.pktlen = pktlen
        self.headroom = headroom
        self.tailroom = tailroom
        if !hasEthernet {
            flags |= PKB_FLAG_NO_ETHER
        }
    }

    public init(raw: UnsafePointer<UInt8>, pktlen: Int, headroom: Int, tailroom: Int, hasEthernet: Bool = true) {
        packetArray = nil
        self.raw = raw
        self.pktlen = pktlen
        self.headroom = headroom
        self.tailroom = tailroom
        if !hasEthernet {
            flags |= PKB_FLAG_NO_ETHER
        }
    }

    public convenience init(copyFrom: UnsafeRawPointer, pktlen: Int) {
        let array: [UInt8] = Arrays.newArray(capacity: pktlen + 256 + 256)
        let raw = Arrays.getRaw(from: array, offset: 256)
        memcpy(raw, copyFrom, pktlen)
        self.init(packetArray: array, offset: 256, pktlen: pktlen, headroom: 256, tailroom: 256)
    }

    public init(_ other: PacketBuffer) {
        useOwned = true

        bridge = other.bridge
        netstack = other.netstack

        inputIface = other.inputIface
        outputIface = other.outputIface
        outputRouteRule = other.outputRouteRule

        if let otherPacketArray = other.packetArray {
            packetArray = Arrays.newArray(capacity: otherPacketArray.capacity, uninitialized: true)
            memcpy(&packetArray!, otherPacketArray, otherPacketArray.capacity)
            raw = Convert.mutraw2ptr(&packetArray!)
                .advanced(by: Convert.ptr2mutptr(other.raw) - Arrays.getRaw(from: otherPacketArray))
        } else {
            packetArray = Arrays.newArray(capacity: other.headroom + other.pktlen + other.tailroom, uninitialized: true)
            raw = Convert.mutraw2ptr(&packetArray!).advanced(by: other.headroom)
            memcpy(&packetArray!,
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
        vlanState_ = other.vlanState_
        vlan_ = other.vlan_
        ethertype_ = other.ethertype_
        ip4Src_ = other.ip4Src_
        ip4Dst_ = other.ip4Dst_
        ip6Src_ = other.ip6Src_
        ip6Dst_ = other.ip6Dst_
        proto_ = other.proto_
        srcPort_ = other.srcPort_
        dstPort_ = other.dstPort_
        appLen_ = other.appLen_
        if let otherEther = other.ether_ {
            ether_ = raw.advanced(by: otherEther - other.raw)
        } else {
            ether_ = nil
        }
        if let otherIp = other.ip_ {
            ip_ = raw.advanced(by: otherIp - other.raw)
        } else {
            ip_ = nil
        }
        if let otherUpper = other.upper_ {
            upper_ = raw.advanced(by: otherUpper - other.raw)
        } else {
            upper_ = nil
        }
        if let otherApp = other.app_ {
            app_ = raw.advanced(by: otherApp - other.raw)
        } else {
            app_ = nil
        }
    }

    public func ensureEthhdr() -> UnsafeMutablePointer<swvs_ethhdr>? {
        if hasEthernet {
            return ether_ == nil ? nil : Convert.ptr2mutUnsafe(ether_!)
        }
        if !occpuyHeadroom(MemoryLayout<swvs_ethhdr>.stride) {
            return nil
        }
        ether_ = raw
        flags &= ~PKB_FLAG_ETHER_DONE
        flags &= ~PKB_FLAG_NO_ETHER
        return Convert.ptr2mutUnsafe(raw)
    }

    public func ensureVlan(_ vlan: UInt16) -> UnsafeMutablePointer<swvs_compose_eth_vlan>? {
        if hasEthernet {
            if vlanState_ != .NO_VLAN {
                return nil
            }
            if !occpuyHeadroom(MemoryLayout<swvs_vlantag>.stride) {
                return nil
            }
            let mut = Convert.ptr2mutptr(ether_!)
            for i in 0 ..< 12 {
                mut.advanced(by: -MemoryLayout<swvs_vlantag>.stride + i).pointee = mut.advanced(by: i).pointee
            }
            vlanState_ = .REMOVED
            let ethvlan: UnsafeMutablePointer<swvs_compose_eth_vlan> = Convert.ptr2mutUnsafe(raw)
            ethvlan.pointee.ethhdr.be_type = BE_ETHER_TYPE_8021Q
            ethvlan.pointee.vlan.be_vid = Convert.reverseByteOrder(vlan)
            return Convert.ptr2mutUnsafe(raw)
        }
        if !occpuyHeadroom(MemoryLayout<swvs_compose_eth_vlan>.stride) {
            return nil
        }
        ether_ = raw
        let ethvlan: UnsafeMutablePointer<swvs_compose_eth_vlan> = Convert.ptr2mutUnsafe(raw)
        ethvlan.pointee.ethhdr.be_type = BE_ETHER_TYPE_8021Q
        ethvlan.pointee.vlan.be_vid = Convert.reverseByteOrder(vlan)
        ethvlan.pointee.vlan.be_type = Convert.reverseByteOrder(ethertype_)
        vlanState_ = .REMOVED
        flags &= ~PKB_FLAG_NO_ETHER
        flags &= ~PKB_FLAG_ETHER_DONE
        return Convert.ptr2mutUnsafe(raw)
    }

    public func removeVlan() {
        if !hasEthernet {
            return
        }
        if vlanState_ == .INVALID || vlanState_ == .NO_VLAN {
            return
        }
        let mut = Convert.ptr2mutptr(ether_!)
        for i in 0 ..< 14 {
            mut.advanced(by: 14 + MemoryLayout<swvs_vlantag>.stride - i).pointee = mut.advanced(by: 14 - i).pointee
        }
        _ = releaseHeadroom(MemoryLayout<swvs_vlantag>.stride)
        vlanState_ = .NO_VLAN
        ether_ = raw
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

    public func clearPacketInfo(from level: PacketInfoLevel, csum: CSumState? = nil) {
        switch level {
        case .ETHER:
            flags &= ~PKB_FLAG_ETHER_DONE
            fallthrough
        case .VLAN:
            vlanState_ = .UNKNOWN
            fallthrough
        case .IP:
            flags &= ~PKB_FLAG_IP_DONE
            fallthrough
        case .UPPER:
            flags &= ~PKB_FLAG_UPPER_DONE
            fallthrough
        default:
            break
        }
        if let csum {
            csumState = csum
        } else {
            if level.rawValue <= PacketInfoLevel.IP.rawValue {
                if csumState == .COMPLETE {
                    csumState = .UNNECESSARY
                }
            }
        }
    }

    public func clearPacketInfo(only level: PacketInfoLevel, csum: CSumState? = nil) {
        switch level {
        case .ETHER:
            flags &= ~PKB_FLAG_ETHER_DONE
        case .VLAN:
            vlanState_ = .UNKNOWN
        case .IP:
            flags &= ~PKB_FLAG_IP_DONE
        case .UPPER:
            flags &= ~PKB_FLAG_UPPER_DONE
        }
        if let csum {
            csumState = csum
        } else {
            if level.rawValue >= PacketInfoLevel.IP.rawValue {
                if csumState == .COMPLETE {
                    csumState = .UNNECESSARY
                }
            }
        }
    }

    public func getAs<T>(_ p: UnsafeRawPointer, _ logHint: String = "<?>") -> UnsafeMutablePointer<T>? {
        let len = MemoryLayout<T>.stride
        if Convert.raw2ptr(p) + len - raw > pktlen {
            assert(Logger.lowLevelDebug("pktlen=\(pktlen) not enough for \(logHint)"))
            return nil
        }
        return Convert.raw2mutptr(p)
    }

    private func calcEtherInfo() {
        if flags & PKB_FLAG_ETHER_DONE != 0 {
            return
        }
        let etherPtr: UnsafeMutablePointer<swvs_ethhdr>? = getAs(raw, "ethernet")
        guard let etherPtr else {
            flags |= PKB_FLAG_ETHER_DONE | PKB_FLAG_ETHER_FAIL
            return
        }

        if !hasEthernet {
            if pktlen == 0 {
                assert(Logger.lowLevelDebug("no room for anything"))
                flags |= PKB_FLAG_ETHER_DONE | PKB_FLAG_ETHER_FAIL
                return
            }
            let ver = (raw[0] >> 4) & 0xf
            if ver == 4 {
                ethertype_ = ETHER_TYPE_IPv4
            } else if ver == 6 {
                ethertype_ = ETHER_TYPE_IPv6
            } else {
                assert(Logger.lowLevelDebug("first byte \(raw[0]) produces unknown version \(ver)"))
                flags |= PKB_FLAG_ETHER_DONE | PKB_FLAG_ETHER_FAIL
                return
            }
            dstmac_ = MacAddress.ZERO
            srcmac_ = MacAddress.ZERO
            ether_ = nil
            ip_ = raw
            flags &= ~PKB_FLAG_ETHER_FAIL
            flags |= PKB_FLAG_ETHER_DONE
            return
        }

        ethertype_ = Convert.reverseByteOrder(etherPtr.pointee.be_type)
        dstmac_ = MacAddress(raw: Convert.ptr2ptrUnsafe(etherPtr))
        srcmac_ = MacAddress(raw: Convert.ptr2ptrUnsafe(etherPtr).advanced(by: 6))
        ether_ = raw
        ip_ = Convert.mut2ptrUnsafe(etherPtr.advanced(by: 1))
        flags &= ~PKB_FLAG_ETHER_FAIL
        flags |= PKB_FLAG_ETHER_DONE
    }

    private func calcVlanInfo() {
        if vlanState_ != .UNKNOWN {
            return
        }
        if flags & PKB_FLAG_ETHER_FAIL != 0 {
            vlanState_ = .INVALID
            return
        }
        if !hasEthernet {
            vlanState = .NO_VLAN
            return
        }
        if ethertype_ == ETHER_TYPE_8021Q {
            let vlanPtr: UnsafeMutablePointer<swvs_vlantag>? = getAs(ip_!, "vlan tag")
            guard let vlanPtr else {
                vlanState_ = .INVALID
                return
            }

            vlan_ = Convert.reverseByteOrder(vlanPtr.pointee.be_vid)
            ethertype_ = Convert.reverseByteOrder(vlanPtr.pointee.be_type)

            ip_ = Convert.ptr2ptrUnsafe(vlanPtr.advanced(by: 1))
            vlanState_ = .HAS_VLAN
        } else {
            vlanState_ = .NO_VLAN
        }
    }

    private func calcIpInfo() {
        if flags & PKB_FLAG_IP_DONE != 0 {
            return
        }
        if vlanState_ == .INVALID {
            flags |= PKB_FLAG_IP_FAIL | PKB_FLAG_IP_DONE
            return
        }
        if ethertype_ == ETHER_TYPE_ARP {
            let arpPtr: UnsafeMutablePointer<swvs_arp>? = getAs(ip_!, "arp")
            guard let arpPtr else {
                flags |= PKB_FLAG_IP_FAIL | PKB_FLAG_IP_DONE
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
                flags |= PKB_FLAG_IP_FAIL | PKB_FLAG_IP_DONE
                return
            }
            if arpPtr.pointee.be_arp_protocol != BE_ARP_PROTOCOL_TYPE_IP {
                assert(Logger.lowLevelDebug("arp, expecting protocol=ip, but got BE:\(arpPtr.pointee.be_arp_protocol)"))
                flags |= PKB_FLAG_IP_FAIL | PKB_FLAG_IP_DONE
                return
            }
            if arpPtr.pointee.arp_hlen != 6 {
                assert(Logger.lowLevelDebug("arp, expecting hlen=6, but got \(arpPtr.pointee.arp_hlen)"))
                flags |= PKB_FLAG_IP_FAIL | PKB_FLAG_IP_DONE
                return
            }
            if arpPtr.pointee.arp_plen != 4 {
                assert(Logger.lowLevelDebug("arp, expecting plen=4, but got \(arpPtr.pointee.arp_plen)"))
                flags |= PKB_FLAG_IP_FAIL | PKB_FLAG_IP_DONE
                return
            }

            ip4Src_ = IPv4(raw: &arpPtr.pointee.arp_sip)
            ip4Dst_ = IPv4(raw: &arpPtr.pointee.arp_tip)
            srcPort_ = Convert.reverseByteOrder(arpPtr.pointee.be_arp_opcode)
        } else if ethertype_ == ETHER_TYPE_IPv4 {
            let ipPtr: UnsafeMutablePointer<swvs_ipv4hdr>? = getAs(ip_!, "ipv4")
            guard let ipPtr else {
                flags |= PKB_FLAG_IP_FAIL | PKB_FLAG_IP_DONE
                return
            }

            let len = Int(ipPtr.pointee.version_ihl & 0x0f) * 4
            if len < 20 {
                assert(Logger.lowLevelDebug("ipv4 len=\(len) < 20"))
                flags |= PKB_FLAG_IP_FAIL | PKB_FLAG_IP_DONE
                return
            }
            if Convert.ptr2ptrUnsafe(ipPtr).advanced(by: len) - raw > pktlen {
                assert(Logger.lowLevelDebug("pktlen=\(pktlen) < ipv4 len=\(len)"))
                flags |= PKB_FLAG_IP_FAIL | PKB_FLAG_IP_DONE
                return
            }
            let totalLen = Int(Convert.reverseByteOrder(ipPtr.pointee.be_total_length))
            if totalLen < len {
                assert(Logger.lowLevelDebug("totalLen=\(totalLen) < len=\(len)"))
                flags |= PKB_FLAG_IP_FAIL | PKB_FLAG_IP_DONE
                return
            }
            let expectedPktlen = Convert.ptr2ptrUnsafe(ipPtr).advanced(by: totalLen) - raw
            if expectedPktlen > pktlen {
                assert(Logger.lowLevelDebug("totalLen=\(totalLen) will exceed pktlen=\(pktlen)"))
                flags |= PKB_FLAG_IP_FAIL | PKB_FLAG_IP_DONE
                return
            } else if expectedPktlen < pktlen {
                assert(Logger.lowLevelDebug("shrinks pktlen from \(pktlen) to \(expectedPktlen)"))
                tailroom += pktlen - expectedPktlen
                pktlen = expectedPktlen
            } else {
                assert(Logger.lowLevelDebug("totalLen=\(totalLen) exactly matches the pktlen"))
            }

            ip4Src_ = IPv4(raw: &ipPtr.pointee.src)
            ip4Dst_ = IPv4(raw: &ipPtr.pointee.dst)
            proto_ = ipPtr.pointee.proto
            upper_ = Convert.ptr2ptrUnsafe(ipPtr).advanced(by: len)
        } else if ethertype_ == ETHER_TYPE_IPv6 {
            let ipPtr: UnsafeMutablePointer<swvs_ipv6hdr>? = getAs(ip_!, "ipv6")
            guard let ipPtr else {
                flags |= PKB_FLAG_IP_FAIL | PKB_FLAG_IP_DONE
                return
            }

            let payloadLen = Int(Convert.reverseByteOrder(ipPtr.pointee.be_payload_len))
            let expectedPktlen = Convert.ptr2ptrUnsafe(ipPtr).advanced(by: 40).advanced(by: payloadLen) - raw
            if expectedPktlen > pktlen {
                assert(Logger.lowLevelDebug("payloadLen=\(payloadLen) will exceed pktlen=\(pktlen)"))
                flags |= PKB_FLAG_IP_FAIL | PKB_FLAG_IP_DONE
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
                flags |= PKB_FLAG_IP_FAIL | PKB_FLAG_IP_DONE
                return
            }

            ip6Src_ = IPv6(raw: &ipPtr.pointee.src)
            ip6Dst_ = IPv6(raw: &ipPtr.pointee.dst)
            (proto_, upper_) = tup
        } else {
            assert(Logger.lowLevelDebug("ether=\(ethertype_) no upper"))
            flags |= PKB_FLAG_IP_FAIL | PKB_FLAG_IP_DONE
            return
        }
        flags &= ~PKB_FLAG_IP_FAIL
        flags |= PKB_FLAG_IP_DONE
    }

    private func calcUpperInfo() {
        if flags & PKB_FLAG_UPPER_DONE != 0 {
            return
        }
        if flags & PKB_FLAG_IP_FAIL != 0 {
            flags |= PKB_FLAG_UPPER_FAIL | PKB_FLAG_UPPER_DONE
            return
        }
        if ethertype_ == ETHER_TYPE_IPv4 || ethertype_ == ETHER_TYPE_IPv6 {
            if proto_ == IP_PROTOCOL_TCP {
                let tcpPtr: UnsafeMutablePointer<swvs_tcphdr>? = getAs(upper_!, "tcp")
                guard let tcpPtr else {
                    flags |= PKB_FLAG_UPPER_FAIL | PKB_FLAG_UPPER_DONE
                    return
                }

                let len = Int((tcpPtr.pointee.data_off >> 4) & 0xf) * 4
                if len < 20 {
                    assert(Logger.lowLevelDebug("tcp data_off=\(len) < 20"))
                    flags |= PKB_FLAG_UPPER_FAIL | PKB_FLAG_UPPER_DONE
                    return
                }
                if Convert.ptr2ptrUnsafe(tcpPtr) + len - raw > pktlen {
                    assert(Logger.lowLevelDebug("pktlen=\(pktlen) not enough for tcp len=\(len)"))
                    flags |= PKB_FLAG_UPPER_FAIL | PKB_FLAG_UPPER_DONE
                    return
                }
                srcPort_ = Convert.reverseByteOrder(tcpPtr.pointee.be_src_port)
                dstPort_ = Convert.reverseByteOrder(tcpPtr.pointee.be_dst_port)
                app_ = Convert.ptr2ptrUnsafe(tcpPtr).advanced(by: len)
                appLen_ = UInt16(pktlen - (app_! - raw))
            } else if proto_ == IP_PROTOCOL_UDP {
                let udpPtr: UnsafeMutablePointer<swvs_udphdr>? = getAs(upper_!, "udp")
                guard let udpPtr else {
                    flags |= PKB_FLAG_UPPER_FAIL | PKB_FLAG_UPPER_DONE
                    return
                }

                let len = Int(Convert.reverseByteOrder(udpPtr.pointee.be_len))
                if len < 8 {
                    assert(Logger.lowLevelDebug("udp len=\(len) < 8"))
                    flags |= PKB_FLAG_UPPER_FAIL | PKB_FLAG_UPPER_DONE
                    return
                }
                let expectedPktlen = Convert.ptr2ptrUnsafe(udpPtr) + len - raw
                if expectedPktlen > pktlen {
                    assert(Logger.lowLevelDebug("pktlen=\(pktlen) not enough for udp len=\(len)"))
                    flags |= PKB_FLAG_UPPER_FAIL | PKB_FLAG_UPPER_DONE
                    return
                } else if expectedPktlen < pktlen {
                    assert(Logger.lowLevelDebug("shrink pktlen from \(pktlen) to \(expectedPktlen)"))
                    tailroom += pktlen - expectedPktlen
                    pktlen = expectedPktlen
                } else {
                    assert(Logger.lowLevelDebug("udpLen=\(len) exactly matches the pktlen"))
                }
                srcPort_ = Convert.reverseByteOrder(udpPtr.pointee.be_src_port)
                dstPort_ = Convert.reverseByteOrder(udpPtr.pointee.be_dst_port)
                app_ = Convert.ptr2ptrUnsafe(udpPtr.advanced(by: 1))
                appLen_ = UInt16(len - 8)
            } else if proto_ == IP_PROTOCOL_ICMP || proto_ == IP_PROTOCOL_ICMPv6 {
                let icmpPtr: UnsafeMutablePointer<swvs_icmp_hdr>? = getAs(upper_!, "icmp{4|6}")
                guard let icmpPtr else {
                    flags |= PKB_FLAG_UPPER_FAIL | PKB_FLAG_UPPER_DONE
                    return
                }

                srcPort_ = UInt16(icmpPtr.pointee.type)
                dstPort_ = UInt16(icmpPtr.pointee.code)
                app_ = Convert.ptr2ptrUnsafe(icmpPtr.advanced(by: 1))
                appLen_ = UInt16(pktlen - (app_! - raw))
            } else {
                assert(Logger.lowLevelDebug("unknown ip proto \(proto_)"))
                flags |= PKB_FLAG_UPPER_FAIL | PKB_FLAG_UPPER_DONE
                return
            }
            flags &= ~PKB_FLAG_UPPER_FAIL
            flags |= PKB_FLAG_UPPER_DONE
        } else {
            assert(Logger.lowLevelDebug("no upper level protocol for \(ethertype_)"))
            flags |= PKB_FLAG_UPPER_FAIL | PKB_FLAG_UPPER_DONE
        }
    }

    public func ensurePktInfo(level: PacketInfoLevel) {
        if level.rawValue >= PacketInfoLevel.ETHER.rawValue {
            calcEtherInfo()
        }
        if level.rawValue >= PacketInfoLevel.VLAN.rawValue {
            calcVlanInfo()
        }
        if level.rawValue >= PacketInfoLevel.IP.rawValue {
            calcIpInfo()
        }
        if level.rawValue >= PacketInfoLevel.UPPER.rawValue {
            calcUpperInfo()
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
            ret += "vlan=\(vlan_),"
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

public enum PacketInfoLevel: UInt8 {
    case ETHER
    case VLAN
    case IP // including arp
    case UPPER
}

public enum VlanState {
    case UNKNOWN
    case HAS_VLAN
    case NO_VLAN
    case REMOVED
    case INVALID
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
