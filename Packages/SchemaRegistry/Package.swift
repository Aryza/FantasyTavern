// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SchemaRegistry",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SchemaRegistry", targets: ["SchemaRegistry"]),
    ],
    dependencies: [
        .package(path: "../EntityModel"),
    ],
    targets: [
        .target(name: "SchemaRegistry", dependencies: ["EntityModel"]),
        .testTarget(name: "SchemaRegistryTests", dependencies: ["SchemaRegistry"]),
    ]
)
