// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "swift-vswitch",
    platforms: [
        .macOS(.v10_15),
    ],
    products: [
        .executable(name: "swvs", targets: ["swvs"]),
        .library(name: "vproxy-common", targets: ["VProxyCommon"]),
        .library(name: "swift-eventloop", targets: ["SwiftEventLoopCommon"]),
        .library(name: "swift-eventloop-posix", targets: ["SwiftEventLoopPosix"]),
        .library(name: "swift-vswitch", targets: ["SwiftVSwitch"]),
        .library(name: "swift-vswitch-ethfwd", targets: ["SwiftVSwitchEthFwd"]),
        .library(name: "swift-vswitch-netstack", targets: ["SwiftVSwitchNetStack"]),
        .library(name: "swift-vswitch-tuntap", targets: ["SwiftVSwitchTunTap"]),
        .library(name: "swift-vswitch-controlplane", targets: ["SwiftVSwitchControlPlane"]),
        .library(name: "swift-vswitch-client", targets: ["SwiftVSwitchClient"]),
        .executable(name: "sample-eventloop", targets: ["Sample_EventLoop"]),
        .executable(name: "sample-taptunping", targets: ["Sample_TapTunPing"]),
        .executable(name: "sample-vs", targets: ["Sample_VirtualServer"]),
    ],
    dependencies: [
        // .package(url: "https://github.com/davecom/SwiftPriorityQueue.git", revision: "1.4.0"),
        .package(url: "https://github.com/apple/swift-collections.git", revision: "1.1.4"),
        .package(url: "https://github.com/apple/swift-argument-parser", revision: "1.5.0"),
        .package(url: "https://github.com/apple/swift-atomics", revision: "1.2.0"),
        .package(url: "https://github.com/vapor/vapor", revision: "4.106.3"),
        .package(url: "https://github.com/vproxy-tools/SwiftLinkedListAndHash", revision: "f028e7c295bae6861dc7e3bf4a8e7d7e27ec09a8"),
    ],
    targets: [
        // common utilities
        .target(
            name: "VProxyCommon",
            dependencies: [
                "VProxyCommonCHelper",
                "WaitfreeMpscQueue",
                "SwiftLinkedListAndHash",
                .product(name: "Collections", package: "swift-collections"),
            ]
        ),
        // event loop api
        .target(
            name: "SwiftEventLoopCommon",
            dependencies: [
                "VProxyCommon",
                // "SwiftPriorityQueue",
                .product(name: "Atomics", package: "swift-atomics"),
            ]
        ),
        // event loop posix
        .target(
            name: "SwiftEventLoopPosix",
            dependencies: ["SwiftEventLoopCommon", "libae", "SwiftEventLoopPosixCHelper"]
        ),
        // vswitch
        .target(
            name: "SwiftVSwitch",
            dependencies: [
                "SwiftEventLoopCommon", "VProxyChecksum", "SwiftVSwitchCHelper", "poptrie",
            ]
        ),
        // vswitch tuntap ifaces
        .target(
            name: "SwiftVSwitchTunTap",
            dependencies: [
                "SwiftVSwitch", "SwiftEventLoopPosix", "SwiftVSwitchTunTapCHelper", "VProxyChecksum",
            ]
        ),
        // ethernet forwarding node graph
        .target(
            name: "SwiftVSwitchEthFwd",
            dependencies: [
                "SwiftVSwitch",
            ]
        ),
        // netstack node graph
        .target(
            name: "SwiftVSwitchNetStack",
            dependencies: [
                "SwiftVSwitch", "SwiftVSwitchVirtualServer",
            ]
        ),
        // ipvs
        .target(
            name: "SwiftVSwitchVirtualServer",
            dependencies: [
                "SwiftVSwitch",
            ]
        ),
        // control plane
        .target(
            name: "SwiftVSwitchControlData",
            dependencies: [
                "SwiftVSwitch",
                .product(name: "Vapor", package: "vapor"),
            ]
        ),
        .target(
            name: "SwiftVSwitchControlPlane",
            dependencies: [
                "SwiftVSwitchControlData",
            ]
        ),
        .target(
            name: "SwiftVSwitchClient",
            dependencies: [
                "SwiftVSwitchControlData",
            ]
        ),
        // ---
        // executables
        // ...
        .executableTarget(
            name: "swvs",
            dependencies: [
                "SwiftVSwitch",
                "SwiftEventLoopPosix",
                "SwiftVSwitchEthFwd",
                "SwiftVSwitchNetStack",
                "SwiftVSwitchControlPlane",
                "SwiftVSwitchClient",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "Sample_EventLoop",
            dependencies: [
                "SwiftEventLoopPosix",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "Sample_TapTunPing",
            dependencies: [
                "SwiftVSwitchTunTap",
                "SwiftEventLoopPosix",
                "SwiftVSwitchEthFwd",
                "SwiftVSwitchNetStack",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "Sample_VirtualServer",
            dependencies: [
                "SwiftVSwitchTunTap",
                "SwiftEventLoopPosix",
                "SwiftVSwitchNetStack",
                "SwiftVSwitchControlPlane",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        // ---
        // native implementations
        // ...
        .target(
            name: "VProxyCommonCHelper"),
        .target(
            name: "SwiftEventLoopPosixCHelper"),
        .target(
            name: "SwiftVSwitchCHelper"),
        .target(
            name: "SwiftVSwitchTunTapCHelper"),
        .target(
            name: "VProxyChecksum",
            path: "submodules/vproxy-checksum"
        ),
        .target(
            name: "libae",
            path: "submodules/libae-valkey/src",
            exclude: ["ae_epoll.c", "ae_epoll_poll.c", "ae_evport.c", "ae_kqueue.c", "ae_poll.c", "ae_select.c"],
            cSettings: [
                .unsafeFlags(["-Wall", "-Wno-shorten-64-to-32", "-Wno-unused-function"]),
            ]
        ),
        .target(
            name: "poptrie",
            path: "submodules/poptrie",
            cSettings: [
                .unsafeFlags(["-Wall", "-Wno-shorten-64-to-32"]),
            ]
        ),
        .target(
            name: "WaitfreeMpscQueue",
            path: "submodules/waitfree-mpsc-queue",
            cSettings: [
                .unsafeFlags(["-Wall", "-Wno-deprecated-pragma"]),
            ]
        ),
        // test cases
        .testTarget(
            name: "unit-tests",
            dependencies: ["SwiftVSwitch", "VProxyCommon", "SwiftEventLoopCommon", "SwiftEventLoopPosix"]
        ),
    ]
)
