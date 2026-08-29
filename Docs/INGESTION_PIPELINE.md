# Ingestion Pipeline — source-verified at v4.6, shipped tree is v5.0

> **Documentation status:** Source-verified on 2026-07-15 against v4.6. **Not re-verified since.** iOS/macOS 4.9 is the shipped version. PCC Dynamic Routing does not change ingestion; indexed content remains local until a later query explicitly selects and consents to a minimized PCC synthesis envelope.
> **Known drift as of 2026-08-05** — in `CHANGELOG.md` under 4.9 but not yet described below: all five workspace metadata writes are now atomic read-modify-writes through `coordinatedMergeData(at:transform:)`, closing the race where an ingestion completing mid-sync-pass left a fully intact document on disk with no metadata row pointing at it. `WorkspaceSyncService` also no longer deletes an index for a library that still has documents.
> **Source of truth:** Codebase audit in `Docs/AUDIT/`, plus `CHANGELOG.md` 4.8–4.9 for ingestion and sync.
> **Scope:** Describes shipped behavior unless explicitly labeled experimental, developer-only, or scaffolded.

This document describes the design and implementation of the import-time document ingestion pipeline, as audited at v4.6.

---

## 1. Overview
The ingestion pipeline converts raw files (PDFs, images, text documents) into searchable text segments with semantic metadata, storing them in parallel lexical and vector indexes. 

```mermaid
flowchart TD
    QLOAD[Load coordinated ingestion queue] --> QMERGE[Merge deletion-wins tombstones]
    QMERGE --> QDECIDE{Interrupted work remains?}
    QDECIDE -- Continue --> A
    QDECIDE -- Stop or Discard --> QTOMB[Persist tombstone and suppress automatic repair]
    EMPTY[Metadata exists but vector index is empty] --> SINGLE[Sequential single-flight repair queue]
    SINGLE --> SUPPRESSED{Library repair suppressed?}
    SUPPRESSED -- Yes --> WAIT[Wait for explicit import or manual rebuild]
    SUPPRESSED -- No --> A
    A[Import File] --> B{File Type}
    B -- PDF Size < 10MB --> C{Native Text Layer?}
    B -- PDF Size >= 10MB --> STREAM[Batched Streaming Ingestion]
    C -- Yes --> D[PDFKit Extraction]
    C -- No --> E[Vision OCR Fallback]
    B -- Text/Markdown --> F[Direct Text Read]
    B -- Image --> IMG[Structured parse, then OCR + classification]
    B -- CSV --> CSVL[RFC 4180 parse to pipe rows]
    B -- Office XML --> OFF[ZIP + XML: docx/xlsx/pptx]
    B -- iWork --> IWORK[Always throws; see 2.6]
    B -- Audio/Video --> AV[SpeechAnalyzer transcription]
    D --> G[Normalizer & OCR Repair]
    E --> G
    F --> G
    IMG --> G
    CSVL --> G
    OFF --> G
    AV --> G
    G --> H[Semantic / Structure-aware Chunking]
    H --> I[Token Boundary Enforcer]
    I --> J[SQLite FTS5 Storage]
    I --> K[Core ML Embedding Generation]
    PROFILE[GPU Execution Profile] --> E
    PROFILE --> K
    K --> L[BNNS Vector Storage]
    J --> LOCAL[Local Search Index Boundary]
    L --> LOCAL
    
    STREAM --> STATE[Load ingestion_state.json & stable doc ID]
    STATE --> S1[Process Batch of 15 Pages]
    S1 --> SKIP{Already completed?}
    SKIP -- Yes --> NEXT_BATCH{More Pages?}
    SKIP -- No --> S2[Extract Chunks]
    S2 --> S3[Vectorize Batch]
    PROFILE --> S3
    S3 --> S4[Store Batch to FTS5 & Vector DB]
    S4 --> S5[Call db.persist & Update ingestion_state.json]
    S5 --> NEXT_BATCH
    NEXT_BATCH -- Yes --> S1
    NEXT_BATCH -- No --> S6[Finalize Document Metadata & Await saveToDisk]
    S6 --> S7[Pre-generate Suggested Questions]
    S7 --> S8[Clean Checkpoints]
```

---

## 1.5 Import entry points *(added 2026-08-27)*

Everything above starts at `A[Import File]`. Three surfaces reach it, and all three stage files the
same way.

| Surface | Platform | Mechanism |
|---|---|---|
| Library "Add Documents" | iOS | `UIDocumentPickerViewController` with `asCopy: true`, in a sheet |
| Library "Add Documents" | macOS | `MacDocumentImportPanel` — `NSOpenPanel.beginSheetModal(for:)`, no sheet |
| Finder drag-and-drop onto the library | macOS, iPadOS | `.dropDestination(for: URL.self)` on the library area |

**All three copy into the app-managed workspace before ingesting**, through
`ImportedFileStaging.copyIntoWorkspace` in
[DocumentPicker.swift](../OpenIntelligence/Features/Documents/Components/DocumentPicker.swift).
Importing by reference was rejected: a library pointing at files outside the workspace neither syncs
across devices nor survives the original being moved. That function is also where the
modification-date touch happens, which is what keeps `WorkspaceSyncService`'s 15-minute sweep from
treating a just-imported file as stale — the behaviour §5 and the canonical source of truth both
describe. A per-file failure is logged and skipped rather than aborting the batch.
`[evidence_level: code_verified, confidence: exact]`

**macOS never uses `NSOpenPanel.runModal()`.** `runModal()` starts a nested modal loop, and AppKit
refuses to start one from inside a CATransaction commit, which is exactly where SwiftUI runs
`onAppear`. Until 2026-08-27 all three macOS pickers did precisely that, so the panel was discarded
before it appeared: a capture that day recorded three `Suppressing invocation of -[NSApplication
runModalForWindow:]` warnings, an `_NSDetectedLayoutRecursion`, and 2,064 lines of `CUICatalog`
window-chrome relayout from the orphaned sheet. `beginSheetModal(for:)` is asynchronous and has no
such restriction. `[evidence_level: device_log_proven, confidence: exact, evidence_source: macOS capture 2026-08-27]`

**Drops are filtered before staging.** Directories are excluded, because the pipeline has no concept
of a folder document and `copyItem` would copy one wholesale. Quota is checked before any copy, so a
drop that would exceed the document limit raises the paywall instead of half-importing.
`[evidence_level: code_verified, confidence: exact]`

---

## 2. Text Extraction Lanes

### PDF Ingestion
- **Standard Lane:** Uses PDFKit to extract the native text layer if available. [StructuredDocumentParser.swift](../OpenIntelligence/Services/Document/Processing/StructuredDocumentParser.swift) is used to resolve structures like tables, lists, and headings.
- **OCR Fallback Lane:** If the native text layer is missing or malformed, the pipeline invokes [LayoutAwareExtractor.swift](../OpenIntelligence/Services/Document/Processing/LayoutAwareExtractor.swift) to render pages as images and run local Apple Vision OCR, restoring page layout anchors.

### Image Ingestion *(corrected 2026-08-08)*
- Standalone images (png/jpg/jpeg/heic/tiff/gif) run through `StructuredDocumentParser.parsePageImage` first, the same `RecognizeDocumentsRequest` path PDFs use, and its output is prepended to the classification and AI description from `ImageUnderstandingService`. A failure falls back to the previous behaviour, so this adds structure and never removes it.
- **Until 2026-08-08 this path never saw the structured parser.** It used `VNRecognizeTextRequest`, which returns text lines in reading order and cannot express that a value belongs to a row and a column, so the same table gave cell structure inside a PDF and flat lines when photographed. `[evidence_level: code_verified, confidence: exact]`

### Camera Capture *(corrected 2026-08-08)*
- Document captures run `RecognizeDocumentsRequest` and prefer its structured output. Non-document captures skip it, since a photo of a pet or a landscape has no document structure to find. Failure or an empty parse leaves the flat OCR text untouched.
- **This path carried both defects.** `CameraManager.analyzeCapture` sorted its OCR observations into reading order and then joined them with a space, discarding every boundary that sort had just established, and it never reached the structured parser at all. Photographing a spec sheet produced flat text while importing the same page as a PDF produced cell structure. `[evidence_level: code_verified, confidence: exact]`

**API currency, verified 2026-08-08.** `RecognizeDocumentsRequest` is Apple's current document-understanding API, introduced at WWDC25 for iOS 26; it parses tables and groups cells into rows automatically. Nothing supersedes it. `VNRecognizeTextRequest` is retained deliberately as the fallback for images where no document is detected, and its continued presence in these files is correct rather than debt. Sources: [WWDC25 session 272](https://developer.apple.com/videos/play/wwdc2025/272/), [RecognizeDocumentsRequest](https://developer.apple.com/documentation/vision/recognizedocumentsrequest), [Recognizing tables within a document](https://developer.apple.com/documentation/Vision/recognize-tables-within-a-document).

### Text & Markdown Ingestion
- Text files, markdown notes, and source code are ingested directly. Markdown structures (headers, code blocks) are parsed to preserve hierarchical section paths.

---

## 2.5 Failure modes fixed on 2026-08-08

Four defects that produced *silent* degradation, meaning ingestion reported success while the content was already damaged. Recorded because each was invisible to the benchmark and each was found by reading code rather than by a failing test.

| Defect | Effect | Fix |
|---|---|---|
| OCR lines joined with a space, twice | Every ingested image became **one unbroken line**. Line items, dates and amounts concatenated into a single sentence; the chunker saw one paragraph and the embedding averaged the page. | Both joins preserve line breaks. |
| `effectiveContent` chose instead of merging | A low-quality page that captured **one table** kept the table and discarded the recovered prose the parser had already re-OCR'd. A scanned datasheet could ship with four fifths of the page absent from chunks, FTS5 and the vector index. | Keeps structured elements *and* appends recovered text, deduplicated. |
| `usedStructuredParsing` counted tables and lists only | A PDF with figures but **no tables** discarded every structured element, including embedded-image analysis produced at Neural Engine cost moments earlier. | Flag reflects whether structured extraction produced anything. |
| Camera captures never reached the structured parser | Photographing a document gave flat reading-order text while importing the same page as a PDF gave table cells. Same content, opposite quality. | Document captures run `RecognizeDocumentsRequest` and prefer its output. |

**Coverage, corrected 2026-08-09.** All four are now exercised by automated tests in `OpenIntelligenceTests/Services/Document/Processing/`. See §2.6.

The warning this section used to carry is worth keeping in its original terms, because it is the reason §2.6 exists: the evaluation corpus was 25 markdown files against 20 advertised formats, so none of the above was exercised by any automated run. A table-chunking change on 2026-08-08 destroyed 70% of retrieved table text while the benchmark reported an unchanged 16/20; it was caught only by a human noticing character counts in the running app. `[evidence_level: measured, confidence: exact, evidence_source: BenchmarkRuns/20260808-retrieval-stages]`

## 2.5.1 Two further defects, found 2026-08-09 by the fixtures in §2.6

Both were found on the **first execution** of the new fixture set, and neither was reachable by any test that existed before it.

| Defect | Effect | Fix |
|---|---|---|
| Word table text was extracted and then discarded | `extractTextFromWordXML` lifts each `<w:tbl>` out, leaves a bare `[[TABLE_n]]` marker in its place, and re-inserts the table text at that marker afterwards. But the intervening step builds its output **only** from `<w:p>...</w:p>` matches, and in OOXML a `<w:tbl>` is a *sibling* of `<w:p>`, never nested inside one. The marker therefore sat outside every paragraph match, never entered the result, and the re-insertion had nothing to replace. **Every table in every `.docx` was parsed into rows and dropped**, while the surrounding prose came through — so extraction looked like it worked. | Marker is wrapped in a `<w:p>` so it lands in the stream that step reads. Marker numbering also moved from append order to document order in the same change, but that is readability rather than a second defect: tables are replaced back-to-front, so append order labelled the last table 0 *and* stored its text at index 0. The pairing was reversed and self-consistent, and would have resolved correctly once substitution began working. Document order is worth having because the marker number now matches the table's position on the page when this is debugged from a log. |
| A fully scanned PDF reported zero OCR pages | The primary structured path hardcoded `usedOCR: false`. It renders and recognises a page image whether or not the PDF carries a text layer, so "Vision ran" is not the signal — "there was no usable native text" is. A scan that `RecognizeDocumentsRequest` read cleanly reported **0** OCR pages while one that fell through to the rescue path reported 1, which is backwards from what "OCR: N pages scanned" tells the user in Document Details. | `usedOCR` is now `isGarbled \|\| bestAvailableText.isEmpty`. |

`[evidence_level: code_verified+test_verified, confidence: exact, evidence_source: DocumentProcessor.swift extractTextFromWordXML and the structured PageParseResult, IngestionFormatCoverageTests 12/12]`

## 2.6 Format coverage, added 2026-08-09

`StructuredPageContentTests` pins the `effectiveContent` merge with no fixture and no Vision call, so that defect has a deterministic guard independent of OCR behaviour.

`IngestionFormatCoverageTests` drives real files through `processDocument` for a text-layer PDF, an image-only (scanned) PDF, a figures-only PDF, a partially legible scan, a PNG of a table, CSV, `.docx` and `.xlsx`. It asserts on **extraction**, not on answers:

- each table row returns with its label and its value on **one line**;
- a multi-line page does not collapse to one line;
- character yield holds against the characters the fixture draws, with a per-lane floor;
- the lane under test is the lane that actually ran;
- the chunk inventory has not changed shape, including that chunking did not lose what extraction already recovered.

That last group is the point. An answer score cannot see any of it: the 2026-08-08 regression held at 16/20 while destroying 70% of retrieved table text.

**Fixtures are synthesised in Swift at test time rather than committed.** Expectations and bytes derive from one `TableSpec`, so there is no hand-transcribed ground truth to drift; no binary enters an iCloud-synced repository; and the test target's file membership does not change, so hard-boundary `project.pbxproj` stays untouched. `.docx` and `.xlsx` are built by a store-only ZIP writer, which works because the reader in `DocumentProcessor` accepts `compressionMethod == 0`. Reasoning and consequences in `Docs/ai/DECISIONS.md`.

**What this does not cover, stated plainly.** A page rasterised from vector text is cleaner than anything a scanner produces, so these fixtures catch *structural* regressions and **not OCR accuracy loss on noisy input**. That is an acceptable trade because all six defects above were structural, but a real scanned corpus is still worth acquiring and this set does not replace it.

### iWork extraction does not work for any document current iWork produces

Not a regression; it has never worked, and the reason is structural rather than a parsing bug. `extractTextFromIWorkDocument`:

1. inspects **directories only**, so a single-file `.pages` — what Pages on iOS always writes — never reaches a content read at all;
2. for the package form, looks for members with extension `xml` or `txt`, while modern iWork stores content as compressed protobuf in `Index/*.iwa`.

Both paths end at `throw DocumentProcessingError.iWorkExtractionFailed`. That is the acceptable half of the answer: it fails loudly, so nothing is indexed as a silent empty. Two tests pin both shapes so that cannot quietly change. `[evidence_level: code_verified+test_verified, confidence: exact]`

**2026-08-21: the outward claims now match this, and the escape hatches were checked before removing
them.** Five user-facing places still advertised iWork support (`README.md`, the App Store
description, `Docs/ai/PROJECT.md`, the picker caption, and the error string, which called support
"limited" when it is zero). Per the claim-audit rule the removal was evidenced in both directions,
not just by absence:

- The iOS 27 SDK on this machine exposes **no** iWork text-extraction API. Swept
  `iPhoneOS.sdk/System/Library/Frameworks` for iWork/`iwa` symbols and for Apple-declared
  `com.apple.iwork.*` type identifiers with a route to content. Nothing.
- The obvious workaround is closed as well. Rendering the file with QuickLook and running the
  existing Vision OCR over it reaches **page 1 and no further**: `QLThumbnailGenerator` takes no
  page index, and `QLPreviewController` is UI-only.

So implementing this genuinely means parsing Apple's undocumented `.iwa` protobuf, and
`ZIPArchive` being file-scoped private means a new reader cannot even see the unzip helper without
an access-level change. **The formats stay in the picker on purpose** so the failure is reachable
and explained; removing them re-creates the defect `CHANGELOG.md:162` already fixed.
`[evidence_level: code_verified+sdk_verified, confidence: exact]`

### Spatial extraction: the word-position arithmetic, and two branches that used to fail silently

`extractTextWithSpatialOrdering` is the column-aware reader for every PDF page that skips Vision.
It asks PDFKit where each word sits via `page.selection(for: NSRange)` and groups the results into
lines, then into columns.

**Until 2026-08-21 the range it asked with drifted off the word.** It was built from a
hand-maintained counter that under-counted two independent ways, and the two compounded:
`split(whereSeparator:)` omits empty subsequences, so every run of whitespace collapsed into a
single gap while the cursor advanced by exactly `+ 1` per gap; and `String.count` counts grapheme
clusters while `NSRange` addresses UTF-16 code units, so ligatures drifted it further. Both
under-count in the same direction, so the range stayed **in bounds** and PDFKit kept returning
bounds, for different text than the word being positioned. The word appended to the line was right
and its recorded coordinates were not. The range now derives from the `Substring`,
`NSRange(word.startIndex..<word.endIndex, in: pageString)`, where `in: pageString` is load-bearing.
`[evidence_level: code_verified+test_verified, confidence: exact, evidence_source: SpatialOffsetArithmeticTests]`

**Two branches returned a materially worse result and said nothing**, which is why a two-column
extraction defect had to be diagnosed by inference across three sessions rather than read off a
trace:

1. `guard spatialLines.count > 3` returns nil, sending the caller to raw `page.string`, which
   interleaves columns by construction. Both call sites read `... ?? text`, so a nil return was
   indistinguishable from a success.
2. When `detectColumnBoundaries` returns empty, the page is read as a single column, sorted by Y
   alone, and returned **non-nil**. Genuinely single-column pages and multi-column pages whose
   boundaries were missed both land here and cannot be told apart from inside the function; in the
   second case a Y-only sort interleaves the columns, because a left line and a right line at the
   same height sort adjacent.

Both now log. The selected `PageProcessingStrategy` is also logged per page, and equal-Y ties break
on X ascending, because `sorted(by:)` is not stable in Swift and the same page could previously
extract differently on two runs. **The instrumentation was the point of that change**, and it is
what made the attribution below possible.
`[evidence_level: code_verified, confidence: exact]`

#### Attribution closed 2026-08-24: the column signal was destroyed before column detection ran

The damage was upstream of every check meant to catch it, which is why branch 2 above looked like
the defect and was only a symptom of it.

Words were grouped into a `SpatialLine` on a **vertical test alone**. `page.string` on a two-column
PDF emits words row by row across the gutter, so a left-column word and a right-column word at the
same height arrive adjacent at the same Y and were merged into one line. That line's `xPosition` is
the **mean** of its words' midpoints, so it lands near the page centre.

`detectColumnBoundaries` then looks for a gap wider than 10% of the page across those means. Once
every line sits at the centre there is no gap, so it returns empty, branch 2 sorts by Y, and the
columns interleave. **Neither a smarter `detectColumnBoundaries` nor the tie-break could have fixed
this**: both operate on X positions that have already been averaged across the gutter.

`DocumentProcessor.spatialLineBreak(wordBounds:currentLineBounds:currentLineY:)` now returns
`.none`, `.verticalGap` or `.horizontalGap`, and a horizontal discontinuity starts a new line: a
move back to or past the line's own left edge, or a forward jump wider than `1.5 ×` glyph height
(floored at 8pt), which is a gutter rather than a word space. Scaling by glyph height keeps the
threshold correct at any page size. Lines then stay inside one column, `xPosition` becomes genuinely
bimodal, and the existing column grouping and per-column top-to-bottom assembly work as designed
with no further change.

It is `nonisolated static` and takes only geometry, so this is the first part of the two-column path
that can be exercised without ingesting a real journal PDF on a device. Seven cases in
`DocumentProcessorTests` cover the gutter crossing, the left-margin wrap, ordinary word spacing,
the next row, both no-line-started guards, and that the threshold scales with type size.

A page whose words arrive across a gutter now says so, so a genuinely single-column page and a
two-column page are no longer indistinguishable in a trace.

Device evidence this closes: a stored chunk read *"…in locomotors are more diverse, consisting of
Gi-coupled 5-HT, and 5-HTS. tion, reinforcement learning…"* — lines emitted out of order, with
"locomotion" severed across the join.

**Withdrawn: the non-English detections are not a scrambling signal.** This document was read as
non-English on 118 of 552 chunks, and that was proposed here as a free interleaving detector. The
corrected capture disproves it: with the ordering fixed and every page matching Vision's transcript,
the distribution barely moved (126 non-English chunks to 123). Inspecting them shows why — they are
reference-list entries such as *"Weissbourd B, Ren J, DeLoach KE, Guenthner CJ, Miyamichi K"*, which
are surnames and initials with no function words, and any language recogniser will call those
Indonesian or Dutch. The signal was reading bibliographies, not damage.
`[evidence_level: device_log_proven, confidence: exact, evidence_source: PostPostFixAgain.txt, lang distribution before and after the fix]`
`[evidence_level: code_verified+test_verified, confidence: exact, evidence_source: DocumentProcessor.spatialLineBreak; DocumentProcessorTests, 7 cases; device capture 2026-08-24, not yet device-verified]`

#### 2026-08-24, same evening: the real defect was line ordering in the Vision path, not columns

Two paired probes settled this in one device run and corrected two prior diagnoses.

`DocumentObservation.text.transcript` for page 1 reads *"…dynamics that regulate diverse aspects of
motivation-related behavior. Dopamine and serotonin transiently modulate moment-to-moment behavior at
timescales ranging from sub-second to minutes…"* — correct and continuous. **Vision's own reading
order was never the problem.**

The text that actually won for that page — `winner=layoutText` on all 8 pages — emitted those same
lines in the order **2, 1, 4, 3**. Adjacent pairs swapped. Pages 3 and 5 take the PDFKit spatial path,
carry its `speci c` ligature drops, and read correctly, which localises the defect to
`LayoutAwareExtractor`.

`groupBlocksByLine` matched a block to a line with
`groups.keys.first { abs($0 - block.topY) < lineTolerance }`. `Dictionary.keys` iterates in hash
order, so a block within tolerance of more than one line joined an **arbitrary** one. The grouping
therefore depended on Vision's block order and on the per-process hash seed, so the same page could
group differently between runs. Blocks are now consumed top-to-bottom and matched to the *nearest*
line from sorted keys.

**Nothing was read across the gutter and no text was lost.** Every word was present and correctly
recognised, in the wrong order — which is exactly why it passed a printable-ratio and entropy quality
gate, and why the repeated non-English detections were a symptom of scrambled word sequences rather
than of missing text.

**Correction, same evening.** The paragraph above attributed this to `groupBlocksByLine`'s
`Dictionary.keys.first` lookup. That is a real defect and it was **not** the cause: the capture after
fixing it was byte-identical, `layoutTextChars=5717` before and after, with the same transposition.

The cause is one level up, in `buildReadingOrderText`:

```swift
if abs(lhs.topY - rhs.topY) > 0.02 { return lhs.topY > rhs.topY }
return lhs.minX < rhs.minX
```

**The threshold is larger than the quantity it compares.** A journal page carries roughly 55 lines,
so consecutive lines sit about 0.015 apart in normalised coordinates — under 0.02. The vertical test
therefore never fired between neighbouring lines, and `minX` decided their order: body text sorted by
left edge, so an indented or hyphenated line jumps ahead of the line above it.

**And it is not a strict weak ordering.** Lines at 0.500, 0.485 and 0.470 make both inner pairs
compare equal while the outer pair compares ordered. `sorted(by:)` is documented as producing an
unspecified result when given such a predicate, which is why the output was scrambled rather than
merely imprecise.

`readingOrderPrecedes(lhsTopY:lhsMinX:rhsTopY:rhsMinX:)` replaces it: strictly by position down the
page, left edge only for an exact tie. No epsilon is required, because `groupBlocksByLine` has
already collapsed a physical line into one element using a tolerance derived from real glyph height.
Applied to all three call sites in the file rather than the one that was proven, and the same
non-transitive shape in `detectAndSeparateTables` is now row-bucket quantisation, which keeps its
legitimate row-then-left-to-right intent while being transitive. Three unit tests pin the ordering,
the transitivity, and that the left edge never overrides a real vertical difference.

**Device-verified 2026-08-24.** After the comparator fix, all eight pages' stored text matches
Vision's transcript order. Page 1 now reads *"dynamics that regulate diverse aspects of
motivation-related / behavior. Dopamine and serotonin transiently modulate / moment-to-moment
behavior at timescales ranging from / sub-second to minutes…"* against the previous *2, 1, 4, 3*.
`layoutTextChars` is unchanged at 5,717, confirming the text was only ever misordered and never lost.
The paired probes were removed once they had done their job; the three comparator unit tests replace
them, and unlike a log line they fail against the old predicate.

Correcting the entry above it: the `952d85f` note described this as gutter interleaving. It is not.
That commit stands on its own — `extractTextWithSpatialOrdering` genuinely did merge across a gutter
and now has 7 tests where it had none — but that path handles 2 of 8 pages here and found nothing to
correct on either, and the language-detection distribution was byte-identical before and after it.
`[evidence_level: device_log_proven+build_verified+test_verified, confidence: exact, evidence_source: PostFix.txt TRANSCRIPT PROBE vs PAGE TEXT PROBE across all 8 pages]`

### Audio and video: the failure mode is verified, transcription itself is not

`say` fails from an agent shell (`-241`), so no *speech* fixture can be authored there. A silent WAV was used to check the failure mode instead, and that part is settled: ingesting audio with nothing to transcribe **throws in about 76 ms** rather than yielding an empty document that gets indexed as a success. `[evidence_level: test_verified, confidence: exact, evidence_source: IngestionFormatCoverageTests testSilentAudio, 0.076s]`

One cold-start caveat, recorded because it cost a run. On the **first** attempt of the session `SpeechAnalyzerService` logged `Starting analysis: silence.wav (1s)` and had not returned when that run was terminated for unrelated reasons; the elapsed time was never measured, so "it hung" is an inference and not an observation. Every subsequent attempt threw immediately. The plausible reading is one-time framework or model preparation. The test caps the wait at 60 s and reports a timeout as a distinct outcome so a genuine stall would be visible rather than taking the suite down.

**Still uncovered: whether transcription of real speech works at all.** No automated test exercises `.mp3`, `.wav`, `.mp4`, `.mov` or `.m4a` with actual speech in it. That needs a committed sample or a human with an audio session.

---

## 3. Chunking & Token Gating

### Semantic Chunking
- Raw text is chunked using [SemanticChunker.swift](../OpenIntelligence/Services/Document/Chunking/SemanticChunker.swift). It runs adaptive windows (default size $\le 310$ words) with character overlap.

### Structure-Aware Chunking
- When structured tables or lists survive the parsing phase, they are preserved as atomic chunks to prevent layout breakage, ensuring that data cells are not separated from their column headers during retrieval.

### Token Limit Enforcement
- Before indexing, chunks are checked against local tokenizers (e.g. `BertTokenizer`) to guarantee they are within the embedding model's limit ($\le 510$ tokens).

---

## 3.5 Stage conservation, added 2026-08-28

Three guards now sit on this path, and they answer different questions. Confusing them is how the
third one came to exist.

| Guard | Asks | Blind to |
|---|---|---|
| `verifyTokenizerCounts` | does the token counter vary with its input? | anything after tokenisation |
| `verifyContentCoverage` | did the finished chunks keep the extracted text? | **which stage** lost it |
| `IngestionStageLedger` | did each transition conserve its input? | anything outside `DocumentProcessor` |

### The metric that was computed and never compared

`verifyContentCoverage` measured two things and asserted on one. `coverage` is a set intersection of
unique words and had a `< 90` threshold. `charRatio` — the same comparison by character volume — was
computed, formatted into the **healthy-path debug line**, and never compared against anything.

Those two metrics fail differently, and the difference is the whole point. Unique vocabulary
saturates long before content does: truncate the back half of a real document and nearly every
distinct three-letter-or-longer word still appears in the front half, so `coverage` stays above 90
and the function stays silent while half the document is gone. `charRatio` is the number that moves
in that case, and it was the number with no threshold.

It now has two bounds. Below 90% means text was dropped between extraction and the finished chunks.
Above 200% means chunks are duplicating content beyond what overlap explains; configured overlap puts
a healthy document around 115–125%, so the ceiling has wide margin and still catches the
duplicate-import shape. Both numbers are reported on every warning whichever bound trips, because
high word coverage beside low volume is the truncation signature specifically, and is a different
fault from both being low.

`[evidence_level: code_verified, confidence: exact, evidence_source: DocumentProcessor.verifyContentCoverage before 2026-08-28 — charRatio assigned once, interpolated into one Log.debug, no comparison anywhere in the file]`

### Localising a loss to its stage

`verifyContentCoverage` is a single end-to-end comparison across four stages: the structure-aware
path or the semantic fallback, then `sanitizeProcessedChunkMetadata`, then
`enforceTokenLimitOnChunks`. It can say text was lost and cannot say where, which leaves a bisect by
hand.

[IngestionStageLedger.swift](../OpenIntelligence/Services/Document/Processing/IngestionStageLedger.swift)
records each transition separately and gives each one a band, so a loss names its own stage:

| Transition | Band | Why |
|---|---|---|
| extraction → chunked | ≥ 0.98 | overlap repeats text so the ratio may exceed 1.0; normalisation trims a little |
| chunked → sanitized | exactly 1.0 of characters | that pass rebuilds `ChunkMetadata` and never reads or writes `chunk.text` |
| sanitized → token-limited | at least 0.99 of **words** | that pass splits rather than truncates, but it is not character-preserving |

The last row is the sharp one, and it is checked in the wrong unit if you are not careful. A split
raises the chunk count while conserving content, so a count alone cannot tell a healthy split from a
truncation — both move the number and only one keeps the text.

But `splitOversizedChunkByTokens` separates on `.!?\n` using `components(separatedBy:)`, which
**discards every separator**, then rejoins with `". "`, injects `[Part N]` markers, and drops
blank-line runs entirely. No word is lost — both flush paths are present — but the character count
moves in both directions. This band was written as exact-characters on 2026-08-28 and corrected the
same day, before it ever ran on a real document: it would have fired on the first document
containing an oversized chunk, which is a false alarm inside the instrument built to stop false
confidence. Words are what the stage conserves, so words are what is checked.

**Noted and not changed:** that the splitter rewrites `!` and `?` to `.` and collapses blank lines is
a real property of the text that reaches embedding. Changing it changes chunk content and therefore
every vector, so it is a separate decision with its own blast radius, not a drive-by fix.

The ledger also flags a run where every chunk came out the same length past three chunks. A stage
that has stopped varying with its input can still conserve characters in aggregate, so no ratio sees
it; this is the same argument `verifyTokenizerCounts` makes one layer down, applied to the chunker.

Every reading counts `chunk.text` directly and never `chunk.metadata.characterCount`. A defect in a
counter is one of the things being hunted, and auditing a stage with the count that stage recorded
makes the audit agree with the bug.

**Not covered:** chunking → embedding and embedding → index. Both live in `RAGService.swift`, outside
the `Services/Document/**` edit boundary the RepoOS router sets for ingestion work. They are the
natural next pass.

`[evidence_level: code_verified + test_verified, confidence: exact, evidence_source: IngestionStageLedgerTests, 10 cases]`

## 4. Dual Index Storage

Once chunks are generated and validated, they are written to two separate storage engines:
1. **Lexical Index:** Stored in SQLite FTS5 via [SQLiteFullTextService.swift](../OpenIntelligence/Services/Storage/SQLiteFullTextService.swift). BM25 column weights prioritize section titles and entity tags.
2. **Vector Index:** Dense query vectors (384-dimensions) are generated using a local Core ML model (`EmbeddingModel.mlpackage`) and stored in [BNNSVectorDatabase.swift](../OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift) using Cosine Similarity.
Both indexes are isolated by `container_id` to enforce library boundaries.

---

## 5. Performance Optimizations & Checkpointing

### Zero-Copy CGImage Processing
- To reduce memory allocations and CPU overhead during structure-aware parsing and OCR fallbacks:
- Bypasses raw pixel drawing and PNG serialization passes.
- Converts preprocessed `CIImage` instances directly to raw `CGImage` pointers utilizing `CIContext`.
- Vision's `RecognizeDocumentsRequest` and `RecognizeTextRequest` perform analysis directly on the raw `CGImage` memory block, accelerating extraction by 30%+ and avoiding OOM memory spikes.

### Page-Level JSON Checkpointing & State Persistence
- To prevent data loss and avoid reprocessing from page 1 during large document ingestion:
- Each page's intermediate `PageParseResult` is serialized to a Codable JSON format.
- Ingestion state and progress are tracked in a session-level `ingestion_state.json` file inside the checkpoints folder:
  `localCacheDir()/IngestionCheckpoints/<docFingerprint>/ingestion_state.json`
- This state file persists a stable `documentId` (ensuring chunks are indexed under the same ID on resume), `lastCompletedPage` index, and accumulated counts (chunks, words, chars).
- If the queue is paused or the app restarts mid-ingest:
  1. The engine restores the stable `documentId` and counts from `ingestion_state.json`.
  2. The loop skips rendering, parsing, embedding, and storage tasks for any page batch where `endPage <= lastCompletedPage`.
- After successfully committing each page batch to the FTS5 index and vector DB, `db.persist()` is called to flush vector changes, and `ingestion_state.json` is updated atomically.
- Upon successful document indexing completion or user queue item discard, the temporary checkpoint directory (containing page checkpoints and the state JSON) is deleted.

### Authoritative Queue Dismissal & Automatic Repair
- Stop/X and paused-item discard add a bounded tombstone for each removed queue ID to the coordinated `ingestion_queue.json` state. The field is optional while decoding, so older queue files remain readable.
- `WorkspaceSyncService` merges tombstones before queue items. A matching stale local or shared item is filtered out, and a tombstone-only file is retained so an empty local queue can still defeat a stale iCloud snapshot.
- Empty-vector self-healing requests enter one sequential in-process scheduler. Stop/Discard persists per-library suppression in local preferences and the rebuild checks it before each safe document stage.
- A rebuild that has already removed a document completes the matching re-add before yielding, preventing cancellation from leaving catalog metadata partially deleted. A later explicit import or manual rebuild clears the suppression.
- The tombstone history is capped at 512 newest IDs; a future explicit import receives a new ID and is not blocked by an older dismissal. `[evidence_level: code_verified, confidence: high_pending_runtime_validation, evidence_source: RAGService.swift, WorkspaceSyncService.swift, IngestionQueueOverlay.swift]`

### Streamed Ingestion Append Support
- To support progressive SQLite indexing during batch-based streaming ingestion:
- `SQLiteFullTextService.swift` implements optional `append` parameters on `store`, `storePages`, and `storeChunks` to bypass default UPSERT deletes.
- Document FTS5 text is combined iteratively with existing content, pages are inserted sequentially, and all batch chunks are appended.
- Page index numbers are aligned dynamically using the batch `pageRange` bounds offset to prevent page mapping collisions.

---

## 5b. Token counting, and the invariant that guards it

**The token counter must be asked whether it counts.** `DocumentProcessor.countTokens` returns
`try tokenizer.encode(text:addSpecialTokens:).count`. If the bundled tokenizer carries a `padding`
block, that call returns the **pad width for every input**, so the counter becomes a constant while
still looking like a measurement.

That is not hypothetical. Until 2026-08-17 both `embedding_tokenizer.bundle` and
`reranker_tokenizer.bundle` carried `"padding": {"strategy": {"Fixed": 128}}` alongside
`"truncation": {"max_length": 128}`, and three defects followed from that one block:

1. **55% of all library content never reached the embedder.** Both compiled models declare input
   shape `[1, 512]` and both Swift providers pad to 512 themselves, so the tokenizers were the only
   component capped at 128. Measured with the real WordPiece vocab over 139 live chunks: median
   chunk **273 tokens**, and **125 of 139 (90%)** truncated.
2. **The `safeTokenLimit` guard at 430 could never fire**, because `countTokens` always returned 128.
   The chunker had no working measure of its own output for the entire life of the feature.
3. **Mean pooling averaged `[PAD]` into every vector**, because the provider builds
   `attentionMask = Array(repeating: 1, count: inputIds.count)` over already-padded ids, so the mask
   marks padding as real content.

Deleting the `padding` block fixes all three, because every consumer already pads to its own fixed
width. Truncation is now 512, matching the models.

**Why it survived so long, and what now guards it.** The logs read
`maxTokens=128/430` on **3,910 of 3,910** recorded ingestions. A constant that sits inside a
plausible range looks exactly like a working measurement, and nothing asked whether it should vary.
`DocumentProcessor.verifyTokenizerCounts` now asks at load: it encodes a one-word string and a
180-word string and logs an error if they measure the same. The check is **behavioural rather than
configuration-based**, so it holds however a future tokenizer expresses padding and does not require
parsing `tokenizer.json`. It logs rather than traps, because a wrong token count degrades retrieval
silently but does not corrupt data, and refusing to ingest would be the worse failure.

**Existing libraries do not benefit until re-embedded.** Old vectors remain valid 384-dimensional
MiniLM embeddings of a truncated, padding-diluted input. Nothing detects the change, because
`KnowledgeContainer` persists only `embeddingProviderId` and `embeddingDim` and neither moves. See
the Notion row "Existing libraries keep truncated vectors because nothing detects the embedding
change".

`[evidence_level: measured, confidence: high, evidence_source: real WordPiece tokenization of 139
live chunks; 3910 constant log lines; BenchmarkRuns/tokfix showing 386 to 430 after the fix]`

## 6. Predictive Self-Tuning & Dynamic Config Optimization

To prevent wasteful document rebuild loops (re-extraction and re-embedding), the pipeline implements **Predictive Self-Tuning** and **Non-Destructive Adjustments** to optimize the RAG parameters *before* ingestion starts:

### Predictive Document Pre-Scan
When a document is selected for import and the container's `autoAdaptDimension` flag is enabled:
1. **Sample Extraction**: The system extracts a raw text preview from the first 10 pages of the document (or the first 10,000 characters).
2. **Feature Analysis**: The `LibraryIntelligenceCenter` analyzes the preview for structural, linguistic, and content signals:
   - **Code/Math Content**: Regex and keyword patterns scan for syntax or equations.
   - **Layout Structure**: Measures list patterns, table structures, and multi-column density.
   - **Language Properties**: Classifies vocabulary richness, multilingual complexity, and technical jargon density.
3. **Pre-Ingestion Adaptation**: Based on these signals, the engine resolves the optimal `ChunkingPlan` (e.g. `densePrecision` strategy, `300` word window for structured text/code) *before* processing page 1.
4. **Dynamic Container Tuning**: The container’s active `chunkingDirective` is updated to `.auto` with these parameters. The ingestion pipeline processes the current document and all subsequent imports using this custom-tuned configuration immediately, eliminating the need to re-process the file.

### Non-Destructive Configuration Shifting
- **Chunking Strategy & Window Shifts**: Since chunk size variations do not break vector math, changes to the chunking strategy, window window size, or overlap are applied **instantly and silently** to the container configuration. The database continues to perform cosine similarity searches over existing mixed chunks, avoiding the CPU/battery drain of full database rebuilds.
- **Embedding Provider Shifts**: Changes to the embedding provider or vector dimension (e.g., from 384D Core ML to 512D Contextual) change the mathematical vector space. Mixing dimensions will crash similarity search; therefore, embedding shifts are blocked during active ingestion and require a full database rebuild to guarantee consistency.
