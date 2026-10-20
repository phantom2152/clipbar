// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "ClipBar", path: "Sources/ClipBar")
    ]
)
