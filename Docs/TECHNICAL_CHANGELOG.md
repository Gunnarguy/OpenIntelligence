> **Documentation status:** Historical reference. This document may describe earlier implementation plans or deprecated architecture. Do not use as the source of truth for OpenIntelligence v4.1.

# OpenIntelligence v4.0 & v4.1 Technical Changelog (Apple Intelligence & Reliability Release)

Changes covered: commit `1702aef7dae510bafe7e28ffa7a53683aff61bc1` through `fc076b637d1766ebefeb819dd997ef5133d955a0`.

This document summarizes the technical implementation changes behind the version 4.0 & 4.1 release cycle currently live on the App Store. This combined release modernizes OpenIntelligence into an Apple Intelligence-native evidence runtime, pairing the initial v4.0 architecture with the v4.1 reliability and telemetry enhancements.

---

## 0. WWDC26 Implementation Map

The technical direction of this release cycle is to move OpenIntelligence from an app-contained RAG engine to an **Apple Intelligence-native evidence runtime**. The table below documents what the iOS SDK unlocked and how it is implemented across the codebase.

| WWDC26 / Platform Area | What Changed / Platform Primitives | Implementation Details |
| --- | --- | --- |
| **Foundation Models Runtime** | `LanguageModelSession`, tools, structured generation, transcripts, provider-aligned model routing, and prompt/runtime specialization. | Split Apple Foundation Models code into `FoundationModelSessionFactory`, `FoundationModelToolRegistry`, `FoundationModelPromptCompiler`, `FoundationModelStructuredGenerator`, `FoundationModelErrorMapper`, `FoundationModelTranscriptStore`, and `FoundationModelTokenBudget`. |
| **Dynamic Profiles** | Runtime profile changes for model behavior, tools, and instructions. | Added `FoundationModelDynamicProfileRegistry` with profiles for direct chat, grounded RAG, extractive RAG, tool-calling RAG, source-only verification, summarization, query planning, and visual evidence QA. |
| **Private Cloud Compute Route** | Secure PCC enclaves for larger/complex workloads while preserving Apple's cryptographic privacy model. | Added `FoundationModelRoute`, `FoundationModelRoutePolicy`, explicit `PrivateCloudComputeLanguageModel()` route checks, `ContextOptions(reasoningLevel:)`, active-route notifications, model status UI, and `PCCRouteEvaluator`. |
| **Core AI & Local Embeddings** | Custom on-device execution for local models (rerankers, classifiers, and embeddings). | Staged experimental `CoreAIModelRegistry`, `CoreAIExecutionBackend`, and `CoreAIEmbeddingBackend` scaffolding. Added `CoreAISentenceEmbeddingProvider` as compiled-out scaffolding (`#if false`) for future OS local APIs, while the production build continues to use the active `CoreMLSentenceEmbeddingProvider`. |
| **Evaluations** | Repeatable AI quality checks beyond standard unit testing. | Added `RAGEvalCase`, `RAGEvalDataset`, `RAGEvalRunner`, `RAGEvalMetrics`, `RAGEvalReportWriter`, `AppleEvaluationsBridge`, and `Docs/EVALS.md`. |
| **App Intents & Entities** | Siri, Shortcuts, and Apple Intelligence integration. | Added `OIDocumentEntity`, `OILibraryEntity`, `OIEntityQueries`, and expanded document/library intents for ask, summarize, compare, search, list, add, and status workflows. |
| **Visual Intelligence** | Camera/image input as an action surface and evidence source. | Added visual/image intents that run Vision OCR and pass extracted text as `.imageOCR` external evidence; added `VisualEvidenceSource`, `VisualEvidenceCard`, and evidence metadata. |
| **Core Spotlight** | Granular system search indexing of application documents. | Expanded `SpotlightIndexService` to index containers, documents, chunks/sections, and parse Spotlight identifiers. |
| **Liquid Glass & UI Telemetry** | iOS 26 glass effect styling, streaming thinking, and layout transition smoothness. | Added `DSGlass`, `glassEffectHelper`, and refreshed core surfaces. Integrated `ThinkingStreamView` in the `UnifiedMetricsBar` for live LLM reasoning tracking. Optimized overlay animations via GPU-driven opacity and scale view modifiers. |

---

## 1. Foundation Models Modularization & Routing

The Apple Foundation Models implementation was decomposed into focused services under `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/`:

*   **`FoundationModelSessionFactory`**: constructs `LanguageModelSession` instances for on-device and PCC routes, including tools, instructions, transcript reuse, and prewarming.
*   **`FoundationModelToolRegistry`**: registers native RAG tools such as corpus retrieval, document inspection, cross-document comparison, and library overview conforming to Apple's model tools schema.
*   **`FoundationModelPromptCompiler`**: compiles context-aware instructions and prompts while reducing token overhead.
*   **`FoundationModelStructuredGenerator`**: handles structured/guided JSON generation for grounded RAG answers.
*   **`FoundationModelErrorMapper`**: maps generation errors (safety guardrail violations, Unsupported locales, context limits) into localized diagnostics.
*   **`FoundationModelTranscriptStore`**: trims transcript history to preserve the available context budget.
*   **`FoundationModelTokenBudget`**: centralizes token estimation and character-to-token mappings.
*   **`FoundationModelRoute` and `FoundationModelRoutePolicy`**: represent and select on-device, automatic, and Private Cloud Compute routes.
*   **`FoundationModelDynamicProfileRegistry`**: supports runtime profile swaps such as direct chat and grounded RAG modes.
*   **MainActor Safety**: Enforced strict `@MainActor` isolation for system LLM availability checks and routing.

Dynamic routing selects On-Device execution for standard queries (4K token context boundary) and Private Cloud Compute for Deep Think queries or larger context spans (up to 32K tokens). A pulsing `ModelStatusIndicator` with an "Under the Hood" details card displays resolved route, active model, and token budget statistics in real-time.

---

## 2. Core AI Experimental Staging & Active Core ML Embeddings

*   **Production Core ML Provider (`CoreMLSentenceEmbeddingProvider`)**: The live, production-ready local vector processing pipeline remains fully powered by the highly optimized Core ML engine (`CoreMLSentenceEmbeddingProvider`).
*   **Disabled Core AI Scaffold (`CoreAISentenceEmbeddingProvider`)**: Staged a dedicated local sentence embedding provider leveraging Apple's new Core AI framework. However, this provider is currently compiled-out (`#if false`) and disabled, pending iOS 27 system API maturity.
*   **`CoreAIModelRegistry` / Backends**: Added experimental registries and execution/embedding backend scaffolding (`CoreAIExecutionBackend`, `CoreAIEmbeddingBackend`) to prepare for running custom models directly on Apple Silicon once the system APIs mature.

---

## 3. RAG Runtime & Retrieval Updates

The query path was reorganized around a dedicated runtime coordinator:

*   **`QueryRuntimeCoordinator.swift`**: Extracts query mode resolution, execution policy mapping, PCC eligibility, adaptive optimization levels, and response metadata creation out of the larger `RAGService` flow.
*   **RAPTOR-lite Summary Routing**: Adds summary filtering for overview-style queries in vector and cached retrieval paths.
*   **Query Pipeline Helpers**: Adjusted `QueryEnhancementService.swift`, `IterativeRetrievalService.swift`, `ContextPackingService.swift`, and `ConfidenceCalibrationService.swift` around the new query/runtime behavior.

---

## 4. Empty Response, Retry, and Partial-Draft Preservation

The generation path was updated to handle failure modes more conservatively:

*   **Empty LLM Responses**: Empty responses route to reliability fallback handling instead of immediately surfacing model-unavailable behavior.
*   **Partial Answer Preservation**: Streaming capture preserves a meaningful partial answer if the model fails after text has already been emitted. The partial-output preservation threshold was lowered so shorter useful drafts can survive.
*   **Retry Mechanisms**: Rate-limited and concurrent request failures get a short primary-model retry before fallback behavior.
*   **Robust Repair**: Stricter grounded repair, evidence-pack, and abstention handling were added for missing-citation, context-overflow, and malformed-response paths.
*   **Thinking Event Timing**: Thinking-event emission was moved after session reset so UI feedback is not lost during route/session changes.

---

## 5. UI Telemetry & Render Optimizations

The UI system was updated to maximize transparency while avoiding layout stuttering on Apple device hardware:

*   **`ThinkingStreamView`**: Added a dedicated subview in `UnifiedMetricsBar` to display real-time animation state during active LLM thinking/reasoning cycles.
*   **GPU-Accelerated Popups**: Refactored `IngestionQueueOverlay` transitions to utilize static layout hierarchy with reactive `.opacity`, `.scaleEffect`, and `.offset` view modifiers animated via spring transitions (`.spring(response: 0.35, dampingFraction: 0.82)`). Bypasses dynamic layout hierarchy calculations, eliminating visual lag during transition.
*   **Grounded Answer UI**: Implemented `GroundedAnswerView`, `VisualEvidenceCard`, `SourceFidelityStatus`, and updated message list views to handle structured answer metadata (evidence IDs, citations, missing support, and abstention behavior).
*   **Theme Updates (Liquid Glass Theme)**:
    *   *DSTypography*: Replaced default default fonts with tight, modern headline sizes and monospaced code blocks.
    *   *DSSpacing & DSCorners*: Standardized smaller gaps (e.g., 14pt margin) and tighter corner radii (e.g., 12pt card, 16pt message bubble) for a sleek, premium, and condensed look.
    *   *`glassCardEffectHelper`*: View modifier that leverages iOS 26+ `.glassEffect` system styling natively, adding an interactive, responsive frosted-glass layer over cards.

---

## 6. Suggested Questions & Grammar Pipelines

The query planning and question suggestions pipeline was refined to guarantee clean, high-quality follow-up questions:

*   **Two-Pass Diversity Selection**: Refactored `SuggestedQuestionsService.selectDiverseChunks` to perform a first pass isolating unique section titles. Falls back to a relaxed round-robin backfill in the second pass to guarantee a full set of candidate chunks (up to target count 12).
*   **NLTagger POS Verification**: Implemented Part-of-Speech tagging analysis in `isValidConceptualTopic` using `NLTagger`. Rejects phrases containing adverbs, layout noise, or ending in invalid parts of speech (verbs, pronouns, conjunctions, prepositions), ensuring high grammatical quality of suggestions.

---

## 7. GPU Batch Vector Math & Adaptive Preprocessing

Retrieval and document processing pipelines were optimized for performance on Apple Silicon hardware:

*   **Metal-Accelerated Cosine Similarity**: Implemented custom SIMD4 and threadgroup-level Metal compute shaders in `GPUComputeService` for cosine similarity and vector normalization, yielding 4x speedups over CPU-based RAG scoring.
*   **`PageComplexityAnalyzer`**: Evaluates digital PDF structure. Pages with valid native text layers skip expensive Vision OCR pipelines entirely. Estimated OCR skip rates average 20% in standard workflows.
*   **Adaptive Preprocessing**: Dynamically scales page rendering resolutions between 360 DPI and 432 DPI based on font risk metrics to optimize document parsing memory footprints.
*   **Haptic Telemetry Pulses**: Integrated `HardwareTelemetry` calls across embedding generation (GPU cosine similarity), image processing, and LLM inference to provide real-time hardware status indicators.

---

## 8. Storage Safety & Deletion Cascades

Storage, indexing, and sync layers were hardened to eliminate file corruption and orphaned database artifacts:

*   **Atomic Vector DB Saves**: Updated `BNNSVectorDatabase.saveToDisk()` to build a contiguous memory buffer and perform atomic file replacement on disk instead of appending via mutable `FileHandle` writes. This resolves cache incoherency, memory-map alignment crashes, and file size conflicts.
*   **Cascading Ingestion Deletions**: Hardened `discardPausedIngestionQueue()` in `RAGService.swift` to invoke `removeDocument()`, triggering a cascading purge across:
    *   FTS5 SQLite search indexes.
    *   Spotlight / Entity Search indexes.
    *   Vector database chunks and norms.
    *   Local document storage directories.
*   **Tombstone Merging**: Updated `WorkspaceSyncService.swift` to synchronize `deleted_documents.json` tombstones bi-directionally, preventing files from being resurrected during sync.
*   **Automated Garbage Collection**: Added cleanup routines inside `WorkspaceSyncService` to prune unreferenced physical files in `ImportedDocuments` and orphaned vector store chunks whose parent documents are no longer active in metadata.

---

## 9. System Integrations: Spotlight, App Intents, Siri, and Visual Intelligence

Siri, Spotlight, and system-wide indexing are integrated as first-class retrieval and discoverability layers:

*   **Spotlight Indexing**: `SpotlightIndexService.swift` now indexes containers, documents, chunks, sections, figures, and citation anchors into Core Spotlight, supporting Spotlight identifier parsing.
*   **App Intents & App Entities**: Added `OIDocumentEntity.swift`, `OILibraryEntity.swift`, and `OIEntityQueries.swift` to resolve persisted App Entities for Siri and Shortcuts query actions.
*   **Visual Intelligence OCR**: Camera/image intents extract OCR text from images and pass them into RAG as `.imageOCR` external evidence, enabling visual evidence citations.

---

## 10. App-Wide UI, Ingestion, Onboarding, Library, and Queue Work

The UI and ingestion pipeline received updates across chat, library, onboarding, and sync modules:

*   **Ingestion Metrics**: Ingestion items now carry richer metrics (words processed, vectors generated, and chunking strategy).
*   **Onboarding Progress**: `OnboardingChecklistView.swift` now mirrors ingestion state locally, uses a timer publisher for smooth elapsed-time display, and shows specific pipeline logs.
*   **Sample Document**: The bundled sample document was renamed from "OpenIntelligence Pricing" to "OpenIntelligence Product Guide" to better align with the onboarding context.
*   **Live Activities**: `IngestionLiveActivityAttributes.swift` and `IngestionLiveActivityService.swift` were updated to support richer Live Activity progress state during long-running background imports.

---

## 11. Continuous Evaluations and Diagnostics

A first-class RAG evaluation framework was added to measure retrieval and answer quality:

*   **`RAGEvalCase.swift`**: JSONL-backed evaluation case and result models.
*   **`RAGEvalDataset.swift`**: Dataset loading, filtering, and bundle loading.
*   **`RAGEvalRunner.swift`**: Async execution of evaluation cases against the RAG engine.
*   **`RAGEvalMetrics`**: Retrieval recall@5 (Target: $\ge 0.85$), citation precision (Target: $\ge 0.90$), exact-value accuracy (Target: $\ge 0.95$), unsupported-claim rate (Target: $\le 0.05$), correct abstention rate (Target: $\ge 0.85$), and context overflow rate (Target: $\le 0.02$).
*   **`RAGEvalReportWriter`**: Markdown and JSON report generation.
*   **`AppleEvaluationsBridge`**: Export shape for Apple/fm CLI-style evaluation tooling.
*   **Diagnostics Hub**: Exposes developer entry points under `DeveloperDiagnosticsHubView` and `PCCRouteEvaluator` to validate model routing and evaluation runs.

---

## 12. SDK Compatibility & Build Configuration

*   **SDK Compatibility**: Added `EngineSDKCompatibility.swift` to provide compile-time fallback definitions when newer WWDC26 SDK symbols are unavailable.
*   **Build Metadata**: Updated `Package.swift` and `OpenIntelligence.xcodeproj/project.pbxproj` build settings for iOS 26+ frameworks.

---

## 13. Liquid Glass, Assets, and Release Metadata

*   **Asset Catalogs**: Expanded the app icon asset catalog to support iPhones, iPads, and Mac targets, along with `Contents.json` updates.
*   **Release Automation**: Updated `fastlane/Fastfile` and `release_notes.txt` connect limits for automated deployment.
*   **Documentation updates**: Public architecture, retrieval pipeline, limit, and Private Cloud Compute documentation files were updated to match the combined release architecture.
