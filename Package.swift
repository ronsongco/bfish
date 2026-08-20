// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "bfish",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(name: "BFishCore", targets: ["BFishCore"]),
        .library(name: "BFishWhisperKit", targets: ["BFishWhisperKit"]),
        .executable(name: "bfish", targets: ["bfish"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "BFishCore"
        ),
        .target(
            name: "BFishWhisperKit",
            dependencies: [
                "BFishCore",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ]
        ),
        .executableTarget(
            name: "bfish",
            dependencies: [
                "BFishCore",
                "BFishWhisperKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "BFishCoreTests",
            dependencies: ["BFishCore"]
        ),
        .testTarget(
            name: "BFishWhisperKitTests",
            dependencies: ["BFishWhisperKit"]
        ),
    ]
)
