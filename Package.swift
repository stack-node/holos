// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Talos",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Talos", targets: ["Talos"]),
    ],
    targets: [
        .executableTarget(
            name: "Talos",
            path: "Sources/Talos"
        ),
    ]
)
