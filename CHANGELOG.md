# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-01-09 (Build 3)

### Added

- **Query Intent Classification**: Classifies queries as keyword/conceptual/balanced for optimal retrieval strategy.
- **Per-Query Weight Tuning**: Dynamic vector/keyword weights based on query intent (keyword→more BM25, conceptual→more vector).
- **Content-Type Auto-Tuning**: Auto-select RetrievalConfig based on document types in container.
- **Corpus-Aware Query Expansion**: Expands queries using actual document vocabulary with garbage filtering.
- **Lost-in-Middle Mitigation**: Reorders context chunks so best matches appear at start AND end (Liu et al. 2023).
- **Cross-Encoder Re-ranking**: BERT-based CoreML reranker with heuristic fallback.
- **Memory Caching**: Per-container vocabulary cache prevents repeated `allChunks()` calls.
- **Content-Adaptive Chunking**: Different presets for code (250w/40w), technical (280w/50w), narrative (400w/70w).

### Changed

- **Context Budget**: Increased from 5000 to 7500 chars; safety margin reduced 900→500 tokens.
- **Chunking Strategy**: Optimized to 280-400 words with ~17% overlap (was 220w at 50% overlap).
- **System Prompts**: Enhanced for comprehensive, detailed responses (150-300 word minimum guidance).
- **Default Chunk Size**: 350 words target (was 400), 60 word overlap (was 75).

### Fixed

- **Memory Leak**: Fixed vocabulary reload on every query via `corpusVocabularyCache`.
- **PCC Token Limit**: Corrected to 4096 tokens (was incorrectly documented as 65K in UI).
- **Offline Capability**: Fixed inaccurate descriptions about always-available offline mode.
- **UI Defaults**: All settings screens now show correct optimized chunking values.

## [0.9.0] - 2025-11-19 (Internal Beta)

### Added

- **Hybrid Search Engine**: Full implementation of BM25 + Vector Search + RRF Fusion.
- **Agentic Tooling**: 12 `@Tool` functions for Apple Intelligence integration.
- **Telemetry Dashboard**: Real-time visualization of RAG pipeline performance (TTFT, Tokens/sec).
- **Apple Foundation Models**: iOS 26 Foundation Models with PCC fallback.
- **OnDeviceAnalysisService**: Extractive QA fallback (always available offline).
- **Privacy Controls**: Private Cloud Compute (PCC) toggles and execution location badges.
- **NLContextualEmbedding Provider**: BERT-like contextual embeddings for 15-25% accuracy boost.
- **AdaptiveEmbeddingOptimizer**: Auto-recommends optimal embedding based on corpus complexity.
- **SemanticChunker**: Paragraph-aware chunking with topic boundary detection.
- **VectorStoreRouter**: Per-container database routing with LRU cache.

### Changed

- **Architecture**: Refactored to a Protocol-First design with `RAGService` orchestration.
- **Concurrency**: Moved heavy compute to `RAGEngine` actor for UI responsiveness.
- **Documentation**: Complete rewrite of `README.md` and architecture docs.
- **Cloud LLM Removal**: Removed OpenAI/GPT direct API integration (Apple-only now).
- **Local Model Removal**: Removed GGUF/CoreML/MLX downloadable models for simpler maintenance.
