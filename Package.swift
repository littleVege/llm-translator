// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LLMTranslator",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "LLMTranslatorCore",
            path: "Sources/LLMTranslatorCore"
        ),
        .executableTarget(
            name: "LLMTranslator",
            dependencies: ["LLMTranslatorCore"],
            path: "Sources/LLMTranslator"
        ),
        .testTarget(
            name: "LLMTranslatorCoreTests",
            dependencies: ["LLMTranslatorCore"],
            path: "Tests/LLMTranslatorCoreTests"
        )
    ]
)
