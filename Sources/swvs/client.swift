import SwiftVSwitchClient
import SwiftVSwitchControlData
import Vapor
import VProxyCommon

struct Client: @unchecked Sendable {
    let client: SwiftVSwitchClient

    init() async throws {
        client = try await SwiftVSwitchClient(baseUrl: "http+unix://%2fvar%2frun%2fswvs.sock")
    }

    func runClient(argv: ArraySlice<String>) async throws {
        guard let first = argv.first else {
            throw IllegalArgumentException("no program provided")
        }
        if first == "ip" {
            try await runIPCommand(argv.dropFirst())
        } else if first == "conntrack" {
            try await runConntrackInNetns(0, argv.dropFirst())
        } else if first.hasPrefix("ns"), first.count > 2 {
            try await runNetnsExec(argv)
        } else {
            throw IllegalArgumentException("unknown command \(first)")
        }
    }

    func runIPCommand(_ argv: ArraySlice<String>) async throws {
        guard let first = argv.first else {
            throw IllegalArgumentException("no ip action provided")
        }

        if first != "netns" {
            throw IllegalArgumentException("ip command should begin with `ip netns` to select the namespace (netstack)")
        }
        return try await runNetnsCommand(argv.dropFirst())
    }

    func runNetnsCommand(_ argv: ArraySlice<String>) async throws {
        guard let first = argv.first else {
            return try await runNetnsShow(argv)
        }

        if first == "show" {
            return try await runNetnsShow(argv.dropFirst())
        } else if first == "add" {
            // TODO:
            throw IllegalArgumentException("TODO")
        } else if first == "del" {
            // TODO:
            throw IllegalArgumentException("TODO")
        } else if first == "exec" {
            try await runNetnsExec(argv.dropFirst())
        } else {
            throw IllegalArgumentException("unknown action for ip netns: \(first)")
        }
    }

    func runNetnsShow(_ argv: ArraySlice<String>) async throws {
        if let _ = argv.first {
            throw IllegalArgumentException("unexpected redundant arguments: \(argv)")
        }
        let nss = try await client.showNetstacks()
        for ns in nss {
            print(ns.name)
        }
    }

    func runNetnsExec(_ argv: ArraySlice<String>) async throws {
        guard let first = argv.first else {
            throw IllegalArgumentException("no netns id provided")
        }
        if !first.hasPrefix("ns") || first.count == 2 {
            throw IllegalArgumentException("expecting ns name to be `ns<id>`, but got \(first)")
        }
        guard let id = UInt32(first.dropFirst(2)) else {
            throw IllegalArgumentException("expecting unsigned int netns id, but got \(first)")
        }
        try await runNetnsExecWithNetnsId(id, argv.dropFirst())
    }

    func runNetnsExecWithNetnsId(_ id: UInt32, _ argv: ArraySlice<String>) async throws {
        guard let first = argv.first else {
            throw IllegalArgumentException("no further commands provided")
        }
        if first == "ip" {
            try await runIPInNetns(id, argv.dropFirst())
        } else if first == "ifconfig" {
            try await runIfconfigInNetns(id, argv.dropFirst())
        } else if first == "ipvsadm" {
            try await runIpvsadmInNetns(id, argv.dropFirst())
        } else {
            throw IllegalArgumentException("unknown command: \(first)")
        }
    }

    func runIPInNetns(_ id: UInt32, _ argv: ArraySlice<String>) async throws {
        guard let first = argv.first else {
            throw IllegalArgumentException("no further commands provided")
        }
        if first == "addr" {
            try await runIPAddr(id, argv.dropFirst())
        } else if first == "link" {
            try await runIPLink(id, argv.dropFirst())
        } else if first == "neigh" {
            try await runIPNeigh(id, argv.dropFirst())
        } else if first == "route" {
            try await runIPRoute(id, argv.dropFirst())
        } else {
            throw IllegalArgumentException("unknown ip command: \(first)")
        }
    }

    func runIPNeigh(_ id: UInt32, _ argv: ArraySlice<String>) async throws {
        guard let first = argv.first else {
            return try await runIPNeighShowAll(id, argv)
        }
        if first == "show" {
            if argv.count == 1 {
                return try await runIPNeighShowAll(id, argv.dropFirst())
            }
            throw IllegalArgumentException("TODO")
        } else {
            throw IllegalArgumentException("unknown ip neigh command: \(first)")
        }
    }
}
