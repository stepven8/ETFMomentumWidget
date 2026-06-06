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
        .target(name: "ETFMomentumCore"),
        .executableTarget(
            name: "ETFMomentumApp",
            dependencies: ["ETFMomentumCore"]
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
