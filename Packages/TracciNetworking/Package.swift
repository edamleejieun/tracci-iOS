// swift-tools-version: 5.9
import PackageDescription

/// Stage G: isolated networking layer for APIClient / Endpoint / Error / Upload.
/// Depends only on Foundation. Token supply is injected via `AccessTokenProviding`.
let package = Package(
    name: "TracciNetworking",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "TracciNetworking", targets: ["TracciNetworking"])
    ],
    targets: [
        .target(
            name: "TracciNetworking",
            path: "Sources/TracciNetworking"
        ),
        .testTarget(
            name: "TracciNetworkingTests",
            dependencies: ["TracciNetworking"],
            path: "Tests/TracciNetworkingTests"
        )
    ]
)
