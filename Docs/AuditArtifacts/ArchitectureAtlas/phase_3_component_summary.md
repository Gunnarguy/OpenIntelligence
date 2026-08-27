# OpenIntelligence Component Atlas Summary (Phase 3)

## Task Information
- **Task Name**: OpenIntelligence Repository Cartographer and Architecture Governance Setup (Phase 3)

## Repository State
- **Current Branch**: `main`
- **Latest Commit Hash**: `bf3a931a7b68552b20f384f0f19bf08fc33138e5`
- **Latest Commit Message**: `chore: Bump iOS version to 4.4 and macOS version to 1.5, preserving 4.3.1 changelog`
- **Working Tree Status**: Dirty

### Exact `git status --porcelain` Output
```text
 M Docs/ARCHITECTURE.md
 M Docs/AppleIntelligenceTransitionPlan.md
 M Docs/BILLING_AND_LIMITS.md
 M Docs/INGESTION_PIPELINE.md
 M Docs/PRIVACY_AND_ROUTING.md
 M Docs/RETRIEVAL_PIPELINE.md
 M README.md
 M WHATS_NEW.md
?? Docs/AuditArtifacts/
?? Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md
?? Docs/DOCUMENTATION_CONSISTENCY_AUDIT.md
?? Docs/FULL_REPO_EVIDENCE_THREADS_ARCHITECTURE_AUDIT.md
?? Docs/FULL_REPO_EVIDENCE_THREADS_AUDIT_VERIFICATION.md
?? Docs/FULL_REPO_LINE_BY_LINE_AUDIT.md
?? Docs/PRODUCT_POSITIONING_AND_EVIDENCE_THREADS_AUDIT.md
?? Docs/PRODUCT_POSITIONING_AND_EVIDENCE_THREADS_AUDIT_V2.md
```

---

## Subsystems Mapped

A total of **270** components (comprising 264 source files and 6 test files) have been grouped across **29 code subsystems** and **1 non-code subsystem**.

### Subsystem Component Distribution
1.  **App Intents/Siri/Shortcuts**: 9 components
2.  **Apple Foundation Models**: 8 components
3.  **OCR/extraction**: 13 components
4.  **PCC routing/consent**: 3 components
5.  **SQLite/FTS storage**: 1 component
6.  **StoreKit**: 8 components
7.  **app lifecycle**: 6 components
8.  **background tasks**: 2 components
9.  **billing/entitlements**: 4 components
10. **chat UI**: 19 components
11. **chat persistence**: 3 components
12. **citations/source rendering**: 20 components
13. **context packing**: 1 component
14. **diagnostics/telemetry**: 27 components
15. **document import**: 11 components
16. **embeddings**: 13 components
17. **export/reporting**: 1 component
18. **generation**: 7 components
19. **iCloud/workspace sync**: 13 components
20. **ingestion queue**: 10 components
21. **library/container management**: 15 components
22. **onboarding**: 5 components
23. **reranking/fusion**: 5 components
24. **retrieval**: 38 components
25. **semantic chunking**: 4 components
26. **settings**: 13 components
27. **tests**: 6 components
28. **vector storage**: 3 components
29. **verification gates**: 3 components
30. **docs/audits**: 0 components (Abstract, non-code subsystem mapped to 84 markdown documentation audit files)

---

## High-Risk Subsystems Analysis

Five subsystems carry a **High** risk classification due to external integration vectors, App Sandbox boundary crossings, or reliance on private system APIs:

| Subsystem | Risk Level | Primary Drivers | Key Components |
| :--- | :--- | :--- | :--- |
| **PCC routing/consent** | **HIGH** | Strict local-first privacy defaults. Background voice intents must fail-safe if iCloud/PCC consent is not determined yet. | `CloudConsentPromptView`, `FoundationModelRoute`, `CloudTransmission` |
| **Apple Foundation Models** | **HIGH** | Interaction with on-device Apple FM models using private system frameworks; risk of behavioral changes across iOS/macOS version boundaries. | `FoundationModelSessionFactory`, `FoundationModelPromptCompiler`, `AppleFoundationLLMService` |
| **iCloud/workspace sync** | **HIGH** | Data consistency risk. Coordinates document/workspace metadata sync via iCloud Drive Ubiquity; conflict resolution edge-cases. | `WorkspaceSyncService`, `SyncResolutionStrategy` |
| **StoreKit / Billing** | **HIGH** | Hard payload capability gates. Unsynchronized local subscription validations or sandbox IAP receipt verification lags. | `StoreKitConfiguration.storekit`, `EntitlementStore`, `PlanUpgradeSheet` |
| **App Intents/Siri/Shortcuts**| **HIGH** | Core system integration boundary. Hard OS limit of 10 shortcuts registered via `AppShortcutsProvider`. Currently uses 9 shortcuts, leaving only 1 available slot. | `RAGAppIntents`, `ScreenAwarenessIntents`, `VisualIntelligenceIntents` |

---

## Undocumented & Underdocumented Subsystems
- **docs/audits**: This subsystem contains no `.swift` source code files; it is fully represented by the 84 Markdown and CSV documentation assets in the repository.
- **SQLite/FTS storage**: Contains only 1 Swift component (`SQLiteFullTextService.swift` / `FullTextStorageService.swift`), yet handles the entirety of the relational metadata indexing. The actual FTS5 query tokenizers are sparsely documented and lack integration unit tests.
- **context packing**: Contains only 1 Swift component (`ContextPackingService.swift`), which calculates evidence compression. Token budget calculations are based on heuristic string lengths and do not perfectly align with CoreML/AppleFM tokenizer profiles.

---

## Uncertain Mappings
- **Infrastructure Extensions**: Files like `KeychainStorage.swift` and `LaunchArguments.swift` are classified under `settings` and `app lifecycle` respectively, but are extensively imported or read from by components in `billing/entitlements` and `diagnostics/telemetry`.
- **Reranking / Fusion**: Standard hybrid search retrieval (`BM25` keyword + vector semantic) overlaps with re-ranking logic. Search fusion (RRF) is handled in `HybridSearchService` (categorized under `reranking/fusion`), while the actual model loading of `ReRankerModel.mlpackage` is done inside `RAGEngine.swift` (categorized under `retrieval` / `reranking/fusion`).

---

## Governance & Safety Check
- **Forbidden files modified**: **NO**
- **App source code files modified**: **NO**
- **Test files modified**: **NO**
- **Xcode configuration/StoreKit files modified**: **NO**

All Phase 3 outputs have been written strictly inside the allowed directory `Docs/AuditArtifacts/ArchitectureAtlas/`.
- `component_inventory.csv` -> [component_inventory.csv](component_inventory.csv)
- `subsystem_map.md` -> [subsystem_map.md](subsystem_map.md)
- `phase_3_component_summary.md` -> [phase_3_component_summary.md](phase_3_component_summary.md)

## Phase 3 Delta Repair Updates
All components mapped in Phase 3 have been cross-verified against the recovered Phase 2 entity inventories. Evidence level and confidence metrics were appended to ensure compliance with the Superseding Evidence Protocol.
