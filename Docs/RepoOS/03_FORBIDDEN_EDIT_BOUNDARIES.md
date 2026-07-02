# RepoOS 03 — Forbidden Edit Boundaries

Explicit list of sensitive files. "Forbidden" means: do not edit without the user explicitly authorizing that file by name, and never during audit/governance phases (`Docs/AgentPlaybooks/00_SUPERSEDING_EVIDENCE_PROTOCOL.md`).

## Tier 1 — Never edit without named user authorization

| File | Why touching it is dangerous |
|---|---|
| `OpenIntelligence.xcodeproj/project.pbxproj` | Hand-edits corrupt target membership and break every build; prohibited by `Docs/AgentPlaybooks/07_TASK_ROUTER_AND_CHANGE_CONTROL.md`. |
| `OpenIntelligence/Resources/StoreKit/StoreKitConfiguration.storekit` | Defines purchasable products/tiers. Drift from App Store Connect breaks purchases and quota resolution (`Docs/AuditArtifacts/ArchitectureAtlas/billing_touchpoints.csv`). |
| `OpenIntelligence/OpenIntelligence.entitlements` | The PCC entitlement is deliberately omitted pending developer-account approval; runtime fallback depends on this exact state. Re-adding it breaks Xcode Cloud archive signing (canonical §3). Other entitlements gate iCloud ubiquity containers. |
| `Info.plist` (capability/background keys) | Background task identifiers, Live Activity support, and ubiquity container config; silent runtime failures if wrong. |
| `Package.swift` / `Package.resolved` (dependency changes) | Pins the Rust-backed `swift-tokenizers` package that provides exact byte-level citation offsets (canonical §3); version drift silently corrupts citation alignment. |

## Tier 2 — Behavior-critical Swift (edit only with approval + plan + tests)

| File | Why |
|---|---|
| `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelRoutePolicy.swift` | PCC consent routing. Known deadlock class: background/App Intents executions blocking on `CloudConsentPromptView` (Atlas §10; risk R06). |
| `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelSessionFactory.swift` | Instantiating `PrivateCloudComputeLanguageModel` without the runtime entitlement check (`EntitlementChecker` in `EngineSDKCompatibility.swift`) causes a **fatal process crash** (Atlas §10). |
| `OpenIntelligence/Core/Support/EngineSDKCompatibility.swift` | Hosts `EntitlementChecker` and SDK availability shims; the crash-prevention layer itself. |
| `OpenIntelligence/UI/Components/CloudConsentPromptView.swift` | Consent gate for cloud transmission; bypassing it violates the privacy model and can deadlock (canonical §8). |
| `OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift` | iCloud Drive ubiquity sync + deletion sweeps. The 15-minute mtime sweep-guard protects freshly imported files from deletion (canonical §3). Errors here = user data loss across devices. Last-write-wins conflict policy is fragile (subsystem_map: HIGH). |
| `OpenIntelligence/Core/Models/ChatMessage.swift` | Persisted as monolithic JSON arrays (canonical §6); any shape change silently breaks/loses existing chat history. Evidence Threads wrap it and require immutability (canonical §11). |
| `OpenIntelligence/Services/Storage/SQLiteFullTextService.swift` | Single shared SQLite file with `container_id` column isolation (canonical §3). Schema changes are destructive migrations; FTS5 tokenizer must match Swift unicode normalization exactly (subsystem_map). |
| `OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift` | Memory-mapped vector store; format changes invalidate every user's index. Known mmap-limit risk R09 (`final_unresolved_risks.csv`). |
| `OpenIntelligence/Services/Embedding/Providers/CoreAISentenceEmbeddingProvider.swift`, `CoreMLSentenceEmbeddingProvider.swift`, `AppleFMEmbeddingProvider.swift` | Production embedding providers (canonical §3). Dimension/pooling changes make stored vectors unsearchable without full re-index; Core AI path relies on iOS 27+ APIs with fallback chain (Atlas §17). |
| `OpenIntelligence/Services/Billing/EntitlementStore.swift` | Entitlements intentionally live in UserDefaults, not Keychain (canonical §9). "Fixing" this strands paying users' entitlement state. |
| `OpenIntelligence/Services/Billing/StoreKitBillingService.swift` | StoreKit transaction handling; subsystem risk HIGH (subsystem_map). |
| `OpenIntelligence/Services/Infrastructure/Configuration/QuotaPolicy.swift` | Monetization tier limits (5 Free / 20 Pro / Unlimited Lifetime, canonical §11); changes are revenue-affecting. |
| `OpenIntelligence/Services/Agentic/RAGAppIntents.swift` | 9 of 10 App Shortcut slots consumed (canonical §10); adding shortcuts past 10 fails silently OS-wide. Intents bypass UI straight into `RAGService` (Atlas §12) — PCC consent deadlock risk R07. |
| `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift` + `RAGService+Streaming.swift` | Central orchestrator; streaming ingestion contract (page batches, incremental FTS5 appends) is OOM-safety-critical (canonical §3). |

## Tier 3 — Process prohibitions (always)
- No destructive git commands (`git reset --hard`, `git clean`, `rm -rf`) — `00_SUPERSEDING_EVIDENCE_PROTOCOL.md`.
- No deleting documentation files; archive/supersede instead (`Docs/DOCUMENTATION_CONSISTENCY_AUDIT.md` workflow).
- No editing canonical docs against code without a new evidence-tagged atlas pass (canonical §16).
- No auto-proceeding from plan to implementation without `PROCEED: IMPLEMENT` (07_TASK_ROUTER).

## How to request an exception
State the exact file, the reason, the blast radius, the verification plan, and wait for the user to name the file in their approval. Absent that, choose a design that avoids the boundary.
