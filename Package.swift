// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexUsageMenuBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexUsageMenuBar", targets: ["CodexUsageMenuBar"]),
        .library(name: "UsageCore", targets: ["UsageCore"])
    ],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(
            name: "CodexUsageMenuBar",
            dependencies: ["UsageCore"]
        ),
        .testTarget(
            name: "UsageCoreTests",
            dependencies: ["UsageCore"]
        )
    ]
)
