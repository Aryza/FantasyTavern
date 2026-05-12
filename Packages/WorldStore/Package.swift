// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WorldStore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WorldStore", targets: ["WorldStore"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "WorldStore"),
        .testTarget(name: "WorldStoreTests", dependencies: ["WorldStore"]),
    ]
)
