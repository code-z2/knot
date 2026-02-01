// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "ENS",
  platforms: [.iOS(.v16)],
  products: [
    .library(name: "ENS", targets: ["ENS"])
  ],
  targets: [
    .target(name: "ENS"),
    .testTarget(name: "ENSTests", dependencies: ["ENS"])
  ]
)
