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
        ),
        .library(
            name: "TopTimerPersistence",
            targets: ["TopTimerPersistence"]
        )
    ],
    targets: [
        .target(name: "TopTimerDomain"),
        .target(
            name: "TopTimerPersistence",
            dependencies: ["TopTimerDomain"]
        ),
        .testTarget(
            name: "TopTimerDomainTests",
            dependencies: ["TopTimerDomain"]
        ),
        .testTarget(
            name: "TopTimerPersistenceTests",
            dependencies: ["TopTimerDomain", "TopTimerPersistence"]
        )
    ]
)
