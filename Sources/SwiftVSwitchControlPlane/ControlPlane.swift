import SwiftVSwitch
import Vapor
import VProxyCommon

public class ControlPlane {
    private let sw: VSwitch
    public init(_ sw: VSwitch) {
        self.sw = sw
    }

    public func launch() async throws {
        try await launch(unix: "/var/run/swvs.sock")
    }

    public func launch(_ addr: BindAddress) async throws {
        let env = Environment(name: "production", arguments: [CommandLine.arguments[0]])
        let app = try await Application.make(env, .shared(MultiThreadedEventLoopGroup(numberOfThreads: 1)))
        app.http.server.configuration.address = addr

        switch addr {
        case let BindAddress.unixDomainSocket(path):
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
            }
        default:
            break
        }

        try await run(app)
    }

    public func launch(unix: String) async throws {
        try await launch(.unixDomainSocket(path: unix))
    }

    private func run(_ app: Application) async throws {
        try app.register(collection: NetstackController(sw))
        try app.register(collection: BridgeController(sw))
        try app.register(collection: NetifController(sw))
        try app.register(collection: NeighController(sw))
        try app.register(collection: RouteController(sw))
        try app.register(collection: IPVSController(sw))
        try app.register(collection: DebugController(sw))
        try await app.execute()
    }
}
