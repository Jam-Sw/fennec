// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "fennec",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Fennec", targets: ["FennecApp"]),
        .executable(name: "fennec", targets: ["FennecCLI"]),
        .library(name: "FennecCore", targets: ["FennecCore"]),
        .library(name: "FennecEngine", targets: ["FennecEngine"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Desert-Ant-Labs/desert-ant-core.git", from: "3.3.0"),
    ],
    targets: [
        .target(name: "FennecCore"),
        .target(name: "FennecEngine", dependencies: [
            "FennecCore",
            .product(name: "Voz", package: "desert-ant-core"),
        ]),
        .executableTarget(name: "FennecApp", dependencies: ["FennecCore", "FennecEngine"]),
        .executableTarget(name: "FennecCLI", dependencies: ["FennecCore", "FennecEngine"]),
        .testTarget(name: "FennecCoreTests", dependencies: ["FennecCore"]),
    ]
)
