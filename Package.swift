// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "UsageCenter",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "UsageCenterCore", targets: ["UsageCenterCore"]),
        .executable(name: "UsageCenter", targets: ["UsageCenter"])
    ],
    targets: [
        .target(
            name: "UsageCenterCore",
            path: "Sources/UsageCenterCore"
        ),
        .executableTarget(
            name: "UsageCenter",
            dependencies: ["UsageCenterCore"],
            path: "Sources/UsageCenter",
            resources: [
                .copy("Resources/Icons")
            ]
        ),
        .testTarget(
            name: "UsageCenterCoreTests",
            dependencies: ["UsageCenterCore"],
            path: "Tests/UsageCenterCoreTests"
        )
    ]
)
