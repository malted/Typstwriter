// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Compiler",
    platforms: [.macOS(.v13)],
    products: [.library(name: "Compiler", targets: ["Compiler"])],
    targets: [
        .binaryTarget(name: "Compiler", path: "Compiler.xcframework")
    ]
)
