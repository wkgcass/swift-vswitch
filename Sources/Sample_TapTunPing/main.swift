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
                throw ValidationError("ipmask[\(idx)]=\(ipmask) is not a valid ip")
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

        let loop = try SelectorEventLoop.open()
        let thread = FDProvider.get().newThread { loop.loop() }
        thread.start()

        let vs = VSwitch(loop: loop, params: VSwitchParams(
            ethsw: EthernetFwdNodeManager(),
            netstack: NetstackNodeManager()
        ))
        vs.start()

        if netType == "mimic" {
            vs.ensureBridge(id: 1)
            let mimic = SimpleHostMimicIface(name: "sample")
            for ipmask in ipmasks {
                mimic.add(ip: ipmask!.ip)
            }
            try vs.register(iface: mimic, bridge: 1)
        } else {
            vs.ensureNetstack(id: 1)
        }

        if isTun {
            let tun = try TunIface.open(dev: devName)
            if netType == "mimic" {
                print("Cannot use type=tun with net-type=mimic.")
                return
            } else {
                try vs.register(iface: tun, netstack: 1)
                for ipmask in ipmasks {
                    vs.addAddress(ipmask!.ip, dev: tun.name)
                    vs.addRoute(ipmask!.network, dev: tun.name, src: ipmask!.ip)
                }
            }
        } else {
            let tap = try TapIface.open(dev: devName)
            if netType == "mimic" {
                try vs.register(iface: tap, bridge: 1)
            } else {
                try vs.register(iface: tap, netstack: 1)
                for ipmask in ipmasks {
                    vs.addAddress(ipmask!.ip, dev: tap.name)
                    vs.addRoute(ipmask!.network, dev: tap.name, src: ipmask!.ip)
                }
            }
        }
        Logger.alert("sample-taptunping started")
        thread.join()
    }
}

TapTunPingSample.main()
