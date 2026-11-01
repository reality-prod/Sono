// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "Sono",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CLyricsEngine",
            path: "Sources/CLyricsEngine",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "Sono",
            dependencies: ["CLyricsEngine"],
            path: "Sources/Sono"
        )
    ]
)
