# Phase 1B Blast Radius Audit

## 1. Executive Summary
Phase 1A successfully established an isolated local JSON store for `EvidenceThread`. This audit evaluates candidates for Phase 1B to advance the feature while strictly preserving isolation from `ChatMessage`, CloudKit, and existing chat features. The recommended path is **Diagnostics-Only Exposure**.

## 2. Candidate Phase 1B Options
1. **Tests Hardening Only**: Enhance `EvidenceThreadStoreTests` with concurrency and edge-case validation.
2. **Minimal Internal API Integration**: Create an `EvidenceThreadRepository` to manage the store and inject it into the app's dependency container.
3. **Diagnostics-Only Exposure**: Build a hidden debug service or standalone SwiftUI debug view that reads/writes to the store to prove it works in the live app, without touching production UI.
4. **UI Prototype**: Integrate `EvidenceThread` into a new, parallel UI.
5. **Sync Design Only**: Plan the iCloud integration without coding it.

## 3. Risk Matrix
| Candidate | Risk Level | Blast Radius | Notes |
|-----------|------------|--------------|-------|
| Tests Hardening | Low | `OpenIntelligenceTests` only | Safest, but doesn't integrate the feature into the app. |
| Minimal API Integration | Medium | Dependency Injection, Domain Layer | Touches app launch/DI setup. Potential for accidental coupling. |
| Diagnostics-Only Exposure | Low-Medium | Isolated Debug UI/Service | Proves the store works in the live app environment without threatening production user workflows. |
| UI Prototype | High | New SwiftUI views, Navigation | High risk of accidental `ChatMessage` or routing entanglement. |
| Sync Design Only | Low | Documentation only | Does not advance the codebase. |

## 4. Recommended Path
**Diagnostics-Only Exposure** (coupled with Tests Hardening).
This proves the `EvidenceThreadStore` functions correctly inside the running macOS/iOS app container (validating file paths and atomic writes dynamically) without wiring it into the production AI/Chat pathways. 

## 5. Allowed Files
- `OpenIntelligence/Core/Models/EvidenceThread.swift`
- `OpenIntelligence/Services/Storage/EvidenceThreadStore.swift`
- `OpenIntelligenceTests/Services/Storage/EvidenceThreadStoreTests.swift`
- `OpenIntelligence/Features/Debug/EvidenceThreadDebugView.swift` [NEW]
- `OpenIntelligence/Features/Debug/EvidenceThreadDebugService.swift` [NEW]

## 6. Prohibited Files
- `OpenIntelligence/Core/Models/ChatMessage.swift`
- `OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift`
- `OpenIntelligence/Services/Storage/SQLiteFullTextService.swift`
- `OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift`
- `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelRoutePolicy.swift`
- `OpenIntelligence/Features/Chat/**`
- `OpenIntelligence/Services/Billing/EntitlementStore.swift`
- `OpenIntelligence/Features/**/AppIntents*`
- `.xcodeproj/project.pbxproj` (Unless strictly adding the new debug files)
- `*.storekit`, `*.entitlements`

## 7. Required Tests
- Concurrency tests for `EvidenceThreadStore`.
- Unit tests verifying the `EvidenceThreadDebugService` correctly fetches and formats threads.

## 8. Required Docs Updates
- `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md`: Register the new Debug service/view.

## 9. Required Notion Updates
- Create a new row or update Phase 1B status to `Planned` and `Gate State: READY`.

## 10. Exact Implementation Prompt Stub for Phase 1B
```markdown
PROCEED: IMPLEMENT PHASE 1B

Mission: Implement Phase 1B (Diagnostics-Only Exposure) for Evidence Threads.
Constraints:
- You may only create `EvidenceThreadDebugView.swift` and `EvidenceThreadDebugService.swift`.
- Do not modify or import `ChatMessage`, `WorkspaceSyncService`, or any production Chat UI components.
- Adhere strictly to the Allowed/Prohibited file lists in `Docs/AuditArtifacts/Planning/phase_1b_blast_radius_audit.md`.
```

## 11. Evidence Level and Confidence
- **Recommended Path selection:** Logic/Inference (0.90 confidence)
- **Blast Radius assessment:** Code Analysis (0.95 confidence)
