// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Codewake",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CodewakeKit", targets: ["CodewakeKit"]),
        .executable(name: "codewake", targets: ["Codewake"]),
    ],
    targets: [
        .target(name: "CodewakeKit"),
        .executableTarget(name: "Codewake", dependencies: ["CodewakeKit"]),
        .testTarget(name: "CodewakeKitTests", dependencies: ["CodewakeKit"]),
    ]
)
