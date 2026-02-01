// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "Passkey",
  platforms: [.iOS(.v16)],
  products: [
    .library(name: "Passkey", targets: ["Passkey"])
  ],
  targets: [
    .target(name: "Passkey"),
    .testTarget(name: "PasskeyTests", dependencies: ["Passkey"])
  ]
)
