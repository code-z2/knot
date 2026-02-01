// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "Balance",
  platforms: [.iOS(.v16)],
  products: [
    .library(name: "Balance", targets: ["Balance"])
  ],
  targets: [
    .target(name: "Balance"),
    .testTarget(name: "BalanceTests", dependencies: ["Balance"])
  ]
)
