// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SnorOhSwift",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio", from: "2.65.0"),
    ],
    targets: [
        .executableTarget(
            name: "SnorOhSwift",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ],
            path: "Sources",
            resources: [
                .copy("../Resources/Sprites"),
                .copy("../Resources/Sounds"),
                .copy("../Resources/Scripts"),
            ]
        ),
        .testTarget(
            name: "SnorOhSwiftTests",
            dependencies: ["SnorOhSwift"],
            path: "Tests"
        ),
    ]
)
