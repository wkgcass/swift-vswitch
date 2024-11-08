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
    @Option(help: "CIDRs separated by `,`.") var cidr: String
    @Option(help: "Choose to use mimic or stack.") var netType: String

    func validate() throws {
        if type != "tap" && type != "tun" {
            throw ValidationError("type should be tap|tun, but got \(type)")
        }
        if netType != "mimic" && netType != "stack" {
            throw ValidationError("net-type should be mimic or stack")
        }
        let split = cidr.split(separator: ",")
        for (idx, cidrstr) in split.enumerated() {
            if GetCIDR(from: String(cidrstr)) == nil {
                throw ValidationError("cidr[\(idx)]=\(cidr) is not a valid ip")
            }
        }
    }

    func run() throws {
        PosixFDs.setup()

        let isTun = type == "tun"
        let split = cidr.split(separator: ",")
        var cidrs: [(any CIDR)?] = Arrays.newArray(capacity: split.count)
        for (idx, cidrstr) in split.enumerated() {
            cidrs[idx] = GetCIDR(from: String(cidrstr))!
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
            for cidr in cidrs {
                mimic.add(ip: cidr!.ip)
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
                for cidr in cidrs {
                    vs.addAddress(cidr!.ip, dev: tun.name)
                    vs.addRoute(cidr!.network, dev: tun.name, src: cidr!.ip)
                }
            }
        } else {
            let tap = try TapIface.open(dev: devName)
            if netType == "mimic" {
                try vs.register(iface: tap, bridge: 1)
            } else {
                try vs.register(iface: tap, netstack: 1)
                for cidr in cidrs {
                    vs.addAddress(cidr!.ip, dev: tap.name)
                    vs.addRoute(cidr!.network, dev: tap.name, src: cidr!.ip)
                }
            }
        }
        Logger.alert("sample-taptunping started")
        thread.join()
    }
}

TapTunPingSample.main()
