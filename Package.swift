// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DrivingMode",
    platforms: [
        .iOS(.v16),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "DrivingMode",
            targets: ["DrivingMode"]
        )
    ],
    targets: [
        .target(
            name: "DrivingMode",
            path: "Sources/DrivingMode",
            resources: [
                .process("../../Resources")
            ]
        ),
        .testTarget(
            name: "DrivingModeTests",
            dependencies: ["DrivingMode"],
            path: "Tests/DrivingModeTests"
        )
    ]
)
