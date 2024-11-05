import SwiftEventLoopCommon
import SwiftVSwitchCHelper
import VProxyChecksum
import VProxyCommon

public class VSwitch {
    public let loop: SelectorEventLoop
    private let params: VSwitchParams
    private var ifaces = [IfaceStore]()
    private var bridges = [UInt32: Bridge]()
    private var netstacks = [UInt32: NetStack]()
    private var forEachPollEvent: ForEachPollEvent?

    public init(loop: SelectorEventLoop, params: VSwitchParams) {
        self.loop = loop
        self.params = params

        params.ethsw.initAllNodes(NodeInit(
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
        while hasPackets && round < 4096 { // maximum run 4096 times, to ensure other loop events handled
            round += 1
            hasPackets = handlePacketsOneRound()
        }
        for i in ifaces {
            i.iface.completeTx()
        }
    }

    private var packets: [PacketBuffer] = Arrays.newArray(capacity: 8192)

    private func handlePacketsOneRound() -> Bool {
        var offset = 0
        for s in ifaces {
            let oldOffset = offset
            s.iface.dequeue(&packets, off: &offset)
            for i in oldOffset ..< offset {
                let p = packets[i]
                p.inputIface = s.iface
                if s.toBridge > 0 {
                    if let br = bridges[s.toBridge] {
                        p.bridge = br
                        p.toBridge = s.toBridge
                    }
                } else if s.toNetstack > 0 {
                    if let ns = netstacks[s.toNetstack] {
                        p.netstack = ns
                        p.toNetstack = s.toNetstack
                    }
                }
                p.csumState = s.iface.offload.rxcsum
            }
            if offset >= packets.count {
                break
            }
        }
        for i in 0 ..< offset {
            let pkb = packets[i]
            assert(Logger.lowLevelDebug("received packet: \(pkb)"))
            if pkb.toBridge == 0 && pkb.toNetstack == 0 {
                Logger.shouldNotHappen("not toBridge and not toNetstack")
                continue
            }
            _ = params.ethsw.devInput.enqueue(pkb)
        }

        var sched = Scheduler(params.ethsw.drop, params.ethsw.devInput)
        while sched.schedule() {}

        return offset > 0
    }

    public func register(iface: any Iface, bridge: UInt32) throws(IOException) {
        if iface.property.layer != .ETHER {
            throw IOException("\(iface.name) is not ethernet iface")
        }
        if ifaces.contains(where: { i in i.iface.handle() == iface.handle() }) {
            throw IOException("already registered")
        }
        try iface.initialize(IfaceInit(
            loop: loop
        ))
        loop.runOnLoop {
            self.ifaces.append(IfaceStore(iface, toBridge: bridge))
        }
    }

    public func register(iface: any Iface, netstack: UInt32) throws(IOException) {
        if ifaces.contains(where: { i in i.iface.handle() == iface.handle() }) {
            throw IOException("already registered")
        }
        try iface.initialize(IfaceInit(
            loop: loop
        ))
        loop.runOnLoop {
            self.ifaces.append(IfaceStore(iface, toNetstack: netstack))
        }
    }

    public func remove(name: String) {
        loop.runOnLoop {
            for (idx, store) in self.ifaces.enumerated() {
                if store.iface.name == name {
                    self.bridges.values.forEach { b in b.remove(iface: store.iface) }
                    self.ifaces.remove(at: idx)
                    store.iface.close()
                    break
                }
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

    public struct VSwitchHelper {
        private var sw: VSwitch

        init(sw: VSwitch) {
            self.sw = sw
        }

        public var bridges: [UInt32: Bridge] { sw.bridges }
        public var netstacks: [UInt32: NetStack] { sw.netstacks }
        public func foreachIface(in br: Bridge, _ f: (any Iface) -> Void) {
            for s in sw.ifaces {
                if sw.bridges[s.toBridge] !== br {
                    continue
                }
                f(s.iface)
            }
        }
    }
}

public struct IfaceInit {
    public let loop: SelectorEventLoop
}

struct IfaceStore {
    let iface: any Iface
    var toBridge: UInt32
    var toNetstack: UInt32

    init(_ iface: any Iface, toBridge: UInt32) {
        self.iface = iface
        self.toBridge = toBridge
        toNetstack = 0
    }

    init(_ iface: any Iface, toNetstack: UInt32) {
        self.iface = iface
        toBridge = 0
        self.toNetstack = toNetstack
    }
}

public struct VSwitchParams {
    public var macTableTimeoutMillis: Int
    public var ethsw: NodeManager

    public init(
        macTableTimeoutMillis: Int = 300 * 1000,
        ethsw: NodeManager
    ) {
        self.macTableTimeoutMillis = macTableTimeoutMillis
        self.ethsw = ethsw
    }
}

public let VSwitchDefaultPacketBufferSize = 2048
public let VSwitchReservedHeadroom = 256
