// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SpaceGrab",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "SpaceGrab", path: "Sources/SpaceGrab")
    ]
)
