// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpiralKit",
    platforms: [
        .iOS(.v18),
        .watchOS(.v11),
        .macOS(.v15),
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
