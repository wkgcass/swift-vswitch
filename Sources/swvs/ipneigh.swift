import SwiftVSwitchClient
import SwiftVSwitchControlData
import VProxyCommon

extension Client {
    func runIPNeighShowAll(_ id: UInt32, _ argv: ArraySlice<String>) async throws {
        if let first = argv.first {
            if first == "help" {
                print("""
                    [ip netns exec] ns<n> ip neigh show
                    [ip netns exec] ns<n> ip neigh add <ip> dev <dev> lladdr <mac>
                """)
                return
            }
            throw IllegalArgumentException("unexpected redundant arguments: \(argv)")
        }
        let neighbors = try await client.showAllNeighbors(netstack: id)
        for neigh in neighbors {
            printNeighbor(neigh)
        }
    }

    private func printNeighbor(_ neigh: NeighborRef) {
        var timeout: String
        if neigh.timeout < 0 {
            timeout = "PERMANENT"
        } else {
            timeout = "timeout=\(neigh.timeout / 1000)s"
        }
        print("\(neigh.ip) dev \(neigh.dev.name) lladdr \(neigh.mac) \(timeout)")
    }
}
