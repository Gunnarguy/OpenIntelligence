# OpenIntelligence Evidence Threads Phase 1A — Local Store Only

Implement Evidence Threads securely as a local-only, isolated feature (Design B) to avoid disrupting the legacy monolithic chat history, PCC routing, and iCloud Drive sync logic.

## Strict Governance Constraints

> [!CAUTION]
> This phase will write directly to `LocalCache/EvidenceThreads/<containerId>/` as isolated JSON files. We must strictly ensure we do not touch `ChatMessage.swift`, `SQLiteFullTextService.swift`, `WorkspaceSyncService.swift`, `FoundationModelRoutePolicy.swift`, or `EntitlementStore.swift`.

## Implementation Scope

### Core Models

#### [NEW] `OpenIntelligence/Core/Models/EvidenceThread.swift`
- Create `EvidenceThread` struct (`Codable`, `Identifiable`).
- Create `EvidenceThreadMessage` struct (`Codable`, `Identifiable`) to separate the data schema entirely from `ChatMessage`.

### Storage Services

#### [NEW] `OpenIntelligence/Services/Storage/EvidenceThreadStore.swift`
- Create an isolated class for saving/loading `EvidenceThread` instances.
- Define logic to write to `Application Support/LocalCache/EvidenceThreads/<containerId>/<threadId>.json`.
- Expose methods: `saveThread(_:)`, `getThread(id:)`, `listThreads(containerId:)`, `deleteThread(id:)`.

## Verification Plan

### Automated Tests
- Write automated tests to ensure `EvidenceThread` correctly serializes and deserializes from isolated local JSON without data loss.
- Verify that `EvidenceThreadStore.saveThread` successfully writes to the `LocalCache/EvidenceThreads/` directory.

### Manual Verification
- Verify that saving an `EvidenceThread` explicitly does not trigger `NSUbiquityIdentityDidChange` logic or invoke `WorkspaceSyncService` (ensure logs show no sync boundary crossings).
- Verify that PCC routing rules continue to run properly and are unaffected.
