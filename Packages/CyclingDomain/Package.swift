// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CyclingDomain",
    platforms: [.macOS(.v13), .iOS(.v17), .watchOS(.v10)],
    products: [
        .library(name: "CyclingDomain", targets: ["CyclingDomain"]),
    ],
    targets: [
        .target(name: "CyclingDomain"),
        .testTarget(name: "CyclingDomainTests", dependencies: ["CyclingDomain"]),
    ]
)
