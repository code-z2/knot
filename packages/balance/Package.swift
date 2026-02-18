// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Balance",
    platforms: [.iOS(.v16), .macOS(.v10_15)],
    products: [
        .library(name: "Balance", targets: ["Balance"]),
    ],
    dependencies: [
        .package(path: "../rpc"),
    ],
    targets: [
        .target(name: "Balance", dependencies: [
            .product(name: "RPC", package: "rpc"),
        ]),
        .testTarget(name: "BalanceTests", dependencies: ["Balance"]),
    ],
)
