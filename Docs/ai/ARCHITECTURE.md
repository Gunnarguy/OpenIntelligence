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

`OpenIntelligenceCapture` (folder `OpenIntelligenceCapture/`, iOS only, since 5.7) is the Lock Screen
camera, a `LockedCameraCaptureExtension` opened by the "Scan into Library" control
(`OpenIntelligence/App/ScanIntoLibraryIntent.swift`). `CaptureExtension.swift` declares the
extension; `CaptureViewfinder.swift` holds its screen and a `UIImagePickerController` camera that
writes each page as a JPEG to the capture session's folder. The extension has no network and no app
group, so the app picks those pages up on its next launch (`Features/Camera/LockedCaptureImport.swift`).
`[evidence_level: code_verified, confidence: exact, evidence_source: OpenIntelligenceCapture/CaptureExtension.swift:13-24, CaptureViewfinder.swift:50-54, project.pbxproj:24 platformFilter = ios]`

## Where each area lives

| Area | Source | Owning document |
|---|---|---|
| Process-wide stores and the engine | `OpenIntelligence/App/AppServices.swift`: `AppServices.shared` (5.8, 2026-11-03) builds once per launch the app's `RAGService`, `WorkspaceSyncService`, `ContainerService`, `EntitlementStore`, `SettingsStore` and `ModelResolutionService`, and every window's `ContentView` observes them; before, each window built its own set and each set started its own launch work. `[evidence_level: code_verified, confidence: exact, evidence_source: AppServices.swift:14-55]` | Atlas §9 |
| Mac window shell | `OpenIntelligence/App/ContentView.swift` `macWindowContent` (5.8, 2026-11-18): on macOS a `NavigationSplitView` replaces the iPhone and iPad `TabView`; its sidebar is `MacSidebar` in `App/MacShell.swift` (areas, libraries, the open library's conversations), sidebar and menu-bar requests reach screens through a per-window `MacShellCommands` (environment `macShellCommands`), and each area is kept once built with `macAreaIsActive` telling it whether it is in front. Settings is a `Settings` scene (`App/MacSettingsWindowRoot.swift`, `SettingsView.macSettingsWindow` in `SettingsView+List.swift`) and the Atlas map a `Window` scene (`MacAtlasWindowRoot`). Documents draws `DocumentTableMac` with an inspector (`DocumentLibraryView+Mac.swift`). `[evidence_level: code_verified, confidence: high]` | `CHANGELOG.md` 5.8, "The Mac app is laid out as a Mac app" |
| Ingestion, chunking, OCR | `OpenIntelligence/Services/Document/` reads, cleans and cuts the text. Corrected 2026-10-20: the queue and the import itself (copy, duplicate check, embedding, both stores, the overview passage) are `RAGService.enqueueDocuments` and `RAGService.addDocument` in `Services/RAG/Orchestration/RAGService+ImportQueue.swift` and `RAGService+Import.swift`, with `RAGService+Streaming.swift` and `RAGService+TextStreaming.swift` for very large files. `[evidence_level: code_verified, confidence: high, evidence_source: RAGService+ImportQueue.swift:33, RAGService+Import.swift:33, RAGService+Import.swift:233-274]` | `Docs/INGESTION_PIPELINE.md`, §1 "The order the code runs" |
| Embedding and providers | `OpenIntelligence/Services/Embedding/` | Atlas §17 |
| Vector storage | `OpenIntelligence/Services/VectorStore/`. Corrected 2026-10-20: `BNNSVectorDatabase`, one flat Float32 file per library searched by brute force, not an HNSW index (see Persistence). `[evidence_level: code_verified, confidence: high, evidence_source: BNNSVectorDatabase.swift:26-41, 1104-1201, VectorStoreRouter.swift:154-172, Package.resolved]` | Atlas §9 |
| Keyword index (SQLite FTS5) | `OpenIntelligence/Services/Storage/` | Atlas §9 |
| Hybrid retrieval, fusion, rerank | `OpenIntelligence/Services/RAG/Retrieval/` (`HybridSearchService`: vector + lexical search, boosts, top-K). Fusion is `RAGEngine.reciprocalRankFusion` and reranking is `RAGEngine.rerank`, both in `OpenIntelligence/Services/RAG/Orchestration/RAGEngine.swift`; `RAGService` calls `rerank` after `HybridSearchService` returns. `[evidence_level: code_verified, confidence: exact, evidence_source: HybridSearchService.swift:246,311,1209,1328-1334; RAGEngine.swift:1003,302; RAGService+QueryRetrieval.swift:556]` | `Docs/RETRIEVAL_PIPELINE.md` |
| Query understanding, rewriting | `OpenIntelligence/Services/Query/` | `Docs/RETRIEVAL_PIPELINE.md` |
| Retrieval tuning knobs | `OpenIntelligence/Services/RAG/Tuning/` | `Docs/RETRIEVAL_PIPELINE.md` |
| RAG orchestration | `OpenIntelligence/Services/RAG/Orchestration/` | Atlas service map |
| Model routing, on-device vs PCC | Decision: `ModelExecutionPlanner.makePlan` in `OpenIntelligence/Services/RAG/Orchestration/ModelExecutionPlanner.swift`, with constraints built by `RAGService.makePostRetrievalModelPlan` and the consent gate in `RAGService.ensureCloudConsentIfNeeded`. `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/` enforces an attached plan and decides the route itself when none is attached: `FoundationModelRoutePolicy.determineRoute` follows the plan at :28-46, otherwise returns `.onDevice` (its "planless branch"). (Corrected 2026-11-04: this said that without a plan it applied the manual preference and then context size against the on-device window and PCC availability, which was 5.6 and the 5.7 work before 2026-10-21; the branch is at :49-65 now and a call with no plan never reaches PCC. `[evidence_level: code_verified, confidence: exact, evidence_source: FoundationModelRoutePolicy.swift:23-65]`) `FoundationModelSessionFactory` builds the session; both are called from `LLMService`. `[evidence_level: code_verified, confidence: exact, evidence_source: ModelExecutionPlanner.swift:24; RAGService+StandardRetrieval.swift:873,RAGService+Generation.swift:1138,RAGService+Generation.swift:1259; FoundationModelRoutePolicy.swift:23-66; AppleFoundationLLMService.swift:408,496]` Corrected 2026-10-20 against the working tree, where those lines are now RAGService+StandardRetrieval.swift:873 (consent gate) and RAGService+Generation.swift:1138 (`makePostRetrievalModelPlan`) and AppleFoundationLLMService.swift:408, 496 and 1040. A new install's route is Hybrid with PCC permission "Ask when needed", which the chat sends as `preferCloud` with PCC allowed. On that route `makePlan` picks PCC only when PCC is usable (supported, entitled, available, quota left), the network is up, the app can ask (it is in front, or the action can bring it forward) or consent is in place (Always Allow, or Just Once for this question), the context fits PCC, and the context does not fit the device's budget or, outside Standard, the synthesis spans more than one document. With PCC picked in the model picker the chat sends `cloudOnly`, the plan's `requiresPCC` is set, and `makePlan` picks PCC whenever PCC is allowed and usable, the network is up, and the app can ask or consent is in place, with no fit or budget test. With On-Device picked it keeps every call local. It can also pick no model at all: abstain when the evidence is not enough, or the deterministic answer for an exact extraction. Standard plans once, after retrieval. Deep Think and Maximum plan inside every `generateWithProperConsent` call, and only their synthesis calls can be planned to PCC: each session, research decision and running answer is pinned to the device unless the person picked PCC in the model picker, and their other helpers (`generateWithFreshSession`) always run on the device. The consent gate runs only for a call with a plan attached (`guard modelExecutionPlan?.requiresCloudConsent == true`, RAGService+StandardRetrieval.swift:881), and Standard's answer and every `generateWithProperConsent` call attach one. `[evidence_level: code_verified, confidence: high, evidence_source: SettingsStore.swift:44-50, 450-462, LLMModel.swift:218, 264-268, ChatScreen+Sending.swift:316-334, ModelExecutionPlanner.swift:36-103, RAGService+StandardRetrieval.swift:873-927, RAGService+QueryRetrieval.swift:122-132, RAGService+Generation.swift:1194-1233, AgenticOrchestrator+Research.swift:296-309, AgenticOrchestrator+ReasoningChain.swift:643-661, AgenticOrchestrator+Maximum.swift:919-938, AgenticOrchestrator+Maximum.swift:1330, RAGService+Agentic.swift:87-130, RAGService+Agentic.swift:208-262]` | `Docs/PRIVACY_AND_ROUTING.md`, Atlas §10 |
| LLM execution | `OpenIntelligence/Services/LLM/` | `Docs/PRIVACY_AND_ROUTING.md` |
| Agentic tools, App Intents, Siri | `OpenIntelligence/Services/Agentic/`. Corrected 2026-10-20: the model's tools are registered in `Services/AIPlatform/AppleFoundationModels/FoundationModelToolRegistry.swift` (`createTools`, six tools). No Deep Think or Maximum session gets them (`disableToolsForSession = true`), every synthesis passes `disableTools: true`, and Standard turns them off once it has assembled context, so no answer written from passages has them. A question answered with no passages, in an empty library for one, reaches the model with `disableTools` at its default, false, so that session can be given the tools. Recursive research asks the model to write `[SEARCH: ...]` as text. `[evidence_level: code_verified, confidence: high, evidence_source: FoundationModelToolRegistry.swift:327-360, FoundationModelSessionFactory.swift:32, LLMModel.swift:173, AgenticOrchestrator+ReasoningChain.swift:623, AgenticOrchestrator+Research.swift:263-315, RAGService+QueryContext.swift:1120-1141, RAGService+QueryPipeline.swift:501, RAGService+Generation.swift:413-418]` | Atlas §12 |
| Evidence Threads | `OpenIntelligence/Core/Models/EvidenceThread.swift`, `OpenIntelligence/Services/Storage/EvidenceThreadStore.swift`; owned by `RAGService` (`threadStore`, `persistChatHistory`, `createNewThread`); UI in `OpenIntelligence/Features/Chat/Conversation/ThreadSidebarView.swift` and `ChatScreen.swift`; per-tier cap `QuotaPolicy.evidenceThreadLimit`; iCloud sync `WorkspaceSyncService.synchronizeEvidenceThreads`; tests `OpenIntelligenceTests/Services/Storage/EvidenceThreadStoreTests.swift`. `[evidence_level: code_verified, confidence: high, evidence_source: RAGService.swift:52,RAGService+ChatHistory.swift:92,276-280; ThreadSidebarView.swift:28; ChatScreen+Body.swift:229, ChatScreen+Actions.swift:358; QuotaPolicy.swift:59; WorkspaceSyncService+Artifacts.swift:104,WorkspaceSyncService+Artifacts.swift:531]` Unknown: the store writes `<AppSupport>/EvidenceThreads/<container>/` (EvidenceThreadStore.swift:60) but sync reads `EvidenceThreads/` under `localRoot` = `<AppSupport>/OpenIntelligence` (WorkspaceSyncService+Artifacts.swift:538, OpenIntelligenceRuntimePaths.swift:105-111), so threads may not reach other devices. Verify: on device, create a thread in an iCloud library and check that it appears on a second device. (Corrected 2026-11-07: the store now writes `<base>/EvidenceThreads/<containerId>/` with `<base>` = `OpenIntelligenceRuntimePaths.baseDirectory()`, the folder sync reads, and moves threads out of the two older roots when it is made, so the path mismatch described here is gone in the code; the device check still stands. `[evidence_level: code_verified, confidence: high, evidence_source: EvidenceThreadStore.swift:10-21, 38-52; OpenIntelligenceRuntimePaths.swift:113]`) | Atlas §15, canonical §11 |
| iCloud workspace sync | `OpenIntelligence/Services/Infrastructure/Storage/` | Atlas |
| Billing, entitlements, quotas | `OpenIntelligence/Services/Billing/`, `Services/Infrastructure/Configuration/` | `Docs/BILLING_AND_LIMITS.md` |
| Evaluation harness | `OpenIntelligence/Services/Evaluation/` | `Docs/EVALS.md` |
| UI | `OpenIntelligence/Features/`, `OpenIntelligence/UI/` | `WHATS_NEW.md`, `Docs/USER_CHANGELOG.md` |

For the symbols to read first in each feature, and the links between them with the line each one cites, see
`Docs/ai/codemap/INDEX.md` (`AGENTS.md` rule 19).

## Large files split by job (2026-11-05 and 2026-11-07)

`RAGService`, `AgenticOrchestrator` and fifteen more of the largest Swift files (ChatScreen, DocumentProcessor,
SettingsView, WorkspaceSyncService, SQLiteFullTextService and the rest) are a main file plus `Type+Job.swift`
extension files, a pure move; on 2026-11-07 `RAGService+QueryPipeline.swift`, `RAGService+Import.swift` and `DocumentProcessor+StructuredParsing.swift` were split again, into 6, 4 and 3 files. Which file holds what: `Docs/ai/FILE_MAP.md`. Where a line of an old file went:
`python3 scripts/split_linemap.py File.swift:N`.

## If the owner says...

The table of his words for each feature, with the entry files and symbols behind them, is in
`Docs/ai/ARCHITECTURE_DETAIL.md` (moved there on 2026-11-20, unchanged, to keep the every-task read set small).
`Docs/ai/codemap/INDEX.md` lists every feature with what it is also called, and the prompt hook prints the slice a
prompt names.

## Data flow

Import: a file is staged, extracted, chunked, embedded and indexed on device (`Docs/INGESTION_PIPELINE.md`). A question
is rewritten, searched by keyword and by meaning, reranked, packed into the model's window, answered and checked
(`Docs/RETRIEVAL_PIPELINE.md`; routing to Private Cloud Compute in `Docs/PRIVACY_AND_ROUTING.md`). The hop-by-hop text
that stood here is in `Docs/ai/ARCHITECTURE_DETAIL.md` (moved 2026-11-20, unchanged).

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
VectorStoreRouter.swift:154-172, Package.resolved, SQLiteFullTextService.swift:87-94, 242-255, SQLiteFullTextService+Chunks.swift:714-735,
RAGService+Import.swift:493-545 (`invalidateVectorStore(for:clearStorage: true)` at 527 and 532)]`

## Security and privacy boundaries

The privacy claim is the product, so these are the invariants worth checking on any change:

- Ingestion, indexing, retrieval, and ranking are local. Nothing is uploaded to make search work.
  Open question, 2026-10-20: one import step was not traced. When `SystemLanguageModel.default` is
  unavailable, the document overview is requested through `RAGService.llmService` with a config that carries
  no route plan and allows PCC, so `FoundationModelRoutePolicy`'s planless branch decides where it runs, and no
  consent check is on that path. Whether that can send a document's text to PCC is not known.
  `[evidence_level: inferred, confidence: medium, evidence_source: DocumentSummaryService.swift:270-314,
  LLMModel.swift:146-173, FoundationModelRoutePolicy.swift:49-95]`
  Closed 2026-11-04: a call with no plan returns `.onDevice` in `determineRoute` (5.7, 2026-10-21), and
  `LLMService` reaches PCC only through that function (its two callers, AppleFoundationLLMService.swift:496 and AppleFoundationLLMService.swift:1040), so
  the overview fallback stays on the device. `[evidence_level: code_verified, confidence: high,
  evidence_source: FoundationModelRoutePolicy.swift:49-65, AppleFoundationLLMService.swift:496, AppleFoundationLLMService.swift:1040; grep -rn "determineRoute(" OpenIntelligence]`
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
  CloudConsentPromptView.swift:7, 45-71, 172-196, 204-263, RAGService+StandardRetrieval.swift:873-927, RAGService+QueryAnswer.swift:66-166,
  ModelExecutionPlanner.swift:36-103, RAGService+Agentic.swift:208-220]`
- From 5.7 the app makes one other kind of request, and it carries nothing from the library: it downloads
  a web page when the person gives it the address ("Save a Web Page", the Link parameter of "Add to
  Library", and a web address pasted on the Documents screen), through `WebPageFetchService`.
  `Docs/PRIVACY_AND_ROUTING.md` has the detail.
- Every use of `PrivateCloudComputeLanguageModel` must be gated behind `EntitlementChecker`.
- The answer's execution badge is read from an execution receipt, not from what was requested.
- There is no account, no server operated by this project, and no third-party AI service in the path.

## External couplings

Apple's Foundation Models and Private Cloud Compute, iCloud Drive, StoreKit and the bundled Core ML models, each with
its failure mode: the table is in `Docs/ai/ARCHITECTURE_DETAIL.md` (moved 2026-11-20, unchanged).

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
