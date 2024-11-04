import ArgumentParser
import SwiftEventLoopCommon
import SwiftEventLoopPosix
import SwiftVSwitch
import SwiftVSwitchTunTap
import VProxyCommon

struct TapTunPingSample: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Ping into tap/tun devices.")

    @Option(help: "Choose to use tap or tun.") var type: String
    @Option(help: "Device name or pattern.") var devName: String
    @Option(help: "Peer mac address.") var mac: String
    @Option(help: "IP addresses separated by `,`.") var ip: String

    func validate() throws {
        if type != "tap" && type != "tun" {
            throw ValidationError("\(type) should be tap|tun, but got \(type)")
        }
        if MacAddress(from: mac) == nil {
            throw ValidationError("mac=\(mac) is not a valid mac")
        }
        let split = ip.split(separator: ",")
        for (idx, ipstr) in split.enumerated() {
            if GetIP(from: String(ipstr)) == nil {
                throw ValidationError("ip[\(idx)]=\(ipstr) is not a valid ip")
            }
        }
    }

    func run() throws {
        PosixFDs.setup()

        let isTun = type == "tun"
        let mac = MacAddress(from: mac)!
        let split = ip.split(separator: ",")
        var ips: [(any IP)?] = Arrays.newArray(capacity: split.count)
        for (idx, ipstr) in split.enumerated() {
            ips[idx] = GetIP(from: String(ipstr))!
        }

        let loop = try SelectorEventLoop.open()
        let thread = FDProvider.get().newThread { loop.loop() }
        thread.start()

        let vs = VSwitch(loop: loop, params: VSwitchParams())
        vs.ensureBroadcastDomain(network: 1)
        vs.start()

        let mimic = SimpleHostMimicIface(name: "sample", mac: mac)
        for ip in ips {
            mimic.add(ip: ip)
        }
        try vs.register(iface: mimic, network: 1)

        if isTun {
            print("tun not supported yet ...")
            return
        } else {
            let tap = try TapIface.open(dev: devName)
            try vs.register(iface: tap, network: 1)
        }

        thread.join()
    }
}

TapTunPingSample.main()
