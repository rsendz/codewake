// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Codewaker",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CodewakerKit", targets: ["CodewakerKit"]),
        .executable(name: "codewaker", targets: ["Codewaker"]),
    ],
    targets: [
        .target(name: "CodewakerKit"),
        .executableTarget(name: "Codewaker", dependencies: ["CodewakerKit"]),
        .testTarget(name: "CodewakerKitTests", dependencies: ["CodewakerKit"]),
    ]
)
