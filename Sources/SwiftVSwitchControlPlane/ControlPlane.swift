import SwiftVSwitch
import Vapor
import VProxyCommon

public class ControlPlane {
    private let sw: VSwitch
    public init(_ sw: VSwitch) {
        self.sw = sw
    }

    public func launch(unix: String) async throws {
        let app = try await Application.make(.production, .shared(MultiThreadedEventLoopGroup(numberOfThreads: 1)))
        app.http.server.configuration.address = .unixDomainSocket(path: unix)

        try await run(app)
    }

    public func launch(address: any IPPort) async throws {
        let app = try await Application.make(.production, .shared(MultiThreadedEventLoopGroup(numberOfThreads: 1)))
        app.http.server.configuration.address = .hostname(address.ip.description, port: Int(address.port))

        try await run(app)
    }

    private func run(_ app: Application) async throws {
        try app.register(collection: NetstackController(sw))
        try await app.execute()
    }
}
