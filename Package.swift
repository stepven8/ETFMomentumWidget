// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ETFMomentumWidget",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ETFMomentumCore", targets: ["ETFMomentumCore"]),
        .executable(name: "ETFMomentumApp", targets: ["ETFMomentumApp"]),
        .executable(name: "ETFMomentumSmoke", targets: ["ETFMomentumSmoke"]),
        .library(name: "ETFMomentumWidgetExtension", targets: ["ETFMomentumWidgetExtension"])
    ],
    targets: [
        .target(
            name: "ETFMomentumCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "ETFMomentumApp",
            dependencies: ["ETFMomentumCore"],
            resources: [
                .copy("Resources/纯五福七星ETF轮动策略（实测可行）.txt")
            ]
        ),
        .executableTarget(
            name: "ETFMomentumSmoke",
            dependencies: ["ETFMomentumCore"]
        ),
        .target(
            name: "ETFMomentumWidgetExtension",
            dependencies: ["ETFMomentumCore"]
        ),
        .testTarget(
            name: "ETFMomentumCoreTests",
            dependencies: ["ETFMomentumCore"]
        )
    ]
)
