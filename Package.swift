// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Folderist",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Folderist",
            path: "Folderist"
        ),
        .testTarget(
            name: "FolderistTests",
            dependencies: ["Folderist"],
            path: "FolderistTests"
        ),
    ]
)
