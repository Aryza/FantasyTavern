// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "EntityModel",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EntityModel", targets: ["EntityModel"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "EntityModel"),
        .testTarget(name: "EntityModelTests", dependencies: ["EntityModel"]),
    ]
)
