# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
