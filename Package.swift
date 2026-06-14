// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MindWeaver",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MindWeaver", targets: ["MindWeaver"])
    ],
    targets: [
        .executableTarget(
            name: "MindWeaver",
            path: "Sources/MindWeaver"
        ),
    ],
    swiftLanguageModes: [.v6]
)
