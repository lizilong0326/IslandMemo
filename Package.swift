// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IslandMemo",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "IslandMemo", targets: ["IslandMemo"])],
    targets: [
        .executableTarget(
            name: "IslandMemo",
            path: "Sources/IslandMemo"
        )
    ]
)
