# OpenIntelligence v4.0 Update Notes

OpenIntelligence version 4.0 is a milestone release that modernizes the application into an **Apple Intelligence-native evidence system**, incorporating the latest OS-level APIs and capabilities introduced at WWDC26. 

This release focuses on modularity, transparent trust visualization, system-level deep integration, and rigorous quality gates. Below is an exhaustive breakdown of every change made in this branch.

---

## 1. Modularization of Apple Foundation Models Architecture

We decomposed the massive, monolithic `AppleFoundationLLMService` class into discrete, single-responsibility helper modules under `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/`. This ensures stability, ease of testing, and modular scaling:

*   **`FoundationModelSessionFactory`**: Standardizes `LanguageModelSession` creation. Handles the mapping of system instructions, session-specific tool registers, and pending transcript restorations.
*   **`FoundationModelToolRegistry`**: Manages the available RAG tool interface. It registers and wraps core system tools (e.g., `retrieve_corpus_evidence`, `inspect_document`, `compare_topic_across_documents`, and `get_library_overview`) conforming to Apple's native model tools schema.
*   **`FoundationModelPromptCompiler`**: Compiles context-aware prompts by combining user queries, retrieved RAG context, and system instructions, optimizing tokens for on-device context boundaries.
*   **`FoundationModelStructuredGenerator`**: Implements guided/structured JSON schema generation using the framework's native structured generation tools for factual, parseable lookup outputs.
*   **`FoundationModelErrorMapper`**: Maps OS-level generation errors (e.g., safety guardrail violations, unsupported locales, context limits) into localized, user-actionable diagnostics.
*   **`FoundationModelTranscriptStore`**: Manages conversation history, providing intelligent context trimming (moving window) to preserve token budget.
*   **`FoundationModelTokenBudget`**: Computes token usage dynamically using official character-to-token mappings (and a robust 1.4 characters-per-token fallback estimate).
*   **`FoundationModelRoute` & `FoundationModelRoutePolicy`**: Encapsulates dynamic execution route selection (On-Device vs. Private Cloud Compute). Standard queries execute locally, while complex reasoning queries (Deep Think/Maximum modes) or massive context spans (up to 32K tokens) route automatically to secure PCC enclaves.

---

## 2. Core AI and Custom Local Model Integration

To prepare for future specialized models (compact local rerankers, semantic classifiers, and custom embedding models), we added local execution backends under `OpenIntelligence/Services/AIPlatform/CoreAI/`:

*   **`CoreAIModelRegistry`**: Registers and tracks local models loaded directly onto Apple Silicon.
*   **`CoreAIExecutionBackend`**: Connects to OS-level, silicon-accelerated inference pathways for running specialized model weights.
*   **`CoreAIEmbeddingBackend`**: Integrates native tokenization and tensor calculations for local text embeddings.

---

## 3. Formal RAG Pipeline Evaluations Framework

We replaced the older ad-hoc benchmark script with a comprehensive, first-class evaluations suite under `OpenIntelligence/Services/Evaluation/` to validate model quality against the strict targets defined in the technical spec:

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
*   **`AppleEvaluationsBridge`**: Interfaces our local evaluation runner with Apple's command-line evaluation tooling (`fm CLI`).
*   **Documentation (`Docs/EVALS.md` & `Docs/AI_AGENT_MAP.md`)**: Comprehensive documentation detailing quality gate target metrics, dataset schemas, and the full 29-step RAG query execution graph.

---

## 4. Deep System-Level Integrations

Siri, Spotlight, and system-wide indexing are promoted to first-class retrieval and discoverability layers:

*   **Granular Spotlight Indexing (`SpotlightIndexService.swift`)**: Updated the indexing layer to index not just general documents, but specific chunks, sections, figures, and citation anchors. This turns Core Spotlight into an active semantic retrieval plane.
*   **Entity-Native App Intents (`RAGAppIntents.swift` & `VisualIntelligenceIntents.swift`)**:
    *   Introduced native schemas: `OIDocumentEntity`, `OILibraryEntity`, `OIChunkEntity`, and `OICitationEntity`.
    *   Exposed entity-native Siri shortcuts including: *"Ask OpenIntelligence about current document"*, *"Summarize document in OpenIntelligence"*, and *"Find documents about topic"*.
    *   Replaced ephemeral, unbacked RAGService initializations inside intents with persistent storage-backed entity resolution.

---

## 5. Modernized UI Trust Layer & Liquid Glass Design System

To make the engine's intelligence and safety guarantees legible to the user, we implemented a state-of-the-art UI trust layer:

*   **`GroundedAnswerView`**: Renders verified, source-locked responses clearly with integrated citation mapping.
*   **`VisualEvidenceCard`**: Renders visual evidence context (Vision OCR text, page regions, barcodes, and QR codes) inside message bubbles, promoting camera/photo captures to first-class citations.
*   **`SourceFidelityStatus`**: Visually represents verification checks, showing if an answer is *Source-locked*, *Partially supported*, or *Lacking sufficient evidence*.
*   **`UnifiedMetricsBar`**: Unified context bar that displays character/token counts, processing duration, and resolved execution paths in real-time.
*   **`IngestionQueueOverlay`**: Replaced the legacy `ProcessingOverlay` with a lighter, more integrated stats drawer showing document queue counts, vectors generated, and words embedded.
*   **`Theme.swift` Updates (Liquid Glass Theme)**:
    *   *DSTypography*: Replaced default default fonts with tight, modern headline sizes and monospaced code blocks.
    *   *DSSpacing & DSCorners*: Standardized smaller gaps (e.g. 14pt margin) and tighter corner radii (e.g. 12pt card, 16pt message bubble) for a sleek, premium, and condensed look.
    *   *`glassCardEffectHelper`*: View modifier that leverages iOS 26+ `.glassEffect` system styling natively, adding an interactive, responsive frosted-glass layer over cards.

---

## 6. Real-Time Routing Badge & Popover

Ensured that routing is updated dynamically and the user understands exactly how the engine works:

*   **`ModelResolutionService` & `ModelStatusIndicator`**:
    *   Refactored the header pill to display the active execution route (e.g., On-Device vs. Private Cloud Compute) dynamically.
    *   Introduced a pulsing scaling animation for the status dot during active query execution.
    *   Transitioned the pill background dynamically based on routing (e.g. green for local, blue for PCC) with smooth state animations.
    *   Replaced the TTFT (time-to-first-token) latency heuristic in `ChatScreen` with the actual route resolved from `FoundationModelRoutePolicy`.
    *   Enriched the indicator detail popover to explain the hybrid engine mechanics "under the hood" (4K token context boundary, PCC cloud enclaves, and cryptographic privacy guarantees).
