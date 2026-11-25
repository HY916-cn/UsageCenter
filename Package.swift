// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "UsageCenter",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "UsageCenterCore", targets: ["UsageCenterCore"]),
        .executable(name: "UsageCenter", targets: ["UsageCenter"])
    ],
    targets: [
        .target(
            name: "UsageCenterCore",
            path: "Sources/UsageCenterCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "UsageCenter",
            dependencies: ["UsageCenterCore"],
            path: "Sources/UsageCenter",
            resources: [
                .copy("Resources/Icons")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "UsageCenterCoreTests",
            dependencies: ["UsageCenterCore"],
            path: "Tests/UsageCenterCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
