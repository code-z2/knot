// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "SignHandler",
  platforms: [.iOS(.v16)],
  products: [
    .library(name: "SignHandler", targets: ["SignHandler"])
  ],
  targets: [
    .target(name: "SignHandler"),
    .testTarget(name: "SignHandlerTests", dependencies: ["SignHandler"])
  ]
)
