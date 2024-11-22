import SwiftVSwitchClient
import SwiftVSwitchControlData
import VProxyCommon

extension Client {
    func runIPRoute(_ id: UInt32, _ argv: ArraySlice<String>) async throws {
        guard let first = argv.first else {
            return try await runIPRouteShowAll(id, argv)
        }
        if first == "show" {
            if argv.count == 1 {
                return try await runIPRouteShowAll(id, argv.dropFirst())
            }
            throw IllegalArgumentException("unexpected redundant arguments: \(argv)")
        } else if first == "add" {
            throw IllegalArgumentException("TODO")
        } else if first == "del" {
            throw IllegalArgumentException("TODO")
        } else if first == "help" {
            print("""
                [ip netns exec] ns<n> ip route show
                [ip netns exec] ns<n> ip route add <cidr> dev <dev>
                [ip netns exec] ns<n> ip route add <cidr> via <ip> dev <dev>
                [ip netns exec] ns<n> ip route del <cidr>
            """)
            return
        } else {
            throw IllegalArgumentException("unknown ip route command: \(first)")
        }
    }

    func runIPRouteShowAll(_ id: UInt32, _ argv: ArraySlice<String>) async throws {
        if let _ = argv.first {
            throw IllegalArgumentException("unexpected redundant arguments: \(argv)")
        }
        let routes = try await client.showAllRoutes(netstack: id)
        for r in routes {
            printRoute(r)
        }
    }

    private func printRoute(_ route: RouteRef) {
        if let gateway = route.gateway {
            print("\(route.rule) via \(gateway) dev \(route.dev.name) src \(route.src)")
        } else {
            print("\(route.rule) dev \(route.dev.name) src \(route.src)")
        }
    }
}
