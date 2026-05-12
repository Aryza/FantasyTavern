// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WorldStore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WorldStore", targets: ["WorldStore"]),
    ],
    dependencies: [
        .package(path: "../EntityModel"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.6"),
    ],
    targets: [
        .target(
            name: "WorldStore",
            dependencies: [
                "EntityModel",
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .testTarget(
            name: "WorldStoreTests",
            dependencies: ["WorldStore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
