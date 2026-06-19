// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HeartbeatSDKSwift",
    platforms: [
        .iOS(.v14),
        .watchOS(.v7)
    ],
    products: [
        .library(
            name: "HeartbeatSDKSwift",
            targets: ["HeartbeatSDKSwift"]),
    ],
    targets: [
        .target(
            name: "HeartbeatSDKSwift")
    ]
)
