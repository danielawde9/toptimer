// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TopTimer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "TopTimerDomain",
            targets: ["TopTimerDomain"]
        )
    ],
    targets: [
        .target(name: "TopTimerDomain"),
        .testTarget(
            name: "TopTimerDomainTests",
            dependencies: ["TopTimerDomain"]
        )
    ]
)
