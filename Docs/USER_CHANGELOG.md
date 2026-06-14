> **Documentation status:** Historical reference. This document may describe earlier implementation plans or deprecated architecture. Do not use as the source of truth for OpenIntelligence v4.1.

# OpenIntelligence v4.0 & v4.1 User-Facing Changelog (Apple Intelligence & Reliability Release)

OpenIntelligence version 4.0 & v4.1 is a major Apple Intelligence modernization and refinement pass currently live on the App Store. The release touches every major component of the user experience—from the local-first execution model to transparent citation details, visual evidence cards, and Siri/Shortcuts system integration.

This document consolidates this major release cycle into a single, cohesive user-facing log—highlighting the Apple Intelligence native foundation alongside a GPU-accelerated ingestion pipeline, Metal vector search performance, live reasoning telemetry, and database protection.

The practical user story is simple: **OpenIntelligence now does a better job showing what evidence it used, where it ran, and how much source support it found before you trust an answer.**

---

## Why WWDC26 Matters Here

WWDC26 shifted the platform architecture by pushing core AI capabilities into system-level frameworks. For OpenIntelligence, this unlocked several important system resources:

*   **Apple Foundation Models**: Native `LanguageModelSession` instances, structured generation, token budgeting, and route-policy layers.
*   **Apple Private Cloud Compute (PCC)**: A secure cloud route for complex or context-heavy work, ensuring cryptographic privacy.
*   **App Intents & App Entities**: Integration with Siri, Shortcuts, and system services for reading, listing, and indexing documents.
*   **Visual Intelligence**: A platform route to import OCR and camera captures as active RAG evidence.
*   **Core Spotlight**: Deep system-level indexing of document chunks and sections.
*   **Core AI**: Execution pathways for local custom models.
*   **Liquid Glass**: A modern visual design system featuring responsive glass effects.

---

## What Users Will Notice First

*   **Transparent Verification UI**: Responses are explicitly labeled so you can see if they are **Source-Locked** (fully supported by your documents), **Partially Supported**, or **Lacking Sufficient Evidence**.
*   **Model Routing Visibility**: The status pill in the header shows you exactly where your query ran: **On-Device** (standard questions up to 4K tokens) or **Private Cloud Compute** (complex or long-context questions up to 32K tokens).
*   **Live Reasoning Telemetry**: You can watch the model's active thinking loop in real-time inside the bottom metrics bar as it organizes thoughts, resolves routing, and writes answers.
*   **Lag-Free Visual Transitions**: The processing dashboard and overlays transition smoothly using GPU-accelerated effects, eliminating visual stutter during document imports.
*   **4x Faster Local Vector Search**: Local vector similarity calculations run on Apple Silicon hardware accelerators using custom Metal pipelines, reducing RAG search latency by 4x.
*   **Clean Discarding & Deletion**: Canceling or deleting an in-progress import now triggers a cascading purge that completely removes file fragments, database records, and Spotlight search indexes, ensuring no orphaned data is left behind.
*   **Grammatically Correct Suggested Questions**: Suggested follow-up questions are grammatically clean and diverse across different sections of your library.

---

## Key Improvements

### 1. Smarter On-Device vs. Private Cloud Compute Routing
*   **Dynamic Policy**: Local execution is preferred for standard queries to protect battery life and latency. Heavy reasoning queries or large files automatically route to secure Private Cloud Compute.
*   **Under the Hood Details**: Tap the header status pill to open a popover detailing the active model name, token budget usage, and explanations of Apple's PCC privacy guarantees.
*   **Direct Route Metrics**: The status bar displays telemetry from the actual resolved routing engine rather than an estimation based on response latency.

### 2. Grounded Answers and Citation Integrity
*   **GroundedAnswerView**: Presents cited answers clearly, making it easy to map each statement back to its specific source document.
*   **Visual Evidence Cards**: Image imports, camera scans, and PDF figures render inside the chat bubbles as OCR-derived evidence.
*   **Fidelity Status**: Clearly displays the verification level of every response, helping you decide how much to rely on the generated answer.

### 3. Better Recovery When Generation Misbehaves
*   **Empty Response Fallback**: If a model returns an empty response, the RAG service now routes into a reliability fallback instead of treating the entire query as unavailable.
*   **Partial-Draft Preservation**: If streaming produced a useful partial answer before a failure, the app preserves that text instead of replacing it with an empty or generic failure result.
*   **Rate Limit Safeguards**: Rate-limited or concurrent Apple Foundation Model failures get a short retry path before falling through to recovery behavior.
*   **Stricter Grounding Repair**: Stricter repair pathways handle context overflow and missing citations, prompting abstention when grounding support is too weak.

### 4. UI Telemetry & Render Optimizations
*   **Thinking Stream**: The `ThinkingStreamView` shows live feedback during reasoning phases so you are never left wondering if the app is frozen.
*   **GPU-Driven Overlay**: Ingestion overlay animations utilize hardware-accelerated opacity and scale transitions, preventing frames from dropping during heavy background indexing.
*   **Massive Document Stability**: Resolved a critical bug where opening the app after ingesting massive documents (e.g., HOA docs) caused an instant crash or UI freeze. Ingestion logs are now lazily loaded and capped to prevent unbounded memory allocation and excessive view generation on launch.

### 5. Suggested Questions & Grammar Safeguards
*   **Diverse Suggestions**: The query planner isolates unique sections of your documents to guarantee follow-up questions cover a variety of topics.
*   **Grammar Filter**: Uses Apple's native language taggers (`NLTagger`) to analyze parts of speech and filter out OCR layout noise, verbs, or incomplete phrases from suggested prompts.

### 6. GPU & Neural Engine (ANE) Pipeline Optimizations
*   **Adaptive Pre-Scan**: Automatically pre-scans documents before ingestion. Clean digital PDF pages bypass expensive Vision OCR pipelines completely, achieving up to a 20% processing speedup.
*   **GPU Resolution Scaling**: Scales document rendering resolution dynamically based on font size risk, reducing document parsing memory requirements on device silicon.
*   **Hardware Telemetry**: Integrates haptic and visual metrics feedback for Vision OCR, vector embedding generation, and LLM inference.

### 7. Database Safety & Zero-Remnant Discarding
*   **Anti-Corruption Writes**: Vector database disk saves write to a contiguous memory buffer and replace database files atomically, preventing corruption if the app reloads during ingestion.
*   **Zero-Remnant Purge**: Deleting or discarding a document cleanly deletes all corresponding vector data, FTS5 database indices, Spotlight entries, and local files.
*   **Sync Tombstones**: Leverages deletion logs (`deleted_documents.json`) to prevent deleted documents from being revived during cross-device syncing.

### 8. System Integrations: Spotlight, Siri, and Shortcuts
*   **Deep Spotlight Indexing**: System Spotlight search can search and index down to specific document chunks, sections, and figures.
*   **App Intents**: Persisted document and library entities are exposed to Siri and Shortcuts. You can ask Siri to summarize, compare, or search documents directly.
*   **Visual Intelligence OCR**: Captures image inputs and extracts their text as active evidence in the RAG pipeline.

### 9. App-Wide UI, Onboarding, and Workflow Improvements
*   **Onboarding Progress**: Updated the checklist and imports dashboard to display live stages, extraction progress, vector generation counts, and a timer publisher for smooth elapsed-time tracking.
*   **Live Activities**: Integrated Live Activity support to show background import status directly on the lock screen and Dynamic Island.
*   **Sample Document**: Renamed the sample document to "OpenIntelligence Product Guide" to align with onboarding instructions.

### 10. Retrieval, Summaries, and Evaluation Quality Gates
*   **Evaluations Framework**: Built a suite to measure retrieval recall, citation precision, exact-value accuracy, and hallucination rates against strict quality gates before updates are shipped.
*   **RAPTOR-Lite Routing**: Added summary routing to handle high-level document overviews by querying generated document summaries.

### 11. Liquid Glass and Visual Polish
*   **Universal AppIcon**: Added a unified universal AppIcon configuration across iOS and macOS targets, resolving catalog build warnings.
*   **Visual density**: Standardized margins (14pt) and tighter corner radii for message bubbles (16pt) and cards (12pt) to create a denser, more cohesive Liquid Glass UI.
