// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "KanataUI",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "KanataUI", targets: ["KanataUI"])
    ],
    targets: [
        .executableTarget(
            name: "KanataUI",
            path: "Sources/KanataUI"
        ),
        .testTarget(
            name: "KanataUITests",
            dependencies: ["KanataUI"],
            path: "Tests/KanataUITests"
        )
    ]
)
