// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WikiLinks",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WikiLinks", targets: ["WikiLinks"]),
    ],
    dependencies: [
        .package(path: "../EntityModel"),
    ],
    targets: [
        .target(name: "WikiLinks", dependencies: ["EntityModel"]),
        .testTarget(name: "WikiLinksTests", dependencies: ["WikiLinks"]),
    ]
)
