import ArgumentParser
import SwiftEventLoopCommon
import SwiftEventLoopPosix
import SwiftVSwitch
import SwiftVSwitchEthFwd
import SwiftVSwitchNetStack
import SwiftVSwitchTunTap
import VProxyCommon

struct TapTunPingSample: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Ping into tap/tun devices.")

    @Option(help: "Choose to use tap or tun.") var type: String
    @Option(help: "Device name or pattern.") var devName: String
    @Option(help: "(IP/Mask)s separated by `,`.") var ipmask: String
    @Option(help: "Choose to use mimic or stack.") var netType: String
    @Option(help: "Core affinity, which is a list of bitmasks separated by `,`.") var coreAffinity: String?

    func validate() throws {
        if type != "tap" && type != "tun" {
            throw ValidationError("type should be tap|tun, but got \(type)")
        }
        if netType != "mimic" && netType != "stack" {
            throw ValidationError("net-type should be mimic or stack")
        }
        let split = ipmask.split(separator: ",")
        for (idx, ipmaskStr) in split.enumerated() {
            if GetIPMask(from: String(ipmaskStr)) == nil {
                throw ValidationError("ipmask[\(idx)]=\(ipmaskStr) is not a valid ip/mask")
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

    func run() throws {
        PosixFDs.setup()

        let isTun = type == "tun"
        let split = ipmask.split(separator: ",")
        var ipmasks: [(any IPMask)?] = Arrays.newArray(capacity: split.count)
        for (idx, ipmaskStr) in split.enumerated() {
            ipmasks[idx] = GetIPMask(from: String(ipmaskStr))!
        }

        var params = VSwitchParams(
            ethsw: { EthernetFwdNodeManager() },
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

        if netType == "mimic" {
            sw.configure { _, sw in sw.ensureBridge(id: 1) }
            let ifprovider = PrototypeIfaceProvider {
                let mimic = SimpleHostMimicIface(name: "sample")
                for ipmask in ipmasks {
                    mimic.add(ip: ipmask!.ip)
                }
                return mimic
            }
            try sw.register(ifprovider, bridge: 1)
        } else {
            sw.ensureNetstack(id: 1)
        }

        if isTun {
            let tun = TunIfaceProvider(dev: devName)
            if netType == "mimic" {
                print("Cannot use type=tun with net-type=mimic.")
                OS.exit(code: 1)
            } else {
                try sw.register(tun, netstack: 1)
                for ipmask in ipmasks {
                    sw.configure { _, sw in
                        sw.addAddress(ipmask!.ip, dev: tun.name)
                        sw.addRoute(ipmask!.network, dev: tun.name, src: ipmask!.ip)
                    }
                }
            }
        } else {
            let tap = TapIfaceProvider(dev: devName)
            if netType == "mimic" {
                try sw.register(tap, bridge: 1)
            } else {
                try sw.register(tap, netstack: 1)
                for ipmask in ipmasks {
                    sw.configure { _, sw in
                        sw.addAddress(ipmask!.ip, dev: tap.name)
                        sw.addRoute(ipmask!.network, dev: tap.name, src: ipmask!.ip)
                    }
                }
            }
        }

        Logger.alert("sample-taptunping started")
        sw.joinMasterThread()
    }
}

TapTunPingSample.main()
