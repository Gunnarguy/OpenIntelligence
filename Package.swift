// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenIntelligenceEngine",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "OpenIntelligenceEngine",
            targets: ["OpenIntelligenceEngine"]
        )
    ],
    dependencies: [
        .package(path: "OpenIntelligence/swift-transformers")
    ],
    targets: [
        .target(
            name: "OpenIntelligenceEngine",
            dependencies: [
                .product(name: "Tokenizers", package: "swift-transformers")
            ],
            path: "OpenIntelligence",
            exclude: [
                "App",
                "Features",
                "OpenIntelligence.entitlements",
                "Services/Billing",
                "UI",
                "swift-transformers",
                "Core/Extensions/MarkdownRenderer.swift",
                "Core/Extensions/KeychainStorage.swift",
                "Core/Extensions/LaunchArguments.swift",
                "Services/Agentic/RAGAppIntents.swift",
                "Services/Agentic/VisualIntelligenceIntents.swift",
                "Services/Agentic/WritingToolsService.swift",
                "Services/Infrastructure/Background",
                "Services/Infrastructure/Integration/ImagePlaygroundService.swift",
                "Services/Infrastructure/Presentation",
                "Services/Infrastructure/Tips",
                "Services/LLM/ModelResolutionService.swift",
                "Services/LLM/LocalOpenAIServerLLMService.swift",
                "Services/Storage/DocumentationCacheService.swift",
                "Resources/Assets",
                "Resources/StoreKit",
                "Core/Support/test_write.txt",
                "Services/Evaluation"
            ],
            sources: [
                "Core",
                "SDK",
                "Services/Agentic",
                "Services/AIPlatform",
                "Services/Document",
                "Services/Embedding",
                "Services/Infrastructure/Compute",
                "Services/Infrastructure/Configuration",
                "Services/Infrastructure/Integration",
                "Services/Infrastructure/Monitoring",
                "Services/Infrastructure/Optimization",
                "Services/Infrastructure/Storage",
                "Services/LLM",
                "Services/Query",
                "Services/RAG",
                "Services/Storage",
                "Services/VectorStore"
            ],
            resources: [
                .copy("Resources/MLModels/EmbeddingModel.mlpackage"),
                .copy("Resources/MLModels/ReRankerModel.mlpackage"),
                .copy("Resources/MLModels/embedding_vocab.json"),
                .copy("Resources/MLModels/reranker_vocab.json"),
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            swiftSettings: [
                .define("OPENINTELLIGENCE_ENGINE_SDK"),
                .unsafeFlags([
                    "-default-isolation=MainActor",
                    "-enable-bare-slash-regex",
                    "-enable-upcoming-feature", "DisableOutwardActorInference",
                    "-enable-upcoming-feature", "InferSendableFromCaptures",
                    "-enable-upcoming-feature", "GlobalActorIsolatedTypesUsability",
                    "-enable-upcoming-feature", "MemberImportVisibility",
                    "-enable-upcoming-feature", "InferIsolatedConformances",
                    "-enable-upcoming-feature", "NonisolatedNonsendingByDefault",
                    "-enable-experimental-feature", "DebugDescriptionMacro"
                ])
            ]
        ),
        .testTarget(
            name: "OpenIntelligenceEngineTests",
            dependencies: ["OpenIntelligenceEngine"],
            path: "OpenIntelligenceTests"
        )
    ],
    swiftLanguageModes: [
        .v5
    ]
)
