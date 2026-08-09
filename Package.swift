// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DustEater",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "DustEaterCore", targets: ["DustEaterCore"]),
        .executable(name: "dustbench", targets: ["dustbench"]),
        .executable(name: "appsizes", targets: ["appsizes"]),
        .executable(name: "DustEaterApp", targets: ["DustEaterApp"])
    ],
    targets: [
        .target(
            name: "DustEaterCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "dustbench",
            dependencies: ["DustEaterCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "appsizes",
            dependencies: ["DustEaterCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "DustEaterApp",
            dependencies: ["DustEaterCore"],
            resources: [
                .copy("Resources/AppIcon.png")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "DustEaterCoreTests",
            dependencies: ["DustEaterCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
