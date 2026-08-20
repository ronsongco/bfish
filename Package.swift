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
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "BFishCore"
        ),
        .executableTarget(
            name: "bfish",
            dependencies: [
                "BFishCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "BFishCoreTests",
            dependencies: ["BFishCore"]
        ),
    ]
)
