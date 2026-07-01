// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-transformers",
    platforms: [
        .iOS("17.0"),
        .macOS("14.0")
    ],
    products: [
        .library(name: "TransformersTokenizers", targets: ["TransformersTokenizers"])
    ],
    dependencies: [
        .package(url: "https://github.com/DePasqualeOrg/swift-tokenizers.git", from: "0.5.0")
    ],
    targets: [
        .target(
            name: "TransformersTokenizers",
            dependencies: [
                .product(name: "Tokenizers", package: "swift-tokenizers")
            ],
            path: "Sources/TokenizersWrapper"
        )
    ]
)

