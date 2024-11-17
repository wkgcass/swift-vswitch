import SwiftEventLoopCommon
import SwiftEventLoopPosix
import SwiftVSwitch
import SwiftVSwitchControlPlane
import SwiftVSwitchEthFwd
import SwiftVSwitchNetStack
import VProxyCommon

func startServer(argv: ArraySlice<String>) async throws {
    var coreAffinity: [Int64]?
    for arg in argv {
        if arg.hasPrefix("core-affinity=") {
            let v = arg.dropFirst("core-affinity=".count)
            let coreAffinitySplit = v.split(separator: ",")
            coreAffinity = Arrays.newArray(capacity: coreAffinitySplit.count, uninitialized: true)
            for (idx, c) in coreAffinitySplit.enumerated() {
                let n = Int64(c)
                if n == nil {
                    print("core-affinity[\(idx)]=\(c) is not a valid integer")
                    OS.exit(code: 1)
                }
                coreAffinity![idx] = n!
            }
        } else {
            throw IllegalArgumentException("unknown key=value: \(arg)")
        }
    }

    PosixFDs.setup()

    let params = VSwitchParams(
        ethsw: { EthernetFwdNodeManager() }, netstack: { NetstackNodeManager() }
    )
    let sw = try VSwitch(params: params)

    let controlPlane = ControlPlane(sw)
    try await controlPlane.launch()
}
