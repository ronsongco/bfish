// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "bfish",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(name: "BFishCore", targets: ["BFishCore"]),
        .executable(name: "bfish", targets: ["bfish"]),
    ],
    targets: [
        .target(
            name: "BFishCore"
        ),
        .executableTarget(
            name: "bfish",
            dependencies: ["BFishCore"]
        ),
        .testTarget(
            name: "BFishCoreTests",
            dependencies: ["BFishCore"]
        ),
    ]
)
