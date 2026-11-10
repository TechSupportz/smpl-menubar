// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SmplMenubar",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "SmplMenubar", path: "Sources/SmplMenubar"),
    ]
)
