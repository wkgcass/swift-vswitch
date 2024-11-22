import VProxyCommon

extension Client {
    func runDebug(_ argv: ArraySlice<String>) async throws {
        guard let first = argv.first else {
            throw IllegalArgumentException("no debug action provided")
        }
        if first == "help" {
            print("""
                debug redirect cost
            """)
            return
        } else if first == "redirect" {
            return try await runDebugRedirect(argv.dropFirst())
        } else {
            throw IllegalArgumentException("unknown debug action \(first)")
        }
    }

    func runDebugRedirect(_ argv: ArraySlice<String>) async throws {
        guard let first = argv.first else {
            throw IllegalArgumentException("no further commands provided")
        }
        if first == "cost" {
            return try await runDebugRedirectCost()
        } else {
            throw IllegalArgumentException("unknown option \(first)")
        }
    }

    func runDebugRedirectCost() async throws {
        let cost = try await client.runDebugRedirectCost()
        print("Total:   \(cost.redirectCostUSecs)")
        print("Count:   \(cost.redirectCount)")
        let usecs = cost.redirectCostUSecs / cost.redirectCount
        print("Average: \(usecs)us")
    }
}
