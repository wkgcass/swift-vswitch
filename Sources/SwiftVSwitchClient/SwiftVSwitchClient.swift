import SwiftVSwitchControlData
import Vapor

public class SwiftVSwitchClient {
    private let app: Application
    private let client: Client
    private let baseUrl: String

    public init(baseUrl: String) async throws {
        let env = Environment(name: "production", arguments: [CommandLine.arguments[0]])
        app = try await Application.make(env, .shared(MultiThreadedEventLoopGroup(numberOfThreads: 1)))
        self.baseUrl = baseUrl
        client = app.client
    }

    public func showNetstacks() async throws -> [NetstackRef] {
        let resp = try await client.get("\(baseUrl)/apis/v1.0/netstacks")
        return try resp.content.decode([NetstackRef].self)
    }

    public func showAllNetifs(netstack: UInt32) async throws -> [NetifRef] {
        let resp = try await client.get("\(baseUrl)/apis/v1.0/netstacks/\(netstack)/netifs")
        return try resp.content.decode([NetifRef].self)
    }

    public func showNetif(netstack: UInt32, ifname: String) async throws -> [NetifRef] {
        let resp = try await client.post("\(baseUrl)/apis/v1.0/netstacks/\(netstack)/netifs/query", content: NetifFilter(name: ifname))
        return try resp.content.decode([NetifRef].self)
    }

    public func showAllNeighbors(netstack: UInt32) async throws -> [NeighborRef] {
        let resp = try await client.get("\(baseUrl)/apis/v1.0/netstacks/\(netstack)/neighbors")
        return try resp.content.decode([NeighborRef].self)
    }

    public func showAllRoutes(netstack: UInt32) async throws -> [RouteRef] {
        let resp = try await client.get("\(baseUrl)/apis/v1.0/netstacks/\(netstack)/routes")
        return try resp.content.decode([RouteRef].self)
    }

    public func showAllIpvsServices(netstack: UInt32) async throws -> [ServiceRef] {
        let resp = try await client.get("\(baseUrl)/apis/v1.0/netstacks/\(netstack)/ipvs/services")
        return try resp.content.decode([ServiceRef].self)
    }

    public func showIpvsService(netstack: UInt32, filter: ServiceFilter) async throws -> [ServiceRef] {
        let resp = try await client.post("\(baseUrl)/apis/v1.0/netstacks/\(netstack)/ipvs/services/query", content: filter)
        return try resp.content.decode([ServiceRef].self)
    }

    public func showAllIPVSConnections(netstack: UInt32) async throws -> [ConnRef] {
        let resp = try await client.get("\(baseUrl)/apis/v1.0/netstacks/\(netstack)/ipvs/connections")
        return try resp.content.decode([ConnRef].self)
    }

    public func showIPVSConnectionsOfService(netstack: UInt32, filter: ServiceFilter) async throws -> [ConnRef] {
        let resp = try await client.post("\(baseUrl)/apis/v1.0/netstacks/\(netstack)/ipvs/connections/query", content: filter)
        return try resp.content.decode([ConnRef].self)
    }

    public func debugListConnections(netstack _: UInt32) async throws -> [ConnRef] {
        let resp = try await client.get("\(baseUrl)/apis/v1.0/debug/connections")
        return try resp.content.decode([ConnRef].self)
    }

    deinit {
        app.shutdown()
    }
}
