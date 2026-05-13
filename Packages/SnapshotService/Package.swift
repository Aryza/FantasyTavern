// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SnapshotService",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SnapshotService", targets: ["SnapshotService"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "SnapshotService"),
        .testTarget(name: "SnapshotServiceTests", dependencies: ["SnapshotService"]),
    ]
)
