// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TesseraKit",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "TesseraKit", targets: ["TesseraKit"]),
        .library(name: "TesseraSystem", targets: ["TesseraSystem"]),
    ],
    targets: [
        .target(name: "TesseraKit"),
        .target(name: "TesseraSystem", dependencies: ["TesseraKit"]),
        .executableTarget(name: "TesseraTests", dependencies: ["TesseraKit", "TesseraSystem"]),
        .executableTarget(name: "WindowDiscover", dependencies: ["TesseraSystem"]),
        .executableTarget(name: "TesseraDaemon", dependencies: ["TesseraKit", "TesseraSystem"]),
        .executableTarget(name: "TesseraMenu", dependencies: []),
    ]
)
