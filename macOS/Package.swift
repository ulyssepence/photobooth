// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "photobooth",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "photobooth",
            path: "Sources",
            exclude: ["Info.plist"],
            resources: [.process("Shaders")]
        )
    ]
)
