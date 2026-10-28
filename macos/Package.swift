// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pocket",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Pocket",
            path: "Sources/Pocket"
        )
    ]
)
