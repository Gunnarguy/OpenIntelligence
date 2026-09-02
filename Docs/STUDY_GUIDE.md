# OpenIntelligence Study Guide

> **Documentation status:** Written 2026-09-02 against commit `273b007`. Every number and every
> "where it runs" statement is taken from `Docs/Engineering/FULL_SYSTEM_TRACE.md`, which cites the
> line for each; the concept definitions come from the 612-entry word bank in
> `Docs/Research/AUDIO_STUDY_GUIDE_V2_TERRA_2026-08-27.md`; the reasons come from the Opus
> walkthrough in `Docs/Research/HOW_OPENINTELLIGENCE_WORKS_OPUS_2026-08-22.txt`. Where the word
> bank and the source disagree, the correction is listed in the module and the source wins.
> `[evidence_level: code_verified_via_trace, confidence: high]`

This is the course. Its job is that you can explain every component of your own app and the reason
it exists, to a non-technical person, to an engineer, and at a whiteboard, without notes.

## How to use it

Seventeen modules in pipeline order, the same order the word bank uses. Each module has:

1. **What it is**, in one breath.
2. **Why it exists**: the reason, which is what interviews actually test.
3. **Where it runs**: thread, unit, and the numbers.
4. **The word bank** for the module: every concept, its status, one sentence. Read it once; then
   use the flashcards.
5. **Corrections**, where the bank or the earlier walkthrough is wrong.
6. **Can you explain it?** A checklist. Say each one out loud. If you cannot, go back.
7. **Quiz**, with answers folded.

Do one module a day. On the eighth day start again from module 00 doing only the checklists. The
status words matter: **Core** runs on the default path; **Conditional** runs in some modes or for
some inputs; **Support** is diagnostics and evaluation; **Dormant** is in the source and not on any
shipping path; **Future** is a reserved name; **Historical** is superseded and misleading if taught
as current.

## The whole thing in twelve sentences

Memorise this first. It is the spine every module hangs from.

1. A file is enqueued as a durable ticket and processed one document at a time.
2. Its text is extracted by type: text layer, 360 DPI OCR, structured table parsing, XML, CSV, or
   on-device speech.
3. The text is cut into chunks of at most 310 words, validated at 430 tokens by the real tokenizer,
   each with a contextual prefix.
4. Each chunk becomes a normalised 384-dimension vector, on Core ML or Core AI, with the unit chosen
   by the GPU profile.
5. Chunks are written to SQLite FTS5 and to a memory-mapped vector file; summaries and entities are
   derived on top.
6. A question is profiled and planned first: intent, complexity, mode, and whether it is agentic.
7. Vector search and BM25 run in parallel and are fused with RRF at k = 60.
8. A cross-encoder reranks the shortlist; a similarity floor and MMR cut it; neighbours are added.
9. Evidence is packed under the real token budget, strongest first and last.
10. A post-retrieval plan chooses abstain, deterministic, on-device, or Private Cloud Compute, and
    only then asks for consent.
11. The model streams a typed answer with citations; nine deterministic gates decide what survives.
12. What comes back is inspectable: claims, byte-offset citations, the completed route, and a trace.

---

## Module 00. System architecture and boundaries

**What it is.** The walls and rooms. What a library is, what stays on the device, and which stages can invent things and which cannot.

**In the bank's words.** Before looking at the machinery, you need to know where the walls, rooms, and rules are. These concepts define what the app is, what belongs to one library, and which steps are rule-based versus model-generated.

**Why it exists.** Everything else in the app assumes these boundaries. A **knowledge container** (a library) scopes every store, so one library's chunks can never answer another library's question. **Local-first** is a concrete promise: ingestion, indexing, retrieval and ranking never leave the device; only the final answer may reach Private Cloud Compute, and only after consent. The **deterministic versus generative** split is the reason the app can be honest about hallucination: extraction, chunking, search, fusion, gates and citations are rule-based and cannot invent; only the two generative stages (query rewriting and answer synthesis) can, so they are the only stages the gates police.

**Where it runs.** Nothing here runs by itself. These are the invariants the code enforces: container scoping in every store, the `OpenIntelligenceEngine` SwiftPM target that excludes UI and Billing, and the three quality modes that turn the same pipeline up or down.

### The word bank (14 concepts)

| Concept | Status | In one sentence |
|---|---|---|
| Container isolation | Core | The rule that lexical rows, vector stores, entity lookups, documents, threads, and queries are filtered by container identity. This prevents cross-library evidence leakage and makes deletion, rebuilding, and sync deterministic… |
| Deep Think mode | Conditional | The multi-step path that enables query rewriting, expansion, HyDE, iterative retrieval, and the agentic orchestrator with stronger verification thresholds. It spends additional retrieval and reasoning work when a one-pass answer… |
| Deterministic stage | Core | A stage whose result is produced by code, indexing, arithmetic, parsing, or fixed policy rather than free-form model generation. Deterministic stages are reproducible and cheap to verify. |
| Engine status vocabulary | Support | The audit classification used in this word bank: Core, Conditional, Support, Dormant, Future, and Historical. The repository contains implemented, wired, optional, scaffolded, and superseded mechanisms. |
| Generative stage | Core | A stage that uses a language model to write, summarize, reformulate, classify, or synthesize text. Generation handles semantic composition that fixed rules cannot express, but it introduces uncertainty, token cost, and… |
| Ingestion pipeline | Core | The one-time transformation from an imported file into normalized text, structured elements, chunks, embeddings, lexical rows, vector artifacts, summaries, and metadata. Every later answer is bounded by what ingestion preserved. |
| Knowledge container / library | Core | A user-visible library with its own documents, embedding configuration, vector artifacts, retrieval settings, statistics, and sync mode. It is the primary isolation boundary. |
| Local-first | Core | Documents, full text, embeddings, indexes, retrieval, generation, and deterministic verification are designed to run on the user device. This is the privacy and availability constraint that determines the architecture. |
| Maximum mode | Conditional | The broadest and strictest user-selectable path with larger candidate sets, more expansion, more agentic sessions, lower retrieval floors, and the highest verification threshold. It is designed for difficult synthesis where… |
| OpenIntelligence engine | Core | The coordinated local document-intelligence runtime that accepts files, builds searchable representations, retrieves evidence, invokes Apple Foundation Models, verifies claims, and returns a cited answer. It gives one owner to… |
| Quality mode | Core | The named policy bundle Standard, Deep Think, or Maximum that changes candidate breadth, similarity thresholds, expansion, iterative retrieval, agentic sessions, confidence requirements, and memory depth. A mode must alter the… |
| Query pipeline | Core | The per-question path that profiles the request, retrieves candidates, ranks and expands evidence, packs context, chooses an execution route, generates or extracts an answer, and verifies it. It converts a broad corpus into a… |
| Retrieval-augmented generation (RAG) | Core | A pattern in which the app retrieves relevant passages before asking the language model to answer from those passages. The on-device model cannot hold an entire library in its context window, and its pretrained memory is not the… |
| Standard mode | Core | The single-pass grounded path with hybrid retrieval, reranking, MMR, citations, generation, and verification. It minimizes latency while preserving the non-negotiable evidence and trust controls. |

### Can you explain it?

1. Say what a knowledge container is and name one thing that is scoped by it.
2. Explain local-first as a list of stages that never leave the device, and the one that may.
3. Name the two generative stages and say why the gates exist because of them.
4. Give one difference between Standard, Deep Think and Maximum that is a number, not an adjective.
5. Explain what the engine target is and why UI and Billing are excluded from it.

### Quiz

<details><summary><strong>What is the difference between a deterministic stage and a generative stage, and why does it matter?</strong></summary>

A deterministic stage is rule-based and produces the same output for the same input: extraction, chunking, search, fusion, gates, citation mapping. A generative stage asks a language model and can invent: query rewriting and answer synthesis. Only generative stages can hallucinate, so verification is aimed at them.

</details>

<details><summary><strong>What does local-first mean in this app, concretely?</strong></summary>

Ingestion, indexing, retrieval, ranking, context packing and verification run on the device. The one step that may leave is final answer synthesis, and only to Private Cloud Compute, only after the post-retrieval plan chooses it and the user consents.

</details>

<details><summary><strong>Name one numeric difference between the three quality modes.</strong></summary>

Initial retrieval breadth: 30 candidates in Standard, 35 in Deep Think, 50 in Maximum. Or the similarity floor: 0.28, 0.25, 0.20. Or the verification confidence bar: 0.50, 0.60, 0.80.

</details>

<details><summary><strong>What is the OpenIntelligence engine, as opposed to the app?</strong></summary>

The `OpenIntelligenceEngine` SwiftPM library target: the same source tree with App, Features, UI, Billing and a few platform files excluded, so the pipeline can be built and tested without the app shell.

</details>

<details><summary><strong>Why does the query pipeline retrieve before it decides where to generate?</strong></summary>

Because the size and sensitivity of the evidence are not known until retrieval is done. The model execution plan is built after retrieval, from the real token count and the minimised payload.

</details>

---

## Module 01. Ingestion control, identity, and lifecycle

**What it is.** The receiving dock. A file becomes a durable work ticket that survives backgrounding, crashes and restarts.

**In the bank's words.** This is the receiving dock. It makes a work ticket for every file, remembers where the job stopped, prevents duplicate work, and makes sure deleting a job really wins over accidentally restarting it.

**Why it exists.** iOS will kill the app mid-import, and a user will quit it. So ingestion is not a function call; it is a state machine with a **checkpoint**, a **lease** and a **heartbeat**, persisted so that a restart resumes from the last completed stage. **Deletion wins** over resumption because a user removing a document must never see it come back. **Content hashes** and **stable document IDs** stop the same file being indexed twice. The whole thing runs **one document at a time**; the parallelism you see in Activity Monitor is inside a document, across pages and embedding batches.

**Where it runs.** Enqueue happens on the main actor (`RAGService.enqueueDocuments`). `runIngestionLoop` then processes the queue serially. Stages go queued, loading, extracting, chunking, analyzing, embedding, indexing, storing, complete, each one published to the Live Activity within 0.5 s.

### The word bank (19 concepts)

| Concept | Status | In one sentence |
|---|---|---|
| Atomic ingestion commit | Core | The final publication of mutually consistent document metadata, lexical rows, chunks, and vector artifacts only after the new set is ready. Publishing pieces independently creates states where SQLite says chunks exist but vectors… |
| Background continued processing | Conditional | An iOS 26 BGContinuedProcessingTask path that can continue a user-initiated import or query after the app leaves the foreground, with CPU/GPU resource policy and persisted status. Long OCR and Maximum queries should not be… |
| Cancellation tombstone | Core | A durable record that a queue item or document was intentionally discarded. Without a tombstone, sync or queue merge can resurrect work that another device or user explicitly removed. |
| Checkpoint | Core | A durable record of ingestion progress, commonly at page or batch boundaries, that lets a large document continue without restarting at page one. Mobile apps are interrupted frequently. |
| Content hash | Core | A cryptographic or stable digest of source content used to identify unchanged files and artifacts. Hashes prevent duplicate ingestion, detect stale checkpoints, and support sync signatures without rereading or trusting filenames. |
| Deduplication | Core | The prevention or merging of logically repeated documents, chunks, or evidence based on IDs, hashes, source identity, or content overlap. Duplicates waste storage and context, distort rank metrics, and make one source appear more… |
| Deletion-wins policy | Core | A merge rule under which an explicit deletion marker defeats an older surviving copy. Distributed replicas otherwise tend to resurrect deleted files because one device still has the last full record. |
| Deterministic UUID | Support | A UUID generated from a stable string hash for cases that need reproducible identifiers. Reproducible IDs let derived artifacts reconnect after reload without a central server assigning identity. |
| Document enqueue | Core | The act of adding one or more URLs to the persistent ingestion queue instead of processing them directly in the UI callback. Queueing makes imports cancellable, resumable, observable, and safe across app backgrounding or… |
| Foreground background-time fallback | Conditional | A shorter UIApplication background task used as a handoff window when the continued-processing task has not yet taken ownership. It closes the timing gap between app backgrounding and scheduler launch, reducing abrupt… |
| Heartbeat | Core | A periodic timestamp proving that the worker holding an ingestion lease is still alive. It distinguishes slow but active OCR from a dead task whose lease should be reclaimed. |
| Ingestion lease | Core | A time-bounded ownership marker indicating that one worker currently owns a queue item. After a crash or termination, an eternal processing flag would strand the item. |
| Ingestion stage state machine | Core | The ordered states queued, loading, transcribing, extracting, chunking, analyzing, adapting, reindexing, embedding, indexing, storing, complete, cancelled, and failed. Explicit states make progress and recovery auditable. |
| IngestionContext | Core | The reason and policy context for an import, such as user initiated, automatic rebuild, or onboarding. The same file-processing machinery may require different UI, tuning, retry, or self-healing behavior depending on why it runs. |
| IngestionItem | Core | The persisted state machine record for one imported file, including stage, progress, timestamps, lease, heartbeat, file identity, errors, and events. A long import needs an explicit durable state rather than an in-memory task. |
| Resumable ingestion | Core | The combined behavior of queue persistence, stable identity, leases, heartbeats, checkpoints, and stage-aware restart. It converts import from an all-or-nothing transaction into recoverable work while still protecting against… |
| Stable document ID | Core | A UUID that continues to identify the logical document across checkpoints, sync, rebuilds, and derived chunks. Page-only or filename-only identity can create duplicates or attach rebuilt chunks to the wrong document. |
| Streaming ingestion lane | Conditional | A bounded-memory path for large files that processes and flushes a page batch at a time instead of retaining the entire document working set. A hundreds-page PDF can exceed the process memory budget if all rendered pages and… |
| Weighted progress | Support | A mapping from stages to unequal progress contributions, with extraction receiving the largest share and storage the smallest. Import work is not evenly distributed. |

### Can you explain it?

1. Recite the stage order.
2. Explain why a paused import must show its true page count (the removal trap).
3. Say what a tombstone is and which rule it enforces.
4. Explain the 20 second iCloud materialisation guard and what it protects.
5. Say how many documents ingest concurrently and where the real parallelism is.

### Quiz

<details><summary><strong>How many documents does the app ingest at once?</strong></summary>

One. `runIngestionLoop` pulls the next queued item and awaits `addDocument` before taking another. Parallelism exists inside a document: page extraction task groups and embedding batches.

</details>

<details><summary><strong>What happens to an import if you quit the app halfway?</strong></summary>

The item's checkpoint and stage are persisted; on relaunch the item is restored as queued or paused with its real progress and resumes from the last completed stage. Removing it is the one action that discards the checkpoint.

</details>

<details><summary><strong>What is a cancellation tombstone?</strong></summary>

A record that a document was deleted, kept so that a resumed or re-synced import cannot resurrect it. Deletion wins.

</details>

<details><summary><strong>Where does a document&#x27;s full text go before it is chunked?</strong></summary>

Into the FTS5 `documents` table, from inside `processDocument`. Chunk rows arrive later, after embedding. A failure in between leaves a document searchable at document level and absent from both chunk indexes.

</details>

<details><summary><strong>What does the iCloud materialisation guard do?</strong></summary>

If the file is an iCloud placeholder, ingestion waits up to 20 seconds for it to download before reading. Without it, a placeholder reads as an empty or partial file.

</details>

---

## Module 02. File extraction and document understanding

**What it is.** The reading room. Copy the text if there is a text layer, look at the page as a picture if there is not, read rows and columns when the layout matters, and listen when it is audio.

**In the bank's words.** This is the reading room. The app chooses whether to copy text, look at a page like a picture, read rows and columns, or listen to audio.

**Why it exists.** Extraction is the ceiling on everything after it: a fact that never made it out of the file cannot be retrieved by any amount of cleverness. PDFs get a **text-layer validation** first, because a scanned PDF often carries a garbage text layer that would poison the index silently. Pages that need OCR are rendered at 360 DPI and go through Vision with the accurate recogniser and language correction, with the language set **narrowed** to what was detected, because thirteen recognisers including four CJK models used to load for every request. A separate structured pass reads tables as rows and columns, because a number without its column heading is worthless.

**Where it runs.** Rendering is CPU (Quartz into a bitmap). OCR and structure parsing are Vision, and Vision decides its own placement; the app only throttles it with a semaphore sized to the device. Transcription runs on `SFSpeechRecognizer` with on-device recognition required. The `SpeechAnalyzer` branch is dead code that never compiles.

### The word bank (52 concepts)

| Concept | Status | In one sentence |
|---|---|---|
| Adaptive preprocessing | Conditional | Image enhancement chosen from page conditions, potentially including contrast, sharpening, denoising, thresholding, and orientation correction. One filter cannot help both faint receipts and high-contrast diagrams. |
| Audio transcription | Conditional | On-device Speech.framework conversion of supported audio or video into text, duration, language, confidence, and timestamped segments. Recordings need a textual representation before the ordinary chunk and retrieval pipeline can… |
| Barcode detection | Conditional | Vision recognition of barcode symbology and payload text inside a camera frame. A barcode may contain the most exact identifier available and should not be approximated through OCR. |
| Camera-to-RAG bridge | Conditional | The actor that converts recognized camera text, structures, and optional image descriptions into a temporary Markdown document and queues it through normal ingestion. Camera captures should enter the same identity, chunking,… |
| Column detection | Conditional | Histogram and gap-based clustering of text-block x coordinates into reading columns. A two-column paper read straight across produces semantically nonsensical passages and citations. |
| Compact cell anchor | Conditional | A precise row-column label attached to a cell value for smaller tables. Cell anchors improve exact lookup without repeating every large table cell and exhausting chunk space. |
| CoreMLDocumentClassifier | Conditional | A local document-type classifier used to infer high-level document characteristics when available. Classification can guide extraction and chunking policy without sending document content to a server. |
| CoreMLRegionDetector | Conditional | A local model path for detecting page-region classes such as tables, figures, or text regions. Region detection helps route visually complex areas to the correct extractor. |
| Detected data entity | Conditional | A structured email, phone number, URL, address, date, money amount, or measurement returned from visual document analysis. Explicit data types create searchable anchors and reduce ambiguity during extraction. |
| Dynamic document vocabulary | Conditional | A per-document list extracted from rough native text, including acronyms, alphanumeric codes, CamelCase words, compounds, and repeated proper-name bigrams. The document can teach OCR its own specialized vocabulary without… |
| Embedding translation | Conditional | Translation of text into the embedding provider target language while retaining original source text for display and citation. A monolingual embedder may retrieve cross-language content poorly. |
| Escalating DPI | Conditional | A policy that begins at a practical render resolution and retries at higher resolution when small-text risk or confidence warrants it. Always rendering at maximum DPI wastes memory and heat; never escalating loses footnotes,… |
| Garbage-text detection | Conditional | Post-OCR rules that identify likely character salad, mixed-script misreads, improbable consonant patterns, and suspicious non-ASCII output while respecting detected document language. Rotated labels and diagrams can generate… |
| ImageUnderstandingService | Conditional | The local service that classifies and interprets visual content found in documents or captures. Images and diagrams can contain evidence not represented in OCR text alone. |
| Language detection | Conditional | Identification of dominant document or extracted-text language using Natural Language APIs. Language affects OCR garbage rules, translation, tokenization expectations, and embedding compatibility. |
| LanguageDetectionService | Conditional | The Natural Language based service that identifies document or extracted-text language and confidence. Language affects OCR garbage rules, translation, tokenization expectations, and user-facing metadata. |
| Layout-aware extraction | Conditional | Spatial reconstruction of text from bounding boxes rather than trusting raw PDF object order. PDF text is stored by coordinates, and multi-column pages can otherwise interleave unrelated lines. |
| Live camera analysis | Conditional | Continuous Vision analysis of preview frames for text, document boundaries, barcodes, scenes, animals, faces, and humans. It provides immediate capture guidance and structured observations before the user commits an image. |
| OCR | Conditional | Optical character recognition that converts pixels into searchable text. A scan or camera image contains no machine-readable words, so OCR is required before any lexical or semantic indexing can occur. |
| OCR confidence | Core | A score associated with recognized observations or segments indicating recognition certainty. Confidence is used to reject weak blocks, trigger rescans, and report transcription or extraction quality rather than silently treating… |
| OCRConfiguration | Core | The central factory and policy authority for recognition revision, accuracy, language correction, languages, minimum text height, custom words, normalization, and garbage filtering. Multiple independently configured Vision… |
| On-device speech requirement | Core | Setting requiresOnDeviceRecognition on speech-recognition requests. It preserves the local-first privacy boundary for imported recordings. |
| OOXML / Office parsing | Conditional | Unzipping and streaming the XML parts of Office documents to recover text and structure. DOCX, PPTX, and XLSX are packages, not plain text. |
| Page complexity class | Core | The classification trivial, simple, moderate, complex, visual, or scanned. A compact label allows downstream extraction and resource policy to act consistently on many page signals. |
| Page rendering | Conditional | Rasterization of a PDF page into an image when visual analysis or OCR is required. Scans and complex layouts contain meaning that the native text layer cannot supply. |
| Page sentinel | Core | A marker inserted between page contents so later processing can preserve page boundaries in a combined text stream. Without explicit boundaries, chunks and citations could cross pages without knowing where evidence came from. |
| PageComplexityAnalyzer | Core | A router that combines native PDF structure, text coverage, layout, numeric density, tables, figures, forms, columns, annotations, and selective Vision signals. The engine needs to know which pages can use native text and which… |
| PDF text layer | Core | The native selectable text embedded in a digitally produced PDF. Reading it through PDFKit is faster and more accurate than OCR when it is trustworthy, and it preserves exact characters for offsets and citations. |
| PDFKit extraction | Core | Use of PDFPage strings, selections, bounds, annotations, and page objects to recover text and layout directly from the PDF. PDFs store text spatially and may expose structure unavailable in a flat string. |
| Reading-order reconstruction | Conditional | Ordering paragraphs, columns, and table regions according to their spatial position on the page. Chunking assumes coherent text sequence. |
| Recognition-language set | Core | The prioritized language list supplied to Vision together with automatic language detection. Limiting OCR to English would corrupt multilingual documents, while unconstrained guessing can degrade recognition. |
| RecognizeDocumentsRequest | Conditional | Vision document recognition that returns paragraphs, lists, tables, and related structure rather than only lines of text. A table flattened into reading order destroys row-column relationships. |
| RFC 4180 CSV parsing | Core | Parsing comma-separated data with proper quoting, escaped quotes, embedded separators, and row boundaries. Naively splitting on commas corrupts valid cells and destroys table relationships. |
| Segmented transcription | Conditional | Dividing media longer than the single-recognition limit into temporary time slices, transcribing each, and offsetting segment timestamps back into the full recording. Long recordings exceed one recognition task's practical… |
| SpatialDocumentAnalyzer | Conditional | The analyzer that derives spatial relationships, page regions, and layout-informed document signals. Position often carries meaning in forms, diagrams, tables, and multi-column documents. |
| StreamingXMLProcessor | Conditional | A bounded-memory XML parser for large packaged document formats. Loading an entire XML document object model can create unnecessary memory spikes for large Office files. |
| Structured Office parser | Core | Format-specific extraction of DOCX, PPTX, and related Office package contents by unzipping the container and parsing XML relationships and text nodes. Office documents contain native structure that should not be flattened through… |
| StructuredElement | Conditional | A typed paragraph, title, list, table, or figure recovered from a page. Typed structure lets the chunker keep tables atomic, boost headings, and present figures differently from prose. |
| Table row record | Conditional | A labeled representation such as Row 2: Model=1688; Reference=1688-020-122. It preserves cross-cell relationships and makes a row independently retrievable. |
| Table schema view | Conditional | A concise list of normalized column names. Schema terms are high-signal lexical anchors for queries such as reference number, dosage, or limit. |
| TableData | Conditional | A table representation retaining rows, optional header, caption, detected entities, alignments, and multiple search-oriented text views. A number is often meaningful only with its row and column labels. |
| TextBlock | Conditional | A recognized text unit with normalized bounding box, confidence, page number, and spatial helpers. Text must retain position long enough to reconstruct columns, lines, and tables. |
| Transcription segment | Conditional | A recognized phrase or word span with start time, end time, and confidence. Timestamped segments allow the indexed text to retain a path back to the original media. |
| TranslationService | Conditional | The service that translates text when a library or embedding policy requests a target language while retaining source provenance. It can improve cross-language embedding consistency without replacing original evidence. |
| Type-specific extractor | Core | A parser chosen from the source file type rather than forcing every input through OCR. Native PDFs, Office XML, CSV, audio, and images preserve different structure. |
| Universal custom words | Support | A domain-agnostic OCR vocabulary containing common units, symbols, document abbreviations, and safety labels. Vision is more likely to preserve short technical tokens such as mg/dL, N.m, or ISO when they are supplied as expected… |
| VisionOCRThrottle | Core | The semaphore and cooldown policy limiting concurrent Vision requests according to device and execution state. Vision and Metal workloads can race, exhaust command buffers, or destabilize memory when launched without bounds. |
| Visual evidence source | Conditional | A provenance object describing an image, page region, or visual observation used as answer evidence. A generated caption should remain linked to the actual visual region rather than masquerade as ordinary document prose. |
| VisualCaptioningService | Conditional | A service that converts selected visual regions into concise textual descriptions suitable for indexing. RAG retrieval operates primarily over text and vectors, so visual evidence needs a textual bridge. |
| VNRecognizeTextRequest | Conditional | Vision line-oriented text recognition used for OCR blocks, live camera frames, and layout extraction. It provides recognized strings, confidence, and bounding boxes for spatial reconstruction. |
| YOLODetectionService | Conditional | An object-detection service using a YOLO-family model path for recognized visual objects. Object labels and bounds can enrich otherwise text-poor pages and camera captures. |
| Zero-copy image path | Core | Conversion and handoff designed to avoid serializing page images through PNG or repeatedly allocating full intermediate buffers. A 400-page document can be killed by memory pressure even when the text logic is correct. |

### Corrections

- OI-0065 `RecognizeDocumentsRequest` is the **structure and table** parser. Plain OCR is `VNRecognizeTextRequest`. Both exist; the word bank blurs the roles.
- OI-0035 and OI-0055 are right that transcription runs on `AudioTranscriptionService` (`SFSpeechRecognizer`). The Opus page's claim that audio goes through `SpeechAnalyzer` is wrong: that branch is behind `#if canImport(SpeechAnalyzer)`, a module that does not exist.
- OI-0085 zero-copy image path: the render allocates a full-page bitmap; what is zero-copy is skipping the PNG round trip, not the raster itself.

### Can you explain it?

1. Explain how the app decides between the text layer and OCR for a PDF.
2. Give the three DPI figures and what each is for (144, 180 or 360, 360).
3. Name the two Vision requests and what each one does.
4. Explain why OCR languages are narrowed and what it cost before.
5. Say which speech API actually runs and why the newer one does not.

### Quiz

<details><summary><strong>How does the app decide whether a PDF needs OCR?</strong></summary>

It samples the page with the most native text (at least 50 characters), renders it and runs a quick OCR pass. If the native text is garbled compared with what Vision reads, every page goes through OCR. A PDF with no text layer at all simply goes to OCR.

</details>

<details><summary><strong>At what resolution are pages rendered for OCR, and how is that set?</strong></summary>

360 DPI: `renderPDFPageAsImage(page:scale: 5.0)`, five times the 72 point base. The complexity triage renders at 144 DPI and the structure pass at 180 DPI downscaled, or 360 for high-risk pages.

</details>

<details><summary><strong>Which Vision request performs OCR, and which reads tables?</strong></summary>

`VNRecognizeTextRequest` with `.accurate` and language correction performs OCR. `RecognizeDocumentsRequest` reads layout, rows and columns on the pages the triage selects.

</details>

<details><summary><strong>Which speech API transcribes audio in shipping builds?</strong></summary>

`SFSpeechRecognizer` through `AudioTranscriptionService`, with `requiresOnDeviceRecognition = true`, in segments of at most 600 seconds. The `SpeechAnalyzer` code path is guarded by a module that does not exist and never compiles.

</details>

<details><summary><strong>What is the largest file the app will read?</strong></summary>

500 MB for files that cannot be streamed. Larger ones are rejected before reading, because loading them into a String would take 1.5 to 2 GB.

</details>

---

## Module 03. Document analysis, adaptation, and derived knowledge

**What it is.** Reading between the lines. Summaries, entities, classifications and specifications derived from the document so that later stages have more than raw text to work with.

**In the bank's words.** After reading the file, the app adds labels: what kind of document is this, what names and codes are important, where are the references, and should it also make a short summary?

**Why it exists.** Some questions are about a document, not about a passage in it. **RAPTOR-lite** adds one summary chunk per document (the L1 level) so an overview question can be routed to summaries instead of forty near-identical body chunks. **GraphRAG-lite** builds an entity index so a question about a name, part number or drug can expand to the chunks that mention it even when the wording differs. Classification and specification detection let the retrieval stage boost the right kind of chunk for the right kind of question.

**Where it runs.** After embedding, in the ingestion loop: vocabulary learning and Vision-entity learning at Steps 4.1 and 4.1b, the document summary at Step 4.5 (one language model call, only when summaries are enabled), content tags at Step 5 on iOS 26 and later.

### The word bank (15 concepts)

| Concept | Status | In one sentence |
|---|---|---|
| Chunk abstraction level | Core | Metadata distinguishing detail L0, document summary L1, and reserved future cluster or library summaries L2-L3. Queries at different scopes need different evidence granularity. |
| Content tagging | Conditional | Foundation Models extraction of topics, actions, emotions, and objects with an NLTagger fallback and timeout. Tags improve library navigation and retrieval vocabulary, but must not block ingestion if the model is unavailable. |
| Derived metadata | Core | The set of section, page, offsets, keywords, entities, abbreviations, structure, numeric flags, siblings, bounds, table data, and abstraction level attached to a chunk. Ranking, expansion, citation, and verification need more… |
| Document classification | Conditional | Assignment of a broad document category or structural class from text and visual signals. Category can guide chunking, suggestions, and diagnostics without hardcoding a domain-specific parser. |
| Document summary chunk | Conditional | A short level-1 summary generated from representative detail chunks, embedded, and indexed as a special chunk. Overview questions should not require retrieving dozens of detail passages. |
| Entity extraction | Core | Identification of names, organizations, places, and other salient terms attached to chunk metadata. Entities provide high-signal lexical fields and enable cross-document expansion without another full vector search. |
| Entity index | Conditional | A persisted forward and reverse mapping between normalized entity names and chunk IDs, with document and container scope. It enables O(1)-style cross-document correlation and GraphRAG-lite expansion from entities already found in… |
| Entity normalization | Conditional | Lowercasing and removal of periods, hyphens, and whitespace to align variants such as U.S.A. and USA or Core Data and CoreData. |
| GraphRAG-lite | Conditional | Expansion from retrieved chunks to other chunks connected by shared entities or explicit document relationships. Vector similarity may miss a relevant passage that uses a different wording but shares an important named entity or… |
| Predictive pre-scan | Core | A sample-based analysis of early pages or characters that estimates code, mathematics, lists, tables, columns, and vocabulary before the full import. Chunking and OCR configuration are expensive to change after every page has… |
| RAPTOR-lite | Conditional | A shallow hierarchical retrieval design using level-0 detail chunks and level-1 document summaries. It offers fast overview routing without the cost and complexity of recursively clustering and summarizing the whole corpus. |
| Reference-list detection | Core | Identification of bibliography or reference sections so they can be penalized, excluded from samples, or treated differently. Reference pages contain dense names and numbers that can dominate retrieval despite not answering the… |
| Representative-text sampling | Conditional | Selection of the first chunk, high-semantic-density chunks, and the final chunk within a strict character budget for summary generation. Feeding the entire document exceeds context, while only taking the beginning misses… |
| Spatial document analysis | Conditional | Analysis of page positions and regions to connect visual or structured elements with surrounding text. Diagrams, captions, and table context can be lost if spatial relationships are discarded too early. |
| Specification detection | Core | Domain-agnostic recognition of structural patterns such as codes, standards, measurements, grades, part numbers, percentages, ranges, and ratios. Exact values are often more reliably extracted by shape than inferred by a model. |

### Can you explain it?

1. Explain RAPTOR-lite as it exists here, not as the paper describes it.
2. Say what GraphRAG-lite indexes and when it is used.
3. Explain why summaries are optional and what turns them on.
4. Describe what the predictive pre-scan looks at.

### Quiz

<details><summary><strong>What is RAPTOR-lite in this app?</strong></summary>

A single summary chunk per document, the L1 level, generated by one language model call after embedding and stored so overview queries can be routed to summaries first. There is no full recursive tree; L2 and L3 are reserved names.

</details>

<details><summary><strong>What does GraphRAG-lite give retrieval?</strong></summary>

An entity index and graph edges between chunks, used for entity expansion and graph-hop context allocation at query time.

</details>

<details><summary><strong>When is a document summary generated?</strong></summary>

At ingestion Step 4.5, only when `enableDocumentSummaries` is on. It costs one language model call per document.

</details>

<details><summary><strong>What does content tagging do and which framework does it?</strong></summary>

It runs Apple's on-device tagging and entity recognition (NaturalLanguage) over the ingested text so keywords, authors and section headers are attached to each chunk record, where BM25 column weights can favour them.

</details>

---

## Module 04. Chunking and tokenizer integrity

**What it is.** Cutting the document into index cards that fit the embedding model, without slicing a table in half.

**In the bank's words.** This is where a big book becomes useful index cards. The cards must be small enough to fit, but large enough to still make sense.

**Why it exists.** The embedding model reads at most 510 word-piece tokens and **silently truncates** anything longer, filing an embedding of the first 510 tokens under the identity of the whole chunk. That is index corruption nothing downstream can detect. So the chunker caps at 310 words, leaves room for a contextual prefix, and then the real tokenizer validates every chunk at 430 tokens plus 80 reserved for the prefix. Overlap keeps a sentence on a cut from being lost; tables and lists are atomic. The **contextual prefix** exists because a chunk read alone has lost what it is about, and that measurably hurts retrieval.

**Where it runs.** CPU. `SemanticChunker` builds chunks; `DocumentProcessor.enforceTokenLimitOnChunks` validates them with the Rust-backed tokenizer that the embedding provider also uses for counting.

### The word bank (21 concepts)

| Concept | Status | In one sentence |
|---|---|---|
| 510-token embedding ceiling | Core | The maximum safe sequence length used by the default sentence embedder after reserving model special tokens. Exceeding it risks silent truncation and index corruption. |
| Actual tokenizer validation | Core | Counting the exact word-piece tokens with the tokenizer paired to the embedding model before accepting a chunk. Word count is only an estimate. |
| Atomic structural block | Core | A table, list, warning, or other structure that the chunker avoids splitting internally. A cell without its header or a warning without its conditions can become misleading evidence. |
| Chunk | Core | A passage-sized retrieval unit derived from a document, carrying content, source identity, metadata, and usually an embedding. Whole documents are too broad for precise ranking and too large for model context. |
| Chunk offset | Core | The character or byte start and end positions locating a chunk or selected sentence inside source content. Exact offsets enable source jumping, citation quotes, and post-retrieval sentence selection without fuzzy text searches. |
| Chunk overlap | Core | Repeated trailing context from one passage at the beginning of the next. Overlap protects facts and sentences near a boundary from being split out of both useful retrieval units. |
| Chunk semantic type | Core | A label such as prose, structural table, semantic table, list item, or warning. Different structures deserve different ranking, packing, and verification treatment. |
| Contextual prefix | Core | A short document and section label prepended to the text used for embedding. A passage removed from its document can lose its subject. |
| Cross-reference metadata | Conditional | References from one chunk to a page, table, figure, section, chapter, appendix, or step. Manuals often answer a question indirectly by pointing elsewhere. |
| Linguistic transition boundary | Core | A break triggered by a small set of English discourse phrases such as However or In conclusion. Transitions often signal a new argument or summary and can improve passage coherence. |
| Maximum chunk size | Core | The hard ceiling, currently designed around no more than about 310 words before additional tokenizer validation. An overlong passage risks embedding truncation and consumes too much generation context. |
| Mixed chunk strategy compatibility | Core | The ability to retain chunks made with different sizes or overlap settings in one vector space. Chunk boundaries change what a vector represents but do not change the coordinate system, so old and new chunks remain comparable. |
| Parent content | Core | A larger source span retained beside the smaller retrieval chunk. Small chunks rank precisely, but generation and citations may need the surrounding paragraph or row context to interpret them correctly. |
| Section-heading boundary | Core | A forced or preferred chunk break around detected headings. A heading defines local topic and is also valuable retrieval metadata. |
| Semantic density | Support | A heuristic indication of how information-rich a passage is. Density helps choose representative chunks for document summaries and can support diagnostics or prioritization. |
| SemanticChunker | Core | The chunk-building service that uses sentence boundaries, section headings, structural blocks, and linguistic transition phrases to form bounded passages. It preserves coherent units better than fixed character slicing and… |
| Sentence boundary | Core | A Natural Language tokenizer boundary used as the smallest ordinary prose split point. Breaking inside a sentence harms meaning, offsets, and citation quality. |
| Sibling group | Core | Metadata linking chunks created from the same section, page, or structural parent. Retrieval can recover one precise hit and then restore adjacent context without broadening the search globally. |
| Target chunk size | Core | The preferred word count toward which the chunker accumulates content. A target balances semantic completeness against retrieval precision and embedding limits. |
| Tokenizer-model pairing | Core | The requirement that the tokenizer vocabulary and preprocessing recipe match the model that consumes the token IDs. A valid tensor produced by the wrong tokenizer does not represent the intended text and can destroy retrieval… |
| Word-piece token | Core | A model vocabulary unit that may be a whole word, fragment, punctuation mark, or symbol. Embedding sequence limits are measured in tokens, not words or characters, so technical text can consume capacity unexpectedly quickly. |

### Can you explain it?

1. Give the numbers: 310, 260, 50, 100, 510, 80, 430, and say what each is.
2. Explain why a word count is not a token count and what went wrong when a padding block made the counter a constant.
3. Say why chunk strategy can change mid-library but the embedding model cannot.
4. Explain what the contextual prefix contains and why it is prepended before embedding.

### Quiz

<details><summary><strong>Why is the chunk ceiling 310 words?</strong></summary>

The model's usable limit is 510 tokens. At roughly 1.5 tokens per word that is about 340 words, minus about 30 words of contextual prefix, which leaves 310.

</details>

<details><summary><strong>What does the tokenizer validation step do, and why was it added?</strong></summary>

It encodes every chunk with the real tokenizer and splits any chunk over 430 tokens (510 minus 80 reserved for the prefix). It was added after a padding block turned the token counter into a constant and 55% of every document was truncated at embedding while every log line read healthy.

</details>

<details><summary><strong>What happens to a chunk that is still too long after splitting?</strong></summary>

It is logged as oversized and the model truncates it at embedding. The tail is lost silently.

</details>

<details><summary><strong>Why can chunk size change without a rebuild while an embedding change requires one?</strong></summary>

Similarity is defined across chunks of any size in the same vector space. Changing the model, dimension, tokenizer or pooling changes the coordinate space itself, so old and new vectors cannot be compared. Embedding changes are blocked during ingestion and force a full re-embed.

</details>

---

## Module 05. Embeddings and vector semantics

**What it is.** Turning meaning into coordinates. Every chunk gets a 384-number position; the question gets one too; nearby means related.

**In the bank's words.** Each chunk gets a location on a map of meaning. The question gets a location too, and nearby locations may talk about similar things.

**Why it exists.** Lexical search cannot find `SAE 0W-20 synthetic` when the question says `what oil does my car take`. A dense embedding can, because the two land near each other. 384 dimensions is the model's fixed width (MiniLM-L6-v2) and small enough that a whole library stays memory-mappable on a phone. Vectors are **L2-normalised** at write time so cosine similarity collapses to a dot product at search time. The **embedding fingerprint** on each library records model, dimension and pooling so two incompatible vector spaces can never be mixed.

**Where it runs.** Core ML by default, with `MLModelConfiguration.computeUnits` chosen from the GPU execution profile: the lower two profiles request CPU plus Neural Engine, the upper two request all units, and Core ML places each layer. On iOS 27 and macOS 27 the default becomes the Core AI provider, which exposes no placement at all. The model is not loaded at launch; it loads on the first `embed()`. Batches over four texts run in a task group sized by the device tier.

### The word bank (33 concepts)

| Concept | Status | In one sentence |
|---|---|---|
| Apple Foundation Models embedding provider | Dormant | A nominal 1,024-dimensional provider scaffold intended for future Apple Foundation Models embedding support. The abstraction anticipates a native Apple embedding capability while preserving the provider interface. |
| Attention mask | Core | A tensor marking which token positions are real input and which are padding. Pooling padded positions would dilute the passage vector and make output depend on batch padding rather than text. |
| Attention-masked mean pooling | Core | Averaging token-state vectors while excluding padded positions according to the attention mask. The model exports token embeddings, not a trustworthy ready-made sentence vector. |
| Bi-encoder | Core | An architecture that encodes the query and each passage independently into vectors, then compares those vectors. Independent passage vectors can be precomputed once during ingestion, making corpus-wide retrieval fast enough on… |
| Core AI sentence provider | Conditional | An iOS/macOS 27 provider for the same 384-dimensional model through Apple's newer Core AI compilation path when available. It creates a future-facing execution path without changing the vector space or forcing a library rebuild… |
| Core ML sentence provider | Core | The default provider that loads the bundled embedding model, builds tensors, runs inference, pools token states, and normalizes the result. Core ML provides a supported on-device execution layer and lets Apple schedule work… |
| Cosine similarity | Core | The normalized dot product measuring the angle between query and passage vectors, conventionally in the range minus one to one. It compares semantic direction without allowing vector magnitude to dominate. |
| Default MiniLM provider | Core | The shipped 384-dimensional MiniLM-L6-v2 sentence embedder executed through Core ML. It offers a compact, local semantic space with manageable storage and fast exact similarity on Apple hardware. |
| Document-chunk embedding | Core | The vector generated from a chunk's contextualized text during ingestion. It is the reusable semantic representation searched by every later question. |
| Dot product | Core | The sum of coordinate-wise products between two vectors. With normalized embeddings it is the computational core of cosine similarity and maps efficiently to Accelerate, BNNS, and Metal. |
| Embedding | Core | A fixed-length numeric representation of a passage or question whose geometry approximates semantic similarity. It lets the engine retrieve conceptually related text even when the user and document use different words. |
| Embedding batch | Core | A group of passages processed together through one provider invocation. Batching amortizes model setup and uses matrix-oriented hardware more efficiently than one passage at a time. |
| Embedding concurrency | Support | The number of embedding operations allowed to execute simultaneously. Too little concurrency underuses hardware, while too much competes for memory and can destabilize Core ML or Vision workloads. |
| Embedding dimension | Core | The number of coordinates in one vector, such as 384 or 512. Similarity requires both vectors to occupy the same dimensional space. |
| Embedding fingerprint | Core | A persisted identity for the provider, model, dimension, tokenizer, pooling behavior, and related vector-space-defining settings. It prevents the engine from mixing vectors that look structurally valid but are semantically… |
| Embedding space | Core | The coordinate system learned by one model and preprocessing recipe. Equal vector lengths do not guarantee comparability. |
| Embedding translation target | Conditional | An optional language into which embedding text is translated before vectorization while preserving original source text for display and citation. Cross-language retrieval can improve when all vectors share one embedding language,… |
| Embedding validation | Core | Checks for expected dimension, finite values, nonempty output, and other integrity conditions. NaN values, wrong widths, or silent truncation can poison every similarity result while still serializing successfully. |
| EmbeddingProvider | Core | The protocol that standardizes model identity, vector dimension, sequence limit, availability, batching, and embedding generation across implementations. A library must know exactly which coordinate system produced its vectors… |
| EmbeddingService | Core | The actor that owns provider selection, model loading, validation, batching, caching, and error handling for embeddings. One authority prevents documents and queries from accidentally using different providers or vector… |
| L2 norm | Core | The Euclidean length of a vector, calculated as the square root of the sum of squared coordinates. Vector length must be known to normalize embeddings and compute cosine similarity efficiently. |
| L2 normalization | Core | Dividing every coordinate by the vector's L2 norm so its length becomes one. For unit vectors, cosine similarity reduces to a dot product, which is faster and more numerically consistent across providers. |
| NLContextualEmbedding provider | Conditional | A 512-dimensional Natural Language framework provider retained as a compatibility option. It allows a system embedding path on supported OS versions but represents a different vector space from MiniLM. |
| NLEmbedding provider | Conditional | A 512-dimensional compatibility provider that averages available word embeddings from Apple's Natural Language framework. It supplies a fallback semantic representation where the preferred sentence model is unavailable. |
| Provider agreement test | Support | A test that compares output shape and semantic behavior across compatible embedding backends. A new runtime backend should preserve the vector space expected by existing libraries rather than merely compile. |
| Query embedding | Core | The vector generated from the user's effective search query. It places the question in the same semantic space as document chunks so nearest passages can be found. |
| Re-embedding | Core | Regenerating every chunk vector in a library under a new embedding fingerprint. Changing the model, dimension, tokenizer, or pooling invalidates all old similarities, so partial migration would mix coordinate systems. |
| Semantic query cache | Support | A local table storing embeddings or semantic results for previously seen normalized questions. Repeated questions can skip model embedding work and reduce latency and energy. |
| Sentence embedding | Core | An embedding model optimized to place sentence- or passage-level meanings into one shared vector space. A token-level model output is not directly searchable as one passage. |
| Special tokens | Core | Model-specific boundary tokens such as classification and separator markers inserted around content. The pretrained model expects the same input framing it saw during training, and those tokens consume part of the sequence limit. |
| Token IDs | Core | Integer vocabulary identifiers produced by the paired tokenizer for each model input token. The model consumes numbers rather than strings, and their meaning depends entirely on the tokenizer-model pairing. |
| Token-state tensor | Core | The model output containing one contextual vector for every input token position. A sentence model must derive one passage representation from these many token-level states. |
| Zero-vector fallback | Support | A correctly sized all-zero embedding returned or substituted when a noncritical provider failure must not corrupt array shape. It prevents crashes and dimension mismatch, while downstream validation can identify that the semantic… |

### Corrections

- OI-0570 Neural Engine, status Core: no line places work on the Neural Engine. Five lines *permit* it. Say "requested", never "runs on".
- OI-0126 Core AI provider is Conditional in the bank, but on iOS 27 and macOS 27 `SettingsStore` makes it the default and migrates saved Core ML defaults, so on those systems it is the primary path.
- OI-0122 Apple Foundation Models embedding provider: a 1,024-dimension placeholder that must never be described as shipped. The bank has this right.

### Can you explain it?

1. Say why 384 and what fixes it.
2. Explain attention-masked mean pooling in one sentence.
3. Explain why normalising at write time makes search cheaper.
4. Give the compute-unit request for each of the four GPU profiles.
5. Say what the fingerprint prevents.
6. Name the four providers and their status.

### Quiz

<details><summary><strong>Why are vectors normalised when they are stored?</strong></summary>

So that cosine similarity, which needs both norms, becomes a plain dot product at search time. The norms are stored separately in `_norms.bin` for the CPU path that uses raw dot products.

</details>

<details><summary><strong>What does the Efficiency profile ask Core ML to use for embeddings?</strong></summary>

`.cpuAndNeuralEngine`: the GPU is excluded on purpose because the Neural Engine is the efficient unit for this work. Balanced, Performance and Maximum ask for `.all` during ingestion.

</details>

<details><summary><strong>What was the ladder bug fixed on 2026-08-26?</strong></summary>

Maximum requested `.cpuAndGPU`, which excludes the Neural Engine, so the top profile did less than Performance. It now requests `.all`.

</details>

<details><summary><strong>When does the embedding model load?</strong></summary>

On the first `embed()` call, not at launch. Only the tokenizer loads at start-up, because token counting is needed before any embedding.

</details>

<details><summary><strong>What is an embedding fingerprint?</strong></summary>

A record on the library of the provider, dimension and pooling recipe used to build its vectors. A different fingerprint means a different coordinate space, so ingestion is blocked until the library is rebuilt.

</details>

---

## Module 06. Lexical indexing, SQLite, and vector persistence

**What it is.** Two filing systems for the same cards: SQLite FTS5 for exact words, a memory-mapped vector store for meaning, plus the machinery that searches the vectors.

**In the bank's words.** The app keeps several filing systems. One remembers exact words, one remembers meaning coordinates, and one remembers facts about where everything came from.

**Why it exists.** Neither index is enough alone. Exact identifiers, part numbers and rare words are BM25's territory; paraphrase is the vector's. FTS5 keeps nine tables, and the `chunks` table weights `section_title` at 10, `section_path` at 5 and `content` at 1 so a match in a heading outranks the same word in prose. Vectors live in `_vectors.bin`, memory-mapped so a library's embeddings cost no heap; norms are in `_norms.bin`. Writes are atomic file swaps. **WAL** lets reads continue during a write.

**Where it runs.** FTS5 is CPU and disk, inside an actor, with a 3 s busy timeout. Vector similarity has a two-level switch: at 1,000 or more vectors **and** a Metal device present, the mapped buffer goes to a Metal kernel with no copy; below that, CPU Accelerate, using one `vDSP_mmul` when the count exceeds the device's batch threshold (16 on M-series) and per-vector `vDSP_dotpr` otherwise. The user's GPU profile does not gate this path.

### The word bank (49 concepts)

| Concept | Status | In one sentence |
|---|---|---|
| 1,000-chunk GPU threshold | Conditional | The documented switching point near which large exact vector search becomes eligible for Metal. It avoids paying GPU overhead on small libraries while exposing parallelism on larger ones. |
| _norms.bin | Core | The binary file of precomputed L2 norms corresponding to stored vectors. Precomputing avoids recalculating vector lengths for every question and supports efficient cosine similarity. |
| _vectors.bin | Core | The contiguous binary file of Float32 embedding coordinates for one library. A flat layout supports memory mapping and high-throughput matrix or dot-product operations without object overhead. |
| Atomic vector-store persistence | Core | Writing replacement metadata, vector, and norm artifacts through temporary files and coordinated replacement rather than mutating live files in place. A crash between independent writes could pair new metadata with old vectors… |
| BM25 | Core | A probabilistic lexical ranking function that rewards informative query-term matches while accounting for term frequency, corpus rarity, and field or document length. Exact words, codes, names, and measurements often carry… |
| BM25 b | Core | The parameter controlling document-length normalization; the fallback implementation uses approximately 0.5. It determines how strongly long chunks are penalized relative to average length. |
| BM25 k1 | Core | The parameter controlling how quickly additional term occurrences saturate; the fallback implementation uses approximately 1.5. It sets the balance between a single precise match and many repeated matches. |
| BNNSVectorDatabase | Core | The default exact vector store using compact metadata, contiguous Float32 vectors, precomputed norms, memory mapping, Accelerate/BNNS, and optional Metal acceleration. It provides a serverless search store optimized for Apple… |
| Busy timeout | Core | The wait period, approximately three seconds, allowed when SQLite is temporarily locked. Immediate failure on short-lived contention would turn normal concurrent ingestion and reads into user-visible errors. |
| chunk_structured table | Core | A relational store for structured elements associated with a chunk. Tables, lists, warnings, and detected data need machine-readable recovery beyond the flattened search string. |
| chunk_table_rows table | Core | A table storing individual recovered table rows as rows rather than only as one flattened chunk. Exact lookup often depends on preserving the relationship among cells in one row. |
| chunks table | Core | The FTS5 surface containing chunk identity, source relations, structural fields, and content used for lexical retrieval. Chunks are the operational retrieval unit, so lexical ranking must return the same identities used by vector… |
| Container column scoping | Core | Using a container UUID column in shared tables rather than one SQLite file per library. A shared schema simplifies migrations and global maintenance while queries still enforce library isolation. |
| Content weight | Core | The baseline BM25 weight, approximately 1, for ordinary chunk body text. Body text remains searchable but does not overpower more intentional structural fields. |
| CPU vector path | Core | Accelerate or BNNS dot-product search used below the configured large-corpus threshold. GPU setup has fixed overhead, so CPU SIMD can be faster for smaller libraries. |
| Document-length normalization | Core | The BM25 adjustment that prevents long passages from winning merely because they contain more words and therefore more opportunities to match. A concise specification row can be more relevant than a long chapter that mentions the… |
| document_content table | Core | A relational store for raw or normalized full document text used for direct extraction and citation reconstruction. The chunk index alone may not preserve enough contiguous text for exact source views or rebuilds. |
| document_meta table | Core | A relational table for counts, dates, size, container identity, and other document metadata. Metadata needs exact typed access and updates rather than full-text tokenization. |
| document_pages table | Core | An FTS5 surface for page-level text and boundaries. Page search, citation navigation, and cross-reference repair need evidence at page granularity. |
| documents table | Core | An FTS5 surface for whole-document text. Some searches and diagnostics need document-level matching in addition to chunk-level precision. |
| documents_vocab | Support | An FTS5 vocabulary view exposing terms learned from the active library. Query expansion can use the corpus's own language instead of a generic synonym list that may introduce unrelated concepts. |
| Exact vector scan | Core | Comparing the query against every stored vector rather than traversing an approximate neighbor graph. At local corpus scale, exact search avoids approximate-recall loss and complex index maintenance while remaining fast with mmap… |
| FTS column weight | Core | A per-column multiplier supplied to BM25 so matches in high-signal metadata count more than body-text matches. A query matching a section heading or section path is usually more intentional than one buried in prose. |
| FTS5 | Core | SQLite's full-text-search virtual table engine. Normal SQL substring matching is too slow and does not provide relevance ranking, tokenization, or corpus statistics needed for lexical retrieval. |
| GPU vector path | Conditional | Metal compute search over the memory-mapped vector buffer for sufficiently large candidate sets and an enabled execution profile. Large batches expose enough parallel arithmetic to offset command-buffer setup and accelerate… |
| HNSW | Historical | Hierarchical Navigable Small World approximate-nearest-neighbor indexing associated with the optional Vectura path. Approximate graphs can reduce search work at very large scale, but they add index complexity and may sacrifice… |
| Inverse document frequency | Core | A weight that increases when a term is rare across the corpus and decreases when it is common. Rare identifiers and technical terms discriminate relevant passages better than words occurring everywhere. |
| Inverted index | Core | A mapping from each indexed term to the rows and positions where it appears. It lets the database jump directly to matching chunks rather than scan every passage. |
| Memory mapping | Core | Mapping a file into virtual address space so vector bytes can be accessed through pointers without reading the whole file into a heap array. Large libraries remain searchable with low resident memory and without a copy on every… |
| Metal buffer pool | Support | A cache of reusable size-bucketed MTLBuffers with device-tier memory limits. Repeated allocation can dominate short GPU operations and increase memory fragmentation. |
| Metal residency set | Conditional | A Metal 4 facility that can keep frequently reused buffers resident for lower page-fault overhead. Persistent vector workloads benefit when buffers do not repeatedly migrate or fault into GPU-visible memory. |
| Nine-column chunks FTS schema | Core | The chunk search table whose nine columns align exactly with the BM25 weight vector. Column order is part of the scoring contract. |
| Partial top-k selection | Core | Maintaining only the highest-scoring candidates while scanning instead of sorting every corpus score. The engine needs perhaps tens of hits, not a complete ordering of thousands, so partial selection reduces memory and sorting… |
| persistentJSON vector-store label | Historical | A legacy configuration name that now routes to the BNNS binary/memory-mapped implementation rather than a vectors-inside-JSON database. Keeping the stored enum value preserves compatibility with existing libraries and settings. |
| Porter tokenizer | Core | The FTS tokenizer configuration that applies English stemming so related word forms share a root. A question using run can match a passage using running, improving lexical recall beyond exact surface strings. |
| Section-path boost | Core | The current intermediate BM25 column weight, approximately 5, for a match in the section hierarchy. A section path preserves topic context that may not be repeated in every chunk body. |
| Section-title boost | Core | The current high BM25 column weight, approximately 10, for a match in the chunk section title. Headings are concise semantic labels and often answer navigation-style queries directly. |
| SQLite | Core | The embedded relational database that stores document text, metadata, chunks, pages, structured content, table rows, vocabulary, and query cache. It provides transactional local persistence and queryable structure without a… |
| SQLite transaction | Core | A group of database writes that either commit together or roll back together. Document metadata, chunks, pages, and structured rows must not become partially visible. |
| SQLiteFullTextService | Core | The actor that owns the shared SQLite connection, schema, transactions, FTS queries, metadata access, and container filters. One serialized database owner prevents connection races and keeps schema and ranking policy centralized. |
| Stemming | Core | Reduction of inflected words to a common search stem. Lexical retrieval otherwise treats many grammatical variants as unrelated terms. |
| Term frequency | Core | How often a query term appears in one searchable row or field. Repeated occurrence increases relevance, but with diminishing returns so keyword stuffing does not dominate indefinitely. |
| UNINDEXED FTS column | Core | A field stored in an FTS row for retrieval or joining but excluded from term indexing. IDs and control metadata must travel with hits without polluting the searchable vocabulary. |
| Vector metadata JSON | Core | The file mapping vector positions to chunk/document identities and metadata required to reconstruct results. The binary float array alone has no source identity, page, text, or deletion semantics. |
| VectorDatabase protocol | Core | The abstraction for storing, loading, searching, deleting, and auditing chunk vectors. Retrieval and SDK code can depend on one contract while the physical store or migration backend changes. |
| VectorStoreRouter | Core | The service that resolves the concrete vector store for a library from its configured vector database kind. One library must consistently read and write one store implementation, and migrations need a controlled switch point. |
| VecturaVectorDatabase | Conditional | An optional adapter for the Vectura/HNSW-style store retained for compatible libraries or migration paths. It preserves access to previously configured approximate stores without making them the default architecture. |
| Virtual table | Core | A SQLite table whose behavior is implemented by an extension such as FTS5 rather than ordinary row storage. It exposes full-text indexing and ranking through SQL while maintaining its own inverted index internally. |
| Write-ahead logging (WAL) | Core | A SQLite journaling mode that writes changes to a separate log before merging them into the main database. It improves read/write concurrency and crash recovery for a UI that may query while ingestion persists data. |

### Corrections

- OI-0155 caveat says the route also depends on the user GPU policy. It does not; the conditions are the 1,000 count and `isGPUAvailable`. The profile gates Core ML units and the MMR matrix.

### Can you explain it?

1. List the nine tables.
2. Give the three FTS column weights and the tokenizer.
3. Explain memory mapping and what it saves.
4. State both conditions for the GPU path and both tiers of the CPU path.
5. Explain why two live instances must never map one file.

### Quiz

<details><summary><strong>What are the two conditions for vector search to use the GPU?</strong></summary>

At least 1,000 vectors in the container, and a Metal device with a command queue. The GPU execution profile is not consulted on this path.

</details>

<details><summary><strong>What does the CPU path do above the batch threshold?</strong></summary>

One `vDSP_mmul` over the whole mapped buffer, then normalisation by the stored norms. Below the threshold it loops `vDSP_dotpr` per vector. The threshold is 16 on M-series and `Int.max` on unsupported devices.

</details>

<details><summary><strong>Which FTS5 columns are indexed and how are they weighted?</strong></summary>

`section_title` (10), `section_path` (5) and `content` (1), tokenised with `porter unicode61`. IDs, page number and structure type are `UNINDEXED`.

</details>

<details><summary><strong>How many SQLite tables are there and name three?</strong></summary>

Nine: `documents`, `chunks`, `document_pages`, `documents_vocab`, `chunk_structured`, `chunk_table_rows`, `document_content`, `document_meta`, `semantic_query_cache`.

</details>

<details><summary><strong>What does the busy timeout do?</strong></summary>

`PRAGMA busy_timeout=3000` makes a writer wait up to three seconds for a lock instead of failing immediately, which matters when ingestion and a query touch the database together.

</details>

---

## Module 07. Query understanding, intent, and execution planning

**What it is.** Understanding the question before searching. What kind of answer is wanted, how hard it is, and what plan to run.

**In the bank's words.** This is the dispatcher. It listens to the question and decides whether it is a tiny fact hunt, a comparison, a summary, a procedure, or a big investigation.

**Why it exists.** The same pipeline cannot serve `what is the torque spec` and `summarise this contract` equally. Intent classification routes overview questions to summaries and lookups to chunks; complexity decides whether a single pass will do or the planner should escalate; **query rewriting** and **HyDE** exist because users write short, vague questions and the index was built from long, specific text. The **semantic query cache** exists because the same question is asked twice more often than you would think. All of this is resolved once, up front, into a `QueryExecutionPlan` by `QueryRuntimeCoordinator`, which also decides PCC eligibility and whether the run is agentic.

**Where it runs.** CPU for classification and planning; a Foundation Models call for rewriting when it is enabled. `QueryRuntimeCoordinator.resolveContext` is the first thing `queryInternal` does.

### The word bank (45 concepts)

| Concept | Status | In one sentence |
|---|---|---|
| Agentic query | Conditional | A request or mode whose answer is produced through multiple retrieval and reasoning sessions rather than one generation pass. Some questions require evidence discovery, gap assessment, reformulation, and synthesis that cannot be… |
| Answer intent | Core | The classification of the form of answer requested, such as lookup, table lookup, procedure, comparison, summary, investigation, computation, or findings. The correct evidence and response shape differ radically between an exact… |
| Compare intent | Core | A request to contrast two or more entities, documents, methods, or states. Comparison requires balanced evidence for each side and explicit dimensions rather than one globally highest-ranked passage. |
| Complex query | Conditional | A multi-part, comparative, explanatory, or otherwise broad request that warrants more candidates and context. The probability that one passage covers the whole answer decreases as the question spans more concepts. |
| Compute intent | Conditional | A request to calculate a result from values found in the corpus. The engine must retrieve exact operands, preserve units, and distinguish source facts from the derived calculation. |
| Constrained-synthesis prompt mode | Core | A prompt mode allowing composition across evidence while requiring source-grounded claims and citations. Procedures, comparisons, and explanations need synthesis but still must remain bounded by retrieved context. |
| Container vocabulary expansion | Conditional | Expansion using terms actually present in the active library's FTS vocabulary. Corpus-native language is less likely than generic synonyms to pull retrieval into unrelated domains. |
| Cross-reference query | Conditional | A question whose evidence may be located at a page, table, figure, or section referenced by another retrieved passage. Technical manuals frequently answer through see page X rather than repeating the data. |
| Decomposed execution | Conditional | A plan that breaks the question into smaller subquestions whose evidence can be retrieved and combined. One embedding for a multi-clause question can average away important components and retrieve passages that address only one… |
| Descriptive keyword | Core | A non-identity query term that states the requested property, such as reference, capacity, route, or dosage. The entity identifies the thing; the descriptive keyword identifies which attribute of that thing is wanted. |
| Direct execution | Core | A plan that sends one effective query through the normal retrieval, packing, generation, and verification path. It minimizes latency when decomposition is unnecessary. |
| Direct-extraction prompt mode | Conditional | A model prompt that asks for an answer copied or tightly derived from the evidence rather than free-form synthesis. Even when deterministic extraction cannot decide, lookup-style questions should minimize unsupported paraphrase. |
| Entity extraction from query | Core | Detecting names, model numbers, standards, dates, products, and other high-value anchors in the question. Entities often determine which exact record or document the user means and guide disambiguation. |
| Findings intent | Conditional | A research-style request for reported findings, authors, studies, outcomes, or evidence patterns. Research documents require evidence aggregation and source attribution rather than a generic topical answer. |
| Forced agentic execution | Conditional | A user action such as Go Deeper that explicitly reruns or continues a question through the agentic path. The user can request additional search and reasoning even when the initial planner chose Standard. |
| GroundedAnswerPolicy | Core | The policy deciding whether an intent should use deterministic extraction, direct-extraction prompting, constrained synthesis, and source-only verification. It keeps exact lookup from being needlessly generated and ensures… |
| HyDE | Conditional | Hypothetical Document Embeddings, where a model writes a plausible answer-like passage whose embedding is used as an additional retrieval query. A short or abstract question may embed poorly, while a hypothetical answer can… |
| Hypothetical document | Conditional | The generated answer-like text used by HyDE only as a retrieval probe. It enriches semantic vocabulary without being treated as evidence or shown as a sourced answer. |
| Investigate intent | Conditional | A broad exploratory request that may require multiple evidence threads, relationships, and iterative retrieval. The answer cannot usually be reduced to one value or one top passage. |
| Keyword search intent | Core | A signal that exact terms, codes, quoted phrases, or short identifiers are central to the question. Dense embeddings can blur rare identifiers, so lexical candidates and lower extractive thresholds deserve more weight. |
| Lookup intent | Core | A request for a specific fact, value, code, date, name, or short answer. Lookup questions benefit from high precision, exact identifiers, structured extraction, and lower tolerance for synthesis. |
| Overview query | Conditional | A question asking what a document, corpus, or topic is generally about rather than for one local detail. Fine-grained chunks can overfit incidental mentions, while summary chunks better represent whole-document themes. |
| Planner escalation | Conditional | Automatic promotion from a nominal Standard request to the agentic path when the execution planner predicts that one pass is insufficient. It allows complexity rather than the mode label alone to control work. |
| Primary entity | Core | The strongest identity-bearing token or phrase in a lookup, such as 1688, a device model, or a named product. A candidate containing the primary entity can resolve ambiguity among otherwise similar specifications. |
| Procedure intent | Core | A request for ordered steps, instructions, setup, troubleshooting, or a process. Procedures need adjacent sequence context and should not be answered from one isolated matching sentence. |
| Query complexity | Core | A classification such as trivial, standard, complex, or agentic derived from length, conjunctions, comparisons, reasoning markers, entities, and intent. Complexity controls how much retrieval, rewriting, context, time, and model… |
| Query decomposition | Conditional | Splitting one complex request into atomic subquestions or facets. Separate retrieval probes reduce semantic averaging and make missing coverage visible. |
| Query expansion | Conditional | Adding synonyms, related terms, entities, abbreviations, or corpus vocabulary to improve recall. The relevant passage may use a technical term the user does not know or an acronym the user spelled out. |
| Query normalization | Core | Cleaning and canonicalizing the user question for stable comparison, tokenization, cache lookup, and downstream heuristics. Whitespace, punctuation, casing, and conversational phrasing can create accidental differences that do… |
| Query rewriting | Conditional | Producing a cleaner, standalone, retrieval-oriented version of the user's question. Conversational pronouns, ellipsis, vague phrasing, and extra words can lower both lexical and dense retrieval quality. |
| Query variation | Conditional | An alternative phrasing generated after weak or repetitive retrieval. A different wording can access lexical or semantic neighborhoods missed by the original expression. |
| QueryExecutionPlan | Core | The explicit decision about direct execution, decomposition, tool use, agentic escalation, and response strategy for one question. A profile describes the question; a plan says what the engine will actually do about it. |
| QueryProfile | Core | The per-question summary of word count, entities, answer intent, search intent, routing classification, complexity, and other decision signals. Every conditional stage needs one coherent interpretation of the question instead of… |
| Response strategy | Core | The plan to use deterministic extraction, constrained synthesis, extractive summarization, or agentic synthesis. The safest and cheapest answer mechanism depends on intent and evidence structure. |
| Routing classification | Core | A query label describing whether the request is direct, cross-topic, overview, or otherwise needs a specialized retrieval route. Search architecture should respond to the shape of the information need, not just the words in the… |
| Search intent | Core | The classification of how evidence is likely to be found, including semantic, keyword, hybrid, or overview-oriented search. A model number should lean lexical while a paraphrased concept needs dense retrieval; overview questions… |
| Semantic search intent | Core | A signal that meaning and paraphrase matter more than exact surface terms. The document may express the answer with different vocabulary than the user. |
| Specification-heavy query | Conditional | A question likely to require codes, measurements, standards, capacities, or other exact technical values. These questions need structured and numeric evidence boosts and stricter unit verification. |
| Standalone rewrite | Conditional | A rewrite that resolves references such as it, that one, or the previous result into an explicit question. Retrieval does not see the human conversational context unless it is incorporated into the query. |
| State-lookup query | Conditional | A request about indicator colors, solid/flashing states, status lights, or similar mappings. The requested answer depends on co-occurrence of a state and its meaning, so generic semantic similarity can choose the wrong row. |
| Subquestion | Conditional | One atomic information requirement derived from a larger user question. Coverage and stopping can be measured per requirement rather than by answer length or source count. |
| Summarize intent | Core | A request to condense a document, section, topic, or result set. A summary should maximize coverage and reduce redundancy rather than retrieve only the single strongest exact hit. |
| Table-lookup intent | Core | A lookup whose answer is expected in a row, cell, key-value table, or other structured record. Flattened prose ranking can retrieve the right table but return the wrong cell. |
| Touchy query | Core | A query containing safety-critical categories or terms such as dosage, pressure, warning, hazard, maximum, or failure. Wrong precision on a critical limit has a higher cost than a minor descriptive omission, so thresholds should… |
| Trivial query | Core | A short and simple request that can use a reduced candidate set and skip expensive enhancement stages. Running HyDE, iterative retrieval, or agentic sessions on every easy lookup adds latency without proportional quality. |

### Can you explain it?

1. Name the three ways a run becomes agentic.
2. Explain HyDE in one sentence and say what it costs.
3. Say what the semantic query cache stores and what it skips.
4. Explain why routing is decided after retrieval, not here.
5. Define a touchy query and what it changes.

### Quiz

<details><summary><strong>What are the three agentic paths?</strong></summary>

`.agentic` (Deep Think or Maximum selected), `.forcedAgentic` (the user pressed Go Deeper), `.plannerEscalated` (the planner escalated a Standard query). `isAgentic` is true for all three.

</details>

<details><summary><strong>What is HyDE?</strong></summary>

Hypothetical document embedding: the model writes a plausible answer passage, and that passage is embedded instead of the bare question, because passages land closer to passages than questions do. It costs a language model call before retrieval.

</details>

<details><summary><strong>What does the semantic query cache skip on a hit?</strong></summary>

Query embedding (Step 2). The cached vector is reused; the rest of the pipeline still runs.

</details>

<details><summary><strong>What does the QueryRuntimeCoordinator resolve?</strong></summary>

Quality mode, PCC eligibility, adaptive configuration, the query profile and execution plan, and the agentic decision, all before any search.

</details>

<details><summary><strong>What is a touchy query?</strong></summary>

A query in a category such as medical, legal, financial, safety or dosage. It raises the Gate A retrieval-confidence bar from 0.40 to 0.55.

</details>

---

## Module 08. Retrieval, fusion, reranking, and evidence expansion

**What it is.** Finding the evidence. Two searches in parallel, one merged ranking, a second opinion from a cross-encoder, then diversity and neighbours.

**In the bank's words.** Several search teams bring back possible answers. The app combines their lists, asks a smarter judge to reorder them, removes copies, and then looks around the best results for missing context.

**Why it exists.** Vector search and keyword search fail differently, so they run **in parallel** and are merged by **Reciprocal Rank Fusion**, which needs no score calibration between them. The **cross-encoder** reads the question and each candidate together, which a bi-encoder cannot, so it is far better at ranking a short list and far too slow for the whole corpus; that is why it runs on `topK × 3` candidates and not on the library. **MMR** trades a little relevance for coverage so five near-duplicate chunks do not crowd out the second document. **Lexical survivors** are re-attached so an exact identifier hit that fusion buried is not lost.

**Where it runs.** Vector search as in module 06. FTS5 on CPU. Rerank is Core ML with all units permitted and low-precision GPU accumulation allowed, concurrent across pairs. The MMR similarity matrix goes to Metal when there are more than 50 candidates, the profile allows Metal vector ops, and a GPU exists.

### The word bank (60 concepts)

| Concept | Status | In one sentence |
|---|---|---|
| Acceptance override | Core | A rule allowing candidates through despite a nominal score floor when relative rank, score margin, breadth, or extractive intent provides sufficient evidence. It prevents rigid thresholds from discarding the best available exact… |
| Breadth-first search (BFS) | Conditional | A graph traversal that visits immediate neighbors before progressively more distant hops. BFS provides bounded, interpretable expansion around a retrieved anchor and avoids diving deeply down one arbitrary relationship. |
| Candidate generation | Core | The broad first retrieval step that produces more possible chunks than will ultimately reach the model. High recall must come before high precision because reranking cannot recover evidence that was never retrieved. |
| Corrective retrieval | Conditional | A targeted fallback that rescans for query terms, structured data, numeric patterns, or cross-reference destinations when normal ranking missed the expected evidence shape. Dense and lexical retrieval can retrieve the right topic… |
| Cross-encoder reranking | Core | A second-stage model that reads the query and one candidate passage together and assigns a relevance score. Joint encoding captures fine-grained interactions that independently generated bi-encoder vectors cannot see. |
| Cross-reference repair | Conditional | Following a detected page, table, figure, or section reference and retrieving the destination evidence. A reference-bearing chunk is not itself the answer and can otherwise create a false positive. |
| Dense retrieval | Core | Searching stored passage vectors by cosine similarity to the query vector. It finds semantic equivalents and paraphrases with little or no exact word overlap. |
| Document-order restoration | Conditional | Sorting selected summary sentences back into their original sequence after relevance and diversity selection. Reading a summary in rank order can reverse chronology or logical progression. |
| Dynamic similarity threshold | Core | A per-query adjustment of the configured score floor based on candidate count, top score, spread, intent, and suspected vocabulary mismatch. Absolute cosine scores are not universally calibrated. |
| Entity expansion | Conditional | Fetching chunks connected through entities shared with the query or current evidence. A concept may be discussed across distant sections and documents without repeating the full query phrase. |
| Entity-aware disambiguation | Core | Preferring a candidate that contains the query's primary entity when competing values are otherwise close. It prevents a nearby specification for a similar product from winning over the explicitly named one. |
| Evidence assessment | Conditional | Scoring whether the current results cover the question, contain enough relevance, and leave identifiable gaps. A loop needs an evidence-based reason to continue rather than a fixed number of redundant searches. |
| Explicit state-structure lookup | Conditional | Direct extraction from structured mappings for indicator colors, flashing states, and their meanings. It preserves the exact pairing between a visible state and its interpretation. |
| Extraction confidence | Core | The score estimating how strongly a candidate value matches the query entity, requested attribute, structure, and proximity signals. A deterministic extractor still needs to abstain when several values are plausible. |
| Extractive QA | Conditional | Returning an answer span copied from retrieved evidence instead of generating new prose. Exact extraction eliminates a major class of hallucination because the returned value must exist in the source. |
| Extractive summarization | Conditional | Selecting source sentences rather than writing a new summary. It reduces generative hallucination and preserves traceable wording for summary requests. |
| Fusion weight | Core | The relative influence assigned to lexical and vector arms around the rank-fusion result. The arms do not necessarily have equal quality in this corpus, so the mixture must be measured rather than assumed. |
| Fusion-stage regression | Support | The measured case where combining a weak dense arm with a stronger lexical arm lowers rank quality relative to BM25 alone. It demonstrates why a theoretically sound architecture still needs instance-specific evaluation and tuning. |
| Graph edge | Conditional | A typed connection between two chunks or entities, such as next, previous, sibling, reference, same section, or shared entity. Edge type preserves why two items are related and supports controlled expansion rather than global… |
| Graph hop | Conditional | One relationship traversal away from an anchor chunk. Hop count approximates relationship distance and limits the blast radius of graph expansion. |
| Graph index | Conditional | An in-memory or derived adjacency structure connecting chunks through siblings, references, entities, sections, pages, and document relationships. Important evidence can be one relationship away from the lexical or semantic hit. |
| Heuristic extractive QA | Conditional | The active Natural Language and rule-based sentence/span scorer using keyword overlap, entity types, proximity, passage rank, and question type. It provides source-bounded extraction without requiring a trained neural start/end… |
| Hybrid search | Core | The coordinated dense and lexical search whose ranked results are merged and then reranked. The two arms have complementary failure modes, so retaining both increases coverage across conceptual and exact queries. |
| Initial candidate breadth | Core | The larger top-k used before expensive reranking, currently mode-dependent at roughly 30, 35, or 50. A cross-encoder can improve order only among candidates it receives, so the first stage must be broad enough to contain the… |
| Iterative retrieval | Conditional | A retrieve, assess, refine, and retrieve-again loop. The first query can miss evidence or reveal terminology needed for a better second search. |
| Jaccard deduplication | Core | A token-set overlap check used to discard expanded content that is substantially redundant, around an 0.8 overlap threshold in the parent service. Parent and child passages naturally overlap, and including both verbatim can… |
| L0 chunk | Core | A normal source-level detail chunk containing directly extracted document content. It is the primary evidence unit for exact facts and citations. |
| L1 summary chunk | Conditional | A document-level summary chunk derived from representative L0 content. It provides an abstraction layer for overview retrieval and broad routing. |
| L2 and L3 abstraction levels | Future | Reserved section- and corpus-level summary layers in the DocumentChunk abstraction enum. Hierarchical summaries could support larger libraries and multi-document overview questions. |
| Lexical retrieval | Core | Searching FTS5 for exact or stemmed query terms and ranking matches with BM25. It is strong on part numbers, standards, names, quotations, and measurements that embeddings may smooth away. |
| Lexical survivor guarantee | Core | A fusion safeguard that retains a sufficiently strong lexical-only result even if dense candidates would otherwise crowd it out. Exact identifiers are often the answer and should not disappear because the semantic arm returns… |
| Maximal marginal relevance (MMR) | Core | A greedy selection algorithm that balances relevance to the query against similarity to already selected results. Top-ranked chunks often repeat the same paragraph, wasting context and hiding complementary evidence. |
| Metadata boost | Core | A post-retrieval score adjustment based on structural and semantic metadata such as headings, entities, table status, numeric data, and exact identifiers. A raw retrieval score cannot capture every evidence-quality signal… |
| Minimum similarity | Core | The score floor below which dense or fused candidates may be rejected. A floor limits irrelevant evidence, but one fixed value fails across domains and embedding vocabularies. |
| MMR lambda | Core | The tradeoff parameter between query relevance and novelty, with lower values putting more emphasis on diversity. Different quality modes can choose whether to concentrate on the strongest passage or cover more independent… |
| Multi-vector retrieval | Conditional | Using several semantic probes for one user request rather than a single query embedding. It increases recall across facets while preserving the original question as the answer objective. |
| Neural start/end span model | Dormant | The planned TinyBERT or DistilBERT extractive QA model with start and end token heads. A trained model could identify exact answer spans more robustly than heuristics. |
| Pairwise similarity matrix | Support | The matrix of candidate-to-candidate cosine similarities used to accelerate diversity calculations. MMR repeatedly asks how similar candidates are to selected items, and precomputing the matrix avoids duplicate dot products. |
| Parallel retrieval arms | Core | Executing vector and FTS search concurrently rather than serially. The arms are independent and latency should approximate the slower one rather than their sum. |
| Parent-document retrieval | Core | Restoring larger parent content around a precisely retrieved child chunk. Small children rank well but may omit definitions, conditions, or headings needed for correct interpretation. |
| Pattern-based specification extraction | Core | Regex and proximity-based discovery of grades, measurements, codes, dates, and similar values in unstructured retrieved text. Not every document produces a clean table, so exact-value answering needs a deterministic fallback. |
| RAPTOR-lite summary routing | Conditional | Routing overview questions to precomputed document-summary chunks at a higher abstraction level. Whole-document questions are better answered by representative summaries than by one incidental detailed chunk. |
| Reciprocal rank fusion (RRF) | Core | A rank-based merge that gives each item a score proportional to the sum of one over k plus its rank in each retrieval list. Dense and BM25 scores live on different scales, while ranks are comparable without fragile score… |
| Redundancy penalty | Core | The MMR subtraction based on the maximum similarity between a candidate and any already selected item. It directly penalizes near-duplicate evidence even when each duplicate is individually relevant. |
| Rerank batch size | Core | The number of query-passage pairs scored in one reranker batch. Batch size controls throughput, memory pressure, and latency on different devices. |
| Rerank score | Core | The model-derived relevance value used to reorder fused candidates. It is a more precise local comparison than the first-stage dense or lexical scores but is calculated over fewer items. |
| Reranker tokenizer | Core | The tokenizer paired specifically with the cross-encoder model. The reranker reads a combined query-passage sequence and cannot safely reuse an arbitrary embedding tokenizer unless the model contract matches. |
| Retrieval cascade | Conditional | A second broader search with more candidates and a stronger lexical weighting when the first result set is weak or sparse. Weak initial retrieval may reflect an overly semantic mix or too-small candidate set rather than absent… |
| RRF constant k | Core | The smoothing constant, conventionally 60 in this implementation, that reduces the dominance of the first few rank positions. It controls how quickly rank contribution decays and makes fusion less brittle to small ordering… |
| Sentence-level relevance | Conditional | The cosine similarity between the query embedding and each candidate sentence embedding. A relevant chunk may contain many irrelevant sentences, so sentence scoring can improve context density. |
| Sibling expansion | Core | Adding adjacent chunks from the same page, section, or sibling group around a strong hit. Procedures and arguments often span chunk boundaries, so one hit should pull its immediate neighborhood. |
| Spec sniper | Conditional | A precision scoring path for chunks that jointly match multiple query concepts and contain numeric, code, key-value, or table signals. It is designed to surface the exact specification row hidden inside a large technical document. |
| Specification boost | Conditional | An increased score for chunks containing relevant measurements, standards, codes, key-value structures, or numeric patterns. Exact technical questions need the passage with the value, not a conceptual explanation of the topic. |
| Stable tie-break | Core | A deterministic secondary order used when candidates have equal or nearly equal scores. Nondeterministic ordering makes tests flaky, citations shift between runs, and benchmark comparisons noisy. |
| State-anchor adjustment | Conditional | A positive or negative score change depending on whether an indicator-state candidate contains the requested color and behavior anchors. A manual may list many lights and meanings; matching only indicator is insufficient. |
| Structured table lookup | Core | Directly matching query entities and requested labels against parsed table rows or key-value structures. A deterministic cell lookup has lower hallucination risk than asking the model to infer the value from a flattened table. |
| Supplementary vector search | Conditional | Additional dense searches using rewritten, expanded, HyDE, or subquestion vectors, followed by deduplicated merge. One query vector cannot represent every facet of a complex question. |
| TinyBERT reranker | Core | The shipped ms-marco-TinyBERT-L2-v2 Core ML cross-encoder used for reranking. A compact model makes joint query-passage scoring feasible on device for a limited shortlist. |
| Top-k | Core | The requested number of highest-ranked results retained at a stage. The pipeline needs bounded work and context, but different stages require different k values to trade recall against cost. |
| Vocabulary mismatch | Core | A detected pattern where many candidates exist but all semantic scores are unusually low and compressed together. Specialized corpus language can make absolute embedding thresholds misleading. |

### Can you explain it?

1. Recite the candidate counts for Standard: 30, 90, up to 60, 36, 90 reranked.
2. Give the RRF formula, k, and the two weights.
3. Explain why the cross-encoder is not run on the whole corpus.
4. Give the similarity floors and MMR lambdas per mode.
5. Explain lexical survivors and the keyword boost cap.

### Quiz

<details><summary><strong>What are the fusion constants?</strong></summary>

RRF with `k = 60`, vector weight 0.7, keyword weight 0.3. Fusion runs off the main thread on a snapshot of the candidates so document-frequency statistics are valid.

</details>

<details><summary><strong>How many candidates does a Standard query gather?</strong></summary>

`initialTopK` is 30. The vector side asks for 90 (30 × 3), FTS5 for up to 60 (min of 30 × 3 and 60), structured rows for up to 36. The reranker scores up to 90 and keeps 90; the similarity floor and MMR cut from there.

</details>

<details><summary><strong>Why does the cross-encoder come after fusion rather than replacing search?</strong></summary>

It reads query and passage together, so it cannot precompute anything and costs one inference per pair. It is accurate on a shortlist and impossible on a corpus.

</details>

<details><summary><strong>What is the MMR lambda per mode and what does lowering it do?</strong></summary>

0.60 Standard, 0.55 Deep Think, 0.50 Maximum. Lower lambda weights diversity more, so Maximum accepts less relevant chunks to cover more of the library.

</details>

<details><summary><strong>What is a lexical survivor?</strong></summary>

A keyword-only hit that fusion pushed below the top-k cut. Up to `max(4, topK / 6)` of them are re-attached so exact matches on identifiers are never lost to paraphrase.

</details>

---

## Module 09. Context selection, compression, and token packing

**What it is.** Deciding what the model actually reads. A hard token budget, an order that fights the model's blind spot, and optional compression.

**In the bank's words.** This is packing a suitcase. The app cannot bring the whole library, so it chooses the most useful evidence and fits it into the model’s limited space.

**Why it exists.** The on-device model has a 4,096-token window and every token spent on evidence is one not available for the answer. So there is a budget: window minus instructions, tools, question, conversation, a 256-token safety reserve and the reserved output. Chunks that do not fit are trimmed and their IDs recorded, not silently forgotten. **Lost-in-the-middle** ordering puts the strongest evidence first and last because models attend poorly to the middle. **Contextual compression** keeps only the sentences that matter, at the cost of a model call and a one-second cooldown to protect the Foundation Models rate budget.

**Where it runs.** CPU. `ContextPackingService` and the token budget in `FoundationModelTokenBudget`, which reads the real window from `SystemLanguageModel.default.contextSize` on iOS 26 and later instead of assuming 4,096.

### The word bank (27 concepts)

| Concept | Status | In one sentence |
|---|---|---|
| 4,096-token on-device limit | Core | The governing on-device Apple Foundation Models context ceiling used by the engine. A naive top-20 chunk set plus prompt and output schema can overflow, causing failure or lost evidence. |
| Available context tokens | Core | The remainder after all fixed prompt, question, tool, safety, and output costs are subtracted from the model limit. This is the actual capacity the retrieval evidence is allowed to consume. |
| Compression expansion guard | Core | Rejecting a compression output when it contains more estimated tokens than the original. Expansion indicates the model paraphrased or hallucinated instead of extracting. |
| Compression passthrough | Core | Returning the original chunk unchanged when it is short, the model is unavailable, compression fails, time expires, or the output is unsafe. Compression is an optimization and must not become a single point of evidence loss. |
| Compression ratio | Conditional | The fraction of estimated tokens retained after contextual compression. It measures whether a compression call actually saved context rather than expanded or duplicated it. |
| Compression time budget | Core | A total wall-clock cap for compressing a batch of chunks. Multiple model calls can dominate query latency and accumulate session context. |
| Context window | Core | The maximum token sequence the language model can consider in one session, including instructions, tools, evidence, conversation, and output framing. The corpus cannot fit, so every upstream retrieval and packing decision exists… |
| ContextPackingService | Core | The deterministic service that chooses and orders core hits, parents, siblings, graph neighbors, and compressed content under a token ceiling. Retrieval rank alone does not solve budget, diversity, sequence, or supporting-context… |
| Contextual compression | Conditional | Using Apple Foundation Models to extract only query-relevant sentences from retrieved chunks while attempting to preserve exact wording. Chunks often contain both useful and irrelevant text, and the 4,096-token window rewards… |
| Core evidence chunk | Core | A high-ranked retrieved passage treated as an anchor that should survive packing if possible. The packer must preserve the strongest direct evidence before spending tokens on context around it. |
| Evidence packet | Core | The final minimized collection of source passages, labels, identifiers, and metadata supplied to the answer stage. It is the boundary between retrieval and generation and defines what the model is allowed to know for this answer. |
| Fresh compression session | Core | Resetting the Foundation Models session between chunk compression calls. Retaining the transcript across chunks accumulates tokens and can overflow the 4,096-token context after several calls. |
| Graph-hop allocation | Conditional | Budget reserved for relationship-derived evidence reached through references or entities. Graph evidence can complete an answer but is usually less directly ranked than the anchor that led to it. |
| Information-density rescue | Core | Selecting source sentences with numbers, entities, colons, codes, or other high-value signals when compression returns no relevant content. Blindly taking the first characters can lose a specification located in the middle or end… |
| Intent-specific packing | Core | Changing evidence allocation and ordering based on whether the user requested a lookup, procedure, comparison, summary, or investigation. The same top-ranked chunks should not be packed identically for every answer shape. |
| Lost-in-the-Middle mitigation | Core | Ordering evidence so high-value passages are placed at context positions less likely to be ignored, commonly at the beginning and end rather than burying all strong evidence centrally. Language models can underuse information… |
| Neighbor allocation | Core | Budget reserved for adjacent or sibling passages. Procedural order and local definitions often cross one chunk boundary. |
| NO_RELEVANT_CONTENT sentinel | Conditional | The exact compression response indicating that the model found no useful sentence in a chunk. A sentinel is easier to distinguish from an empty or malformed response than free-form language. |
| Parent allocation | Core | Budget reserved for larger source spans surrounding core chunks. A precise hit may be uninterpretable without its defining paragraph or table context. |
| Query-echo stripping | Core | Removing an echoed user question from model-compressed text. An echoed query can fool later keyword scoring into treating an irrelevant passage as highly relevant. |
| Question-token cost | Core | The actual or estimated tokens occupied by the user question and effective rewritten form. A long multi-part question leaves less room for evidence and can trigger decomposition. |
| Reserved output tokens | Core | Capacity withheld from input so the model has room to produce the answer and structured fields. Packing evidence to the absolute context ceiling can leave no generation budget and cause truncation or failure. |
| Safety-token reserve | Core | Additional headroom for tokenizer-estimation error, framework wrappers, and variable structured-decoding overhead. A budget that is correct only on average is unsafe under a hard model limit. |
| Source sentence selection | Core | Choosing exact sentences from evidence to maximize query relevance and information density before generation. Retrieval can identify the right chunk while the actual answer sentence remains buried among unrelated prose. |
| System-prompt overhead | Core | Tokens consumed by behavioral instructions, grounding rules, output format, and answer policy. Those instructions are necessary but leave less room for source evidence, so they must be measured in the same budget. |
| Token budget | Core | The explicit accounting of total context limit, instructions, tool schemas, question, conversation, evidence, safety margin, and reserved output. Character or chunk counts are not enough because model capacity is consumed by… |
| Tool-schema overhead | Conditional | Tokens used to describe registered Foundation Models tools and their arguments. Tool calling expands capability but directly competes with evidence for the context window. |

### Can you explain it?

1. Write the evidence-capacity equation from memory.
2. Give the constants: 4,096, 3,200, 256, 1.4 and 2.5 characters per token.
3. Explain lost-in-the-middle ordering.
4. Say what happens to a chunk that does not fit.
5. Explain the compression cooldown.

### Quiz

<details><summary><strong>What is the default token budget and where does it come from?</strong></summary>

3,200 tokens of a 4,096 base window, with a 256-token safety reserve. The real window is read from the system model at runtime and can be larger.

</details>

<details><summary><strong>How does the app estimate tokens from characters?</strong></summary>

1.4 characters per token on device and 2.5 for the cloud fallback estimate, both deliberately conservative.

</details>

<details><summary><strong>What happens to evidence that does not fit the budget?</strong></summary>

The packer stops adding chunks once `usedTokens + tokens` would exceed the budget and records the trimmed chunk IDs, which the retrieval diagnostics can show. Skipped siblings are counted separately.

</details>

<details><summary><strong>Why is there a one-second sleep after contextual compression?</strong></summary>

To let the Foundation Models rate budget recover before the generation call, because compression already spent a model call.

</details>

<details><summary><strong>Is extractive QA used?</strong></summary>

No. The neural span model is a stub that returns nil and the code always proceeds to generation. The bank labels it Dormant, which is correct.

</details>

---

## Module 10. Model execution, routing, tools, and generation

**What it is.** Choosing which model answers, building the session, and generating. The plan, the route, the session, the stream.

**In the bank's words.** Now the app chooses which answering engine is allowed to run, gives it the evidence and rules, and records what engine actually completed the answer.

**Why it exists.** Where the answer runs is a decision with privacy, cost and quality consequences, so it is made explicitly and after retrieval by `ModelExecutionPlanner`: abstain if the evidence is insufficient, deterministic if a rule-based extractor can answer, Private Cloud Compute only if the capability exists, the network is up, the user is present or has consented, **and** either the local budget does not fit or the query complexity asks for it. Every PCC plan carries an on-device fallback. The **minimised payload** is built before consent is requested, so the user is asked about the exact text that would leave. Structured generation with `@Generable` exists so the answer arrives as typed claims with citations, not prose to be parsed.

**Where it runs.** Planning is CPU. Generation is `LanguageModelSession.streamResponse` on `SystemLanguageModel.default`; Apple places the on-device model and the app cannot move it. PCC needs iOS 27 or macOS 27, the entitlement, availability and quota, and is built with Swift 6.4. The advanced on-device route executes the same default model; no advanced model exists in the SDK.

### The word bank (62 concepts)

| Concept | Status | In one sentence |
|---|---|---|
| @Generable | Core | The Foundation Models annotation defining a type the framework can produce through constrained decoding. It enforces field presence and types at generation time rather than repairing malformed free-form output afterward. |
| @Guide | Core | A field-level natural-language constraint attached to a generable property. The type says what data shape is required, while the guide says what semantic content belongs in the field. |
| Abstain execution target | Core | A plan target that intentionally returns no unsupported answer. No available model should be allowed to convert absent or contradictory evidence into fluent certainty. |
| Active model | Core | The model or analysis path that is actually executing or most recently completed. Fallback, framework availability, or route policy may make it differ from the selected label. |
| AdapterManager | Support | The compatibility layer coordinating available LLM service adapters. It decouples the RAG engine from one backend implementation and contains legacy transitions. |
| advanced20B preference alias | Historical | A compatibility value that currently resolves to the on-device route rather than a selectable twenty-billion-parameter tier. It preserves stored preferences while avoiding false model identity claims. |
| Apple Foundation Models | Core | Apple's on-device generative model framework used for local answer generation, constrained structures, tools, and auxiliary model tasks. It supplies a private, system-managed language model without bundling a large generative… |
| Atomic claim | Core | One independently verifiable assertion in the answer rather than a paragraph containing several facts. Verification and evidence mapping are more reliable when each claim can be supported or rejected separately. |
| Citation namespace | Core | The one-to-one mapping among prompt source labels, model citations, retrieved chunks, response chips, and source views. A cited answer is unsafe if S3 in the text can refer to a different source than chip 3 below it. |
| Cloud consent | Dormant | The user decision allow once, allow and remember, or deny for a specific provider and minimized payload. Even privacy-preserving cloud compute should not receive document evidence without an explicit user policy. |
| Cloud transmission record | Dormant | The audit record of provider, model, prompt preview, character counts, chunk count, content hashes, estimated bytes, plan ID, and route reason. A cloud badge alone cannot show what left the device or why. |
| Constrained decoding | Core | Model decoding restricted to a declared output schema. It eliminates a class of parsing failures and lets downstream verification operate over explicit claims and citations. |
| core3B preference alias | Historical | A compatibility value that now means on-device execution, not selection of an observable three-billion-parameter model. Older settings and UI values must continue to resolve without claiming an API capability Apple does not… |
| Deterministic execution target | Core | A plan target that returns an extractive or otherwise code-produced answer without generative synthesis. When source structure already yields the answer, generation adds risk and latency without value. |
| DirectRAGAnswer | Conditional | A smaller structured answer shape without the explicit reasoning field. Exact or constrained paths may need less output overhead and less hidden analysis text. |
| Evidence source label | Core | A compact identifier such as S1, S2, or an evidence ID attached to each excerpt in the prompt. The model needs an unambiguous namespace it can cite, and downstream code needs to map that label back to the exact chunk. |
| Execution attempt | Core | One timed try against a target with a result such as succeeded, partial, failed, or skipped. A receipt needs the full chain to explain fallback and attest the completed route. |
| Execution context | Core | The user/runtime policy automatic, on-device only, prefer cloud, or cloud only. It defines a privacy and routing constraint independent of answer quality mode. |
| Execution fallback | Core | The approved alternative target used when the intended target cannot complete. A fallback must preserve user privacy policy and be explicit in telemetry. |
| Fail-closed routing | Core | The rule that denied, unknown, unsupported, unavailable, or exhausted cloud conditions choose a permitted local fallback or abstention rather than optimistically transmit. Privacy and authorization uncertainty must never be… |
| Foundation Model preference | Core | The preference automatic, on-device aliases, or Private Cloud Compute used by model-route policy. It captures a user route choice while retaining compatibility with historical model labels. |
| Foundation Model tool | Conditional | A typed callable operation exposed to the language model during a session. Tools let the model request deterministic retrieval or document operations instead of fabricating results. |
| FoundationModelSessionFactory | Core | The central creator of Apple Foundation Models sessions for answer generation and auxiliary use cases. Central construction keeps instructions, tools, use-case policy, routing, and transcript behavior consistent. |
| FoundationModelToolRegistry | Conditional | The central registry of the app's approved Foundation Models tools and their schemas. An allowlisted registry controls capability, prompt overhead, and auditability. |
| InferenceConfig | Core | The per-query bundle of generation parameters, Foundation Model preference, execution context, cloud permission, quality mode, prompts, and attached execution plan. All model calls in a query, including agentic synthesis, need… |
| LanguageModelSession | Core | A Foundation Models conversation/inference session that carries instructions, tools, transcript state, and generation calls. A session is the framework boundary for model interaction and may accumulate context across calls. |
| LLMService | Core | The service that compiles requests, selects or invokes the active language-model backend, streams text, requests structured output, and records generation metrics. Retrieval should not know framework-specific session details, and… |
| Local OpenAI-compatible server backend | Conditional | A developer or alternative backend that calls a user-specified local OpenAI-compatible server rather than Apple Foundation Models. It can support testing or external local inference without changing the RAG retrieval contract. |
| Matched terms | Support | The query concepts the model reports finding in the supplied sources. They provide an additional diagnostic signal about whether generation used the intended evidence. |
| Maximum generation tokens | Core | The cap on how many output tokens a model call may produce. It bounds latency and prevents output from consuming capacity needed by later chained calls or UI. |
| Minimized cloud payload | Dormant | Only the selected evidence and prompt material required for the question, rather than the whole library. Late routing and data minimization reduce exposure and make consent concrete. |
| Model availability state | Core | The resolved condition available, simulator unsupported, unsupported device, Apple Intelligence disabled, model preparing, or another unavailable reason. Model execution must fail explicitly and intelligibly rather than enter a… |
| ModelExecutionPlan | Core | The immutable post-retrieval plan naming the intended synthesis target, reason, token estimates, fallback target, and policy version. Routing should be a checkable decision based on the exact minimized evidence payload, not a… |
| ModelExecutionReceipt | Core | The immutable record of intended, actual, and completed targets, attempts, quota, fallback reason, policy, and timing for one answer. It proves how the answer was produced and prevents UI route claims from being inferred from… |
| ModelResolutionService | Support | The observable single source of truth for what the user selected, what is actually active, the execution path, fallback reason, status, parameters, and history. A model picker label is not proof of the model or route that… |
| On-device execution target | Core | A plan target that invokes the local SystemLanguageModel. It preserves the local-first guarantee and is the only generative target in shipping App Store builds. |
| Partial stream completion | Core | A route outcome in which meaningful output was delivered before the stream failed or ended prematurely. Discarding all partial text can be worse than preserving an explicitly marked incomplete answer. |
| PCC quota state | Dormant | The framework-reported or normalized condition available, limit reached, unsupported, or unknown. Cloud execution must not be attempted when authorization or capacity is uncertain. |
| PCC reasoning level | Dormant | The none, moderate, or deep reasoning request associated with a Private Cloud Compute route. Cloud execution could allocate more reasoning effort according to query mode. |
| PCC suppression cooldown | Support | A temporary period after route failure during which the engine avoids retrying PCC and forces local execution. Repeatedly attempting an unavailable route wastes latency and can create loops. |
| Policy version | Support | A version identifier attached to route plans and receipts. Routing logic evolves, and historical results need to be interpreted under the policy that produced them. |
| Post-retrieval routing | Core | Choosing deterministic, on-device, abstain, or potential cloud synthesis only after evidence size and quality are known. Before retrieval, the engine does not know whether the answer fits locally or what exact content would leave… |
| Private Cloud Compute target | Dormant | The source-level route for Apple Private Cloud Compute on compatible compiler, OS, entitlement, availability, quota, foreground, network, and consent conditions. It is designed to handle evidence packets that exceed the on-device… |
| Prompt compiler | Core | The component that turns query intent, evidence excerpts, source labels, grounding rules, answer format, and route constraints into model instructions and prompt content. Prompt text is an executable interface to the model and… |
| RAGAnswer | Core | The structured model output containing reasoning, direct answer, confidence, citations, atomic claims, and matched terms. It carries the information needed to render, audit, and verify a model response. |
| Reasoning-first field order | Conditional | Placing a reasoning or analysis field before the final answer in a generable type. Field order can encourage the model to identify supporting facts before committing to the answer. |
| Registered retrieval tools | Conditional | The current group of approximately six model-callable tools for document search and related deterministic operations. They support agentic evidence gathering while keeping model actions inside the app's local data boundary. |
| Response-tail trimming | Core | Removing obvious unfinished artifacts, duplicated schema fragments, or partial trailing structures after a terminated stream. A preserved partial answer should not expose broken serialization or misleading half-sentences. |
| Route reason | Core | The policy explanation for why a target was intended, such as exact extraction, local fit, user choice, or context overflow. A route without a reason is difficult to audit or reproduce. |
| Selected model | Core | The model family or execution preference the user requested. User intent must be distinguished from the route the runtime can actually honor. |
| Session transcript | Core | The accumulated instructions, prompts, tool calls, tool outputs, and model responses within a LanguageModelSession. The model sees this history on later calls, consuming context and influencing behavior. |
| Session use case | Core | A label distinguishing general answer generation from query enhancement, content tagging, contextual compression, or other focused work. Different tasks require different instructions and should not contaminate one shared… |
| Streaming generation | Core | Receiving model output incrementally rather than waiting for the complete answer. It improves perceived latency, enables live progress, and can preserve meaningful partial text if a later error occurs. |
| Structured generation | Core | Requesting a typed output object instead of unconstrained text. Claims, citations, confidence, matched terms, and refusal state become machine-readable and do not depend on fragile JSON parsing. |
| SystemLanguageModel.default | Core | The system-provided default on-device Apple language model exposed by FoundationModels. The OS owns model availability, updates, and final hardware scheduling, so the app must query capability rather than assume a named parameter… |
| Temperature | Core | The sampling parameter controlling output randomness, with lower values making generation more deterministic. Grounded question answering benefits from consistency and low creative drift, especially for exact values. |
| Time to first token | Support | The elapsed time from query execution start or generation request to the first delivered model token. It distinguishes retrieval/setup latency from model streaming responsiveness. |
| Tokens per second | Support | Generated token count divided by active generation duration. It measures streaming throughput on a named device and route, not answer quality. |
| Tool call | Conditional | One model request to execute an approved deterministic tool with typed arguments. It separates deciding what to look up from actually reading the corpus. |
| Tool-call counter | Support | A query-scoped count of model tool invocations. Tool loops need hard observability and limits to prevent runaway repeated searches. |
| Top-p | Support | Nucleus-sampling configuration limiting token choices to a cumulative probability mass. It can constrain sampling diversity when the backend supports it. |
| Transcript persistence | Support | Saving selected model transcript or query progress state for diagnostics or continuation. Long-running and background queries need recoverable state, while debugging needs evidence of what the engine actually sent and received. |

### Corrections

- OI-0341 `advanced20B` alias: selecting it runs the default model and telemetry reports `.onDevice`. The bank's status labels are right; do not describe a 20B on-device model as real.
- OI-0378 PCC target: the code path exists and compiles with Swift 6.4, but whether a given App Store build carries PCC symbols is a build fact, not a source fact. The ledger records builds with zero PCC symbols.

### Can you explain it?

1. Recite the planner's four targets and the full PCC condition.
2. Explain why consent comes after retrieval.
3. Say what the session factory does with a saved transcript and why it prewarms.
4. Give the temperature per mode and the two GenerationOptions fields.
5. Explain selected model versus completed route.

### Quiz

<details><summary><strong>Under what conditions does the planner choose Private Cloud Compute?</strong></summary>

Capability allows PCC, the network is available, the app is foreground-interactive or consent is granted, and either the local token budget does not fit or the query's complexity requests cloud synthesis. Otherwise on-device, with the reason recorded.

</details>

<details><summary><strong>What is the minimised cloud payload?</strong></summary>

The retrieved chunks in rank order, each cut to a character allowance of at least 240 and at most an even share of the maximum, with document name and page. It is built before consent so the prompt can show what would be sent.

</details>

<details><summary><strong>What does the route policy do when a plan is attached?</strong></summary>

The plan wins: deterministic, on-device and abstain targets run locally; a PCC target runs on PCC with reasoning none for Standard, moderate for Deep Think, deep for Maximum.

</details>

<details><summary><strong>What does choosing the advanced on-device model actually run?</strong></summary>

`SystemLanguageModel.default`. The SDK exposes no advanced model, so the session factory runs the default and reports the route as on-device so telemetry does not claim a tier that never ran.

</details>

<details><summary><strong>What are the generation temperatures?</strong></summary>

0.4 in Standard, 0.4 in Deep Think, 0.3 in Maximum, passed with `maximumResponseTokens` in `GenerationOptions`.

</details>

---

## Module 11. Agentic, recursive, and multi-session reasoning

**What it is.** Thinking in loops. When one pass is not enough: plan, search, read, note, search again, then write, then check.

**In the bank's words.** For hard questions, the app becomes a research team. It makes a checklist, searches one piece at a time, writes facts into a notebook, checks what is missing, and stops when the notebook is good enough.

**Why it exists.** A 3B-parameter model with a 4,096-token window cannot answer a multi-hop question in one pass. So the orchestrator breaks the work into sessions, each a fresh window, and carries a **FactBank** between them instead of the raw transcript. Escalation is decided by measured retrieval quality against a per-profile threshold, not by guessing complexity up front. Every loop has three kinds of stop: a step cap, a confidence target, and a wall clock (180 seconds for recursive research) because thermal state will stop a phone before the maths does. Internal planning and analysis calls are pinned to the device; only the final synthesis may reach PCC.

**Where it runs.** Orchestration is CPU. Every model call is on-device Foundation Models. Re-retrieval reuses module 08. Backoff comes from the thermal and memory state and a per-tier step cooldown.

### The word bank (40 concepts)

| Concept | Status | In one sentence |
|---|---|---|
| Agentic configuration | Conditional | The limits and policy for maximum sessions, retrieval passes, tools, time, evidence thresholds, and stopping behavior. An open-ended model loop needs deterministic resource and safety boundaries. |
| Agentic phase | Conditional | A named state such as planning, searching, expanding, analyzing, synthesizing, refining, reformulating, or verifying. Explicit phases make the loop observable and allow deterministic policy to control what actions are legal next. |
| AgenticOrchestrator | Conditional | The multi-session controller for planning, repeated retrieval, evidence assessment, query reformulation, fact accumulation, synthesis, refinement, and verification. Complex questions need an adaptive loop whose next action… |
| Analyzing phase | Conditional | Evaluating evidence, extracting facts, resolving source identities, and identifying missing coverage. The loop must distinguish evidence quantity from answer completeness. |
| ChainLink | Conditional | A structured reasoning-chain output containing reasoning, a condensed insight, next focus, and cumulative confidence. It gives the next session a small explicit state rather than an unbounded transcript. |
| Convergence | Conditional | The state in which additional retrieval passes no longer add material facts or improve coverage enough to justify continued work. Maximum mode needs evidence-driven stopping rather than endless use of its high session allowance. |
| Conversation summary | Conditional | A compressed representation of older dialogue that preserves entities, decisions, and unresolved questions. It lets long conversations retain continuity without replaying every message verbatim. |
| ConversationMemoryService | Conditional | The service that summarizes and retrieves recent conversation context for standalone rewriting and continuity. Follow-up questions need prior entities and constraints, but full chat history cannot consume the entire model context. |
| Coverage map | Conditional | The record of which subquestions or required answer dimensions have supporting facts. The loop needs a concrete definition of completeness to know when to stop. |
| Critique step | Conditional | A focused pass identifying unsupported claims, omissions, contradictions, or weak reasoning in a draft. Targeted critique gives the refinement phase a concrete repair objective. |
| Default agentic profile | Conditional | The ordinary Deep Think multi-session configuration. It balances evidence depth and runtime for questions that exceed Standard. |
| Evidence gap | Conditional | A specific required fact, facet, comparison side, or condition that is not yet supported by the current corpus evidence. Naming the gap enables targeted retrieval instead of generic more searching. |
| Evidence-driven stopping | Core | Stopping based on coverage, confidence, novelty, contradictions, and improvement rather than a fixed number of thoughts. A fixed loop count wastes work on easy questions and may stop too early on hard ones. |
| EvidenceThread | Core | A local per-library conversation thread containing messages, title, timestamps, and metadata. It persists the user-visible evidence conversation separately from transient model sessions. |
| Expanding phase | Conditional | Adding parents, siblings, cross-references, entities, graph neighbors, or broader candidates around promising hits. Initial search often finds an anchor rather than the complete answer. |
| Fact | Conditional | An atomic evidence-backed proposition stored in the FactBank. Atomic facts can be deduplicated, checked for contradictions, mapped to sources, and combined deliberately. |
| Fact deduplication | Conditional | Merging or rejecting semantically repeated facts encountered across sessions. Repeated discovery should increase confidence or coverage, not consume state as if it were new information. |
| Fact provenance | Conditional | The source IDs, chunks, pages, or evidence labels attached to a FactBank fact. A recursive loop must not detach a condensed fact from the source that justified it. |
| FactBank | Conditional | The cumulative source-backed state that stores facts discovered across subquestions and sessions together with provenance. Passing compact facts forward lets recursive RAG retain knowledge without carrying every full transcript… |
| Fast agentic profile | Conditional | A reduced multi-session configuration for limited deeper work. It provides some decomposition and verification without the full latency of thorough reasoning. |
| Hard session cap | Core | The absolute maximum number of agentic model sessions allowed even if convergence never occurs. Deterministic safety bounds protect battery, heat, latency, quota, and cancellation behavior. |
| LLM call count | Support | The number of separate model invocations used to produce an answer. It differentiates a Standard single pass from recursive RAG and helps explain latency and energy. |
| Memory turn limit | Core | The mode-dependent number of recent conversation turns retained or considered, roughly 5, 10, or 20. More context improves continuity but competes with document evidence and can introduce stale assumptions. |
| Planning phase | Conditional | The step that interprets the request, identifies subquestions, and chooses an initial evidence strategy. Searching before defining requirements can produce many relevant passages that still fail to answer the whole question. |
| ReasonedInsight | Conditional | A structured output containing analysis, one key insight, discovered terms, and confidence. It standardizes what an intermediate evidence-analysis session passes forward. |
| ReasonedSynthesis | Conditional | A structured final integration of multiple insights with key points, confidence, and sources. The last step must reconcile accumulated findings rather than simply concatenate them. |
| Reasoning session | Conditional | One bounded LanguageModelSession call dedicated to a particular agentic objective. Fresh focused sessions avoid transcript overflow and isolate evidence assessment from final answer writing. |
| Reasoning trace | Support | A user-facing or diagnostic sequence of named progress events and condensed intermediate outcomes. It explains what stages ran without exposing raw hidden chain-of-thought. |
| Reasoning-chain token total | Support | The sum of tokens consumed across every model call in recursive execution. One 4,096-token limit per session does not describe the total computational work of the answer. |
| Recursive RAG | Conditional | A pattern that makes several bounded retrieval and language-model calls, passing condensed facts or insights forward instead of forcing the full problem into one context window. Multiple 4,096-token sessions can collectively… |
| Refining phase | Conditional | Improving an initial synthesis in response to verification failures, omissions, or unsupported claims. A generated answer can be mostly correct but require targeted repair rather than a full restart. |
| Reformulating phase | Conditional | Changing the search query or decomposition when evidence is weak, redundant, or off-target. Repeating the same failed retrieval cannot discover a different lexical or semantic neighborhood. |
| Searching phase | Conditional | The execution of hybrid retrieval for the current query or subquestion. The loop remains grounded by gathering source evidence before making claims. |
| Self-RAG | Conditional | A self-evaluation pattern in which the model or orchestration layer checks whether evidence supports the answer and may retrieve or revise again. Generation quality depends on the evidence and can be improved by explicitly… |
| Standard reasoning chain | Conditional | A bounded multi-step reasoning sequence used within some Standard answer paths without invoking the full agentic orchestrator. A question can benefit from structured evidence analysis and synthesis while still avoiding open-ended… |
| Synthesizing phase | Conditional | Combining accumulated source-backed facts into a coherent answer. Multiple subquestions and documents require composition after their evidence is independently gathered. |
| ThinkingEvent | Support | A typed progress event with phase, title, detail, icons, counters, confidence, and generation state. Typed events keep the live UI and SDK synchronized with the actual pipeline rather than parsing log strings. |
| Thorough agentic profile | Conditional | A broader configuration with more retrieval and reasoning allowance. Cross-topic or incomplete-evidence questions may need more passes and source expansion. |
| Unlimited agentic profile | Conditional | The Maximum-mode configuration with a high but still finite safety cap, including up to roughly 50 sessions in current source. Maximum should stop when evidence converges, but a hard ceiling protects against pathological loops. |
| Verifying phase | Conditional | Running source and claim checks over the agentic synthesis. More model calls do not make an answer trustworthy by themselves; the final output still needs deterministic gates. |

### Can you explain it?

1. Give the four profiles with their step cap, confidence target and escalation threshold.
2. Explain the two `executeRecursiveResearch` call sites and how to tell them apart in a log.
3. Give the reasoning-chain session counts.
4. Explain what Maximum does differently (0.98, 50 sessions, 3 chunks each, FactBank).
5. Say why tools are disabled inside Maximum sessions.

### Quiz

<details><summary><strong>What are the agentic profiles?</strong></summary>

fast: 2 steps, 0.70 confidence, 0.25 escalation. default: 5, 0.85, 0.35. thorough: 8, 0.95, 0.45. unlimited: 50, 0.98, 0.50.

</details>

<details><summary><strong>How do you tell which recursive-research call site ran?</strong></summary>

By the iteration denominator in the log. One site passes `maxIterations: 5`, the other `maxIterations: 3`; the default is 7 and is not used by either.

</details>

<details><summary><strong>What stops a Maximum run?</strong></summary>

Reaching 0.98 confidence, saturation (no novelty), cancellation, or the session cap, which is 50 scaled down to the evidence pool at three chunks per session. A 180-second budget bounds each recursive research phase.

</details>

<details><summary><strong>Which agentic calls may go to Private Cloud Compute?</strong></summary>

Only the final synthesis, through the post-retrieval plan. Planning and evidence analysis set `executionContext = .onDeviceOnly` and `allowPrivateCloudCompute = false`.

</details>

<details><summary><strong>What is the FactBank for?</strong></summary>

It carries source-backed facts between sessions so each new 4,096-token window starts from distilled evidence instead of the previous transcript, which is what used to overflow at 4,521 tokens.

</details>

---

## Module 12. Verification, grounding, confidence, and abstention

**What it is.** The nine checks. Deterministic gates that decide whether the generated answer is allowed to stand.

**In the bank's words.** This is the fact-checking desk. It asks whether every important sentence is really supported, whether numbers match, and whether the safest answer is “I do not have enough evidence.”

**Why it exists.** The generative stage can invent. So after it, rule-based gates run in a fixed order: A retrieval confidence, B evidence coverage (every claim cites), C numeric sanity, D contradiction sweep, E semantic grounding (the response embedded and compared to its best source), F quote faithfulness, G generation quality, H answer completeness, with I domain isolation applied before synthesis. Unsupported claims are removed or the app **abstains** with a Not Enough Evidence answer. **Confidence** is calibrated from several inputs; **fidelity** is specifically how well the cited sources support the text. They are different numbers on purpose.

**Where it runs.** CPU inside the `VerificationGateService` actor. Gate E costs one embedding call. Thresholds: `tauNormal` 0.40, `tauTouchy` 0.55, margin 0.03, semantic grounding 0.50; a strict profile raises all four. The mode's confidence bar is 0.50, 0.60, 0.80.

### The word bank (40 concepts)

| Concept | Status | In one sentence |
|---|---|---|
| Absence assertion | Core | The explicit claim that requested information is not present in the corpus, supported by sufficiently broad retrieval and search checks. Saying not found is itself a factual assertion and should not be issued after a shallow miss. |
| Abstention | Core | The deliberate decision to say the documents do not support an answer instead of guessing. A grounded system needs a valid no-answer outcome; otherwise every retrieval miss becomes a hallucination opportunity. |
| Abstention threshold | Core | The calibrated confidence floor below which the answer is refused, made stricter from Standard to Maximum and for touchy queries. A higher-effort mode should not merely search more; it should demand stronger evidence before… |
| Answer replacement guard | Core | A safeguard preventing a later transformation or fallback from replacing a stronger grounded answer with a weaker or unsupported one. Multi-stage pipelines can regress after producing a correct extractive answer. |
| Bibliography penalty | Core | A reduction or exclusion applied to chunks recognized as references when the query seeks substantive findings rather than citations. A bibliography contains query terms and author names but usually does not state the evidence… |
| Calibration caveat | Core | The fact that configured calibration is a heuristic policy unless validated against held-out outcome frequencies. A displayed 80 percent should not be interpreted as a statistically proven 0.80 probability without empirical… |
| Calibration parameters | Core | The slope, intercept, penalties, and conservative/default parameter set used to adjust confidence. Central parameters make confidence behavior testable and mode-dependent. |
| Claim verification verdict | Core | The supported, partial, or unsupported classification attached to one answer claim. A single global confidence hides which exact assertions are reliable. |
| Confidence calibration | Core | Transforming raw signals using configured parameters and verification results to produce a more conservative answer confidence. Raw model and similarity scores have different scales and can be overconfident. |
| Confidence policy | Core | The per-query thresholds and calibration parameters derived from answer intent, touchy status, and quality mode. Confidence and abstention decisions should change coherently with risk and requested effort. |
| Critical gate | Core | A verification gate whose failure can independently force abstention, currently including retrieval confidence, numeric sanity, and semantic grounding. Some failures invalidate the answer regardless of how well other dimensions… |
| DomainIsolationService | Core | The service that classifies claim/evidence domains and penalizes or blocks support crossing incompatible domains. Common terms can make an unrelated medical, legal, automotive, or computing passage appear semantically relevant. |
| Evidence-first mode | Core | A policy that treats retrieved source content as the primary answer authority and model output as a constrained transformation. It reverses the unsafe pattern of generating first and searching for citations afterward. |
| Fidelity | Core | The degree to which the visible answer remains locked to and fully supported by the cited sources. Confidence can reflect overall certainty, while fidelity specifically communicates source support. |
| Gate A: Retrieval Confidence | Core | The check that the retrieved evidence has sufficient relevance and separation to justify answering. No downstream phrasing can compensate for an evidence set that never found the answer. |
| Gate B: Evidence Coverage | Core | The claim-by-claim check that answer assertions are supported by supplied evidence. An answer can cite sources globally while individual claims remain unsupported. |
| Gate C: Numeric Sanity | Core | The critical check that numbers, units, ranges, and exact values in the answer are present and consistent with evidence. Numeric hallucinations are especially dangerous because a small digit or unit change can invert meaning. |
| Gate D: Contradiction Sweep | Core | The check for conflicts among the answer, evidence passages, and potentially conflicting source statements. A high-similarity source can still disagree with another relevant source or with the generated claim. |
| Gate E: Semantic Grounding | Core | The critical semantic check that the answer meaning remains close to the evidence meaning. Exact token overlap alone misses paraphrased fabrication, while semantic comparison can detect drift. |
| Gate F: Quote Faithfulness | Core | The check that quoted or extractive language actually appears in the attributed source and has not been materially altered. Quotation marks and citations imply a stronger provenance guarantee than ordinary synthesis. |
| Gate G: Generation Quality | Core | The check for empty, malformed, repetitive, truncated, or otherwise unusable model output. An answer can be grounded yet still fail as a response because the stream or schema was incomplete. |
| Gate H: Answer Completeness | Core | The check that the response addresses the requested facets rather than answering only an easy subset. Partial coverage can be misleading when presented as a complete answer. |
| Gate I: Domain Isolation | Core | The check that specialized evidence and claims remain within the correct domain, document context, and citation scope. Shared words across medical, engineering, legal, and general domains can create plausible but cross-domain… |
| Missing-information list | Core | The explicit fields, facts, or support the question requested but the corpus did not provide. A refusal is more useful when it identifies the gap rather than returning a generic failure. |
| Not Enough Evidence | Core | The UI state for abstention or evidence too weak to safely verify an answer. The absence of a confident answer is itself important information about the corpus. |
| Numeric-unit verification | Core | Comparing numbers together with their units, qualifiers, ranges, and source context rather than checking digits alone. 5 mg and 5 mL are not interchangeable, and maximum versus typical changes the claim. |
| Partially Supported | Core | The UI state indicating useful answer content remains but some details did not receive full verification. It exposes uncertainty instead of flattening mixed claim support into one green badge. |
| Partially supported claim | Core | A claim for which evidence supports the main point but not every detail or degree of certainty. The engine can preserve useful information while explicitly lowering trust rather than pretending full support. |
| Precision lock | Conditional | A high-confidence state where deterministic or source-only evidence is strong enough to answer directly and block unnecessary generative rewriting. Exact values can be degraded by paraphrase or accidental number changes. |
| Quote-span verification | Core | Checking that a cited quote exists in the source text at the attributed location or within an accepted normalized match. A fabricated quote with a real citation is more misleading than an uncited paraphrase. |
| Raw confidence | Core | An uncalibrated score derived from model output, retrieval scores, claim support, or extraction strength. It is an internal signal, not automatically a probability that the answer is true. |
| Reliability mode | Core | A user/runtime setting that favors grounded fallback, verification, and explicit uncertainty over permissive output. The product promise depends on failing safely when evidence or generation is weak. |
| Scientific-domain claim check | Conditional | Special handling for research claims, statistical language, methods, results, and citation sections. Scientific text has recurring structures where bibliography or background language can be mistaken for study findings. |
| Source-Locked | Core | The UI state indicating all material claims passed source grounding at the required fidelity threshold. It gives the user a stronger and more specific trust signal than a generic confidence number. |
| Source-only verification | Core | Checking that the final answer can be reconstructed or supported from source passages without relying on model memory. Citations are meaningful only when the cited text actually entails the claim. |
| SourceOnlyAnswerService | Core | A fallback and verification service that constructs or validates an answer exclusively from retrieved source sentences. When generative grounding is uncertain, the safest useful result may be a concise extractive answer rather… |
| Supported claim | Core | A claim whose meaning and material details are directly justified by mapped evidence. It is eligible to remain in a source-locked answer. |
| Unsupported claim | Core | A claim with no adequate evidence mapping or a contradiction with supplied evidence. It must not survive merely because the overall answer sounds plausible. |
| Verification configuration | Core | The threshold bundle for normal, touchy, margin, semantic grounding, and critical-category behavior. One centralized configuration prevents separate answer paths from using contradictory safety standards. |
| VerificationGateService | Core | The deterministic post-generation service that evaluates retrieval confidence, evidence coverage, numeric sanity, contradictions, semantic grounding, quotes, generation quality, completeness, and domain isolation. A language… |

### Can you explain it?

1. Recite gates A to I in order with one phrase each.
2. Give the four default thresholds and the touchy categories.
3. Explain why Gate E is called the real hallucination killer and what it costs.
4. Distinguish confidence from fidelity.
5. Say what the app does when gates fail.

### Quiz

<details><summary><strong>What does Gate A check?</strong></summary>

That the top rerank score is at least tau (0.40, or 0.55 for touchy categories) and the margin between the top two scores is at least 0.03. Weak or ambiguous retrieval fails before the answer is even read.

</details>

<details><summary><strong>What does Gate E do?</strong></summary>

Embeds the generated response and compares it with the best-matching source chunk. Below 0.50 cosine similarity the answer is semantically ungrounded and treated as likely hallucination.

</details>

<details><summary><strong>Why was Maximum&#x27;s verification threshold lowered from 0.98 to 0.80?</strong></summary>

Because 0.98 was unreachable in practice, so every Maximum answer failed verification.

</details>

<details><summary><strong>What is the difference between confidence and fidelity?</strong></summary>

Confidence is a calibrated trust signal from retrieval scores, gate results and session depth. Fidelity is how well the cited sources support the text. A confident answer with low fidelity is exactly what the gates exist to catch.

</details>

<details><summary><strong>What happens when a claim fails Gate B?</strong></summary>

It has no citation, so it is marked unsupported and removed or the answer is downgraded to partially supported; if too little survives, the app abstains.

</details>

---

## Module 13. Response structure, provenance, rendering, and observability

**What it is.** What comes back and how you can inspect it. Typed answers, citations to byte offsets, the route badge, and the trace that records every stage.

**In the bank's words.** The final report includes the answer, the receipts, the source labels, and clues showing how the machine got there.

**Why it exists.** An answer you cannot audit is a guess with good typography. So the response is a `StructuredAnswer` of claims with evidence IDs, citations map to character ranges in the source (the tokenizer pass in ingestion is what makes that exact), the route badge says which model **completed**, the retrieval diagnostics show what was dropped, and the pipeline trace log records every stage with timings. Evidence threads persist so a conversation's sources survive relaunch.

**Where it runs.** CPU. The trace file is `pipeline_trace.log` in the app container's Documents folder; it rotates, so long captures use `tail -F` into an archive. The hardware HUD's Neural Engine pulse is synthetic: no public API reports Neural Engine occupancy.

### The word bank (35 concepts)

| Concept | Status | In one sentence |
|---|---|---|
| Enhanced code block | Conditional | The response component that renders code with language labels, scrolling, and copy behavior. Code answers need formatting that preserves whitespace and supports practical reuse. |
| Evidence ID | Core | The stable identifier linking a claim citation to one source record and ultimately one chunk. Human-readable source numbers can change with ordering; a stable ID preserves identity underneath. |
| Evidence quote cap | Core | The response policy limiting stored evidence excerpts to roughly 240 characters. A concise quote is sufficient for inspection while bounding response size and accidental overexposure. |
| Evidence record | Core | A response-level source object containing evidence ID, page, quote, document name, and section path. Claims need a stable source representation independent of the transient RetrievedChunk object graph. |
| Evidence-thread persistence | Core | Saving user messages, answers, citations, and metadata into the selected local thread. A verified answer should remain reproducible and inspectable after the transient query task ends. |
| Execution-route metadata | Core | The user-facing path name, reason, policy version, and icon describing where synthesis ran. Route truth should come from execution evidence rather than the model picker. |
| Grounded answer view | Core | The response surface that presents answer text together with citations and source-grounding information. Grounding must be visible at the point the user reads the claim. |
| Hardware telemetry pulse | Support | A short-lived signal indicating that OCR, vector similarity, reranking, or another workload is active on the conceptual hardware display. It makes otherwise invisible local computation understandable to the user. |
| Inline citation | Core | A source marker embedded next to the claim it supports inside the answer text. Claim-local citations reduce ambiguity compared with a detached source list. |
| Markdown renderer | Core | The block-aware renderer for headings, lists, code, tables, emphasis, links, and horizontal rules in model responses. Technical answers lose usability or meaning if structured text is displayed as one plain string. |
| OICitation | Core | The SDK citation value containing source name, optional page, and optional quote. External clients need a small stable citation contract independent of internal chunk models. |
| OIEngine | Core | The reusable public SDK facade for library management, ingestion, querying, streaming, progress, citations, diagnostics, and availability. It defines a stable product boundary above the internal RAGService mega-orchestrator. |
| OIQueryProgressEvent | Support | The SDK-safe version of live query progress with phase, title, detail, icon, counters, and confidence. A reusable engine must expose progress without requiring the app's SwiftUI types. |
| OIQueryResult | Core | The SDK result containing answer, citations, confidence, abstained state, warnings, model name, quality mode, reasoning trace, and diagnostics. SDK clients need the same provenance and route truth available to the first-party UI. |
| Pipeline signpost | Support | A lightweight os-signpost marker around important pipeline intervals. Signposts allow Instruments to measure stage latency without parsing text logs. |
| Pipeline trace | Support | A chronological record of stage events, decisions, timing, route attempts, and selected evidence for one execution. A multi-stage engine cannot be debugged reliably from a final answer alone. |
| PipelineTraceExporter | Support | The feature that serializes shareable pipeline evidence from instrumented query execution. Device-only failures require a reproducible artifact rather than a verbal report. |
| RAG audit feature flags | Support | Booleans recording whether rewrite, expansion, HyDE, iterative retrieval, routing, summaries, parent retrieval, corrective retrieval, compression, graph packing, cascade, multi-vector, or unlimited reasoning actually ran.… |
| RAGAuditSnapshot | Support | The detailed per-query snapshot of provider, dimensions, chunk policy, retrieval configuration, score distribution, candidate counts, context budget, route, features, and recursive metrics. It preserves the exact operating… |
| RAGResponse | Core | The internal response object carrying answer text, retrieved chunks, confidence, abstention state, reasoning trace, metadata, and diagnostics. The engine needs a richer result than a string so verification, UI, SDK, and… |
| Refuse flag | Core | The explicit Boolean marking that the engine declined to provide a substantive answer. A refusal should be machine-readable rather than inferred from wording. |
| Response metadata | Core | The attached route, token budget, model, timing, retrieval, quality-mode, and feature information describing how the answer was produced. The same answer text can have very different trust and cost implications depending on… |
| Response transformation | Conditional | A post-answer operation such as rewriting, summarizing, or formatting the verified response through an approved service. Users may want a different presentation while preserving the underlying sourced result. |
| Retrieval diagnostics | Support | Counts and timings for candidates, reranked chunks, context chunks, embedding provider, warnings, and feature flags. A bad answer can originate in extraction, retrieval, packing, or generation, and diagnostics narrow the failing… |
| RetrievalLogEntry | Support | A timestamped record of the query, active library, and chunks returned by retrieval. It supports inspection of what the answer stage actually received. |
| RetrievalTraceCollector | Support | A per-query thread-safe collector of rank-ordered output at vector, lexical, fusion, boosted, candidate, rerank, and final stages. Counts cannot show whether the correct chunk survived. |
| Source chip | Core | The tappable UI representation of a response evidence source. It lets the user inspect the actual document passage rather than trust the model or badge. |
| Structured answer type | Core | The lookup, table lookup, procedure, compare, summarize, investigate, compute, findings, or refused label stored with the answer. The response renderer and evaluator need to know the intended answer shape. |
| StructuredAnswer | Core | The durable claim-oriented answer model containing refusal state, answer type, answer text, atomic claims, evidence records, missing information, and debug data. It is the provenance contract between generation, verification,… |
| TelemetryCenter | Support | The central emitter of typed runtime telemetry events for system, pipeline, and user-visible diagnostics. Structured telemetry keeps monitoring decoupled from UI and raw print statements. |
| Thinking stream | Support | The live UI sequence of typed progress events during retrieval, reasoning, generation, and verification. Long Deep Think and Maximum queries need observable progress without exposing private raw reasoning. |
| Timing breakdown | Support | The display and data model separating retrieval, generation, and other stage durations. Total latency alone cannot show which subsystem should be optimized. |
| Token-budget metadata | Core | The total, prompt, evidence, generation, and remaining token counts attached to a response. It explains why some evidence was compressed or omitted and makes hard model constraints observable. |
| Unified metrics bar | Support | The response UI combining timing, model route, confidence, retrieval, context, and source metrics. The user needs one place to understand the answer's operating evidence without opening raw diagnostics. |
| Writing Tools integration | Conditional | The local service exposing proofread, rewrite, and summarize operations for answer or user text. Presentation changes can use Apple intelligence features without entering the retrieval pipeline again. |

### Can you explain it?

1. Explain how a citation reaches a character range.
2. Say what the route badge reads and why it reflects the receipt, not the selection.
3. Name three things the retrieval diagnostics sheet shows.
4. Say where the pipeline trace lives and why it needs an archive tail.
5. Explain what the HUD can and cannot measure.

### Quiz

<details><summary><strong>Why can citations point at a sentence rather than a page?</strong></summary>

Because the tokenizer validation pass at ingestion records exact byte offsets for each chunk, and claims carry evidence IDs that map back to those offsets.

</details>

<details><summary><strong>Why does the route badge read from the execution receipt?</strong></summary>

Because the selected model is user intent and the completed route is what actually ran; a PCC plan can fall back to on-device, and the badge must show the fallback, not the wish.

</details>

<details><summary><strong>What does the pipeline trace record and where is it?</strong></summary>

Every query and ingestion stage with timings and counts, in `pipeline_trace.log` under the app container's Documents folder. It rotates, so a long run is captured with `tail -F` into an archive file.

</details>

<details><summary><strong>Can the app show live Neural Engine utilisation?</strong></summary>

No. There is no public API for it. The HUD shows a synthetic activity pulse and device lookup data.

</details>

---

## Module 14. Evaluation, benchmarks, and quality measurement

**What it is.** Measuring whether any of this works. Fixtures, metrics, and the two lessons that made most earlier figures unusable.

**In the bank's words.** This is the test track. It checks not only whether the final answer was right, but exactly where the correct evidence was lost if it was wrong.

**Why it exists.** Retrieval quality claims are unfalsifiable without a harness, which is why the benchmark harness came first in the retrieval plan. Two lessons dominate. First, **chunk-level retrieval scored against document-level ground truth** produces nonsense: it reported an nDCG of 2.131. Second, **retrieval is nondeterministic**: two runs of one build return different evidence for one question, so no A/B is trustworthy until that is fixed. And twice now, one real document on real hardware has beaten the whole synthetic suite at finding a defect.

**Where it runs.** `RAGEvalRunner` and the evaluation services on the macOS Debug build. Runs live under `BenchmarkRuns/` and are archived, never deleted; `BenchmarkRuns/LEDGER.md` indexes them and is the only citable source for a number.

### The word bank (31 concepts)

| Concept | Status | In one sentence |
|---|---|---|
| Abstention accuracy | Support | How often the engine correctly refuses unanswerable questions and answers answerable ones. Always answering and always refusing are both poor systems; the decision boundary must be measured. |
| Answer accuracy | Support | The proportion of cases judged correct under the dataset scoring rule. It gives a headline outcome but must be decomposed because retrieval, synthesis, and errors can produce the same aggregate. |
| Benchmark baseline | Support | A frozen reference result and configuration against which later runs are compared. Without a baseline, code changes can alter quality while individual runs still look plausible. |
| Benchmark ledger | Support | The chronological record of benchmark runs, versions, configurations, and findings. Evaluation conclusions need provenance and should survive the machine that produced them. |
| Completed-route attestation | Support | The invariant that the target claimed as completed appears in the attempt chain with an attesting success or allowed partial outcome. A UI cannot truthfully say PCC or on-device completed based only on the intended plan. |
| Credited relevance | Support | The evaluation rule mapping retrieved chunks to ground-truth evidence with exact or accepted equivalence criteria. Chunk boundaries and parent expansion can produce evidence that is relevant without sharing the exact original… |
| Distractor document | Support | An irrelevant or partially related document included with the target source during evaluation. Retrieval quality cannot be measured if the corpus contains only the answer document. |
| Error rate | Support | The proportion of cases that terminate through an execution, timeout, parsing, or infrastructure error rather than a valid answer or abstention. Infrastructure failures should not be hidden inside answer-quality metrics. |
| Evaluation case | Support | One question with corpus scope, expected answer or evidence, answerability, and scoring metadata. Quality must be measured against explicit ground truth rather than selected anecdotes. |
| Evaluation dataset | Support | A versioned collection of evaluation cases with schema validation and attribution. A stable corpus allows before-and-after comparisons and prevents cherry-picking. |
| Evaluation report writer | Support | The component that serializes metrics, case outcomes, configuration, and warnings into a durable report. A console summary is insufficient for later audit and comparison. |
| Evidence level | Support | A label distinguishing code-verified, test-verified, simulator-verified, device-verified, measured, inferred, or unverified claims. A source file proves implementation, not necessarily runtime behavior or performance. |
| Exact match | Support | A strict answer metric indicating whether the normalized output exactly equals the expected answer. It is useful for short factual lookups where paraphrase should not change the value. |
| Exact sign test | Support | A nonparametric test of whether wins and losses between two paired systems are symmetric, ignoring ties. It quantifies whether one retrieval arm consistently beats another without assuming normally distributed metric differences. |
| Fail-closed route invariant | Support | The requirement that denied consent and unavailable, exhausted, unsupported, or unknown cloud quota do not complete on PCC. Authorization uncertainty must never become a cloud attempt. |
| Fallback attribution invariant | Support | The requirement that a completed target different from the intended target has an explicit fallback reason and attempt history. Silent fallback makes route badges and debugging misleading. |
| Hallucination rate | Support | The proportion of answers containing unsupported material under the evaluation definition. A system can improve exact match by answering more aggressively while becoming less safe. |
| Mean reciprocal rank (MRR) | Support | The average reciprocal position of the first relevant result. It captures how quickly the pipeline surfaces at least one usable evidence item. |
| Normalized discounted cumulative gain (nDCG) | Support | A ranking metric that rewards placing highly relevant items early while supporting graded relevance. It evaluates more of the ranking than first-hit MRR and respects relevance strength. |
| Paired comparison | Support | Comparing two retrieval configurations on the same cases rather than only comparing aggregate means. Per-case wins, losses, and ties show whether an apparent improvement is consistent or driven by a few outliers. |
| Physical-device verification | Support | Testing user-visible and hardware-dependent behavior on a real supported device rather than only in the simulator. Apple Intelligence, thermal behavior, Neural Engine scheduling, PCC, background processing, and memory pressure… |
| Precision at k | Support | The fraction of the top k results that are relevant. High recall with mostly irrelevant evidence wastes context and can confuse generation. |
| QASPER fixture | Support | The external research-paper question-answering benchmark adapted into local Markdown fixtures with distractor papers. Externally authored questions reduce the self-authored-fixture bias that made earlier tests too easy. |
| Quality matrix | Support | A batch evaluation across modes, routes, or configurations that produces comparable rows and columns. Many quality regressions are interactions rather than one isolated setting. |
| RAGEvalRunner | Support | The harness that ingests fixtures, runs queries, captures outputs and stage traces, and aggregates metrics. Manual testing cannot consistently measure hundreds of stage-level outcomes. |
| Recall at k | Support | The fraction of relevant evidence items present in the top k results. It measures whether the retrieval stage found the needed chunks before later ranking or generation. |
| Route invariant | Support | A Boolean property that must hold for execution receipts, such as completed route attempted, fallback attributed, and denied/unknown cloud failing closed. Routing truth is a correctness property separate from answer content. |
| Stage survival | Support | Whether the relevant chunk remains present from vector/lexical through fusion, boosts, truncation, reranking, and final retrieval. A stage can preserve counts while dropping the only correct evidence item. |
| Synthetic fixture bias | Support | The tendency of tests authored alongside their expected questions to flatter the same assumptions and vocabulary built into the engine. A perfect score on self-authored examples can hide weak generalization and abstention. |
| Tiny research suite | Support | A compact synthetic suite covering exact lookup, missing information, multi-hop retrieval, rank retrieval, and lost-in-the-middle behavior. Small deterministic cases are fast regression tests even though they cannot estimate… |
| Token F1 | Support | The harmonic mean of token-level answer precision and recall against the expected answer. It gives partial credit to substantively correct answers that differ in wording. |

### Can you explain it?

1. Define recall@k, precision@k, MRR and nDCG in one line each.
2. Explain the chunk-versus-document ground truth pitfall.
3. State the nondeterminism blocker and how to verify it.
4. Say why runs are never deleted.
5. Explain what a distractor document tests.

### Quiz

<details><summary><strong>Why did nDCG once report 2.131?</strong></summary>

Chunk-level results were scored against document-level ground truth, so multiple chunks from one relevant document each counted as a hit and the score exceeded its own ceiling.

</details>

<details><summary><strong>What is the nondeterminism blocker?</strong></summary>

Two runs of one build return different retrieved chunk IDs for one question. Until the cause upstream of tie-breaking is found, no retrieval A/B is trustworthy. Verify by running a fixed query set twice and diffing the chunk IDs.

</details>

<details><summary><strong>Why must benchmark run directories never be deleted?</strong></summary>

`BenchmarkRuns/` is gitignored, so a deleted run is gone and its `results.jsonl` was the only evidence behind whatever the ledger cites. Three directories were lost this way on 2026-08-19.

</details>

<details><summary><strong>What is the difference between a synthetic fixture and a device run?</strong></summary>

A synthetic fixture tests the pipeline the way it was configured in the harness; a device run tests the configuration the app actually uses. Twice, one real document on real hardware found what the whole suite missed.

</details>

---

## Module 15. Device adaptation, compute, background work, sync, and product limits

**What it is.** The power manager and janitor. How hard the device may work, what runs in the background, how libraries sync, and what the tiers limit.

**In the bank's words.** This is the power manager and janitor. It decides how hard the phone can work, keeps local and shared copies safe, and makes long jobs survive when possible.

**Why it exists.** One configuration cannot serve a fanless MacBook Air and an iPhone in a hot car. `DeviceCapabilityService` detects the chip, memory and Metal limits once and hands every subsystem an envelope: batch sizes, concurrency, agentic depth, cooldowns. The GPU execution profile is the user's lever on top of that. Thermal and memory pressure degrade the pipeline, critical thermal to minimal mode. Background tasks are registered so ingestion and index maintenance can continue when iOS allows. Sync exists so a library is the same on every device, and the guard that waits for iCloud to materialise a file is what stops a placeholder being indexed as an empty document.

**Where it runs.** Detection is CPU and one Metal device query at first access. Five `BGTaskScheduler` registrations on iOS only: continued ingestion, continued query, index maintenance (4 h, needs power), Spotlight reindex (2 h), app refresh (30 min). The 1.68-second idle timer in `WorkspaceSyncService` is the open defect: its damage is bounded, its cause is not fixed.

### The word bank (44 concepts)

| Concept | Status | In one sentence |
|---|---|---|
| AdaptivePipelineOptimizer | Core | The runtime policy that adjusts enhancement features, candidate limits, context, rerank batch, agentic steps, cooldowns, timeout, thresholds, and MMR from device state and query complexity. The engine should degrade gracefully… |
| Balanced optimization level | Conditional | A reduced configuration that disables some repeated work and lowers candidate/context limits. It trades a modest amount of quality work for sustained responsiveness. |
| Balanced profile | Core | The default profile allowing GPU for indexing and page rendering while keeping answer generation primarily on CPU plus Neural Engine policy. It captures most throughput gains without enabling every high-heat path. |
| BGTaskScheduler maintenance | Conditional | Scheduled background tasks for index maintenance, Spotlight reindexing, and app refresh. Search artifacts and OS integrations need upkeep that should not block foreground use. |
| BNNSGraphService | Core | The Accelerate-based service for batch normalization, matrix cosine similarity, softmax, RRF arithmetic, and pairwise similarity. It centralizes optimized vector math and provides a CPU/Apple-Silicon path below or beside Metal. |
| Continued ingestion task | Conditional | A BGContinuedProcessingTask carrying user-started document ingestion through background execution. Large imports should survive app switching and preserve visible progress. |
| Continued query task | Conditional | A BGContinuedProcessingTask carrying a long Deep Think or Maximum query after the app backgrounds. A long answer should not disappear simply because the user leaves the app. |
| Core ML compute units | Core | The allowed hardware set such as CPU and Neural Engine or all units for a model invocation. It expresses execution preference while Apple retains the final scheduling decision. |
| Debounced workspace change | Core | Waiting briefly, about two seconds, to combine rapid local-change notifications into one sync pass. Ingestion writes many related artifacts and should not launch a full merge for each one. |
| Device capability tier | Core | The baseline, enhanced, advanced, ultra-advanced, or unsupported classification derived from hardware identity. The tier provides a stable policy input for candidate breadth, concurrency, and agentic limits. |
| DeviceCapabilityService | Core | The central detector and policy source for chip, device tier, form factor, memory, Metal limits, batch sizes, concurrency, and GPU profile. One hardcoded pipeline configuration would underuse Macs and destabilize thermally… |
| Efficiency profile | Core | The profile keeping models on CPU plus Neural Engine and avoiding GPU vector/render work where possible. It minimizes heat and contention for sustained battery use. |
| Efficient optimization level | Conditional | A power-saving configuration that disables HyDE, compression, and iterative retrieval and reduces batch/candidate limits. Expensive auxiliary model calls are the first features to remove under resource pressure. |
| Full optimization level | Core | The runtime state with the device-tier base configuration and all permitted quality features enabled. It maximizes quality when thermal and memory conditions allow. |
| GPU execution profile | Core | The user policy Efficiency, Balanced, Performance, or Maximum controlling which workloads may use GPU and at what concurrency. A discrete policy communicates real behavior without implying an exact utilization percentage the app… |
| GPUComputeService | Conditional | The Metal service providing batch cosine similarity, normalization, and MMR diversity kernels with CPU fallback. Large vector batches are highly parallel and can benefit from custom compute kernels. |
| Hardware execution envelope | Core | The resolved snapshot of chip, memory, Metal limits, compute route, OCR concurrency, render slots, embedding batch, vector batch, and GPU concurrency. Pipeline decisions need the concrete device constraints that produced them. |
| iCloud-shared sync mode | Conditional | A per-library policy that mirrors supported workspace artifacts through the app's iCloud container. It enables multi-device continuity while retaining explicit library-level control. |
| Ingestion Live Activity | Conditional | The lock-screen or Dynamic Island progress representation for active ingestion. Long imports benefit from durable progress without reopening the app. |
| Local-only sync mode | Core | A library policy that keeps its artifacts in the device application-support workspace and excludes them from iCloud sharing. Some users or corpora require strict device locality independent of general app settings. |
| LoggingConfiguration | Support | The centralized control over log levels, categories, file buffering, redaction, and shareable trace inclusion. Diagnostic evidence must be useful without leaking arbitrary document content or flooding storage. |
| Maximum GPU profile | Core | The highest concurrency and GPU-ceiling policy using the same engines as Performance with fewer internal limits. It exists for hardware and users who prioritize maximum throughput over heat and battery. |
| Maximum-mode quota | Conditional | The tracked allowance for high-cost Maximum queries under the relevant product tier. Maximum can use substantially more local model sessions and background time than Standard. |
| Memory pressure | Core | The runtime condition nominal, warning, or critical indicating process or system memory stress. Image and model buffers can cause jetsam termination before ordinary Swift errors occur. |
| Metal Performance Shaders | Conditional | Apple GPU primitives and infrastructure used alongside custom Metal kernels. They support optimized matrix and buffer operations on unified-memory hardware. |
| Minimal optimization level | Conditional | The emergency configuration retaining only essential retrieval and generation with small limits and no agentic steps. Critical thermal state needs a deterministic safe mode rather than a best-effort full pipeline. |
| Neural Engine | Core | Apple's dedicated machine-learning accelerator available through Core ML scheduling. Embedding, OCR, and model inference can run efficiently without treating CPU or GPU as the only compute resources. |
| Performance profile | Core | The profile allowing all compute units and moving sufficiently large searches to GPU. It prioritizes latency when the user accepts higher energy and thermal cost. |
| Query timeout | Core | The maximum wall-clock allowance for a query configuration. Retrieval or model loops need a hard latency boundary and a path to cancellation or partial result. |
| QuotaPolicy | Core | The centralized limits for libraries, documents, and feature access by workspace tier. Scattered magic limits create inconsistent behavior and difficult migrations. |
| SettingsStore | Core | The persisted central source for user model, routing, quality, GPU, RAG tuning, privacy, and presentation settings. Query execution must snapshot one coherent setting state rather than reread mutable UI values during the run. |
| Shared vector-store materialization guard | Core | The rule that sync aborts if iCloud reports a vector store but the file contents have not downloaded and cannot be read. An unavailable shared file can look like an empty library and cause destructive overwrite. |
| Spotlight indexing | Conditional | Publishing document and library metadata to Core Spotlight for OS-level discovery. Users can find an indexed document from system search without exposing the corpus to a remote service. |
| Step cooldown | Conditional | A short delay inserted between expensive stages under the resolved adaptive policy. Cooldowns allow heat, memory, and asynchronous hardware work to settle during sustained multi-step queries. |
| StoreKit entitlement | Core | The verified purchase or subscription state controlling library count, document limits, sync, and higher-cost modes. Product limits must be enforced consistently across UI and engine entry points. |
| Sync bootstrap conflict | Conditional | The state where both local and iCloud workspaces contain meaningful independent libraries and the engine cannot safely choose one automatically. Blind replacement could delete unique documents or duplicate libraries. |
| Sync merge plan | Conditional | The deterministic mapping of source libraries/documents to canonical identities across local and shared roots. Merging must preserve identity, deletion, and source-container relations rather than concatenate files. |
| Sync write-in-progress guard | Core | The process-wide flag preventing local change notifications from recursively starting another sync while a sync write is active. Sync writes themselves create filesystem changes that could otherwise trigger loops. |
| Thermal state | Core | The ProcessInfo classification nominal, fair, serious, or critical. Sustained OCR, embedding, and model work can heat mobile devices and trigger throttling or termination. |
| TOPS lookup | Support | A device-identifier table of approximate or projected trillion-operations-per-second figures shown for explanatory hardware context. Apple exposes no public live Neural Engine occupancy or throughput measurement API. |
| Unified memory | Core | Apple's memory architecture in which CPU and GPU can access the same physical memory pool. It enables near-zero-copy vector and image paths but also means every subsystem competes within one process memory budget. |
| vDSP | Core | Accelerate's vectorized digital signal processing primitives used for dot products, sums, division, clipping, and matrix multiplication. It provides highly optimized SIMD arithmetic without handwritten CPU loops. |
| Vector sync signature cache | Support | A conservative signature of file attributes and document/source sets recorded after a sync proves local and shared vector stores already match. It avoids repeatedly deserializing every vector record merely to decide that no write… |
| WorkspaceSyncService | Conditional | The per-library iCloud workspace synchronizer for containers, documents, vector artifacts, queue state, tombstones, and conflict resolution. Users need the same indexed library across devices without a custom backend. |

### Corrections

- OI-0558 GPU execution profile: it governs Core ML units, ingestion embedding units, the MMR matrix and concurrency ceilings. It does not govern the vector-search GPU path.

### Can you explain it?

1. Name the five tiers and what detects them.
2. Give the compute-unit request for each GPU profile on the query path and on ingestion.
3. List the five background task identifiers with their intervals.
4. Explain what critical thermal does and what memory pressure does.
5. Describe the 1.68-second churn: what it was, what bounded it, what is still open.

### Quiz

<details><summary><strong>What does the device capability ladder scale?</strong></summary>

Agentic step concurrency (3 to 32), step cooldown (100 ms to 0), vector batch size (128 to 16,384), embedding batch (8 to 512), the matrix-multiply threshold, Vision concurrency (2 to 64), PDF render concurrency (1 to 64, capped by memory), embedding concurrency (2 to 64).

</details>

<details><summary><strong>Which background tasks are registered and when may they run?</strong></summary>

Continued ingestion and continued query (system-scheduled), index maintenance no earlier than 4 hours and only on external power, Spotlight reindex no earlier than 2 hours, app refresh no earlier than 30 minutes. iOS only.

</details>

<details><summary><strong>What happens at critical thermal state?</strong></summary>

`AdaptivePipelineOptimizer` switches to minimal mode for device protection. Serious thermal no longer throttles; critical memory pressure switches to efficient mode.

</details>

<details><summary><strong>What was the idle churn?</strong></summary>

`reloadWorkspaceData()` fired every 1.68 seconds while idle because a container's orphaned state never resolved, reloading every vector store each time: 2,848 loads in 164 idle seconds. The router now compares an on-disk signature first, so the reload is free, but the timer still fires.

</details>

<details><summary><strong>How does the app know which chip it is on?</strong></summary>

`utsname` for the device model, `sysctlbyname("machdep.cpu.brand_string")` for the chip name on Mac, physical memory, and a Metal device query for GPU limits, parsed into a tier and a TOPS figure by lookup.

</details>

---

## Module 16. Dormant, future, superseded, and commonly misnamed mechanisms

**What it is.** The blueprint shelf. Things that are in the source but not in the machine that runs today, and old names that mislead if taught as current.

**In the bank's words.** Some blueprints are in the workshop but are not part of the machine that runs today. This section labels them clearly so you do not mistake a plan for a working gear.

**Why it exists.** A repository accumulates scaffolds, reserved enums and superseded names, and a document that teaches them as live behaviour is the most expensive kind of wrong. The bank's status vocabulary exists for this: Core, Conditional, Support, Dormant, Future, Historical. Learn the dormant list as carefully as the core list, because interviewers ask about exactly these.

**Where it runs.** Nowhere. That is the point.

### The word bank (25 concepts)

| Concept | Status | In one sentence |
|---|---|---|
| 18-of-20 zero-hallucination result | Historical | A withdrawn accuracy claim from an invalidly fast synthetic run where generation likely did not execute as assumed. Untrustworthy evaluation evidence should be removed rather than updated cosmetically. |
| 32K PCC window | Historical | A compatibility fallback and historical documentation value for potential cloud context. The public shipping runtime has not verified this as an active OpenIntelligence production limit. |
| 3B versus 20B selector | Historical | The withdrawn implication that the app can choose between exact on-device parameter-count tiers. The framework exposes availability and execution, not a reliable selector or attestation for these sizes. |
| AFM 3 Core Advanced label | Historical | A withdrawn user-facing model-tier name not selectable or observable through the public SDK. A precise name implied control the app did not have. |
| Approximate confidence probability | Historical | The mistaken interpretation that a displayed heuristic confidence value is a statistically calibrated probability of truth. Calibration requires held-out outcome frequencies and reliability analysis. |
| Automatic online self-training | Historical | The idea that the app continuously retrains or autonomously changes its models from ordinary user activity. The current engine adjusts policy and configuration but does not train the bundled embedding or reranker models on user… |
| AutoTuneService | Support | The service intended to update selected retrieval thresholds or policies from measured evaluation data under explicit constraints. Tuning should be evidence-driven and bounded rather than silently self-modifying from user answers. |
| Bundled Core ML generative backend | Historical | A removed custom local generative model path distinct from Apple Foundation Models. The current product relies on the system language model and deterministic analysis paths. |
| Default HNSW architecture | Historical | The incorrect generalization that OpenIntelligence always uses an approximate HNSW vector index. The default current store is BNNSVectorDatabase exact scan; HNSW belongs only to the optional Vectura path. |
| Dynamic Foundation Model profiles | Dormant | A registry intended to describe runtime Foundation Model capability profiles. It anticipated a more observable model-tier API. |
| Embedding-based chunk boundary detection | Dormant | The implemented path that would compare adjacent sentence embeddings and split where semantic similarity falls. It could add language-independent topical boundaries beyond headings and transition phrases. |
| Fixed 384-dimensional architecture | Historical | The oversimplified claim that all OpenIntelligence embeddings are 384-dimensional. 384 is the default MiniLM space, while configured Natural Language providers use 512 and the dormant AppleFM scaffold declares 1,024. |
| Late chunking | Historical | A research technique that embeds a long document jointly and pools token states for each later chunk span. It could preserve cross-chunk context, but that is not what the current SemanticChunker does. |
| Live Neural Engine utilization | Future | A hypothetical percentage or occupancy metric for the Apple Neural Engine. No public API currently supplies live ANE utilization to this app. |
| Local GGUF backend | Historical | A previously supported or considered local generative model format removed from the current architecture. The app consolidated on Apple Intelligence and On-Device Analysis rather than maintaining bundled third-party generative… |
| Local MLX generative backend | Historical | A removed local generative model path based on MLX-style execution. Maintaining several model runtimes increased complexity and fragmented routing. |
| Model judges | Historical | The withdrawn claim that a separate model grades answer correctness. No implemented model-as-judge service exists in the active engine; deterministic verification and benchmark ground truth serve different roles. |
| Neural extractive QA model | Dormant | The planned Core ML start/end-span model represented by a stub protocol implementation. The design is present, but the active answer path uses heuristic extraction and specification logic. |
| PCC simulation | Historical | The withdrawn description that older OS versions simulate Private Cloud Compute. A simulation would misstate privacy and route behavior. |
| Production PCC | Dormant | The source architecture for live Private Cloud Compute completion. The route is intended for oversized evidence and deeper reasoning, but current App Store binaries were built without the required SDK path. |
| RAPTOR L2/L3 hierarchy | Future | Section- and corpus-level abstraction layers above current document summaries. They could support hierarchical retrieval across very large libraries. |
| Single 29-step pipeline | Historical | The older documentation shorthand that represented the engine as one fixed numbered sequence. Current execution branches by file type, intent, quality mode, evidence, device state, and route, so no one number captures every path. |
| Single recursive thought loop | Historical | The oversimplified label for several distinct mechanisms: execution planning, iterative retrieval, recursive multi-session RAG, Self-RAG, critique/refinement, and deterministic verification. Collapsing them hides which component… |
| Unmeasured speed multipliers | Historical | Withdrawn claims such as 1,000x, 240x, 100x, or 4x improvements without supporting benchmark artifacts. Mechanism changes can be real while exact performance factors remain unproven. |
| Zero latency | Historical | The withdrawn description of on-device generation as having no latency. Physical-device measurements show nonzero time to first token and throughput limits. |

### Corrections

- Add to the dormant list: the `SpeechAnalyzer` transcription branch (guarded by a module that does not exist; never compiles).
- Add to the historical list: the `.cpuAndGPU` Maximum profile (removed the Neural Engine; fixed 2026-08-26) and the `NSImage.lockFocus` macOS render path (4× oversize, 370 MB per page; replaced by a `CGBitmapContext`).

### Can you explain it?

1. Name every Dormant item and say what runs instead.
2. Name every Future item.
3. Explain why HNSW is not used and what is used instead (exact scan over mmap).
4. Say what the advanced20B alias actually executes.
5. Explain the difference between PCC in source and PCC in a shipped build.

### Quiz

<details><summary><strong>Why is there no approximate nearest-neighbour index?</strong></summary>

Because an exact scan over memory-mapped, normalised vectors on Accelerate or Metal is fast enough at the library sizes a phone holds, and it has no recall loss. HNSW is a reserved name.

</details>

<details><summary><strong>What does the Apple Foundation Models embedding provider do today?</strong></summary>

Nothing usable. It is a 1,024-dimension placeholder scaffold and must not be described as a shipped embedder.

</details>

<details><summary><strong>Which transcription path never runs?</strong></summary>

The `SpeechAnalyzer` branch. `SFSpeechRecognizer` with on-device recognition runs instead.

</details>

<details><summary><strong>What is the difference between PCC existing in source and PCC being in production?</strong></summary>

The route compiles under Swift 6.4 and iOS 27, but a given App Store build may carry zero PCC symbols and iOS 26 users always get the on-device route. Say which build you mean.

</details>

<details><summary><strong>What replaced the bundled Core ML generative backend?</strong></summary>

Nothing bundled. Generation is the system language model through Foundation Models; deterministic extraction handles what does not need a model.

</details>

---

## The interview drills

**Ninety seconds.** "OpenIntelligence turns your files into a private, searchable knowledge base
on the device. Ingestion extracts, chunks and embeds every document into two indexes, one for exact
words and one for meaning. A question is searched both ways in parallel, fused, reranked by a
cross-encoder, and packed under a hard token budget. Apple's on-device model writes a typed answer
with citations, and nine deterministic gates decide what is allowed to stand. Only the final answer
may leave the device, to Private Cloud Compute, and only after the app shows you exactly what would
be sent and you agree."

**Five minutes.** The twelve sentences above, each expanded with one number: 310 words, 510
tokens, 384 dimensions, 1,000 vectors, k = 60, 0.7 and 0.3, 4,096 and 3,200, 0.40 and 0.55, nine
gates, 180 seconds.

**At the whiteboard.** Draw the two indexes, the parallel search, the fusion, the shortlist, the
budget, the plan, the model, the gates. Then be asked "where does the Neural Engine run?" and answer
honestly: the code requests it on five lines and Apple decides; nothing in the app can measure it.

## Corrections in one place

| Claim as taught | What the source says |
|---|---|
| Audio goes through `SpeechAnalyzer` | The branch never compiles. `SFSpeechRecognizer`, on device, in 600-second segments. |
| Embeddings run on the Neural Engine | Requested, not placed. Efficiency and Balanced request CPU + Neural Engine; Performance and Maximum request all units; Core ML decides. Core AI exposes nothing. |
| The GPU profile decides whether vector search uses Metal | It does not. The switch is 1,000 vectors and a Metal device. The profile gates Core ML units and the MMR matrix. |
| `RecognizeDocumentsRequest` does OCR | It parses structure and tables. `VNRecognizeTextRequest` does OCR. |
| Page rendering is zero-copy | The PNG round trip is skipped; a full-page bitmap is still allocated per page. |
| Maximum verification bar is 0.98 | 0.80. The 0.98 target lives in the agentic loop, not the gate. |
| The advanced on-device model | Executes the default model. No advanced model exists in the SDK. |
| Core AI is a fallback | On iOS 27 and macOS 27 it is the default and saved Core ML defaults are migrated to it. |
