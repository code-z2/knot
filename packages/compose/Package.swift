// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "Compose",
  platforms: [.iOS(.v16), .macOS(.v12)],
  products: [
    .library(name: "Compose", targets: ["Compose"])
  ],
  dependencies: [
    .package(path: "../aa"),
    .package(path: "../balance"),
    .package(path: "../rpc"),
    .package(path: "../transactions"),
  ],
  targets: [
    .target(
      name: "Compose",
      dependencies: [
        .product(name: "AA", package: "aa"),
        .product(name: "Balance", package: "balance"),
        .product(name: "RPC", package: "rpc"),
        .product(name: "Transactions", package: "transactions"),
      ]
    )
  ]
)
