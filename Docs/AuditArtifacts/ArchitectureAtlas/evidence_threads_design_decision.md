# Evidence Threads Design Decision

> **Superseded in part (2026-09-29).** Phase 1B (`b661aab`, 2026-06-28) changed what sections 5, 8 and 10 decided, and Phase 1C replaced section 12's message type:
> - **Section 5.** Threads are stored in `Application Support/EvidenceThreads/<containerId>/` (`EvidenceThreadStore.swift:60`), not under `LocalCache/`. The store copies old `LocalCache/EvidenceThreads/` files across at launch (`migrateLegacyThreadsIfNeeded`, `EvidenceThreadStore.swift:19-23`).
> - **Section 8.** iCloud sync shipped, through `WorkspaceSyncService.synchronizeEvidenceThreads` (called at `WorkspaceSyncService.swift:2331`, defined at `:2732`). Whether it reaches the store's folder is an open Unknown in the Evidence Threads row of `Docs/ai/ARCHITECTURE.md`.
> - **Section 10.** App Intents shipped: `ListEvidenceThreadsIntent` (`RAGAppIntents.swift:795`) and `CreateNewEvidenceThreadIntent` (`:843`).
> - **Section 12.** Phase 1A (`f977849`, 2026-06-27) defined `EvidenceThreadMessage` inside `EvidenceThread.swift` rather than in a file of its own, with `messages: [EvidenceThreadMessage]`. Phase 1C (`5e5f1b9`, the same day) deleted the type and made `messages` `[ChatMessage]` (`EvidenceThread.swift:16`), which is why every thread file stores `ChatMessage`'s Codable shape and why `ChatMessage.swift` stays a hard boundary.
>
> The same Phase 1B commit added per-tier thread limits (`QuotaPolicy.evidenceThreadLimit`), which qualifies section 9, and Phases 1B and 1C (`5e5f1b9`) edited `WorkspaceSyncService.swift` and `ChatScreen.swift`, two files section 14 prohibited in Phase 1. Still standing: the comparison of Designs A to D (sections 2 to 4), the choice of one JSON file per thread, and section 6, since `ChatMessage.swift` has not changed since `fca838e` (2026-06-09) and is a hard-boundary file in `CLAUDE.md`. For the current state read canonical doc section 11 and the Evidence Threads row of `Docs/ai/ARCHITECTURE.md`. `[evidence_level: code_verified, confidence: high, evidence_source: EvidenceThreadStore.swift:19-23,60; WorkspaceSyncService.swift:2331,2732; RAGAppIntents.swift:795,843; EvidenceThread.swift:16; git show --stat b661aab; git show f977849 and 5e5f1b9 (the EvidenceThreadMessage struct added, then removed); git log on ChatMessage.swift; read 2026-09-29]`

## 1. Decision Summary
We will implement Evidence Threads using isolated JSON files per thread (Design B). This ensures zero blast radius to the legacy chat system, provides high performance for individual thread operations, and aligns perfectly with the existing iCloud Drive (Ubiquity) sync mechanism without requiring complex SQLite or CoreData migrations.

## 2. Designs Compared
- **Design A:** Add `threadId` to `ChatMessage` and reuse `chat_history_<containerId>.json`.
- **Design B:** Use isolated thread files under `LocalCache/EvidenceThreads/<containerId>/`.
- **Design C:** Use SQLite-backed thread store.
- **Design D:** Use SwiftData/CoreData-backed thread store.

## 3. Chosen Design
**Design B: Use isolated thread files under `LocalCache/EvidenceThreads/<containerId>/`.**

## 4. Rejected Designs and Why
- **Design A:** Rejected. Modifying `ChatMessage` and reusing the existing monolithic JSON array increases the blast radius significantly. It risks corrupting existing user chat histories and suffers from poor performance (O(N) write/delete scaling).
- **Design C:** Rejected. The current `SQLiteFullTextService.swift` is strictly local-only. Implementing sync for SQLite would require custom delta-sync logic, breaking the current `WorkspaceSyncService` paradigm.
- **Design D:** Rejected. Introducing CoreData/SwiftData would imply a shift to CloudKit for sync, which fundamentally contradicts the current `NSUbiquityIdentityDidChange` (iCloud Drive) architecture.

## 5. Storage Path Recommendation
`Application Support/LocalCache/EvidenceThreads/<containerId>/<threadId>.json`

## 6. Whether ChatMessage should be modified
**No.** `ChatMessage.swift` must remain completely untouched to preserve legacy compatibility.

## 7. Whether legacy chat should be copy-forwarded
**Yes.** The legacy chat structures should remain untouched while net-new `EvidenceThread` models are created.

## 8. Whether iCloud sync is deferred
**Yes.** Phase 1 will write local files only. Sync via `WorkspaceSyncService` is deferred.

## 9. Whether StoreKit is deferred
**Yes.** Billing boundaries are untouched.

## 10. Whether App Intents are deferred
**Yes.** Siri/App Intents integrations for threads are deferred.

## 11. Whether routing/PCC is untouched
**Yes.** `LLMService` and `FoundationModelRoutePolicy` handle PCC consent and routing automatically; they must not be modified.

## 12. Files allowed in future Phase 1A
- Net-new models: `EvidenceThread.swift`, `EvidenceThreadMessage.swift`
- Net-new store: `EvidenceThreadStore.swift`
- Net-new UI views for Evidence Threads.

## 13. Files allowed in future Phase 1B
- Integration points: `RAGService.swift` (to supply thread context to queries).
- App entry point: `OpenIntelligenceApp.swift` (for dependency injection of the new store).

## 14. Files prohibited in Phase 1
- `ChatMessage.swift`
- `ChatScreen.swift`
- `SQLiteFullTextService.swift`
- `WorkspaceSyncService.swift`
- `LLMService.swift`
- `FoundationModelRoutePolicy.swift`
- `EntitlementStore.swift`

## 15. Tests/QA Required
- Thread creation, persistence, and retrieval from disk.
- Deletion of isolated thread files.
- Ensuring legacy chat remains fully functional without data loss.
- Verification that new files do not trigger unintentional PCC errors.

## 16. Remaining Unknowns
- How `RAGService.swift` will ingest the `EvidenceThread` context without breaking legacy `ChatComposerV2.swift` behavior.
- The exact retention policy for Evidence Threads (should they be auto-pruned or kept indefinitely).
