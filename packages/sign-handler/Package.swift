// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SignHandler",
    platforms: [.iOS(.v16), .macOS(.v10_15)],
    products: [
        .library(name: "SignHandler", targets: ["SignHandler"]),
    ],
    dependencies: [
        .package(url: "https://github.com/web3swift-team/web3swift.git", branch: "develop"),
    ],
    targets: [
        .target(
            name: "SignHandler",
            dependencies: [
                .product(name: "web3swift", package: "web3swift"),
            ],
        ),
        .testTarget(name: "SignHandlerTests", dependencies: ["SignHandler"]),
    ],
)
