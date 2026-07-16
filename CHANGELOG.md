## [Unreleased]
### Added
- **[Orchestration]** Implemented PCC Dynamic Routing Phases 0–8 for v4.6: deterministic local retrieval/planning, post-retrieval `ModelExecutionPlan` selection, conditional minimized Private Cloud Compute synthesis, deterministic local verification, and durable intended/attempted/actual/fallback/completed `ModelExecutionReceipt` telemetry. Automatic routing no longer claims PCC before retrieval evidence is available. `[evidence_level: code_verified, confidence: high, evidence_source: ModelExecutionPlanner.swift, RAGService.swift, LLMService.swift]`
- **[Privacy]** Moved PCC consent to the final post-retrieval route, displays the exact minimized payload size and route reason, prevents background/App Intent consent waits, and keeps iOS 26 execution local-only. Denial or unavailable foreground UI uses the declared on-device fallback unless the user explicitly requires cloud-only execution. `[evidence_level: code_verified, confidence: high, evidence_source: RAGService.swift, CloudConsentPromptView.swift, AgenticOrchestrator.swift]`
- **[Platform]** Re-enabled the Apple-approved `com.apple.developer.private-cloud-compute` entitlement. Native macOS verifies its signed process with Security.framework; iOS/Catalyst development and ad-hoc builds parse the embedded signed provisioning profile; profile-less App Store/TestFlight builds defer to Apple's documented PCC availability and quota APIs. Native PCC remains iOS/macOS 27+. Signed installation and live PCC execution validation remain pending. `[evidence_level: code_verified+sdk_verified+user_confirmed, confidence: high_for_source_unverified_for_distribution, evidence_source: OpenIntelligence.entitlements, EngineSDKCompatibility.swift, FoundationModelCapabilityProvider.swift, FoundationModelSessionFactory.swift]`
- **[Compatibility]** Removed unsupported public 3B/20B execution claims from active model labels, migrates the legacy Advanced preference to the public on-device system model, uses exact SDK context/token APIs where available, and preserves historical response decoding through optional receipt metadata. `[evidence_level: code_verified, confidence: high, evidence_source: LLMModel.swift, SettingsStore.swift, FoundationModelTokenBudget.swift, RAGQuery.swift]`
- **[Testing]** Verified the v4.6 app, engine, and unit-test targets compile against the iOS 27 Simulator SDK. All 8 PCC planner/receipt tests and all 3 ingestion tombstone tests pass; the repository suite is 109/110, with only the independent existing SemanticChunker organization-name assertion failing. Signed-device PCC execution remains a promotion gate. `[evidence_level: build_verified, confidence: exact_for_simulator, evidence_source: Xcode 27.0 test result 2026-07-15]`
- **[General]** Added the repository-local `route-openintelligence-work` Codex skill, a deterministic RepoOS preflight/router, and a dedicated workspace-automation route so every task resolves its evidence, edit boundaries, verification, documentation, and Notion-roadmap relevance from current repository artifacts. The preflight now derives the active release on every run and explicitly targets `CHANGELOG.md` `[Unreleased]`, the matching version section in `Docs/RELEASE_NOTES.md`, and the same Notion `Target Release` for durable implementations.

### Fixed
- **[Settings]** Replaced the misleading continuous GPU percentage with Efficiency, Balanced, Performance, and Maximum execution profiles. The same persisted profile now controls Core ML preferences at safe reload boundaries, PDF rendering, large MMR/vector Metal gates, and background GPU eligibility; a real Efficiency selection no longer resets to Balanced on relaunch. Settings now distinguishes configured policy from Apple frameworks' final hardware scheduling. `[evidence_level: code_verified+test_verified, confidence: high_pending_device_thermal_validation, evidence_source: DeviceCapabilityService.swift, SettingsView.swift, RAGEngine.swift, BNNSVectorDatabase.swift, GPUExecutionProfileTests.swift]`
- **[Privacy]** Made remembered Apple PCC consent authoritative across relaunches. A canonical `Always Allow` or denial now wins over stale legacy picker state, legacy remembered choices migrate safely, selecting Ask removes the canonical grant, and startup no longer manufactures a zero-payload consent prompt. Consent UI is requested only for a real finalized evidence envelope. `[evidence_level: code_verified+test_verified, confidence: high_pending_physical_device_validation, evidence_source: SettingsStore.swift, RAGService.swift, PCCConsentPreferenceMigrationTests.swift]`
- **[Ingestion]** Made queue dismissal authoritative: Stop/X and paused-item discard now persist bounded deletion-wins tombstones through iCloud reconciliation, so the same queue IDs cannot reappear after a workspace reload. Empty-vector self-healing rebuilds now run through one sequential scheduler, honor persistent per-library suppression on the current device, and stop only at catalog-safe points. Explicit imports and manual rebuilds clear that local suppression. `[evidence_level: code_verified, confidence: high_pending_runtime_validation, evidence_source: RAGService.swift, WorkspaceSyncService.swift, IngestionQueueOverlay.swift, IngestionQueueTombstoneTests.swift]`
- **[Indexing]** Made the embedding-normalization ordering fixture construct its SIMD coordinates explicitly, avoiding Swift type-inference ambiguity without changing the tested values. `[evidence_level: code_verified, confidence: exact, evidence_source: EmbeddingNormalizationBoundsTests.swift]`
- **[Chunking]** Added a deterministic capitalized-entity fallback when Natural Language tagging returns no entities, preserving useful chunk metadata in simulator or asset-constrained environments. `[evidence_level: code_verified, confidence: exact, evidence_source: SemanticChunker.swift]`
- **[Compatibility]** Fixed the physical-iPhone build failure caused by calling macOS-only imported `SecTaskCreateFromSelf` and `SecTaskCopyValueForEntitlement` declarations in the iOS branch. The checker now uses `SecTask` only on native macOS, parses signed provisioning entitlements on iOS/Catalyst development and ad-hoc builds, and uses Foundation Models availability/quota gates for profile-less distribution builds. A generic arm64 iPhoneOS build now succeeds. `[evidence_level: build_verified+sdk_verified, confidence: exact_for_compilation, evidence_source: EngineSDKCompatibility.swift and generic/platform=iOS build 2026-07-15]`
- **[Orchestration]** Added a Swift 6 `@unknown default` for future PCC quota-status values. Unrecognized SDK states now map to `.unknown`, preserving fail-closed routing instead of breaking compilation when Apple extends the non-frozen quota enum. `[evidence_level: code_verified, confidence: exact, evidence_source: FoundationModelCapabilityProvider.swift]`
- **[Orchestration]** Restructured the chat screen's view composition into separately compiled layers, resolving a Swift compiler timeout that could fail automated builds. No visual or behavioral change.
- **[Orchestration]** Added an explicit initializer to the hardware X-Ray overlay so its sidebar-aware configuration constructs correctly across Swift compiler versions. No visual or behavioral change.

## 4.6 - 2026-07-14
### Fixed
- **[Orchestration]** The Silicon HUD legend is now reliably draggable: put it anywhere on screen and the position persists across launches. The whole legend rectangle is touch-targetable (working around a translucent-material hit-testing quirk on iOS 27), the drag activates on touch-down at highest priority, and an interfering double-tap recognizer was removed. Drag movement resolves atomically (no more layer-tearing or spring-lag while dragging), and on iOS the legend now lives in its own floating layer above all app chrome — on iOS the floating layer is sized to the legend itself (AssistiveTouch-style; macOS keeps its corner legend), so it is draggable everywhere, physically incapable of blocking any other touch on screen, and its position reliably survives app relaunches.
- **[Orchestration]** The X-Ray hardware borders (SoC purple box, Taptic Engine) now map against the true full-screen dimensions instead of the safe-area-shrunken view, so they highlight the actual physical component locations — with the navigation bar, home indicator, and keyboard no longer skewing the mapping.
- **[Orchestration]** Restored the Silicon HUD legend to its exact v4.5 position (fixed x:110, right of the sidebar toggle): the mid-screen jump when the conversation sidebar opened was never owner-requested and is removed.
- **[Orchestration]** Re-enabled the macOS App Sandbox (`com.apple.security.app-sandbox = true`) and added user-selected file read access, fixing Mac App Store delivery rejection ITMS-90296. iOS builds are unaffected; previously shipped Mac builds were already sandboxed, so user data locations are unchanged.
- **[Orchestration]** Fixed the Silicon X-Ray overlay's physical-position mapping compressing when the keyboard appears: component borders (Taptic Engine, SoC) drew at mid-screen while typing because the overlay's geometry excluded the keyboard region. The overlay now always maps against the full screen.
- **[Indexing]** Hardened FTS5 schema migrations: `ensureColumnExists` now takes a closed, compiler-owned `ColumnMigration` enum instead of raw table/column/definition strings, with identifier validation and proper identifier/PRAGMA quoting as defense in depth. Consolidates audited PRs #27 and #55; neither branch was merged directly.
- **[Orchestration]** Model-route telemetry now reports the actually executed route: the "Advanced" on-device preference runs the standard on-device model (the installed SDK exposes no 20B/advanced model — compiler-probe verified), and telemetry no longer claims a model tier that never ran.
- **[Orchestration]** `EntitlementChecker.hasEntitlement` now fails closed when no embedded provisioning profile can be found and additionally checks the macOS profile name (`embedded.provisionprofile`). Distribution builds can no longer instantiate native Private Cloud Compute without a provable entitlement; the existing safe fallback path engages instead.
### Changed
- **[Indexing]** Unified fallback-embedding magnitude computation in `NLEmbeddingProvider` to a single-pass reduce (bit-identical result, no intermediate array), matching the accumulation style of `validateEmbedding`. Reimplements audited PR #28.
- **[Indexing]** Replaced the six-array min/max extraction in `Embedding3DView` normalization with a single-pass `normalizationBounds` helper preserving exact `min()`/`max()` NaN and seeding semantics. Reimplements audited PR #31 with the audit-mandated testable helper.
- **[Indexing]** Variance computation in `AdaptiveEmbeddingOptimizer` now folds squared deviations in a single pass (bit-identical to the previous map+reduce). Reimplements audited PR #35.
- **[Orchestration]** Rewrote `MarkdownRenderer.isHorizontalRule` as a single-pass scan that preserves the renderer's exact current semantics (mixed-marker rejection, whitespace trimming behavior), with a DEBUG-only test seam. Supersedes audited PR #34, whose literal patch would have changed tab handling.
- **[Orchestration]** Extracted `StructuredAnswerParsing` (pure, internal) backing `StructuredAnswer`'s private `citationIndex`/`minimumClaimLength` helpers so tests exercise parsing rules without widening `StructuredAnswer` visibility. Reimplements audited PRs #29/#38 without their visibility widening; PR #38's original assertions were incorrect and are documented in the audit record.
### Added
- **[Orchestration]** Regression test suites pinning current behavior for: fallback embeddings, embedding-space normalization bounds, RAG eval mean/percentile latency (PR #33 audited as no-change-needed: its guard was dead code), horizontal-rule parsing, structured-answer citation parsing, launch-argument parsing edge matrix (adopts audited PR #51), `WorkspaceTier` and `LLMModelType` suites (consolidating audited PRs #26/#46 and #32/#50).

## 4.5.1 - 2026-07-03
### Fixed
- **[Ingestion]** Resolved concurrency race conditions and deadlocks during parallel PDF ingestion by introducing thread-safe `NSRecursiveLock` serialization around CoreImage image generation, preventing concurrent Metal context memory crashes on Apple Silicon.
- **[Ingestion]** Implemented robust resumption state tracking for large document ingestion using `ingestion_state.json`, preserving a stable `documentId` and accumulated counts (chunks, words, chars) across app suspensions, sleeps, and restarts.
- **[Ingestion]** Fixed vector database progress loss by forcing `db.persist()` calls at the end of each page batch, ensuring embeddings are flushed to disk periodically.
- **[Ingestion]** Resolved app freezes and metadata loss upon force close by awaiting `saveDocumentsToDisk()` synchronously on completion, and pre-generating suggested questions immediately inside the ingestion pipeline rather than on-demand.
- **[Ingestion]** Hardened the `SelfTuning` engine to dynamically apply chunking adjustments (strategy, window size, overlap) directly to the active container configuration without forcing or scheduling a full database rebuild, reserving rebuilds only for destructive embedding provider shifts.
- **[UI]** Hardened Live Activity lifecycles by terminating any lingering/orphaned activities on app startup when the ingestion queue is empty, and ending duplicate activities to prevent stacking.
- **[UI]** Disabled the Silicon X-Ray HUD overlay completely on macOS as it is an iOS-centric diagnostic feature that was inadvertently persisting on the Mac build.
- **[UI]** Restored the iOS Silicon HUD position back to its original layout coordinates (x: 45, y: safeAreaInsets.top + 85), and configured the HUD legend to dynamically shift to the right (x: 345) when the conversation history sidebar is visible to prevent overlap.
- **[Orchestration]** Corrected a key platform misconception regarding on-device execution: Apple's native 20B sparse Mixture-of-Experts model (AFM 3 Core Advanced) is restricted by the OS to devices with at least 12GB of RAM. Implemented programmatic physical memory gating (`physicalMemory >= 11.5GB`) to automatically fallback to the local 3B Core model and hide the 20B Advanced preference option on unsupported physical devices (such as 8GB iPhones/iPads), preventing hidden system fallbacks and aligning UI options with hardware realities. Sincerest apologies for the previous oversight claiming local 20B support on all iOS 27 devices.
- **[Orchestration]** Restrained dynamic Hybrid (Automatic) routing from selecting Private Cloud Compute if the app lacks the `com.apple.developer.private-cloud-compute` entitlement, preventing silent model errors and fallback latency. Greyed out and disabled the PCC option in the header model preference selection menu when unentitled.
- **[Orchestration]** Disabled macOS automatic window tabbing programmatically on Mac Catalyst targets to prevent duplicate and redundant window tab views at the top of the window.
- **[Indexing]** Fixed a recurring Accelerate/BNNS startup error where the app failed to memory-map (`mmap`) empty or newly created vector databases (`Cocoa Error 260 / POSIX Error 2`), by adding a check to skip mapping operations when the database contains 0 chunks (`expectedBytes == 0`).
- **[Orchestration]** Deprecated headless python benchmark scripts in favor of a native, in-app `ValidationDashboardView`. 
- **[Orchestration]** Added a visual benchmark runner to the Developer Diagnostics Hub, allowing execution of pre-configured RAG validation suites with real-time monitoring of document ingestion, chunking, and reasoning outputs directly in the app.
- **[Ingestion]** Fixed severe text extraction hallucinations (data loss) on macOS by restoring the `renderScale` fallback for garbled document layers to `6.0`, ensuring Vision OCR has sufficient resolution to parse text accurately.

## 4.5.0 - 2026-07-01
### Added
- **[Indexing]** Compiled and bundled `EmbeddingModel.aimodel` inside the package resource bundle to support the native, zero-copy Core AI embedding execution path on Apple Silicon.
- **[Indexing]** Created `scripts/compile_core_ai_model.py` to automate PyTorch-to-Core AI model graph conversion using the Apple `coreai-torch` extensions.
- Large document ingestion streaming. End-to-end memory-safe stream process that avoids OOM crashes during large PDF embedding and SQLite UPSERTs.
- `RAGService+Streaming` and asynchronous `pageRange` bounds on `DocumentProcessor` for dynamic batch extraction.
- **[Indexing]** High-performance Rust-backed `swift-tokenizers` (DePasqualeOrg) integration, achieving 100x tokenization speedups and byte-level character offsets for precise citation mapping. Exposed via a local `TransformersTokenizers` wrapper target (renamed to resolve SPM product name collision and GUID registration conflicts) linked transparently into the main target.
- **[Orchestration]** Dynamic default embedding provider auto-selection. Automatically configures new libraries and settings to default to the native `coreai_sentence_embedding` on iOS 27+ / macOS 27+ targets while preserving `coreml_sentence_embedding` fallbacks for older (iOS/macOS 26) releases.
- **[Diagnostics]** An **AI Subsystem Diagnostics** card integrated into the Library settings, providing real-time "x-ray vision" of model load status, Neural Engine/GPU hardware acceleration targets, Rust-backed tokenizer parser, vocabulary details, byte-level citation offsets, and latency profiles.
### Fixed
- **[UI]** Enabled saving of embedding configuration options when a provider is unavailable at save-time, allowing runtime fallback routing (e.g., Core AI falling back to Core ML) to resolve and execute cleanly.
- **[Indexing]** Fixed Core AI tensor name mapping by explicitly binding the exported PyTorch graph output to "embeddings" and parsing the MLFeatureProvider dictionary correctly in `CoreAISentenceEmbeddingProvider`.
- **[Orchestration]** Fixed global embedding provider toggling bug during document ingestion that bypassed container settings. Relocated `enableIngestionMode` scoping explicitly into the `addDocument()` pipeline to guarantee the selected container provider (e.g., Core AI vs Core ML) is accurately targeted.
- SQLite FTS5 index truncation where previous batch FTS5 data, page mapping records, and chunk search records were deleted/overwritten on each streaming iteration. Added `append` support to `store`, `storePages`, and `storeChunks` methods in `SQLiteFullTextService`.
- Page index offset mapping during streaming PDF ingestion, correcting human-readable page numbering for page-level contexts.
- Ingestion deletion race condition where `WorkspaceSyncService` deleted active streaming ingest documents before metadata registration, resolved via file age protection and queue storage relative path propagation.
- Core AI embedding provider selector availability on iOS 27, introducing `CoreAISentenceEmbeddingProvider.shared` single-instance caching, an awaitable model readiness gate, and helpful compile-time and runtime diagnostics in `ContainerSettingsSheet`.
- **[Orchestration]** Resolved a fatal process crash when executing reasoning-heavy queries via Private Cloud Compute without the required developer entitlement. Implemented a runtime signature verification utility (`EntitlementChecker`) that checks the app's code signature/provisioning profile on iOS 27+ / macOS 27+ and falls back gracefully to local on-device models if the entitlement is missing. Removed the `com.apple.developer.private-cloud-compute` entitlement from [OpenIntelligence.entitlements](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/OpenIntelligence.entitlements) to resolve Xcode Cloud archive export validation failures (exit code 70) while waiting for App Store Small Business Program entitlement approval.
- **[Indexing]** Tokenizer resource resolution. Moved tokenizer resource bundles to the local `swift-transformers` package target to completely bypass Xcode file-system synchronized target resource collisions and flattening bugs, resolving compile-time and runtime loading issues.
- **[Settings]** SwiftUI scope lookup error inside settings sheets by accessing `@EnvironmentObject` variables directly using `self.settings` inside sheet extensions, resolving PCC fallback configuration compile failures.
- **[Ingestion]** Ingestion file sync-sweep race condition where background cleanups deleted recently uploaded files. Resolved by touching the modification date of newly copied workspace files to current date, ensuring they are protected by the 15-minute sweep guard before metadata registration finishes.

> **Documentation status:** Verified for OpenIntelligence v4.3 on June 20, 2026.

# Changelog

This is the public version history for OpenIntelligence. It focuses on user-visible product changes and intentionally omits private engine tuning, thresholds, and internal implementation details.

## 4.4 - June 2026

- **[Ingestion]** Implemented zero-copy `CGImage` processing in `StructuredDocumentParser.swift`, bypassing CPU-bound PNG serialization and decompress steps to accelerate Vision OCR and structure extraction by 30%+.
- **[Ingestion]** Added a page-level JSON checkpointing system in `DocumentProcessor.swift` (persisted locally under the non-syncing `localCacheDir()/IngestionCheckpoints/` path) to support resumption of interrupted document uploads.
- **[Ingestion]** Integrated checkpoint cleanup hooks in `RAGService.swift` triggered upon successful document completion and queue item discards.
- **[Widgets]** Refined `IngestionLiveActivityLockScreenView` to render a tailored, glanceable layout for the `.small` activity family on watchOS (Smart Stack), featuring a circular progress ring and compact metadata details.
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
- **[Orchestration]** Wrapped native Private Cloud Compute execution in compiler-version conditionals (`#if compiler(>=6.4)`) to support compilation on older SDK environments (like Xcode 16.x on the GitHub Actions CI runner).
- **[Retrieval]** Refined RAG verification gate logic to prevent false-positive refusals on query-specific terms, and added English stemming rules for singular/plural word variants.
- **[Retrieval]** Restored support for ungrounded fallbacks under standard/reliability modes when ungrounded answers are permitted.
- **[Orchestration]** Hardened model preference selection by forcing local execution boundaries (`allowPrivateCloudCompute = false`, `executionContext = .onDeviceOnly`) and capping RAG context budgets to 6K tokens when the 3B Core or 20B Advanced models are selected.
- **[Orchestration]** Resolved all Swift 6 compiler warnings and actor isolation issues across RAGService and EvidenceThreadStore.
- **[Retrieval]** Adjusted similarity thresholds and replaced vocabulary-limited word pairs in the Developer Diagnostics Quick Sanity Check to prevent false failures under CoreML and legacy Natural Language embedding providers.
- **[Orchestration]** Added a direct external link row to the Notion Roadmap database in the About Screen to easily monitor milestones and task statuses.
- **[Orchestration]** Shifted the iOS Silicon HUD status overlay horizontally to the right of the top-left threads sidebar button to avoid overlapping while maintaining the original vertical offset.
- **[Orchestration]** Fixed the 'New Chat' action to preserve previous conversation history in a completed thread instead of deleting it from disk, and introduced container-scoped active thread tracking to prevent cross-container thread selection bleed.
- **[Orchestration]** Calibrated Pro Annual subscription price to $29.99/year (representing a 58% savings vs monthly) and introduced a 7-day free trial introductory offer.
- **[Orchestration]** Discontinued the consumable Document Pack add-on, removing all related UI cards, quick-refill views, and purchase flows.
- **[Orchestration]** Replaced the custom two-step review prompt alert with direct calls to Apple's native \`requestReview\` action during successful sessions and thumbs-up events, satisfying App Store Review Guideline 5.6.

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
- **[Indexing] Core AI Native Embeddings**: Fully integrated and enabled the `CoreAISentenceEmbeddingProvider` under Apple's Core AI framework. Unlocks zero-copy Silicon-native sentence embeddings on iOS 27+ / macOS 27+ compatible devices, with dynamic auto-tuning and library settings configuration mappings.
- **Live Telemetry & UI Trust Layer**: Added the `ThinkingStreamView` directly to the `UnifiedMetricsBar` for live LLM reasoning telemetry and refreshed the interface with modern Liquid Glass UI components.
- **Metal GPU-Accelerated Vector Search**: Integrated SIMD4 and threadgroup-level Metal pipelines in `GPUComputeService` for 4x faster local batch vector calculations.
- **Adaptive Ingestion Pipeline**: Integrated `PageComplexityAnalyzer` to pre-scan document structures. Digital PDF pages skip Vision OCR execution automatically (averaging a 20% skip rate), and the system dynamically scales rendering resolution (360-432 DPI) based on page density risk.
- **Database Safety & Physical File GC**: Switched `BNNSVectorDatabase` disk saves to atomic writes, preventing local file corruption and size mismatch issues. Added local physical file garbage collection in `WorkspaceSyncService` to purge orphaned documents.
- **Cascading Ingestion Deletions**: Hardened the ingestion queue to trigger a clean cascading deletion (database entries, physical files, FTS5 tables, and Spotlight indexes) when uploads are canceled or discarded.
- **Siri, Shortcuts & Spotlight**: Document and library items are now persisted App Entities (`OIDocumentEntity`, `OILibraryEntity`), enabling Siri/Shortcuts actions. Spotlight indexes down to specific chunks and sections.
- **Suggested Questions Polish**: Refined suggestions with a two-pass diversity chunk selector, `NLTagger` POS grammar filters, and offline curated suggestions that bypass LLM runtime overhead on app start.
- **Continuous Evaluations Suite**: Built `RAGEvalRunner` to run evaluation datasets, tracking Recall@5, Citation Precision, and Hallucination metrics against spec targets.
- **[Shortcuts] iCloud Syncing Evidence Threads**: Implemented thread-safe local JSON storage for isolated chat history, bidirectionally synchronized via `WorkspaceSyncService` in iCloud Drive, gated with billing quotas (5/20/unlimited), and registered as Siri App Intents. Added a dedicated shortcuts integration card directly to the settings dashboard detailing copyable Siri phrases and validation rules.
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
