# Module 02. File extraction and document understanding

Fifty-two concepts. This is the reading room: getting the words, tables and pictures out of a file, on the device, without trusting the file.

## The ladder

**Like you're five.** Some papers have real words the phone can copy. Some papers are just pictures of words, so the phone has to look at the picture and read it like you do. Some papers have tables, and the phone is careful to keep the rows and columns lined up. Some "papers" are recordings, so the phone listens and writes down what it hears.

**Like an idiot.** Extraction is the step where a PDF, Word file, spreadsheet, photo or audio recording becomes plain text the rest of the app can use. The app picks a different tool per file type. It does not trust a PDF's hidden text layer, because scanned PDFs often have a garbage one; it checks a page first. It reads pages at high resolution when it has to OCR them. It reads tables as tables. And it does all of it on the phone.

**Like less of an idiot.** Extraction is the ceiling on the whole app: a fact that never makes it out of the file cannot be retrieved later by any cleverness. So there is a page-complexity triage that decides per page whether the native text is enough, whether OCR is needed, and whether a structured pass for tables is worth it. OCR goes through Apple's Vision framework with the accurate recogniser, language correction, and a language list narrowed to what was detected. A different Vision request reads document structure. Office files are unzipped and their XML streamed. CSV is parsed properly. Audio is transcribed with on-device speech recognition in ten-minute segments. Garbage-text detection throws out character salad from rotated labels and diagrams.

**Average Joe.** The reason so much machinery exists here is that the cheap path lies. A PDF that "has text" might have text from a broken OCR someone ran years ago. A two-column paper read straight across produces sentences that never existed. A number without its column header is worthless. So each of those failure modes has a specific counter: text-layer validation, column detection and reading-order reconstruction, table row records with their headers attached.

**Dot-connector.** Two Vision requests, two jobs. `VNRecognizeTextRequest` is line-oriented OCR: strings, confidence, bounding boxes. `RecognizeDocumentsRequest` is structure: paragraphs, lists, tables with rows and columns. The word bank blurs them in places; keep them separate. Rendering a page to a bitmap is cheap CPU work (12 to 16 ms a page at 360 DPI on a real trace); recognition is where the hours go, and the app throttles Vision with a semaphore sized to the device because unbounded Vision plus Metal races and exhausts command buffers. And the thing about "zero-copy": what is skipped is the PNG round trip; a full-page bitmap is still allocated.

**Expert.** PDF text-layer validation: pick the page with the most native text (at least 50 characters), render, quick OCR, compare; garbled means every page goes to OCR. Complexity triage renders at 144 DPI and looks for grid lines and figures; classes are trivial, simple, moderate, complex, visual, scanned. OCR render is `renderPDFPageAsImage(page:scale: 5.0)`, 360 DPI, `UIGraphicsImageRenderer` opaque on iOS and a `CGBitmapContext` on macOS. OCR request: `.accurate`, `usesLanguageCorrection = true`, `recognitionLanguages` narrowed by `LanguageDetectionService`, custom words from the dynamic document vocabulary plus universal custom words. Structure pass at 180 DPI downscaled, or 360 for high-risk pages. Vision concurrency 2 to 64 by device tier with a short cooldown. Audio: `AudioTranscriptionService`, `SFSpeechRecognizer`, `requiresOnDeviceRecognition = true`, segments of at most 600 s. 500 MB cap for non-streamable files.

**Expert's expert.** The macOS render path used to go through `NSImage.lockFocus`, which produced images four times larger than requested, 370 MB per page; replaced by a bitmap context in late August. The OCR language narrowing landed 2026-08-29 because thirteen recognisers including four CJK models were loading on every request. And the `SpeechAnalyzer` branch in `SpeechAnalyzerService` never compiles: it is guarded by `#if canImport(SpeechAnalyzer)`, a module that does not exist in the SDK (the API lives in `Speech.framework`), and it calls `results(for:)` on an actor that declares `analyzeSequence(from:)` instead. Every build takes the legacy `SFSpeechRecognizer` path. Filed to Future Backlog 2026-09-02. Anything that says audio goes through SpeechAnalyzer is wrong.

## Every concept

### Adaptive preprocessing (Conditional, verified in `OCRConfiguration`)
- **Idiot:** touching up the photo before reading it: contrast, sharpen, straighten.
- **Dot-connector:** one filter cannot fix both a faint receipt and a crisp diagram, so preprocessing is chosen per page and clean pages are left alone.
- **Expert:** after rasterisation, before the OCR pass, with quality scoring selecting or escalating candidates.

### Audio transcription (Conditional, verified)
- **Idiot:** the phone listens to the recording and types it out.
- **Dot-connector:** a recording has no words to index until it is transcribed; the transcript then goes through normal chunking with timestamps kept.
- **Expert:** `AudioTranscriptionService` on `SFSpeechRecognizer`, on-device required, segmented at 600 s. Not `SpeechAnalyzer`; see the ladder.

### Barcode detection (Conditional, verified)
- **Idiot:** reads the barcode instead of squinting at the digits.
- **Dot-connector:** a barcode carries the most exact identifier on the page; OCR would only approximate it.
- **Expert:** `CaptureToRAGBridge` during live camera analysis; the payload can be written into the capture before ingestion.

### Camera-to-RAG bridge (Conditional, verified)
- **Idiot:** point the camera at a page and it becomes a document.
- **Dot-connector:** captures are turned into a temporary Markdown document and sent through the exact same ingestion pipeline, so they get the same identity, chunking, embedding and verification.
- **Expert:** an actor in `Features/Camera/CaptureToRAGBridge.swift`, runs after recognition and before enqueue.

### Column detection (Conditional, verified in `LayoutAwareExtractor`)
- **Idiot:** figures out that the page has two columns so it doesn't read across them.
- **Dot-connector:** histogram and gap clustering of text-block x-coordinates. Reading a two-column paper straight across produces nonsense passages and nonsense citations.
- **Expert:** after blocks are extracted, before per-column top-to-bottom ordering.

### Compact cell anchor (Conditional, verified in `StructuredDocumentParser`)
- **Idiot:** a tiny label on a cell saying which row and column it's from.
- **Dot-connector:** for small tables it improves exact lookup without repeating every cell and blowing the chunk budget.
- **Expert:** generated after row records, before the canonical Markdown table representation.

### CoreMLDocumentClassifier (Conditional, verified)
- **Idiot:** guesses what kind of document this is.
- **Dot-connector:** a local classifier that can steer extraction and chunking without sending content anywhere.
- **Expert:** loads with `computeUnits = .cpuAndNeuralEngine`; runs during analysis before the ingestion plan is resolved.

### CoreMLRegionDetector (Conditional, verified)
- **Idiot:** finds the boxes on the page: this is a table, that's a figure.
- **Dot-connector:** routing visually complex regions to the right extractor.
- **Expert:** `computeUnits = .all`; after rendering, before structured region processing, when enabled.

### Detected data entity (Conditional, verified)
- **Idiot:** the app notices "that's an email address," "that's a dollar amount."
- **Dot-connector:** typed data become searchable anchors and remove ambiguity during extraction.
- **Expert:** emails, phones, URLs, addresses, dates, money, measurements from visual analysis, attached to page or table structure before chunking.

### Dynamic document vocabulary (Conditional, verified in `OCRConfiguration`)
- **Idiot:** the document teaches the OCR its own weird words first.
- **Dot-connector:** acronyms, codes, CamelCase, compounds and repeated name pairs pulled from the rough native text and handed to Vision as expected words, so OCR stops misreading them. No hardcoded medical or legal lists.
- **Expert:** derived before OCR, merged with universal custom words into `customWords`.

### Embedding translation (Conditional, verified in `TranslationService`)
- **Idiot:** translate a copy for the search map, keep the original for showing you.
- **Dot-connector:** a monolingual embedder retrieves cross-language content badly; translating only the embedding input fixes that without rewriting the source you'll be quoted.
- **Expert:** immediately before embedding for affected documents or summaries.

### Escalating DPI (Conditional, verified)
- **Idiot:** try a normal zoom, zoom in more if the text is tiny.
- **Dot-connector:** max DPI everywhere wastes memory and heat; never escalating loses footnotes and labels. Page analysis and OCR confidence decide.
- **Expert:** the structure pass is 180 DPI downscaled or 360 for high-risk pages; the OCR pass is 360 by default.

### Garbage-text detection (Conditional, verified)
- **Idiot:** throws away "text" that's actually noise from a diagram.
- **Dot-connector:** rotated labels and diagrams produce fluent-looking salad; letting it in poisons chunks, vocabulary and embeddings.
- **Expert:** rules for mixed scripts, improbable consonant runs and suspicious non-ASCII, respecting detected language; after OCR, before text enters the corpus.

### ImageUnderstandingService (Conditional, verified)
- **Idiot:** looks at pictures in the document and says what's in them.
- **Dot-connector:** diagrams carry evidence OCR can't see.
- **Expert:** runs on selected visual regions after page analysis; descriptions attached to chunks.

### Language detection (Conditional, verified) and LanguageDetectionService (Conditional, verified)
- **Idiot:** figures out what language the document is in.
- **Dot-connector:** language drives OCR garbage rules, translation, tokenizer expectations, and, since 2026-08-29, which Vision recognisers load.
- **Expert:** NaturalLanguage-based; runs once enough text exists; feeds `recognitionLanguages` on the OCR request.

### Layout-aware extraction (Conditional, verified)
- **Idiot:** reads the page the way a human's eyes move, not the way the file happens to store it.
- **Dot-connector:** PDF text is stored by coordinates; multi-column pages interleave lines if you trust file order.
- **Expert:** `LayoutAwareExtractor`, after native or Vision block extraction, before page text assembly.

### Live camera analysis (Conditional, verified)
- **Idiot:** the camera preview already sees text, edges and barcodes before you snap.
- **Dot-connector:** guidance and structured observations before commit; it does not create a document by itself.
- **Expert:** `CameraManager` plus the bridge; text, boundaries, barcodes, scenes, animals, faces, humans.

### OCR (Conditional, verified)
- **Idiot:** turning a picture of words into words.
- **Dot-connector:** required before any indexing of a scan or photo; it follows render and preprocessing and precedes structure recovery and chunking.
- **Expert:** `VNRecognizeTextRequest` configured by `OCRConfiguration`; see the ladder for the exact settings.

### OCR confidence (Core, verified)
- **Idiot:** how sure the reader is about each line.
- **Dot-connector:** used to reject weak blocks, trigger rescans, and report quality instead of pretending every character is exact.
- **Expert:** per-observation confidence from Vision and per-segment from speech; consumed before normalisation and indexing.

### OCRConfiguration (Core, verified)
- **Idiot:** the one place that sets up how reading works.
- **Dot-connector:** independently configured Vision requests drift; one authority keeps ingestion and camera recognition aligned.
- **Expert:** revision, accuracy, language correction, languages, minimum text height, custom words, normalisation and garbage filtering, applied before execution and after results.

### On-device speech requirement (Core, verified)
- **Idiot:** the recording never leaves the phone to be transcribed.
- **Dot-connector:** the local-first promise applied to audio.
- **Expert:** `requiresOnDeviceRecognition = true` on every request.

### OOXML / Office parsing (Conditional, verified) and Structured Office parser (Core, verified) and StreamingXMLProcessor (Conditional, verified)
- **Idiot:** Word and PowerPoint files are zip files full of XML; the app opens them and reads the XML directly instead of taking screenshots.
- **Dot-connector:** native structure is preserved and no page is rasterised; the XML is streamed so a huge deck doesn't spike memory.
- **Expert:** selected by file type in `DocumentProcessor`; `StreamingXMLProcessor` is the bounded-memory parser.

### Page complexity class (Core, verified) and PageComplexityAnalyzer (Core, verified)
- **Idiot:** a label for how hard each page is to read.
- **Dot-connector:** trivial, simple, moderate, complex, visual, scanned. The label decides native text versus OCR versus full visual handling, so easy pages stay cheap and hard pages get the expensive path.
- **Expert:** `PageComplexityAnalyzer` combines native structure, text coverage, layout, numeric density, tables, figures, forms, columns, annotations and selective Vision signals; triage render at 144 DPI.

### Page rendering (Conditional, verified)
- **Idiot:** turning a page into a picture so it can be read as one.
- **Dot-connector:** only when analysis or OCR needs it; 360 DPI; cheap compared with recognition.
- **Expert:** `renderPDFPageAsImage(page:scale: 5.0)`; platform-specific renderer; macOS was 4× oversize until the bitmap-context fix.

### Page sentinel (Core, verified)
- **Idiot:** a marker between pages in the combined text.
- **Dot-connector:** without it, chunks and citations could cross pages without knowing where the evidence came from.
- **Expert:** inserted during extraction, interpreted when building page-aware chunks and offsets.

### PDF text layer (Core, verified) and PDFKit extraction (Core, verified)
- **Idiot:** copying the words a real PDF already contains.
- **Dot-connector:** faster and more accurate than OCR when it's trustworthy, and it preserves exact characters for offsets and citations. It also seeds the OCR vocabulary.
- **Expert:** `PDFPage` strings, selections, bounds and annotations via `LayoutAwareExtractor`; attempted first unless validation says the layer is absent or garbage.

### Reading-order reconstruction (Conditional, verified)
- **Idiot:** putting the pieces in the order a person would read them.
- **Dot-connector:** correct words in the wrong order are still a corrupted corpus.
- **Expert:** the final layout step in `LayoutAwareExtractor` before page text enters processing.

### Recognition-language set (Core, verified)
- **Idiot:** the list of languages the reader is allowed to expect.
- **Dot-connector:** English-only corrupts multilingual documents; unconstrained guessing degrades recognition; since 2026-08-29 the set is narrowed to what was detected.
- **Expert:** `recognitionLanguages` on the request, set by `OCRConfiguration`.

### RecognizeDocumentsRequest (Conditional, verified)
- **Idiot:** the reader that understands tables and lists, not just lines.
- **Dot-connector:** returns paragraphs, lists and tables as structure so rows and columns survive. This is not the OCR request.
- **Expert:** used in `StructuredDocumentParser` on pages the triage selects; 180 DPI downscaled or 360 for high-risk pages.

### RFC 4180 CSV parsing (Core, verified)
- **Idiot:** reads spreadsheets-as-text correctly, quotes and commas and all.
- **Dot-connector:** splitting on commas corrupts cells that contain commas. The standard exists for a reason.
- **Expert:** in `DocumentProcessor` CSV extraction before rows are indexed.

### Segmented transcription (Conditional, verified) and Transcription segment (Conditional, verified)
- **Idiot:** long recordings are cut into slices, each transcribed, timestamps stitched back.
- **Dot-connector:** one recognition task has a practical duration limit; slices also isolate retries.
- **Expert:** 600 s maximum per segment; each segment yields spans with start, end and confidence, offset back into the full recording.

### SpatialDocumentAnalyzer (Conditional, verified) and Spatial document analysis (Conditional, verified)
- **Idiot:** notices where things sit on the page, because position is meaning in forms and diagrams.
- **Dot-connector:** connects captions, figures and table context with surrounding text before it's too late.
- **Expert:** consumes extracted blocks before metadata and chunk construction.

### StructuredElement (Conditional, verified), TableData (Conditional, verified), Table row record (Conditional, verified), Table schema view (Conditional, verified)
- **Idiot:** the app keeps tables as tables: headers, rows, and a one-line list of the column names.
- **Dot-connector:** a row record like "Row 2: Model=1688; Reference=1688-020-122" makes a row independently retrievable; the schema view gives BM25 the column names as high-signal anchors; typed elements let the chunker keep tables atomic and boost headings.
- **Expert:** `StructuredDocumentParser` emits them; rows go to `chunk_table_rows`, elements to `chunk_structured`.

### TextBlock (Conditional, verified)
- **Idiot:** a piece of recognised text plus where it was on the page.
- **Dot-connector:** position has to survive long enough to rebuild columns, lines and tables.
- **Expert:** normalised bounding box, confidence, page number; produced by PDFKit or Vision, consumed by layout clustering.

### TranslationService (Conditional, verified)
- **Idiot:** translates when a library asks for it, but never replaces the original.
- **Dot-connector:** cross-language embedding consistency without changing the quoted evidence.
- **Expert:** after language detection, before the optional translated-embedding path.

### Type-specific extractor (Core, verified)
- **Idiot:** the right tool for the file type.
- **Dot-connector:** forcing everything through OCR loses structure and wastes rasterisation; PDF, Office XML, CSV, audio and images each keep different structure.
- **Expert:** selected right after load in `DocumentProcessor`.

### Universal custom words (Support, verified)
- **Idiot:** a list of short technical tokens the reader should expect: mg/dL, N·m, ISO.
- **Dot-connector:** Vision keeps such tokens when told to expect them.
- **Expert:** merged with the dynamic vocabulary into the OCR request.

### VisionOCRThrottle (Core, verified)
- **Idiot:** don't run too many readers at once.
- **Dot-connector:** Vision and Metal race, exhaust command buffers and destabilise memory when launched without bounds.
- **Expert:** an actor-based semaphore sized by `DeviceCapabilityService` (2 to 64 by tier) with a cooldown between operations.

### Visual evidence source (Conditional, verified) and VisualCaptioningService (Conditional, verified)
- **Idiot:** a picture can be evidence too, and the app says which picture.
- **Dot-connector:** captions bridge images into text retrieval; the provenance object keeps the caption tied to the real region so it can't pass as prose.
- **Expert:** `VisualEvidenceSource` in the response model and `VisualEvidenceCard` in the UI; captioning after image understanding, before embedding.

### VNRecognizeTextRequest (Conditional, verified)
- **Idiot:** the line reader.
- **Dot-connector:** strings, confidence and boxes for OCR blocks, live camera frames and layout extraction. This is the OCR request.
- **Expert:** `.accurate`, language correction on, narrowed languages, custom words, minimum text height from `OCRConfiguration`.

### YOLODetectionService (Conditional, verified)
- **Idiot:** spots objects in pictures.
- **Dot-connector:** labels and bounds enrich text-poor pages and captures; it does not replace text retrieval.
- **Expert:** Core ML with `computeUnits = .all`; contributes visual metadata during image understanding.

### Zero-copy image path (Core, verified with a caveat)
- **Idiot:** don't save the page as a PNG and reload it just to read it.
- **Dot-connector:** the round trip is what's skipped; the page bitmap itself is still allocated. Peak memory is lower, not zero.
- **Expert:** `CIImage` to `CGImage` handoff inside the render-to-Vision path in `DocumentProcessor`.
