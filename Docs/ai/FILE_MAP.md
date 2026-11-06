# File map of the split files

Which file holds what, for the large Swift files split by job on 2026-11-05 (5.8). Read this when a file named in an
older doc, commit or citation no longer has the line it names, or before editing one of these types. A line of an old
file: `python3 scripts/split_linemap.py File.swift:N`. Moved here from `Docs/ai/ARCHITECTURE.md` on 2026-11-06 so the
every-task read set does not grow (`test_every_task_loads_only_the_small_universal_set`).

## The two largest types, by file (split 2026-11-05)

`RAGService` and `AgenticOrchestrator` were one file each, 23,427 and 9,447 lines (391,593 and 161,551 tokens by
Anthropic's counter). On 2026-11-05 each was split into extension files by job, moving whole sections unchanged; the
only edits were access keywords (`private` removed from 236 declarations another file now uses).
Every caller is unchanged: an `extension RAGService` in another file is the same type. A line cited as
`RAGService.swift:N` or `AgenticOrchestrator.swift:N` before then is found with `python3 scripts/split_linemap.py
RAGService.swift:N` (map in `Docs/ai/split-2026-11-05-linemap.json`, lines as of `e68facb2`).

| File (`Services/RAG/Orchestration/`) | Lines | Holds |
|---|---|---|
| `RAGService.swift` | 1,364 | the class: stored and published state, dependencies, setup, model service, the extension files' stored properties |
| `RAGService+Types.swift` | 337 | audit snapshot, retrieval log entry, ingestion context and the other small types |
| `RAGService+ChatHistory.swift` | 1,122 | chat history, evidence threads, transcript persistence, the import queue's saved state |
| `RAGService+Consent.swift` | 408 | Private Cloud Compute consent, pipeline tracing |
| `RAGService+StandardRetrieval.swift` | 1,309 | Standard's retrieval helpers: cross-references, spec-table sniper, section boost, lexical relevance, contextual retrieval |
| `RAGService+SentenceExtraction.swift` | 726 | sentence-level extraction for lookups |
| `RAGService+Storage.swift` | 1,509 | document persistence, workspace reload, vector store access |
| `RAGService+Import.swift` | 3,346 | document management: `addDocument` (1,443 lines), the queue, rebuilds, re-embedding, deferred enrichment |
| `RAGService+Deletion.swift` | 943 | deleting with undo |
| `RAGService+SelfTuning.swift` | 271 | self-tuning |
| `RAGService+AgenticQuery.swift` | 931 | thinking timeline, `executeAgenticQuery` (Deep Think and Maximum entry) |
| `RAGService+QueryPipeline.swift` | 5,950 | Standard's question path, nearly all one function, `queryInternal` (5,824 lines) |
| `RAGService+Generation.swift` | 1,936 | direct chat fallback, context homogeneity, model routing after retrieval, `generateWithFallback` |
| `RAGService+AnswerFinishing.swift` | 1,957 | content classification, response finishing and cleanup, precision-lookup overrides, corrective retrieval |
| `RAGService+Device.swift` | 612 | device capability and chip detection, `RAGServiceError` |
| `RAGService+ToolHandler.swift` | 1,102 | `RAGToolHandler`, including `executeFullRetrievalPipeline` (Deep Think's and Maximum's search) |

| File (`Services/Agentic/`) | Lines | Holds |
|---|---|---|
| `AgenticOrchestrator.swift` | 987 | the class, its state, `executeHoldingAnswerStream` (Deep Think's run) |
| `AgenticOrchestrator+Types.swift` | 358 | `ThinkingStep`, `AgenticConfig`, `AgenticResult`, chain and cluster configs, `AgenticError` |
| `AgenticOrchestrator+Retrieval.swift` | 1,719 | retrieval quality, evidence budget, step executors, `executeMultiQuerySearch`, cross-references, graph expansion |
| `AgenticOrchestrator+Research.swift` | 511 | the recursive research loop |
| `AgenticOrchestrator+SelfRAG.swift` | 1,210 | Self-RAG, Self-RAG 2.0 verification and citations, speculative RAG |
| `AgenticOrchestrator+ReasoningChain.swift` | 1,317 | `executeReasoningChain` (Deep Think's sessions) |
| `AgenticOrchestrator+Maximum.swift` | 1,539 | `executeTrueUnlimitedReasoning` (Maximum) |
| `AgenticOrchestrator+MultiChain.swift` | 1,536 | multi-chain execution |
| `RAGService+Agentic.swift` | 374 | the `RAGService` extension the orchestrator uses |

`[evidence_level: measured, confidence: exact, evidence_source: wc -l after the split; the move check that every original line is in the new files once, access keywords aside]`

## The other large files, by file (split 2026-11-05)

Fifteen more files, 60,585 lines in all, were split the same way that night: whole sections or whole types moved into files named for their job, the only code edits `private`/`fileprivate` removed where another file now uses a declaration. Each move was checked line by line (`BenchmarkRuns/2026-11-05-file-split/prove_move.py`: every original line once, none added, blank lines counted, each file in the original order), for calls that could bind to a different declaration once a `private` one moved to another file (`overload_check.py`, `widen_overload_sets.py`, `widen_check.py`), and on iOS and macOS builds. `python3 scripts/split_linemap.py File.swift:N` gives where a line of the old file went; the commit before each split is under `_bases` in `Docs/ai/split-2026-11-05-linemap.json`.

| Old file | Lines before | Now | What went where |
|---|---|---|---|
| `ChatScreen.swift` (`Features/Chat/Conversation/`) | 4,922 | 9 files, largest 1,588 lines | `+Body`: `body`, its lifecycle and presentation layers, the metrics bar and live metrics, the screenshot demo seed. `+Actions`: starter prompts, suggestions, history, export, new/clear/stop/regenerate/go deeper, illustrate, transform actions. `+Content`: the main content views. `+Sending`: sending, attachments, the Maximum paywall, toasts. `+Streaming`: streaming cadence, partial answers, error text. |
| `DocumentProcessor.swift` (`Services/Document/Processing/`) | 10,669 | 12 files, largest 2,690 lines | `+Import`: `processDocument`. `+TextExtraction`: page text and structure inference. `+PDFText`: text quality, headers and footers, PDF loading. `+StructuredParsing`: Apple's structured parsing. `+TokenLimits`: token limits and coverage checks. `+ImagesAndOCR`, `+Layout`, `+TablesAndTextFiles` (tables, text files, JSON records), `+MediaAndOffice` (audio and video, Office and iWork), `+Checkpointing`, `ZIPArchive`. Stays: configuration, GPU, tracing, progress, chunking strategy. |
| `SettingsView.swift` (`Features/Settings/`) | 3,684 | 8 files, largest 809 lines | `+List` (the index and root list), `+Account` (hero, billing), `+ModelAndCloud` (model, Private Cloud Compute, shared-workspace sync), `+Device` (context window, silicon, GPU), `+Modes` (generation, retrieval, mode features), `+AppleIntelligence`, `+AppearanceAndSupport`. |
| `AdaptiveVisualizationsView.swift` (`Features/Telemetry/Visualizations/`) | 3,238 | 5 files, largest 1,072 lines | Nine views; the four other groups moved whole into files named for them. |
| `UnifiedMetricsBar.swift` (`Features/Chat/Response/`) | 4,800 | 8 files, largest 835 lines | `+CompactStrip` (the two-row strip and premium badges), `+Badges`, `+DetailsPanel`, `+ReasoningAndSearch`, `+RunSections`, `+CompactRows`, `+IntelligenceCard`. Stays: the audit data (the struct's stored properties, so its memberwise initializer) and the format helpers. |
| `Embedding3DView.swift` (`Features/Telemetry/Visualizations/`) | 5,134 | 9 files, largest 1,348 lines | `EmbeddingSpaceRenderer+Panels`, `+SearchAndHelp`, `+Stats`, `+Data`; `Embedding3DSceneView`, `AtlasChart3D`, `SceneViewContainer`, `SceneConstruction` (the scene-building functions) moved whole. Every new file repeats the file's `#if canImport(SceneKit)`. |
| `LLMService.swift` (`Services/LLM/`) | 2,326 | 2 files, largest 1,925 lines | The Apple Foundation Models service, one class inside `#if canImport(FoundationModels)`, moved whole. Stays: the protocols, streaming and usage types, the mock and unavailable services, `LLMError`. |
| `SemanticChunker.swift` (`Services/Document/Chunking/`) | 2,325 | 5 files, largest 792 lines | `+Chunking`, `+Structure`, `+Boundaries`, `+Extraction`. The class is `nonisolated`, so each file is a `nonisolated extension` (a plain extension would make the moved methods main-actor isolated under this module's default isolation). |
| `SuggestedQuestionsService.swift` (`Services/Query/UX/`) | 4,463 | 6 files, largest 1,717 lines | One file per step: `+Bank` (bank and API), `+ChunkSelection`, `+LLMGeneration`, `+ContentFallback` (steps 3 and 4), `+Grounding`. |
| `SQLiteFullTextService.swift` (`Services/Storage/`) | 3,684 | 6 files, largest 1,068 lines | `+Documents`, `+Chunks`, `+Search`, `+Statistics`, `+ContentReader`. The schema (initialization, migrations, column helpers) stays in the main file, unchanged. Hard boundary: the owner names it before an edit. |
| `WorkspaceSyncService.swift` (`Services/Infrastructure/Storage/`) | 4,275 | 7 files, largest 769 lines | `+Bootstrap`, `+LibrarySync`, `+Merging`, `+Artifacts`, `+Reconciliation`, `+FileCoordination`, cut at member boundaries (no section markers). Hard boundary across all of them. |
| `VisualizationsView.swift` (`Features/Telemetry/Visualizations/`) | 3,661 | 10 files, largest 612 lines | 35 views; groups moved whole into files named for the view they serve, plus `VisualizationMath`. |
| `DatabaseDashboardView.swift` (`Features/Database/`) | 2,806 | 8 files, largest 539 lines | `+Header`, `+Overview`, `+Index`, `+MaintenanceAndSearch`; `DatabaseSupportingViews`, `LibraryIntelligenceCard`, `DocumentPreviewSheet` moved whole. |
| `ContainerSettingsSheet+Sections.swift` (`Features/Documents/Settings/`) | 2,001 | 6 files, largest 648 lines | `ContainerSettingsSheet+Chunking`, `+Intelligence`, `+Search`, `+NerdStats`; `ChunkingPreview` moved whole. |
| `DocumentLibraryView.swift` (`Features/Documents/Library/`) | 2,597 | 5 files, largest 709 lines | `+DocumentList`, `+SharedWorkspace`, `+Body`, `+Actions`, cut at member boundaries (no section markers). Stays: the view's state and derived values. |

`[evidence_level: measured, confidence: exact, evidence_source: wc -l after each split; prove_move.py on each split's plan in BenchmarkRuns/2026-11-05-file-split/plans]`

