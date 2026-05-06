# Engine Inventory

## Current Status

OpenIntelligence Engine is best understood today as a substantial Apple-native document-intelligence prototype and codebase head start.

The repo contains a real engine inside a real app codebase. Some parts are strongly reusable. Some are still tightly tied to the app. This file separates those categories.

## Current SDK Boundary Hotspots

These are the file-level hotspots still worth watching during sellable-engine cleanup:

- `OpenIntelligence/Services/LLM/LLMService.swift`: carries Apple ChatGPT extension and AppIntents code. The framework compile path now excludes the real AppIntents implementation and falls back to the compatibility stub.
- `OpenIntelligence/Services/Infrastructure/Integration/ContainerService.swift`: still persists active-library state and Spotlight-related toggles through raw `UserDefaults` keys.
- `OpenIntelligence/Services/Infrastructure/Configuration/SettingsStore.swift`: still mixes engine runtime configuration with SwiftUI-facing app settings and app-storage semantics.
- `OpenIntelligence/Services/Infrastructure/Monitoring/HardwareTelemetryState.swift`: motherboard HUD diagnostics remain in an engine-included folder because core services still report telemetry through it.
- `OpenIntelligence/Services/Storage/DocumentationCacheService.swift`: cached web-doc support is app-facing and is now excluded from the engine target.
- `OpenIntelligence/Services/LLM/ModelResolutionService.swift`: model-status UI service is dead code and is now excluded from the engine target.
- `OpenIntelligence/Services/Infrastructure/Background/IngestionLiveActivityAttributes.swift`: this app live-activity type was only a stray recovered project reference and has been removed from project metadata.

## Core Engine

### Engine entry-point file

- File path: `OpenIntelligence/SDK/OpenIntelligenceEngine.swift`
- Purpose: gives another Apple app a small set of engine entry points for checking availability, creating the engine, importing files, and asking questions.
- Why it matters: gives a buyer a practical starting integration boundary instead of forcing them into the entire app surface.
- Reusable outside the app: yes, with caveats.
- App coupling risk: wraps `ContainerService`, `RAGService`, and app runtime paths.
- Buyer caveat: this is an evaluation-stage entry-point file, not a finished SDK contract.

### Document ingestion

- File path: `OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift`
- Purpose: reads files, chooses extraction path, preserves pages, and prepares text for chunking.
- Why it matters: ingestion quality is the first major bottleneck in document QA.
- Reusable outside the app: yes.
- App coupling risk: logging, progress reporting, and downstream service assumptions are app-shaped.
- Buyer caveat: broad coverage exists, but ingestion still needs corpus-specific evaluation.

### OCR and text extraction

- File paths: `OpenIntelligence/Services/Document/Config/OCRConfiguration.swift`, `OpenIntelligence/Services/Document/Processing/StructuredDocumentParser.swift`, `OpenIntelligence/Services/Document/Processing/LayoutAwareExtractor.swift`
- Purpose: handles OCR fallback, structured parsing, layout-aware extraction, and page cleanup.
- Why it matters: bad OCR creates downstream retrieval and answer errors.
- Reusable outside the app: yes.
- App coupling risk: tied to current runtime assumptions and device capability logic.
- Buyer caveat: strong base, but not a guarantee of perfect table or procedure capture.

### Chunking

- File path: `OpenIntelligence/Services/Document/Chunking/SemanticChunker.swift`
- Purpose: creates structure-aware chunks with metadata such as section paths, keywords, entities, and parent context.
- Why it matters: chunk quality drives retrieval quality.
- Reusable outside the app: yes.
- App coupling risk: depends on current embedding and metadata conventions.
- Buyer caveat: technical and procedural documents can still break chunk fidelity.

### Embeddings

- File paths: `OpenIntelligence/Services/Embedding/EmbeddingService.swift`, `OpenIntelligence/Services/Embedding/Providers/CoreMLSentenceEmbeddingProvider.swift`, `OpenIntelligence/Services/Embedding/Providers/AppleFMEmbeddingProvider.swift`
- Purpose: generates local semantic vectors for retrieval.
- Why it matters: vector search depends on this layer.
- Reusable outside the app: yes.
- App coupling risk: provider selection and runtime assumptions are still app-config driven.
- Buyer caveat: current real path is Core ML and Natural Language. `AppleFMEmbeddingProvider.swift` exists only as an unavailable scaffold and is not an active embedding provider.

### Storage

- File paths: `OpenIntelligence/Services/Storage/SQLiteFullTextService.swift`, `OpenIntelligence/Core/Models/KnowledgeContainer.swift`
- Purpose: stores container metadata, full-document text, chunk text, and page text locally.
- Why it matters: this is the durable local knowledge layer.
- Reusable outside the app: yes.
- App coupling risk: current persistence is routed through app support paths and singleton-style services.
- Buyer caveat: container isolation is good prototype engineering, but not yet a hardened SDK boundary.

### Full-text search

- File path: `OpenIntelligence/Services/Storage/SQLiteFullTextService.swift`
- Purpose: provides FTS5 and BM25-backed literal search over documents, chunks, and pages.
- Why it matters: exact-value and keyword lookup depend on it.
- Reusable outside the app: yes.
- App coupling risk: singleton and app-path assumptions.
- Buyer caveat: this is one of the stronger reusable pieces in the repo.

### Vector search

- File paths: `OpenIntelligence/Services/VectorStore/VectorStoreRouter.swift`, `OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift`
- Purpose: manages per-container vector indexes and similarity search.
- Why it matters: semantic retrieval depends on it.
- Reusable outside the app: yes.
- App coupling risk: current router listens for app memory warnings and uses app support paths.
- Buyer caveat: strong implementation, but still not packaged as a clean framework module.

### Retrieval and reranking

- File paths: `OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift`, `OpenIntelligence/Services/RAG/Retrieval/ParentDocumentService.swift`, `OpenIntelligence/Services/RAG/Retrieval/GraphIndexService.swift`
- Purpose: combines vector and BM25 retrieval, expands context, and follows references.
- Why it matters: this is where document QA becomes more than vector search.
- Reusable outside the app: yes.
- App coupling risk: current orchestration is centered on `RAGService`.
- Buyer caveat: graph-style retrieval exists, but this is not full GraphRAG.

### Context packing

- File path: `OpenIntelligence/Services/RAG/Retrieval/ContextPackingService.swift`
- Purpose: fits the best evidence into the current Apple token budget.
- Why it matters: the public Apple path is context-limited, so packing policy matters.
- Reusable outside the app: yes.
- App coupling risk: tuned specifically for current model/runtime assumptions.
- Buyer caveat: today it is calibrated around the public 4096-token Foundation Models path.

### Generation adapters

- File paths: `OpenIntelligence/Services/LLM/LLMService.swift`, `OpenIntelligence/Services/LLM/ModelResolutionService.swift`
- Purpose: abstracts answer generation and model/runtime selection.
- Why it matters: connects retrieval to user-visible answers.
- Reusable outside the app: partially.
- App coupling risk: current tool set and orchestration are still strongly app-shaped.
- Buyer caveat: the Apple-native generation path is real, but not fully separated from the app runtime.

### Verification

- File paths: `OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift`, `OpenIntelligence/Services/RAG/Safety/SourceOnlyAnswerService.swift`, `OpenIntelligence/Services/RAG/Safety/ConfidenceCalibrationService.swift`
- Purpose: checks answer support, numeric consistency, grounding, and domain isolation.
- Why it matters: this is a major part of the engine's value beyond generic chat.
- Reusable outside the app: yes.
- App coupling risk: uses current score scales, thresholds, and answer shapes.
- Buyer caveat: citations and gates improve behavior, but do not guarantee correctness.

### Benchmark harness

- File paths: `OpenIntelligence/App/DebugRAGValidationHarness.swift`, `scripts/run_rag_benchmarks.py`, `scripts/rag_benchmark_studio.py`, `Benchmarks/README.md`
- Purpose: runs the engine against manifests, collects traces, and generates reports.
- Why it matters: makes the prototype inspectable and regression-testable.
- Reusable outside the app: partially.
- App coupling risk: the harness is embedded in the Debug app runtime and uses app launch arguments and entitlement seeding.
- Buyer caveat: useful for evaluation, but still early and not a formal benchmark program.

## App-Specific

| Area                            | Primary paths                                                                 | Why it is app-specific                           |
| ------------------------------- | ----------------------------------------------------------------------------- | ------------------------------------------------ |
| SwiftUI screens                 | `OpenIntelligence/App/`, `OpenIntelligence/Features/`, `OpenIntelligence/UI/` | end-user product surface, not core engine IP     |
| Onboarding                      | `OpenIntelligence/Features/Onboarding/`                                       | demo and first-run experience                    |
| Paywalls and StoreKit           | `OpenIntelligence/Services/Billing/`, `OpenIntelligence/Features/Billing/`    | consumer monetization, not engine transfer value |
| Settings UI                     | `OpenIntelligence/Features/Settings/`                                         | product controls and app presentation            |
| App Store metadata and Fastlane | `fastlane/`, screenshots, metadata, release scripts                           | release operations, not engine capability        |
| Visual chrome                   | design system and presentation components                                     | product styling, not engine core                 |

## Shared and Support

| Area                             | Primary paths                                                                                                               | Why it matters                                     | Caveat                                               |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------- | ---------------------------------------------------- |
| Engine settings and model config | `OpenIntelligence/Services/Infrastructure/Configuration/SettingsStore.swift`, `OpenIntelligence/Core/Models/LLMModel.swift` | controls execution context and feature toggles     | mixes engine and app concerns                        |
| Device capability logic          | `OpenIntelligence/Services/Infrastructure/Monitoring/DeviceCapabilityService.swift`                                         | decides what the engine can do on current hardware | still app-runtime oriented                           |
| Logging                          | shared `Log` calls and logging config                                                                                       | useful for debugging and audits                    | custom app logging system                            |
| Model and container types        | `OpenIntelligence/Core/Models/KnowledgeContainer.swift`, `DocumentChunk.swift`, `RAGStructuredResponse.swift`               | core data model layer                              | some types carry app-era assumptions                 |
| Runtime paths                    | `OpenIntelligence/Core/Models/KnowledgeContainer.swift`, `OpenIntelligence/Core/Support/OpenIntelligenceRuntimePaths.swift` | lets the facade override base storage              | current persistence layout still grew out of the app |
| Benchmark entitlement helpers    | `DebugRAGValidationHarness.swift`, `WorkspaceTier.swift`, `EntitlementStore` compatibility shims                            | useful for debug evaluation                        | not production entitlement logic for buyers          |

## Bottom Line

The reusable value is real and concentrated in ingestion, storage, retrieval, verification, and benchmark tooling.

The main transfer risk is not that the engine is fake. It is that the current engine still lives inside an app codebase and needs further separation before it looks like a clean commercial SDK.
