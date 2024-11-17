import SwiftVSwitch
import SwiftVSwitchControlData
import Vapor
import VProxyCommon

struct AddressController: RouteCollection, @unchecked Sendable {
    private let sw: VSwitch
    public init(_ sw: VSwitch) {
        self.sw = sw
    }

    func boot(routes: any Vapor.RoutesBuilder) throws {
        _ = routes.grouped("apis", "v1.0", "netstacks", ":ns", "netifs", ":ifId", "addresses")
        // TODO: api.get(use: xxx)
    }
}
