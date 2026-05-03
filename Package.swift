// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Holos",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Holos", targets: ["Holos"]),
    ],
    targets: [
        .executableTarget(
            name: "Holos",
            path: "Sources/Holos"
        ),
    ]
)
