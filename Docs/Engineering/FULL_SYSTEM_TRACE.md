# OpenIntelligence Full System Trace

> **Documentation status:** Written 2026-09-01 against commit `4840078` (main, working tree clean
> apart from this file). Every file:line below was read from that tree on that date, either
> directly or through a delegated inventory that was then re-checked line by line. Line numbers
> drift; the symbol names do not, so re-verify with the commands in §11 before quoting a number.
> `[evidence_level: code_verified, confidence: exact_for_symbols_high_for_line_numbers]`

This is the execution trace: what actually runs, in what order, on which thread, on which piece
of silicon, with what data volume, and what each stage throws away. It covers process launch,
navigation, ingestion, a Standard query, the agentic modes, the hardware and concurrency map, the
platform split, and a claims audit of the two documents that came before it.

Two earlier documents describe this app and this one is meant to be read after them:

- **How OpenIntelligence Works** (Claude Opus 5, 2026-08-10, republished 2026-08-22). The
  explanation of *why* each part exists, written for a walkthrough. About 10,900 words. Its
  hardware placement is thin and one of its claims is wrong (§9).
- **OpenIntelligence Audio Study Guide, Version 2** (GPT-5.6 Terra, 2026-08-27). The controlled
  vocabulary: 612 concepts, each with a status label and code anchors. About 94,000 words. All
  153 source paths it cites exist. It is a glossary in pipeline order, not an execution trace.

What neither does is say which unit executes a stage and how the code decides that. That is the
spine of this document.

---

## 0. How to read hardware placement claims

Code on Apple platforms does not place work on a unit. It *requests* one, and four different
mechanisms exist in this app, with very different evidentiary weight:

| Mechanism | What the code can actually control | Where it appears | Evidence weight |
|---|---|---|---|
| `MLModelConfiguration.computeUnits` | A permitted set: `.cpuOnly`, `.cpuAndGPU`, `.cpuAndNeuralEngine`, `.all`. Core ML then places each layer where it will run; the Neural Engine is never guaranteed. | Embedding model, reranker, classifiers, region detector, extractive QA stub | Strong. The line exists and can be read. |
| Metal compute pipeline | Explicit. If a command buffer is committed, the GPU ran it. | Vector similarity, batch normalisation, MMR diversity matrix | Exact. |
| Accelerate (`vDSP_*`, `BNNS`) | CPU SIMD. Never leaves the CPU. | Cosine similarity below the GPU threshold, norms, pooling | Exact. |
| Framework-decided | None. Vision, Speech, NaturalLanguage and FoundationModels choose internally and expose no placement API. | OCR, structured document parsing, transcription, NER, every LLM call | Only "the framework decides". Any document that says "OCR runs on the Neural Engine" is repeating an Apple marketing claim or a code comment, not reading a placement. |

The app has no way to measure Neural Engine occupancy either. The hardware HUD's "Neural Engine"
pulse is a synthetic activity signal, not a reading
(`Services/Infrastructure/Monitoring/HardwareTelemetryState.swift`).
`[evidence_level: code_verified, confidence: high]`

---

## 1. Launch: process start to first interactive screen

All paths below are under `OpenIntelligence/` unless stated.

### 1.1 Timeline

| # | What runs | Where | Thread | Sync on launch path? | What it loads or arms | Unit | Evidence |
|---|---|---|---|---|---|---|---|
| 1 | `OpenIntelligenceApp.init` | `App/OpenIntelligenceApp.swift:17-40` | Main | Yes | DEBUG validation harness; disables Catalyst window tabbing; wires `IngestionRuntimeBridge` and the query bridge to `BackgroundTaskService`; `AppTipConfiguration.configure()`; `registerBackgroundTasks()` under `#if os(iOS)` | CPU | code_verified / exact |
| 2 | `BGTaskScheduler.shared.register` ×5 | `App/OpenIntelligenceApp.swift:141-186` | Main | Yes (iOS only) | Identifiers: `com.openintelligence.document-ingestion`, `com.openintelligence.rag-query`, `com.openintelligence.index-maintenance`, `com.openintelligence.spotlight-reindex`, `com.openintelligence.app-refresh` (`Services/Infrastructure/Background/BackgroundTaskService.swift:133-137`) | CPU | code_verified / exact |
| 3 | `WindowGroup { ContentView() }` | `App/OpenIntelligenceApp.swift:41-45` | Main | Yes | Scene | CPU | code_verified / exact |
| 4 | `ContentView.init` | `App/ContentView.swift:27-60` | Main | Yes | Constructs, in order: `WorkspaceSyncService`, `ContainerService`, `StoreKitBillingService`, `EntitlementStore`, `RAGService`, `SettingsStore`, `ModelResolutionService`, `OnboardingStateStore`, `WhatsNewStore` | CPU | code_verified / exact |
| 5 | `StoreKitBillingService.init` | `Services/Billing/StoreKitBillingService.swift:24-29` | Main → Task | Deferred | Spawns the `Transaction.updates` listener (`:306`) that runs for the life of the process | CPU | code_verified / exact |
| 6 | `RAGService.init` | `Services/RAG/Orchestration/RAGService.swift:1537-1570` | Main | Yes | `DocumentProcessor()`, `DocumentSummaryService()`, `EmbeddingService()`, `VectorStoreRouter()`, `ContextPackingService`, `ExtractiveSummarizationService` | CPU | code_verified / exact |
| 7 | `EmbeddingService.init` → `CoreMLSentenceEmbeddingProvider.setup` | `Services/Embedding/EmbeddingService.swift:57-58`, `Services/Embedding/Providers/CoreMLSentenceEmbeddingProvider.swift:174-181` | Main → Task | Deferred | Loads only the Rust-backed tokenizer (`AutoTokenizer.from(directory:)`, `:242`). **The embedding model is not loaded at launch.** It loads on first `embed()` (`:183-194`) | CPU | code_verified / exact |
| 8 | `RAGEngine.init` | `Services/RAG/Orchestration/RAGEngine.swift:69-71` | Task | Deferred | `setupReRanker()` loads `ReRankerModel.mlmodelc` with `computeUnits = .all` and `allowLowPrecisionAccumulationOnGPU = true` (`:84-88`), plus its tokenizer (`:112`) | Core ML, unit requested `.all` | code_verified / exact |
| 9 | `DeviceCapabilityService.shared` | `Services/Infrastructure/Monitoring/DeviceCapabilityService.swift:275, 293-320` | First access, Main | Yes, on first touch | `utsname` (`:1038`), `sysctlbyname("machdep.cpu.brand_string")` (`:1104, 1139`), `ProcessInfo.physicalMemory` (`:1122, 1578`), `MTLCreateSystemDefaultDevice()` for the Metal snapshot (`:1583`). Produces tier, chip, form factor, TOPS, memory, Metal limits | CPU + a Metal device handle | code_verified / exact |
| 10 | `SQLiteFullTextService.shared` | `Services/Storage/SQLiteFullTextService.swift:75` | Actor | Lazy | Nothing at launch. `ensureInitialized()` (`:162`) opens the database on first use: `sqlite3_open` (`:172`), `PRAGMA journal_mode=WAL` (`:183`), `PRAGMA busy_timeout=3000` (`:184`), then creates nine tables (§3.6) | CPU, disk | code_verified / exact |
| 11 | `BNNSVectorDatabase` per container | `Services/VectorStore/BNNSVectorDatabase.swift:116-223` | Actor | Deferred | On load: metadata JSON to heap, `_norms.bin`, and `_vectors.bin` memory-mapped with zero heap copy (`:223`). Legacy JSON stores migrate once (`:235-278`) | CPU, mmap | code_verified / exact |
| 12 | `ContentView.body` → `TabView` | `App/ContentView.swift:259-301` | Main | Yes | Five tabs: Chat (`:261`), Documents (`:269`), Atlas (`:281`), Database (`:291`), Settings (`:301`). Onboarding overlay at `:91` when `onboardingStore.isChecklistVisible` | CPU | code_verified / exact |
| 13 | `ContentView.task` | `App/ContentView.swift:214-227` | MainActor async | After first frame | `billingService.refreshProducts()`, `reconcileEntitlementsOnLaunch()`, `refreshSharedWorkspaceIfNeeded(forceReload: true)`, and sample import when screenshot mode asks for it | CPU, network (StoreKit), iCloud | code_verified / exact |
| 14 | `IngestionLiveActivityService.restoreExistingActivityIfNeeded` | `App/OpenIntelligenceApp.swift:79` | Main | Deferred | Reattaches to a Live Activity left over from a previous process | CPU | code_verified / exact |

Nothing on the launch path touches the GPU or requests the Neural Engine except the reranker
load in row 8, and that runs in a detached task. First-query latency is therefore paid at the
first query, not at launch: the embedding model compiles on first `embed()`, and the FTS database
opens on first access. `[evidence_level: code_verified, confidence: high]`

### 1.2 Timers and periodic work armed at launch

| Source | Interval or trigger | Where | Purpose | Evidence |
|---|---|---|---|---|
| `Transaction.updates` | Continuous stream | `Services/Billing/StoreKitBillingService.swift:306` | StoreKit transaction listener | code_verified / exact |
| Workspace change debounce | 2.0 s on main | `Services/Infrastructure/Storage/WorkspaceSyncService.swift:321` | Coalesces local workspace changes before a reconfigure pass | code_verified / exact |
| `BGProcessingTask` index maintenance | Earliest 4 h, requires external power | `Services/Infrastructure/Background/BackgroundTaskService.swift:186-188` | Vector compaction and index maintenance | code_verified / exact |
| `BGProcessingTask` Spotlight reindex | Earliest 2 h | `…/BackgroundTaskService.swift:201-203` | Spotlight reindex | code_verified / exact |
| `BGAppRefreshTask` | Earliest 30 min | `…/BackgroundTaskService.swift:216` | App refresh | code_verified / exact |
| Chat UI clock | `Timer.publish(every: 0.2)` | `Features/Chat/Conversation/ChatScreen.swift:221` | Streaming UI tick | code_verified / exact |
| Thermal, memory, battery, low-power observers | Notification | `Services/Infrastructure/Monitoring/SystemStateMonitor.swift:523, 599` | Feeds `AdaptivePipelineOptimizer` | code_verified / exact |
| **Idle churn** | **1.68 s, indefinitely, while idle** | Trigger in `WorkspaceSyncService`; damage bounded in `Services/VectorStore/VectorStoreRouter.swift:248-262` | `reloadWorkspaceData()` fires every 1.68 s when a container's orphaned state never resolves. On 2026-08-29 it produced 2,848 vector loads in 164 idle seconds. The router now compares an on-disk signature first, so idle reloads are free. **The trigger itself is untouched**, which is the open item in `Docs/ai/STATE.md` | code_verified / exact |

---

## 2. Navigation: what each screen can start

Root is `TabView(selection:)` at `App/ContentView.swift:259`, each tab in its own
`NavigationStack`. iOS and macOS share this tree; platform differences are local (`#if os`,
`#if targetEnvironment(macCatalyst)`, `fullScreenCover` versus `sheet`).
`[evidence_level: code_verified, confidence: exact]`

| Tab | View | Heavy work it can start | Where the call leaves the UI |
|---|---|---|---|
| Chat | `ChatScreen` (`Features/Chat/Conversation/ChatScreen.swift:185`) | The full query pipeline (§4) via `sendMessage(_:)` (`:2489`) → `ragService.query(text, topK:, config:)` (`:2665-2740`); Writing Tools transforms; cloud-consent sheet (`:812`) | `Task` off the main actor, streaming back through `LLMStreamingContext` |
| Documents | `DocumentLibraryView` (`Features/Documents/Library/DocumentLibraryView.swift:37`) | Ingestion (§3) via `reviewAndEnqueueDocuments(urls)` (`:1330`) → `RAGService.enqueueDocuments` (`RAGService.swift:4667`); sample import; reindex and re-embed of a whole container (`ContainerSettingsSheet+Sections.swift:120`); wipe | `MainActor` enqueue, then the serial ingestion loop (§3.1) |
| Atlas | `AdaptiveVisualizationsView` (`Features/Telemetry/Visualizations/AdaptiveVisualizationsView.swift:15`) | `LibraryVisualizationEngine.shared.analyze(containerId:)` on appear: dimensionality reduction over every vector in the container, then SceneKit for the 3D atlas (`Embedding3DView.swift`) | Background `Task`; SceneKit renders on the GPU |
| Database | `DatabaseDashboardView` (`Features/Database/DatabaseDashboardView.swift:13`) | FTS5 statistics, optimize, rebuild, vacuum, integrity check, search benchmark, K-means cluster labelling with LLM naming (`:151-163`) | Background `Task` with a watchdog |
| Settings | `SettingsView` (`Features/Settings/SettingsView.swift:16`) | GPU profile change (`DeviceCapabilityService.shared.setGPUProfile`, `:1826`), iCloud sync toggle (`:1054`), model configuration sheet, developer diagnostics hub with benchmark and validation runs | `MainActor`, then whatever the service does |

Seven settings keys have a UI and no reader in the service layer:
`enableWritingTools`, `enableSpeechAnalysis`, `enableTranslation`, `useHighAccuracyEmbeddings`,
`enableScreenAwareness`, `enableADM3Visuals`, `enableRAGEvaluations`. The first three are
acknowledged in a comment at `Features/Settings/SettingsView.swift:2626`. Flipping them changes
nothing. `[evidence_level: grep_verified, confidence: high]`

Seventeen App Intents exist (`Services/Agentic/RAGAppIntents.swift`,
`VisualIntelligenceIntents.swift`, `ScreenAwarenessIntents.swift`). The query intents all resolve
to `RAGService.query`, so a Siri question runs the same §4 pipeline in the background with
`openAppWhenRun: false`. The ingestion Live Activity starts with `Activity.request` at
`Services/Infrastructure/Background/IngestionLiveActivityService.swift:80`, updates throttled to
0.5 s at `:59`, and ends with a ten-minute retention at `:139`.
`[evidence_level: code_verified, confidence: exact]`

---

## 3. Ingestion: file URL to queryable chunks

### 3.1 Control flow

| # | Stage | Entry | Concurrency | Evidence |
|---|---|---|---|---|
| 1 | Enqueue | `RAGService.enqueueDocuments` (`RAGService.swift:4667`), item state `.queued` (`:4681`) | `MainActor` | code_verified / exact |
| 2 | Serial loop | `RAGService.runIngestionLoop` (`:4969`): `while let next = nextQueuedIngestionItem()` → `addDocument` (`:5356`) | **One document at a time.** Parallelism exists only inside a document (pages, embeddings) | code_verified / exact |
| 3 | iCloud materialisation guard | `WorkspaceSyncService.ensureItemAvailableLocally(at:timeout: 20)` (`Services/Infrastructure/Storage/WorkspaceSyncService.swift:850`) | Blocks the document up to 20 s while iCloud downloads a placeholder | code_verified / exact |
| 4 | Stage `.loading` | `RAGService.swift:5576` | | code_verified / exact |
| 5 | Parse and chunk | Step 1 at `:5644` → `DocumentProcessor.processDocument` (`Services/Document/Processing/DocumentProcessor.swift:569`) | See §3.2 | code_verified / exact |
| 6 | Auto-adapt configuration | Step 1.5 at `:5787-5980`, stage `.analyzing` | | code_verified / exact |
| 7 | Embed | Step 2 at `:6011`, stage `.embedding` (`:6099`) | See §3.4 | code_verified / exact |
| 8 | Build chunk records | Step 3 at `:6172` | | code_verified / exact |
| 9 | Store vectors | Step 4 at `:6229`: `db.storeBatch(chunks:)` (`:6251`), `db.persist()` (`:6252`) | Actor-serialised | code_verified / exact |
| 10 | Spotlight chunks | Step 4.0.0 at `:6259` (if enabled) | | code_verified / exact |
| 11 | Store chunk rows in FTS5 | Step 4.0.1 at `:6291`, `SQLiteFullTextService.shared.storeChunks` (`:6333`), stage `.indexing` | Actor | code_verified / exact |
| 12 | Learn vocabulary and Vision entities | Steps 4.1 and 4.1b at `:6340, 6358` | | code_verified / exact |
| 13 | Document summary (RAPTOR-lite L1) | Step 4.5 at `:6383` (if enabled) | One LLM call | code_verified / exact |
| 14 | Persist vector store again | Step 4.9 at `:6452-6454` | | code_verified / exact |
| 15 | Content tags | Step 5 at `:6456` (iOS 26+ tagging model) | | code_verified / exact |
| 16 | State update, `.complete` | `:6604`, `:6654` | | code_verified / exact |

The full document text goes into the FTS `documents` table **before** chunking, from inside
`processDocument` (`DocumentProcessor.swift:642, 813` → `SQLiteFullTextService.store(text:for:containerId:)`
at `SQLiteFullTextService.swift:362`). Chunk rows are written after embedding (row 11). So a
document that fails between rows 5 and 11 is lexically searchable at document level and absent
from both chunk indexes. `[evidence_level: code_verified, confidence: high]`

### 3.2 Extraction, by input type

Dispatch is on file extension and `UTType` at `DocumentProcessor.swift:9428-9538`: `pdf`, `csv`,
image, audio, audiovisual, with Office and text formats handled on other branches of the same
switch. Files over 500 MB that cannot be streamed are rejected before reading (`:681-683`).
`[evidence_level: code_verified, confidence: exact]`

| Input | What runs | Unit | Concurrency | Evidence |
|---|---|---|---|---|
| PDF with a text layer | `PDFPage.string` per page. First, text-layer validation (`:3220-3262`): the longest page sample of at least 50 characters is rendered and given a quick OCR pass; if the native text is garbled, every page is routed to OCR instead | CPU | Page loop | code_verified / exact |
| PDF page raster | `renderPDFPageAsImage(page:scale: 5.0)` (`:6978`), which is 360 DPI. iOS draws through `UIGraphicsImageRenderer` with an opaque format (`:7018-7050`); macOS draws into a `CGContext` with `noneSkipLast` (`:7061-7090`), written to replace the deprecated `NSImage.lockFocus` | CPU (Quartz). Not the GPU | Bounded by `pdfRenderingConcurrency` (§6.3) and sub-batched by `maxRenderConcurrency` (`:4149`) | code_verified / exact |
| Page complexity triage | `PageComplexityAnalyzer` renders at 144 DPI (`Services/Document/Chunking/PageComplexityAnalyzer.swift:1048`) to decide which pages need the structured parser | CPU | | code_verified / exact |
| Scanned or photographed page, OCR | `VNRecognizeTextRequest` (`:7510`), configured by `OCRConfiguration.configure` (`Services/Document/Config/OCRConfiguration.swift:191-202`): `.accurate`, `usesLanguageCorrection = true`, and either the languages detected for this document with `automaticallyDetectsLanguage = false`, or all thirteen configured languages with auto-detect on. Narrowing landed 2026-08-29 | **Framework-decided.** Vision does not expose placement | `VisionOCRThrottle` async semaphore sized by `DeviceCapabilityService.visionOperationConcurrency`, with a GPU cooldown between operations (`Services/Document/Config/VisionOCRThrottle.swift:100-110, 159`) | code_verified / exact |
| Layout, tables, structure | `RecognizeDocumentsRequest` in `StructuredDocumentParser.swift:680`, `IntelligentDocumentProcessor.swift:847`, `CoreMLRegionDetector.swift:429`. Structure pass at 180 DPI downscaled, or the full 360 DPI for high-risk pages (`StructuredDocumentParser.swift:598-641`) | **Framework-decided.** The code comment at `DocumentProcessor.swift:4080` says Neural Engine; that is a comment, not a placement | `withTaskGroup` over pages (`:3547`) bounded by `visionParsingConcurrency` (`:4084`) | code_verified for the calls / inferred for the unit |
| Office (docx, xlsx, pptx) | Unzip, then `StreamingXMLProcessor` over the XML parts | CPU | | code_verified / high |
| CSV | RFC 4180 parse, table rows also stored in `chunk_table_rows` | CPU | | code_verified / high |
| Images | Vision OCR as above, plus captioning and classification: `YOLODetectionService` (`computeUnits = .all`, `Services/Document/Classification/YOLODetectionService.swift:80`), `CoreMLRegionDetector` (`.all`, `:177`), `CoreMLDocumentClassifier` (`.cpuAndNeuralEngine`, `:223`) | Core ML, units as listed | | code_verified / exact |
| **Audio and video** | `DocumentProcessor.swift:8775` → `SpeechAnalyzerService`. **The `SpeechAnalyzer` branch never compiles**: it is guarded by `#if canImport(SpeechAnalyzer)` (`Services/Document/Analysis/SpeechAnalyzerService.swift:17, 94, 141, 160`) and no module of that name exists; the iOS 27 SDK ships `SpeechAnalyzer` inside `Speech.framework`. Even under `canImport(Speech)` the code would not compile, because it calls `analyzer.results(for: url)` and `bestTranscription`, which the SDK's `SpeechAnalyzer` actor does not declare (it uses `SpeechTranscriber` modules and `analyzeSequence`). Every build therefore takes `legacyTranscription` (`:237-243`) → `AudioTranscriptionService` (`Services/Document/Extraction/AudioTranscriptionService.swift`): `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` (`:217`) in segments of at most 600 s (`:81`) | **Framework-decided** (Speech). On-device is enforced by the request flag | Sequential segments | code_verified / exact, SDK checked at `/Applications/Xcode-beta.app/…/iPhoneOS.sdk/…/Speech.framework/Modules/Speech.swiftmodule/arm64e-apple-ios.swiftinterface` |

### 3.3 Chunking and the token ceiling

| Constant | Value | Where | Evidence |
|---|---|---|---|
| Hard chunk ceiling | 310 words (`safeMaxSize`) | `Services/Document/Chunking/SemanticChunker.swift:156` | code_verified / exact |
| Largest target | 260 words (`safeMaxSize - 50`) | `:159` | code_verified / exact |
| Overlap cap | 50 words | `:161` | code_verified / exact |
| Smallest target | 100 words | `:163` | code_verified / exact |
| Technical-reference profile | `maxSize: 310` | `:180-183` | code_verified / exact |
| Embedding model limit | 510 tokens (`maxEmbeddableTokens`) | `DocumentProcessor.swift:6434` | code_verified / exact |
| Reserved for the contextual prefix | 80 tokens | `:6437` | code_verified / exact |
| Enforced per chunk | 430 tokens (`safeTokenLimit`) | `:6440`, enforced by `enforceTokenLimitOnChunks` (`:6479`) using the real tokenizer (`CoreMLSentenceEmbeddingProvider.countTokens`, `:283-288`) | code_verified / exact |

The reason this exists is in the ledger: a padding block once made the token counter a constant,
and 55% of every document was silently truncated at embedding while every log line read healthy.
The counter now goes through the same tokenizer the model uses. Chunks that are still oversized
after splitting are logged at `:6670` and will be truncated by the model.
`[evidence_level: code_verified, confidence: high]`

### 3.4 Embedding

| Aspect | Fact | Where | Evidence |
|---|---|---|---|
| Provider selection | Default `coreml_sentence_embedding`. On iOS 27 and macOS 27 with `CoreAI` importable, `SettingsStore` resolves the default to `coreai_sentence_embedding` and auto-migrates a saved Core ML default | `Services/Infrastructure/Configuration/SettingsStore.swift:531-544`; `EmbeddingService.swift:127-146` | code_verified / exact |
| Core AI provider | `@available(iOS 27, macOS 27)`, loads `EmbeddingModel.bundle/main.mlirb` through `AIModel(contentsOf:)`. `CoreAI.framework` is present in the installed iOS 27 SDK. Pooling reads the CLS row; the Core ML path mean-pools. The vector space is the same 384 dimensions | `Services/Embedding/Providers/CoreAISentenceEmbeddingProvider.swift:11-16, 104`; `CoreMLSentenceEmbeddingProvider.swift:70-73` | code_verified / exact |
| Core ML provider load | Lazy, on first `embed()`. `MLModel(contentsOf: EmbeddingModel.mlmodelc, configuration:)` with `computeUnits` from `DeviceCapabilityService.preferredComputeUnits`; during ingestion the model is reloaded with `embeddingComputeUnitsDuringIngestion` (`enableIngestionMode`, `:137-165`) | `CoreMLSentenceEmbeddingProvider.swift:183-232` | code_verified / exact |
| Compute units by profile | Query and reranker path: Efficiency and Balanced → `.cpuAndNeuralEngine`; Performance and Maximum → `.all`. Ingestion embedding: Efficiency → `.cpuAndNeuralEngine`; everything else → `.all`. Maximum used to return `.cpuAndGPU`, which **excluded** the Neural Engine and was slower than Performance; fixed 2026-08-26 | `DeviceCapabilityService.swift:812-821, 844-851` | code_verified / exact |
| One inference | Tokenise (`Tokenizers`), fill pooled `MLMultiArray` triples (`input_ids`, `attention_mask`, `token_type_ids`, sequence length 512, pool at `:21-54`), `model.prediction(from:)` (`:350`), attention-masked mean pool over `last_hidden_state` (`:364-368`), L2 normalise with vDSP, clamped so a zero vector cannot divide by zero | `CoreMLSentenceEmbeddingProvider.swift:300-430` | code_verified / exact |
| Batch | `embedBatch`: sequential for four or fewer texts, else `withThrowingTaskGroup` with width `DeviceCapabilityService.embeddingConcurrency` (§6.3) | `:442-480` | code_verified / exact |
| Data shape | Chunk text plus contextual prefix in; 384 `Float` out per chunk | | code_verified / exact |

Where does an embedding actually run? For the Core ML path the honest answer is: on whatever Core
ML picks within the permitted set. On the lower two GPU profiles the GPU is excluded, so it is CPU
or Neural Engine. On the upper two it may be any of the three. For Core AI the code has no
placement control at all. `[evidence_level: code_verified, confidence: high]`

### 3.5 Persistence and IDs

`BNNSVectorDatabase.persist()` (`:467`) → `saveToDisk()` (`:307`) writes `_vectors.bin`,
`_norms.bin` and a metadata JSON with `.atomic`, then re-maps the vector file. Chunks link to
documents by `DocumentChunk.documentId`; the same UUIDs are the `chunk_id` and `document_id`
columns in FTS5. There is no cross-store transaction: a crash between the vector persist (row 9)
and the FTS chunk write (row 11) leaves vectors without chunk rows, and the ingestion restore path
is what reconciles it. `[evidence_level: code_verified, confidence: high]`

### 3.6 The nine SQLite tables

`documents`, `chunks`, `document_pages` (FTS5), `documents_vocab` (fts5vocab), and the plain
tables `chunk_structured`, `chunk_table_rows`, `document_content`, `document_meta`,
`semantic_query_cache` (`SQLiteFullTextService.swift:191-321, 2170`). The `chunks` table indexes
`section_title`, `section_path` and `content`, tokenised `porter unicode61`, and leaves the IDs,
page number and structure type `UNINDEXED` (`:242-254`). `[evidence_level: code_verified, confidence: exact]`

### 3.7 What ingestion drops silently

| Point | Rule | Where |
|---|---|---|
| Whole file | Non-streamable and over 500 MB | `DocumentProcessor.swift:681` |
| Whole file | Duplicate of an already-imported document | `RAGService.swift:5405` |
| Whole file | Tier quota reached | `RAGService.swift:5490` (`DocumentQuotaError`) |
| Pages | Text-layer garble check routes the page to OCR; OCR confidence and noise filters strip strings | `DocumentProcessor.swift:3220-3262, 766` |
| Table cells | Uncertain numeric cells dropped from structure | `DocumentProcessor.swift:8481` |
| Chunk tail | Anything past 510 tokens after prefix, if a chunk is still oversized after the split pass | `DocumentProcessor.swift:6670` |
| Whole document | iCloud placeholder not materialised within 20 s | `WorkspaceSyncService.swift:850` |

Each of these is logged; none of them is surfaced as a count the user can see, which is the
failure class the ledger keeps recording. The `IngestionStageLedger`
(`Services/Document/Processing/IngestionStageLedger.swift`) now names the stage that dropped text.
`[evidence_level: code_verified, confidence: high]`

---

## 4. A Standard query: send to rendered answer

### 4.1 Entry

`ChatScreen.sendMessage(_:)` (`Features/Chat/Conversation/ChatScreen.swift:2489`) builds an
`InferenceConfig` from the settings sheet values (`:2665-2682`) and calls
`RAGService.query(_:topK:config:containerId:qualityModeOverride:externalEvidence:streamHandler:trace:)`
(`RAGService.swift:9012`), which binds the stream handler into a task-local and calls
`queryInternal` (`:9084`). `[evidence_level: code_verified, confidence: exact]`

`queryInternal` first resolves the run through `QueryRuntimeCoordinator.resolveContext`
(`:9130`), which decides the quality mode, PCC eligibility, adaptive configuration, the query
profile, and whether the run is agentic. If `runtimeContext.isAgentic` (`:9153`) the call leaves
for `executeAgenticQuery` (`:9187`) and §5 applies. Otherwise the steps below run in this order.
`[evidence_level: code_verified, confidence: exact]`

### 4.2 Stage table

Line numbers are in `RAGService.swift` unless a path is given.

| Step | Stage | What runs | Unit | Candidates in → out | Evidence |
|---|---|---|---|---|---|
| Cache | Semantic query cache | Exact hit reuses the cached vector and skips Step 2 (`:9427, 9845`); stored in `semantic_query_cache` | CPU | | code_verified / exact |
| 0 | Corpus vocabulary | Build or fetch the container's vocabulary (`:9449`) | CPU | | code_verified / exact |
| 1 | Query understanding | Optional LLM rewrite when `enableQueryRewriting` (`:9513`, reader at `:9508`), then corpus-aware expansion (`:9628-9687`) and answer-intent classification (`:9741`) | FoundationModels, framework-decided | | code_verified / exact |
| 2 | Query embedding | Same provider as ingestion, one text (`:9776-9800`) | Core ML or Core AI, as §3.4 | 1 vector | code_verified / exact |
| 3 | Hybrid search | `HybridSearchService.searchWithFTS5` (`Services/RAG/Retrieval/HybridSearchService.swift:1007-1060`): `async let` vector search and FTS5 search **in parallel**. Vector side asks for `topK × 3` (`× 2` when `topK > 50`, `:250`); FTS5 side `min(topK × 3, 60)` (`:1030`); structured rows `min(topK × 3, 36)` (`:1036`). Fusion is Reciprocal Rank Fusion with `k = 60` and weights vector 0.7, keyword 0.3 (`:208-211, 293-299`). Keyword hits that would fall below the cut are re-attached up to `max(4, topK / 6)` survivors (`:377`). Section-title and path boosts are applied afterwards (`:10453`) | See 4.3 | `initialTopK` is 30 in Standard (`Core/Models/RAGQualityMode.swift:74-80`), so 90 vector + up to 60 lexical candidates in, a fused ranked list out | code_verified / exact |
| 4 | Rerank | `RAGEngine.rerank` (`Services/RAG/Orchestration/RAGEngine.swift:294`) → `rerankWithCrossEncoder` (`:1404`): query and passage tokenised together to 512 tokens (`:1412`), `MLModel.prediction` per pair, concurrent via `withTaskGroup` (`:1516`). Called with `topK: effectiveTopK × 3` and trimmed to that (`:10502, 10535`) | Core ML, `computeUnits = .all`, low-precision GPU accumulation allowed (`RAGEngine.swift:86-87`) | Up to 90 pairs scored | code_verified / exact |
| 4.3 | Confidence filter | Drop below the mode's `minSimilarity`: 0.28 Standard, 0.25 Deep Think, 0.20 Maximum (`RAGQualityMode.swift:85-92`); procedural queries raise the bar (`:10822`); lenient mode lowers it (`:10784`) | CPU | | code_verified / exact |
| 4.4 | Document spread | Ensure more than one document is represented before diversifying (`:11018`) | CPU | | code_verified / exact |
| 4.5 | MMR | `RAGEngine.applyMMR` with `mmrLambda` 0.60 / 0.55 / 0.50 by mode (`RAGQualityMode.swift:210-217`). The pairwise similarity matrix goes to Metal when there are more than 50 candidates **and** `useMetalForVectorOps` **and** a GPU device exists (`RAGEngine.swift:155-160`), else CPU | GPU or CPU, decided at `RAGEngine.swift:158` | Diversified set | code_verified / exact |
| 4.6 | Expansion | Parent document retrieval when enabled (`:11548`, reader `:11551`), cross-reference resolution (`:11606`), targeted spec retrieval (`:11629`) | CPU + SQLite | | code_verified / exact |
| 4.7 | Contextual compression | Optional extractive sentence filtering (`:11659`, reader `:11668`), followed by a one-second cooldown to protect the Foundation Models rate budget (`:11828-11830`) | FoundationModels when enabled | | code_verified / exact |
| 4.9 | Graph-based packing | `ContextPackingService` (`:11861`; `Services/RAG/Retrieval/ContextPackingService.swift`) | CPU | | code_verified / exact |
| 5 | Context assembly | Off-main string build (`:12066`); extractive summarisation (`:12650`); extractive QA is disabled, generation always runs (`:12731`) | CPU | Chunks that do not fit the token budget are trimmed and their IDs recorded (`ContextPackingService.swift:208-218`) | code_verified / exact |
| Plan | Post-retrieval model plan | `makePostRetrievalModelPlan` (`:13038`, defined `:15439`) → `ModelExecutionPlanner.makePlan` (§4.4) | CPU | | code_verified / exact |
| 6 | Generation | `switch plan.synthesisTarget` (`:13050`): `.privateCloudCompute` (`:13051`), `.onDevice` and `.deterministic` (`:13120`), `.abstain` (`:13146`). Local generation goes through `LLMService` (§4.5) | FoundationModels, framework-decided; or PCC | | code_verified / exact |
| Gates | Verification | `VerificationGateService` (§4.6) | CPU, plus one embedding call for Gate E | Claims in, supported and unsupported claims out | code_verified / exact |
| Render | Structured answer | `StructuredAnswer` and citations mapped back to chunk offsets; route badge in `ResponseDetailsView` reads the completed route label (`Features/Chat/Response/ResponseDetailsView.swift:314-322`) | CPU | | code_verified / exact |

### 4.3 The vector search, exactly

`BNNSVectorDatabase.search(embedding:topK:)` (`Services/VectorStore/BNNSVectorDatabase.swift:486`):

1. `gpuThreshold = 1000` (`:501`). If the container holds at least 1,000 vectors **and**
   `GPUComputeService.isGPUAvailable` (`:505-507`; `isGPUAvailable` is "a Metal device and a
   command queue exist", `GPUComputeService.swift:196`), the whole memory-mapped buffer is handed
   to `batchCosineSimilarityFlatBuffer` (`:515`) with no heap copy. Inside, the threadgroup kernel
   `batchCosineSimilarityThreadgroup` is used at 1,000 or more documents when it is safe, else the
   SIMD kernel (`GPUComputeService.swift:764`). Kernels are compiled from Metal source at init
   (`:258-280`). Buffers come from a size-bucketed pool (`:94-143`) and, on Metal 4, a residency
   set (`:345-374`).
2. Otherwise the CPU path: if the count is at least
   `DeviceCapabilityService.batchMatrixMultiplyThreshold` (16 on M-series, `Int.max` on
   unsupported devices, `DeviceCapabilityService.swift:619`), one `vDSP_mmul` over the mapped
   buffer (`:536`), else one `vDSP_dotpr` per vector against the mapped pointer (`:365`).
3. Scores are normalised by the stored norms and the top `min(topK, count)` are selected.

So the sentence "GPU above a thousand chunks" has two hidden conditions (a Metal device, and a
successful kernel compile) and the CPU path has its own two-tier switch. Note that the user's GPU
execution profile does **not** gate this path; it gates MMR (`useMetalForVectorOps`) and Core ML
compute units. `[evidence_level: code_verified, confidence: exact]`

### 4.4 Where the answer is allowed to run

`ModelExecutionPlanner.makePlan` (`Services/RAG/Orchestration/ModelExecutionPlanner.swift:24-132`):

- `.abstain` when the evidence is judged insufficient (`:38`).
- `.deterministic` when a rule-based extractor can answer (`:70`).
- `.privateCloudCompute` only if the capability snapshot allows PCC, the network is available,
  the app is foreground-interactive or consent is already granted, **and** either the local
  budget does not fit or the query's complexity requests cloud synthesis (`:78-89`). Reason is
  recorded as `.localContextExceeded` or `.complexSynthesis`.
- `.onDevice` otherwise, with the reason (`.networkUnavailable`, `.consentUnavailable`, and so on).
- Every PCC plan carries an on-device fallback (`:107-108`). The plan has three stages: retrieve
  (deterministic), synthesise (the target), verify (deterministic) (`:118-120`).

The cloud payload is built by `CloudEvidenceMinimizer.makeEnvelope` (`:139-168`): chunks in rank
order, each cut to `min(remaining, max(240, maximumCharacters / min(count, 8)))` characters. That
truncation is silent in the payload; the plan records the budget it used.
`[evidence_level: code_verified, confidence: exact]`

Consent is asked only after retrieval, once the planner has selected PCC and built the minimised
payload (`RAGService.swift:11833-11834`). A denied consent forces `executionContext = .onDeviceOnly`
(`:11838-11844`). `[evidence_level: code_verified, confidence: exact]`

### 4.5 Route policy, session, generation

`FoundationModelRoutePolicy.determineRoute` (`Services/AIPlatform/AppleFoundationModels/FoundationModelRoutePolicy.swift:23-119`):

- With a plan attached, the plan wins: on-device for deterministic, on-device and abstain targets;
  PCC with reasoning `.none` (exact lookup, Standard), `.moderate` (Deep Think), `.deep` (Maximum)
  (`:28-47`).
- Without a plan: a manual preference of `core3B` or `advanced20B` forces on-device; a manual
  PCC preference forces PCC (`:50-57`). Otherwise the on-device window is read from
  `SystemLanguageModel.default.contextSize` rather than assumed to be 4,096 (`:71`;
  `FoundationModelTokenBudget.swift:28-33`), and PCC is chosen only when the estimated context
  exceeds it, PCC is allowed, and `isPCCAvailable()` (`:92, 99-101, 110-112`).
- `isPCCAvailable()` (`:121-132`) requires `compiler(>=6.4)`, iOS or macOS 27, the entitlement,
  and `PrivateCloudComputeLanguageModel().isAvailable && !quotaUsage.isLimitReached`. The
  installed toolchain is Swift 6.4, so this branch compiles.

`FoundationModelSessionFactory.createSession` (`FoundationModelSessionFactory.swift:24-110`):

- `.onDevice`: `SystemLanguageModel.default`, availability guard, then either
  `LanguageModelSession(model:tools:transcript:)` with `prewarm()` when a saved transcript is
  reused, or `LanguageModelSession(model:tools:instructions:)` (`:46-54`).
- `.onDeviceAdvanced` executes the **same default model**; the comment says no advanced on-device
  model exists in the SDK and telemetry is corrected to `.onDevice` (`:57-62`).
- `.privateCloudCompute`: `PrivateCloudComputeLanguageModel()` under iOS 27 with the same
  entitlement and quota guards (`:87-101`).

`LLMService` calls `determineRoute` at `:601` and `:1095`, creates the session at `:517`, builds
`GenerationOptions(temperature:maximumResponseTokens:)` (`:750-759`), and streams with
`session.streamResponse(to:options:)` (`:777-786`); a continuation prompt streams at `:1311`.
Placement of the on-device model is framework-decided; nothing in the app can move it.
`[evidence_level: code_verified, confidence: exact]`

Token budget: `baseContextLength = 4096`, `defaultTokenBudget = 3200`, `safetyReserve = 256`,
1.4 characters per token on device and 2.5 for the cloud fallback estimate
(`FoundationModelTokenBudget.swift:22-53, 94`). `ContextPackingService` uses the same 3,200
default (`ContextPackingService.swift:60`). Temperature by mode: 0.4 / 0.4 / 0.3
(`RAGQualityMode.swift:95-101`). `[evidence_level: code_verified, confidence: exact]`

### 4.6 The nine gates

`VerificationGateService` (`Services/RAG/Safety/VerificationGateService.swift`) is an actor with
gates A through I (`:63-72`), run in order A, B, C, D, E, F, G, H (`:179-226`); Gate I, domain
isolation, is applied before synthesis. Default thresholds: `tauNormal 0.40`, `tauTouchy 0.55`
(medical, legal, financial, safety, dosage, drug, medication), `muMargin 0.03`,
`semanticGroundingThreshold 0.50` (`:95-99`); a strict profile is 0.65 / 0.75 / 0.10 / 0.60
(`:104-108`). Gate E embeds the response and compares it with the best source chunk, so it is the
one gate that costs an inference. The mode's `verificationConfidenceThreshold` is 0.50 / 0.60 /
0.80; the comment on Maximum says 0.98 was unreachable (`RAGQualityMode.swift:226-233`).
`[evidence_level: code_verified, confidence: exact]`

### 4.7 What a query drops silently

| Point | Rule | Where |
|---|---|---|
| Candidates | Below `minSimilarity` after rerank | `RAGService.swift:10781` |
| Candidates | MMR redundancy | `:11063` |
| Chunks | Do not fit the token budget | `ContextPackingService.swift:208-218` |
| Siblings | Skipped for budget | `RAGService.swift:18809` |
| Cloud payload | Per-chunk character allowance | `ModelExecutionPlanner.swift:161` |
| Claims | Gate B uncited, Gate E ungrounded | `VerificationGateService.swift:183, 201` |

---

## 5. Deep Think, Maximum, and escalation

### 5.1 How a run becomes agentic

`QueryRuntimeCoordinator` (`Services/RAG/Orchestration/QueryRuntimeCoordinator.swift`) produces
one of three agentic paths: `.agentic` (mode is Deep Think or Maximum), `.forcedAgentic` (the
user pressed Go Deeper), `.plannerEscalated` (the planner escalated a Standard query; logged at
`:218`). `isAgentic` is true for all three (`:78-80`). `RAGService.executeAgenticQuery` builds an
`AgenticOrchestrator(ragService:config:qualityMode:)` and calls `execute` (`RAGService.swift:8573-8580`).
`[evidence_level: code_verified, confidence: exact]`

### 5.2 Profiles

| Profile | `maxSteps` | `confidenceThreshold` | `escalationThreshold` | Where |
|---|---|---|---|---|
| fast | 2 | 0.70 | 0.25 | `Services/Agentic/AgenticOrchestrator.swift:125-130` |
| default | 5 | 0.85 | 0.35 | `:117-122` |
| thorough | 8 | 0.95 | 0.45 | `:133-138` |
| unlimited | 50 | 0.98 | 0.50 | `:144-149` ("thermal will stop us first") |

Reasoning-chain session counts: light 3, standard 4, deep 5, unlimited 50, each session a fresh
4,096-token window (`:4286-4310`). Deep Think's effective session count comes from the reasoning
policy (`:4686`). `[evidence_level: code_verified, confidence: exact]`

### 5.3 The loop

1. Retrieval quality is scored by `evaluateRetrievalQuality` (`:1122`) and re-scored after each
   expansion (`:364, 466, 489, 918`). Lexical relevance under 0.10 with an invalid semantic intent
   is a hard exit (`:382`; `Services/RAG/Tuning/AgenticPolicyService.swift:146`).
2. Recursive research: `executeRecursiveResearch(…, maxIterations:)` (`:2759`, default 7) with a
   180-second wall-clock budget (`:2757, 2805`). Each iteration asks the model for a decision over
   the accumulated context; `.search` retrieves and appends, `.answer` synthesises and breaks
   (`:2828-2868`). **Two call sites**: `:683` passes 5, `:3625` passes 3. The log line's iteration
   denominator (`N/5` versus `N/3`) is the only way to tell which ran.
3. Deep Think adds `runVerificationLoop` after the chain (`:3560`).
4. Maximum runs `executeTrueUnlimitedReasoning` (`:6064`): target confidence 0.98, `maxSessions`
   50 scaled down to the evidence pool at three chunks per session (`:6100-6114`), a `FactBank`
   carried across sessions, a running synthesis every few sessions, termination on target,
   saturation, cancellation, or the cap (`:6137`). Tools are disabled in these sessions to
   prevent context overflow (`:6398`).
5. Every internal planning and analysis call is pinned local: `executionContext = .onDeviceOnly`,
   `allowPrivateCloudCompute = false` (`:8567-8569`). Only the final synthesis goes through
   `makePostRetrievalModelPlan` (`:8670, 8685`) and may reach PCC.

Backoff: `AdaptivePipelineOptimizer` moves to `.minimal` on critical thermal state (`:58`) and
`.efficient` on critical memory (`:64`); `isConstrained` is any non-nominal thermal or memory
state, plus low battery on iOS (`:79-83`). `DeviceCapabilityService.agenticStepCooldownMs` is
100 ms on baseline tiers and 0 on M-series (`:551`). `[evidence_level: code_verified, confidence: exact]`

Hazards the code itself records: context overflow at "4521+ tokens on a 4096 limit" (`:4945`),
citations resolved against the wrong array for the life of the chain (`:4425`, fixed), and
dangling citations from a shorter re-ordered list (`:758`).
`[evidence_level: code_verified, confidence: exact]`

---

## 6. The hardware and concurrency map

### 6.1 Every unit request in the app

| Where | Symbol | Work | Unit requested | Fallback |
|---|---|---|---|---|
| `Services/Embedding/Providers/CoreMLSentenceEmbeddingProvider.swift:191, 145, 165` | `MLModelConfiguration.computeUnits` | Sentence embeddings | From profile: `.cpuAndNeuralEngine` or `.all` (§3.4) | Load error → provider unavailable, `EmbeddingService` warns (`:65`) |
| `Services/RAG/Orchestration/RAGEngine.swift:86, 97` | `computeUnits = .all`, `allowLowPrecisionAccumulationOnGPU` | Cross-encoder rerank | Any | Rerank skipped when model missing (`:330`) |
| `Services/Document/Classification/YOLODetectionService.swift:80` | `.all` | Object detection on images | Any | |
| `Services/Document/Classification/CoreMLRegionDetector.swift:177` | `.all` | Region detection | Any | |
| `Services/Document/Classification/CoreMLDocumentClassifier.swift:223` | `.cpuAndNeuralEngine` | Document classification | CPU or ANE | |
| `Services/RAG/Extraction/ExtractiveQAService.swift:139` | `.cpuAndNeuralEngine` | Span model, **dormant**: the placeholder returns nil and generation always runs (`RAGService.swift:12731`) | | |
| `Services/Infrastructure/Compute/GPUComputeService.swift:258-280, 701, 764` | Metal kernels `batchCosineSimilarity`, `…SIMD`, `…Threadgroup`, `batchNormalize`, `mmrDiversityMatrix` | Vector similarity, normalisation, MMR matrix | GPU | CPU `vDSP` (`:26` in `batchCosineSimilarity`) |
| `Services/VectorStore/BNNSVectorDatabase.swift:365, 536` | `vDSP_dotpr`, `vDSP_mmul` | Similarity below 1,000 vectors | CPU SIMD | |
| `Services/Infrastructure/Compute/BNNSGraphService.swift` | Accelerate BNNS and vDSP | Batch normalisation, cosine matrices, softmax, fusion arithmetic | CPU SIMD | |
| `Services/Document/Processing/DocumentProcessor.swift:7510` | `VNRecognizeTextRequest` | OCR | Framework-decided | PDFKit text layer |
| `StructuredDocumentParser.swift:680`, `IntelligentDocumentProcessor.swift:847`, `CoreMLRegionDetector.swift:429` | `RecognizeDocumentsRequest` | Layout and tables | Framework-decided | Plain OCR |
| `Services/Document/Extraction/AudioTranscriptionService.swift:215-217` | `SFSpeechURLRecognitionRequest`, on-device required | Transcription | Framework-decided, on device | None; the `SpeechAnalyzer` path is compiled out (§3.2) |
| `Services/Query/Routing/QueryRouterService.swift:294` and the chunker | `NLTagger`, `NLTokenizer`, `NLLanguageRecognizer` | NER, tokens, language | Framework-decided | |
| `Services/LLM/LLMService.swift:517, 777-786` | `LanguageModelSession` | Every generation | Framework-decided on device; PCC when routed | On-device fallback stage in every PCC plan |
| `Features/Telemetry/Visualizations/Embedding3DView.swift` | SceneKit | 3D atlas | GPU | |

`[evidence_level: code_verified, confidence: exact for the lines; the "unit requested" column is what the code asks for, never what ran]`

### 6.2 What the GPU execution profile actually changes

`GPUExecutionProfile` is `efficiency`, `balanced`, `performance`, `maximum`
(`DeviceCapabilityService.swift:26-30`), each with an `Engagement` of `usesCPU`, `usesNeuralEngine`,
`usesGPU` and a list of effects (`:49-110`). Concretely it drives: Core ML compute units for the
query-side models (`:812-821`), embedding units during ingestion (`:844-851`), `useMetalForVectorOps`
for the MMR matrix, and the concurrency ceilings below. It does not gate the vector-search GPU
path (§4.3). The ladder bug fixed 2026-08-26 was that Maximum removed the Neural Engine while
claiming to add hardware. `[evidence_level: code_verified, confidence: exact]`

### 6.3 The device capability ladder

Tiers: `.baseline` (A17 Pro), `.enhanced` (A18), `.advanced` (A19), `.ultraAdvanced` (M-series
and later), `.unsupported` (`:133-138`), detected from `utsname`, the CPU brand string, and
physical memory, with TOPS looked up per chip (`:1038-1330`). The scaling M5 and later chips need
was fixed 2026-08-26 after a new Mac was tiered as M3-era.

| Consumer | Range | Where |
|---|---|---|
| `maxConcurrentAgenticSteps` | 3 → 32 | `:527` |
| `agenticStepCooldownMs` | 100 → 0 | `:551` |
| `vectorBatchSize` | 128 → 16,384 | `:583` |
| `embeddingBatchSize` | 8 → 512 | `:603` |
| `batchMatrixMultiplyThreshold` | `Int.max` → 16 | `:619` |
| `visionParsingConcurrency` | 2 → 64, RAM-scaled on Mac | `:675` |
| `pdfRenderingConcurrency` | 1 → 64, capped by a per-page memory estimate | `:739` |
| `embeddingConcurrency` | 2 → 64 | `:778` |

`[evidence_level: code_verified, confidence: high for ranges, exact for lines]`

### 6.4 Concurrency topology

| Primitive | Where | Owner |
|---|---|---|
| `MainActor` | UI, `RAGService` published state, `DeviceCapabilityService.shared` | UI |
| Actors | `BNNSVectorDatabase`, `VecturaVectorDatabase`, `SQLiteFullTextService`, `VerificationGateService`, `AsyncVisionSemaphore` | Retrieval, storage, gates, OCR throttle |
| Serial ingestion loop | `RAGService.runIngestionLoop` (`:4969`) | Ingestion |
| `withTaskGroup` | Page extraction (`DocumentProcessor.swift:3547`), embeddings (`CoreMLSentenceEmbeddingProvider.swift:461`), rerank (`RAGEngine.swift:1516`), agentic cluster insights (`AgenticOrchestrator.swift:7064`), suggested questions (`SuggestedQuestionsService.swift:606`) | Ingestion, retrieval, agentic |
| `async let` | Vector and FTS5 searches in parallel (`HybridSearchService.swift:1032-1037`) | Retrieval |
| `Task.detached` | Workspace sync and artifact persistence (`WorkspaceSyncService.swift:948, 3611`) | Sync |
| `DispatchQueue` | `com.openintelligence.vectordb` concurrent (`VectorDatabase.swift:98`), camera analysis and capture queues (`CameraManager.swift:30-31`) | Legacy store, camera |
| `OperationQueue` | `syncVisionOperationQueue` (`VisionOCRThrottle.swift:166`) | OCR |
| `BGTaskScheduler` | Five registrations (§1.1) | Background |

`[evidence_level: code_verified, confidence: exact]`

---

## 7. iOS versus macOS

| Area | iOS | macOS | Where |
|---|---|---|---|
| Background tasks | `BGTaskScheduler` registered | Not registered (`#if os(iOS)`); Catalyst bypasses `UIBackgroundTask` | `OpenIntelligenceApp.swift:37-38`; `BackgroundTaskService.swift:143` |
| Live Activity | Yes | No | `IngestionLiveActivityService.swift` |
| PDF page raster | `UIGraphicsImageRenderer`, opaque | `CGContext`, `noneSkipLast`; the `NSImage.lockFocus` path was replaced because it exploded memory on Retina | `DocumentProcessor.swift:7018-7050`, `7061-7090` |
| GPU memory-warning observer | `UIApplication.didReceiveMemoryWarningNotification` clears the buffer pool | No equivalent observer | `GPUComputeService.swift:313` |
| Memory pressure source | `os_proc_available_memory` and the memory-warning notification | `os_proc_available_memory` only | `SystemStateMonitor.swift:429, 599` |
| Window tabbing | n/a | Disabled at launch | `OpenIntelligenceApp.swift:23-27` |
| Presentation | `fullScreenCover` for camera and the 3D atlas | `sheet` | `ChatComposerV2.swift:178, 187`; `AdaptiveVisualizationsView.swift:160-166` |

`RAGService.swift` has six `canImport(UIKit)` blocks and `DocumentProcessor.swift` three; none of
the platform seams in this document are `#if os(macOS)`. The ledger's note stands: the `#else`
half of a `canImport(UIKit)` pair is where macOS has historically received the worse or missing
implementation, and it still builds and still logs healthy.
`[evidence_level: code_verified, confidence: high]`

---

## 8. The failure class, stage by stage

Every serious defect in this app's history had the same shape: a stage discards data and every
log line still reads healthy. This is where each stage can do that today.

| Stage | Drop | Visible to the user? |
|---|---|---|
| Extraction | Oversized file, garbled text layer, low-confidence OCR strings, uncertain table cells | Only in logs and the stage ledger |
| Chunking | Chunk tails past 510 tokens | Logged |
| Embedding | None by design; zero vectors are prevented | |
| Persistence | Vectors without chunk rows after a mid-write crash | Repair path |
| Retrieval | Below-threshold candidates, MMR redundancy, budget-trimmed chunks, skipped siblings | Retrieval diagnostics sheet |
| Cloud | Per-chunk character allowance in the payload | Plan telemetry |
| Generation | Model refusal or guardrail filter | Mapped to an error |
| Verification | Uncited and ungrounded claims | Shown as unsupported |

`[evidence_level: code_verified, confidence: high]`

---

## 9. Claims audit of the two earlier documents

Per `oi-claim-audit`: nothing here is withdrawn from either document; these are the places where
the source disagrees or adds a condition.

### 9.1 How OpenIntelligence Works (Opus 5)

| Claim | Finding |
|---|---|
| "Audio and video go through SpeechAnalyzer" | **Wrong in every build.** The branch is behind `#if canImport(SpeechAnalyzer)`, a module that does not exist, and calls an API shape the SDK does not declare. Transcription runs on `SFSpeechRecognizer` with on-device recognition required (§3.2). |
| "384-dimensional sentence embeddings, generated on the Neural Engine through Apple's newer on-device inference path where available, falling back to Core ML" | The Core AI path exists and is the default on iOS 27 and macOS 27, so "where available" is right. "On the Neural Engine" is a request, and only on the Core ML path: the lower two GPU profiles request `.cpuAndNeuralEngine`, the upper two `.all`, and Core ML decides. Core AI exposes no placement at all. |
| "Below 1,000 chunks vDSP_dotpr; at or above 1,000 a Metal compute shader" | Right, with two conditions omitted: a Metal device must exist, and the CPU path itself switches to `vDSP_mmul` above the device's batch threshold (§4.3). |
| "Vision's RecognizeDocumentsRequest handles scans, photos and camera captures" | OCR is `VNRecognizeTextRequest`; `RecognizeDocumentsRequest` is the structure and table parser used on pages the complexity triage selects. Both exist; the roles are split. |
| "the nine SQLite tables" | Confirmed, nine (§3.6). |
| "Page rendering is zero-copy, converting CIImage straight to CGImage without a PNG round trip" | The render itself is a Quartz raster into a bitmap context at 360 DPI; there is no PNG step, but a full-page bitmap is allocated per page. "Zero-copy" describes the vector store's mmap, not page rendering. |
| Hardware placement generally | Thin: the document never says which unit runs OCR, transcription, reranking or generation. §0 and §6 are the answer. |

### 9.2 Audio Study Guide, Version 2 (GPT-5.6 Terra)

| Item | Finding |
|---|---|
| All 153 cited source paths | Exist (`git ls-files` check, 0 missing). |
| OI-0035, OI-0055 audio transcription anchored to `AudioTranscriptionService` | **Correct**, and more accurate than the Opus page: it names the path that actually runs. |
| OI-0126 Core AI provider, "Conditional", "selected conditionally before falling back to Core ML" | Correct, with one addition: on iOS 27 and macOS 27 `SettingsStore` makes it the default and migrates saved Core ML defaults (`:531-544`), so on those OS versions it is the primary path, not a conditional one. |
| OI-0155 1,000-chunk GPU threshold, caveat "the actual route also depends on device and user GPU policy" | Half right. Device, yes (`isGPUAvailable`). The user GPU profile does **not** gate this path; it gates MMR and Core ML units (§4.3, §6.2). |
| OI-0551 Core ML compute units "derived from GPU execution profile and provider policy" | Correct (§3.4). |
| OI-0570 Neural Engine, status "Core" | The status is a category claim. No line in the app places work on the Neural Engine; five lines permit it (§6.1). "Core" is defensible only as "requested on the default path". |
| OI-0601 live Neural Engine utilisation, "Future" | Correct; the HUD pulse is synthetic. |
| OI-0605 neural extractive QA, "Dormant" | Correct (`RAGService.swift:12731`). |
| OI-0185 Metal residency set | Exists (`GPUComputeService.swift:345`). |
| Pipeline recitation, Standard Query step 10 "post-retrieval ModelExecutionPlan" | Matches the source order (`RAGService.swift:13038` after Step 5 at `:12066`). |
| Step 6 "Cross-encode the shortlist with TinyBERT" | The model is `ReRankerModel.mlpackage`; the architecture name is not stated in code and was not verified here. |
| Equations: RRF `k ≈ 60` | Exactly 60 (`HybridSearchService.swift:297`). |

### 9.3 The delegated inventories

Six read-only inventories ran on Antigravity (five on Gemini 3.1 Pro, one on Gemini 3.7 Flash;
three earlier Sonnet attempts died mid-run). Each returned a verify command that was run under
`bash -c` and each artifact was spot-checked line by line. The launch inventory was **discarded**:
it described `OpenIntelligenceApp.init` as calling functions it does not call and cited line
numbers that do not exist (§1.1 was rewritten from source). The other five were used only for
claims that were re-read here; where a line number in this document differs from an inventory,
this document is the one that was checked.

---

## 10. What this trace does not cover

- Runtime measurements. Nothing here is a timing or a utilisation figure; the ledger
  (`BenchmarkRuns/LEDGER.md`) is the only source for those, and its evidence is uneven.
- Which unit actually executed a framework-decided call on a given device. No public API
  reports it; Instruments' Core ML and Neural Engine templates on the connected device do.
- iCloud sync internals beyond the ingestion guard and the idle-churn trigger; `WorkspaceSyncService`
  is the hard-boundary file that owns them.
- Billing, quota and entitlement logic beyond the launch-path calls.

---

## 11. Verification

Run from the repository root under bash. One line per symbol is the pass condition.

```bash
bash -c 'for s in "static let shared = DeviceCapabilityService()" "BGTaskScheduler.shared.register" "gpuThreshold = 1000" "vDSP_mmul" "computeUnits = .all" "cpuAndNeuralEngine" "k: 60" "tauNormal: 0.40" "canImport(SpeechAnalyzer)" "requiresOnDeviceRecognition = true" "safeTokenLimit = maxEmbeddableTokens" "static let safeMaxSize = 310" "maxIterations: 5" "maxIterations: 3" "researchTimeBudget: TimeInterval { 180 }" "PrivateCloudComputeLanguageModel()" "batchCosineSimilarityFlatBuffer" "candidates.count > 50"; do printf "%-45s " "$s"; grep -rn --include="*.swift" -F "$s" OpenIntelligence/Services OpenIntelligence/App | grep -v "swift-transformers\|^\s*//" | head -1 | cut -c1-110; done'
```

```bash
ls /Applications/Xcode-beta.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks | grep -E "^(CoreAI|Speech|FoundationModels)\.framework$"
```

The second command shows that `CoreAI.framework` and `Speech.framework` exist and that no
`SpeechAnalyzer.framework` does, which is the whole of the §3.2 finding.
