// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CarCast",
    platforms: [
        .iOS(.v16),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CarCast",
            targets: ["CarCast"]
        )
    ],
    targets: [
        .target(
            name: "CarCast",
            path: "Sources/CarCast",
            resources: [
                .process("../../Resources")
            ]
        ),
        .testTarget(
            name: "CarCastTests",
            dependencies: ["CarCast"],
            path: "Tests/CarCastTests"
        )
    ]
)
