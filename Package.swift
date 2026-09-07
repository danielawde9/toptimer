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
        ),
        .library(
            name: "TopTimerSystem",
            targets: ["TopTimerSystem"]
        ),
        .library(
            name: "TopTimerApp",
            targets: ["TopTimerApp"]
        ),
        .executable(name: "TopTimer", targets: ["TopTimerExecutable"])
    ],
    targets: [
        .target(name: "TopTimerDomain"),
        .target(
            name: "TopTimerPersistence",
            dependencies: ["TopTimerDomain"]
        ),
        .target(name: "TopTimerSystem", dependencies: ["TopTimerDomain"]),
        .target(
            name: "TopTimerApp",
            dependencies: ["TopTimerDomain", "TopTimerPersistence", "TopTimerSystem"]
        ),
        .executableTarget(name: "TopTimerExecutable", dependencies: ["TopTimerApp"]),
        .testTarget(
            name: "TopTimerDomainTests",
            dependencies: ["TopTimerDomain"]
        ),
        .testTarget(
            name: "TopTimerPersistenceTests",
            dependencies: ["TopTimerDomain", "TopTimerPersistence"]
        ),
        .testTarget(
            name: "TopTimerSystemTests",
            dependencies: ["TopTimerSystem", "TopTimerDomain"]
        ),
        .testTarget(
            name: "TopTimerAppTests",
            dependencies: ["TopTimerApp", "TopTimerDomain", "TopTimerPersistence"]
        )
    ]
)
