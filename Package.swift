// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "swift-vswitch",
    products: [
        .executable(name: "swvs", targets: ["swvs"]),
        .library(name: "swift-vswitch", targets: ["SwiftVSwitch"]),
        .executable(name: "sample-eventloop", targets: ["Sample_EventLoop"]),
    ],
    dependencies: [
        .package(url: "https://github.com/davecom/SwiftPriorityQueue.git", revision: "1.4.0"),
        .package(url: "https://github.com/apple/swift-collections.git", revision: "1.1.4"),
        .package(url: "https://github.com/apple/swift-argument-parser", revision: "1.5.0"),
    ],
    targets: [
        .target(
            name: "VProxyCommon",
            dependencies: [
                .product(name: "Collections", package: "swift-collections"),
            ]
        ),
        .target(
            name: "SwiftEventLoopCommon",
            dependencies: ["VProxyCommon"]
        ),
        .target(
            name: "SwiftVSwitch",
            dependencies: [
                "SwiftEventLoopCommon", "SwiftPriorityQueue",
            ]
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
            name: "SwiftEventLoopPosixCHelper"),
        .target(
            name: "SwiftEventLoopPosix",
            dependencies: ["SwiftEventLoopPosixCHelper", "SwiftEventLoopCommon", "libae"]
        ),
        .executableTarget(
            name: "swvs",
            dependencies: ["SwiftEventLoopPosix", "SwiftVSwitch"]
        ),
        .executableTarget(
            name: "Sample_EventLoop",
            dependencies: [
                "SwiftEventLoopPosix",
                "SwiftPriorityQueue",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "unit-tests",
            dependencies: ["VProxyCommon", "SwiftEventLoopCommon", "SwiftEventLoopPosix", "SwiftPriorityQueue"]
        ),
    ]
)
