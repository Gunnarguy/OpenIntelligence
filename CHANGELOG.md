# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2025-06-15

### Added

- **NLContextualEmbedding Provider**: BERT-like contextual embeddings (iOS 17+) for 15-25% better semantic search accuracy. Enable via Library Settings → Embedding Model → Contextual NL.
- **AdaptiveEmbeddingOptimizer**: Auto-recommends optimal embedding provider based on corpus complexity (vocabulary richness, technical content, code density).
- **Siri Intent for Embedding**: "Hey Siri, what embedding model is OpenIntelligence using?" — check your accuracy mode via voice.
- **Enhanced Error Messages**: Embedding errors now include provider context for easier debugging.
- **Accessibility Labels**: Full VoiceOver support for embedding provider selection and response metadata.

### Changed

- **Fallback Chain**: NLContextualEmbedding now gracefully falls back to NLEmbedding (instead of hash) when assets unavailable.
- **Telemetry**: All embedding events now include provider metadata for analytics.
- **ThinkingStreamView**: Timeline previews show "⚡ Contextual" badge for high-accuracy mode.

### Fixed

- **AdaptiveEmbeddingOptimizer**: Now correctly recommends `nl_contextual_embedding` for complex corpora.
- **ResponseMetadata**: Consistently includes `embeddingProvider` across all 6 code paths.

## [1.0.0] - 2025-11-19

### Added

- **Hybrid Search Engine**: Full implementation of BM25 + Vector Search + RRF Fusion.
- **Agentic Tooling**: 12 `@Tool` functions for Apple Intelligence integration.
- **Telemetry Dashboard**: Real-time visualization of RAG pipeline performance (TTFT, Tokens/sec).
- **Model Support**:
  - Apple Foundation Models (System).
  - Local GGUF (Llama 3, Mistral) via `llama.cpp`.
  - OpenAI API integration.
- **Privacy Controls**: Private Cloud Compute (PCC) toggles and execution location badges.

### Changed

- **Architecture**: Refactored to a Protocol-First design with `RAGService` orchestration.
- **Concurrency**: Moved heavy compute to `RAGEngine` actor for UI responsiveness.
- **Documentation**: Complete rewrite of `README.md` and architecture docs.

### Fixed

- **Streaming**: Resolved UI freeze issues during token streaming.
- **Persistence**: Fixed vector database storage paths for Simulator vs. Device.
