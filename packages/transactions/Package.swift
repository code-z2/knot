// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Transactions",
    platforms: [.iOS(.v16), .macOS(.v10_15)],
    products: [
        .library(name: "Transactions", targets: ["Transactions"]),
    ],
    dependencies: [
        .package(path: "../rpc"),
    ],
    targets: [
        .target(name: "Transactions", dependencies: [
            .product(name: "RPC", package: "rpc"),
        ]),
        .testTarget(name: "TransactionsTests", dependencies: ["Transactions"]),
    ],
)
