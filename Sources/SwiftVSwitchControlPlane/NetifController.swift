import SwiftVSwitch
import SwiftVSwitchControlData
import Vapor
import VProxyCommon

struct NetifController: RouteCollection, @unchecked Sendable {
    private let sw: VSwitch
    public init(_ sw: VSwitch) {
        self.sw = sw
    }

    func boot(routes: any Vapor.RoutesBuilder) throws {
        let api = routes.grouped("apis", "v1.0")
        api.get("netstacks", ":ns", "netifs", use: listNetifs)
        api.post("netstacks", ":ns", "netifs", "query", use: filterNetifs)
    }

    private func listNetifs(req: Request) async throws -> [NetifRef] {
        let nsStr = req.parameters.get("ns")!
        let ns = UInt32(nsStr)
        guard let ns else {
            throw Abort(.badRequest, reason: "netstack/:id expects an unsigned integer, but got \(nsStr)")
        }

        let box = try sw.queryWithErr { sw in
            guard let ns = sw.netstacks[ns] else {
                throw Abort(.notFound, reason: "netstack/\(ns) not found")
            }

            let ifaces = Box([NetifRef]())
            for i in sw.ifaces.values {
                if i.toNetstack != ns.id {
                    continue
                }
                if let netif = ifaceToNetif(i, ns) {
                    ifaces.pointee.append(netif)
                }
            }
            return ifaces
        }!
        fetchAllStats(box)
        return box.pointee
    }

    private func ifaceToNetif(_ i: IfaceEx, _ ns: NetStack) -> NetifRef? {
        let ips = ns.ips.getBy(iface: i)
        var addressesV4 = [Address]()
        var addressesV6 = [Address]()
        for v4 in ips.0 {
            addressesV4.append(Address(ip: v4.ipv4.description, mask: v4.maskInt))
        }
        for v6 in ips.1 {
            addressesV6.append(Address(ip: v6.ipv6.description, mask: v6.maskInt))
        }
        return NetifRef(
            name: i.name,
            id: i.id,
            addressesV4: addressesV4,
            addressesV6: addressesV6,
            mac: i.mac.description,
            statistics: IfaceStatistics()
        )
    }

    private func fetchAllStats(_ box: Box<[NetifRef]>) {
        sw.blockForeachWorker { sw in
            for idx in box.pointee.indices {
                guard let iface = sw.ifaces[box.pointee[idx].id] else {
                    continue
                }
                box.pointee[idx].statistics.inc(iface.meta.statistics)
            }
        }
    }

    private func filterNetifs(req: Request) async throws -> [NetifRef] {
        let nsStr = req.parameters.get("ns")!
        let ns = UInt32(nsStr)
        guard let ns else {
            throw Abort(.badRequest, reason: "netstack/:id expects an unsigned integer, but got \(nsStr)")
        }
        let filter = try req.content.decode(NetifFilter.self)

        let box = try sw.queryWithErr { sw in
            guard let ns = sw.netstacks[ns] else {
                throw Abort(.notFound, reason: "netstack/\(ns) not found")
            }

            let ifaces = Box([NetifRef]())
            for i in sw.ifaces.values {
                if let netif = ifaceToNetif(i, ns) {
                    if i.toNetstack != ns.id {
                        continue
                    }
                    if let fname = filter.name {
                        if netif.name != fname {
                            continue
                        }
                    }
                    ifaces.pointee.append(netif)
                }
            }
            return ifaces
        }!
        fetchAllStats(box)
        return box.pointee
    }
}
