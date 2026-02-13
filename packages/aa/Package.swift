// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "AA",
  platforms: [.iOS(.v16), .macOS(.v12)],
  products: [
    .library(name: "AA", targets: ["AA"])
  ],
  dependencies: [
    .package(path: "../passkey"),
    .package(path: "../rpc"),
    .package(path: "../transactions"),
    .package(url: "https://github.com/web3swift-team/web3swift.git", branch: "develop"),
  ],
  targets: [
    .target(
      name: "AA",
      dependencies: [
        .product(name: "Passkey", package: "passkey"),
        .product(name: "RPC", package: "rpc"),
        .product(name: "Transactions", package: "transactions"),
        .product(name: "web3swift", package: "web3swift"),
      ]
    ),
    .testTarget(
      name: "AATests",
      dependencies: [
        "AA",
        .product(name: "Passkey", package: "passkey"),
        .product(name: "Transactions", package: "transactions"),
      ]
    )
  ]
)
