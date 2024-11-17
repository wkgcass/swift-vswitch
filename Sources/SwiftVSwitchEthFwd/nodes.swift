import SwiftVSwitch
import VProxyCommon

public class EthernetFwdNodeManager: NodeManager {
    public init() {
        super.init(DevInput())
        addNode(EthernetInput())
        addNode(VLanInput())
        addNode(MulticastInput())
        addNode(BroadcastInput())
        addNode(BroadcastOutput())
        addNode(UnicastInput())
        addNode(FloodOutput())
    }
}

class DevInput: SwiftVSwitch.DevInput {
    private var ethernetInput = NodeRef("ethernet-input")

    override public func initGraph(mgr: NodeManager) {
        super.initGraph(mgr: mgr)
        mgr.initRef(&ethernetInput)
    }

    override public func schedule0(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        if pkb.dstmac == nil {
            assert(Logger.lowLevelDebug("not ethernet packet"))
            return sched.schedule(pkb, to: drop)
        }
        return sched.schedule(pkb, to: ethernetInput)
    }
}

class EthernetInput: Node {
    private var broadcastInput = NodeRef("broadcast-input")
    private var multicastInput = NodeRef("multicast-input")
    private var unicastInput = NodeRef("unicast-input")
    private var vlanInput = NodeRef("vlan-input")

    init() {
        super.init(name: "ethernet-input")
    }

    override func initGraph(mgr: NodeManager) {
        super.initGraph(mgr: mgr)
        mgr.initRef(&broadcastInput)
        mgr.initRef(&multicastInput)
        mgr.initRef(&unicastInput)
        mgr.initRef(&vlanInput)
    }

    override public func schedule(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        if pkb.vlanState == .HAS_VLAN {
            return sched.schedule(pkb, to: vlanInput)
        }

        guard let bridge = sched.sw.bridges[pkb.inputIface!.toBridge] else {
            assert(Logger.lowLevelDebug("bridge not found \(pkb.inputIface!.toBridge)"))
            return sched.schedule(pkb, to: drop)
        }
        pkb.bridge = bridge

        let dstmac = pkb.dstmac!
        let srcmac = pkb.srcmac!
        let bridgeId = bridge.id
        let ifid = pkb.inputIface!.id
        sched.sw.foreachWorker { sw in
            if let bridge = sw.bridges[bridgeId], let inputIface = sw.ifaces[ifid] {
                bridge.macTable.record(mac: srcmac, iface: inputIface)
            }
        }

        if dstmac.isBroadcast() {
            return sched.schedule(pkb, to: broadcastInput)
        } else if dstmac.isMulticast() {
            return sched.schedule(pkb, to: multicastInput)
        } else {
            return sched.schedule(pkb, to: unicastInput)
        }
    }
}

class VLanInput: Node {
    private var ethernetInput = NodeRef("ethernet-input")

    init() {
        super.init(name: "vlan-input")
    }

    override func initGraph(mgr: NodeManager) {
        super.initGraph(mgr: mgr)
        mgr.initRef(&ethernetInput)
    }

    override func schedule(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        // TODO: support vlan sub interface
        return sched.schedule(pkb, to: drop)
    }
}

class MulticastInput: Node {
    private var broadcastOutput = NodeRef("broadcast-output")

    init() {
        super.init(name: "multicast-input")
    }

    override func initGraph(mgr: NodeManager) {
        super.initGraph(mgr: mgr)
        mgr.initRef(&broadcastOutput)
    }

    override func schedule(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        return sched.schedule(pkb, to: broadcastOutput)
    }
}

class BroadcastInput: Node {
    private var broadcastOutput = NodeRef("broadcast-output")

    init() {
        super.init(name: "broadcast-input")
    }

    override func initGraph(mgr: NodeManager) {
        super.initGraph(mgr: mgr)
        mgr.initRef(&broadcastOutput)
    }

    override func schedule(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        return sched.schedule(pkb, to: broadcastOutput)
    }
}

class BroadcastOutput: Node {
    private var devOutput = NodeRef("dev-output")

    init() {
        super.init(name: "broadcast-output")
    }

    override func initGraph(mgr: NodeManager) {
        super.initGraph(mgr: mgr)
        mgr.initRef(&devOutput)
    }

    override func schedule(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        sched.sw.foreachIface(in: pkb.bridge!) { iface in
            if iface.handle() == pkb.inputIface!.handle() {
                return
            }
            let newPkb = PacketBuffer(pkb)
            newPkb.outputIface = iface
            sched.schedule(newPkb, to: devOutput)
        }
    }
}

class UnicastInput: Node {
    private var devOutput = NodeRef("dev-output")
    private var floodOutput = NodeRef("flood-output")

    init() {
        super.init(name: "unicast-input")
    }

    override func initGraph(mgr: NodeManager) {
        super.initGraph(mgr: mgr)
        mgr.initRef(&devOutput)
        mgr.initRef(&floodOutput)
    }

    override func schedule(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        let outputDev = pkb.bridge!.macTable.lookup(mac: pkb.dstmac!)
        guard let outputDev else {
            assert(Logger.lowLevelDebug("unable to find output iface"))
            return sched.schedule(pkb, to: floodOutput)
        }

        // prevent outputDev equals inputDev
        if outputDev.handle() == pkb.inputIface!.handle() {
            assert(Logger.lowLevelDebug("input and output ifaces are the same, need to remove mac entry"))
            pkb.bridge!.macTable.remove(mac: pkb.dstmac!)
            return sched.schedule(pkb, to: drop)
        }

        pkb.outputIface = outputDev
        return sched.schedule(pkb, to: devOutput)
    }
}

class FloodOutput: Node {
    private var broadcastOutput = NodeRef("broadcast-output")

    init() {
        super.init(name: "flood-output")
    }

    override func initGraph(mgr: NodeManager) {
        super.initGraph(mgr: mgr)
        mgr.initRef(&broadcastOutput)
    }

    override func schedule(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        return sched.schedule(pkb, to: broadcastOutput)
    }
}
