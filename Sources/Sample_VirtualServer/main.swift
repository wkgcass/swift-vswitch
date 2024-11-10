import ArgumentParser
import SwiftEventLoopCommon
import SwiftEventLoopPosix
import SwiftVSwitch
import SwiftVSwitchNetStack
import SwiftVSwitchTunTap
import SwiftVSwitchVirtualServerBase
import VProxyCommon

struct VirtualServerSample: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A sample virtual server.")

    @Option(help: "Choose to use tap or tun.") var type: String
    @Option(help: "Device name or pattern.") var devName: String
    @Option(help: "(IP/Mask)s separated by `,`.") var vip: String
    @Option(help: "Port for the virtual server.") var port: UInt16
    @Option(help: "Dest ip:port.") var dest: String
    @Option(help: "Core affinity, which is a bitmask.") var coreAffinity: Int64?

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
        if GetIPPort(from: dest) == nil {
            throw ValidationError("dest=\(dest) is not a valid ip")
        }
    }

    func run() throws {
        PosixFDs.setup()

        let isTun = type == "tun"
        let split = vip.split(separator: ",")
        var vips: [(any IPMask)?] = Arrays.newArray(capacity: split.count)
        for (idx, vipmask) in split.enumerated() {
            vips[idx] = GetIPMask(from: String(vipmask))!
        }
        let destIpPort = GetIPPort(from: dest)!

        var opts = SelectorOptions()
        if let coreAffinity {
            opts.coreAffinity = coreAffinity
        }
        let loop = try SelectorEventLoop.open(opts: opts)
        let thread = FDProvider.get().newThread { loop.loop() }
        thread.start()

        let sw = VSwitch(loop: loop, params: VSwitchParams(
            ethsw: DummyNodeManager(),
            netstack: NetstackNodeManager()
        ))
        sw.start()
        sw.ensureNetstack(id: 1)
        loop.runOnLoop {
            let netstack = sw.netstacks[1]!
            for vipmask in vips {
                for proto in [IP_PROTOCOL_TCP, IP_PROTOCOL_UDP] {
                    let svc = Service(proto: proto,
                                      vip: vipmask!.ip,
                                      port: port,
                                      sched: RoundRobinDestScheduler.instance)
                    _ = netstack.ipvs.addService(svc)
                    _ = svc.addDest(Dest(destIpPort.ip, destIpPort.port, service: svc, weight: 10, fwd: .FNAT))
                    for vipmask2 in vips {
                        _ = svc.addLocalIP(vipmask2!.ip)
                    }
                }
            }
        }

        if isTun {
            let tun = try TunIface.open(dev: devName)
            try sw.register(iface: tun, netstack: 1)
            for vipmask in vips {
                sw.addAddress(vipmask!.ip, dev: tun.name)
                sw.addRoute(vipmask!.network, dev: tun.name, src: vipmask!.ip)
            }
        } else {
            let tap = try TapIface.open(dev: devName)
            try sw.register(iface: tap, netstack: 1)
            for vipmask in vips {
                sw.addAddress(vipmask!.ip, dev: tap.name)
                sw.addRoute(vipmask!.network, dev: tap.name, src: vipmask!.ip)
            }
        }
        Logger.alert("sample-vs started")
        thread.join()
    }
}

VirtualServerSample.main()
