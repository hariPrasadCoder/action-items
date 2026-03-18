// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ActionItems",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "ActionItems",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/ActionItems"
        )
    ]
)
