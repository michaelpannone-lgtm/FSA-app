// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HSACore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "HSACore", targets: ["HSACore"])
    ],
    targets: [
        .target(name: "HSACore"),
        .testTarget(name: "HSACoreTests", dependencies: ["HSACore"])
    ]
)
