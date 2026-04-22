// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SpiralGeometry",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(name: "SpiralGeometry", targets: ["SpiralGeometry"]),
    ],
    targets: [
        .target(name: "SpiralGeometry"),
        .testTarget(name: "SpiralGeometryTests", dependencies: ["SpiralGeometry"]),
    ]
)
