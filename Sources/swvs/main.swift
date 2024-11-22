import VProxyCommon

let HELP_MSG = """
Usage:
    swvs c      -- As client
    swvs s      -- As server
Client:
    brctl help
    ip netns help
    [ip netns exec] ns<n> ip addr help
    [ip netns exec] ns<n> ip link help
    [ip netns exec] ifconfig --help
    [ip netns exec] ns<n> ip route help
    [ip netns exec] ns<n> ip neigh help
    [ip netns exec] ns<n> ipvsadm --help
    [ip netns exec] ns<n> conntrack --help
    debug help
Server:
    [optional] core-affinity=Core affinity, which is a list of bitmasks separated by `,`.
               default: only one worker thread and no core affinity
"""

@main
class Main {
    static func main() async throws {
        let argv = CommandLine.arguments.dropFirst()
        guard let first = argv.first else {
            print(HELP_MSG)
            OS.exit(code: 1)
            return
        }

        if first == "-h" || first == "--help" || first == "help" || first == "-help" {
            print(HELP_MSG)
            OS.exit(code: 0)
        }

        if first != "c" && first != "s" {
            print("First argument must be `c` for client or `s` for server")
            OS.exit(code: 1)
        }

        if first == "c" {
            let client = try await Client()
            do {
                try await client.runClient(argv: argv.dropFirst())
            } catch {
                print(error)
            }
            OS.exit(code: 0)
        } else {
            try await startServer(argv: argv.dropFirst())
        }
    }
}
