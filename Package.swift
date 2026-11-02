// swift-tools-version: 5.9
import PackageDescription
import Foundation

var testSwiftSettings: [SwiftSetting] = []
let cltMacroPath = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if FileManager.default.fileExists(atPath: cltMacroPath) {
    testSwiftSettings.append(.unsafeFlags(["-load-plugin-library", cltMacroPath]))
}

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
        ),
        .testTarget(
            name: "StageFlowTests",
            dependencies: ["StageFlow"],
            path: "Tests/StageFlowTests",
            swiftSettings: testSwiftSettings
        )
    ]
)
