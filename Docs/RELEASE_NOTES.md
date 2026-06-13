> **Documentation status:** Historical reference. This document may describe earlier implementation plans or deprecated architecture. Do not use as the source of truth for OpenIntelligence v4.1.

# OpenIntelligence v4.0 & v4.1 Release Notes (WWDC26 Apple Intelligence Update)

OpenIntelligence version 4.0 & v4.1 is a milestone release that modernizes the application into an **Apple Intelligence-native evidence system**, incorporating the latest OS-level APIs and capabilities introduced at WWDC26. 

This release notes document details the complete picture of this major release cycle currently live on the App Store—covering modular foundation models, Private Cloud Compute, local sentence embeddings acceleration, live reasoning telemetry, robust data persistence, and sandboxed system integrations.

---

## 1. Modularization of Apple Foundation Models Architecture

The massive, monolithic `AppleFoundationLLMService` class was decomposed into discrete, single-responsibility helper modules under `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/` to ensure stability, ease of testing, and modular scaling:

*   **`FoundationModelSessionFactory`**: Standardizes `LanguageModelSession` creation. Handles the mapping of system instructions, session-specific tool registers, and pending transcript restorations.
*   **`FoundationModelToolRegistry`**: Manages the available RAG tool interface. It registers and wraps core system tools (e.g., `retrieve_corpus_evidence`, `inspect_document`, `compare_topic_across_documents`, and `get_library_overview`) conforming to Apple's native model tools schema.
*   **`FoundationModelPromptCompiler`**: Compiles context-aware prompts by combining user queries, retrieved RAG context, and system instructions, optimizing tokens for on-device context boundaries.
*   **`FoundationModelStructuredGenerator`**: Implements guided/structured JSON schema generation using the framework's native structured generation tools for factual, parseable lookup outputs.
*   **`FoundationModelErrorMapper`**: Maps OS-level generation errors (e.g., safety guardrail violations, unsupported locales, context limits) into localized, user-actionable diagnostics.
*   **`FoundationModelTranscriptStore`**: Manages conversation history, providing intelligent context trimming (moving window) to preserve token budget.
*   **`FoundationModelTokenBudget`**: Computes token usage dynamically using official character-to-token mappings (and a robust 1.4 characters-per-token fallback estimate).
*   **`FoundationModelRoute` & `FoundationModelRoutePolicy`**: Encapsulates dynamic execution route selection (On-Device vs. Private Cloud Compute). Standard queries execute locally, while complex reasoning queries (Deep Think/Maximum modes) or massive context spans (up to 32K tokens) route automatically to secure PCC enclaves.
*   **`FoundationModelDynamicProfileRegistry`**: Standardizes runtime profile swaps for model behavior, tools, and instructions. Supports profiles for direct chat, grounded RAG, extractive RAG, tool-calling RAG, source-only verification, summarization, query planning, and visual evidence QA.

---

## 2. Core AI Experimental Framework & Production Core ML Embeddings

To prepare for future local execution models on Apple Silicon and support local-first AI, the Core AI framework layer was introduced. However, since system-level local execution APIs are still maturing, the production-ready embedding layer remains backed by the proven Core ML pipeline:

*   **Production Local Embeddings (`CoreMLSentenceEmbeddingProvider`)**: The live, production-ready local vector processing pipeline remains fully powered by the highly optimized Core ML engine (`CoreMLSentenceEmbeddingProvider`).
*   **Experimental Core AI Scaffold (`CoreAISentenceEmbeddingProvider`)**: Staged preliminary scaffolding for running tokenization and dense vector calculations directly on Apple's Core AI framework. This provider is currently disabled (`#if false`) and staged for future OS-level API capabilities, ensuring the production build remains stable on the proven Core ML pipeline.
*   **`CoreAIModelRegistry` / Backends**: Staged experimental registries and execution/embedding backend scaffolding (`CoreAIExecutionBackend`, `CoreAIEmbeddingBackend` under `OpenIntelligence/Services/AIPlatform/CoreAI/`) to prepare for running custom models directly on Apple Silicon once the system APIs mature.

---

## 3. Real-Time Telemetry & Liquid Glass UI Design System

To make the underlying reasoning loops of on-device LLMs transparent and ensure a premium user experience, a state-of-the-art UI trust layer was implemented:

*   **`ThinkingStreamView`**: Displays live, animated indicators during LLM thinking and reasoning phases.
*   **`UnifiedMetricsBar` Integration**: Integrates the thinking stream view directly into the metrics bar at the bottom of the chat interface, providing immediate telemetry feedback on active tokens, duration, and routing.
*   **`GroundedAnswerView`**: Renders verified, source-locked responses clearly with integrated citation mapping.
*   **`VisualEvidenceCard`**: Renders visual evidence context (Vision OCR text, page regions, barcodes, and QR codes) inside message bubbles, promoting camera/photo captures to first-class citations.
*   **`SourceFidelityStatus`**: Visually represents verification checks, showing if an answer is *Source-locked*, *Partially supported*, or *Lacking sufficient evidence*.
*   **`IngestionQueueOverlay` Transition**: Replaced CPU-bound layout dynamic hierarchy rendering with GPU-accelerated opacity, scale, and offset transitions to eliminate layout stutter.
*   **Theme Updates (Liquid Glass Theme)**:
    *   *DSTypography*: Replaced default system fonts with tight, modern headline sizes and monospaced code blocks.
    *   *DSSpacing & DSCorners*: Standardized smaller gaps (e.g., 14pt margin) and tighter corner radii (e.g., 12pt card, 16pt message bubble) for a sleek, premium look.
    *   *`glassCardEffectHelper`*: View modifier that leverages iOS 26+ `.glassEffect` system styling natively, adding an interactive, responsive frosted-glass layer over cards.

---

## 4. Real-Time Routing Badge & Popover

Routing is updated dynamically, ensuring the user understands exactly how the hybrid engine resolves:

*   **`ModelResolutionService` & `ModelStatusIndicator`**:
    *   Refactored the header pill to display the active execution route (e.g., On-Device vs. Private Cloud Compute) dynamically.
    *   Introduced a pulsing scaling animation for the status dot during active query execution.
    *   Transitioned the pill background dynamically based on routing (e.g., green for local, blue for PCC) with smooth state animations.
    *   Replaced the TTFT (time-to-first-token) latency heuristic in `ChatScreen` with the actual route resolved from `FoundationModelRoutePolicy`.
    *   Enriched the indicator detail popover to explain the hybrid engine mechanics "under the hood" (4K token context boundary, PCC cloud enclaves, and cryptographic privacy guarantees).

---

## 5. Suggested Questions & Grammar Safeguards

The query planning and question suggestions pipeline was refined to guarantee clean, high-quality follow-up questions:

*   **Two-Pass Diversity Selector**: Prevents duplicated categories or narrow section topics by running a section-isolation pass, falling back round-robin to ensure the target 12 diverse chunks are surfaced.
*   **POS Grammar Filters**: Integrates `NLTagger` Part-of-Speech analysis to filter out adverb suffixes (e.g., `simply`, `merely`), layout noise, and verbs from generated conceptual topics, ensuring suggested follow-up questions are grammatically clean and topic-grounded.

---

## 6. GPU-Accelerated Vector Search & Ingestion Optimization

The ingestion and retrieval phases were optimized to leverage Apple Silicon hardware:

*   **Metal Cosine Similarity Pipeline**: Replaced CPU-bound vector similarity calculations in `GPUComputeService` with threadgroup-level Metal shaders and SIMD4 batch pipelines, achieving a 4x reduction in query-time retrieval latency.
*   **Adaptive Preprocessing & Page Pre-Scan**: Integrated `PageComplexityAnalyzer` to pre-scan document structures. Digital PDF pages with validated text skip Vision OCR execution automatically (averaging a 20% skip rate), and the system dynamically scales rendering resolution (360-432 DPI) based on page density risk.
*   **Haptic & Ingestion Telemetry**: Coupled execution stages to native telemetry haptic indicators (`HardwareTelemetry` haptic pulses), providing real-time feedback during OCR scanning, embedding math, and LLM inference.

---

## 7. Atomic Vector Store Writes & Cascading Deletions

Storage, indexing, and sync layers were hardened to eliminate file corruption and orphaned database artifacts:

*   **Atomic Database Writes**: Replaced inline `FileHandle` appending in `BNNSVectorDatabase` with thread-safe atomic data replacement on disk, resolving size mismatches and mmap crashes.
*   **Cascading Deletions**: Deleting or discarding interrupted/paused ingestion items now triggers a clean cascade that removes document metadata, purges FTS5 indexes, wipes partial vectors from disk, and removes physical files from storage.
*   **Orphaned Chunk & File Cleanup**: Scans and garbage-collects physical files and vector databases to purge orphaned chunks whose parent documents are no longer active.
*   **Sync Tombstones**: Leverages `deleted_documents.json` tombstones to prevent bi-directional sync from resurrecting deleted files.

---

## 8. Empty Response, Retry, and Partial-Draft Preservation

Stricter generation safeguards ensure answer delivery remains stable under network or API strain:

*   **Abstentions & Retries**: Rate-limited or concurrent Foundation Model request failures get a short retry path. Empty model responses route to a reliability fallback rather than failing silently.
*   **Partial Answers**: Stream captures preserve valid partial answers if the model fails late in execution. Stricter repair pathways handle context overflow and missing citations.

---

## 9. Siri, Shortcuts, Spotlight, and Visual Intelligence

Siri, Spotlight, and system-wide indexing are promoted to first-class retrieval and discoverability layers:

*   **Granular Spotlight Indexing (`SpotlightIndexService.swift`)**: Updated the indexing layer to index not just general documents, but specific chunks, sections, figures, and citation anchors. This turns Core Spotlight into an active semantic retrieval plane.
*   **Entity-Native App Intents (`RAGAppIntents.swift` & `VisualIntelligenceIntents.swift`)**:
    *   Introduced native schemas: `OIDocumentEntity`, `OILibraryEntity`, `OIChunkEntity`, and `OICitationEntity`.
    *   Exposed entity-native Siri shortcuts including: *"Ask OpenIntelligence about current document"*, *"Summarize document in OpenIntelligence"*, and *"Find documents about topic"*.
    *   Replaced ephemeral, unbacked RAGService initializations inside intents with persistent storage-backed entity resolution.
*   **Visual Intelligence Integration**: Extracts OCR text from camera or image inputs and passes it as external evidence, elevating visual documents into first-class citations in the answer pipeline.

---

## 10. App-Wide UI, Onboarding, and Ingestion Queue Improvements

*   **Onboarding Progress**: Updated the onboardingchecklist and imports dashboard to display live stages, extraction progress, vector generation counts, and a timer publisher for smooth elapsed-time tracking.
*   **Live Activities**: Integrated Live Activity support to show background import status directly on the lock screen and Dynamic Island.
*   **Sample Document**: Renamed the sample document to "OpenIntelligence Product Guide" to align with onboarding instructions.

---

## 11. RAG Pipeline Evaluations Framework

The older ad-hoc benchmark script was replaced with a comprehensive, first-class evaluations suite under `OpenIntelligence/Services/Evaluation/` to validate model quality against the strict targets defined in the technical spec:

*   **`RAGEvalCase` & `RAGEvalDataset`**: Models represent test datasets containing queries, expected outputs, ground-truth chunks, and expected citations in a robust `.jsonl` dataset format.
*   **`RAGEvalRunner`**: Runs full evaluation sets against the RAG retrieval and generation engine asynchronously.
*   **`RAGEvalMetrics`**: Analyzes results to compute performance metrics including:
    *   *Retrieval Recall@5* (Target: $\ge 0.85$)
    *   *Citation Precision* (Target: $\ge 0.90$)
    *   *Exact-value Accuracy* (Target: $\ge 0.95$)
    *   *Unsupported-claim (Hallucination) Rate* (Target: $\le 0.05$)
    *   *Correct Abstention Rate* (Target: $\ge 0.85$)
    *   *Context Overflow Rate* (Target: $\le 0.02$)
*   **`RAGEvalReportWriter`**: Formats evaluation runs into readable Markdown reports and structured JSON files for CI/CD tracking.
*   **`AppleEvaluationsBridge`**: Interfaces the local evaluation runner with Apple's command-line evaluation tooling (`fm CLI`).
*   **Documentation (`Docs/EVALS.md` & `Docs/AI_AGENT_MAP.md`)**: Comprehensive documentation detailing quality gate target metrics, dataset schemas, and the full 29-step RAG query execution graph.

---

## 12. App Icon Assets & Build Compatibility

*   **Universal AppIcon**: Integrated a unified universal AppIcon configuration across iOS and macOS targets, resolving catalog build warnings.
*   **SDK Compatibility**: Added compatibility wrappers for iOS 26+ SDK symbols, keeping compile-time behaviors protected while supporting modern APIs.
