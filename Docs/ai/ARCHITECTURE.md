# Architecture map

A routing map, not a description. `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md` is the deep
reference and this file exists to get you to the right part of it, and to the right source file,
without reading the whole set.

`[evidence_level: code_verified, confidence: high, evidence_source: directory listing of
OpenIntelligence/Services, file existence checks 2026-08-07; claim-by-claim re-verification against
source 2026-09-01 — reranker model, trace stages, referenced documents and target membership;
re-verified 2026-09-24 at d5cc916 — routing decision, fusion and rerank ownership, reranker
fallback, Evidence Threads row, and the owner-vocabulary section]`

## Targets, and why it matters

Two build targets share the tree:

- **`OpenIntelligence`**, the app.
- **`OpenIntelligenceEngine`**, a SwiftPM target whose synchronized root groups include
  `Services/RAG` but not `Services/Evaluation`.

That is not trivia. A type referenced by a file in the Engine target must live in a folder the
Engine target also builds, which is why `RetrievalTraceCollector` sits in
`Services/RAG/Retrieval/` rather than beside the metrics that score it. Check target membership
before deciding where a new file goes.

`OpenIntelligenceLiveActivities` is a separate widget extension.

## Where each area lives

| Area | Source | Owning document |
|---|---|---|
| Ingestion, chunking, OCR | `OpenIntelligence/Services/Document/` | `Docs/INGESTION_PIPELINE.md` |
| Embedding and providers | `OpenIntelligence/Services/Embedding/` | Atlas §17 |
| Vector storage | `OpenIntelligence/Services/VectorStore/` | Atlas §9 |
| Keyword index (SQLite FTS5) | `OpenIntelligence/Services/Storage/` | Atlas §9 |
| Hybrid retrieval, fusion, rerank | `OpenIntelligence/Services/RAG/Retrieval/` (`HybridSearchService`: vector + lexical search, boosts, top-K). Fusion is `RAGEngine.reciprocalRankFusion` and reranking is `RAGEngine.rerank`, both in `OpenIntelligence/Services/RAG/Orchestration/RAGEngine.swift`; `RAGService` calls `rerank` after `HybridSearchService` returns. `[evidence_level: code_verified, confidence: exact, evidence_source: HybridSearchService.swift:294,332-334; RAGEngine.swift:294,963; RAGService.swift:10986]` | `Docs/RETRIEVAL_PIPELINE.md` |
| Query understanding, rewriting | `OpenIntelligence/Services/Query/` | `Docs/RETRIEVAL_PIPELINE.md` |
| Retrieval tuning knobs | `OpenIntelligence/Services/RAG/Tuning/` | `Docs/RETRIEVAL_PIPELINE.md` |
| RAG orchestration | `OpenIntelligence/Services/RAG/Orchestration/` | Atlas service map |
| Model routing, on-device vs PCC | Decision: `ModelExecutionPlanner.makePlan` in `OpenIntelligence/Services/RAG/Orchestration/ModelExecutionPlanner.swift`, with constraints built by `RAGService.makePostRetrievalModelPlan` and the consent gate in `RAGService.ensureCloudConsentIfNeeded`. `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/` enforces an attached plan and decides the route itself when none is attached: `FoundationModelRoutePolicy.determineRoute` follows the plan at :28-46, otherwise applies the manual preference and then context size against the on-device window and PCC availability (its "planless branch"). `FoundationModelSessionFactory` builds the session; both are called from `LLMService`. `[evidence_level: code_verified, confidence: exact, evidence_source: ModelExecutionPlanner.swift:24; RAGService.swift:3666,16195,16311; FoundationModelRoutePolicy.swift:23-117; LLMService.swift:609,697]` | `Docs/PRIVACY_AND_ROUTING.md`, Atlas §10 |
| LLM execution | `OpenIntelligence/Services/LLM/` | `Docs/PRIVACY_AND_ROUTING.md` |
| Agentic tools, App Intents, Siri | `OpenIntelligence/Services/Agentic/` | Atlas §12 |
| Evidence Threads | `OpenIntelligence/Core/Models/EvidenceThread.swift`, `OpenIntelligence/Services/Storage/EvidenceThreadStore.swift`; owned by `RAGService` (`threadStore`, `persistChatHistory`, `createNewThread`); UI in `OpenIntelligence/Features/Chat/Conversation/ThreadSidebarView.swift` and `ChatScreen.swift`; per-tier cap `QuotaPolicy.evidenceThreadLimit`; iCloud sync `WorkspaceSyncService.synchronizeEvidenceThreads`; tests `OpenIntelligenceTests/Services/Storage/EvidenceThreadStoreTests.swift`. `[evidence_level: code_verified, confidence: high, evidence_source: RAGService.swift:354,688,878-880; ThreadSidebarView.swift:28; ChatScreen.swift:620,2077; QuotaPolicy.swift:59; WorkspaceSyncService.swift:2331,2732]` Unknown: the store writes `<AppSupport>/EvidenceThreads/<container>/` (EvidenceThreadStore.swift:60) but sync reads `EvidenceThreads/` under `localRoot` = `<AppSupport>/OpenIntelligence` (WorkspaceSyncService.swift:2739, OpenIntelligenceRuntimePaths.swift:105-111), so threads may not reach other devices. Verify: on device, create a thread in an iCloud library and check that it appears on a second device. | Atlas §15, canonical §11 |
| iCloud workspace sync | `OpenIntelligence/Services/Infrastructure/Storage/` | Atlas |
| Billing, entitlements, quotas | `OpenIntelligence/Services/Billing/`, `Services/Infrastructure/Configuration/` | `Docs/BILLING_AND_LIMITS.md` |
| Evaluation harness | `OpenIntelligence/Services/Evaluation/` | `Docs/EVALS.md` |
| UI | `OpenIntelligence/Features/`, `OpenIntelligence/UI/` | `WHATS_NEW.md`, `Docs/USER_CHANGELOG.md` |

## If the owner says...

Product vocabulary, mapped to where it lives. Paths are under `OpenIntelligence/` unless shown
otherwise. `[evidence_level: code_verified, confidence: high, evidence_source: each file:line
below, read or grepped at d5cc916 on 2026-09-24]`

| Owner says | Entry file(s) | Key symbol(s) |
|---|---|---|
| Standard, Deep Think, Maximum (quality modes) | `Core/Models/RAGQualityMode.swift`; pickers in `Features/Chat/Conversation/ChatScreen.swift` and `Features/Settings/SettingsView.swift`; Deep Think and Maximum run through `Services/Agentic/AgenticOrchestrator.swift` | `RAGQualityMode.standard` / `.deepThink` / `.maximum`, `displayName` (RAGQualityMode.swift:41), `usesAgenticOrchestrator` (:151); `SettingsStore.ragQualityMode`; `QualityModeQuickPicker` (ChatScreen.swift:3868); `RAGService.executeAgenticQuery` (RAGService.swift:8787) → `AgenticOrchestrator` |
| Glossary | `UI/Components/Glossary.swift`, `Features/Settings/GlossaryView.swift` | `Glossary` (Glossary.swift:565), `GlossaryTermID`, `GlossarySection`; `GlossaryView`, opened from `SettingsView.swift:527`, `HowItWorksView` and `OnboardingChecklistView` |
| The HUD, Silicon HUD, X-ray overlay | `Features/Telemetry/Dashboard/MotherboardHUDView.swift`; data from `Services/Infrastructure/Monitoring/HardwareTelemetryState.swift` | `HardwareXRayOverlay` (:296), `SiliconLegend` (:721), `FloatingLegendWindowManager` (:952, UIKit only); toggle `SettingsStore.showSiliconHUD` (SettingsStore.swift:289, Settings toggle at SettingsView.swift:3048); `HardwareTelemetryState`, `HardwareTelemetryReporter` |
| Deleting a library | `Features/Documents/Library/LibraryDeletion.swift`, called from `DocumentLibraryView.swift` and `Features/Documents/Settings/ContainerSettingsSheet.swift` | `LibraryDeletion.delete` → `WorkspaceSyncService.deleteSharedLibrary` for iCloud libraries, `RAGService.removeDocument` per document, `ContainerService.deleteContainer(id:)` (`Services/Infrastructure/Integration/ContainerService.swift:161`). The SDK's `OpenIntelligenceEngine.deleteLibrary` bypasses this path (see the header of `LibraryDeletion.swift`). |
| The PCC consent sheet | `UI/Components/CloudConsentPromptView.swift`, presented by `Features/Chat/Conversation/ChatScreen.swift` | `CloudConsentPromptView`; `.sheet(item: $activeCloudConsent)` fed by `RAGService.pendingCloudConsent` (RAGService.swift:1484); answered through `RAGService.resolveCloudConsent(decision:)`; raised by `RAGService.ensureCloudConsentIfNeeded` (:3666) |
| Evidence Threads | see the Evidence Threads row above | `EvidenceThreadStore`, `RAGService.createNewThread`, `ThreadSidebarView` |
| The model selector | `UI/Components/ModelStatusIndicator.swift`, placed in `ChatScreen.swift:3804`; `Features/Settings/Components/ModelSelectorSheet.swift` | `ModelStatusIndicator`, a picker over `SettingsStore.fmPreference` (`FoundationModelPreference`, `Core/Models/LLMModel.swift:234`). `ModelSelectorSheet` sets `SettingsStore.selectedModel`, but the only place that creates it is its own `#Preview` (ModelSelectorSheet.swift:223) `[evidence_level: grep_verified, confidence: high]` |
| Shortcuts, Siri | `Services/Agentic/RAGAppIntents.swift`, `Services/Agentic/ScreenAwarenessIntents.swift`, `Services/Agentic/Entities/` | `RAGAppShortcutsProvider` (RAGAppIntents.swift:266), 9 `AppShortcut` entries; intents such as `QueryDocumentsIntent`, `SearchLibraryIntent`, `IngestDocumentIntent`. Shortcut count is a hard boundary. |
| Sample documents | `Features/Documents/Library/SampleDocumentManager.swift` | `SampleDocumentManager` (:95), sample bodies written in Swift in `samples`, `importSamples` (:365), `refreshStaleSamples` (:522); started from `DocumentLibraryView.importSampleWorkspace` and `OnboardingChecklistView` |
| What's New, version history | `Features/Onboarding/WhatsNewStore.swift`, `WhatsNewView.swift`; `Features/Settings/VersionHistory.swift`, `VersionHistoryView.swift`; `Resources/VersionHistory.md` | `WhatsNewStore.releases` (:102) and `evaluateOnLaunch`, sheet presented in `App/ContentView.swift`; `VersionHistoryLoader` parses the bundled `VersionHistory.md`, a copy of `Docs/USER_CHANGELOG.md` held in step by `VersionHistoryTests.testBundledHistoryMatchesTheWrittenChangelog`; opened from `SettingsView.swift:564` and `AboutView.swift` |

## Data flow

Import → `Services/Document` extracts and chunks → `Services/Embedding` vectorises →
vectors land in `Services/VectorStore`, text lands in the FTS5 index in `Services/Storage`.

Query → `Services/Query` rewrites and classifies intent → `HybridSearchService` runs dense vector
search and lexical scoring (concurrently on the FTS5 path), fuses them with reciprocal rank fusion
(`RAGEngine.reciprocalRankFusion`), applies boosts, and returns a top-K; it does not rerank →
`RAGService` reranks that set with `RAGEngine.rerank` and packs context →
`RAGService.makePostRetrievalModelPlan` builds the constraints and `ModelExecutionPlanner.makePlan`
decides where to execute on the main answer path, with `RAGService.ensureCloudConsentIfNeeded` as the consent gate (when no plan is attached, `FoundationModelRoutePolicy.determineRoute` in `Services/AIPlatform` decides instead) →
`Services/LLM` generates, using `FoundationModelRoutePolicy` and `FoundationModelSessionFactory` in
`Services/AIPlatform` to turn that plan into a session → the answer carries citations back to the
chunks that produced it. `[evidence_level: code_verified, confidence: high, evidence_source:
HybridSearchService.swift:294,332-334,1032-1033; RAGService.swift:10986,13672,13709;
ModelExecutionPlanner.swift:24; FoundationModelRoutePolicy.swift:49-117; LLMService.swift:609,697]`

The stage names in that pipeline are enumerated in `RetrievalTraceCollector.Stage`: `vector`,
`lexical`, `fusion`, `boosted`, `candidates`, `rerank`, `final`. (`candidates` was missing from this
list until 2026-09-01.)

The reranker is a real Core ML cross-encoder, not a heuristic: `RAGEngine` loads `ReRankerModel`
at launch and `rerankWithCrossEncoder` runs when both the model and its tokenizer are present,
falling back to a heuristic ranker when either is missing: keyword match, term proximity, chunk
position and metadata boosts, less table-of-contents, question-bank and bibliography penalties, with
a warning logged when it runs. `[evidence_level: code_verified, confidence: exact, evidence_source:
RAGEngine.swift:329-415]` Worth stating explicitly, because a search
scoped to `Services/RAG/Retrieval/` finds only heuristic scoring and reads as though no reranker
exists — an error made on 2026-08-29 and carried into a published audit.

## Persistence

Vectors in `BNNSVectorDatabase`, text and metadata in SQLite with an FTS5 index, threads in
`EvidenceThreadStore`, library state reconciled across devices by `WorkspaceSyncService`. All four
are hard-boundary in some respect. A schema, format, or model-dimension change forces existing users
to reindex their entire library, which is why they are gated.

## Security and privacy boundaries

The privacy claim is the product, so these are the invariants worth checking on any change:

- Ingestion, indexing, retrieval, and ranking are local. Nothing is uploaded to make search work.
- Only final answer generation may leave the device, only to Apple Private Cloud Compute, only with
  consent, and only after the user has seen which excerpts would be sent.
- Every use of `PrivateCloudComputeLanguageModel` must be gated behind `EntitlementChecker`.
- The answer's execution badge is read from an execution receipt, not from what was requested.
- There is no account, no server operated by this project, and no third-party AI service in the path.

## External couplings

Four systems the app does not control. Each one's failure mode is different, and the app is expected
to keep working without three of them.

| System | Code boundary | If unavailable |
|---|---|---|
| Apple Foundation Models (on-device and PCC) | `Services/AIPlatform/AppleFoundationModels/` | No answer generation. Retrieval still works, so citations and evidence remain available. The public SDK exposes no tier selector, no server architecture, and no server context window; do not name any of them. |
| CloudKit / iCloud Drive | `Services/Infrastructure/Storage/WorkspaceSyncService.swift` | Library stops reconciling across devices. Local library keeps working. Sync interleaving is a known source of defects and has no test coverage. |
| StoreKit 2 | `Services/Billing/`, `EntitlementStore.swift` | Entitlement state cannot refresh. Must degrade toward the user keeping what they paid for, never toward revoking it. |
| Core ML reranker | `Resources/MLModels/ReRankerModel.mlpackage` | The cross-encoder drops out and `RAGEngine.rerank` ranks candidates with its heuristic fallback instead, logging a warning; scores are not comparable to a cross-encoder run. `[evidence_level: code_verified, confidence: exact, evidence_source: RAGEngine.swift:329-346]` Bound to `cross-encoder/ms-marco-TinyBERT-L2-v2` by exact path in `THIRD_PARTY_NOTICES.md`, which is the provenance of record. |

Nothing else is external. There is no server operated by this project and no third-party AI service
in the path, which is a product guarantee rather than a current state.

## Non-obvious constraints

- **The repository lives in iCloud-synced `~/Documents`.** Synchronized file groups plus iCloud
  conflict copies produce duplicate-symbol errors that point at innocent code. `.git` is a file
  pointing at `.git.nosync` for the same reason.
- **`RAGAppIntents.swift` uses 9 of 10 available Siri shortcut slots.** The tenth is close to a
  one-way door.
- **Retrieval measurement exists but is not yet trustworthy.** The harness does measure it —
  `BenchmarkRuns/LEDGER.md` carries nDCG and MRR@10 figures — so the older claim that it never had
  is withdrawn as of 2026-09-01. The live problem is different and worse: retrieval is
  **nondeterministic**, two runs of one build returning different evidence for one question, so no
  A/B between components is trustworthy, including judgements about what already shipped. That is
  the current work. See `Docs/ai/STATE.md`.
