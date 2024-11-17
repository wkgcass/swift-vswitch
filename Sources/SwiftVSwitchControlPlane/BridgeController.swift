import SwiftVSwitch
import SwiftVSwitchControlData
import Vapor
import VProxyCommon

struct BridgeController: RouteCollection, @unchecked Sendable {
    private let sw: VSwitch
    public init(_ sw: VSwitch) {
        self.sw = sw
    }

    func boot(routes: any Vapor.RoutesBuilder) throws {
        let api = routes.grouped("apis", "v1.0", "bridges")
        api.get(use: listBridges)
    }

    private func listBridges(req _: Request) async throws -> [BridgeRef] {
        let box = sw.query { sw in
            let bridges = Box([BridgeRef]())
            for b in sw.bridges.values {
                var ifaces = [String]()
                for iface in sw.ifaces.values {
                    if iface.toBridge == b.id {
                        ifaces.append(iface.name)
                    }
                }
                bridges.pointee.append(BridgeRef(
                    name: "br\(b.id)",
                    id: b.id,
                    interfaces: ifaces
                ))
            }
            return bridges
        }!
        return box.pointee
    }
}
