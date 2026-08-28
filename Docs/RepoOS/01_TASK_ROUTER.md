# RepoOS 01 — Task Router

Routes common task types to owning subsystems with read-first docs, edit zones, and verification. Machine-readable version: `Docs/AuditArtifacts/RepoOS/change_impact_matrix.csv`. This router extends (does not replace) `Docs/AgentPlaybooks/07_TASK_ROUTER_AND_CHANGE_CONTROL.md`.

## Universal preflight (every task)
1. Read `AGENTS.md`, `Docs/AgentPlaybooks/00_SUPERSEDING_EVIDENCE_PROTOCOL.md`, `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md`, `Docs/AppleIntelligenceTransitionPlan.md`.
2. Find the owning subsystem below; read its row's read-first docs.
3. Check `Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md`.
4. Produce an implementation plan, then **STOP and wait for `PROCEED: IMPLEMENT`** before any source edit (07_TASK_ROUTER rule; no auto-proceed).
5. Run the workspace preflight and use its artifact-derived active release for the `CHANGELOG.md` section it names in `documentation_targets.changelog_section`, the matching `Docs/RELEASE_NOTES.md` section, and Notion `Target Release` whenever the routed task is a durable implementation. That section is **not always `[Unreleased]`**: a first numbered heading carrying the `unreleased` marker on its own line is the open section, and entries go under it. Read the preflight's `state` field, not just `version`.

## Universal verification commands
- Build: `bash scripts/build_simulator_smoke.sh` (scheme `OpenIntelligence`, default destination `platform=iOS Simulator,name=iPhone 17 Pro`)
- Full tests: `xcodebuild test -scheme OpenIntelligence -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO`
- Clean-state check: `git status --porcelain` (must show only intended files)
- Secret scan (before commit of new files): `python3 scripts/secret_scan.py`

## Routes

### 1. Retrieval / ranking change
- **Subsystem:** retrieval, reranking/fusion, context packing (`Docs/AuditArtifacts/ArchitectureAtlas/subsystem_map.md`)
- **Read first:** `Docs/RETRIEVAL_PIPELINE.md`, Atlas §7 flow 4, `Docs/AuditArtifacts/ArchitectureAtlas/component_inventory.csv` rows for retrieval
- **Allowed:** `OpenIntelligence/Services/RAG/Retrieval/**`, `OpenIntelligence/Services/Query/**`, `OpenIntelligence/Services/RAG/Tuning/**`, matching tests
- **Forbidden:** `SQLiteFullTextService.swift` schema, `BNNSVectorDatabase.swift`, anything in 03_FORBIDDEN_EDIT_BOUNDARIES
- **Verify:** `xcodebuild test ... -only-testing:OpenIntelligenceTests/HybridSearchServiceTests -only-testing:OpenIntelligenceTests/ContextPackingServiceTests` + build smoke
- **Docs to update:** `Docs/RETRIEVAL_PIPELINE.md`, `CHANGELOG.md`

### 2. Embedding provider change
- **Subsystem:** embeddings
- **Read first:** Atlas §17 (Core AI boundary), canonical §3 (Core AI in production; Rust tokenizer)
- **Allowed:** `OpenIntelligence/Services/Embedding/**` (provider selection logic only)
- **Forbidden:** Deleting/renaming existing provider files; vector storage; changing embedding dimensionality without re-index plan (breaks `BNNSVectorDatabase` mmap data)
- **Verify:** build smoke + full test suite; manual check of AI Subsystem Diagnostics card noted in Atlas §10
- **Approval:** REQUIRED — provider changes alter production index compatibility

### 3. Core AI / iOS 27 / Apple Foundation Models change
- **Subsystem:** Apple Foundation Models (HIGH risk)
- **Read first:** Atlas §10 + §17, canonical §3 and §8, `Docs/PRIVACY_AND_ROUTING.md`
- **Allowed:** `OpenIntelligence/Services/AIPlatform/**` only with explicit user approval
- **Forbidden:** `FoundationModelRoutePolicy.swift`, `FoundationModelSessionFactory.swift`, `EngineSDKCompatibility.swift` (EntitlementChecker), `OpenIntelligence/OpenIntelligence.entitlements` — PCC entitlement handling prevents fatal crashes
- **Verify:** build smoke; confirm no `PrivateCloudComputeLanguageModel` instantiation path bypasses `EntitlementChecker` (`grep -rn "PrivateCloudComputeLanguageModel" OpenIntelligence/`)
- **Approval:** ALWAYS

### 4. Evidence Threads change
- **Subsystem:** chat persistence / Evidence Threads (integrated per canonical §11–12)
- **Read first:** canonical §11, Atlas §15, `Docs/AgentPlaybooks/05_EVIDENCE_THREADS_IMPLEMENTATION_GUARDRAILS.md`, `Docs/AuditArtifacts/ArchitectureAtlas/evidence_threads_design_decision.md`
- **Allowed:** `OpenIntelligence/Core/Models/EvidenceThread.swift`, `OpenIntelligence/Services/Storage/EvidenceThreadStore.swift`, `OpenIntelligence/Features/Chat/Conversation/ThreadSidebarView.swift`, `OpenIntelligence/Features/Debug/EvidenceThread*`
- **Forbidden:** `ChatMessage.swift` (must remain untouched — canonical §11), `WorkspaceSyncService.swift`, `QuotaPolicy.swift` tier limits
- **Verify:** build smoke; serialize/deserialize round-trip check; confirm thread saves respect quota gating
- **Approval:** REQUIRED (was governance-gated; storage layout is sync-coupled)

### 5. iCloud / workspace sync change
- **Subsystem:** iCloud/workspace sync (HIGH risk)
- **Read first:** canonical §7, Atlas §9, `Docs/AuditArtifacts/ArchitectureAtlas/sync_touchpoints.csv`
- **Allowed:** nothing without explicit approval
- **Forbidden:** `WorkspaceSyncService.swift` deletion-sweep and mtime-guard logic (data-loss protection, canonical §3); introducing CloudKit (canonical §4 false claim)
- **Verify:** `grep -rn "CKDatabase\|CKContainer" OpenIntelligence/ --include=*.swift` must stay empty; build smoke; full tests
- **Approval:** ALWAYS

### 6. StoreKit / billing change
- **Subsystem:** StoreKit, billing/entitlements (HIGH risk)
- **Read first:** `Docs/BILLING_AND_LIMITS.md`, canonical §9, `Docs/AuditArtifacts/ArchitectureAtlas/billing_touchpoints.csv`
- **Allowed:** UI-level billing views (`OpenIntelligence/Features/Billing/**`) with approval
- **Forbidden:** `StoreKitConfiguration.storekit`, `StoreKitBillingService.swift`, `EntitlementStore.swift` (UserDefaults-backed — do not "fix" to Keychain), `QuotaPolicy.swift`
- **Verify:** build with `OpenIntelligence-StoreKitTesting` scheme; full tests
- **Approval:** ALWAYS

### 7. App Intents / Siri / Shortcuts change
- **Subsystem:** App Intents (HIGH risk)
- **Read first:** canonical §10 (9/10 slots used), Atlas §12, `app_intents_touchpoints.csv`
- **Allowed:** intent phrase/copy tweaks with approval
- **Forbidden:** Adding ≥2 App Shortcuts (silent OS registration failure at 10); wiring intents to PCC-consent paths (deadlock risk R06/R07 in `final_unresolved_risks.csv`)
- **Verify:** build smoke; count `AppShortcut` registrations in `RAGAppIntents.swift`
- **Approval:** ALWAYS

### 8. Ingestion / OCR / chunking change
- **Subsystem:** document import, ingestion queue, OCR/extraction, semantic chunking
- **Read first:** `Docs/INGESTION_PIPELINE.md`, Atlas §16 ingestion flow + §18 (streaming)
- **Allowed:** `OpenIntelligence/Services/Document/**`, matching tests
- **Forbidden:** checkpoint location (`localCacheDir()/IngestionCheckpoints/` must stay local-only, canonical §6); FTS5 append/streaming contract in `RAGService+Streaming.swift`
- **Verify:** `-only-testing:OpenIntelligenceTests/.../DocumentProcessorTests -only-testing:.../SemanticChunkerTests`; build smoke
- **Docs to update:** `Docs/INGESTION_PIPELINE.md`, `CHANGELOG.md`

### 9. Chat UI / citations change
- **Subsystem:** chat UI, citations/source rendering (LOW risk)
- **Read first:** Atlas §5–6
- **Allowed:** `OpenIntelligence/Features/Chat/**`, `OpenIntelligence/UI/**`
- **Forbidden:** `ChatMessage.swift` model shape (breaks persisted JSON histories)
- **Verify:** build smoke; full tests
- **Docs to update:** `WHATS_NEW.md`/`Docs/USER_CHANGELOG.md` if user-visible

### 10. Documentation governance change
- **Subsystem:** docs/audits
- **Read first:** `Docs/AgentPlaybooks/02_DOCUMENTATION_RECONCILIATION.md`, `03_CHANGE_IMPACT_DOC_UPDATE.md`, `Docs/DOCUMENTATION_CONSISTENCY_AUDIT.md`
- **Allowed:** `Docs/**`, `README.md`, `PRIVACY.md`, `CHANGELOG.md` — additive edits and reconciliation; never delete docs
- **Forbidden:** editing canonical docs to contradict code without a new evidence-tagged atlas pass (canonical §16)
- **Verify:** `git status --porcelain` limited to docs; all new claims carry evidence tags

### 11. Release readiness check
- **Subsystem:** verification gates / release
- **Read first:** `Docs/RepoOS/04_RELEASE_READINESS_DASHBOARD.md`
- **Allowed:** read-only + report artifacts under `Docs/AuditArtifacts/**`
- **Verify:** every dashboard row PASS/FAIL with evidence

### 12. App Store / product copy update
- **Subsystem:** release / marketing surfaces
- **Read first:** `Docs/PRIVACY_AND_ROUTING.md`, `Docs/LIMITATIONS.md`, canonical §3 (only make claims the code supports — e.g., iCloud Drive sync, NOT CloudKit; local PCC fallback, NOT guaranteed enclave execution)
- **Allowed:** `fastlane/**` metadata, `WHATS_NEW.md`, `Docs/USER_CHANGELOG.md`, `PRIVACY.md`
- **Forbidden:** claims contradicting canonical §4 unsafe claims
- **Verify:** cross-check each product claim against canonical §3; approval before publishing

### 13. Build / project config change
- **Forbidden by default:** `OpenIntelligence.xcodeproj/project.pbxproj`, `Package.swift` targets, `Info.plist` capabilities, `ci_scripts/**`
- **Approval:** ALWAYS, with explicit user authorization naming the file

### 14. App icon / asset catalog appearance change
- **Subsystem:** user-visible app icon assets
- **Read first:** `Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md`, `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md`
- **Allowed:** `OpenIntelligence/Resources/Assets/Assets.xcassets/AppIcon.appiconset/**`
- **Forbidden:** `OpenIntelligence.xcodeproj/project.pbxproj`, entitlements, capability keys, and unrelated source/config files
- **Verify:** validate `Contents.json`; compile the asset catalog with `xcrun actool`; run `bash scripts/build_simulator_smoke.sh`
- **Docs to update:** `WHATS_NEW.md`, `Docs/USER_CHANGELOG.md`, `CHANGELOG.md`
- **Approval:** plan approval before edit

### 15. RepoOS / Codex workspace automation
- **Subsystem:** developer governance and agent workflow automation
- **Read first:** `AGENTS.md`, `.codex/skills/route-openintelligence-work/SKILL.md`, `.agents/rules/00-repoos-routing.md`, `.agents/rules/01-docs-and-notion-sync.md`
- **Allowed:** `.codex/skills/**`, `.agents/**`, `.claude/**`, `CLAUDE.md`, `Docs/ai/**`, `Docs/RepoOS/**`, `Docs/AuditArtifacts/RepoOS/**`, `AGENTS.md`, the enforcement-layer scripts (`scripts/required_docs.sh`, `scripts/enforce_docs_hook.sh`, and their tests), and documentation required by rule 14
- **Forbidden:** all `OpenIntelligence/**` app source, Xcode project configuration, StoreKit, entitlements, package dependency pins, and every Tier 2 boundary in `03_FORBIDDEN_EDIT_BOUNDARIES.md`
- **Verify:** skill `quick_validate.py`; router unit tests executed directly with `python3 .codex/skills/route-openintelligence-work/scripts/test_repoos_router.py`; `bash scripts/test_enforce_docs_hook.sh`; `bash scripts/test_stop_handoff.sh`; representative preflight runs; CSV parse; secret scan on new files; build smoke to prove no app regression
- **Docs to update:** Command Center, Task Router, change-impact matrix, `CHANGELOG.md`, and the full AGENTS.md rule 14 set for a durable workflow feature
- **Approval:** required before edits; Notion roadmap synchronization required for durable workspace automation
