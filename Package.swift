// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Jigglypuff",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Jigglypuff", targets: ["Jigglypuff"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Jigglypuff",
            dependencies: [],
            path: "Sources/Jigglypuff"
        )
    ]
)
