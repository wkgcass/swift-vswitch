import SwiftVSwitchCHelper
import VProxyChecksum
import VProxyCommon

open class Node: CustomStringConvertible, Equatable, Hashable {
    public let name: String
    public var packets: [UnownedPacketBuffer] = Arrays.newArray(capacity: 2048)
    public var offset = 0
    public var drop = NodeRef("drop")
    private var nodeInit_: NodeInit? = nil
    public var nodeInit: NodeInit { nodeInit_! }

    public init(name: String) {
        self.name = name
    }

    open func initGraph(mgr: NodeManager) {
        mgr.initNode(&drop)
    }

    func initNode(nodeInit: NodeInit) {
        nodeInit_ = nodeInit
    }

    public func schedule(_ sched: inout Scheduler) {
        if offset == 0 {
            return
        }
        for i in 0 ..< offset {
            schedule(packets[i].pkb, &sched)
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
        packets[offset].pkb = pkb
        offset += 1
        return true
    }

    public var description: String {
        return "Node(\(name)"
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
}

public struct Scheduler {
    private var drop: DropNode
    private var nextNodes = Set<Node>()

    init(_ drop: DropNode, _ initialNodes: Node...) {
        self.drop = drop
        for n in initialNodes {
            nextNodes.insert(n)
        }
    }

    public mutating func schedule(_ pkb: PacketBuffer, to: NodeRef) {
        let node = to.node
        if node.enqueue(pkb) {
            nextNodes.insert(node)
        } else if node != drop {
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
    var node: Node { node_! }

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
    var devOutput = DevOutput()
    var devInput: DevInput

    public init(_ devInput: DevInput) {
        self.devInput = devInput
        addNode(drop)
        addNode(devOutput)
        addNode(devInput)
    }

    public func addNode(_ node: Node) {
        storage[node.name] = node
    }

    public func initNode(_ ref: inout NodeRef) {
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

public struct NodeInit {
    public let sw: VSwitch.VSwitchHelper
}

open class DevInput: Node {
    public init() {
        super.init(name: "dev-input")
    }

    override public func schedule(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        // statistics
        if let iface = pkb.inputIface {
            iface.statistics.rxbytes += UInt64(pkb.pktlen)
            iface.statistics.rxpkts += 1
        }

        if csumDrop(pkb) {
            if let iface = pkb.inputIface {
                iface.statistics.rxerrcsum += 1
            }
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

    override public func enqueue(_: PacketBuffer) -> Bool {
        // do nothing, just drop the packet
        assert(Logger.lowLevelDebug("drop packet"))
        return false
    }
}

class DevOutput: Node {
    init() {
        super.init(name: "dev-output")
    }

    override func enqueue(_ pkb: PacketBuffer) -> Bool {
        guard let iface = pkb.outputIface else {
            assert(Logger.lowLevelDebug("outputIface not specified"))
            return false
        }

        // clear switch and iface related fields
        pkb.bridge = nil
        pkb.inputIface = nil
        pkb.outputIface = nil
        pkb.toBridge = 0
        pkb.toNetstack = 0

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
            return false
        }
        iface.statistics.txbytes += UInt64(pkb.pktlen)
        iface.statistics.txpkts += 1
        return true
    }
}