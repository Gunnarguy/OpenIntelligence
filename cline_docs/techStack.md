# Tech Stack – OpenIntelligence (2025 Modernization)

Last updated: 2025-10-28

## Platforms and Targets
- iOS 26+, iPadOS 26+, macOS 15+ (SDK setting per project.pbxproj)
- Swift 5, Swift Concurrency enabled; default actor isolation = MainActor
- Xcode File System–Synchronized project group for source auto-discovery

## Core Architecture
- SwiftUI app with service-oriented modules:
  - Services: LLM backends, Embeddings, RAG pipeline, Telemetry, Document processing
  - Models: data structures for documents, chunks, queries, responses, configuration
  - Views: Settings, Chat, Diagnostics, Telemetry Dashboard
- RAG pipeline
  - Chunking, embeddings, hybrid search (vector + BM25), re-ranking (RRF/MMR), context assembly
  - Background actor RAGEngine for CPU-heavy stages (MMR/context) to reduce main-thread work

## AI and ML Backends
- Apple Intelligence / Foundation Models (iOS 26+)
  - SystemLanguageModel / LanguageModelSession (FoundationModels) for on-device execution with PCC fallback
  - Tool calling for agentic RAG (search/list/summary tools)
  - Execution context and PCC preferences surfaced in Settings
- ChatGPT Extension (iOS 18.1+)
  - App Intents–based system integration (entitlement dependent), not primary
- OpenAI Direct
  - HTTPS client to OpenAI chat completions; configurable model (GPT-4o, o1, GPT-5 families)
- MLX Local (macOS)
  - Local server bridge to mlx-lm using OpenAI-style endpoints (no data leaves the Mac)
- Core ML LLM (planned)
  - CoreMLLLMService for on-device custom models (.mlpackage) with tokenizer adapters

## Embeddings
- Abstraction
  - EmbeddingProvider protocol for pluggable providers
  - Default: NLEmbeddingProvider (NaturalLanguage), 512-dim, word-avg parity
- Providers
  - NLEmbeddingProvider (on-device, fast)
  - CoreMLSentenceEmbeddingProvider (scaffold): for multilingual sentence encoders (e5/MiniLM/GTE) converted to Core ML
- Vector DB
  - Cosine similarity search; performance optimizations (precomputed norms, caching)
  - Plan: index namespacing or re-embed workflow for dimension mismatches

## Frameworks and Libraries
- SwiftUI (UI)
- FoundationModels (SystemLanguageModel / LanguageModelSession) [iOS 26+]
- AppIntents (intents, ChatGPT extension)
- NaturalLanguage (NLEmbedding, tagging, tokenization)
- Vision, VisionKit (OCR and scanning; planned upgrades)
- CoreML (custom models for embeddings and LLMs; scaffolds in place)
- PDFKit (document ingestion)
- AVFoundation/Speech (planned: TTS/ASR)
- Combine/OSSignpost (diagnostics/perf where needed)

## Privacy and Execution
- On-device first policies; PCC opt-in/opt-out and execution context control
- Backend telemetry planned:
  - Execution location (📱 On-Device / ☁️ PCC / 🖥️ MLX / 🔑 OpenAI)
  - TTFT, tokens/sec, toolCallsMade
- Clear UI labeling of data flow and privacy guarantees (PCC zero retention)

## Key Design Decisions
- Pluggable backends via LLMService; auto routing + fallback order in Settings
- Embeddings provider abstraction to support better multilingual encoders
- macOS MLX local backend to keep sensitive data on-machine for larger open models
- Background actor for heavy RAG steps to maintain UI responsiveness
- Progressive enhancement: gracefully degrade to On-Device Analysis on older hardware

## Files of Interest
- Services/LLMService.swift: AppleFoundationLLMService, OpenAILLMService, CoreMLLLMService scaffold
- Services/Embeddings/:
  - EmbeddingProvider.swift, NLEmbeddingProvider.swift, CoreMLSentenceEmbeddingProvider.swift
- Services/MLXLocalLLMService.swift: macOS local server bridge
- Services/RAGEngine.swift: CPU-heavy RAG stages
- Views/Settings/SettingsView.swift: model selection, PCC, fallbacks, pipeline visualization
- cline_docs/: projectRoadmap.md, currentTask.md, techStack.md (this), codebaseSummary.md (planned)
