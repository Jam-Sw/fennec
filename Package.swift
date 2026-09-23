// swift-tools-version: 6.2
import PackageDescription

// The installer sets FENNEC_APP_ONLY so an end-user build never resolves the
// test-only packages (swift-testing, and swift-syntax behind it). Tests need
// swift-testing because the Command Line Tools ship no Testing module.
let appOnly = Context.environment["FENNEC_APP_ONLY"] != nil

let testTargets: [Target] = appOnly ? [] : [
    .testTarget(name: "FennecCoreTests", dependencies: [
        "FennecCore",
        .product(name: "Testing", package: "swift-testing"),
    ]),
]

let package = Package(
    name: "fennec",
    // A version string rather than `.v15`: Swift 6.4 failed to resolve the member form.
    platforms: [.macOS("15.0")],
    products: [
        .executable(name: "Fennec", targets: ["FennecApp"]),
        .executable(name: "fennec", targets: ["FennecCLI"]),
        .library(name: "FennecCore", targets: ["FennecCore"]),
        .library(name: "FennecEngine", targets: ["FennecEngine"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Desert-Ant-Labs/desert-ant-core.git", from: "3.3.0"),
    ] + (appOnly ? [] : [
        .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.2.4"),
    ]),
    targets: [
        .target(name: "FennecCore"),
        .target(name: "FennecEngine", dependencies: [
            "FennecCore",
            .product(name: "Voz", package: "desert-ant-core"),
        ]),
        .executableTarget(name: "FennecApp", dependencies: ["FennecCore", "FennecEngine"]),
        .executableTarget(name: "FennecCLI", dependencies: ["FennecCore", "FennecEngine"]),
    ] + testTargets
)
