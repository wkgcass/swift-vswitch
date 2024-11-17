import SwiftVSwitchClient
import SwiftVSwitchControlData
import VProxyCommon

extension Client {
    func runIPLink(_ id: UInt32, _ argv: ArraySlice<String>) async throws {
        guard let first = argv.first else {
            return try await runIPLinkShowAll(id, argv)
        }
        if first == "show" {
            if argv.count == 1 {
                return try await runIPLinkShowAll(id, argv.dropFirst())
            }
            try await runIPLinkShowOne(id, argv.dropFirst())
        } else {
            throw IllegalArgumentException("unknown ip link command: \(first)")
        }
    }

    func runIPLinkShowAll(_ id: UInt32, _ argv: ArraySlice<String>) async throws {
        if let _ = argv.first {
            throw IllegalArgumentException("unexpected redundant arguments: \(argv)")
        }
        let netifs = try await client.showAllNetifs(netstack: id)
        for netif in netifs {
            printForIPLink(netif)
        }
    }

    func runIPLinkShowOne(_ id: UInt32, _ argv: ArraySlice<String>) async throws {
        var ifname: String
        if argv.count == 1 {
            ifname = argv.first!
        } else if argv.count == 2 {
            if argv.first! != "dev" {
                throw IllegalArgumentException("expecting <ifname> or dev <ifname>, but got \(argv)")
            }
            ifname = argv[argv.startIndex + 1]
        } else {
            throw IllegalArgumentException("expecting <ifname> or dev <ifname>, but got \(argv)")
        }

        let netifs = try await client.showNetif(netstack: id, ifname: ifname)
        for netif in netifs {
            printForIPLink(netif)
        }
    }

    private func printForIPLink(_ netif: NetifRef) {
        print("\(netif.id): \(netif.name): status UP")
        print("    link/ether \(netif.mac) brd ff:ff:ff:ff:ff:ff")
    }
}
