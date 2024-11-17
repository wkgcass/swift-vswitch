import SwiftVSwitch
import SwiftVSwitchControlData
import Vapor
import VProxyCommon

struct NeighController: RouteCollection, @unchecked Sendable {
    private let sw: VSwitch
    public init(_ sw: VSwitch) {
        self.sw = sw
    }

    func boot(routes: any Vapor.RoutesBuilder) throws {
        let api = routes.grouped("apis", "v1.0", "netstacks", ":ns", "neighbors")
        api.get(use: listNeighbors)
    }

    private func listNeighbors(req: Request) async throws -> [NeighborRef] {
        let nsStr = req.parameters.get("ns")!
        let ns = UInt32(nsStr)
        guard let ns else {
            throw Abort(.badRequest, reason: "netstack/:id expects an unsigned integer, but got \(nsStr)")
        }

        let box = try sw.queryWorkerWithErr { sw in
            guard let ns = sw.netstacks[ns] else {
                throw Abort(.notFound, reason: "netstack/\(ns) not found")
            }

            let neighs = Box([NeighborRef]())
            for n in ns.arpTable.entries {
                neighs.pointee.append(NeighborRef(
                    ip: n.ip.description,
                    mac: n.mac.description,
                    dev: NetifId(name: n.dev.name, id: n.dev.id),
                    timeout: Int(n.ttl)
                ))
            }
            return neighs
        }!
        return box.pointee
    }
}
