# Canonical OpenIntelligence Source of Truth

## 1. Purpose and Supersession Rule
This document is the absolute ground truth for the OpenIntelligence repository architecture. It supersedes all other markdown documentation, comments, and developer notes. If another document contradicts this file, that document is considered stale or hallucinated.

## 2. Current Product Definition
OpenIntelligence is a local-first, privacy-preserving retrieval-augmented generation application for Apple platforms, leveraging on-device intelligence.

## 3. Safe Claims
- The app uses iCloud Drive (Ubiquity containers) for sync via `NSFileCoordinator` and `NSMetadataQuery`. `[evidence: code_verified, exact, WorkspaceSyncService.swift]`
- PCC execution routes natively to secure enclaves via `FoundationModels.PrivateCloudComputeLanguageModel` on iOS 27 / macOS 27+ only if the process contains the `com.apple.developer.private-cloud-compute` code-signed entitlement, verified at runtime via `EntitlementChecker`. If the entitlement is missing, the system falls back cleanly to local `SystemLanguageModel` simulation to prevent fatal crashes. Dedicated UI settings sheets and an AI Subsystem Diagnostics card provide real-time status of PCC routing and model readiness. Due to Xcode Cloud archive export signing requirements, the entitlement is temporarily omitted from the active `.entitlements` file, relying on the runtime fallback to local models until the developer account is approved for the PCC capability. `[evidence: code_verified, exact, FoundationModelSessionFactory.swift, FoundationModelRoutePolicy.swift, ContainerSettingsSheet+Sections.swift, OpenIntelligence.entitlements]`
- Relational metadata indexing relies on a single shared SQLite file with column-based `container_id` isolation. `[evidence: code_verified, exact, SQLiteFullTextService.swift]`
- Billing entitlements are stored in `UserDefaults`. `[evidence: code_verified, exact, EntitlementStore.swift]`
- Core AI embeddings are used in production. Runs zero-copy Silicon-native sentence embeddings on iOS 27+ / macOS 27+ compatible devices, falling back to Core ML. The compiled model is bundled inside a custom raw resource folder (`EmbeddingModel.bundle`) to bypass Xcode build-time `mlassetc` compiler checks that block minimum deployment targets below 27.0. `[evidence: code_verified, exact, CoreAISentenceEmbeddingProvider.swift, Package.swift]`
- Ingestion pipeline runs zero-copy `CGImage` Vision OCR/Structure processing, page-level JSON checkpoints under `localCacheDir()`, parallel ingestion concurrency locks (using `NSRecursiveLock` around CGImage rendering), and a predictive pre-scan (via `LibraryIntelligenceCenter`) to self-tune extraction configurations before indexing begins. `[evidence: code_verified, exact, DocumentProcessor.swift, RAGService.swift, LayoutAwareExtractor.swift, StructuredDocumentParser.swift, PageComplexityAnalyzer.swift]`
- Large document ingestion streams in page batches (OOM safe) and performs incremental FTS5 database inserts via an append option. `WorkspaceSyncService` protects recently modified or queue-tracked files from sync-based deletion sweeps. Recently copied workspace files are protected from background deletion sweeps by touching their modification date to current date immediately after copying, ensuring they are protected by the 15-minute sweep guard before metadata registration finishes. `[evidence: code_verified, exact, RAGService+Streaming.swift, WorkspaceSyncService.swift, RAGService.swift, DocumentPicker.swift]`
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
- `LLMService.swift` and `FoundationModelRoutePolicy.swift` handle consent. Deadlocks can occur if background tasks bypass the `CloudConsentPromptView`. `[evidence: code_verified, exact, FoundationModelRoutePolicy.swift]`

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
- App Intents triggering PCC consent deadlock.
- iCloud Sync behavior for imported physical documents.
- `BNNSVectorDatabase` memory mapping limits.

## 15. Required Future-Agent Checklist
See `Docs/AuditArtifacts/ArchitectureAtlas/future_agent_checklist.md`.

## 16. How to Supersede this Canonical Doc
To supersede this doc, an agent must complete a new Architecture Atlas discovery phase verifying the code changes and use `evidence_level` and `confidence` metrics in a Delta Repair report.
