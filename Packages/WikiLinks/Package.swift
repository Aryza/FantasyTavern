// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WikiLinks",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WikiLinks", targets: ["WikiLinks"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "WikiLinks"),
        .testTarget(name: "WikiLinksTests", dependencies: ["WikiLinks"]),
    ]
)
