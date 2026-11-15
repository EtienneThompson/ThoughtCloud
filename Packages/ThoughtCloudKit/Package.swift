// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThoughtCloudKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ThoughtCloudKit", targets: ["ThoughtCloudKit"]),
    ],
    targets: [
        .target(name: "ThoughtCloudKit"),
        .testTarget(name: "ThoughtCloudKitTests", dependencies: ["ThoughtCloudKit"]),
    ]
)
