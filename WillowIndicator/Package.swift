// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WillowIndicator",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "WillowIndicator",
            path: "Sources"
        )
    ]
)
