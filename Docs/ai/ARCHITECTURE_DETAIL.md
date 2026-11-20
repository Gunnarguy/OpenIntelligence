# Architecture detail

Three sections moved here from `Docs/ai/ARCHITECTURE.md` on 2026-11-20, word for word, because that file is read at the
start of every task and had grown to 37 KB (the every-task read set has a 40 KB limit,
`test_every_task_loads_only_the_small_universal_set`). Read this file when a task needs the feature vocabulary, the
hop-by-hop data flow, or the external couplings. It is checked by `scripts/verify_doc_claims.py` like the file it came
from.

## If the owner says...

Product vocabulary, mapped to where it lives. Paths are under `OpenIntelligence/` unless shown
otherwise. `[evidence_level: code_verified, confidence: high, evidence_source: each file:line
below, read or grepped at d5cc916 on 2026-09-24]`

| Owner says | Entry file(s) | Key symbol(s) |
|---|---|---|
| Standard, Deep Think, Maximum (quality modes) | `Core/Models/RAGQualityMode.swift`; pickers in `Features/Chat/Conversation/ChatScreen.swift` and `Features/Settings/SettingsView.swift`; Deep Think and Maximum run through `Services/Agentic/AgenticOrchestrator.swift` | `RAGQualityMode.standard` / `.deepThink` / `.maximum`, `displayName` (RAGQualityMode.swift:41), `usesAgenticOrchestrator` (:151); `SettingsStore.ragQualityMode`; `QualityModeQuickPicker` (QualityModeQuickPicker.swift:23); `RAGService.executeAgenticQuery` (RAGService+AgenticQuery.swift:333) → `AgenticOrchestrator`. Corrected 2026-10-20 against the working tree: a new install starts in Standard (SettingsStore.swift:617-624). `QualityModeQuickPicker` is now at QualityModeQuickPicker.swift:23 and `executeAgenticQuery` at RAGService+AgenticQuery.swift:333, entered from RAGService+QueryPipeline.swift:224 before any Standard step runs. It first tries a precision lookup for a lookup or a precise value (RAGService+AgenticQuery.swift:462-475): a value the extractor locks is returned with no orchestrator, no model call and no gates, and reads Not Checked. Deep Think runs with the device's config (`DeviceCapabilityService.optimizedAgenticConfig`), not `RAGQualityMode.agenticConfig`, and Maximum with `AgenticConfig.unlimited`. The loop, its stop rules and what follows it are in `Docs/HOW_IT_WORKS.md` section 07. `[evidence_level: code_verified, confidence: high, evidence_source: RAGService+AgenticQuery.swift:124-300, RAGService+AgenticQuery.swift:426-485, RAGService+QueryPipeline.swift:203-228, QualityModeQuickPicker.swift:23, DeviceCapabilityService.swift:1063]` |
| Glossary | `UI/Components/Glossary.swift`, `Features/Settings/GlossaryView.swift` | `Glossary` (Glossary.swift:587), `GlossaryTermID`, `GlossarySection`; `GlossaryView`, opened from `SettingsView+List.swift:495`, `HowItWorksView` and `OnboardingChecklistView` |
| The HUD, Silicon HUD, X-ray overlay | `Features/Telemetry/Dashboard/MotherboardHUDView.swift`; data from `Services/Infrastructure/Monitoring/HardwareTelemetryState.swift` | `HardwareXRayOverlay` (:296), `SiliconLegend` (:736), `FloatingLegendWindowManager` (:1090, UIKit only); toggle `SettingsStore.showSiliconHUD` (SettingsStore.swift:290, Settings toggle at SettingsView+AppearanceAndSupport.swift:100); `HardwareTelemetryState`, `HardwareTelemetryReporter` |
| Deleting a library | `Features/Documents/Library/LibraryDeletion.swift`, called from `DocumentLibraryView.swift` and `Features/Documents/Settings/ContainerSettingsSheet.swift` | `LibraryDeletion.delete` → `WorkspaceSyncService.deleteSharedLibrary` for iCloud libraries, `RAGService.removeDocument` per document, `ContainerService.deleteContainer(id:)` (`Services/Infrastructure/Integration/ContainerService.swift:217`). The SDK's `OpenIntelligenceEngine.deleteLibrary` bypasses this path (see the header of `LibraryDeletion.swift`). |
| The PCC consent sheet | `UI/Components/CloudConsentPromptView.swift`, presented by `Features/Chat/Conversation/ChatScreen.swift` | `CloudConsentPromptView`; `.sheet(item: $activeCloudConsent)` fed by `RAGService.pendingCloudConsent` (RAGService.swift:734); answered through `RAGService.resolveCloudConsent(decision:)`; raised by `RAGService.ensureCloudConsentIfNeeded` (RAGService+StandardRetrieval.swift:873). Corrected 2026-10-20: in the working tree these are RAGService.swift:734, RAGService+Consent.swift:159 and RAGService+StandardRetrieval.swift:873, and the sheet shows sizes and counts, not the excerpts (see "Security and privacy boundaries"). `[evidence_level: code_verified, confidence: high, evidence_source: RAGService.swift:734, RAGService+Consent.swift:159, RAGService+StandardRetrieval.swift:873, CloudConsentPromptView.swift:172-196]` |
| Evidence Threads | see the Evidence Threads row above | `EvidenceThreadStore`, `RAGService.createNewThread`, `ThreadSidebarView` |
| The model selector | `UI/Components/ModelStatusIndicator.swift`, placed in `ChatScreen.swift@dc66b29:3804`; `Features/Settings/Components/ModelSelectorSheet.swift` (removed in 5.7 on 2026-10-20: nothing referenced it) | `ModelStatusIndicator`, a picker over `SettingsStore.fmPreference` (`FoundationModelPreference`, `Core/Models/LLMModel.swift:246`). `ModelSelectorSheet` sets `SettingsStore.selectedModel`, but the only place that creates it is its own `#Preview` (ModelSelectorSheet.swift:223) `[evidence_level: grep_verified, confidence: high]` (removed in 5.7 on 2026-10-20: nothing referenced it). So did `QuickModelPickerSheet` and `ModelQuickSelector`, which only a `#Preview` created (ModelStatusIndicator.swift@b914298b:245-371); both were removed 2026-11-06. Otherwise `selectedModel` is set inside `SettingsStore` alone, and it picks the service class `RAGService.rebuildLLMServicesFromSettings` builds (RAGService.swift@dc66b29:1986-1989) `[evidence_level: grep_verified, confidence: high, evidence_source: grep for ModelQuickSelector(, QuickModelPickerSheet( and selectedModel = at dc66b29, 2026-09-28]` |
| Shortcuts, Siri | `Services/Agentic/RAGAppIntents.swift`, `Services/Agentic/ScreenAwarenessIntents.swift`, `Services/Agentic/VisualIntelligenceIntents.swift`, and from 5.7 `SearchPassagesIntent.swift`, `AddToLibraryIntent.swift`, `LibraryIntents.swift`, `OpenItemIntents.swift`, `IntentSupport.swift` and `AppNavigationRequest.swift` in the same folder; `Services/Agentic/Entities/` | `RAGAppShortcutsProvider` (RAGAppIntents.swift:666), 10 `AppShortcut` entries since 5.7 (9 through 5.6); intents such as `QueryDocumentsIntent`, `SearchLibraryIntent`, `IngestDocumentIntent`; 22 actions in all, 17 of them returning a value (counted 2026-10-12). Shortcut count is a hard boundary: all ten slots are used. |
| Sample documents | `Features/Documents/Library/SampleDocumentManager.swift` | `SampleDocumentManager` (:95), sample bodies written in Swift in `samples`, `importSamples` (:383), `refreshStaleSamples` (:556); started from `DocumentLibraryView.importSampleWorkspace` and `OnboardingChecklistView` |
| What's New, version history | `Features/Onboarding/WhatsNewStore.swift`, `WhatsNewView.swift`; `Features/Settings/VersionHistory.swift`, `VersionHistoryView.swift`; `Resources/VersionHistory.md` | `WhatsNewStore.releases` (:102) and `evaluateOnLaunch`, sheet presented in `App/ContentView.swift`; `VersionHistoryLoader` parses the bundled `VersionHistory.md`, a copy of `Docs/USER_CHANGELOG.md` held in step by `VersionHistoryTests.testBundledHistoryMatchesTheWrittenChangelog`; opened from `SettingsView+List.swift:544` and `AboutView.swift` |

## Data flow

Import → `Services/Document` extracts and chunks → `Services/Embedding` vectorises →
vectors land in `Services/VectorStore`, text lands in the FTS5 index in `Services/Storage`.

Corrected 2026-10-20 against the working tree: the FTS5 index is written twice. The whole document goes in
after extraction and before the text is cut, with one row per page for a multi-page PDF or a batch of a large
one, and one row per passage goes in after the vectors are stored. A single-page PDF and every other file get
no page rows, and a file imported in pieces stores its whole text once at the end. `RAGService.addDocument`
drives both, and `Docs/INGESTION_PIPELINE.md` §1, "The order the code runs", has the steps.
`[evidence_level: code_verified, confidence: high, evidence_source: DocumentProcessor+Import.swift:337-365, 396,
RAGService+Import.swift:339-349, 1205, RAGService+TextStreaming.swift:320-321]`

Query → `Services/Query` rewrites and classifies intent → `HybridSearchService` runs dense vector
search and lexical scoring (concurrently on the FTS5 path), fuses them with reciprocal rank fusion
(`RAGEngine.reciprocalRankFusion`), applies boosts, and returns a top-K; it does not rerank →
`RAGService` reranks that set with `RAGEngine.rerank` and packs context →
`RAGService.makePostRetrievalModelPlan` builds the constraints and `ModelExecutionPlanner.makePlan`
decides where to execute on the main answer path, with `RAGService.ensureCloudConsentIfNeeded` as the consent gate (when no plan is attached, `FoundationModelRoutePolicy.determineRoute` in `Services/AIPlatform` decides instead, and since 5.7 it returns the device; corrected 2026-11-04, `[evidence_level: code_verified, confidence: exact, evidence_source: FoundationModelRoutePolicy.swift:49-65]`) →
`Services/LLM` generates, using `FoundationModelRoutePolicy` and `FoundationModelSessionFactory` in
`Services/AIPlatform` to turn that plan into a session → the answer carries citations back to the
chunks that produced it. `[evidence_level: code_verified, confidence: high, evidence_source:
HybridSearchService.swift:246,311,1209,1234-1240,1328-1334; RAGService+QueryRetrieval.swift:556,RAGService+QueryRetrieval.swift:122,RAGService+QueryRetrieval.swift:159;
ModelExecutionPlanner.swift:24; FoundationModelRoutePolicy.swift:49-66; AppleFoundationLLMService.swift:408,496]`

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
ran (in 5.6 they read Not Checked). `Docs/HOW_IT_WORKS.md` section 07 has the loop. Lines today: fusion at HybridSearchService.swift:1328-1334 and RAGEngine.swift:1003,
rerank at RAGEngine.swift:302 called from RAGService+QueryRetrieval.swift:556. `[evidence_level: code_verified,
confidence: high, evidence_source: RAGService+QueryPipeline.swift:224, RAGService+QueryPreparation.swift:292-424, RAGService+QueryExits.swift:579-668, RAGService+QueryAnswer.swift:207-240, RAGService+QueryPipeline.swift:937, RAGService+QueryAnswer.swift:819-865, RAGService+QueryAnswer.swift:363-387,
RAGService+AnswerFinishing.swift:428-453, RAGService+AgenticQuery.swift:802-826, QueryRewriterService.swift:83-110, QueryProfileService.swift:49-52, ConfidencePolicyService.swift:48-54,
RAGQualityMode.swift:226-233, VerificationGateService.swift:250, AgenticOrchestrator.swift:180, 386-985,
AgenticOrchestrator+Retrieval.swift:1055-1149, AgenticOrchestrator+ReasoningChain.swift:465-545, AgenticOrchestrator+MultiChain.swift:17-72 (`gatherAllRelevantChunks`, Maximum's larger pool)]`

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

## External couplings

Four systems the app does not control. Each one's failure mode is different, and the app is expected
to keep working without three of them.

| System | Code boundary | If unavailable |
|---|---|---|
| Apple Foundation Models (on-device and PCC) | `Services/AIPlatform/AppleFoundationModels/` | No answer generation. Retrieval still works, so citations and evidence remain available. The public SDK exposes no tier selector, no server architecture, and no server context window; do not name any of them. The on-device side is read from the device, never fixed: the window is `SystemLanguageModel.default.contextSize` (4,096 to 8,192 by device and system version; `FoundationModelTokenBudget.baseContextLength` 4,096 only where it reports none), and on iOS and macOS 27 the model's name is `SystemLanguageModel.variant.displayName` ("AFM 3 Core" or "AFM 3 Core Advanced", one per device, chosen by the system; `Docs/ai/DECISIONS.md` 2026-11-17). [evidence_level: code_verified, confidence: high] |
| CloudKit / iCloud Drive | `Services/Infrastructure/Storage/WorkspaceSyncService.swift` | Library stops reconciling across devices. Local library keeps working. Sync interleaving is a known source of defects. Since 5.7 one case has tests: a sync pass skips a library's vector store while an import into it is unfinished (`WorkspaceSyncImportGuardTests`). Since 2026-11-18 a pass that changed nothing writes nothing: `writeJSON` skips identical bytes through `coordinatedMergeData`, and `synchronizeIngestionQueue` skips a root whose items, contexts and tombstones are unchanged, ignoring `updatedAt` and order. A rewrite in the iCloud root moves a content-change date that `workspaceSignature` hashes (the metadata query watches only that root), so it reads as a change from iCloud and starts the next pass; before, `deleted_documents.json` and `ingestion_queue.json` there did that on every pass. A write added to a pass needs the same check (`WorkspaceSyncFileWriteTests`, Atlas §9). `[evidence_level: code_verified, test_verified, confidence: high]` Reconciliation between two devices has no test coverage. |
| StoreKit 2 | `Services/Billing/`, `EntitlementStore.swift` | Entitlement state cannot refresh. Must degrade toward the user keeping what they paid for, never toward revoking it. |
| Core ML reranker | `Resources/MLModels/ReRankerModel.mlpackage` | The cross-encoder drops out and `RAGEngine.rerank` ranks candidates with its heuristic fallback instead, logging a warning; scores are not comparable to a cross-encoder run. `[evidence_level: code_verified, confidence: exact, evidence_source: RAGEngine.swift:329-346]` Bound to `ibm-granite/granite-embedding-reranker-english-r2` (since 5.8; `cross-encoder/ms-marco-TinyBERT-L2-v2` through 5.7) by exact path in `THIRD_PARTY_NOTICES.md`, which is the provenance of record. Two fixed-shape functions, `len256` and `len512`, run on the Neural Engine; built by `scripts/build_reranker_model.py`. |

Nothing else is external. There is no server operated by this project and no third-party AI service
in the path, which is a product guarantee rather than a current state.
