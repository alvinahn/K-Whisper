// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Voxa",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Voxa", targets: ["Voxa"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Voxa",
            dependencies: [],
            path: "Sources/Voxa",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
