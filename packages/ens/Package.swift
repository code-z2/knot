// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "ENS",
  platforms: [.iOS(.v16), .macOS(.v10_15)],
  products: [
    .library(name: "ENS", targets: ["ENS"])
  ],
  dependencies: [
    .package(url: "https://github.com/web3swift-team/web3swift.git", branch: "develop"),
    .package(path: "../rpc"),
    .package(path: "../transactions"),
  ],
  targets: [
    .target(
      name: "ENS",
      dependencies: [
        .product(name: "web3swift", package: "web3swift"),
        .product(name: "RPC", package: "rpc"),
        .product(name: "Transactions", package: "transactions"),
      ]
    ),
    .testTarget(name: "ENSTests", dependencies: ["ENS"])
  ]
)
