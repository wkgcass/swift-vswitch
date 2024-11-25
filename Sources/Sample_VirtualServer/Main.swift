import ArgumentParser
import SwiftEventLoopCommon
import SwiftEventLoopPosix
import SwiftVSwitch
import SwiftVSwitchControlPlane
import SwiftVSwitchNetStack
import SwiftVSwitchTunTap
import VProxyCommon

@main
struct Main {
    static func main() async {
        await VirtualServerSample.main()
    }
}

struct VirtualServerSample: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A sample virtual server.")

    @Option(help: "Choose to use tap or tun.") var type: String
    @Option(help: "Device name or pattern.") var devName: String
    @Option(help: "(IP/Mask)s separated by `,`.") var vip: String
    @Option(help: "Port for the virtual server.") var port: UInt16
    @Option(help: "Dest (ip:port{weight})s separated by `,`.") var dest: String
    @Option(help: "Core affinity, which is a list of bitmasks separated by `,`.") var coreAffinity: String?

    func validate() throws {
        if type != "tap" && type != "tun" {
            throw ValidationError("type should be tap|tun, but got \(type)")
        }
        let split = vip.split(separator: ",")
        for (idx, vipmask) in split.enumerated() {
            if GetIPMask(from: String(vipmask)) == nil {
                throw ValidationError("vip[\(idx)]=\(vipmask) is not a valid ip/mask")
            }
        }
        let destSplit = dest.split(separator: ",")
        for (idx, ipportweight) in destSplit.enumerated() {
            var ipportStr = String(ipportweight)
            var weightStr = "10"
            let braceIdx = ipportweight.firstIndex(of: "{")
            if let braceIdx {
                if !ipportweight.hasSuffix("}") {
                    throw ValidationError("dest[\(idx)]=\(ipportweight) is not a valid ip:port{weight}, contains `{` but does not end with `}`")
                }
                weightStr = String(ipportweight[ipportweight.index(braceIdx, offsetBy: 1) ..< ipportweight.index(before: ipportweight.endIndex)])
                ipportStr = String(ipportweight[..<braceIdx])
            }

            if GetIPPort(from: String(ipportStr)) == nil {
                throw ValidationError("dest[\(idx)]=\(ipportweight) doesn't contain valid ip:port: \(ipportStr)")
            }
            let weight = Int(weightStr)
            if weight == nil {
                throw ValidationError("dest[\(idx)]=\(ipportweight) doesn't contain valid weight: \(weightStr)")
            }
        }
        if let coreAffinity {
            let coreAffinitySplit = coreAffinity.split(separator: ",")
            for (idx, coreAffinity) in coreAffinitySplit.enumerated() {
                let n = Int64(coreAffinity)
                if n == nil {
                    throw ValidationError("core-affinity[\(idx)]=\(coreAffinity) is not a valid integer")
                }
            }
        }
    }

    func run() async throws {
        PosixFDs.setup()

        let isTun = type == "tun"
        let split = vip.split(separator: ",")
        var vips: [(any IPMask)?] = Arrays.newArray(capacity: split.count)
        for (idx, vipmask) in split.enumerated() {
            vips[idx] = GetIPMask(from: String(vipmask))!
        }
        let destSplit = dest.split(separator: ",")
        var dests: [(any IPPort, Int)?] = Arrays.newArray(capacity: destSplit.count)
        for (idx, ipportweight) in destSplit.enumerated() {
            var ipportStr = String(ipportweight)
            var weightStr = "10"
            let braceIdx = ipportweight.firstIndex(of: "{")
            if let braceIdx {
                weightStr = String(ipportweight[ipportweight.index(braceIdx, offsetBy: 1) ..< ipportweight.index(before: ipportweight.endIndex)])
                ipportStr = String(ipportweight[..<braceIdx])
            }
            let ipport = GetIPPort(from: String(ipportStr))!
            let weight = Int(weightStr)!
            dests[idx] = (ipport, weight)
        }

        var params = VSwitchParams(
            ethsw: { DummyNodeManager() },
            netstack: { NetstackNodeManager() }
        )

        var coreAffinity = [Int64]()
        if let affinity = self.coreAffinity {
            for s in affinity.split(separator: ",") {
                coreAffinity.append(Int64(s)!)
            }
        }
        if !coreAffinity.isEmpty {
            params.coreAffinityMasksForEveryThreads = coreAffinity
        }

        let sw = try VSwitch(params: params)
        sw.start()

        sw.ensureNetstack(id: 1)
        sw.configure { idx, sw in
            let netstack = sw.netstacks[1]!
            for vipmask in vips {
                for proto in [IP_PROTOCOL_TCP, IP_PROTOCOL_UDP] {
                    let svc = Service(proto: proto,
                                      vip: vipmask!.ip,
                                      port: port,
                                      sched: WeightedRoundRobinDestScheduler(),
                                      totalWorkerCount: coreAffinity.count,
                                      currentWorkerIndex: idx)
                    _ = netstack.ipvs.addService(svc)
                    for destIpPortWeight in dests {
                        let destIpPortWeight = destIpPortWeight!
                        let destIpPort = destIpPortWeight.0
                        let weight = destIpPortWeight.1
                        _ = svc.addDest(Dest(destIpPort.ip, destIpPort.port, service: svc, weight: weight, fwd: .FNAT))
                    }
                    for vipmask2 in vips {
                        let vipmask2 = vipmask2!
                        _ = svc.addLocalIP(vipmask2.ip)
                    }
                }
            }
        }

        if isTun {
            let tun = TunIfaceProvider(dev: devName)
            try sw.register(tun, netstack: 1)
            for vipmask in vips {
                sw.configure { _, sw in
                    sw.addAddress(vipmask, dev: tun.name)
                }
            }
        } else {
            let tap = TapIfaceProvider(dev: devName)
            try sw.register(tap, netstack: 1)
            for vipmask in vips {
                sw.configure { _, sw in
                    sw.addAddress(vipmask, dev: tap.name)
                }
            }
        }

        Logger.alert("sample-vs started")
        let controlPlane = ControlPlane(sw)
        try await controlPlane.launch()
    }
}
