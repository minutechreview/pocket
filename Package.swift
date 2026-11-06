// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchClip",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "NotchClipCore"),
        .executableTarget(name: "NotchClip", dependencies: ["NotchClipCore"]),
        .testTarget(name: "NotchClipCoreTests", dependencies: ["NotchClipCore"]),
    ],
    swiftLanguageModes: [.v5]
)
