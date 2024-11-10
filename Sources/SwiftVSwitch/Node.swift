import SwiftVSwitchCHelper
import VProxyChecksum
import VProxyCommon

open class Node: CustomStringConvertible, Equatable, Hashable {
    public let name: String
    public var packets: [UnownedPacketBuffer] = Arrays.newArray(capacity: 2048)
    public var offset = 0
    public var drop = NodeRef("drop")
    public var stolen = NodeRef("stolen")
    private var nodeInit_: NodeInit? = nil
    public var nodeInit: NodeInit { nodeInit_! }

    public init(name: String) {
        self.name = name
    }

    open func initGraph(mgr: NodeManager) {
        mgr.initRef(&drop)
        mgr.initRef(&stolen)
    }

    func initNode(nodeInit: NodeInit) {
        nodeInit_ = nodeInit
    }

    public func schedule(_ sched: inout Scheduler) {
        if offset == 0 {
            return
        }
        for i in 0 ..< offset {
            if let owned = packets[i].owned {
                schedule(owned, &sched)
            } else {
                schedule(packets[i].pkb, &sched)
            }
        }
        offset = 0
    }

    open func schedule(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        sched.schedule(pkb, to: drop)
    }

    open func enqueue(_ pkb: PacketBuffer) -> Bool {
        if offset >= packets.count {
            var packets: [UnownedPacketBuffer] = Arrays.newArray(capacity: packets.capacity * 2)
            for i in 0 ..< packets.count {
                packets[i] = self.packets[i]
            }
            self.packets = packets
        }
        if pkb.useOwned {
            packets[offset].owned = pkb
        } else {
            packets[offset].pkb = pkb
            packets[offset].owned = nil
        }
        offset += 1
        return true
    }

    public var description: String {
        return "Node(\(name))"
    }

    public func hash(into hasher: inout Hasher) {
        ObjectIdentifier(self).hash(into: &hasher)
    }

    public static func == (lhs: Node, rhs: Node) -> Bool {
        return lhs === rhs
    }
}

public struct UnownedPacketBuffer {
    public unowned var pkb: PacketBuffer
    public var owned: PacketBuffer?
}

public struct Scheduler {
    private unowned var drop: DropNode
    private unowned var stolen: StolenNode
    private unowned var devOutput: DevOutput
    private var nextNodes = Set<Node>()

    init(mgr: NodeManager, _ initialNodes: Node...) {
        drop = mgr.drop
        stolen = mgr.stolen
        devOutput = mgr.devOutput
        for n in initialNodes {
            nextNodes.insert(n)
        }
    }

    public mutating func schedule(_ pkb: PacketBuffer, to: NodeRef) {
        let node = to.node
        if node == devOutput || node == drop || node == stolen {
            _ = node.enqueue(pkb)
            return
        }
        if node.enqueue(pkb) {
            assert(Logger.lowLevelDebug("schedule \(Unmanaged.passUnretained(pkb).toOpaque()) to \(node.name) succeeded"))
            nextNodes.insert(node)
        } else {
            assert(Logger.lowLevelDebug("schedule \(Unmanaged.passUnretained(pkb).toOpaque()) to \(node.name) failed, drop now"))
            _ = drop.enqueue(pkb)
        }
    }

    mutating func schedule() -> Bool {
        if nextNodes.isEmpty {
            return false
        }
        let backup = nextNodes
        nextNodes = Set<Node>()
        for n in backup {
            n.schedule(&self)
        }
        return !nextNodes.isEmpty
    }
}

public struct NodeRef {
    public let name: String
    private unowned var node_: Node?
    var node: Node {
        if node_ == nil {
            assert(Logger.lowLevelDebug("node \(name) is nil !!!"))
        }
        return node_!
    }

    public init(_ name: String) {
        self.name = name
    }

    public mutating func set(_ n: Node) {
        node_ = n
    }
}

open class NodeManager {
    var storage = [String: Node]()
    var drop = DropNode()
    var stolen = StolenNode()
    var devOutput = DevOutput()
    var devInput: DevInput

    public init(_ devInput: DevInput) {
        self.devInput = devInput
        addNode(drop)
        addNode(stolen)
        addNode(devOutput)
        addNode(devInput)
        addNode(FastOutputNode())
    }

    public func addNode(_ node: Node) {
        storage[node.name] = node
    }

    public func initRef(_ ref: inout NodeRef) {
        let node = storage[ref.name]
        if node == nil {
            Logger.error(.IMPROPER_USE, "unable to find node with name \(ref.name), exiting ...")
        }
        ref.set(node!)
    }

    func initAllNodes(_ nodeInit: NodeInit) {
        for n in storage.values {
            n.initGraph(mgr: self)
        }
        for n in storage.values {
            n.initNode(nodeInit: nodeInit)
        }
    }
}

public class DummyNodeManager: NodeManager {
    public init() {
        super.init(DevInput())
    }
}

open class NetStackNodeManager: NodeManager {
    var userInput: UserInput

    public init(devInput: DevInput, userInput: UserInput) {
        self.userInput = userInput
        super.init(devInput)
    }
}

public class DummyNetStackNodeManager: NetStackNodeManager {
    public init() {
        super.init(devInput: DevInput(), userInput: UserInput())
    }
}

public struct NodeInit {
    public let sw: VSwitch.VSwitchHelper
}

open class DevInput: Node {
    public init() {
        super.init(name: "dev-input")
    }

    override public func schedule(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        guard let iface = pkb.inputIface else {
            assert(Logger.lowLevelDebug("inputIface not present in pkb"))
            return sched.schedule(pkb, to: drop)
        }

        // statistics
        iface.meta.statistics.rxbytes += UInt64(pkb.pktlen)
        iface.meta.statistics.rxpkts += 1

        if csumDrop(pkb) {
            iface.meta.statistics.rxerrcsum += 1
            return sched.schedule(pkb, to: drop)
        }
        return schedule0(pkb, &sched)
    }

    open func schedule0(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        return sched.schedule(pkb, to: drop)
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
}

class DropNode: Node {
    init() {
        super.init(name: "drop")
    }

    override public func enqueue(_ pkb: PacketBuffer) -> Bool {
        // do nothing, just drop the packet
        assert(Logger.lowLevelDebug("packet \(pkb) dropped"))
        return false
    }
}

class StolenNode: Node {
    init() {
        super.init(name: "stolen")
    }

    override public func enqueue(_ pkb: PacketBuffer) -> Bool {
        assert(Logger.lowLevelDebug("packet \(Unmanaged.passUnretained(pkb).toOpaque()) stolen"))
        return true
    }
}

class DevOutput: Node {
    init() {
        super.init(name: "dev-output")
    }

    override func initGraph(mgr: NodeManager) {
        super.initGraph(mgr: mgr)
    }

    override func enqueue(_ pkb: PacketBuffer) -> Bool {
        guard let iface = pkb.outputIface else {
            assert(Logger.lowLevelDebug("outputIface not specified"))
            return false
        }

        if let conn = pkb.conn {
            if conn.fastOutput.enabled && !conn.fastOutput.isValid {
                conn.fastOutput.outdev = iface
                if iface.meta.property.layer == .ETHER {
                    conn.fastOutput.outDstMac = pkb.dstmac!
                    conn.fastOutput.outSrcMac = pkb.srcmac!
                }
                conn.fastOutput.isValid = true
            }
        }

        // clear switch and iface related fields
        pkb.bridge = nil
        pkb.netstack = nil
        pkb.inputIface = nil
        // keep outputIface, the iface might need to use extra info

        // csum
        if iface.meta.offload.txcsum == .COMPLETE {
            // can be offloaded
        } else if pkb.csumState == .COMPLETE {
            // already calculated
        } else if pkb.csumState == .UNNECESSARY, iface.meta.offload.txcsum == .UNNECESSARY {
            // no need to calculate
        } else {
            // do re-calculate
            if iface.meta.property.layer == .IP {
                if let ip = pkb.ip {
                    var out = vproxy_csum_out()
                    if pkb.ethertype == ETHER_TYPE_IPv4 {
                        vproxy_pkt_ipv4_csum(Convert.ptr2mutUnsafe(ip), Int32(pkb.lengthFromIpToEnd), VPROXY_CSUM_ALL, &out)
                    } else if pkb.ethertype == ETHER_TYPE_IPv6 {
                        vproxy_pkt_ipv6_csum(Convert.ptr2mutUnsafe(ip), Int32(pkb.lengthFromIpToEnd), VPROXY_CSUM_ALL, &out)
                    }
                }
            } else {
                vproxy_pkt_ether_csum(Convert.ptr2mutUnsafe(pkb.raw), Int32(pkb.pktlen), VPROXY_CSUM_ALL)
            }
            pkb.csumState = .COMPLETE
        }

        assert(Logger.lowLevelDebug("xmit packet: \(pkb) to \(iface.name)"))

        let ok = iface.enqueue(pkb)
        // statistics
        if !ok {
            assert(Logger.lowLevelDebug("failed to enqueue to \(iface.name)"))
            iface.meta.statistics.txerr += 1
            return false
        }
        if iface.meta.property.layer == .IP {
            iface.meta.statistics.txbytes += UInt64(pkb.lengthFromIpToEnd)
        } else {
            iface.meta.statistics.txbytes += UInt64(pkb.pktlen)
        }
        iface.meta.statistics.txpkts += 1
        return true
    }
}

class FastOutputNode: Node {
    private var devOuptut = NodeRef("dev-output")

    public init() {
        super.init(name: "fast-output")
    }

    override func initGraph(mgr: NodeManager) {
        super.initGraph(mgr: mgr)
        mgr.initRef(&devOuptut)
    }

    override func schedule(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        assert(Logger.lowLevelDebug("into fast-output: \(pkb)"))

        let conn = pkb.conn!
        assert(conn.fastOutput.enabled)
        assert(conn.fastOutput.isValid)

        if conn.fastOutput.outdev!.meta.property.layer == .ETHER {
            guard let ether = pkb.ensureEthhdr() else {
                assert(Logger.lowLevelDebug("no room for ethernet header"))
                return sched.schedule(pkb, to: drop)
            }
            conn.fastOutput.outSrcMac.copyInto(&ether.pointee.src)
            conn.fastOutput.outDstMac.copyInto(&ether.pointee.dst)
        }
        pkb.outputIface = conn.fastOutput.outdev
        return sched.schedule(pkb, to: devOuptut)
    }
}

open class UserInput: Node {
    public init() {
        super.init(name: "user-input")
    }
    open override func enqueue(_ pkb: PacketBuffer) -> Bool {
        return false
    }
}
