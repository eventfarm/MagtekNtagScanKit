// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MagtekNtagScanKit",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "MagtekNtagScanKit",
            targets: ["MagtekNtagScanKit"]),
    ],
    targets: [
        .target(
            name: "MagtekNtagScanKit",
            dependencies: [.target(name: "MTSCRA")]
        ),
        .binaryTarget(
            name: "MTSCRA",
            path: "./Sources/MTSCRA.xcframework"
        )
    ]
)
