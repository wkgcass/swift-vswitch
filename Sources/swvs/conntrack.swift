import ArgumentParser
import SwiftVSwitch
import SwiftVSwitchClient
import SwiftVSwitchControlData
import VProxyCommon

extension Client {
    func runConntrackInNetns(_ id: UInt32, _ argv: ArraySlice<String>) async throws {
        guard let first = argv.first else {
            throw IllegalArgumentException("no further commands provided")
        }
        if first.hasPrefix("-L") {
            let show = try ConntrackShow.parse([String](argv))
            try await show.run(self, netstack: id)
        } else {
            throw IllegalArgumentException("unknown conntrack arguments: \(argv)")
        }
    }
}

struct ConntrackShow: AsyncParsableCommand {
    @Flag(name: .customShort("L"), help: "List conntrack or expectation table") var list = false
    @Flag(name: .customShort("n"), help: "Numeric") var numeric = false
    @Flag(name: .customLong("debug"), help: "Show debug connections") var debug = false

    func run(_ client: Client, netstack: UInt32) async throws {
        if netstack != 0 && debug {
            throw IllegalArgumentException("cannot run debug conntrack in netns")
        }
        if debug {
            let conns = try await client.client.debugListConnections(netstack: netstack)
            printConntrackConnections(conns)
        } else {
            throw IllegalArgumentException("TODO")
        }
    }
}

func printConntrackConnections(_ conns: [ConnRef]) {
    for conn in conns {
        let proto = if conn.proto == IP_PROTOCOL_TCP {
            "tcp"
        } else {
            "udp"
        }
        let commonStr = "ttl=\(conn.ttl)"
        if let peer = conn.peer {
            print("\(proto)      \(conn.proto) \(formatConntrackConnection(conn)) \(formatConntrackConnection(peer)) addr=\(conn.address) peer=\(peer.address) \(commonStr)")
        } else {
            print("\(proto)      \(conn.proto) \(formatConntrackConnection(conn)) addr=\(conn.address) \(commonStr)")
        }
    }
}

func formatConntrackConnection(_ conn: ConnRef) -> String {
    return "src=\(conn.src) dst=\(conn.dst) sport=\(conn.srcPort) dport=\(conn.dstPort)"
}
