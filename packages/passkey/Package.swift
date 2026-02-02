// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "Passkey",
  platforms: [.iOS(.v16), .macOS(.v12)],
  products: [
    .library(name: "Passkey", targets: ["Passkey"])
  ],
  dependencies: [
    .package(url: "https://github.com/valpackett/SwiftCBOR.git", from: "0.6.0")
  ],
  targets: [
    .target(
      name: "Passkey",
      dependencies: [
        .product(name: "SwiftCBOR", package: "SwiftCBOR")
      ]
    ),
    .testTarget(name: "PasskeyTests", dependencies: ["Passkey"])
  ]
)
