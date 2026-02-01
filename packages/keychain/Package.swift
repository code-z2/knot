// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "Keychain",
  platforms: [.iOS(.v16)],
  products: [
    .library(name: "Keychain", targets: ["Keychain"])
  ],
  targets: [
    .target(name: "Keychain"),
    .testTarget(name: "KeychainTests", dependencies: ["Keychain"])
  ]
)
