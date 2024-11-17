import SwiftVSwitch
import SwiftVSwitchControlData
import Vapor
import VProxyCommon

struct RouteController: RouteCollection, @unchecked Sendable {
    private let sw: VSwitch
    public init(_ sw: VSwitch) {
        self.sw = sw
    }

    func boot(routes: any Vapor.RoutesBuilder) throws {
        let api = routes.grouped("apis", "v1.0", "netstacks", ":ns", "routes")
        api.get(use: listRoutes)
    }

    private func listRoutes(req: Request) async throws -> [RouteRef] {
        let nsStr = req.parameters.get("ns")!
        let ns = UInt32(nsStr)
        guard let ns else {
            throw Abort(.badRequest, reason: "netstack/:id expects an unsigned integer, but got \(nsStr)")
        }

        let box = try sw.queryWithErr { sw in
            guard let ns = sw.netstacks[ns] else {
                throw Abort(.notFound, reason: "netstack/\(ns) not found")
            }

            let routes = Box([RouteRef]())
            for n in ns.routeTable.rulesV4.values {
                var gatewayStr: String?
                if let gateway = n.gateway {
                    gatewayStr = gateway.description
                }
                routes.pointee.append(RouteRef(
                    rule: n.rule.description,
                    gateway: gatewayStr,
                    dev: NetifId(name: n.dev.name, id: n.dev.id),
                    src: n.src.description
                ))
            }
            for n in ns.routeTable.rulesV6.values {
                var gatewayStr: String?
                if let gateway = n.gateway {
                    gatewayStr = gateway.description
                }
                routes.pointee.append(RouteRef(
                    rule: n.rule.description,
                    gateway: gatewayStr,
                    dev: NetifId(name: n.dev.name, id: n.dev.id),
                    src: n.src.description
                ))
            }
            return routes
        }!
        return box.pointee
    }
}
