// swift-tools-version: 5.9
import PackageDescription

/// Stage G: HTTP stub / result queue / call recorder for unit tests.
/// Depends on TracciNetworking only — Feature capability stubs stay in TracciTests.
let package = Package(
    name: "TracciTestSupport",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "TracciTestSupport", targets: ["TracciTestSupport"])
    ],
    dependencies: [
        .package(path: "../TracciNetworking")
    ],
    targets: [
        .target(
            name: "TracciTestSupport",
            dependencies: ["TracciNetworking"],
            path: "Sources/TracciTestSupport"
        )
    ]
)
