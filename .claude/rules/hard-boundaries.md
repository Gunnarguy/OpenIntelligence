---
paths:
  - "OpenIntelligence.xcodeproj/**"
  - "**/*.storekit"
  - "**/*.entitlements"
  - "Info.plist"
  - "Package.swift"
  - "Package.resolved"
  - "OpenIntelligence/Core/Models/ChatMessage.swift"
  - "OpenIntelligence/Core/Support/EngineSDKCompatibility.swift"
  - "OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift"
  - "OpenIntelligence/Services/Infrastructure/Configuration/QuotaPolicy.swift"
  - "OpenIntelligence/Services/Storage/SQLiteFullTextService.swift"
  - "OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift"
  - "OpenIntelligence/Services/Billing/EntitlementStore.swift"
  - "OpenIntelligence/Services/Agentic/RAGAppIntents.swift"
  - "OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelRoutePolicy.swift"
  - "OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelSessionFactory.swift"
---

# Stop. This is a hard-boundary file.

You are reading a file on the forbidden-edit list in `Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md`.
Reading is fine. Editing is not, unless the user named this specific file in their approval.

If a fix appears to require editing it: stop, describe the change you would make and why the
boundary is in the way, and ask. Do not make the edit and mention it afterwards.

"It is only a log line", "it is one character", and "it is obviously correct" are not exemptions.
Each of these files guards something a compile-clean change can still break silently:

| File | What breaks quietly |
|---|---|
| `project.pbxproj` | Synchronized file groups and target membership; iCloud already corrupts this tree |
| `*.storekit`, `EntitlementStore.swift` | Purchase and entitlement state for people who already paid |
| `*.entitlements`, `Info.plist` | Capability gating, including Private Cloud Compute access |
| `Package.swift`, `Package.resolved` | Pinned dependency versions |
| `ChatMessage.swift` | Persisted message shape, so conversation history |
| `WorkspaceSyncService.swift` | Cross-device iCloud library reconciliation |
| `SQLiteFullTextService.swift` schema | The FTS5 index, which requires a full reindex to change |
| `BNNSVectorDatabase.swift` format | On-disk vector format, same problem |
| `QuotaPolicy.swift` tier limits | What each paid tier is allowed to do |
| `RAGAppIntents.swift` shortcut count | 9 of 10 Siri shortcut slots are used; a tenth is a one-way door |
| `FoundationModelRoutePolicy.swift`, `FoundationModelSessionFactory.swift` | Where a query executes, which is the app's central privacy promise |
| `EngineSDKCompatibility.swift` | SDK availability gating across OS versions |
