import SwiftVSwitchClient
import SwiftVSwitchControlData
import VProxyCommon

extension Client {
    func runIfconfigInNetns(_ id: UInt32, _ argv: ArraySlice<String>) async throws {
        guard let first = argv.first else {
            return try await showAllIfaces(inNetns: id, argv)
        }
        return try await showIface(inNetns: id, ifname: first, argv.dropFirst())
    }

    func showAllIfaces(inNetns nsId: UInt32, _ argv: ArraySlice<String>) async throws {
        if let _ = argv.first {
            throw IllegalArgumentException("unexpected redundant arguments: \(argv)")
        }
        let netifs = try await client.showAllNetifs(netstack: nsId)
        for netif in netifs {
            printNetif(netif)
        }
    }

    func showIface(inNetns nsId: UInt32, ifname: String, _ argv: ArraySlice<String>) async throws {
        if let _ = argv.first {
            throw IllegalArgumentException("unexpected redundant arguments: \(argv)")
        }
        let netifs = try await client.showNetif(netstack: nsId, ifname: ifname)
        for netif in netifs {
            printNetif(netif)
        }
    }

    private func printNetif(_ netif: NetifRef) {
        print("\(netif.name):")
        for addr in netif.addressesV4 {
            print("\tinet \(addr.ip)  netmask \(addr.mask)")
        }
        for addr in netif.addressesV6 {
            print("\tinet6 \(addr.ip)  prefixlen \(addr.mask)")
        }
        print("\tether \(netif.mac)")
        let s = netif.statistics
        print("\tRX packets \(s.rxpkts)  bytes \(s.rxbytes)")
        print("\tRX errcsum \(s.rxerrcsum)")
        print("\tTX packets \(s.txpkts)  bytes \(s.txbytes)")
        print("\tTX errors \(s.txerr)")
        print()
    }
}
