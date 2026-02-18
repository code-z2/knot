// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AccountSetup",
    platforms: [.iOS(.v16), .macOS(.v12)],
    products: [
        .library(name: "AccountSetup", targets: ["AccountSetup"]),
    ],
    dependencies: [
        .package(path: "../aa"),
        .package(path: "../sign-handler"),
        .package(path: "../passkey"),
        .package(path: "../keychain"),
    ],
    targets: [
        .target(
            name: "AccountSetup",
            dependencies: [
                .product(name: "AA", package: "aa"),
                .product(name: "SignHandler", package: "sign-handler"),
                .product(name: "Passkey", package: "passkey"),
                .product(name: "Keychain", package: "keychain"),
            ],
        ),
        .testTarget(name: "AccountSetupTests", dependencies: ["AccountSetup"]),
    ],
)
