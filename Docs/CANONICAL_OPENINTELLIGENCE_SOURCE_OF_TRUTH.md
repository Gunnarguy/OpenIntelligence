# Canonical OpenIntelligence Source of Truth

## 1. Purpose and Supersession Rule
This document is the absolute ground truth for the OpenIntelligence repository architecture. It supersedes all other markdown documentation, comments, and developer notes. If another document contradicts this file, that document is considered stale or hallucinated.

## 2. Current Product Definition
OpenIntelligence is a local-first, privacy-preserving retrieval-augmented generation application for Apple platforms, leveraging on-device intelligence.

## 3. Safe Claims
- The app uses iCloud Drive (Ubiquity containers) for sync via `NSFileCoordinator` and `NSMetadataQuery`. `[evidence: code_verified, exact, WorkspaceSyncService.swift]`
- The public execution targets are `SystemLanguageModel.default` on-device and, on iOS/macOS 27+, `FoundationModels.PrivateCloudComputeLanguageModel`. There is no app-selectable public 3B/20B/Advanced model API. The source PCC entitlement is enabled following user-confirmed Apple approval. `EntitlementChecker` uses public platform evidence: native macOS `SecTask`, the embedded signed provisioning profile for iOS/Catalyst development and ad-hoc builds, and Apple's documented PCC availability/quota APIs when App Store/TestFlight omits that profile. The session factory rechecks availability and quota immediately before construction. The branch is generic arm64 iPhoneOS compile-verified. iOS/macOS 26 is local-only—local execution is never represented as simulated PCC. Signed installation and distribution behavior are not yet runtime-verified. `[evidence_level: build_verified+sdk_verified+user_confirmed, confidence: high_for_source_unverified_for_distribution, evidence_source: LLMModel.swift, EngineSDKCompatibility.swift, FoundationModelCapabilityProvider.swift, FoundationModelSessionFactory.swift, OpenIntelligence.entitlements]`
- PCC route selection occurs after local retrieval. `ModelExecutionPlanner` consumes pre-retrieval constraints, post-retrieval evidence, live capability/quota state, and exact-or-labeled-fallback context budgets. The selected cloud stage receives a minimized evidence envelope only after valid consent; deterministic verification remains local. `ModelExecutionReceipt` separates intended, attempted, actual, fallback, and completed routes and is persisted optionally for backward compatibility. `[evidence_level: code_verified, confidence: high, evidence_source: ModelExecutionPlanner.swift, RAGService.swift, ModelExecutionReceipt.swift, RAGQuery.swift]`
- GPU-capable application work uses four persisted execution preferences (Efficiency, Balanced, Performance, Maximum), not a claimed utilization percentage. The preference gates PDF rendering, Core ML compute configuration at existing model-load boundaries, sufficiently large Metal vector/MMR paths, and background GPU eligibility; Apple frameworks retain final device scheduling control. `[evidence_level: code_verified+test_verified, confidence: high_pending_device_thermal_validation, evidence_source: DeviceCapabilityService.swift, SettingsView.swift, RAGEngine.swift, BNNSVectorDatabase.swift]`
- Relational metadata indexing relies on a single shared SQLite file with column-based `container_id` isolation. `[evidence: code_verified, exact, SQLiteFullTextService.swift]`
- Billing entitlements are stored in `UserDefaults`. `[evidence: code_verified, exact, EntitlementStore.swift]`
- Core AI embeddings are used in production. Runs zero-copy Silicon-native sentence embeddings on iOS 27+ / macOS 27+ compatible devices, falling back to Core ML. The compiled model is bundled inside a custom raw resource folder (`EmbeddingModel.bundle`) to bypass Xcode build-time `mlassetc` compiler checks that block minimum deployment targets below 27.0. `[evidence: code_verified, exact, CoreAISentenceEmbeddingProvider.swift, Package.swift]`
- Ingestion pipeline runs zero-copy `CGImage` Vision OCR/Structure processing, page-level JSON checkpoints under `localCacheDir()`, parallel ingestion concurrency locks (using `NSRecursiveLock` around CGImage rendering), and a predictive pre-scan (via `LibraryIntelligenceCenter`) to self-tune extraction configurations before indexing begins. `[evidence: code_verified, exact, DocumentProcessor.swift, RAGService.swift, LayoutAwareExtractor.swift, StructuredDocumentParser.swift, PageComplexityAnalyzer.swift]`
- Large document ingestion streams in page batches (OOM safe) and performs incremental FTS5 database inserts via an append option. `WorkspaceSyncService` protects recently modified or queue-tracked files from sync-based deletion sweeps. Recently copied workspace files are protected from background deletion sweeps by touching their modification date to current date immediately after copying, ensuring they are protected by the 15-minute sweep guard before metadata registration finishes. `[evidence: code_verified, exact, RAGService+Streaming.swift, WorkspaceSyncService.swift, RAGService.swift, DocumentPicker.swift]`
- Ingestion queue removal uses bounded, deletion-wins tombstones in the existing coordinated queue JSON. Tombstones survive an otherwise empty queue, filter stale local/shared items during iCloud Drive reconciliation, and remain backward compatible with queue files that predate the field. Automatic empty-vector repair is single-flight and sequential; Stop/Discard persistently suppresses it per library in local device preferences until an explicit import or manual rebuild clears the suppression. `[evidence_level: code_verified, confidence: high_pending_runtime_validation, evidence_source: WorkspaceSyncService.swift, RAGService.swift, IngestionQueueOverlay.swift]`
- On-device tokenization is powered by a high-performance Rust-backed `swift-tokenizers` (DePasqualeOrg) package loaded asynchronously from the local resource bundle, replacing legacy pure-Swift `BertTokenizer` to provide a 100x speedup and exact byte-level character offsets. `[evidence: code_verified, exact, CoreAISentenceEmbeddingProvider.swift, CoreMLSentenceEmbeddingProvider.swift, DocumentProcessor.swift, RAGEngine.swift]`

## 4. Unsafe Claims
- The app uses CloudKit databases. (FALSE) `[evidence: code_verified, exact]`
- Knowledge libraries use separate isolated SQLite files. (FALSE) `[evidence: code_verified, exact]`

## 5. Non-Negotiable Facts
- `SUPERSEDING_EVIDENCE_PROTOCOL.md` must be followed for all agent workflows.
- No destructive commands may be run.

## 6. Storage Boundaries
- SQLite is strictly local. `[evidence: code_verified, exact]`
- Vectors use `BNNSVectorDatabase` with memory mapping. `[evidence: code_verified, exact]`
- Chat messages are serialized to monolithic JSON arrays. `[evidence: code_verified, exact]`
- Ingestion checkpoints are stored as JSON files under `localCacheDir()/IngestionCheckpoints/<fingerprint>/`. `[evidence: code_verified, exact, DocumentProcessor.swift]`

## 7. Sync Boundaries
- `WorkspaceSyncService.swift` sweeps local files for iCloud Drive ubiquity sync. `[evidence: code_verified, exact, WorkspaceSyncService.swift]`

## 8. Routing/PCC Boundaries
- `QueryRuntimeCoordinator` produces constraints only; it does not claim a final PCC route. `RAGService` assembles evidence locally, creates the post-retrieval plan, minimizes the PCC envelope, and requests consent for that exact payload. `LLMService` and `FoundationModelSessionFactory` execute the selected public target and record the actual result. `[evidence_level: code_verified, confidence: high, evidence_source: QueryRuntimeCoordinator.swift, RAGService.swift, LLMService.swift, FoundationModelSessionFactory.swift]`
- Background and App Intent execution never suspends waiting for `CloudConsentPromptView`: remembered consent may authorize PCC; otherwise Hybrid and explicit PCC policy use the declared local fallback before meaningful text streams. The receipt preserves PCC as intended and on-device as completed, and no PCC/local fallback occurs after meaningful text has streamed. `[evidence_level: code_verified, confidence: high_pending_physical_device_validation, evidence_source: ModelExecutionPlanner.swift, ModelExecutionPlan.swift, LLMService.swift, RAGService.swift]`
- The chat picker stores routing policy, not execution history. `Hybrid`, `On-Device`, and `PCC` remain stable through route notifications and relaunch; per-response route badges are computed from existing optional receipt/route metadata without changing the persisted `ChatMessage` shape. `[evidence_level: build_verified+code_verified, confidence: high_pending_ui_runtime_validation, evidence_source: SettingsStore.swift, ModelStatusIndicator.swift, MessageBubbleV2.swift, ChatMessage.swift and generic iOS 27 simulator build 2026-07-16]`
- **The picker persisted correctly but did not govern routing in Deep Think or Maximum until 2026-07-30.** `AgenticOrchestrator.generateWithProperConsent` built a fresh `InferenceConfig` carrying only maxTokens/temperature/systemPrompt, so `fmPreference`, `executionContext`, and `allowPrivateCloudCompute` fell back to defaults regardless of the stored policy. Three physical-device runs — one per setting — were identical in routing, and an On-Device selection still sent a minimized envelope to PCC. Consent was never bypassed and Standard was unaffected. Fixed by capturing a `UserRoutingPreference` per query in `executeAgenticQuery` and applying it before planning; On-Device is now absolute and covers final synthesis. `[evidence_level: device_verified_for_the_defect+build_verified+test_verified_for_the_fix, confidence: high_for_the_defect_unverified_on_device_for_the_fix, evidence_source: PCC/On-Device/Hybrid device logs 2026-07-30, commit 6f29d2d]`
- PCC remembered consent is canonical in `cloudConsent.applePCC`; the legacy `pcc.setting` value is migrated and synchronized without overriding an explicit canonical allow/deny decision. The app does not prewarm consent UI at launch. `pendingCloudConsent` is populated only by a real transmission record after the route and minimized envelope exist. `[evidence_level: code_verified+test_verified, confidence: high_pending_physical_device_validation, evidence_source: SettingsStore.swift, RAGService.swift, PCCConsentPreferenceMigrationTests.swift]`
- Unknown future `PrivateCloudComputeLanguageModel.QuotaUsage.Status` values map to `.unknown` via `@unknown default`; they never authorize PCC execution. `[evidence_level: code_verified, confidence: exact, evidence_source: FoundationModelCapabilityProvider.swift]`
- Telemetry may record plan IDs, public target names, counts, token budgets, quota categories, hashes, reason codes, and verification status. It must not record raw query, document, transcript, or reasoning content. `[evidence_level: code_verified+policy, confidence: high, evidence_source: RAGService.swift, ModelExecutionReceipt.swift]`
- The floating Silicon HUD is scene-scoped on iOS: frame calculation requires the HUD window's `UIWindowScene.screen`, avoiding deprecated global-screen state and cross-display ambiguity. `[evidence_level: build_verified+code_verified, confidence: exact_for_build, evidence_source: MotherboardHUDView.swift and generic iOS 27 simulator build 2026-07-16]`

## 9. Billing Boundaries
- Managed by `EntitlementStore.swift` via `UserDefaults`.

## 10. App Intents Boundaries
- `RAGAppIntents` utilizes 9 of the 10 available App Shortcuts limit.

## 11. Evidence Threads Canonical Decision
- **Design B**: Relocated from `LocalCache` to `Application Support/EvidenceThreads/<containerId>/` to support iCloud Drive synchronization. `[evidence: code_verified, exact, EvidenceThreadStore.swift]`
- **Synchronization**: Thread files are synchronized bidirectionally via `WorkspaceSyncService.swift` on changes, gated by tier-specific limits (5 Free / 20 Pro / Unlimited Lifetime) in `QuotaPolicy.swift`. `[evidence: code_verified, exact]`
- Legacy `ChatMessage` remains untouched (EvidenceThread uses ChatMessage array for immutability).
- RAGService and ChatScreen integration complete. ChatScreen features a slide-out ThreadSidebarView, enabling thread switching, creation, and deletion, with history persistence and loading managed asynchronously by RAGService.

## 12. Phase Boundaries
- Phase 0: Master Operating Rules (Complete)
- Phase 1: Repository Inventory (Complete)
- Phase 2: Entity & System Audit (Complete)
- Phase 3: Component Atlas (Complete)
- Phase 4: Call Relationships & Side Channels (Complete)
- Phase 5: Data-Flow and Risk-Boundary Maps (Complete)
- Phase 6: Documentation Scan & Pro Review (Complete)
- Phase 7: Evidence Threads Placement (Complete)
- Phase 8: Canonical Control System (Complete)
- Phase 9: Evidence Threads MVP Integration (Complete)
- Phase 10: Ingestion & watchOS Live Activity Refinement (Complete)

## 13. Files Allowed/Prohibited by Phase
- Audit phases prohibit modification of `*.swift` files, tests, configurations.
- Implementation phases strictly define a limited blast radius of allowed files (e.g., `EvidenceThread.swift`).

## 14. Known Unresolved Risks
- **Native PCC execution is owner-confirmed on a physical device (2026-07-28, on v4.6)** and is no longer listed as unverified. `[evidence_level: user_confirmed, confidence: high_for_execution_path, evidence_source: owner device testing]` Still unverified: signed physical-device installation, archive/TestFlight entitlement propagation, quota exhaustion, and network-transition behavior. Owner confirmation covered the execution path only and did not state coverage for those edge scenarios.
- The background/App Intent consent deadlock has a source-level prevention path and focused policy tests, but still requires physical-device/manual validation.
- iCloud Sync behavior for imported physical documents.
- `BNNSVectorDatabase` memory mapping limits.

## 15. Required Future-Agent Checklist
See `Docs/AuditArtifacts/ArchitectureAtlas/future_agent_checklist.md`.

## 16. How to Supersede this Canonical Doc
To supersede this doc, an agent must complete a new Architecture Atlas discovery phase verifying the code changes and use `evidence_level` and `confidence` metrics in a Delta Repair report.

## 17. Repository Agent Operations Boundary
- Every repository task is routed through `.codex/skills/route-openintelligence-work/SKILL.md`, which derives task ownership and change requirements from `Docs/AuditArtifacts/RepoOS/change_impact_matrix.csv`. Its preflight also derives the active release from current repository artifacts and reports the exact changelog, release-notes, and Notion release targets without forcing edits for read-only work. `[evidence: code_verified, exact, .codex/skills/route-openintelligence-work/scripts/repoos_router.py]`
- The workspace router is developer governance tooling only. It does not compile into, modify, or execute within the OpenIntelligence Apple app. `[evidence: code_verified, exact, change_impact_matrix.csv repoos_workspace_automation boundary]`
- Notion relevance must be evaluated on every task; durable implementation, bug, milestone, release, and roadmap work is synchronized at start and verified completion according to `.agents/workflows/sync-notion.md`. `[evidence: code_verified, exact, .codex/skills/route-openintelligence-work/SKILL.md]`
