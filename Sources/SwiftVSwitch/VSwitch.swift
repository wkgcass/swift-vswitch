import SwiftEventLoopCommon
import SwiftVSwitchCHelper
import VProxyChecksum
import VProxyCommon

public class VSwitch {
    public let loop: SelectorEventLoop
    private let params: VSwitchParams
    public private(set) var ifaces = [String: IfaceEx]()
    public private(set) var bridges = [UInt32: Bridge]()
    public private(set) var netstacks = [UInt32: NetStack]()
    private var forEachPollEvent: ForEachPollEvent?

    public init(loop: SelectorEventLoop, params: VSwitchParams) {
        self.loop = loop
        self.params = params

        params.ethsw.initAllNodes(NodeInit(
            sw: VSwitchHelper(sw: self)
        ))
        params.netstack.initAllNodes(NodeInit(
            sw: VSwitchHelper(sw: self)
        ))
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

    private func handlePackets() {
        var hasPackets = handlePacketsOneRound()
        var round = 1
        while hasPackets, round < 4096 { // maximum run 4096 times, to ensure other loop events handled
            round += 1
            hasPackets = handlePacketsOneRound()
        }
        for i in ifaces.values {
            i.iface.completeTx()
        }
    }

    private var packets: [PacketBuffer] = Arrays.newArray(capacity: 8192)

    private func handlePacketsOneRound() -> Bool {
        var offset = 0
        for ex in ifaces.values {
            let oldOffset = offset
            ex.iface.dequeue(&packets, off: &offset)
            for i in oldOffset ..< offset {
                let p = packets[i]
                assert(Logger.lowLevelDebug("received packet: \(p)"))

                p.inputIface = ex
                p.csumState = ex.iface.meta.offload.rxcsum

                if ex.toBridge > 0 {
                    _ = params.ethsw.devInput.enqueue(p)
                } else if ex.toNetstack > 0 {
                    _ = params.netstack.devInput.enqueue(p)
                } else {
                    Logger.shouldNotHappen("\(p) not toBridge nor toNetstack")
                }
            }
            if offset >= packets.count {
                break
            }
        }

        var sched = Scheduler(mgr: params.ethsw, params.ethsw.devInput)
        while sched.schedule() {}
        sched = Scheduler(mgr: params.netstack, params.netstack.devInput, params.netstack.userInput)
        while sched.schedule() {}

        return offset > 0
    }

    public func register(iface: any Iface, bridge: UInt32) throws(IOException) {
        if iface.meta.property.layer != .ETHER {
            throw IOException("\(iface.name) is not ethernet iface")
        }
        if ifaces.values.contains(where: { i in i.iface.handle() == iface.handle() }) {
            throw IOException("already registered")
        }
        try iface.initialize(IfaceInit(
            loop: loop
        ))
        loop.runOnLoop {
            self.ifaces[iface.name] = IfaceEx(iface, toBridge: bridge)
        }
    }

    public func register(iface: any Iface, netstack: UInt32) throws(IOException) {
        if ifaces.values.contains(where: { i in i.iface.handle() == iface.handle() }) {
            throw IOException("already registered")
        }
        try iface.initialize(IfaceInit(
            loop: loop
        ))
        loop.runOnLoop {
            self.ifaces[iface.name] = IfaceEx(iface, toNetstack: netstack)
        }
    }

    public func remove(name: String) {
        loop.runOnLoop {
            if let ex = self.ifaces.removeValue(forKey: name) {
                ex.iface.close()
            }
        }
    }

    public func ensureBridge(id: UInt32) {
        if id == 0 { // should not use id==0
            return
        }
        loop.runOnLoop {
            if self.bridges.keys.contains(id) {
                return
            }
            self.bridges[id] = Bridge(loop: self.loop, params: self.params)
        }
    }

    public func removeBridge(id: UInt32) {
        loop.runOnLoop {
            if let br = self.bridges.removeValue(forKey: id) {
                br.release()
            }
        }
    }

    public func ensureNetstack(id: UInt32) {
        if id == 0 { // should not use id==0
            return
        }
        loop.runOnLoop {
            if self.netstacks.keys.contains(id) {
                return
            }
            self.netstacks[id] = NetStack(loop: self.loop, params: self.params)
        }
    }

    public func removeNetstack(id: UInt32) {
        loop.runOnLoop {
            if let n = self.netstacks.removeValue(forKey: id) {
                n.release()
            }
        }
    }

    private func getDevAndNetstack(dev: String) -> (IfaceEx, NetStack)? {
        guard let iface = ifaces[dev] else {
            Logger.warn(.INVALID_INPUT_DATA, "dev \(dev) not found")
            return nil
        }
        if iface.toNetstack == 0 {
            Logger.warn(.INVALID_INPUT_DATA, "dev \(dev) is not targeting netstack")
            return nil
        }
        guard let ns = netstacks[iface.toNetstack] else {
            Logger.warn(.INVALID_INPUT_DATA, "netstack \(iface.toNetstack) for \(dev) not found")
            return nil
        }
        return (iface, ns)
    }

    public func addAddress(_ ip: (any IP)?, dev: String) {
        guard let ip else {
            return
        }
        loop.runOnLoop {
            guard let (iface, ns) = self.getDevAndNetstack(dev: dev) else {
                return
            }
            ns.addIp(ip, dev: iface)
        }
    }

    public func delAddress(_ ip: (any IP)?, dev: String) {
        guard let ip else {
            return
        }
        loop.runOnLoop {
            guard let (iface, ns) = self.getDevAndNetstack(dev: dev) else {
                return
            }
            ns.removeIp(ip, dev: iface)
        }
    }

    public func addRoute(_ rule: any Network, dev: String, src: any IP) {
        if (rule is NetworkV4 && src is IPv6) || (rule is NetworkV6 && src is IPv4) {
            Logger.warn(.INVALID_INPUT_DATA, "AF of \(rule) and \(src) mismatch")
            return
        }
        loop.runOnLoop {
            guard let (iface, ns) = self.getDevAndNetstack(dev: dev) else {
                return
            }
            ns.routeTable.addRule(RouteTable.RouteRule(rule: rule, dev: iface, src: src))
        }
    }

    public func delRoute(_ rule: any Network, netstackId: UInt32) {
        if netstackId == 0 {
            return
        }
        loop.runOnLoop {
            guard let ns = self.netstacks[netstackId] else {
                Logger.warn(.INVALID_INPUT_DATA, "netstack \(netstackId) not found")
                return
            }
            ns.routeTable.delRule(rule)
        }
    }

    public struct VSwitchHelper {
        private var sw: VSwitch

        init(sw: VSwitch) {
            self.sw = sw
        }

        public var bridges: [UInt32: Bridge] { sw.bridges }
        public var netstacks: [UInt32: NetStack] { sw.netstacks }
        public func foreachIface(in br: Bridge, _ f: (IfaceEx) -> Void) {
            for ex in sw.ifaces.values {
                if sw.bridges[ex.toBridge] !== br {
                    continue
                }
                f(ex)
            }
        }
    }
}

public struct IfaceInit {
    public let loop: SelectorEventLoop
}

public struct VSwitchParams {
    public var macTableTimeoutMillis: Int
    public var arpTableTimeoutMillis: Int
    public var arpRefreshCacheMillis: Int

    public var ethsw: NodeManager
    public var netstack: NetStackNodeManager

    public init(
        macTableTimeoutMillis: Int = 300 * 1000,
        arpTableTimeoutMillis: Int = 4 * 3600 * 1000,
        arpRefreshCacheMillis: Int = 60 * 1000,
        ethsw: NodeManager,
        netstack: NetStackNodeManager
    ) {
        self.macTableTimeoutMillis = macTableTimeoutMillis
        self.arpTableTimeoutMillis = arpTableTimeoutMillis
        self.arpRefreshCacheMillis = arpRefreshCacheMillis
        self.ethsw = ethsw
        self.netstack = netstack
    }
}

public let VSwitchDefaultPacketBufferSize = ThreadMemPoolArraySize
public let VSwitchReservedHeadroom = 256
