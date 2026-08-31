// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NumberSniperCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NumberSniperCore", targets: ["NumberSniperCore"])
    ],
    targets: [
        .target(name: "NumberSniperCore"),
        .testTarget(name: "NumberSniperCoreTests", dependencies: ["NumberSniperCore"])
    ]
)
