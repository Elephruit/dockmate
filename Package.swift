// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DockMate",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "DockMate", targets: ["DockMate"])],
    targets: [
        .target(name: "DockMateCore"),
        .executableTarget(name: "DockMate", dependencies: ["DockMateCore"]),
        .testTarget(name: "DockMateCoreTests", dependencies: ["DockMateCore"])
    ]
)
