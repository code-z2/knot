// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RPC",
    platforms: [.iOS(.v16), .macOS(.v10_15)],
    products: [
        .library(name: "RPC", targets: ["RPC"]),
    ],
    dependencies: [
        .package(url: "https://github.com/web3swift-team/web3swift.git", branch: "develop"),
    ],
    targets: [
        .target(
            name: "RPC",
            dependencies: [
                .product(name: "web3swift", package: "web3swift"),
            ],
        ),
        .testTarget(name: "RPCTests", dependencies: ["RPC"]),
    ],
)
