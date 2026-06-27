# Canonical OpenIntelligence Source of Truth

## 1. Purpose and Supersession Rule
This document is the absolute ground truth for the OpenIntelligence repository architecture. It supersedes all other markdown documentation, comments, and developer notes. If another document contradicts this file, that document is considered stale or hallucinated.

## 2. Current Product Definition
OpenIntelligence is a local-first, privacy-preserving retrieval-augmented generation application for Apple platforms, leveraging on-device intelligence.

## 3. Safe Claims
- The app uses iCloud Drive (Ubiquity containers) for sync via `NSFileCoordinator` and `NSMetadataQuery`.
- PCC execution is simulated entirely locally on `SystemLanguageModel.default`.
- Relational metadata indexing relies on a single shared SQLite file with column-based `container_id` isolation.
- Billing entitlements are stored in `UserDefaults`.

## 4. Unsafe Claims
- The app uses CloudKit databases. (FALSE)
- The app executes against a remote PCC secure enclave. (FALSE)
- Core AI embeddings are used in production. (FALSE, it's behind `#if false`).
- Knowledge libraries use separate isolated SQLite files. (FALSE)

## 5. Non-Negotiable Facts
- `SUPERSEDING_EVIDENCE_PROTOCOL.md` must be followed for all agent workflows.
- No destructive commands may be run.

## 6. Storage Boundaries
- SQLite is strictly local.
- Vectors use `BNNSVectorDatabase` with memory mapping.
- Chat messages are serialized to monolithic JSON arrays.

## 7. Sync Boundaries
- `WorkspaceSyncService.swift` sweeps local files for iCloud Drive ubiquity sync.

## 8. Routing/PCC Boundaries
- `LLMService.swift` and `FoundationModelRoutePolicy.swift` handle consent. Deadlocks can occur if background tasks bypass the `CloudConsentPromptView`.

## 9. Billing Boundaries
- Managed by `EntitlementStore.swift` via `UserDefaults`.

## 10. App Intents Boundaries
- `RAGAppIntents` utilizes 9 of the 10 available App Shortcuts limit.

## 11. Evidence Threads Canonical Decision
- **Design B**: Use isolated thread files under `LocalCache/EvidenceThreads/<containerId>/`.
- Legacy `ChatMessage` must remain untouched.

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
