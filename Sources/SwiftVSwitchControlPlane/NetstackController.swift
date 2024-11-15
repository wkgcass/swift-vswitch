import SwiftVSwitch
import Vapor

struct NetstackRef: Content {
    var id: UInt32
}

struct NetstackController: RouteCollection, @unchecked Sendable {
    private let sw: VSwitch
    public init(_ sw: VSwitch) {
        self.sw = sw
    }

    func boot(routes: any Vapor.RoutesBuilder) throws {
        let api = routes.grouped("apis", "v1.0", "netstacks")
        api.get(use: listNetstacks)
    }

    private func listNetstacks(req _: Request) async throws -> [NetstackRef] {
        return [NetstackRef(id: 123)]
    }
}
