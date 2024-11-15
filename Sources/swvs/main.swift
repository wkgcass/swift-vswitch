#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

import SwiftEventLoopCommon
import SwiftEventLoopPosix
import SwiftVSwitch
import SwiftVSwitchControlPlane
import SwiftVSwitchEthFwd
import SwiftVSwitchNetStack

PosixFDs.setup()

let sw = try VSwitch(params: VSwitchParams(
    ethsw: { EthernetFwdNodeManager() }, netstack: { NetstackNodeManager() }
))

let controlPlane = ControlPlane(sw)
try await controlPlane.launch(unix: "/var/run/swvs.sock")
