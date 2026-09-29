# Ingestion, parsing/OCR, chunking and embedding in OpenIntelligence (code at b37ab4c, shipped as 5.4)

**Scope and method.** This is a read-only static audit of the Swift source at commit `b37ab4c15f89` (a merge dated 2026-09-25; the working tree was clean). No build, simulator run or device run was done, so nothing here was observed at runtime.

**Evidence tags.** Tags follow the repository protocol as `[evidence_level, confidence]`:
- `code_verified`: I read the code path myself.
- `grep_verified`: found, or ruled out, by a repository-wide search. Every absence claim was checked two ways (the symbol plus other spellings or call sites).
- `doc_claim_only`: stated in a doc and not confirmed in code.
- `inferred`: deduced from code I read, but not observed.
- `unknown`: could not be established.

**Citations.** Sources are written `ALIAS:line`. All paths are relative to `/home/user/OpenIntelligence/`:

| Alias | Path |
|---|---|
| DP | `OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift` (10,025 lines) |
| SDP | `OpenIntelligence/Services/Document/Processing/StructuredDocumentParser.swift` |
| SC | `OpenIntelligence/Services/Document/Chunking/SemanticChunker.swift` |
| PCA | `OpenIntelligence/Services/Document/Chunking/PageComplexityAnalyzer.swift` |
| OCR | `OpenIntelligence/Services/Document/Config/OCRConfiguration.swift` |
| IU | `OpenIntelligence/Services/Document/Classification/ImageUnderstandingService.swift` |
| SAS | `OpenIntelligence/Services/Document/Analysis/SpeechAnalyzerService.swift` |
| ATS | `OpenIntelligence/Services/Document/Extraction/AudioTranscriptionService.swift` |
| ES | `OpenIntelligence/Services/Embedding/EmbeddingService.swift` |
| EF | `OpenIntelligence/Services/Embedding/EmbeddingFingerprint.swift` |
| EP | `OpenIntelligence/Services/Embedding/Providers/EmbeddingProvider.swift` |
| CML | `OpenIntelligence/Services/Embedding/Providers/CoreMLSentenceEmbeddingProvider.swift` |
| CAI | `OpenIntelligence/Services/Embedding/Providers/CoreAISentenceEmbeddingProvider.swift` |
| AFM | `OpenIntelligence/Services/Embedding/Providers/AppleFMEmbeddingProvider.swift` |
| NLE | `OpenIntelligence/Services/Embedding/Providers/NLEmbeddingProvider.swift` |
| AEO | `OpenIntelligence/Services/Embedding/AdaptiveEmbeddingOptimizer.swift` (holds `actor LibraryIntelligenceCenter`) |
| R | `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift` |
| RS | `OpenIntelligence/Services/RAG/Orchestration/RAGService+Streaming.swift` |
| DC | `OpenIntelligence/Core/Models/DocumentChunk.swift` |
| KC | `OpenIntelligence/Core/Models/KnowledgeContainer.swift` |
| BNNS | `OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift` |
| FTS | `OpenIntelligence/Services/Storage/SQLiteFullTextService.swift` |
| TOK | `OpenIntelligence/swift-transformers/Sources/TokenizersWrapper/Resources/embedding_tokenizer.bundle/tokenizer.json` |
| IPD | `Docs/INGESTION_PIPELINE.md` |
| ATLAS | `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md` |
| TPN | `THIRD_PARTY_NOTICES.md` |

## 1. Which code path parses each input type, which Apple APIs it uses, and how layout, headings, tables and figures become text

### Takeaway
Every input type goes through one call, `DocumentProcessor.processDocument`. It produces one flat normalised string and, for PDFs and some text formats, a list of structured elements. Everything after that point is text:
- Tables are serialised into up to three text renderings.
- Figures become a text description.
- Audio becomes a transcript.

On every shipping OS, PDFs go through Vision's `RecognizeDocumentsRequest` on rendered page images, or through PDFKit text on pages routed around Vision. Three weaknesses follow:
- Each page's elements are emitted in type order (title, then tables, then lists, then paragraphs) rather than reading order.
- Figure chunks are appended after the last page, so they inherit the wrong section.
- VisionKit is not used anywhere.

### Cited Findings
**Entry and dispatch**
- The ingestion entry point is `RAGService.addDocument` (R:5607). It calls `documentProcessor.processDocument(at:chunkOverride:containerId:)` (R:5955-5959). PDFs over 10 MB are diverted to `importLargePDFStreamed` instead (R:5939-5952; RS:19). `[code_verified, exact]`
- `processDocument` (DP:569) detects the type (DP:594; `detectDocumentType` at DP:9425):
  - XML over 50 MB is streamed with a SAX parser (`StreamingXMLProcessor`) directly into chunks with `structureType "streamed_xml"`, and those chunks' `wordCount` is `split(separator: " ")` (DP:602-680, 627-629).
  - Any other file over 500 MB is rejected (DP:687-691). `[code_verified, exact]`
- PDFs go to `extractStructuredPDFContent` (DP:707-718). That function detects the document language first (DP:3851). Under `#available(iOS 26.0, *)` it runs `extractWithStructuredParsing`; otherwise it runs the legacy `extractTextFromPDFWithPages` (DP:3853-3866). Its own comment says the legacy function is "only the pre-26 fallback … on every shipping OS it never ran" (DP:3847-3849). `[code_verified, high]`
- Non-PDF types go through `extractTextWithPageInfo` (DP:720-737; switch at DP:1121-1179):
  - text/markdown: `readTextFileWithFallbackEncodings` (DP:1127-1129)
  - rtf (DP:1131-1133)
  - png/jpeg/heic/tiff/gif: `extractTextFromImage` (DP:1136-1139)
  - 21 code/markup types (DP:1144-1148)
  - csv (DP:1151-1154)
  - office/iWork (DP:1157-1160)
  - audio/video (DP:1163-1166)
  - unknown: plain text is tried, otherwise `unsupportedFormat` (DP:1168-1178)
  - Empty text throws `emptyDocument` (DP:1182-1186).

  `[code_verified, exact]`
- For non-PDF types, heuristic structure is inferred from the extracted text (DP:724-730) unless the type is PDF, code or audio/video (DP:1241-1250). The heuristic parsers detect markdown pipe tables (DP:1796-1884), key–value blocks (DP:1884-1958) and "parallel list" tables (DP:1959-2090). `[code_verified, high]`

**PDF with a text layer, and scanned PDF (structured path)**
- Per-page Vision uses `RecognizeDocumentsRequest` (SDP:689), configured as follows:
  - `customWords` = universal words plus a per-document vocabulary (SDP:694)
  - `useLanguageCorrection = true` (SDP:695)
  - `minimumTextHeightFraction = 0.004` (SDP:627, 696)
  - explicit recognition languages when the document language was detected, auto-detect otherwise (SDP:706-710)
  - executed through `VisionOCRThrottle.performAsync` (SDP:714-721)

  `[code_verified, exact]`
- If Vision finds no document structure, the page falls back to `RecognizeTextRequest` (SDP:723-746; config at SDP:1419-1423). The whole page becomes one `.paragraph` element with `qualityScore 0.5` (SDP:735-740). `[code_verified, exact]`
- Render scale is 5.0× (≈360 DPI), or 6.0× (≈432 DPI) when the text layer is garbled or the page's complexity signals cross thresholds, for example `fineTextRisk ≥ 0.45`, `tablePresence > 0.16`, `columnCount > 1` or `textCoverage < 0.58` (DP:219-244). `[code_verified, exact]` The DPI conversion is my arithmetic (scale × 72) and matches the UI glossary copy of "360 to 432 DPI" (`OpenIntelligence/UI/Components/Glossary.swift:241`). `[inferred, high]`
- Pages that already have PDFKit layout text skip Vision layout detection (DP:4326-4328). Pages with no rendered image use `layoutText ?? plainText` from PDFKit and are traced as `structured-skip-vision-layout` / `structured-skip-vision-native` (DP:4430-4440). So a text-layer PDF can be ingested largely from PDFKit text, and a scanned PDF goes through `RecognizeDocumentsRequest` on the rendered image. `[code_verified, medium]` I read these fragments, not the full routing function (DP:3899-5090).
- Page complexity routing uses `PageComplexityAnalyzer.analyzeBatch` (DP:3363, DP:4100). That calls `analyze(page:pageNumber:)` **without** a page image (PCA:367-371). The Vision pass (`VNDetectRectanglesRequest` PCA:991, `VNDetectTextRectanglesRequest` PCA:1018) only runs `if needsVisionAnalysis, let image = pageImage ?? renderPageForAnalysis(page)` (PCA:294-299), and `renderPageForAnalysis` returns `nil` when UIKit is unavailable (PCA:1045-1072). `[code_verified, exact]`
- `DocumentProcessor`'s own page renderer does have an AppKit branch (DP:7061-7110), so the macOS build is AppKit-native rather than Catalyst. `[inferred, high]`
- Within a page, the structured snapshot emits elements in this fixed order (SDP:807-915):
  1. `document.title` (SDP:813-824)
  2. every table (SDP:832-836)
  3. every list (SDP:838-844)
  4. every paragraph (SDP:846-870)

  Paragraphs of 10 characters or fewer are dropped (SDP:852). Low-confidence text is kept but prefixed `[OCR quality: low]` (SDP:867); low-confidence titles are prefixed `[OCR unclear]` (SDP:819). `[code_verified, exact]`
- Pages are processed concurrently in task groups, then re-sorted by page index before assembly (DP:4397, DP:5017 structured; DP:3547, DP:3772 legacy). Repeated headers and footers and "garbage" lines are removed per page before text assembly (DP:5031, 5052; legacy DP:3775, 3783). `[code_verified, exact]`

**Figures**
- The OS 27 figure extraction block, which would crop figures and caption them with `VisualCaptioningService`, is commented out (SDP:872-905), and `figureCount` is the constant `0` (SDP:810). `VisualCaptioningService` is referenced nowhere else (repository grep found only SDP:895). `[grep_verified, high]`
- Figures come instead from `analyzeEmbeddedImages` (DP:7129). It calls `ImageUnderstandingService.shared.analyzeDocumentImages` (DP:7172; IU:465), which runs at most 2 concurrent analyses (IU:484) and sorts results by page (IU:539). `[code_verified, exact]`
- Those figure elements are **appended after all page elements** (DP:5045-5048). `createStructureAwareChunks` walks elements in order and keeps a running `currentSectionTitle` (DP:5248-5260), so every figure chunk inherits the section title and path of the last titled page in the document. `[code_verified for the ordering, exact; mislabelled section is inferred, high]`
- Figure chunk text is a labelled block (DP:5696-5738):
  - `Section Path:`, `FIGURE:`, `TYPE:`, `CLASSIFICATIONS:`
  - `CAPTION:` (≤220 characters), `SUMMARY:` (≤320), `LABELS:` (OCR, ≤280)
  - `NEARBY BEFORE:` / `NEARBY AFTER:` (≤220 each)
  - `SOURCE: <file>, page N`

  Image metadata fields are filled from it (DP:5434-5454). `[code_verified, exact]`

**Images (standalone files)**
- `extractTextFromImage` (DP:7558) calls `ImageUnderstandingService.analyzeStandaloneImage` (IU:923). That service uses:
  - `ClassifyImageRequest` (IU:143), falling back to `VNClassifyImageRequest` (IU:171)
  - `VNRecognizeTextRequest` for OCR (IU:231; config IU:279-282)
  - a FoundationModels `LanguageModelSession` description (IU:647-684)

  `processDocument` then also runs `StructuredDocumentParser.parsePageImage` with `customWords: []` and prepends its output (DP:7597-7614). `[code_verified, exact]`

**DOCX / XLSX / PPTX / iWork**
- Office files are unzipped by an in-repo ZIP reader (DP:9612-9790, including a custom deflate path at DP:9772) and parsed with **regular expressions over the XML**, not an XML parser (DP:8872-9380):
  - Word: tables via `<w:tbl>` placeholders (DP:8983-9014), paragraphs via `<w:p\b[^>]*>(.*?)</w:p>` (DP:9022), list items via the presence of `<w:numPr>` (DP:9024)
  - Excel: shared strings and sheets (DP:9131-9243)
  - PowerPoint: slides (DP:9270-9380)
  - tables rendered as pipe tables (DP:9243)

  `[code_verified, high]`
- Heading styles: I found no `pStyle`/`Heading` handling in `extractTextFromWordXML` (DP:8975-9075 searched for `pStyle|Heading|heading`). DOCX headings therefore reach the chunker as plain paragraphs, and only the chunker's text heuristics can recover them. `[grep_verified within that range, medium]`
- iWork (Pages/Numbers/Keynote) content is not parsed. The code logs that `.iwa` protobuf "this app does not parse" (DP:8839-8845). Legacy `.doc/.xls/.ppt` throws `legacyOfficeFormat` (DP:8832-8835). `[code_verified, exact]`

**Markdown / plain text / RTF / CSV / code**
- Headings are detected only by the chunker's `detectSections` (SC:873):
  - Markdown `#`, `##`, `###` patterns (SC:880-884)
  - numbered and ALL-CAPS patterns
  - title-case heuristics with blacklists and known-heading sets (SC:897-937, SC:988-1040)

  `[code_verified, high]`
- CSV has delimiter detection and a row parser (DP:8603-8770). Code files are read as-is (DP:8596). `[code_verified, high]`

**Audio / video**
- `extractTextFromAudioVideo` (DP:8774) calls `SpeechAnalyzerService.analyze`. The language comes **only from filename hints** such as `_es`, `spanish` or `_ja`, defaulting to `en-US` (DP:8783-8797). `[code_verified, exact]`
- The `SpeechAnalyzer` path is compiled only under `#if canImport(SpeechAnalyzer)` / `import SpeechAnalyzer` (SAS:17-19, 93-100, 141-145, 160). It calls `SpeechAnalyzer(locale:)` and `analyzer.results(for: url)` and reads `result.bestTranscription.formattedString`/`.segments` (SAS:169-209). Otherwise it falls back to `AudioTranscriptionService`, which uses `SFSpeechRecognizer` with `SFSpeechURLRecognitionRequest` and `requiresOnDeviceRecognition = true` (SAS:235-243; ATS:92-96, 215-217). `[code_verified, exact]`
- No type or module named `SpeechAnalyzer` exists anywhere in the repository (grep for `class|struct|actor SpeechAnalyzer`, `name: "SpeechAnalyzer"`, and directories named `SpeechAnalyzer*` all returned nothing). Apple ships `SpeechAnalyzer` inside the `Speech` framework (the file already does `import Speech`, SAS:15), and the call shape above looks like the `SFSpeechRecognitionResult` API. Whether `canImport(SpeechAnalyzer)` is true under the Xcode 27 SDK, and therefore which path runs, cannot be settled here. `[unknown; inferred that the legacy SFSpeechRecognizer path is the one that runs, medium]`

**Vision / VisionKit / DataDetection inventory**
- Vision requests in the ingestion code:
  - `RecognizeDocumentsRequest` (SDP:689; `IntelligentDocumentProcessor.swift:847`; `CoreMLRegionDetector.swift:429`)
  - `RecognizeTextRequest` (SDP:1419)
  - `VNRecognizeTextRequest` revision 3 with language correction and `minimumTextHeight 0.0` (OCR:190-205; `LayoutAwareExtractor.swift:238-246`; IU:231)
  - `.fast` recognition in the region detector (`CoreMLRegionDetector.swift:356`)
  - `VNDetectRectanglesRequest` / `VNDetectTextRectanglesRequest` (PCA:991, 1018)

  `[grep_verified, high]`
- **VisionKit is never imported.** A repo-wide grep for `VisionKit` across `.swift`, `.pbxproj`, `.plist` and `.entitlements` finds only the Boolean `supportsVisionKit = true` capability flags (R:18829, R:18944, R:19188). A second search for `VNDocumentCameraViewController|DataScannerViewController|ImageAnalyzer` found nothing. `[grep_verified, high]`
- **DataDetection** is imported (SDP:14). `extractDetectedData` reads `text.detectedData`, maps Apple's `DataDetector.Match` values (email, phone, URL, address, date, money, measurement, flight number, shipment tracking, payment identifier; SDP:91-128), and adds regex sweeps for types Apple returned nothing for (SDP:1285-1310). Its **only call site is per table cell inside `parseTable`** (SDP:961-962). The only other `detectedData` read is inside that function (SDP:1308). `[grep_verified, high]`

**How tables become text**
- Every Vision/heuristic table becomes a *structural* chunk (DP:5807-5838):

  ```
  Section Path: …
  TABLE: <title>
  HEADERS: h1 | h2 | …
  ROW n: v1 | v2 | …
  [Specifications]
  <key>: <value>   (one line per pair)
  SOURCE: <file>, page N
  ```

  Tables over 380 words are split with `splitOversizedAtomicChunk` (DP:5287-5316). `[code_verified, exact]`
- `keyValuePairs` is an **ordered** tuple array, so it is deterministic (SDP:428-477):
  - 2-column tables give column 0 as the key and column 1 as the value.
  - Multi-column tables with a header row emit one `header: cell` pair per cell.
  - Tables with 3 or more columns and no header give no pairs.

  `[code_verified, exact]`
- A second *semantic* chunk is always emitted (DP:5840-5886): "This {technical reference|research data|…} from {file} page N describes {title}. It appears under {path}. Columns include {first 5 headers}. Key values include {first 4 pairs}." or "Representative rows: {first 2 rows}". `[code_verified, exact]`
- A third set, per-row "COMPATIBILITY ROW" chunks, is emitted when all of these hold (DP:5888-5929):
  - the title or a header contains one of the hard-coded signals `compat, requirement, supported, model, camera, head, coupler`
  - there are at least 3 headers and at least 2 rows
  - the source is trusted (`vision_document`, `layout_table`, `crop_rescue`)

  `[code_verified, exact]`
- Structured table payloads (headers, rows, quality) also go to FTS side tables (R:6585-6596). `[code_verified, exact]`
- Lists become **one chunk per item**, each headed by `Section Path:` or `Section:` (DP:5393-5419, 5788-5799). `[code_verified, exact]`
- In the structured path the section "hierarchy" is a single level: `currentSectionPath = [titleText]` from Vision's per-page `document.title`. The code says why: "Structured parsing currently gives us flat page titles, not true heading levels" (DP:5250-5256). `[code_verified, exact]`

### Inferences
- The emission order (tables and lists before paragraphs, paragraphs buffered until the next atomic element) means introductory prose like "Table 3 shows…" lands in a chunk *after* the table it introduces, and paragraphs from page N can be flushed together with text from later pages. Reading order is preserved across pages but not within a page in the structured PDF path. `[inferred, high]`
- A table's content is indexed at least twice (structural and semantic), sometimes N+2 times (with compatibility rows). Its numbers appear in `[Specifications]` lines, in `ROW` lines, and again in the summary sentence. This multiplies near-duplicate chunks competing for retrieval slots. `[inferred, high]`
- Any answer path that quotes chunk `content` verbatim (for example an extractive shortcut) will surface these serialisation artefacts:
  - `TABLE:/HEADERS:/ROW n:` lines
  - `[Specifications]` blocks
  - `Section Path:` and `SOURCE:` header lines
  - `[OCR quality: low]` and `[OCR unclear]` markers

  `[inferred, high]`

### Gaps
- I did not read the full per-page routing in `extractWithStructuredParsing` (DP:3899-5090), including hybrid mode and region-crop rescue. The exact rule for when a text-layer page skips Vision is only partly verified.
- Whether `DocumentObservation.Container.paragraphs` repeats text that also appears in `tables`/`lists` depends on Apple's API; if it does, content would be duplicated. It needs an SDK check or a device run.
- Which speech path runs under Xcode 27 (the `canImport(SpeechAnalyzer)` question) needs an SDK check: `find /Applications/Xcode.app -name '*SpeechAnalyzer*'`.

## 2. How text becomes chunks: chunker, window and overlap, self-tuning, parent/child, contextual prefix, sections, entities and metadata

### Takeaway
There is one real chunker, the synchronous `SemanticChunker.chunkText`. It is word-based, with a hard maximum of 310 words and an effective target of at most 260 words and overlap of at most 50 words, because `DocumentProcessor` clamps every request. The self-tuning "window" values (280–420 words) therefore never take effect.

Boundaries come from section, table and transition-phrase heuristics, then from a character-length estimate snapped to NLTokenizer sentence boundaries inside ±100/±30-character windows. That snapping can cut mid-word.

A second, token-based guard at 430 tokens splits oversized chunks by rewriting their text: it splits on every `.`, `!`, `?` and newline and rejoins with ". ".

`contextualPrefix` *is* populated, but only with the filename plus a heading path. The "parent" of a table, list or figure chunk is just the section title string.

### Cited Findings
**Which chunker runs**
- Both ingestion branches call `SemanticChunker().chunkText(...)`: the flat branch (DP:911-954) and the structure-aware paragraph buffer (DP:5199-5206, one new chunker per flush). `[code_verified, exact]`
- The async `chunkTextAsync`, which uses sentence-embedding boundaries (SC:598-652, `detectEmbeddingBoundaries` SC:1147), has no call site outside its own file (grep for `.chunkTextAsync(`). The sync version records `embeddingBoundaryCount: 0` (SC:571). So embedding-based topic segmentation, advertised in the file header (SC:10-16), does not run in ingestion. `[grep_verified, high]`
- The file header explicitly says this is **not** late chunking: "the chunks are then embedded independently and carry no cross-chunk context … Real late chunking is tracked as its own roadmap row" (SC:18-28). `[code_verified, exact]`

**Sizes, window, overlap (all in words, not tokens)**
- `SemanticChunker.ChunkingConfig` constants (SC:156-174):
  - `safeMaxSize = 310`
  - `maxTargetSize = 260`
  - `maxOverlap = 50`
  - `minTargetSize = 100`
  - defaults: target 260, min 80, max 310, overlap 50, `parentWindowChars = 250`

  `[code_verified, exact]`
- Presets (SC:180-214):
  - `technicalReference`: target 240, min 80, max 310, overlap 45
  - `narrative`: 260/100/310/50
  - `code`: 180/50/280/35

  `recommended(for:)` maps types to presets (SC:217-250):
  - PDF, images and CSV → technicalReference
  - code/markup → code
  - markdown/text/rtf/unknown → the default config
  - office and audio/video → narrative

  Strategy overrides (SC:256-281):
  - `densePrecision`: target ≤190, max ≤240, overlap 30–45, parent ≤180 characters
  - `elastic`: target 300–310, min ≥100, overlap ≥65, parent ≥320 characters

  `[code_verified, exact]`
- `DocumentProcessor` builds the effective config as follows (DP:858-884). `[code_verified, exact]`
  - `targetSize = min(window, 260)`
  - `minSize = max(preset.min, 60)`
  - `maxSize = 310`
  - `overlap = min(overlap, 50)`

  `parentWindowChars` is not passed, so it is always the default 250, and the strategy presets' `maxSize` (240) and parent windows (180/320) are discarded. `[code_verified, exact]`
- `RAGService.ChunkingDefaults` is `targetWindow = 350`, `overlap = 60` (R:1576-1579), and `DocumentProcessor.init` defaults to 350/60 (DP:430). Both exceed the clamp, so neither is ever the effective size. `ChunkingDefaults` is used only for rebuild comparisons and self-tuning deltas (R:7939-7941, R:8422-8423). `[code_verified, exact]`
- The document's `ProcessingMetadata` records the **unclamped** requested window and overlap (`targetWordWindow = activeWindow`, `overlapWords = activeOverlap`), with strategy defaulting to `"balanced"` (DP:1053-1055). The recorded window is not the window that ran. `[code_verified, exact]`

**Self-tuning (LibraryIntelligenceCenter, ChunkingPlan, ChunkingDirective, predictive pre-scan)**
- **Predictive pre-scan.** When `container.autoAdaptDimension` is set, `addDocument` extracts a preview before each ingest: the first 10 PDF pages' `page.string`, or for other types `String(contentsOf:encoding: .utf8).prefix(10000)` (R:8326-8345). It then calls `recommendChunkingPlan` (AEO:174-217, which estimates `avgWords = words/10`, AEO:193) and **overwrites the container-wide `chunkingDirective`** (R:5907-5937). The initial override comes from the container's current directive (`let chunkOverride = chunkingOverride(for: container)`, R:5770; R:8314-8324). `[code_verified, exact]`
- `buildChunkingPlan` (AEO:221-271) picks the window and overlap:

  | Condition | Window | Overlap |
  |---|---|---|
  | code | 280 | 50 |
  | math | 320 | 55 |
  | structuredRatio > 0.35 | 300 | 55 |
  | multilingual > 0.6 (`elastic`) | 380 | 65 |
  | otherwise | `clamp(avgWords, 300…420)` | 60 |
  | any OCR asset present | (unchanged) | at least 70 |

  **Every window is ≥ 280 and every overlap ≥ 50**, so after the clamp (260/50) the directive changes only the *strategy*: the minimum size (60/80/100) and topic detection. It changes the target and overlap only relative to a container with *no* directive, whose presets are 240/45 (PDF) or 180/35 (code). `[code_verified for the values, exact; net effect inferred, high]`
- **Post-ingest self-tuning.** `generateIntelligenceSnapshot` runs `analyzeLibrary` over all chunks in the library (AEO:100-171; R:535-557). When `autoAdaptDimension` is set (R:571), a chunk shift is applied immediately ("Dynamically adjusted chunking configuration … No rebuild required", R:579-591). A shift is triggered by a strategy change, a window shift of 40 or more words, or an overlap shift of 15 or more (R:8417-8451). `[code_verified, exact]`
- The directive carries `updatedAt: Date` (KC:408-413). `[code_verified, exact]`

**The boundary algorithm and why cuts can land mid-word**
- `chunkText` works as follows (SC:325-581):
  1. Texts under `minSize` words become a single chunk whose `parentContent` is the whole text (SC:336-361, SC:1944-1949).
  2. Otherwise it loops, calling `findOptimalChunkRange`, for up to 50,000 chunks (SC:379-508).
  3. A **hard limit** truncates any range longer than `maxSize` words at an NLTokenizer word boundary; the remainder flows into the next chunk, so nothing is lost (SC:435-464).
  4. Micro-chunks under 15 words are merged into the previous chunk (SC:512-556).

  `[code_verified, exact]`
- `findOptimalChunkRange` (SC:1225-1364) tries, in order:
  1. section starts within `[start+minSize·3, start+maxSize·10]` **characters** whose word count fits `[min,max]`
  2. table-block ends
  3. topic boundaries, which are occurrences of 10 transition phrases such as "However," or "In conclusion," (SC:1109-1127)
  4. a fallback: the character length of the first `targetSize` words split on `" "` only (SC:1292-1327), snapped with `findNearestSentenceEnd(within: 100)` (SC:1330-1332), then table protection (SC:1335-1361)

  `[code_verified, exact]`
- `findNearestSentenceEnd` tokenises only a ±100-character substring with `NLTokenizer(.sentence)` and treats **every sentence token's `upperBound` as a boundary** (SC:1369-1406). That includes the last token, which ends wherever the window ends. `findNearestSentenceStart` treats every token's `lowerBound`, including the first token at the window start (index − distance), as a sentence start (SC:1410-1440). `[code_verified, exact]`
- `advancePosition` (SC:1859-1888) finds the next chunk's start this way:
  1. Take the last `overlap` words (split on `" "`) and search backwards for them joined with single spaces.
  2. Snap to `findNearestSentenceStart(…, within: 30)`.
  3. If the joined text is not found (newlines or double spaces inside the overlap region), there is **no overlap**: it returns `chunkEnd`.

  `buildParentContent` uses the same helpers within ±120 characters (SC:1443-1461). `[code_verified, exact]`
- Word counts inside the chunker use NLTokenizer word units (SC:91-99). The boundary estimate uses `split(separator: " ")` (SC:1293) and `advancePosition` uses `split(separator: " ")` too (SC:1867), so three different notions of a "word" feed one boundary decision. `[code_verified, exact]`

**Token guard and the text-rewriting splitter**
- After chunking, `enforceTokenLimitOnChunks` (DP:6479-6532) splits any chunk over `safeTokenLimit = 430` tokens. The constant is 510 − 80 tokens reserved for the prefix (DP:6433-6440), counted with the real tokenizer or `chars/3+2` as fallback (DP:6450-6462). `[code_verified, exact]`
- The splitter, `splitOversizedChunkByTokens` (DP:6597-6674), does the following:
  - splits on the character set `".!?\n"`, which includes every decimal point, abbreviation and line break (DP:6603)
  - rejoins with `". "` (DP:6643, 6647), so "4.5 L" becomes "4. 5 L" and a newline-separated table becomes one run-on line
  - prefixes each part with `[Part N]\n` (DP:6615, 6632, 6656)
  - force-splits single over-long "sentences" on spaces (DP:6622-6645)

  Sub-chunks inherit the parent's metadata and page offsets, and only the first keeps the structured table payload (DP:6677-6716). `[code_verified, exact]`
- Stage conservation is recorded (DP:838-842, 956-968), and `verifyContentCoverage` compares unique words and non-whitespace character volume. Both only **log** warnings (below 90% words or characters, or above 200% characters) and change nothing (DP:6722-6817). `[code_verified, exact]`

**Parent/child**
- `parentContent` depends on the path:

  | Path | `parentContent` | Source |
  |---|---|---|
  | Prose chunks (both paths) | ±250-character window snapped to sentence starts/ends (±120 search) | SC:479-483, SC:1443-1461 |
  | Table, list and figure chunks | the **section title string** (`parentText: currentSectionTitle`) | DP:5311, 5320, 5345, 5373, 5405, 5463, 5471 |
  | Micro-chunk merges | concatenated parents | SC:521-523 |
  | Rebuild from FTS5 | `nil` | R:7984 |

  `[code_verified, exact]`
- `ChunkMetadata.siblingGroupId` is set for table, list and figure chunks as `"{table|list|figure}-p{page}-{slug(title)}"` (DP:5767-5772). `siblingCount` is never set for detail chunks: `makeChunkMetadata` has no such parameter (DP:5614-5667), and the only non-forwarding writers are summary chunks (`siblingCount: 1`, `DocumentSummaryService.swift:160`) and two `nil` writes (R:10704, 10756). `[grep_verified, medium]`

**contextualPrefix**
- It is populated at ingest (R:6291-6327). The format is `"[<filename without extension, with _ and - replaced by spaces>]"` (R:7534-7545), then `" [<section path joined by ' > '>]"` or `" [<section title>]"`, then a trailing space. The section path and title are included only if `trustedSectionDisplayPath`/`trustedSectionDisplayLabel` accept them: they reject labels containing `_` or `|`, empty labels, and some script-mix cases (R:2984-3010+). `[code_verified, exact]`
- The prefix is embedded as `contextualPrefix + translatedChunkText` (R:6327) and stored separately in `DocumentChunk.contextualPrefix` (R:6484).
  - The streamed large-PDF path uses a different prefix, `"<filename with extension>: "`, with no section (RS:127-131, 149).
  - L1 summary chunks use `"[Summary of <name>]"` (`DocumentSummaryService.swift:171`).

  `[code_verified, exact]`
- The model's doc comment still says the format is `"[From {filename}] [{section}] "` (DC:19-24). A telemetry view parses `"[From filename]"` (`OpenIntelligence/Features/Telemetry/Visualizations/AdaptiveVisualizationsView.swift:2233-2238`). Both are stale. `[grep_verified, high]`
- Table, list and figure chunks *also* carry the context inline in `content` (`Section Path:` and `SOURCE: <file>, page N` lines; DP:5704-5736, 5792-5795, 5818-5836). `[code_verified, exact]`

**Section titles and paths, structureType, chunkType**
- Prose chunks: `sectionTitle` is the nearest preceding detected section (SC:1481), `sectionPath` comes from `buildSectionPath` (SC:1484), and `pageNumber` comes from the page-range map (SC:1487). `[code_verified, exact]`
- `structureType` values:
  - `"paragraph"` / `"table"` / `"list"` / `"figure"` in the structured path (DP:5223, 5295, 5408, 5439)
  - `nil` in the flat path (DP:941)
  - `"streamed_xml"` for streamed XML (DP:629)

  `[code_verified, exact]`
- `chunkType` values:
  - `prose`, or `warning` when "warning/caution/danger/important/notice/precaution" appears in the first 240 characters or the section title (SC:1504, 1531-1537)
  - `tableStructural` / `tableSemantic` / `listItem` in the structured path (DP:5324, 5349, 5377, 5402)

  `[code_verified, exact]`

**Entities, keywords and abbreviations**
- Prose chunk `entities` come from `SemanticChunker.extractEntities` (SC:1554-1600+): NLTagger `.nameType` with `.joinNames`, keeping person, organisation and place names, plus a PascalCase regex capped at 20 matches. `[code_verified, exact]`
- Table and list chunk `entities` come from `element.detectedEntities` (DataDetection from table cells only; DP:5302, 5329, 5354, 5382, 5414). Figure `entities` are the image classification labels (DP:5446). `[code_verified, exact]`
- The document-level "Vision entities" (`lastDetectedEntities`) are gathered from structured elements (DP:5108-5118), counted into `visionEntitiesDetected` (DP:1049), and fed to `ContainerVocabularyService.learnFromDetectedEntities` (R:6634-6643). `[code_verified, exact]`
- Keywords:
  - Prose: lemma counts of nouns, verbs and adjectives; capitalised phrases scored +2; `SpecificationDetector` values scored +3; top 10 kept (SC:1801-1854).
  - Structured: `Array(Set(keywords)).prefix(20)` (DP:6862).
  - Abbreviations: `extractAbbreviations` (SC:1756).

  `[code_verified, exact]`

**Every stored field**
- `DocumentChunk` has 7 fields: `id` (default `UUID()`), `documentId`, `content`, `parentContent`, `contextualPrefix`, `embedding`, `metadata` (DC:12-26, 34-50). `[code_verified, exact]`
- `ChunkMetadata` has 31 fields (DC:115-219; CodingKeys DC:293-325):
  - position and counts: `chunkIndex`, `startPosition`, `endPosition`, `pageNumber`, `wordCount`, `characterCount`, `createdAt` (default `Date()`, DC:239)
  - section and descriptors: `sectionTitle`, `sectionPath`, `keywords`, `semanticDensity`, `hasNumericData`, `hasListStructure`
  - structure: `structureType`, `siblingGroupId`, `siblingCount`, `abstractionLevel`, `bboxArray`, `documentCategory`, `chunkType`
  - extraction: `entities`, `abbreviations`, `tableTitle`
  - image: `imageContentType`, `mediaReferenceId`, `imageCaption`, `imageDescription`, `imageExtractedText`, `imageClassifications`
  - references: `hasCrossReferences`, `resolvedReferences`

  `[code_verified, exact]`
- Fields that are never, or only partially, meaningful:
  - `mediaReferenceId` has no ingestion writer (grep for non-forwarding `mediaReferenceId:` assignments found none). `[grep_verified, medium]`
  - Structured chunks get `startPosition = 0`, `endPosition = text.count` rather than document offsets (DP:5640-5641).
  - Structured paragraph sub-chunks carry offsets into the paragraph buffer, not the document (DP:5213-5214).
  - `RAGService` renumbers `chunkIndex` by position before storage (R:6444-6449).

  `[code_verified, exact]`

### Inferences
- The chunker has no tokenizer-aware sizing. The word limits (target ≤ 260, max 310) are converted to tokens only by comment arithmetic ("≈ 1.3–2.0 tokens/word", SC:139-143). The 430-token guard therefore probably fires often on technical text, where 310 words is 400–620 tokens. When it fires it rewrites text rather than moving a boundary. `[inferred, high]`
- The ±100/±30/±120-character snapping treats window edges as boundaries. Wherever there is no real sentence boundary within that distance (tables, lists, OCR text without punctuation, long sentences), the cut lands at an arbitrary character, which is usually mid-word. This depends on NLTokenizer reporting a token that starts at the substring start. `[inferred, high; not observed at runtime]`
- The self-tuning machinery changes little that actually runs (it only moves `minSize` and topic detection). But it changes the container directive, and so the embedding fingerprint (section 3), on almost every ingest. It is mostly configuration churn. `[inferred, high]`

### Gaps
- How often the 430-token splitter and the hard word limit fire on real libraries is not in code. It would need the logs (`SPLIT OVERSIZED CHUNK`, `HARD LIMIT`) from a device run.
- The exact rules in `detectSections` (SC:873-1080) were only skimmed. False-positive heading rates are unknown.

## 3. How chunks become vectors: model, tokenizer, token limit, truncation, pooling, normalisation, batching, providers and fingerprint

### Takeaway
One model is shipped: all-MiniLM-L6-v2, 384 dimensions. It runs in two runtimes, a Core ML `.mlpackage` and a Core AI `main.mlirb`, both with a 512-token input and attention-masked mean pooling. Only the Core ML provider L2-normalises in Swift and logs truncation.

The text embedded per chunk is `"[file] [section path] " + (possibly translated) chunk text`, truncated to 512 tokens by a character binary search. Each chunk gets exactly one vector. There is no late chunking, no multi-vector, and no image embedding.

Settings and container creation choose Core AI on OS 27, and the Core AI provider has a readiness loop that can spin forever if its tokenizer fails to load. The fingerprint hashes the tokenizer and declared recipe strings, plus the container's current chunking directive, so every self-tuning change looks like a pipeline change.

### Cited Findings
**Model and artefacts**
- Provenance is declared as `sentence-transformers/all-MiniLM-L6-v2`, Apache 2.0 (TPN:3-6). `[doc_claim_only, high]`
- Code declares `dimension = 384` (CML:64-66; CAI:29) and revisions `"MiniLM-L6-v2/coreml-mlpackage"` (CML:74) and `"MiniLM-L6-v2/coreai-mlirb-meanpool"` (CAI:23). The bundled artefacts are `OpenIntelligence/Resources/MLModels/EmbeddingModel.mlpackage` and `EmbeddingModel.bundle/main.mlirb`. `[code_verified, exact; the weights' identity is doc_claim_only]`

**Tokenizer**
- Loaded with `AutoTokenizer.from(directory:)` from the `Tokenizers` module (CAI:9, 55-63; CML:239-247; DP:482-494). TOK is 711,468 bytes: WordPiece, vocabulary 30,522, `BertNormalizer` with lowercase, `truncation.max_length 512` (LongestFirst), and `padding: null`. Both providers hard-code CLS/SEP/PAD ids 101/102/0 (CML:116-118; CAI:38-40). `[code_verified by parsing TOK, exact]`
- `DocumentProcessor` checks at load time that the tokenizer counts rather than pads (1 word vs 180 words). A failure is logged, not fatal (DP:436-479). `[code_verified, exact]`

**Maximum tokens and truncation**
- Both providers use `maxSequenceLength = 512` and `maxSafeTokens = 512` (CML:113, 296; CAI:48, 154). The protocol default of 510 (EP:65-66) is overridden. The comment "510 for CoreML" at R:6305 is stale. `[code_verified, exact]`
- Before embedding, if `countTokens(prefix+text) > 512`, the text is cut by a **character-level binary search** to fit (R:6331-6359; re-embed R:8048-8062). The tail of the chunk is simply not represented in the vector, while `content` is stored in full. `[code_verified, exact]`
- The Core ML provider still hard-truncates ids to 512 and logs an ERROR "TRUNCATION … BUG: Chunk escaped size limits" (CML:508-523). The Core AI provider truncates **silently** (CAI:182-189). `[code_verified, exact]`
- The streamed large-PDF path instead uses `maxTokens = outputDimension == 384 ? 500 : 8000` and, when exceeded, `String(text.prefix(1500))` characters (RS:128-134). `[code_verified, exact]`
- Token counting when no tokenizer is loaded:

  | Component | Fallback |
  |---|---|
  | Core ML provider | `chars/3+2` (CML:283-293) |
  | `DocumentProcessor` | `chars/3+2` (DP:6450-6462) |
  | Core AI provider | returns **0** (CAI:144-152), so the pre-truncation check never fires |

  `[code_verified, exact]`

**Pooling and normalisation**
- Core ML: attention-masked mean over `hiddenState` rows, handling both Float32 and Float16 outputs (the GPU path outputs Float16, CML:364-366), then **L2-normalised** with vDSP (CML:355-423). `[code_verified, exact]`
- Core AI: passes `input_ids` plus a required `attention_mask` (CAI:194-208) and returns the graph output (`embeddings`/`output_0`/`output`/`_0`) **as-is, with no Swift-side normalisation** (CAI:210-233). It declares `poolingRecipe "mean-attention-masked/l2"` (CAI:22). `[code_verified, exact]` Whether the exported graph L2-normalises is `[unknown]`.
- Two comments are stale. `EmbeddingService` (ES:104-112) and the Core ML provider's recipe comment (CML:68-72) still say Core AI "returns `last_hidden_state[:, 0, :]`, the CLS token". The Core AI provider (CAI:19-23, 194-201) and ATLAS §17 (ATLAS:358-366) say the mean-pooling re-export on 2026-08-18 changed that. `[code_verified that the comments conflict, exact]`

**Batching and concurrency**
- With a progress handler, `EmbeddingService.generateEmbeddings` batches 16 at a time; without one, it makes a single `embedBatch` call (ES:255-307). The main ingest and re-embed paths pass a progress handler (R:6384-6401, R:8081-8098). The streamed large-PDF path does not (RS:138). `[code_verified, exact]`
- Core ML `embedBatch`:
  - runs sequentially for 4 or fewer items
  - otherwise uses a sliding `TaskGroup` of `DeviceCapabilityService.embeddingConcurrency`
  - writes results by index, so output order is deterministic (CML:442-496)
  - runs one `[1,512]` inference per text

  `[code_verified, exact]`
- Core AI `embedBatch` is sequential (CAI:240-247). `[code_verified, exact]`
- "Ingestion mode" reloads the Core ML model with `.cpuAndGPU` compute units so Vision can use the Neural Engine (CML:126-170). `[code_verified, high]`
- NaN/Inf/dimension validation runs only in single-text `generateEmbedding` (ES:239-252, 317-341), **not** in the batch path that ingestion uses (ES:255-307). `[code_verified, exact]`

**Providers, defaults and fallback**
- `EmbeddingService.forProvider` (ES:71-214) handles these ids:
  - `coreai_sentence_embedding` (iOS/macOS 27, otherwise Core ML)
  - `coreml_sentence_embedding`
  - `apple_fm_embed`
  - `nl_embedding`
  - anything else falls to Core ML with a warning

  There is no case for `"nl_contextual_embedding"` even though `nativeDimensions` lists it at 512 (ES:79-85, 125-179), so a container set to it would silently get 384-d Core ML vectors. `[code_verified, exact]`
- If the chosen provider is unavailable, `forProvider` falls back to Core ML, then to `NLEmbedding` at 512-d (ES:181-213). `[code_verified, exact]`
- A benchmark-only override comes from the `benchmarkEmbeddingProvider` user default (ES:104-122). `[code_verified, exact]`
- Default provider:
  - `KnowledgeContainer.init` defaults to `coreml_sentence_embedding`, 384 (KC:168-169). `[code_verified, exact]`
  - `SettingsStore` (`OpenIntelligence/Services/Infrastructure/Configuration/SettingsStore.swift:535-544`) and `ContainerService` (`OpenIntelligence/Services/Infrastructure/Integration/ContainerService.swift:309`) assign `"coreai_sentence_embedding"` as the default. `[grep_verified, medium; the surrounding conditions were not read]`
  - ATLAS says settings "automatically recommend and switch to the Core AI provider on supported hardware", and that Core AI "skips in the simulator" (ATLAS:368, 383). `[doc_claim_only]`
- `AppleFMEmbeddingProvider` is a stub: `isAvailable` is always `false`, `embed` throws `.notImplemented`, and it declares a placeholder dimension of 1024 (AFM, whole file). `[code_verified, exact]`
- `NLEmbeddingProvider` averages word vectors (512-d) and falls back to a hash embedding for missing words or low coverage (NLE:17-80, 171-190). `EmbeddingService.createFallbackEmbedding` (the zero vector) is private and never called (ES:382-385; grep). `[code_verified, high]`

**Core AI robustness**
- `awaitReady` loops with 50 ms sleeps while `(!isModelLoaded && !isModelLoadingFailed) || (tokenizer == nil && !isModelLoadingFailed)` (CAI:135-142). If the tokenizer load fails but the model loads, the load error is only logged (CAI:56-62) and `isModelLoadingFailed` stays false, so `embed` never returns. `[code_verified logic, exact; hang inferred, high]`
- The model loads via a symlink at `tmp/EmbeddingModel.aimodel` that is recreated on every init (CAI:84-100). `[code_verified, exact]`

**What text is embedded**
- `textsToEmbed[i] = contextualPrefix + translatedTextsForEmbedding(chunk.text)` (R:6297-6327, 6361). FTS5 stores the untranslated `chunk.content` (R:6605). When a container has a translation target, the lexical index and the vector index therefore see different languages. `[code_verified for the calls; translation behaviour not read → inferred, medium]`

**EmbeddingFingerprint**
- The fingerprint is `SHA-256("1|providerId|dimension|maxSequenceLength|poolingRecipe|modelRevision|chunkerRecipe" + tokenizer.json bytes)`, truncated to 16 hex characters and memoised (EF:27-80). It deliberately excludes the compiled model bytes (EF:84-95). `[code_verified, exact]`
- `chunkerRecipe = "\(directive.strategy)/\(directive.targetWordWindow)"` or `"default"`. The fingerprint is computed in three places (R:4633-4639, R:7047-7053, R:7262-7268). `[code_verified, exact]`
- On a mismatch with a stored fingerprint, the library is flagged in `librariesNeedingIndexRebuild` and the new fingerprint is adopted (R:4642-4658). `[code_verified, exact]`
- The fingerprint does **not** include:
  - the prefix format (and it differs between the main and streamed paths)
  - the translation target
  - overlap, min size, or the 430-token splitter
  - OCR/Vision settings or text normalisation

  `[code_verified by reading EF, exact]`

### Inferences
- The directive is rewritten by the pre-scan before most ingests (R:5907-5937) and by post-ingest self-tuning (R:579-591), and `chunkerRecipe` includes the directive's window. So a library flips its fingerprint whenever the last-ingested document's preview implies a different strategy or window. The rebuild banner fires even though the effective chunking (clamped to 260/50) may not have changed at all. IPD §6 claims chunking shifts are applied "instantly and silently … avoiding … full database rebuilds" (IPD:823), which this contradicts. `[inferred, high]`
- A single library can hold vectors from different recipes without the fingerprint noticing:
  - main-path prefix (`[file] [section]`) versus streamed-path prefix (`file.pdf: `)
  - Core AI (silent truncation, Swift-unnormalised) versus Core ML

  `[inferred, high]`
- Chunks target about 340–400 tokens and are allowed up to 512 tokens including the prefix. That is well above the short sequences MiniLM-L6-v2 is commonly described as trained for. The model card's own limit (it states inputs over 256 word pieces are truncated by default) is **not** in the repository and was not fetched. `[inferred; external claim unverified here]`

### Gaps
- Whether `main.mlirb` normalises its output, and whether Core AI and Core ML vectors are numerically interchangeable, needs a device comparison.
- The conditions under which SettingsStore/ContainerService pick Core AI were not read (SettingsStore.swift ~520-545; ContainerService.swift ~300-315).
- The effect of Float16 GPU inference in ingestion mode versus Float32 on retrieval is unmeasured.

## 4. How chunks and vectors reach storage: call order, transactionality, partial failure, checkpoints, resume, re-ingest and re-embed

### Takeaway
Ingestion writes to three stores in sequence with no transaction and no rollback:
1. FTS5 document and page text, *before* chunking.
2. The vector store.
3. FTS5 chunk rows.

The vector store silently drops any chunk whose vector width differs from its own dimension, while FTS5 keeps every chunk. The streamed large-PDF path commits FTS5 chunk rows *before* flushing vectors to disk.

The repair flow (`reembedDocuments`) can rebuild from vector-store or FTS5 chunk rows only when the recorded chunking config "matches", which it structurally does not for containers without a directive. Otherwise it needs the source file. When the source is missing it marks the document `.complete` ("Skipped"), and the self-healing caller then logs success and takes the banner down.

### Cited Findings
**Main path (`addDocument`) call order**

| Step | Call | Source |
|---|---|---|
| 1 | Inside `processDocument`: `SQLiteFullTextService.store(text:)` stores the whole normalised document and `storePages` stores per-page text, **before** chunking | DP:809-830 |
| 2 | Chunking, token limit, coverage log | DP:852-976 |
| 3 | `generateEmbeddings` | R:6384-6401 |
| 4 | `db.storeBatch(chunks:)`, then `db.persist()`, then the fingerprint is stamped only if the store was empty before this import | R:6506-6526 |
| 5 | Spotlight chunk indexing | R:6530-6553 |
| 6 | `SQLiteFullTextService.storeChunks` (non-throwing; `append: false` deletes the document's existing FTS chunks first) | R:6564-6614; FTS:834-880 |
| 7 | Vocabulary learning per chunk, plus Vision entities | R:6616-6657 |
| 8 | Optional L1 summary via a FoundationModels call with a 12 s timeout, stored with `db.storeBatch([summaryChunk])`; failures swallowed | R:6659-6725; `DocumentSummaryService.swift:42` |
| 9 | `db.persist()` | R:6731-6732 |
| 10 | `documents.append` | R:6885 |
| 11 | `saveDocumentsToDisk()` | R:6908 |

`[code_verified, exact]`
- The `catch` block marks the item `.failed` and rethrows. It deletes **nothing**: no FTS5 text, pages or chunks, and no vectors (R:6965-7018). `[code_verified, exact]`
- `BNNSVectorDatabase.storeBatch` filters with `inputChunks.filter { $0.embedding.count == dimension }` and only logs "Skipped N chunks (dim mismatch)" (BNNS:440-445). It appends without de-duplicating by id (BNNS:450-460). `addDocument` then writes **all** chunks to FTS5 (R:6609-6613) and reports success. `[code_verified, exact]`
- FTS5 `chunks` is an FTS5 virtual table (FTS:242). Its `chunk_id` is the string `"<documentId>_<chunkIndex>"` (FTS:864). The side table `chunk_structured` uses `chunk_id` as primary key with `INSERT OR REPLACE` (FTS:262-263, 1026). `[code_verified, exact]`
- `BNNSVectorDatabase.allChunks()` returns metadata-only copies with `embedding: []` (BNNS:20, 450-458, 695-698), and `RAGService` hydrates vectors explicitly where it needs them (R:4197-4203). `runVectorAudit` counts `chunks.filter { $0.embedding.count != expectedDim }` over `allChunks()` (R:504-507), so on a BNNS store it would report **every** chunk as mismatched. `[code_verified, high]`

**Streamed large-PDF path (PDF over 10 MB; RS:19-269)**
- It works in 15-page batches (RS:70-79). For each batch:
  1. `processDocument(pageRange:)` appends FTS doc and page text (RS:100-106; DP:812-823).
  2. The batch is embedded with the `"file: "` prefix and 1,500-character truncation (RS:125-138).
  3. `db.storeBatch` buffers the vectors in memory (RS:155).
  4. **FTS5 `storeChunks(append: true)` commits** (RS:191-196).
  5. **Then** `db.persist()` flushes vectors (RS:199).
  6. Then the state file is written with `lastCompletedPage` (RS:201-211).

  `[code_verified, exact]`
- Resume reads `ingestion_state.json` from the checkpoint directory and skips completed batches (RS:33-64, 81-85). `[code_verified, exact]`
- The `Document` record is appended only after all batches finish (RS:219-234). It has no `processingMetadata` and no `fileHash` (RS:219-226). `[code_verified, exact]`
- Chunk ids are `UUID()` (RS:143). `chunkIndex` restarts at 0 for each batch, because each `processDocument` call numbers its own chunks (DP:928-930, 5142-5165), and FTS `chunk_id` derives from it. `[code_verified, exact]`
- This path does **no** summary, vocabulary learning, entity learning, Spotlight chunk indexing or fingerprint stamping (full function read, RS:28-269). Checkpoints are cleaned on success (RS:268). `[code_verified, exact]`
- Per-page structured checkpoints (JSON per page) are written during structured parsing (DP:4975-4991). Pages marked `[CHECKPOINT_SKIPPED]` are skipped (DP:4400-4402). The directory is keyed by a document fingerprint (DP:9803-9821). `[code_verified, exact]`

**Re-embed and repair (`reembedDocuments`, R:7763-8256; self-healing R:7292-7394)**
- Eligibility excludes documents with active queue items. If every document is excluded, the call throws `rebuildBlockedByQueue`; if the library is empty, it returns (R:7802-7841). `[code_verified, exact]`
- **Optimised path.** It runs when `chunkingConfigHasNotChanged`:
  - the document's recorded window, overlap and strategy equal the container directive, or `ChunkingDefaults` 350/60/"balanced" when there is no directive; or
  - the document has no recorded values and the reason contains "Self-healing" (R:7939-7953).

  It takes the document's chunks from the vector store, else **reconstructs them from FTS5 rows**. The reconstruction is lossy (R:7955-7991):
  - `keywords []`, `semanticDensity 0.5`, `parentContent nil`, `contextualPrefix nil`
  - no entities, abbreviations, `chunkType`, table or image fields
  - `wordCount` from `split(" ")`
  - ids from `UUID.deterministic("docId_chunkIndex")`

  It then re-embeds with a freshly built prefix (R:8025-8098), calls `db.deleteChunks(forDocument:)`, then `storeBatch`, then `persist` (R:8119-8122; not atomic). `[code_verified, exact]`
- **Full path.** If the source file is missing, the document is marked `.complete` with "Skipped (source file missing)" and the loop `continue`s (R:8135-8150). Otherwise it runs `removeDocument(keepPhysicalFile: true)` then `addDocument(context: .autoRebuild)` (R:8181-8196); if `addDocument` throws, the document has already been removed. `[code_verified, exact]`
- After the loop it emits "Library rebuild complete" regardless of skips (R:8248-8255). The self-healing caller logs "Self-healing rebuild completed successfully" and **removes the rebuild banner** whenever no error was thrown (R:7340-7361). `[code_verified, exact]`

### Inferences
- **Containers without a directive.** Documents record their preset window (240 for PDF and image, 260 for text and office, 180 for code), but the comparison target is `ChunkingDefaults.targetWindow = 350`. So the cheap FTS5-based repair is refused unless the document has no recorded metadata and the run is self-healing. Repair then needs the original file. `[inferred from DP:1053-1055 and R:7939-7953, high]`
- **Streamed path crash.** A kill between the FTS5 commit and `persist` leaves FTS5 chunk rows with no vectors. On resume the same batch is re-processed and appended again, leaving FTS5 with duplicate rows (and duplicate `chunk_id`s) for that batch while vectors hold one copy. `[inferred, medium]`
- A failure midway through the streamed path leaves vectors and FTS rows for earlier batches with no `Document` record until the same file is ingested again. `[inferred, medium]`

### Gaps
- How the BNNS store's `dimension` is set when a container is created or its provider changes was not read. That determines when the dimension filter drops chunks.
- Whether per-page checkpoints from the non-streamed path are ever cleaned (`cleanCheckpoints` is called only from RS:268) was not established.

## 5. Determinism and idempotency

### Takeaway
For a fixed input string and fixed config, the chunker's boundary logic reads as deterministic: page order is re-sorted, boundaries depend only on text and config, and results are written by index. The nondeterminism sits in three places:
- **Upstream**, in what text reaches it: a `Set`-derived subset of Vision custom words, plus path and routing decisions.
- **In which config applies**: the container directive depends on library history.
- **In metadata**: `Set`-ordered keywords and entities, random UUIDs, timestamps, and an optional LLM summary chunk.

Nothing tests re-ingest determinism.

### Cited Findings
**Deterministic by construction**
- Page results are sorted before assembly (DP:3772, 5017). Embedded images are sorted by page (IU:539). `keyValuePairs` is an ordered array (SDP:428-477). Topic boundaries are sorted (SC:1126). Batch embedding results are written by index (CML:461-494). `[code_verified, exact]`

**Source 1: Vision custom words**
- `extractDynamicVocabulary` accumulates candidate terms in a `Set<String>` and returns `Array(vocabulary.prefix(500))` (OCR:224-300). The candidates are acronyms, alphanumeric codes, camelCase words, unit compounds, low-vowel words, and repeated capitalised bigrams from up to 50,000 characters of the first 50 pages' PDFKit text (DP:3390-3401).
- When a document yields more than 500 candidates, *which* 500 (and in what order) depends on Swift's per-process hash seed. The result feeds `RecognizeDocumentsRequest.textRecognitionOptions.customWords` (OCR:303-311; SDP:694).

`[code_verified, exact; the effect on OCR output is inferred, medium]`

**Source 2: metadata ordering and selection**
- Micro-chunk merges use `Array(Set(topKeywords))` and `Array(Set(entities))` (SC:533, 539).
- Structured keywords use `Array(Set(keywords)).prefix(20)` (DP:6862), which is a *selection*, not just an order.
- Keyword ties are ordered by Dictionary order (SC:1851-1853).

`[code_verified, exact]`

**Source 3: identity and time**
- `DocumentChunk.id` defaults to `UUID()` (DC:35) and the streamed path uses `UUID()` (RS:143); only the FTS5 reconstruction uses deterministic ids (R:7981).
- `createdAt = Date()` (DC:239). `ChunkingDirective.updatedAt: Date` (KC:413).

`[code_verified, exact]`

**Source 4: adaptive config and path selection**
- The pre-scan resets the directive from the file's own preview (R:5907-5937). But the preview is read as UTF-8 for every non-PDF type (R:8327-8331), so DOCX/XLSX/PPTX, images and audio get `""` and skip the pre-scan. They are then chunked with **whatever directive the container holds**, meaning the previous file's pre-scan or the post-ingest library-wide self-tuning (R:5770, R:535-591). `[code_verified for the UTF-8 read and the directive fallback, exact; that binary formats decode to "" is inferred, high; order-dependence inferred, high]`
- File size selects the path:
  - over 10 MB, a PDF uses the streamed path with 15-page batches and forced boundaries (R:5939)
  - over 50 MB, XML uses the SAX path (DP:602)

  `[code_verified, exact]`
- macOS versus iOS: the complexity analysis's Vision pass runs only where UIKit exists (PCA:298, 1045-1072). Its signals feed render scale and routing (DP:219-296). The same file can therefore take different page routes on Mac and iPhone. `[code_verified for the gate, exact; effect inferred, high]`

**Source 5: timing**
- The L1 summary chunk exists only if FoundationModels answers within 12 s (R:6674-6725; `DocumentSummaryService.swift:42`). A library's vector-store chunk count per document therefore varies by 0 or 1 between ingests. `[code_verified for the timeout, exact; variance inferred, medium]`
- Resumed structured ingests reuse per-page JSON checkpoints from a previous run (DP:4400-4402, 4975-4991). `[code_verified, exact]`

**Source 6: shared mutable state**
- `DocumentProcessor` keeps per-document state (`lastDetectedEntities`, `currentDocumentCustomWords`, `currentDocumentRecognitionLanguages`) that is reset at the start of each `processDocument` (DP:573-580).
- `RAGService` reads `documentProcessor.lastDetectedEntities` *after* processing (R:6636).
- The code itself notes that two documents can ingest concurrently (DP:4405-4412).

`[code_verified, exact; cross-document leakage inferred, medium]`

**Floating point**
- Ingestion mode moves Core ML embeddings to GPU/Float16, while other paths may produce Float32 (CML:126-170, 364-366). The same text can therefore get slightly different vectors depending on when it was embedded. `[code_verified, high; magnitude unknown]`

**Tests**
- A grep of `OpenIntelligenceTests/Services/Document/Chunking/*.swift` for `determinis|idempot|twice|repeat` finds no determinism test. The one hit (`ChunkingLimitsTests.swift:47`) is unrelated. `[grep_verified, high]`

### Inferences
- Re-ingesting a file is not idempotent at the identity level: new chunk UUIDs, new `createdAt`, and possibly a new directive and fingerprint. Anything keyed on chunk ids, such as citations, caches or Spotlight, sees a different set each time. `[inferred, high]`
- If the owner's "eight ingests, eight counts" involved a scanned or OCR-heavy PDF, the custom-words `Set` subset is the most specific code-level candidate. For DOCX, images or audio, directive inheritance is. For large PDFs, streamed-path batch boundaries. `[inferred, medium]`

### Gaps
- Whether `RecognizeDocumentsRequest` output actually changes with the `customWords` subset or order is an Apple-runtime question.

## 6. Verdicts on the twelve roadmap rows (titles treated as unverified leads)

### Takeaway
The code **confirms the mechanism** for five rows: repair reports success, mid-word boundaries, table-only DataDetection, no late chunking, and the macOS Vision gap. It **partly confirms** the word-count/truncation row and the modality row. It **refutes or narrows** two: a prefix exists, and DataDetection is read for table cells even though VisionKit is indeed absent. It **cannot settle** three: the chunk-count variance, the 452-vector figure, and the embedder benchmark. For those it identifies concrete candidate mechanisms.

### Cited Findings
1. **"The chunker is not deterministic: one file, one hash, eight ingests, eight different chunk counts"** (https://app.notion.com/3d749a74d54f8177b33afb79fa1b25a4). **Cannot settle from code.**
   - The boundary logic in `SemanticChunker` depends only on text and config (SC:325-581, 1225-1364, 1859-1888); `Set` use there touches metadata only (SC:533, 539). `[inferred, medium-high]`
   - Code-verified upstream sources could change the text or config between ingests: the `Set`→`prefix(500)` Vision custom words (OCR:227-299), directive inheritance for non-UTF-8 formats (R:8327-8331, R:5770), streamed versus in-memory path (R:5939), checkpoint reuse (DP:4400-4402), and the optional L1 summary chunk (R:6674-6725). `[code_verified, exact for each mechanism]`
   - No test covers re-ingest determinism (grep, §5).
2. **"452 chunks in one library have no vector, so a quarter of it is keyword-searchable only"** (https://app.notion.com/3d749a74d54f812cb828d19ff84661e9). **Consistent with code; the figure cannot be settled.** Verified ways an FTS5 chunk row can exist without a vector:
   - BNNS silently drops dimension-mismatched chunks while FTS5 stores all (BNNS:442-445; R:6609-6613).
   - The streamed path commits FTS5 before persisting vectors (RS:191-199).
   - The re-embed path is delete-then-store (R:8120-8122).
   - There is no rollback on failure (R:6965-7018).

   `[code_verified mechanisms, exact]` **Measurement caution.** `runVectorAudit`'s dimension check reads `embedding.count` from `allChunks()`, which BNNS strips to `[]` (R:504-507; BNNS:695-698). Any "no vector" count derived that way would count every chunk. How the 452 was measured matters. `[code_verified, high]`
3. **"A library with no vectors cannot repair itself, and the repair reports success"** (https://app.notion.com/3c049a74d54f81fd9255edc739959d36). **"Reports success": confirmed.**
   - Missing-source documents are marked `.complete` "Skipped" and the loop continues (R:8135-8150).
   - The function returns normally with "Library rebuild complete" (R:8248-8255).
   - Self-healing logs success and removes the banner (R:7353-7361).

   `[code_verified, exact]`

   **"Cannot repair itself": conditionally confirmed.** The FTS5-based optimised repair is refused for directive-less containers because recorded preset windows (240/260/180) never equal `ChunkingDefaults` 350 (DP:1053-1055; R:7939-7953), so repair falls to re-ingesting from the source file. A repair that re-embeds at a dimension different from the store's would also have every chunk silently dropped (BNNS:442-445) and still "succeed". `[inferred, high]`
4. **"Chunk boundaries land mid-word and mid-phrase"** (https://app.notion.com/3b149a74d54f81549549d5aa76d92cdb). **Mechanism confirmed in code.**
   - Sentence-snap helpers treat the ±100/±30/±120-character window edges as sentence boundaries (SC:1369-1440, 1330, 1875, 1453-1454).
   - The fallback length estimate uses space-only splitting (SC:1293-1327).
   - The token splitter breaks at every `.`/`!`/`?`/newline, including decimals, and rewrites text with ". " (DP:6603-6648).

   `[code_verified logic, exact; runtime frequency inferred, high]`
5. **"Detected entities come from table cells only, so most documents contribute none"** (https://app.notion.com/3d849a74d54f81509c9af5e93d69754c). **Confirmed for DataDetection entities** (the `DetectedEntity` stream used for vocabulary learning and the `visionEntitiesDetected` count): the only call site is per table cell (SDP:961; SDP:1306-1308), and non-PDF formats never run it. `[grep_verified, high]` **Not true for chunk `entities` in general**: prose chunks get NLTagger person, organisation and place names plus PascalCase terms (SC:1498, 1554-1600). `[code_verified, exact]`
6. **"Contextual retrieval is absent: chunks are embedded with no trace of where they came from"** (https://app.notion.com/3cc49a74d54f81118ff7cfd44ba15314). **Refuted as worded.** Every main-path chunk is embedded with `[filename] [section path]` (R:6291-6327, 7534-7545), and streamed chunks with `file.pdf: ` (RS:127-131). `[code_verified, exact]`

   **Confirmed in the stronger sense.** No LLM-written situating context exists. The section part is dropped whenever the label is not "trusted" (R:2984-3010). In the structured path it is at most one flat page title (DP:5250-5256), and figure chunks carry the *last* section's label (DP:5045-5048). `[code_verified, exact; the share of chunks carrying only a filename is unknown]`
7. **"Late chunking: embed full document, pool per chunk"** (https://app.notion.com/3b349a74d54f81008780d4a0cbe9c158). **Absent (confirmed).** The chunker header disclaims it (SC:18-28), each chunk is a separate `[1,512]` inference (CML:300-440; CAI:156-238), and no long-context embedder is bundled. `[code_verified, exact]`
8. **"Modality-aware indexing for tables and figures"** (https://app.notion.com/3b149a74d54f81478a31e3eb32bfd6db). **Partly present, as text.**
   - Present: table-specific chunk types and renderings (DP:5807-5929), structured table payloads in the FTS side tables `chunk_structured`/`chunk_table_rows` (FTS:262-290; R:6585-6596), and figure description chunks with image metadata (DP:5696-5738, 5434-5454).
   - Absent: separate modality indexes or embedders; image embeddings (no feature-print or image-embedding code under `Services/`, grep); and the Vision figure crop-and-caption path, which is commented out (SDP:872-905).

   `[code_verified/grep_verified, high]`
9. **"Word counts look wrong and ingested text may be truncated"** (https://app.notion.com/3d749a74d54f81aa94a6cb1831c2af20). **Word counts: confirmed inconsistent.** Six definitions coexist:

   | Where | Definition | Source |
   |---|---|---|
   | Document `totalWords` | `split(separator: " ")` (newline-joined words count as one) | DP:746, 1034 |
   | Streamed totals | sum of chunk word counts (overlap and table companions double-counted) | RS:110-112 |
   | Stage ledger | `isWhitespace` split | DP:841 |
   | Chunk metadata | NLTokenizer | SC:91-99; DP:6465-6474 |
   | FTS5 reconstruction | `split(" ")` | R:7975 |
   | Streamed XML | `split(" ")` | DP:627, 660 |

   `[code_verified, exact]`

   **Truncation: confirmed at the vector level.** The tail beyond 512 tokens is not embedded (R:6331-6359; CAI:182-189; RS:132-134, a 1,500-character cut). **Content loss or alteration** paths: garbage-line and header/footer removal (DP:3775, 3783, 5031, 5052), paragraphs of 10 characters or fewer dropped (SDP:852), and splitter rewriting (DP:6603-6648). Coverage checks only log (DP:6722-6817). `[code_verified, exact]`

   Whether content is actually lost on a given document needs a run.
10. **"Vision: DataDetection results are computed and thrown away, and VisionKit is never imported"** (https://app.notion.com/3d849a74d54f81899cf5fdff9d536baa). **DataDetection half: narrowed.** It is now read for **table cells** and used (SDP:961, 1285-1310; R:6634-6643; DP:1049). Detections on paragraphs, lists, titles and fallback text are never read, since there is no other `detectedData` read. `[grep_verified, high]` **VisionKit half: confirmed.** VisionKit is not imported anywhere; only `supportsVisionKit = true` flags exist (R:18829, 18944, 19188). `[grep_verified, high]`
11. **"Page complexity analysis never runs its Vision pass on macOS because the page renderer returns nil there"** (https://app.notion.com/3cb49a74d54f81fbb47cec6d8ed526d8). **Confirmed.** `analyzeBatch` passes no image (PCA:367-371), the renderer returns `nil` without UIKit (PCA:1045-1072), and the Vision pass requires an image (PCA:298). `[code_verified, exact]` That the macOS target lacks UIKit is inferred from DP's AppKit branch (DP:7061). `[inferred, high]`
12. **"Benchmark three embedders and replace MiniLM-L6-v2 if warranted"** (https://app.notion.com/3b149a74d54f81f0a1a0dc9f4d12614a). **Cannot settle from code.** Only one real model ships, in two runtimes (CML/CAI). The Apple FM provider is a stub (AFM). `NLEmbedding` is a word-vector-average fallback (NLE). `NLContextualEmbedding` exists but is unreachable through `forProvider` (ES:125-179). A benchmark override hook exists (ES:104-122). `[code_verified, exact]`

### Inferences
- Several rows are symptoms of one design choice: text-only, one-vector-per-chunk ingestion, with non-transactional multi-store writes and heuristic-heavy extraction. They are not independent bugs. `[inferred, medium]`

### Gaps
- The Notion rows' bodies and evidence were not read (the assignment asked to treat titles as leads). The 452 count and the eight-ingest counts need the owner's data or logs.

## 7. Structural gaps (what this pipeline cannot do by design)

### Takeaway
The pipeline is a word-count text chunker feeding a 384-d, 512-token sentence encoder, one vector per chunk. Structure is serialised to text, context is a filename/heading header, and writes to three stores are non-atomic. The limits below follow from that design, not from individual bugs.

### Cited Findings
- **Chunk size versus embedder**
  - The chunker is word-based (target ≤ 260, maximum 310 words; SC:156-165; DP:875-884) and relies on comment arithmetic of 1.3–2.0 tokens per word (SC:139-143).
  - The real limit is enforced *afterwards*: at 430 tokens (DP:6440) by a text-rewriting splitter (DP:6603-6648), then at 512 by a silent tail cut (R:6331-6359).
  - The prefix budget is fixed at 80 tokens (DP:6437), while the prefix itself (filename plus full section path) is unbounded (R:6313-6323).

  `[code_verified, exact]`
- **One vector per chunk, no cross-chunk context.** There is no late chunking (SC:18-28), no multi-vector, and no hierarchical embedding beyond the optional L1 document summary (R:6674-6712). `[code_verified, exact]`
- **Reading order and hierarchy are lost in structured PDFs.** Elements come out in type order per page (SDP:813-870), section paths are one flat page title (DP:5250-5256), and figures are appended at the end with the wrong section (DP:5045-5048). `[code_verified, exact]`
- **Structure is serialised to text only.** Tables become 2 to N+2 text chunks (DP:5280-5387). Figures become text descriptions. The figure crop-and-caption path is commented out (SDP:872-905). No image embeddings exist (grep). `[code_verified/grep_verified, high]`
- **Format coverage holes.**
  - iWork is not parsed (DP:8839-8845); legacy Office is refused (DP:8832-8835).
  - DOCX headings are not preserved (DP:8975-9075, grep). `[grep_verified, medium]`
  - Audio language comes from the filename (DP:8783-8797).
  - The SpeechAnalyzer path is compile-gated behind a module name absent from the repo (SAS:17-19).

  `[code_verified, exact]`
- **No transactional ingest.** Nothing rolls back on failure (R:6965-7018). Dimension-mismatched vectors are dropped silently (BNNS:442-445). The streamed path commits FTS before vectors (RS:191-199). Repair can report success having done nothing (R:8135-8150, 7353-7361). `[code_verified, exact]`
- **Knobs that do nothing, and a fingerprint that fires on them.** `ChunkingDefaults` 350/60 (R:1576-1579), plan windows 280–420 (AEO:221-271), and strategy `maxSize`/`parentWindowChars` (SC:256-281) are all discarded by the clamp (DP:858-884). Yet `chunkerRecipe` in the fingerprint changes with them (R:4639). `[code_verified, exact]`
- **Two embedding recipes in one library.** The main path and streamed path differ in prefix format (R:6323 versus RS:127) and truncation rule (R:6341-6353 versus RS:132-134); Core AI and Core ML differ in logging and normalisation (CAI:182-233 versus CML:355-423, 508-523). None of this is in the fingerprint (EF:39-47). `[code_verified, exact]`
- **Entity extraction is split and shallow.** DataDetection runs on table cells only (SDP:961). Prose uses NLTagger with three name types plus PascalCase (SC:1554-1600). There is no entity linking or normalisation beyond lowercase de-duplication. `[code_verified, high]`

### Inferences
- A fix confined to an answer-time shortcut cannot correct any of these upstream properties. Every answer path inherits mid-word chunk edges, rewritten numbers in split chunks, duplicated table renderings, mislabelled figure sections, missing vectors and filename-only prefixes, and an extractive path that quotes `content` verbatim is the most exposed to them. `[inferred, high]`

### Gaps
- None beyond those listed in sections 1–5.

## 8. Questions the code cannot settle (need a device run or data)

### Takeaway
These questions need runtime evidence: logs, fixture re-ingests, or an SDK check. Static reading cannot close any of them.

### Cited Findings
- **Chunk-count variance.** Is chunk-count variance real, and where does it enter? Re-ingest one OCR-heavy PDF, one DOCX and one large PDF N times, logging for each run:
  - a hash of the extracted text (after DP:833)
  - the `customWords` list (DP:3400)
  - the active directive (R:5770, 5930)
  - which path ran (R:5939)
  - whether an L1 summary chunk was stored (R:6699)

  `[unknown]`
- **customWords sensitivity.** Does `RecognizeDocumentsRequest` output depend on the subset and order of `customWords` (SDP:694)? `[unknown]`
- **Which speech path runs.** Is `canImport(SpeechAnalyzer)` true with Xcode 27 (SAS:17)? `[unknown]`
- **Core AI numerics.** Does `main.mlirb` L2-normalise, and are Core AI and Core ML vectors equivalent (CAI:210-233 versus CML:414-423)? Does the `awaitReady` hang (CAI:135-142) occur in practice? `[unknown]`
- **Splitter and truncation frequency.** How often do the 430-token splitter (DP:6486-6496) and the embed-time truncation (R:6332-6353) fire on real libraries, and how much text does truncation cut? `[unknown]`
- **Mid-word boundaries in practice.** Does NLTokenizer report a first token starting at a substring's first character, making SC:1410-1440 return window edges? What share of stored chunks start or end mid-word? `[unknown]`
- **Dimension drops.** How often does BNNS drop chunks for a dimension mismatch (look for "Skipped N chunks (dim mismatch)", BNNS:444)? And how was "452 chunks have no vector" measured, given `runVectorAudit`'s stripped-embedding check (R:504-507)? `[unknown]`
- **Duplicated paragraph text.** Does `DocumentObservation.Container.paragraphs` duplicate table or list text? `[unknown]`
- **Section-context coverage.** What share of chunks carry section context in their prefix after `trustedSectionDisplayPath` (R:2984-3010)? `[unknown]`
- **Embedder quality.** How does MiniLM-L6-v2 retrieval quality at 300–512-token inputs compare with alternative embedders on this corpus? This is the roadmap's three-embedder benchmark, and the repo contains no such comparison in code. `[unknown]`

### Inferences
- A small, deterministic re-ingest harness would settle most of the determinism and "no vector" questions directly: same file, N runs, diff extracted text, config, chunk texts and per-store counts. `[inferred, high]`

### Gaps
- No device, simulator or benchmark data was available to this audit. The `BenchmarkRuns/` ledgers were not read.
