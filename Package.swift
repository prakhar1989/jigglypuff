// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Transrib",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Transrib", targets: ["Transrib"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Transrib",
            dependencies: [],
            path: "Sources/Transrib"
        )
    ]
)
