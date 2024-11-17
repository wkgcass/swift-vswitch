import VProxyCommon

let HELP_MSG = """
Usage:
    swvs c      -- As client
    swvs s      -- As server
Client:
    brctl show
    brctl addbr br<n>
    brctl delbr br<n>
    brctl showmacs br<n>
    ip netns add ns<n>
    ip netns del ns<n>
    ip netns show
    [ip netns exec] ns<n> ip addr show
    [ip netns exec] ns<n> ip addr add <ipmask> dev <dev>
    [ip netns exec] ns<n> ip link show
    [ip netns exec] ifconfig <dev>
    [ip netns exec] ns<n> ip route show
    [ip netns exec] ns<n> ip route add <cidr> dev <dev>
    [ip netns exec] ns<n> ip route add <cidr> via <ip> dev <dev>
    [ip netns exec] ns<n> ip route del <cidr>
    [ip netns exec] ns<n> ip neigh show
    [ip netns exec] ns<n> ip neigh add <ip> dev <dev> lladdr <mac>
    [ip netns exec] ns<n> ipvsadm -ln
    [ip netns exec] ns<n> ipvsadm -ln <-t|-u> <vs>
    [ip netns exec] ns<n> ipvsadm -A <-t|-u> <vs> [-s sched]
    [ip netns exec] ns<n> ipvsadm -E <-t|-u> <vs> [-s sched]
    [ip netns exec] ns<n> ipvsadm -D <-t|-u> <vs>
    [ip netns exec] ns<n> ipvsadm -a <-t|-u> <vs> -r <rs> -w <weight> <--fullnat|--masquerading>
    [ip netns exec] ns<n> ipvsadm -e <-t|-u> <vs> -r <rs> [-w <weight>]
    [ip netns exec] ns<n> ipvsadm -d <-t|-u> <vs> -r <rs>
    [ip netns exec] ns<n> conntrack -Ln
    conntrack -Ln --debug
Server:
    [optional] core-affinity=Core affinity, which is a list of bitmasks separated by `,`.
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
