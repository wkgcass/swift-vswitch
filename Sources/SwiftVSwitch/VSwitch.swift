import SwiftEventLoopCommon
import SwiftVSwitchCHelper
import VProxyChecksum
import VProxyCommon

public class VSwitch {
    public let loop: SelectorEventLoop
    private let params: VSwitchParams
    private var ifaces = [IfaceStore]()
    private var broadcastDomains = [UInt32: BroadcastDomain]()
    private var forEachPollEvent: ForEachPollEvent?

    public init(loop: SelectorEventLoop, params: VSwitchParams) {
        self.loop = loop
        self.params = params
    }

    public func start() {
        forEachPollEvent = ForEachPollEvent { self.handlePackets() }
        loop.forEachLoop(forEachPollEvent!)
    }

    public func stop() {
        if let forEachPollEvent {
            forEachPollEvent.valid = false
        }
    }

    private var packets: [PacketBuffer] = Arrays.newArray(capacity: 128)

    private func handlePackets() {
        // first round do not consider 'hasPackets' field
        var hasPackets = handlePacketsOneRound()
        var round = 0
        while hasPackets, round < 4096 { // maximum run 4096 times, to ensure other loop events handled
            round += 1
            hasPackets = handlePacketsOneRound()
        }
    }

    private func handlePacketsOneRound() -> Bool {
        var offset = 0
        for s in ifaces {
            let oldOffset = offset
            s.iface.dequeue(&packets, off: &offset)
            for i in oldOffset ..< offset {
                let p = packets[i]
                p.inputIface = s.iface
                if let bd = broadcastDomains[s.network] {
                    p.broadcastDomain = bd
                }
                p.csumState = s.iface.offload.rxcsum
                // statistics
                s.iface.statistics.rxbytes += UInt64(p.pktlen)
                s.iface.statistics.rxpkts += 1
            }
            if offset >= packets.count {
                break
            }
        }
        for i in 0 ..< offset {
            let pkb = packets[i]
            assert(Logger.lowLevelDebug("received packet: \(pkb)"))

            if csumDrop(pkb) {
                if let iface = pkb.inputIface {
                    iface.statistics.rxerrcsum += 1
                }
                continue
            }
            handleOnePacket(pkb)
        }
        for i in ifaces {
            i.iface.completeTx()
        }
        return offset > 0
    }

    private func csumDrop(_ pkb: PacketBuffer) -> Bool {
        if pkb.csumState == .COMPLETE || pkb.csumState == .UNNECESSARY {
            return false
        }
        // not valid ip packet
        guard let ip = pkb.ip else {
            return false
        }
        // not ip packet
        if pkb.ethertype != ETHER_TYPE_IPv4 && pkb.ethertype != ETHER_TYPE_IPv6 {
            return false
        }

        // get
        var ipCsum: (UInt8, UInt8) = (0, 0)
        if pkb.ethertype == ETHER_TYPE_IPv4 {
            let ip: UnsafePointer<swvs_ipv4hdr> = Convert.ptr2ptrUnsafe(ip)
            ipCsum = ip.pointee.csum
        }
        var checkUpper = false
        var upperCsum: (UInt8, UInt8) = (0, 0)
        if let upper = pkb.upper {
            if pkb.proto == IP_PROTOCOL_ICMP || pkb.proto == IP_PROTOCOL_ICMPv6 {
                let icmp: UnsafePointer<swvs_icmp_hdr> = Convert.ptr2ptrUnsafe(upper)
                upperCsum = icmp.pointee.csum
                if upperCsum.0 != 0 || upperCsum.1 != 0 {
                    checkUpper = true
                }
            } else if pkb.proto == IP_PROTOCOL_TCP {
                let tcp: UnsafePointer<swvs_tcphdr> = Convert.ptr2ptrUnsafe(upper)
                upperCsum = tcp.pointee.csum
                checkUpper = true
            } else if pkb.proto == IP_PROTOCOL_UDP {
                let udp: UnsafePointer<swvs_udphdr> = Convert.ptr2ptrUnsafe(upper)
                upperCsum = udp.pointee.csum
                if upperCsum.0 != 0 || upperCsum.1 != 0 {
                    checkUpper = true
                }
            }
        }

        // recalc
        vproxy_pkt_ether_csum(Convert.ptr2mutUnsafe(pkb.raw), Int32(pkb.pktlen), VPROXY_CSUM_ALL)

        // check
        if pkb.ethertype == ETHER_TYPE_IPv4 {
            let ip: UnsafePointer<swvs_ipv4hdr> = Convert.ptr2ptrUnsafe(ip)
            let newCsum = ip.pointee.csum
            if newCsum != ipCsum {
                assert(Logger.lowLevelDebug("invalid ip csum: expecting \(ipCsum), but got \(newCsum)"))
                return true
            }
        }
        if checkUpper, let upper = pkb.upper {
            if pkb.proto == IP_PROTOCOL_ICMP || pkb.proto == IP_PROTOCOL_ICMPv6 {
                let icmp: UnsafePointer<swvs_icmp_hdr> = Convert.ptr2ptrUnsafe(upper)
                let newCsum = icmp.pointee.csum
                if newCsum != upperCsum {
                    assert(Logger.lowLevelDebug("invalid icmp4|6 csum: expecting \(upperCsum), but got \(newCsum)"))
                    return true
                }
            } else if pkb.proto == IP_PROTOCOL_TCP {
                let tcp: UnsafePointer<swvs_tcphdr> = Convert.ptr2ptrUnsafe(upper)
                let newCsum = tcp.pointee.csum
                if newCsum != upperCsum {
                    assert(Logger.lowLevelDebug("invalid tcp csum: expecting \(upperCsum), but got \(newCsum)"))
                    return true
                }
            } else if pkb.proto == IP_PROTOCOL_UDP {
                let udp: UnsafePointer<swvs_udphdr> = Convert.ptr2ptrUnsafe(upper)
                let newCsum = udp.pointee.csum
                if newCsum != upperCsum {
                    assert(Logger.lowLevelDebug("invalid udp csum: expecting \(upperCsum), but got \(newCsum)"))
                    return true
                }
            }
        }

        // csum is ok (because it's recalculated) when reaches here
        assert(Logger.lowLevelDebug("csum is re-calculated"))
        pkb.csumState = .COMPLETE
        return false
    }

    private func handleOnePacket(_ pkb: PacketBuffer) {
        guard let bd = pkb.broadcastDomain else {
            assert(Logger.lowLevelDebug("no broadcast domain for \(pkb)"))
            return
        }
        guard let dstmac = pkb.dstmac, let srcmac = pkb.srcmac else {
            assert(Logger.lowLevelDebug("not ethernet packet: \(pkb)"))
            return
        }

        if let inputIface = pkb.inputIface {
            bd.macTable.record(mac: srcmac, iface: inputIface)
        }

        if !dstmac.isUnicast() {
            handleBroadcast(pkb)
            return
        }

        let target = bd.macTable.lookup(mac: dstmac)
        guard let target else {
            assert(Logger.lowLevelDebug("output iface not found for \(pkb)"))
            return
        }
        if let inputIface = pkb.inputIface {
            if target.handle() == inputIface.handle() {
                assert(Logger.lowLevelDebug("is reinput, drop the packet!!"))
                // must remove the entry
                bd.macTable.remove(mac: dstmac)
                return
            }
        }
        xmit(target, pkb)
    }

    private func handleBroadcast(_ pkb: PacketBuffer) {
        for (idx, s) in ifaces.enumerated() {
            if let inputIface = pkb.inputIface {
                if s.iface.handle() == inputIface.handle() {
                    // should not handle
                    continue
                }
            }
            if idx == ifaces.endIndex { // last iface, no need to clone
                xmit(s.iface, pkb)
            } else {
                let newPkb = PacketBuffer(pkb)
                xmit(s.iface, newPkb)
            }
        }
    }

    private func xmit(_ iface: any Iface, _ pkb: PacketBuffer) {
        // remove bridge related fields
        pkb.broadcastDomain = nil
        pkb.inputIface = nil

        // csum
        if iface.offload.txcsum == .COMPLETE {
            // can be offloaded
        } else if pkb.csumState == .COMPLETE {
            // already calculated
        } else if pkb.csumState == .UNNECESSARY, iface.offload.txcsum == .UNNECESSARY {
            // no need to calculate
        } else {
            // do re-calculate
            vproxy_pkt_ether_csum(Convert.ptr2mutUnsafe(pkb.raw), Int32(pkb.pktlen), VPROXY_CSUM_ALL)
            pkb.csumState = .COMPLETE
        }

        assert(Logger.lowLevelDebug("xmit packet: \(pkb) to \(iface.name)"))

        let ok = iface.enqueue(pkb)
        // statistics
        if !ok {
            assert(Logger.lowLevelDebug("failed to enqueue to \(iface.name)"))
            iface.statistics.txerr += 1
            return
        }
        iface.statistics.txbytes += UInt64(pkb.pktlen)
        iface.statistics.txpkts += 1
    }

    public func register(iface: any Iface, network: UInt32) throws(IOException) {
        if ifaces.contains(where: { i in i.iface.handle() == iface.handle() }) {
            return // already registered
        }
        try iface.initialize(IfaceInit(
            loop: loop,
            sw: self
        ))
        loop.runOnLoop {
            self.ifaces.append(IfaceStore(iface, network))
        }
    }

    public func remove(name: String) {
        loop.runOnLoop {
            for (idx, store) in self.ifaces.enumerated() {
                if store.iface.name == name {
                    self.broadcastDomains.values.forEach { b in b.remove(iface: store.iface) }
                    self.ifaces.remove(at: idx)
                    break
                }
            }
        }
    }

    public func ensureBroadcastDomain(network: UInt32) {
        loop.runOnLoop {
            if self.broadcastDomains.keys.contains(network) {
                return
            }
            self.broadcastDomains[network] = BroadcastDomain(loop: self.loop, params: self.params)
        }
    }

    public func removeBroadcastDomain(network: UInt32) {
        loop.runOnLoop {
            if let bd = self.broadcastDomains.removeValue(forKey: network) {
                bd.release()
            }
        }
    }
}

public struct IfaceInit {
    public let loop: SelectorEventLoop
    public let sw: VSwitch
}

struct IfaceStore {
    let iface: any Iface
    var network: UInt32
    init(_ iface: any Iface, _ network: UInt32) {
        self.iface = iface
        self.network = network
    }
}

public struct VSwitchParams {
    public var macTableTimeoutMillis: Int

    public init(macTableTimeoutMillis: Int = 300 * 1000) {
        self.macTableTimeoutMillis = macTableTimeoutMillis
    }
}

public let VSwitchDefaultPacketBufferSize = 2048
public let VSwitchReservedHeadroom = 256
