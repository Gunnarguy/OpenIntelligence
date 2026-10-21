# Architecture map

A routing map, not a description. `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md` is the deep
reference and this file exists to get you to the right part of it, and to the right source file,
without reading the whole set.

`[evidence_level: code_verified, confidence: high, evidence_source: directory listing of
OpenIntelligence/Services, file existence checks 2026-08-07; claim-by-claim re-verification against
source 2026-09-01 — reranker model, trace stages, referenced documents and target membership;
re-verified 2026-09-24 at d5cc916 — routing decision, fusion and rerank ownership, reranker
fallback, Evidence Threads row, and the owner-vocabulary section]`

Corrected 2026-10-20 against the working tree (`b868fc0` plus the 5.7 work in progress), where it
disagreed with the code: the ingestion and vector storage rows, the routing row (the defaults, the rule,
and what the consent sheet shows), the tools row, the modes row (the branch, the precision shortcut, the
configs, and a pointer to `Docs/HOW_IT_WORKS.md` section 07 for the loop), the consent sheet row's lines,
both lines of "Data flow", the vector store under "Persistence", and the consent invariant under "Security
and privacy boundaries".
Line numbers in these notes are that tree's and will move: `RAGService.swift` grew 50 lines during the pass,
and its lines were re-pinned to the file as it stood at 22:27 PDT. Each note carries its own evidence.

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
| Ingestion, chunking, OCR | `OpenIntelligence/Services/Document/` reads, cleans and cuts the text. Corrected 2026-10-20: the queue and the import itself (copy, duplicate check, embedding, both stores, the overview passage) are `RAGService.enqueueDocuments` and `RAGService.addDocument` in `Services/RAG/Orchestration/RAGService.swift`, with `RAGService+Streaming.swift` and `RAGService+TextStreaming.swift` for very large files. `[evidence_level: code_verified, confidence: high, evidence_source: RAGService.swift:6113, 6909, 7258-7297]` | `Docs/INGESTION_PIPELINE.md`, §1 "The order the code runs" |
| Embedding and providers | `OpenIntelligence/Services/Embedding/` | Atlas §17 |
| Vector storage | `OpenIntelligence/Services/VectorStore/`. Corrected 2026-10-20: `BNNSVectorDatabase`, one flat Float32 file per library searched by brute force, not an HNSW index (see Persistence). `[evidence_level: code_verified, confidence: high, evidence_source: BNNSVectorDatabase.swift:26-41, 1104-1201, VectorStoreRouter.swift:154-172, Package.resolved]` | Atlas §9 |
| Keyword index (SQLite FTS5) | `OpenIntelligence/Services/Storage/` | Atlas §9 |
| Hybrid retrieval, fusion, rerank | `OpenIntelligence/Services/RAG/Retrieval/` (`HybridSearchService`: vector + lexical search, boosts, top-K). Fusion is `RAGEngine.reciprocalRankFusion` and reranking is `RAGEngine.rerank`, both in `OpenIntelligence/Services/RAG/Orchestration/RAGEngine.swift`; `RAGService` calls `rerank` after `HybridSearchService` returns. `[evidence_level: code_verified, confidence: exact, evidence_source: HybridSearchService.swift:294,332-334; RAGEngine.swift:294,963; RAGService.swift:10986]` | `Docs/RETRIEVAL_PIPELINE.md` |
| Query understanding, rewriting | `OpenIntelligence/Services/Query/` | `Docs/RETRIEVAL_PIPELINE.md` |
| Retrieval tuning knobs | `OpenIntelligence/Services/RAG/Tuning/` | `Docs/RETRIEVAL_PIPELINE.md` |
| RAG orchestration | `OpenIntelligence/Services/RAG/Orchestration/` | Atlas service map |
| Model routing, on-device vs PCC | Decision: `ModelExecutionPlanner.makePlan` in `OpenIntelligence/Services/RAG/Orchestration/ModelExecutionPlanner.swift`, with constraints built by `RAGService.makePostRetrievalModelPlan` and the consent gate in `RAGService.ensureCloudConsentIfNeeded`. `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/` enforces an attached plan and decides the route itself when none is attached: `FoundationModelRoutePolicy.determineRoute` follows the plan at :28-46, otherwise applies the manual preference and then context size against the on-device window and PCC availability (its "planless branch"). `FoundationModelSessionFactory` builds the session; both are called from `LLMService`. `[evidence_level: code_verified, confidence: exact, evidence_source: ModelExecutionPlanner.swift:24; RAGService.swift:3666,16195,16311; FoundationModelRoutePolicy.swift:23-117; LLMService.swift:609,697]` Corrected 2026-10-20 against the working tree, where those lines are now RAGService.swift:4391 (consent gate) and 18400 (`makePostRetrievalModelPlan`) and LLMService.swift:641, 729 and 1261. A new install's route is Hybrid with PCC permission "Ask when needed", which the chat sends as `preferCloud` with PCC allowed. On that route `makePlan` picks PCC only when PCC is usable (supported, entitled, available, quota left), the network is up, the app can ask (it is in front, or the action can bring it forward) or consent is in place (Always Allow, or Just Once for this question), the context fits PCC, and the context does not fit the device's budget or, outside Standard, the synthesis spans more than one document. With PCC picked in the model picker the chat sends `cloudOnly`, the plan's `requiresPCC` is set, and `makePlan` picks PCC whenever PCC is allowed and usable, the network is up, and the app can ask or consent is in place, with no fit or budget test. With On-Device picked it keeps every call local. It can also pick no model at all: abstain when the evidence is not enough, or the deterministic answer for an exact extraction. Standard plans once, after retrieval. Deep Think and Maximum plan inside every `generateWithProperConsent` call, and only their synthesis calls can be planned to PCC: each session, research decision and running answer is pinned to the device unless the person picked PCC in the model picker, and their other helpers (`generateWithFreshSession`) always run on the device. The consent gate runs only for a call with a plan attached (`guard modelExecutionPlan?.requiresCloudConsent == true`, RAGService.swift:4399), and Standard's answer and every `generateWithProperConsent` call attach one. `[evidence_level: code_verified, confidence: high, evidence_source: SettingsStore.swift:44-50, 450-462, LLMModel.swift:218, 264-268, ChatScreen.swift:3172-3190, ModelExecutionPlanner.swift:36-103, RAGService.swift:4391-4440, 15793-15803, 18456-18495, AgenticOrchestrator.swift:3124-3137, 5333-5351, 6901-6920, 7312, 9123-9150, 9228-9282]` | `Docs/PRIVACY_AND_ROUTING.md`, Atlas §10 |
| LLM execution | `OpenIntelligence/Services/LLM/` | `Docs/PRIVACY_AND_ROUTING.md` |
| Agentic tools, App Intents, Siri | `OpenIntelligence/Services/Agentic/`. Corrected 2026-10-20: the model's tools are registered in `Services/AIPlatform/AppleFoundationModels/FoundationModelToolRegistry.swift` (`createTools`, six tools). No Deep Think or Maximum session gets them (`disableToolsForSession = true`), every synthesis passes `disableTools: true`, and Standard turns them off once it has assembled context, so no answer written from passages has them. A question answered with no passages, in an empty library for one, reaches the model with `disableTools` at its default, false, so that session can be given the tools. Recursive research asks the model to write `[SEARCH: ...]` as text. `[evidence_level: code_verified, confidence: high, evidence_source: FoundationModelToolRegistry.swift:327-360, FoundationModelSessionFactory.swift:32, LLMModel.swift:173, AgenticOrchestrator.swift:5313, 3091-3143, RAGService.swift:14769-14775, 17106-17111]` | Atlas §12 |
| Evidence Threads | `OpenIntelligence/Core/Models/EvidenceThread.swift`, `OpenIntelligence/Services/Storage/EvidenceThreadStore.swift`; owned by `RAGService` (`threadStore`, `persistChatHistory`, `createNewThread`); UI in `OpenIntelligence/Features/Chat/Conversation/ThreadSidebarView.swift` and `ChatScreen.swift`; per-tier cap `QuotaPolicy.evidenceThreadLimit`; iCloud sync `WorkspaceSyncService.synchronizeEvidenceThreads`; tests `OpenIntelligenceTests/Services/Storage/EvidenceThreadStoreTests.swift`. `[evidence_level: code_verified, confidence: high, evidence_source: RAGService.swift:354,688,878-880; ThreadSidebarView.swift:28; ChatScreen.swift:620,2077; QuotaPolicy.swift:59; WorkspaceSyncService.swift:2331,2732]` Unknown: the store writes `<AppSupport>/EvidenceThreads/<container>/` (EvidenceThreadStore.swift:60) but sync reads `EvidenceThreads/` under `localRoot` = `<AppSupport>/OpenIntelligence` (WorkspaceSyncService.swift:2739, OpenIntelligenceRuntimePaths.swift:105-111), so threads may not reach other devices. Verify: on device, create a thread in an iCloud library and check that it appears on a second device. | Atlas §15, canonical §11 |
| iCloud workspace sync | `OpenIntelligence/Services/Infrastructure/Storage/` | Atlas |
| Billing, entitlements, quotas | `OpenIntelligence/Services/Billing/`, `Services/Infrastructure/Configuration/` | `Docs/BILLING_AND_LIMITS.md` |
| Evaluation harness | `OpenIntelligence/Services/Evaluation/` | `Docs/EVALS.md` |
| UI | `OpenIntelligence/Features/`, `OpenIntelligence/UI/` | `WHATS_NEW.md`, `Docs/USER_CHANGELOG.md` |

For the symbols to read first in each feature, and the links between them with the line each one cites, see
`Docs/ai/codemap/INDEX.md` (`AGENTS.md` rule 19).

## If the owner says...

Product vocabulary, mapped to where it lives. Paths are under `OpenIntelligence/` unless shown
otherwise. `[evidence_level: code_verified, confidence: high, evidence_source: each file:line
below, read or grepped at d5cc916 on 2026-09-24]`

| Owner says | Entry file(s) | Key symbol(s) |
|---|---|---|
| Standard, Deep Think, Maximum (quality modes) | `Core/Models/RAGQualityMode.swift`; pickers in `Features/Chat/Conversation/ChatScreen.swift` and `Features/Settings/SettingsView.swift`; Deep Think and Maximum run through `Services/Agentic/AgenticOrchestrator.swift` | `RAGQualityMode.standard` / `.deepThink` / `.maximum`, `displayName` (RAGQualityMode.swift:41), `usesAgenticOrchestrator` (:151); `SettingsStore.ragQualityMode`; `QualityModeQuickPicker` (ChatScreen.swift:3868); `RAGService.executeAgenticQuery` (RAGService.swift:8787) → `AgenticOrchestrator`. Corrected 2026-10-20 against the working tree: a new install starts in Standard (SettingsStore.swift:617-624). `QualityModeQuickPicker` is now at ChatScreen.swift:4154 and `executeAgenticQuery` at RAGService.swift:10770, entered from :11588 before any Standard step runs. It first tries a precision lookup for a lookup or a precise value (:10899-10912): a value the extractor locks is returned with no orchestrator, no model call and no gates, and reads Not Checked. Deep Think runs with the device's config (`DeviceCapabilityService.optimizedAgenticConfig`), not `RAGQualityMode.agenticConfig`, and Maximum with `AgenticConfig.unlimited`. The loop, its stop rules and what follows it are in `Docs/HOW_IT_WORKS.md` section 07. `[evidence_level: code_verified, confidence: high, evidence_source: RAGService.swift:10561-10737, 10863-10922, 11570-11592, ChatScreen.swift:4154, DeviceCapabilityService.swift:1044]` |
| Glossary | `UI/Components/Glossary.swift`, `Features/Settings/GlossaryView.swift` | `Glossary` (Glossary.swift:565), `GlossaryTermID`, `GlossarySection`; `GlossaryView`, opened from `SettingsView.swift:527`, `HowItWorksView` and `OnboardingChecklistView` |
| The HUD, Silicon HUD, X-ray overlay | `Features/Telemetry/Dashboard/MotherboardHUDView.swift`; data from `Services/Infrastructure/Monitoring/HardwareTelemetryState.swift` | `HardwareXRayOverlay` (:296), `SiliconLegend` (:721), `FloatingLegendWindowManager` (:952, UIKit only); toggle `SettingsStore.showSiliconHUD` (SettingsStore.swift:289, Settings toggle at SettingsView.swift:3048); `HardwareTelemetryState`, `HardwareTelemetryReporter` |
| Deleting a library | `Features/Documents/Library/LibraryDeletion.swift`, called from `DocumentLibraryView.swift` and `Features/Documents/Settings/ContainerSettingsSheet.swift` | `LibraryDeletion.delete` → `WorkspaceSyncService.deleteSharedLibrary` for iCloud libraries, `RAGService.removeDocument` per document, `ContainerService.deleteContainer(id:)` (`Services/Infrastructure/Integration/ContainerService.swift:161`). The SDK's `OpenIntelligenceEngine.deleteLibrary` bypasses this path (see the header of `LibraryDeletion.swift`). |
| The PCC consent sheet | `UI/Components/CloudConsentPromptView.swift`, presented by `Features/Chat/Conversation/ChatScreen.swift` | `CloudConsentPromptView`; `.sheet(item: $activeCloudConsent)` fed by `RAGService.pendingCloudConsent` (RAGService.swift:1484); answered through `RAGService.resolveCloudConsent(decision:)`; raised by `RAGService.ensureCloudConsentIfNeeded` (:3666). Corrected 2026-10-20: in the working tree these are RAGService.swift:2048, 2642 and 4391, and the sheet shows sizes and counts, not the excerpts (see "Security and privacy boundaries"). `[evidence_level: code_verified, confidence: high, evidence_source: RAGService.swift:2048, 2642, 4391, CloudConsentPromptView.swift:172-196]` |
| Evidence Threads | see the Evidence Threads row above | `EvidenceThreadStore`, `RAGService.createNewThread`, `ThreadSidebarView` |
| The model selector | `UI/Components/ModelStatusIndicator.swift`, placed in `ChatScreen.swift:3804`; `Features/Settings/Components/ModelSelectorSheet.swift` (removed in 5.7 on 2026-10-20: nothing referenced it) | `ModelStatusIndicator`, a picker over `SettingsStore.fmPreference` (`FoundationModelPreference`, `Core/Models/LLMModel.swift:234`). `ModelSelectorSheet` sets `SettingsStore.selectedModel`, but the only place that creates it is its own `#Preview` (ModelSelectorSheet.swift:223) `[evidence_level: grep_verified, confidence: high]` (removed in 5.7 on 2026-10-20: nothing referenced it). So does `QuickModelPickerSheet`: only `ModelQuickSelector` opens it, and only that file's `#Preview` creates `ModelQuickSelector` (ModelStatusIndicator.swift:348). Otherwise `selectedModel` is set inside `SettingsStore` alone, and it picks the service class `RAGService.rebuildLLMServicesFromSettings` builds (RAGService.swift:1986-1989) `[evidence_level: grep_verified, confidence: high, evidence_source: grep for ModelQuickSelector(, QuickModelPickerSheet( and selectedModel = at dc66b29, 2026-09-28]` |
| Shortcuts, Siri | `Services/Agentic/RAGAppIntents.swift`, `Services/Agentic/ScreenAwarenessIntents.swift`, `Services/Agentic/VisualIntelligenceIntents.swift`, and from 5.7 `SearchPassagesIntent.swift`, `AddToLibraryIntent.swift`, `LibraryIntents.swift`, `OpenItemIntents.swift`, `IntentSupport.swift` and `AppNavigationRequest.swift` in the same folder; `Services/Agentic/Entities/` | `RAGAppShortcutsProvider` (RAGAppIntents.swift:371), 10 `AppShortcut` entries since 5.7 (9 through 5.6); intents such as `QueryDocumentsIntent`, `SearchLibraryIntent`, `IngestDocumentIntent`; 22 actions in all, 17 of them returning a value (counted 2026-10-12). Shortcut count is a hard boundary: all ten slots are used. |
| Sample documents | `Features/Documents/Library/SampleDocumentManager.swift` | `SampleDocumentManager` (:95), sample bodies written in Swift in `samples`, `importSamples` (:365), `refreshStaleSamples` (:522); started from `DocumentLibraryView.importSampleWorkspace` and `OnboardingChecklistView` |
| What's New, version history | `Features/Onboarding/WhatsNewStore.swift`, `WhatsNewView.swift`; `Features/Settings/VersionHistory.swift`, `VersionHistoryView.swift`; `Resources/VersionHistory.md` | `WhatsNewStore.releases` (:102) and `evaluateOnLaunch`, sheet presented in `App/ContentView.swift`; `VersionHistoryLoader` parses the bundled `VersionHistory.md`, a copy of `Docs/USER_CHANGELOG.md` held in step by `VersionHistoryTests.testBundledHistoryMatchesTheWrittenChangelog`; opened from `SettingsView.swift:564` and `AboutView.swift` |

## Data flow

Import → `Services/Document` extracts and chunks → `Services/Embedding` vectorises →
vectors land in `Services/VectorStore`, text lands in the FTS5 index in `Services/Storage`.

Corrected 2026-10-20 against the working tree: the FTS5 index is written twice. The whole document goes in
after extraction and before the text is cut, with one row per page for a multi-page PDF or a batch of a large
one, and one row per passage goes in after the vectors are stored. A single-page PDF and every other file get
no page rows, and a file imported in pieces stores its whole text once at the end. `RAGService.addDocument`
drives both, and `Docs/INGESTION_PIPELINE.md` §1, "The order the code runs", has the steps.
`[evidence_level: code_verified, confidence: high, evidence_source: DocumentProcessor.swift:987-1015, 1046,
RAGService.swift:7894, 7981, RAGService+TextStreaming.swift:316-317]`

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

Corrected 2026-10-20 against the working tree: that is the Standard path, the default for a new install.
`Services/Query` keeps a lookup literal and rewrites another question only when it finds it ambiguous, and
intent comes from a heuristic, with no model. The fusion is weighted (`k: 60`, the library's weights shifted
by the question's search intent and held between 0.35 and 0.65). After generation, the extracted-value
override replaces the model's answer with a value it locks at 0.82, unless (from 5.7) the answer already
states that value, and then the nine gates run once and label the answer. Standard withholds it only when
reliability mode and developer tuning are both off or the gates' average is below 0.50 (0.25 for a lookup),
and the gates never send it back to the model. A `.lookup` or `.tableLookup` question whose gates failed, and
whose answer the extracted-value override did not lock, then gets the source-only check, two on-device calls
that can rewrite or withhold it. Deep Think and Maximum leave before
the first Standard step: up to 5 search phrasings, each through the full retrieval pipeline, fused into 20
passages and graded. Only an excellent or good grade gets the loop of sessions, on the device unless the
person picked PCC in the model picker, which reads one retrieved pool (in Maximum's excellent branch, a
larger one gathered once) with no new retrieval or rerank per session. From 5.7 their answers go through the nine gates too, as a label, unless the source-only check
ran (in 5.6 they read Not Checked). `Docs/HOW_IT_WORKS.md` section 07 has the loop. Lines today: fusion at HybridSearchService.swift:1328-1334 and RAGEngine.swift:997,
rerank at RAGEngine.swift:302 called from RAGService.swift:13070. `[evidence_level: code_verified,
confidence: high, evidence_source: RAGService.swift:11588, 11983-12110, 16500-16529, 16571-16834, 16870-16894,
19500-19525, 11239-11263, QueryRewriterService.swift:83-110, QueryProfileService.swift:49-52, ConfidencePolicyService.swift:48-54,
RAGQualityMode.swift:226-233, VerificationGateService.swift:250, AgenticOrchestrator.swift:339, 544-1143,
2185-2270, 5155-5235, 8045-8085]`

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

Corrected 2026-10-20 against the working tree: the vector store is one flat file per library,
`_vectors.bin` of raw Float32 in arrival order beside `_norms.bin` and `_meta.json`, all three rewritten whole
at each save, with no index, no quantisation and no clustering. A search compares the question with every vector, with Metal on the GPU
from 1,000 vectors when the device allows it and with vDSP on the CPU otherwise. It is not HNSW: VecturaKit is
not a dependency, so the `vecturaHNSW` kind falls back to this store. The FTS5 tables share one
`fulltext.sqlite` across libraries through a `container_id` column, with porter stemming and section
titles weighted 10, section paths 5 and body text 1. If a library's embedder can't be loaded at import and a
stand-in is used, the library is switched to the stand-in and its vectors are cleared before the import goes
on. `[evidence_level: code_verified,
confidence: high, evidence_source: BNNSVectorDatabase.swift:26-41, 1036-1091, 1104-1201,
VectorStoreRouter.swift:154-172, Package.resolved, SQLiteFullTextService.swift:87-94, 242-255, 1440-1461,
RAGService.swift:7080-7128, 7894-7895]`

## Security and privacy boundaries

The privacy claim is the product, so these are the invariants worth checking on any change:

- Ingestion, indexing, retrieval, and ranking are local. Nothing is uploaded to make search work.
  Open question, 2026-10-20: one import step was not traced. When `SystemLanguageModel.default` is
  unavailable, the document overview is requested through `RAGService.llmService` with a config that carries
  no route plan and allows PCC, so `FoundationModelRoutePolicy`'s planless branch decides where it runs, and no
  consent check is on that path. Whether that can send a document's text to PCC is not known.
  `[evidence_level: inferred, confidence: medium, evidence_source: DocumentSummaryService.swift:270-314,
  LLMModel.swift:146-173, FoundationModelRoutePolicy.swift:49-95]`
- Only final answer generation may leave the device, only to Apple Private Cloud Compute, only with
  consent, and only after the user has seen which excerpts would be sent.
  Corrected 2026-10-20 against the working tree: the consent sheet (Always Allow, Just Once, Deny) does
  not show the excerpts. It shows what Private Cloud Compute is and, under Show Details, the provider, the
  model and how much would be sent: the prompt's and the context's size in characters, the number of
  passages, the payload's size and why PCC was chosen. After Always Allow, later sends are not asked about.
  A new install's route is Hybrid with permission "Ask when needed", so the sheet can come up on any question
  whose context does not fit the device or, outside Standard, whose synthesis spans more than one document,
  and on any question once PCC is picked in the model picker. "Final answer generation" is, in Standard, the
  answer, a citation retry (only when reliability mode and developer tuning are both off and the answer was not
  streamed) and an integrity repair of a malformed answer, all on the answer's route. In Deep Think and
  Maximum it is their synthesis calls, and once PCC is picked in the model picker their sessions can go too
  (the routing row above). `[evidence_level: code_verified, confidence: high, evidence_source:
  CloudConsentPromptView.swift:7, 45-71, 172-196, 204-263, RAGService.swift:4391-4440, 16274-16392,
  ModelExecutionPlanner.swift:36-103, AgenticOrchestrator.swift:9228-9240]`
- From 5.7 the app makes one other kind of request, and it carries nothing from the library: it downloads
  a web page when the person gives it the address ("Save a Web Page", the Link parameter of "Add to
  Library", and a web address pasted on the Documents screen), through `WebPageFetchService`.
  `Docs/PRIVACY_AND_ROUTING.md` has the detail.
- Every use of `PrivateCloudComputeLanguageModel` must be gated behind `EntitlementChecker`.
- The answer's execution badge is read from an execution receipt, not from what was requested.
- There is no account, no server operated by this project, and no third-party AI service in the path.

## External couplings

Four systems the app does not control. Each one's failure mode is different, and the app is expected
to keep working without three of them.

| System | Code boundary | If unavailable |
|---|---|---|
| Apple Foundation Models (on-device and PCC) | `Services/AIPlatform/AppleFoundationModels/` | No answer generation. Retrieval still works, so citations and evidence remain available. The public SDK exposes no tier selector, no server architecture, and no server context window; do not name any of them. |
| CloudKit / iCloud Drive | `Services/Infrastructure/Storage/WorkspaceSyncService.swift` | Library stops reconciling across devices. Local library keeps working. Sync interleaving is a known source of defects. Since 5.7 one case has tests: a sync pass skips a library's vector store while an import into it is unfinished (`WorkspaceSyncImportGuardTests`). Reconciliation between two devices has no test coverage. |
| StoreKit 2 | `Services/Billing/`, `EntitlementStore.swift` | Entitlement state cannot refresh. Must degrade toward the user keeping what they paid for, never toward revoking it. |
| Core ML reranker | `Resources/MLModels/ReRankerModel.mlpackage` | The cross-encoder drops out and `RAGEngine.rerank` ranks candidates with its heuristic fallback instead, logging a warning; scores are not comparable to a cross-encoder run. `[evidence_level: code_verified, confidence: exact, evidence_source: RAGEngine.swift:329-346]` Bound to `cross-encoder/ms-marco-TinyBERT-L2-v2` by exact path in `THIRD_PARTY_NOTICES.md`, which is the provenance of record. |

Nothing else is external. There is no server operated by this project and no third-party AI service
in the path, which is a product guarantee rather than a current state.

## Non-obvious constraints

- **The repository lives in iCloud-synced `~/Documents`.** Synchronized file groups plus iCloud
  conflict copies produce duplicate-symbol errors that point at innocent code. `.git` is a file
  pointing at `.git.nosync` for the same reason.
- **`RAGAppIntents.swift` uses all 10 available Siri shortcut slots since 5.7** (9 through 5.6). Adding one
  now means removing one: an eleventh stops the whole set registering with no error.
- **Retrieval measurement exists but is not yet trustworthy.** The harness does measure it —
  `BenchmarkRuns/LEDGER.md` carries nDCG and MRR@10 figures — so the older claim that it never had
  is withdrawn as of 2026-09-01. The live problem is different and worse: retrieval is
  **nondeterministic**, two runs of one build returning different evidence for one question, so no
  A/B between components is trustworthy, including judgements about what already shipped. It is a
  Future Backlog item, not the current work: the roadmap rows "Retrieval is nondeterministic, which
  makes every quality change in the stack unfalsifiable"
  (https://app.notion.com/3cc49a74d54f81d7a88dffe679ce9bb1) and "Two runs of one build return
  different evidence for the same question" (https://app.notion.com/3bf49a74d54f81189046d2f007f68272)
  were both To Do in Future Backlog on 2026-09-29, when `Docs/ai/STATE.md` had 5.5 as the open release (5.7 is the open release on 2026-10-12).
  (Corrected 2026-09-29: this line used to call it the
  current work.) `[evidence_level: artifact_derived, confidence: high, evidence_source: Notion
  roadmap data source queried 2026-09-29; Docs/ai/STATE.md Objective]`
