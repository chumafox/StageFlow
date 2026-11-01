// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StageFlow",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "StageFlow", targets: ["StageFlow"])
    ],
    targets: [
        .executableTarget(
            name: "StageFlow",
            path: "Sources/StageFlow"
        )
    ]
)
