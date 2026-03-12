// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpiralKit",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(name: "SpiralKit", targets: ["SpiralKit"]),
    ],
    targets: [
        .target(
            name: "SpiralKit",
            path: "Sources/SpiralKit"
        ),
        .testTarget(
            name: "SpiralKitTests",
            dependencies: ["SpiralKit"],
            path: "Tests/SpiralKitTests"
        ),
    ]
)
