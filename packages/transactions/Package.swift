// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "Transactions",
  platforms: [.iOS(.v16), .macOS(.v10_15)],
  products: [
    .library(name: "Transactions", targets: ["Transactions"])
  ],
  targets: [
    .target(name: "Transactions"),
    .testTarget(name: "TransactionsTests", dependencies: ["Transactions"])
  ]
)
