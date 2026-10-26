// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LLMTranslator",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1")
    ],
    targets: [
        .target(
            name: "LLMTranslatorCore",
            path: "Sources/LLMTranslatorCore"
        ),
        .executableTarget(
            name: "LLMTranslator",
            dependencies: [
                "LLMTranslatorCore",
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ],
            path: "Sources/LLMTranslator"
        ),
        .testTarget(
            name: "LLMTranslatorCoreTests",
            dependencies: ["LLMTranslatorCore"],
            path: "Tests/LLMTranslatorCoreTests"
        ),
        .testTarget(
            name: "LLMTranslatorTests",
            dependencies: ["LLMTranslator"],
            path: "Tests/LLMTranslatorTests"
        )
    ]
)
