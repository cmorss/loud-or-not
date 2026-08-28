// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LoudOrNot",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "LoudOrNotCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "LoudOrNot",
            dependencies: ["LoudOrNotCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "LoudOrNotCoreTests",
            dependencies: ["LoudOrNotCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
