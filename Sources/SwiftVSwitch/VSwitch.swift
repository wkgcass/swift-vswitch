#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Collections
import SwiftEventLoopCommon
import SwiftVSwitchCHelper
import VProxyChecksum
import VProxyCommon

public class VSwitch {
    private let params: VSwitchParams
    private var threads: [VSwitchPerThread]
    private var master_: VSwitchPerThread? // is also inside 'threads' array
    private var master: VSwitchPerThread { master_! }

    public init(params: VSwitchParams) throws(IOException) {
        self.params = params
        let masterLoop = try SelectorEventLoop.open()

        threads = [VSwitchPerThread]()
        master_ = VSwitchPerThread(index: 0, loop: masterLoop, params: params, parent: self)
        threads.append(master)
        for (idx, coreAffinity) in params.coreAffinityMasksForEveryThreads.enumerated() {
            var opts = SelectorOptions()
            opts.coreAffinity = coreAffinity
            var loop: SelectorEventLoop
            do {
                loop = try SelectorEventLoop.open(opts: opts)
            } catch {
                for sw in threads {
                    sw.loop.close()
                }
                throw error
            }
            let perthread = VSwitchPerThread(index: idx, loop: loop, params: params, parent: self)
            threads.append(perthread)
        }
    }

    public func joinMasterThread() {
        master.loop.getRunningThread()!.join()
    }

    public func configure(_ f: @escaping (Int, VSwitchPerThread) -> Void) {
        master.loop.blockUntilFinish {
            for (tid, sw) in self.threads.enumerated() {
                f(tid, sw)
            }
        }
    }

    public func foreachWorker(_ f: @escaping (VSwitchPerThread) -> Void) {
        master.loop.runOnLoop {
            for i in 1 ..< self.threads.count {
                let sw = self.threads[i]
                sw.loop.runOnLoop { f(sw) }
            }
        }
    }

    public func start() {
        for sw in threads {
            sw.loop.loop { r in FDProvider.get().newThread(r) }
        }

        for (tid, sw) in threads.enumerated() {
            if tid == 0 {
                continue // do not start master
            }
            sw.start()
        }
    }

    public func stop() {
        for sw in threads {
            sw.stop()
        }
        for sw in threads {
            sw.loop.close()
        }
    }

    public func register(iface: any Iface, bridge: UInt32) throws(IOException) {
        if params.coreAffinityMasksForEveryThreads.count > 1 {
            throw IOException("cannot add a single iface to a multi-threaded vswitch")
        }
        try register(SingleThreadIfaceProvider(iface: iface), bridge: bridge)
    }

    public func register(iface: any Iface, netstack: UInt32) throws(IOException) {
        if params.coreAffinityMasksForEveryThreads.count > 1 {
            throw IOException("cannot add a single iface to a multi-threaded vswitch")
        }
        try register(SingleThreadIfaceProvider(iface: iface), netstack: netstack)
    }

    public func register(_ ifaceProvider: IfacePerThreadProvider, bridge: UInt32) throws(IOException) {
        try register(ifaceProvider) { sw, iface, params throws(IOException) in
            try sw.register(iface: iface, params: params, bridge: bridge)
        }
    }

    public func register(_ ifaceProvider: IfacePerThreadProvider, netstack: UInt32) throws(IOException) {
        try register(ifaceProvider) { sw, iface, params throws(IOException) in
            try sw.register(iface: iface, params: params, netstack: netstack)
        }
    }

    private func register(
        _ ifaceProvider: IfacePerThreadProvider,
        addToPerThreadSw: (VSwitchPerThread, any Iface, IfaceExParams) throws(IOException) -> Void
    ) throws(IOException) {
        var ifaceProvider = ifaceProvider
        var params = IfaceExParams(mac: MacAddress.random())
        var ifaceName: String?
        var meta: IfaceMetadata?
        var ifaceSelfMac: MacAddress?

        for (tid, sw) in threads.enumerated() {
            if tid == 0 {
                continue
            }
            if let iface = try ifaceProvider.provide(tid: tid) {
                ifaceName = iface.name
                meta = iface.meta
                if iface.meta.initialMac != nil {
                    ifaceSelfMac = iface.meta.initialMac
                }
                try addToPerThreadSw(sw, iface, params)
            } else {
                Logger.warn(.ALERT, "no iface provided for threads[\(tid)]")
            }
        }

        guard let ifaceName else {
            Logger.error(.IMPROPER_USE, "no iface provided")
            throw IOException("no iface provided")
        }
        if ifaceSelfMac != nil {
            params.mac = ifaceSelfMac!
        }
        let dummyIface = DummyIface(name: ifaceName, meta: meta!)
        try addToPerThreadSw(master, dummyIface, params)
    }

    public func ensureNetstack(id: UInt32) {
        if id == 0 { // should not use id==0
            return
        }
        let shared = NetStackShared(
            globalConntrack: GlobalConntrack(params: params)
        )
        for sw in threads {
            sw.ensureNetstack(id: id, shared: shared)
        }
    }
}

public class VSwitchPerThread {
    public let index: Int
    public let sw: VSwitch
    public let loop: SelectorEventLoop
    private let params: VSwitchParams
    private let ethswNodes: NodeManager
    private let netstackNodes: NetStackNodeManager
    public private(set) var ifaces = [String: IfaceEx]()
    public private(set) var bridges = [UInt32: Bridge]()
    public private(set) var netstacks = [UInt32: NetStack]()
    private let redirected = ConcurrentQueue<PacketBufferForRedirecting>()
    private var forEachPollEvent: ForEachPollEvent?
    private var helper_: VSwitchHelper?
    private var helper: VSwitchHelper {
        if helper_ == nil {
            helper_ = VSwitchHelper(sw: self)
        }
        return helper_!
    }

    init(index: Int, loop: SelectorEventLoop, params: VSwitchParams, parent: VSwitch) {
        self.index = index
        self.loop = loop
        self.params = params
        sw = parent
        ethswNodes = params.ethsw()
        netstackNodes = params.netstack()

        ethswNodes.initAllNodes(NodeInit())
        netstackNodes.initAllNodes(NodeInit())
    }

    public func start() {
        forEachPollEvent = ForEachPollEvent(Runnable.wrap { self.handlePackets() })
        loop.forEachLoop(forEachPollEvent!)
    }

    public func stop() {
        if let forEachPollEvent {
            forEachPollEvent.valid = false
        }
        helper_ = nil
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
        if round >= 4096 {
            loop.wakeup()
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
                    _ = ethswNodes.devInput.enqueue(p)
                } else if ex.toNetstack > 0 {
                    _ = netstackNodes.devInput.enqueue(p)
                } else {
                    Logger.shouldNotHappen("\(p) not toBridge nor toNetstack")
                }
            }
            if offset >= packets.count {
                break
            }
        }

        var sched = Scheduler(sw: helper, mgr: ethswNodes, ethswNodes.devInput)
        while sched.schedule() {}
        sched = Scheduler(sw: helper, mgr: netstackNodes, netstackNodes.devInput, netstackNodes.userInput)
        while sched.schedule() {}
        handleRedirected()
        loop.handleRunOnLoopEvents() // in case some jobs want to run

        return offset > 0
    }

    @inline(__always)
    private func handleRedirected() {
        // redirected packets should be coming from netstack
        var sched = Scheduler(sw: helper, mgr: netstackNodes)
        var hasRedirected = false
        while true {
            let re = redirected.pop()
            guard let re else { break }
            let pkb = re.pkb
            assert(pkb.conn != nil)
            if pkb.conn!.destroyed {
                assert(Logger.lowLevelDebug("conn is already destroyed \(pkb)"))
                continue
            }
            if !replaceObjectsForRedirectedPkb(pkb, re) {
                continue
            }
            if sched.addRedirected(pkb) { hasRedirected = true }
        }
        if hasRedirected { while sched.schedule() {} }
    }

    // NOTE: this function is called on another thread
    public func reenqueue(_ pkb: PacketBuffer) {
        // the packet would be redirected only if it's associated with a connection
        assert(pkb.conn != nil)

        var pkb = pkb
        if !pkb.buf.shareable() {
            pkb = PacketBuffer(pkb)
        }
        redirected.push(PacketBufferForRedirecting(pkb))
        loop.wakeup()
    }

    private func replaceObjectsForRedirectedPkb(_ pkb: PacketBuffer, _ r: PacketBufferForRedirecting) -> Bool {
        guard let ns = netstacks[r.netstack] else {
            assert(Logger.lowLevelDebug("unable to handle redirected packet, no netstack \(r.netstack) found"))
            return false
        }
        pkb.netstack = ns
        guard let inputIface = ifaces[r.inputIface] else {
            assert(Logger.lowLevelDebug("unable to handle redirected packet, no iface \(r.inputIface) found"))
            return false
        }
        pkb.inputIface = inputIface
        return true
    }

    func register(iface: any Iface, params: IfaceExParams, bridge: UInt32) throws(IOException) {
        if iface.meta.property.layer != .ETHER {
            throw IOException("\(iface.name) is not ethernet iface")
        }
        if ifaces.values.contains(where: { i in i.iface.handle() == iface.handle() }) {
            throw IOException("already registered")
        }
        try iface.initialize(IfaceInit(
            loop: loop
        ))
        loop.blockUntilFinish {
            self.ifaces[iface.name] = IfaceEx(iface, params: params, toBridge: bridge)
        }
    }

    func register(iface: any Iface, params: IfaceExParams, netstack: UInt32) throws(IOException) {
        if ifaces.values.contains(where: { i in i.iface.handle() == iface.handle() }) {
            throw IOException("already registered")
        }
        try iface.initialize(IfaceInit(
            loop: loop
        ))
        loop.blockUntilFinish {
            self.ifaces[iface.name] = IfaceEx(iface, params: params, toNetstack: netstack)
        }
    }

    public func remove(name: String) {
        loop.blockUntilFinish {
            if let ex = self.ifaces.removeValue(forKey: name) {
                ex.iface.close()
            }
        }
    }

    public func ensureBridge(id: UInt32) {
        if id == 0 { // should not use id==0
            return
        }
        loop.blockUntilFinish {
            if self.bridges.keys.contains(id) {
                return
            }
            self.bridges[id] = Bridge(id: id, loop: self.loop, params: self.params)
        }
    }

    public func removeBridge(id: UInt32) {
        loop.blockUntilFinish {
            if let br = self.bridges.removeValue(forKey: id) {
                br.release()
            }
        }
    }

    func ensureNetstack(id: UInt32, shared: NetStackShared) {
        if id == 0 { // should not use id==0
            return
        }
        loop.blockUntilFinish {
            if self.netstacks.keys.contains(id) {
                return
            }
            self.netstacks[id] = NetStack(id: id, sw: self, params: self.params, shared: shared)
        }
    }

    public func removeNetstack(id: UInt32) {
        loop.blockUntilFinish {
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
        loop.blockUntilFinish {
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
        loop.blockUntilFinish {
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
        loop.blockUntilFinish {
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
        loop.blockUntilFinish {
            guard let ns = self.netstacks[netstackId] else {
                Logger.warn(.INVALID_INPUT_DATA, "netstack \(netstackId) not found")
                return
            }
            ns.routeTable.delRule(rule)
        }
    }

    public struct VSwitchHelper {
        private var sw: VSwitchPerThread

        init(sw: VSwitchPerThread) {
            self.sw = sw
        }

        public var index: Int { sw.index }
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

        public func foreachWorker(_ f: @escaping (VSwitchPerThread) -> Void) {
            sw.sw.foreachWorker(f)
        }
    }
}

public struct IfaceInit {
    public let loop: SelectorEventLoop
}

public struct VSwitchParams {
    public var coreAffinityMasksForEveryThreads: [Int64]
    public var macTableTimeoutMillis: Int
    public var arpTableTimeoutMillis: Int
    public var arpRefreshCacheMillis: Int
    public var conntrackGlobalHashSize: Int

    public var ethsw: () -> NodeManager
    public var netstack: () -> NetStackNodeManager

    public init(
        coreAffinityMasksForEveryThreads: [Int64] = [-1], // one thread, no mask
        macTableTimeoutMillis: Int = 300 * 1000,
        arpTableTimeoutMillis: Int = 4 * 3600 * 1000,
        arpRefreshCacheMillis: Int = 60 * 1000,
        conntrackGlobalHashSize: Int = 1_048_576,
        ethsw: @escaping () -> NodeManager,
        netstack: @escaping () -> NetStackNodeManager
    ) {
        self.coreAffinityMasksForEveryThreads = coreAffinityMasksForEveryThreads
        self.macTableTimeoutMillis = macTableTimeoutMillis
        self.arpTableTimeoutMillis = arpTableTimeoutMillis
        self.arpRefreshCacheMillis = arpRefreshCacheMillis
        self.conntrackGlobalHashSize = conntrackGlobalHashSize
        self.ethsw = ethsw
        self.netstack = netstack
    }
}

public let VSwitchDefaultPacketBufferSize = ThreadMemPoolArraySize
public let VSwitchReservedHeadroom = 256
