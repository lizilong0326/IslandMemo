// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IslandMemo",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "IslandMemo", targets: ["IslandMemo"])],
    dependencies: [
        .package(url: "https://github.com/6tail/lunar-swift.git", exact: "1.1.8"),
    ],
    targets: [
        .executableTarget(
            name: "IslandMemo",
            dependencies: [
                .product(name: "LunarSwift", package: "lunar-swift"),
            ],
            path: "Sources/IslandMemo",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
