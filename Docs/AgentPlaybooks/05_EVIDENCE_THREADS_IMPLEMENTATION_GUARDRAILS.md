# Evidence Threads Implementation Guardrails

> **Phase 1A only (2026-09-29).** These constraints governed the first, local-only store (`f977849`, 2026-06-27). Phase 1B (`b661aab`, 2026-06-28) shipped three things this page forbids:
> - **iCloud sync of thread files**: `WorkspaceSyncService.synchronizeEvidenceThreads`, called at `WorkspaceSyncService.swift:2331` and defined at `:2732`. Whether it reaches the folder the store writes is an open Unknown; see the Evidence Threads row in `Docs/ai/ARCHITECTURE.md`.
> - **App Intents**: `ListEvidenceThreadsIntent` (`RAGAppIntents.swift:795`) and `CreateNewEvidenceThreadIntent` (`:843`).
> - **Storage in `Application Support/EvidenceThreads/<containerId>/`** (`EvidenceThreadStore.swift:60`), not `LocalCache/EvidenceThreads/`; `migrateLegacyThreadsIfNeeded` copies old `LocalCache` threads across at launch.
>
> The same commit added per-tier thread limits (`QuotaPolicy.evidenceThreadLimit`, checked in `RAGService.createNewThread`), so the StoreKit line below is also Phase 1A only. **Still binding:** every hard-boundary file in `CLAUDE.md`, whatever this page says, which includes `WorkspaceSyncService.swift`, `RAGAppIntents.swift`'s shortcut count, `QuotaPolicy.swift` tier limits, `EntitlementStore.swift`, `*.storekit` and `FoundationModelRoutePolicy.swift`; the `evidence_threads_change` route's forbidden list (`ChatMessage.swift`, `WorkspaceSyncService.swift`, `QuotaPolicy.swift` tier limits, `Docs/RepoOS/01_TASK_ROUTER.md` section 4); `ChatMessage` untouched, since `EvidenceThread.messages` is `[ChatMessage]`; no destructive migrations; and no per-token disk writes during generation. Evidence Threads changes follow that route (`AGENTS.md` rule 13). The three Phase 1B changes above were made under their own approval and do not license further edits to those files. `[evidence_level: code_verified, confidence: high, evidence_source: WorkspaceSyncService.swift:2331,2732; RAGAppIntents.swift:795,843; EvidenceThreadStore.swift:19-23,60; EvidenceThread.swift:16; RAGService.swift:878-880; git log -S for each symbol, 2026-09-29]`

This playbook defines the specific boundaries and constraints for implementing the "Evidence Threads" feature.

## Strict Implementation Constraints
- **NO Implementation without Approval**: Do not write Swift code until the Architecture Atlas and Canonical Docs are fully reviewed and approved by the user.
- **Phase 1A Storage**: Must use local on-device store only.
- **Storage Location**: Prefer isolated local files under `LocalCache/EvidenceThreads/` if supported by the atlas. Do NOT use the base `Documents/` directory for thread storage.
- **NO iCloud Sync**: Sync is strictly forbidden in Phase 1.
- **NO StoreKit Integration**: Billing/Entitlement changes are forbidden in Phase 1.
- **NO App Intents**: Siri shortcut integration is forbidden in Phase 1.
- **NO PCC/Routing Changes**: Modifications to the `FoundationModelRoutePolicy` or privacy boundaries are forbidden in Phase 1.
- **NO Destructive Migrations**: Do not drop or wipe existing SQLite tables or Vectura indices to support Evidence Threads.
- **NO Streaming-Token Disk Writes**: Do not write individual LLM tokens to disk during generation to avoid I/O thrashing.
- **ChatMessage Immutability**: Do not modify the existing `ChatMessage` model unless strictly proven necessary and approved by the user.
