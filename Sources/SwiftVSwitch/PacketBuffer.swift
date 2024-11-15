#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import SwiftEventLoopCommon
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

    public private(set) var buf: BufRef
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
    private var ip4Src_ = IPv4.ANY
    private var ip4Dst_ = IPv4.ANY
    private var ip6Src_ = IPv6.ANY
    private var ip6Dst_ = IPv6.ANY
    private var proto_: UInt8 = 0
    private var srcPort_: UInt16 = 0
    private var dstPort_: UInt16 = 0
    private var appLen_: UInt16 = 0
    private var tup_: PktTuple? = nil

    public var conn: Connection? = nil

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

    public var tuple: PktTuple? {
        if flags & PKB_FLAG_UPPER_DONE == 0 {
            ensurePktInfo(level: .UPPER)
        }
        if flags & PKB_FLAG_UPPER_FAIL != 0 {
            return nil
        }
        if tup_ == nil {
            tup_ = PktTuple(proto: proto_, srcPort: srcPort_, dstPort: dstPort_,
                            srcIp: ipSrc!, dstIp: ipDst!)
        }
        return tup_
    }

    public init(buf: BufRef, pktlen: Int, headroom: Int, tailroom: Int, hasEthernet: Bool = true) {
        self.buf = buf
        let raw = buf.raw()
        self.raw = raw.advanced(by: headroom)
        self.pktlen = pktlen
        self.headroom = headroom
        self.tailroom = tailroom
        if !hasEthernet {
            flags |= PKB_FLAG_NO_ETHER
        }
    }

    public init(_ other: PacketBuffer) {
        useOwned = true

        bridge = other.bridge
        netstack = other.netstack

        inputIface = other.inputIface
        outputIface = other.outputIface
        outputRouteRule = other.outputRouteRule

        if other.headroom + other.pktlen + other.tailroom == ThreadMemPoolArraySize {
            buf = RawBufRef()
        } else {
            buf = ArrayBufRef(Arrays.newArray(capacity: other.headroom + other.pktlen + other.tailroom,
                                              uninitialized: true))
        }
        raw = buf.raw().advanced(by: other.headroom)
        memcpy(Unsafe.ptr2mutptr(buf.raw()),
               other.raw.advanced(by: -other.headroom),
               other.headroom + other.pktlen + other.tailroom)

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
        tup_ = other.tup_
        conn = other.conn
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
            if flags & PKB_FLAG_ETHER_DONE == 0 {
                ensurePktInfo(level: .ETHER)
            }
            return ether_ == nil ? nil : Unsafe.ptr2mutUnsafe(ether_!)
        }
        if !occpuyHeadroom(MemoryLayout<swvs_ethhdr>.stride) {
            return nil
        }
        ether_ = raw
        flags &= ~PKB_FLAG_ETHER_DONE
        flags &= ~PKB_FLAG_NO_ETHER
        return Unsafe.ptr2mutUnsafe(raw)
    }

    public func ensureVlan(_ vlan: UInt16) -> UnsafeMutablePointer<swvs_compose_eth_vlan>? {
        if hasEthernet {
            if vlanState_ != .NO_VLAN {
                return nil
            }
            if !occpuyHeadroom(MemoryLayout<swvs_vlantag>.stride) {
                return nil
            }
            let mut = Unsafe.ptr2mutptr(ether_!)
            memmove(mut.advanced(by: -4), mut, 12)
            vlanState_ = .REMOVED
            let ethvlan: UnsafeMutablePointer<swvs_compose_eth_vlan> = Unsafe.ptr2mutUnsafe(raw)
            ethvlan.pointee.ethhdr.be_type = BE_ETHER_TYPE_8021Q
            ethvlan.pointee.vlan.be_vid = Utils.byteOrderConvert(vlan)
            return Unsafe.ptr2mutUnsafe(raw)
        }
        if !occpuyHeadroom(MemoryLayout<swvs_compose_eth_vlan>.stride) {
            return nil
        }
        ether_ = raw
        let ethvlan: UnsafeMutablePointer<swvs_compose_eth_vlan> = Unsafe.ptr2mutUnsafe(raw)
        ethvlan.pointee.ethhdr.be_type = BE_ETHER_TYPE_8021Q
        ethvlan.pointee.vlan.be_vid = Utils.byteOrderConvert(vlan)
        ethvlan.pointee.vlan.be_type = Utils.byteOrderConvert(ethertype_)
        vlanState_ = .REMOVED
        flags &= ~PKB_FLAG_NO_ETHER
        flags &= ~PKB_FLAG_ETHER_DONE
        return Unsafe.ptr2mutUnsafe(raw)
    }

    public func removeVlan() {
        if !hasEthernet {
            return
        }
        if vlanState_ == .INVALID || vlanState_ == .NO_VLAN {
            return
        }
        let mut = Unsafe.ptr2mutptr(ether_!)
        memmove(mut.advanced(by: 4), mut, 14)
        _ = releaseHeadroom(MemoryLayout<swvs_vlantag>.stride)
        vlanState_ = .NO_VLAN
        ether_ = raw
    }

    public func convertToIPv4() -> UnsafeMutablePointer<swvs_ipv4hdr>? {
        if flags & PKB_FLAG_IP_DONE == 0 {
            ensurePktInfo(level: .IP)
        }
        if flags & PKB_FLAG_IP_FAIL != 0 {
            return nil
        }
        if ethertype == ETHER_TYPE_IPv4 {
            return Unsafe.ptr2mutUnsafe(ip_!)
        }
        if ethertype != ETHER_TYPE_IPv6 {
            return nil
        }
        let v6: UnsafePointer<swvs_ipv6hdr> = Unsafe.ptr2ptrUnsafe(ip_!)
        let hopLimits = v6.pointee.hop_limits

        let oldIp = ip_!
        ip_ = upper_!.advanced(by: -20)
        let count = oldIp - raw
        let delta = ip_! - oldIp
        let oldRaw = raw
        if delta > 0 {
            _ = releaseHeadroom(delta)
        } else { // maybe have a lot of ip options
            if !occpuyHeadroom(-delta) {
                assert(Logger.lowLevelDebug("unable to occupy headroom for ip6->ip4: \(-delta)"))
                return nil
            }
        }
        // +-----|--------+-----+-----+
        // |     |        |     |     |
        // raw newraw   oldIp   ip  upper
        let newRaw = Unsafe.ptr2mutptr(raw)
        memmove(newRaw, oldRaw, count)

        let v4: UnsafeMutablePointer<swvs_ipv4hdr> = Unsafe.ptr2mutUnsafe(ip_!)
        memset(v4, 0, 20)
        v4.pointee.version_ihl = 0x45
        v4.pointee.be_total_length = Utils.byteOrderConvert(UInt16(lengthFromIpToEnd))
        v4.pointee.time_to_live = hopLimits
        v4.pointee.proto = proto_
        ethertype_ = ETHER_TYPE_IPv4
        if ether_ != nil {
            ether_ = raw
            if vlanState_ != .NO_VLAN {
                let ethervlan: UnsafeMutablePointer<swvs_compose_eth_vlan> = Unsafe.ptr2mutUnsafe(ether_!)
                ethervlan.pointee.vlan.be_type = BE_ETHER_TYPE_IPv4
            } else {
                let ether: UnsafeMutablePointer<swvs_ethhdr> = Unsafe.ptr2mutUnsafe(ether_!)
                ether.pointee.be_type = BE_ETHER_TYPE_IPv4
            }
        }
        clearPacketInfo(only: .IP)
        return v4
    }

    public func convertToIPv6() -> UnsafeMutablePointer<swvs_ipv6hdr>? {
        if flags & PKB_FLAG_IP_DONE == 0 {
            ensurePktInfo(level: .IP)
        }
        if flags & PKB_FLAG_IP_FAIL != 0 {
            return nil
        }
        if ethertype == ETHER_TYPE_IPv6 {
            return Unsafe.ptr2mutUnsafe(ip_!)
        }
        if ethertype != ETHER_TYPE_IPv4 {
            return nil
        }
        let v4: UnsafePointer<swvs_ipv4hdr> = Unsafe.ptr2ptrUnsafe(ip_!)
        let ttl = v4.pointee.time_to_live

        let oldIp = ip_!
        ip_ = upper_!.advanced(by: -40)
        let count = oldIp - raw
        let delta = oldIp - ip_!
        let oldRaw = raw
        if delta > 0 {
            if !occpuyHeadroom(delta) {
                assert(Logger.lowLevelDebug("unable to occupy headroom for ip4->ip6: \(-delta)"))
                return nil
            }
        } else {
            _ = releaseHeadroom(-delta)
        }
        //   |-------+-----+---------+----------+
        //   |       |     |         |          |
        // newraw    ip   raw      oldIp      upper
        let newRaw = Unsafe.ptr2mutptr(raw)
        memmove(newRaw, oldRaw, count)

        let v6: UnsafeMutablePointer<swvs_ipv6hdr> = Unsafe.ptr2mutUnsafe(ip_!)
        memset(v6, 0, 40)
        v6.pointee.vtc_flow.0 = (6 << 4)
        v6.pointee.be_payload_len = Utils.byteOrderConvert(UInt16(lengthFromUpperToEnd))
        v6.pointee.next_hdr = proto_
        v6.pointee.hop_limits = ttl
        ethertype_ = ETHER_TYPE_IPv6
        if ether_ != nil {
            ether_ = raw
            if vlanState_ != .NO_VLAN {
                let ethervlan: UnsafeMutablePointer<swvs_compose_eth_vlan> = Unsafe.ptr2mutUnsafe(ether_!)
                ethervlan.pointee.vlan.be_type = BE_ETHER_TYPE_IPv6
            } else {
                let ether: UnsafeMutablePointer<swvs_ethhdr> = Unsafe.ptr2mutUnsafe(ether_!)
                ether.pointee.be_type = BE_ETHER_TYPE_IPv6
            }
        }
        clearPacketInfo(only: .IP)
        return v6
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
            tup_ = nil
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
            tup_ = nil
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
        if Unsafe.raw2ptr(p) + len - raw > pktlen {
            assert(Logger.lowLevelDebug("pktlen=\(pktlen) not enough for \(logHint)"))
            return nil
        }
        return Unsafe.raw2mutptr(p)
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

        ethertype_ = Utils.byteOrderConvert(etherPtr.pointee.be_type)
        dstmac_ = MacAddress(raw: Unsafe.ptr2ptrUnsafe(etherPtr))
        srcmac_ = MacAddress(raw: Unsafe.ptr2ptrUnsafe(etherPtr).advanced(by: 6))
        ether_ = raw
        ip_ = Unsafe.mut2ptrUnsafe(etherPtr.advanced(by: 1))
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

            vlan_ = Utils.byteOrderConvert(vlanPtr.pointee.be_vid)
            ethertype_ = Utils.byteOrderConvert(vlanPtr.pointee.be_type)

            ip_ = Unsafe.ptr2ptrUnsafe(vlanPtr.advanced(by: 1))
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

            let expectedPktlen = Unsafe.ptr2ptrUnsafe(arpPtr) + MemoryLayout<swvs_arp>.stride - raw
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
            srcPort_ = Utils.byteOrderConvert(arpPtr.pointee.be_arp_opcode)
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
            if Unsafe.ptr2ptrUnsafe(ipPtr).advanced(by: len) - raw > pktlen {
                assert(Logger.lowLevelDebug("pktlen=\(pktlen) < ipv4 len=\(len)"))
                flags |= PKB_FLAG_IP_FAIL | PKB_FLAG_IP_DONE
                return
            }
            let totalLen = Int(Utils.byteOrderConvert(ipPtr.pointee.be_total_length))
            if totalLen < len {
                assert(Logger.lowLevelDebug("totalLen=\(totalLen) < len=\(len)"))
                flags |= PKB_FLAG_IP_FAIL | PKB_FLAG_IP_DONE
                return
            }
            let expectedPktlen = Unsafe.ptr2ptrUnsafe(ipPtr).advanced(by: totalLen) - raw
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
            upper_ = Unsafe.ptr2ptrUnsafe(ipPtr).advanced(by: len)
        } else if ethertype_ == ETHER_TYPE_IPv6 {
            let ipPtr: UnsafeMutablePointer<swvs_ipv6hdr>? = getAs(ip_!, "ipv6")
            guard let ipPtr else {
                flags |= PKB_FLAG_IP_FAIL | PKB_FLAG_IP_DONE
                return
            }

            let payloadLen = Int(Utils.byteOrderConvert(ipPtr.pointee.be_payload_len))
            let expectedPktlen = Unsafe.ptr2ptrUnsafe(ipPtr).advanced(by: 40).advanced(by: payloadLen) - raw
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
                if Unsafe.ptr2ptrUnsafe(tcpPtr) + len - raw > pktlen {
                    assert(Logger.lowLevelDebug("pktlen=\(pktlen) not enough for tcp len=\(len)"))
                    flags |= PKB_FLAG_UPPER_FAIL | PKB_FLAG_UPPER_DONE
                    return
                }
                srcPort_ = Utils.byteOrderConvert(tcpPtr.pointee.be_src_port)
                dstPort_ = Utils.byteOrderConvert(tcpPtr.pointee.be_dst_port)
                app_ = Unsafe.ptr2ptrUnsafe(tcpPtr).advanced(by: len)
                appLen_ = UInt16(pktlen - (app_! - raw))
            } else if proto_ == IP_PROTOCOL_UDP {
                let udpPtr: UnsafeMutablePointer<swvs_udphdr>? = getAs(upper_!, "udp")
                guard let udpPtr else {
                    flags |= PKB_FLAG_UPPER_FAIL | PKB_FLAG_UPPER_DONE
                    return
                }

                let len = Int(Utils.byteOrderConvert(udpPtr.pointee.be_len))
                if len < 8 {
                    assert(Logger.lowLevelDebug("udp len=\(len) < 8"))
                    flags |= PKB_FLAG_UPPER_FAIL | PKB_FLAG_UPPER_DONE
                    return
                }
                let expectedPktlen = Unsafe.ptr2ptrUnsafe(udpPtr) + len - raw
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
                srcPort_ = Utils.byteOrderConvert(udpPtr.pointee.be_src_port)
                dstPort_ = Utils.byteOrderConvert(udpPtr.pointee.be_dst_port)
                app_ = Unsafe.ptr2ptrUnsafe(udpPtr.advanced(by: 1))
                appLen_ = UInt16(len - 8)
            } else if proto_ == IP_PROTOCOL_ICMP || proto_ == IP_PROTOCOL_ICMPv6 {
                let icmpPtr: UnsafeMutablePointer<swvs_icmp_hdr>? = getAs(upper_!, "icmp{4|6}")
                guard let icmpPtr else {
                    flags |= PKB_FLAG_UPPER_FAIL | PKB_FLAG_UPPER_DONE
                    return
                }

                srcPort_ = UInt16(icmpPtr.pointee.type)
                dstPort_ = UInt16(icmpPtr.pointee.code)
                app_ = Unsafe.ptr2ptrUnsafe(icmpPtr.advanced(by: 1))
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
            return (hdr, Unsafe.ptr2ptrUnsafe(v6.advanced(by: 1)))
        }
        let hdrptr: UnsafePointer<swvs_ipv6nxthdr> = Unsafe.ptr2ptrUnsafe(v6.advanced(by: 1))
        if Unsafe.ptr2ptrUnsafe(hdrptr) + 8 - raw > pktlen {
            assert(Logger.lowLevelDebug("pktlen=\(pktlen) not enough for nexthdr \(hdrptr)"))
            return nil
        }
        if Unsafe.ptr2ptrUnsafe(hdrptr) + 8 + Int(hdrptr.pointee.len) - raw > pktlen {
            assert(Logger.lowLevelDebug("pktlen=\(pktlen) not enough for nexthdr \(hdrptr) len=\(hdrptr.pointee.len)"))
            return nil
        }
        return skipIPv6NextHeaders(hdrptr)
    }

    private func skipIPv6NextHeaders(_ hdrptr: UnsafePointer<swvs_ipv6nxthdr>) -> (UInt8, UnsafePointer<UInt8>)? {
        let p: UnsafePointer<UInt8> = Unsafe.ptr2ptrUnsafe(hdrptr)
        let nxt = p.advanced(by: Int(8 + hdrptr.pointee.len))
        if !IPv6_needs_next_header.contains(hdrptr.pointee.next_hdr) {
            return (hdrptr.pointee.next_hdr, nxt)
        }
        if Unsafe.ptr2ptrUnsafe(nxt) + 8 - raw > pktlen {
            assert(Logger.lowLevelDebug("pktlen=\(pktlen) not enough for nexthdr \(nxt)"))
            return nil
        }
        let nxtPtr: UnsafePointer<swvs_ipv6nxthdr> = Unsafe.ptr2ptrUnsafe(nxt)
        if Unsafe.raw2ptr(nxt) + 8 + Int(nxtPtr.pointee.len) - raw > pktlen {
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

public class PacketBufferForRedirecting {
    public let pkb: PacketBuffer
    public var netstack: UInt32
    public var inputIface: String
    init(_ pkb: PacketBuffer) {
        self.pkb = pkb
        netstack = pkb.netstack!.id
        inputIface = pkb.inputIface!.name
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

open class BufRef {
    public init() {}

    open func raw() -> UnsafePointer<UInt8> {
        return UnsafePointer(bitPattern: 0)!
    }

    open func shareable() -> Bool {
        return false
    }

    open func doDeinit() {}

    deinit {
        doDeinit()
    }
}

public class ArrayBufRef: BufRef {
    public var array: [UInt8]

    public init(_ array: [UInt8]) {
        self.array = array
    }

    override public func raw() -> UnsafePointer<UInt8> {
        return Unsafe.mut2ptr(Arrays.getRaw(from: array))
    }

    override public func shareable() -> Bool {
        return true
    }
}

public class RawBufRef: BufRef {
    public let index: Int
    private let raw_: UnsafePointer<UInt8>

    override public init() {
        let thread = FDProvider.get().currentThread()
        if let thread, let res = thread.memPool.get() {
            index = res.0
            raw_ = Unsafe.mut2ptr(res.1)
        } else {
            index = -1
            let m = malloc(VSwitchDefaultPacketBufferSize)!
            raw_ = Unsafe.mutraw2ptr(m)
        }
    }

    override public func raw() -> UnsafePointer<UInt8> {
        return raw_
    }

    override public func shareable() -> Bool {
        return index == -1
    }

    override public func doDeinit() {
        if index == -1 {
            free(Unsafe.ptr2mutraw(raw_))
        } else {
            let thread = FDProvider.get().currentThread()!
            thread.memPool.store(index)
        }
    }
}
