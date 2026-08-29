// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Jiggypuff",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Jiggypuff", targets: ["Jiggypuff"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Jiggypuff",
            dependencies: [],
            path: "Sources/Jiggypuff"
        )
    ]
)
