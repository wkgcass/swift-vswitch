import SwiftVSwitchClient
import SwiftVSwitchControlData
import VProxyCommon

extension Client {
    func runIPAddr(_ id: UInt32, _ argv: ArraySlice<String>) async throws {
        guard let first = argv.first else {
            return try await runIPAddrShowAll(id, argv)
        }
        if first == "show" {
            if argv.count == 1 {
                return try await runIPAddrShowAll(id, argv.dropFirst())
            }
            try await runIPAddrShowOne(id, argv.dropFirst())
        } else if first == "add" {
            // TODO:
            throw IllegalArgumentException("TODO")
        } else if first == "del" {
            // TODO:
            throw IllegalArgumentException("TODO")
        } else {
            throw IllegalArgumentException("unknown ip addr command: \(first)")
        }
    }

    func runIPAddrShowAll(_ id: UInt32, _ argv: ArraySlice<String>) async throws {
        if let _ = argv.first {
            throw IllegalArgumentException("unexpected redundant arguments: \(argv)")
        }
        let netifs = try await client.showAllNetifs(netstack: id)
        for netif in netifs {
            printForIPAddr(netif)
        }
    }

    func runIPAddrShowOne(_ id: UInt32, _ argv: ArraySlice<String>) async throws {
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
            printForIPAddr(netif)
        }
    }

    private func printForIPAddr(_ netif: NetifRef) {
        print("\(netif.id): \(netif.name): status UP")
        print("    link/ether \(netif.mac) brd ff:ff:ff:ff:ff:ff")
        for addr in netif.addressesV4 {
            print("    inet \(addr.ip)/\(addr.mask) \(netif.name)")
        }
        for addr in netif.addressesV6 {
            print("    inet6 \(addr.ip)/\(addr.mask)")
        }
    }
}
