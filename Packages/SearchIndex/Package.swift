// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SearchIndex",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SearchIndex", targets: ["SearchIndex"]),
    ],
    dependencies: [
        .package(path: "../EntityModel"),
    ],
    targets: [
        .target(name: "SearchIndex", dependencies: ["EntityModel"]),
        .testTarget(name: "SearchIndexTests", dependencies: ["SearchIndex"]),
    ]
)
