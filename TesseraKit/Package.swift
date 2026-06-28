// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TesseraKit",
    products: [
        .library(name: "TesseraKit", targets: ["TesseraKit"]),
    ],
    targets: [
        .target(name: "TesseraKit"),
        .executableTarget(name: "TesseraTests", dependencies: ["TesseraKit"]),
    ]
)
