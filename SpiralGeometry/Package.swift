// swift-tools-version: 6.0

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
    ]
)
