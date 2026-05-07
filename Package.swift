// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KWhisper",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "KWhisper", targets: ["KWhisper"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "KWhisper",
            dependencies: [],
            path: "Sources/KWhisper",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
