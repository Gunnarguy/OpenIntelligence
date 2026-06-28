> **Documentation status:** Verified for OpenIntelligence v4.3 on June 20, 2026.

# Changelog

This is the public version history for OpenIntelligence. It focuses on user-visible product changes and intentionally omits private engine tuning, thresholds, and internal implementation details.

## 4.4 - June 2026

- **[Evidence Threads]** Implemented Phase 1A local thread persistence. Created `EvidenceThread` and `EvidenceThreadMessage` Codable models to store research chat sessions locally on disk.
- **[Evidence Threads]** Placed thread storage directories under `LocalCache/EvidenceThreads/<containerId>/` to isolate them and prevent accidental sweeps from the iCloud Drive ubiquity sync daemon.
- **[Diagnostics]** Implemented Phase 1B Diagnostics-Only Exposure. Created `EvidenceThreadDebugService` and `EvidenceThreadDebugView` inside `Features/Debug/` to test persistence, thread mocking, and thread deletion without altering production views.
- **[Orchestration]** Completed Phase 1C & 1D Integration. Integrated Evidence Thread persistence into the production `RAGService` and `ChatScreen` systems.
- **[Orchestration]** Replaced the skeletal `EvidenceThreadMessage` with the fully featured `ChatMessage` array, ensuring immutability while capturing complete response details and citations on disk.
- **[Orchestration]** Created `ThreadSidebarView` with standard Design System tokens to serve as an elegant slide-out navigation panel for managing and selecting threads. Wired it dynamically to the leading toolbar navigation button.
- **[Orchestration]** Updated `RAGService` to load the most recent thread automatically on container preload, save new queries dynamically to the active thread, and handle thread deletions cleanly without crossing sync boundaries.
- **[Entitlements]** Aligned and verified quota logic in `QuotaPolicy.swift` restricting the Pro tier to a hard limit of 1,000 document uploads (unlimited uploads are restricted to Lifetime).
- **[Orchestration]** Integrated native `FoundationModels.PrivateCloudComputeLanguageModel` execution when running on iOS 27 / macOS 27+, allowing elevated quality modes (Deep Think/Maximum) to run natively on secure enclaves, while maintaining simulated local fallback for older OS versions.
- **[Orchestration]** Reverted `EvidenceThread` and `EvidenceThreadStore` scope modifiers from `public` to `internal` to prevent compilation errors regarding exposed internal model properties.
- **[Orchestration]** Wrapped native Private Cloud Compute execution in compiler-version conditionals (`#if compiler(>=6.1)`) to support compilation on older SDK environments like the GitHub Actions CI runner.

## 4.3.1 - June 2026


- **[Orchestration]** Fixed MainActor deadlock in WorkspaceSyncService by offloading NSFileCoordinator read locks to detached background tasks, eliminating UI hangs during iCloud synchronizations.
- **[Orchestration]** Offloaded synchronous file operations in TranscriptPersistenceService, ConversationMemoryService, and ContainerService to detached tasks to prevent MainActor deadlocks and guarantee UI fluidity.
- **[Orchestration]** Resolved a persistent ingestion queue loop where deleted ubiquitous iCloud files could be resurrected as paused ingestion tasks across devices by utilizing checkResourceIsReachable().
- **[Orchestration]** Lifted the Apple Silicon hardware telemetry HUD to avoid occlusion by the bottom conversational metrics bar on macOS, while explicitly preserving original layout coordinates on iOS.
- **[Orchestration]** Restored native macOS Image Playground (.imagePlaygroundSupport) button bindings.
- **[Orchestration]** Enhanced Image Playground generation by utilizing `.extracted(from:)` to pass the entire LLM response, enabling full semantic interpretation instead of relying solely on isolated extracted nouns.
- **[Orchestration]** Capped Image Playground extraction context at 1000 characters to optimize semantic extraction without overloading the Apple Intelligence framework with unnecessarily large text blocks.
- **[Orchestration]** Implemented native macOS sharing interfaces across the application, adding `ShareLink` support for Pipeline Trace Logs and enabling `NSSharingServicePicker` for "Share with Friends" functionality in Settings.
- **[Orchestration]** Fixed a race condition during background iCloud synchronization where a document could be duplicated in the local extraction queue if it was both restored as an interrupted session and automatically detected as missing vectors by the self-healing rebuild daemon.
- **[Orchestration]** Resolved a Swift 6 compiler type-inference error related to `Identifiable` conformance when iterating over active background ingestion queues.
- **[Orchestration]** Disabled extractive override to force LLM generation for RAG queries, preventing raw truncated text bypasses.

## 4.3 - June 2026

- **[Orchestration]** Powered by the AFM 3 Architecture: Updated model configuration parsing to dynamically route and visibly highlight across the entire third-generation model suite (AFM 3 Core, AFM 3 Core Advanced, and AFM 3 Cloud Pro).
- **[Agentic]** Siri Screen Awareness: Integrated AppIntents background context frameworks to allow Siri to natively ingest on-screen files and URLs directly into RAG libraries without touching the app.
- **[Generative]** ADM 3 Cloud Integration: Plumbed Apple's ADM 3 architecture via Image Playground API into the core generation pipeline for instant visual concept rendering.
- **[Retrieval]** Lightning-Fast Answer Generation: Rebuilt the RAG deduplication pipeline using O(N) Set-based tracking, resulting in an over 1,000x speedup in evidence aggregation for large libraries.
- **[Orchestration]** Buttery-Smooth Database Dashboard: Implemented a dynamic UUID dictionary cache in `DatabaseDashboardView`, accelerating row rendering performance by ~240x during heavy scrolling.
- **[Orchestration]** Removed legacy `OnDeviceAnalysisService` to simplify LLM routing, fully trusting Apple Intelligence native FoundationModels.
- **[Orchestration]** Integrated the 20B Apple Foundation Model (AFM 3 Core Advanced) into the execution pipeline. Prioritized `.onDeviceAdvanced` routing over Private Cloud Compute to maximize local privacy and eliminate cloud latency for reasoning operations.
- **[Orchestration]** Hardened token budget obedience and evaluation suites to maintain extreme robustness against Apple Intelligence constraints.
- **[Models]** Streamlined configuration parsing by removing legacy `strictMode` boolean from `KnowledgeContainer`, mapping directly to native `minSimilarity` thresholds.
- **[UI]** Pruned visual noise by removing obsolete logic relating to the deprecated "Fibonacci sphere" distribution in `AdaptiveVisualizationsView`.
- **[Tests]** Expanded `OpenIntelligenceEngineTests` suite with hybrid search safety checks and Semantic Chunker hardening against empty strings and malformed data.
- **[Orchestration]** Fixed agentic reasoning orchestration so that Standard mode strictly prohibits auto-escalating to Deep Think loops when utilizing the constrained 3B Core model.
- **[Orchestration]** Fixed UI context capability strings to correctly report: 4K (3B Core), 4K (20B Advanced), 32K (PCC Cloud Pro). Purged hallucinated token contexts to strictly align with Apple June 2026 Foundation Models API specs.
- **[Orchestration]** Unlocked RAM ceilings allowing exponential concurrent pipeline scaling for ultra-advanced Apple Silicon.
- **[Orchestration]** Reclassified `VerificationGateService` Domain Isolation gate to an advisory status to prevent abstention false-positives on cross-domain queries.
- **[Background]** Hardened `BackgroundTaskService` against `BGTaskSchedulerErrorDomain error 3` by eliminating string dynamic identifiers and wildcards from system registration logic.
- **[FoundationModels]** Harmonized all availability macro targeting across the entire codebase to `iOS 26.0, macOS 26.0`, correctly aligning with Apple's 2025 unified naming architecture.
- **[Shortcuts]** Fixed string interpolation in AppIntents parameter summaries.
- **[Shortcuts]** Dropped 3 experimental iOS 27.0 AppShortcuts to strictly enforce Apple's 10-shortcut system limit.
- **[Shortcuts]** Resolved ITMS-90626 by removing the trademark "Siri" from Screen Awareness `IntentDescription` metadata.

## 4.2 - June 2026

- **Modernized UI for macOS/iOS**: Completely rebuilt the live telemetry HUD utilizing iOS 26/macOS 26/WWDC26+ APIs. Integrated `.ultraThinMaterial` for premium glassmorphism, hardware `.sensoryFeedback` for interactive haptics, and smooth `.symbolEffect` animations.
- **Dynamic Verification Gates**: The visual HUD for RAG telemetry now adapts its pipeline dynamically based on your active `RAGQualityMode` (Standard = 4 gates, Deep Think = 8 gates, or Maximum = 12 gates).
- **Fixed Chat History Persistence**: Resolved an issue that sometimes skipped loading your previous chat history during a cold boot after force-closing the app.
- **Granular Hardware Telemetry**: The Execution Badge now dynamically fetches and displays exact onboard RAM allocations alongside TOPS processing power.
- **Accuracy in Retrieval Metrics**: Corrected UI labels to differentiate between semantic Database Matching (Vector Similarity) and active LLM reasoning thresholds (Total Confidence).
- **Agentic Tool Visibility**: The telemetry HUD now surfaces implicit, hidden engine calls (such as Vector Search Engine lookups) during standard modes that do not trigger recursive tool event streams.
- **Clean Sub-second Telemetry**: Fixed a visual bug presenting Time-To-First-Token in raw oversized milliseconds (e.g., 12000ms), standardizing values to an elegant `< 1.2s` formatted duration.
- **Native Resizable Telemetry Drawer**: Completely rebuilt the expanded metrics panel to behave like a fluid, native iOS bottom sheet. Users can now physically pull the handle down to manually resize the metrics view seamlessly during live telemetry inspection or recording.


## 4.0 & 4.1 - June 2026 (Apple Intelligence Release)

OpenIntelligence version 4.0 & 4.1 is a milestone upgrade that integrates Apple Intelligence system-level APIs with optimized on-device and secure cloud routing. This unified release incorporates both the initial v4.0 architecture and the v4.1 reliability and telemetry enhancements currently live on the App Store:

- **Apple Foundation Models Integration**: Migrated language model sessions to native iOS 26+ FoundationModels APIs. Deconstructed the monolithic LLM services into dedicated helper modules (`FoundationModelSessionFactory`, `FoundationModelToolRegistry`, `FoundationModelPromptCompiler`, `FoundationModelStructuredGenerator`, `FoundationModelTranscriptStore`, and `FoundationModelTokenBudget`).
- **Dynamic Routing Policy**: Standard queries route to local on-device models (4K token context boundary), while complex or long-context queries automatically scale to secure Private Cloud Compute (32K tokens).
- **Core AI Local Scaffolding**: Staged `CoreAISentenceEmbeddingProvider` as experimental local scaffolding under Apple's Core AI framework (.aimodel loading with 512-token BERT tokenization), while the production build continues to run on the highly optimized Core ML vector engine.
- **Live Telemetry & UI Trust Layer**: Added the `ThinkingStreamView` directly to the `UnifiedMetricsBar` for live LLM reasoning telemetry and refreshed the interface with modern Liquid Glass UI components.
- **Metal GPU-Accelerated Vector Search**: Integrated SIMD4 and threadgroup-level Metal pipelines in `GPUComputeService` for 4x faster local batch vector calculations.
- **Adaptive Ingestion Pipeline**: Integrated `PageComplexityAnalyzer` to pre-scan document structures. Digital PDF pages skip Vision OCR execution automatically (averaging a 20% skip rate), and the system dynamically scales rendering resolution (360-432 DPI) based on page density risk.
- **Database Safety & Physical File GC**: Switched `BNNSVectorDatabase` disk saves to atomic writes, preventing local file corruption and size mismatch issues. Added local physical file garbage collection in `WorkspaceSyncService` to purge orphaned documents.
- **Cascading Ingestion Deletions**: Hardened the ingestion queue to trigger a clean cascading deletion (database entries, physical files, FTS5 tables, and Spotlight indexes) when uploads are canceled or discarded.
- **Siri, Shortcuts & Spotlight**: Document and library items are now persisted App Entities (`OIDocumentEntity`, `OILibraryEntity`), enabling Siri/Shortcuts actions. Spotlight indexes down to specific chunks and sections.
- **Suggested Questions Polish**: Refined suggestions with a two-pass diversity chunk selector, `NLTagger` POS grammar filters, and offline curated suggestions that bypass LLM runtime overhead on app start.
- **Continuous Evaluations Suite**: Built `RAGEvalRunner` to run evaluation datasets, tracking Recall@5, Citation Precision, and Hallucination metrics against spec targets.
- **RAG Generation Safeguards**: Enforced main-actor safety and hardened reasoning loops with retry policies to prevent rate-limited empty responses from overwriting valid answer drafts.
- **Render Optimizations**: Replaced CPU layout calculations in `IngestionQueueOverlay` with spring-animated opacity, scale, and offset transformations to avoid dynamic UI layout stutter, adding duration timers for ingestion tasks.

## 3.7 - May 2026

- Tightened the Documents surface again with cleaner library pills, a less crowded header, smaller sync controls, and clearer library-management affordances
- Strengthened shared-workspace and background-ingestion plumbing so queue cleanup, reconciliation, and long-running library work behave more predictably
- Improved camera capture, OCR-heavy import reliability, and mixed digital/scanned page handling so harder documents are less fragile on the way in
- Preserved clean digital text more conservatively while keeping the heavier recovery path for noisy scans, image-heavy pages, and visually complex inputs
- Strengthened retrieval, context packing, parent-document use, and answer shaping so responses stay closer to the source passages they are built from
- Improved suggested questions and follow-ups so they stay more tied to the active library, more grounded, and less generic across repeated refreshes
- Smoothed out chat attachment and capture flows so new material can move into the question-answer loop more directly
- Expanded answer review with clearer source inspection, timing, retrieval-quality, and evidence details when users want to understand how a response was formed
- Improved rendering for technical and structured answers, including clearer code block presentation and better response-detail surfaces
- Tightened diagnostics, monitoring, and device-aware performance behavior so larger libraries and longer-running sessions are more stable to work with
- Added native App Store rating and review prompting triggers after successful query tasks
- Resolved Mac Catalyst layout truncations, including the Sync Mode picker, action chips, and scrollable library selector pills
- Enabled full iCloud ubiquity container access and network permissions for Mac Catalyst by packaging universal sandbox entitlements
- Resolved Xcode build catalog warnings with a unified universal AppIcon configuration across iOS and macOS targets
- Redesigned the Silicon hardware telemetry HUD to dynamically rotate motherboard borders (SoC and Taptic outlines) to match device layout rotation, added iPad layout coordinates, and cleanly hid visual outlines on Mac targets
- Hardened suggested questions and 3D visualization keywords to aggressively filter out OCR junk, syntax noise, and generic templates

## 3.6 - May 2026

- Added per-library storage choice so every library can be Local Only or iCloud Drive independently
- Kept the app local-first by default, with only iCloud-marked libraries entering the shared iCloud workspace
- Added cross-device reuse for iCloud libraries so imported files and processed library state can show up on the user's other Apple devices
- Stopped same-name iCloud libraries from merging implicitly by switching shared matching to stable library identity instead of display name
- Made explicit per-library moves to iCloud Drive behave like direct opt-in instead of routing through a second generic sync-choice step
- Added a global Documents-level refresh and sync-review flow that can surface libraries found only in iCloud, only on this device, or removed remotely
- Added clearer follow-up handling for shared-library deletions so the app can prompt to delete the library here too or keep a local copy
- Added queue lease handling so another device can resume long-running work for an iCloud library if the first device drops out
- Cleaned up the Documents and Settings sync surfaces with clearer status, shorter copy, one main place to manage storage, global refresh/review controls, and less truncation on tighter layouts
- Smoothed out the Documents tab follow-up layout so the new sync UI is easier to read and tap without crowding the rest of the page
- Made in-app import cancellation work more reliably from the upload queue overlay
- Prevented deleted or reconfigured libraries from reviving old queued documents after sync or reload, and tightened cleanup when removing a library
- Split document normalization into conservative versus aggressive paths so plain digital text is preserved more faithfully while OCR and scanned inputs still get heavier cleanup
- Extended the conservative text path across text, markdown, code/config files, CSV, audio/video transcripts, and Office/iWork-style digital documents
- Improved OCR and image-analysis stability during document import

## 3.5 - May 2026

- Rolled up the corrective work since 3.2.5 into a more stable 3.5 release focused on trust, first-touch clarity, and harder real-world documents
- Strengthened exact answers across Standard, Deep Think, and Maximum for direct source-backed lookups over tables, specifications, measurements, counts, dates, prices, and similar exact values
- Tightened starter questions and follow-up suggestions so they stay grounded in actual passage support, fail closed more often on weak evidence, and avoid canned filler around procedures, requirements, and duration claims
- Reworked onboarding, empty states, and the bundled sample workspace so first-run guidance explains the real product story more clearly: model limits, best-supported file types, and when processing stays on-device versus uses Apple Private Cloud Compute
- Unified PDF and image visual ingestion behind one adaptive path, preserved searchable figures and structured tables more reliably, and reduced fake tables, broken headings, mixed table/prose contamination, and reference-section noise on scientific PDFs
- Improved long-running user-initiated imports with better queue recovery, background cleanup, and Live Activity lifecycle handling
- Cleaned up library and settings surfaces so per-library isolation and live runtime behavior are described more accurately

## 3.3 - April 2026

- Large user-initiated imports now preserve queue state, resume after interruption more cleanly, and surface clearer progress on supported devices
- Removed the old ingestion fidelity setting and replaced it with one adaptive visual-ingestion path that raises OCR/detail recovery only when a page actually needs it
- Preserved embedded PDF figures as searchable chunks with captions, OCR labels, page context, and visual descriptions instead of dropping them during structured chunking
- Grounded embedded-image analysis with real page text observations so figure captions and nearby instructions attach more reliably
- Preserved parsed table titles, headers, and rows in SQLite during ingestion so uploaded reference documents remain more inspectable and queryable instead of collapsing to flattened text only
- Added a structured table fallback path for retrieval when exact values sit under table headings, schemas, or row data that ordinary chunk search can miss
- Kept the exact-answer cleanup from the 3.2.5 corrective line in place so direct fact questions stay brief, grounded, and less citation-heavy across Standard, Deep Think, and Maximum
- Tightened starter-question quality so suggested questions stay closer to what a single grounded passage can actually answer cleanly

## 3.2.5 - April 2026

- Improved exact-value answers for table rows, specifications, measurements, counts, limits, dates, and prices when the source clearly contains the answer
- Added a precision lookup path before Deep Think and Maximum begin longer reasoning, so simple source-backed questions can still resolve quickly
- Shared stronger table/spec retrieval rescue across Standard, Deep Think, and Maximum
- Tightened generated starter questions so they are grounded in actual uploaded passages instead of loose document labels or generic topics
- Cleaned up exact measurement answers, including nearby equivalent units when present in the source

## 3.1 - April 2026

- Preserved grounded partial answers in Deep Think and Maximum when a late-stage generation interruption happens, instead of dropping generic stop text onto useful output
- Improved ingestion for noisy scans, multi-column PDFs, and corrupted tables so rows and columns survive extraction more reliably
- Strengthened table-aware retrieval and structured evidence packing for specification sheets, statistical tables, and dense scientific documents
- Tightened claim verification so unsupported statements are pruned or downgraded before final answers are shown
- Improved long-form reasoning with better evidence clustering, corrective retrieval, and more conservative abstention when support is weak

## 3.0 - April 2026

- Reworked noisy PDF and OCR table ingestion so structured rows survive extraction instead of collapsing into column-order garbage
- Added a corrective retrieval pass that runs before answer generation when first-pass evidence is weak, thin, or too generic
- Strengthened extractive handling for tables, specifications, and statistical outputs with better table-priority evidence selection and page recovery
- Tightened grounded abstention behavior when retrieved evidence is structurally weak or topically mismatched
- Improved diagnostics so retrieval hardening and corrective recovery are visible during pipeline review

## 2.5 - April 2026

- Starter questions now come from representative samples of the active library instead of generic prompts
- Refreshing starter questions surfaces more varied grounded prompts rather than repeating the same ideas
- Follow-up suggestions behave more reliably after answers and library switches, including deeper follow-up, clarification, and comparison flows
- Grounded answer routing is stronger before answers are shown, with a stricter path for fact-heavy questions and a more constrained synthesis path when needed
- Evidence verification is tighter before final answer presentation so weak support is handled more conservatively
- Weakly supported answers are surfaced more clearly through better answer review and source inspection
- Source cards, filenames, and scrollable excerpts are easier to inspect in response details
- Tables, lists, quotes, headings, separators, and other structured technical output render much better
- Malformed links in generated answers are repaired more aggressively
- PDF imports filter garbage text and noisy extraction more cleanly on messier files
- Maximum mode now has a real daily free-use quota path with clearer paid behavior
- Historical paid users are protected more generously in entitlement handling
- Settings, billing, and plan messaging were cleaned up to better match the actual entitlement model

## 2.0.x - March 2026

- Faster everyday document Q&A workflows
- Better handling for edge-case documents and long-running sessions
- Sharper source review, app responsiveness, and product polish

## 2.0.0 - February 2026

- Public App Store release of OpenIntelligence
- Native iPhone experience for asking questions about personal documents
- Multi-format import, local organization, and cited answers
- Subscription and purchase support for product access tiers

## Notes

Detailed internal algorithm changes and research-oriented engine updates are tracked privately rather than in the public changelog.
- [Orchestration] Added FoundationModelPreference override to allow manual selection of 3B Core, 20B Advanced, or Private Cloud Compute tiers in ChatScreen.
- [Orchestration] Fixed InferenceConfig argument order in ChatScreen to resolve compilation failure.
- [Orchestration] Dynamically hide 20B Advanced preference from UI on older OS versions.
- [Orchestration] Resolved duplicated text rendering in manual model selector pill.
- [Orchestration] Fixed bug causing Gate I to falsely fail during Verification Pipeline execution.
- [UI] Cleaned up manual model selector pill layout.
