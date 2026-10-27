# How OpenIntelligence Works

> **Documentation status:** Source-verified against `f0ac9b9` on 2026-08-21. Every architectural
> constant below was re-read from the code on that date: the 4,096-token context window (corrected
> 2026-10-18: that is the figure Apple documents and the app's fallback, and the app reads the window the
> device reports, which is 8,192 on a Mac with macOS 27; the lines below say so), the 384
> dimensions, the 310-word chunk ceiling under a 510-token limit, the nine SQLite tables, the nine
> verification gates and the 1,000-chunk GPU threshold all hold. Subsystem line counts were recounted
> and had all drifted upward since this page was first written; recount them with the command below
> rather than trusting the table. **The accuracy figures in section 08 were withdrawn rather than
> updated**, and are explained where they occur. A second withdrawal made on the same date, the
> implication that Private Cloud Compute runs in production, was reversed on 2026-09-20: PCC shipped
> in 5.2 on 2026-09-10, and section 05 keeps both the original correction and this supersession. `[evidence_level: code_verified, confidence: exact_for_constants_withdrawn_for_measurements]`

> **Corrected 2026-09-29** against `8be003a`: the GPU Acceleration profile gates Metal vector search
> (Efficiency and Balanced, the default, keep it on the CPU); a citation points at a chunk with its page
> and a short quote, not at a byte range or an exact sentence; and the extractive answer step's own path
> is off, but the same extractor answers value questions through five live call sites.
> `[evidence_level: code_verified, confidence: exact, evidence_source: BNNSVectorDatabase.swift:501-507; DeviceCapabilityService.swift:923-934; StructuredAnswer.swift:65-117,440; RAGService.swift:8705,8734,9199,14383,15192]`

> **Corrected 2026-10-27** against `1e4a718` (the 5.7 code): section 01's layer table (nine feature areas, and the
> `UI/` layer it left out), step 1's conversation memory, step 5's rank-2 defect (fixed in `fa80e71`, and noted where
> the page still called it open), step 6's temperatures, section 04's rows for gates A and B, section 05's rung 4,
> and section 08's table labels and Deep Think figures.
> Each note sits under the passage it corrects, and the original text stays in place above it.
> `[evidence_level: code_verified+artifact_derived, confidence: exact for code and high for benchmarks, evidence_source: the files and lines cited at each note, read 2026-10-27 at 1e4a718, nothing built or run]`

> **Corrected 2026-10-27, second pass,** against `55fea8e`: section 05's rung 1 and section 04's list of the answers
> the checks run on, both for Standard's reliability fallback, with a pointer where step 6 and section 11 repeat
> rung 1. Each note sits under the passage it corrects.
> `[evidence_level: code_verified, confidence: exact, evidence_source: the files and lines cited at each note, read 2026-10-27 at 55fea8e, nothing built or run]`

> **Corrected 2026-10-20** against the working tree (`b868fc0` plus the 5.7 work in progress), wherever this page
> disagreed with the code. What changed:
> - **Section 07 is rewritten from the code.** Deep Think and Maximum first try a shortcut for exact values, then
>   search up to five ways and grade what they found, and only an excellent or good haul gets the multi-session
>   reading. Deep Think's sessions read slices of that one search and never search while they read. Deep Think goes
>   back out after the reading, in research rounds when the notes show a gap or the answer reads like a miss, and in
>   the Self-RAG check's retries, while Maximum's one big gather comes before its reading. No session is handed a
>   tool. Deep Think stops early only when three conditions hold at once or the model says the answer is complete,
>   while Maximum's own loop stops on either of two. Fifty is Maximum's ceiling, and Deep Think stops at 8 sessions
>   on every device.
> - **The word bank's step tables say which steps run in which mode.** Standard's query expansion (steps 1.5 to 1.5c),
>   HyDE and contextual compression run in no mode, positional reordering runs in whole-passage packing (never for a
>   procedure, and for a lookup only when its context is packed again for the device), extractive summaries (5.9)
>   cannot run, the nine checks run once after the answer and label it, and step 8.1's calibrated figure is logged
>   rather than shown as the answer's confidence.
> - **Also corrected:** the word index stems words rather than matching them exactly, the vector store is one flat
>   file compared with every vector, chunk sizes (260 target, 310 ceiling, 430-token split) and the 380-word limit on
>   keeping a table whole, one summary per document with no tree, the evidence budget logged on an iPhone, the
>   default route (Hybrid, with Private Cloud Compute set to "Ask when needed"), when Standard goes to Private Cloud
>   Compute, what the consent sheet shows, when the checks refuse an answer, which checks compare the answer with the
>   passages, and how the device backs off under pressure.
> - **Versions.** 5.7 is the App Store build (live 2026-10-22); 5.6 was live from 2026-10-08. Each behaviour new in 5.7
>   says so, for example the nine checks labelling Deep Think and Maximum answers, which read Not Checked in 5.6.
> - **Line numbers.** `RAGService.swift` changed throughout the 5.7 work. Its line numbers on this page are
>   those of 22:11 on 2026-10-20, when it had 22,746 lines, and the larger ranges also name their step or function.
> - **Revised the same evening** after an independent review of these corrections: overstated claims narrowed,
>   exhaustive claims tagged `grep_verified` after the greps were run, and the device-log figure tagged
>   `artifact_derived`.
>
> Withdrawn claims are quoted where they are replaced, so the record shows what was said.
> `[evidence_level: code_verified, confidence: exact, evidence_source: the files and lines cited at each corrected passage, read 2026-10-20, nothing built or run]`

This is the long-form explanation of what the app does, in order, and **why each part is there**.
It is written at two levels throughout: a plain-English block for anyone, and the technical detail
underneath it.

```bash
# Recount the subsystem sizes in section 01
for s in RAG Document Infrastructure Agentic Query Storage LLM Embedding Evaluation VectorStore AIPlatform Billing; do
  printf "%-16s %8s\n" "$s" "$(find OpenIntelligence/Services/$s -name '*.swift' -exec cat {} + | wc -l)"
done
```

---

## 00. The whole thing at once

> **In plain words**
> **Imagine a librarian with a very small desk.**
> You hand over a stack of your own books. The librarian reads every one and writes index cards about what's on each page. That's the first half of the app, and it happens once, when you add a document.
> Then you ask a question. The librarian runs to the shelves, grabs the handful of cards most likely to answer it, and brings them back to the desk. Here's the catch: **the desk only fits about four pages at a time.** Not four hundred. Four. So choosing *which* cards make it onto the desk is the entire hard problem, and almost everything in this app exists to make that choice well.
> Then the librarian writes an answer using only what's on the desk, and you watch it being written. When it's finished, a fact-checker compares it against those pages and puts a label on it: Verified, or Unverified with the checks it failed. In Standard it also leaves out of the Fact Check list under the answer any claim it couldn't find support for, and if the checks fail badly enough, it takes the answer back and says so instead. If nothing on the desk answers the question, the librarian is required to say *"that isn't in your documents"* rather than guess.
> Everything below is a detail of that story.

OpenIntelligence is a local-first retrieval-augmented generation system. Documents are parsed, chunked, embedded and indexed entirely on device. A question is answered by retrieving evidence from that index, packing it into a strictly bounded context window, generating from it, and then checking the finished output against the evidence and labelling it.

> **Corrected 2026-10-20.** This section said a fact-checker compares the answer "before you see it" and "stops it" when
> it says something the pages don't, and that the output is verified "before it is shown". The answer streams into the
> chat as it is written in every mode, and the nine checks run once, after it is finished. They label it. In Standard
> they also keep any claim Gate B marks unsupported out of the claim list shown under the answer (Fact Check), and
> they replace the answer with a refusal only under the rule in section 04. In Deep Think and Maximum they label the
> answer and nothing more (5.7). In 5.6 the nine checks did not run on those answers, though, by the code's own note,
> Deep Think's Self-RAG check did on every device but an A17 Pro, and so did the source-only check for a lookup. The source-only check can
> still rewrite a lookup's answer, or refuse it, after the writing (section 04).
> `[evidence_level: code_verified, confidence: exact, evidence_source: ChatScreen.swift:3291, FoundationModelStructuredGenerator.swift:117-158, RAGService.swift:16568-16734 (step 7.5), 11238-11262, 20072-20089 (resolvedDisplayResponse), StructuredAnswer.swift:979-1047 (sanitizeForVerification), GroundedAnswerView.swift:71-99, AgenticOrchestrator.swift:199-208, 798-816]`

The governing constraint is that Apple's on-device foundation model has a small, fixed **context window**: 4,096 tokens in Apple's documentation and 8,192 on a Mac with macOS 27, and the app reads the device's own figure. A document does not fit. Neither does a naive top-20 chunk set once the system prompt, tool schemas and output schema are accounted for. Every packing, compression, ordering and filtering decision in the pipeline traces back to that number.
The second constraint is that documents stay on the device. So "send the whole corpus to a larger model" is not available either. Retrieval-augmented generation is not a preference here; it is the only architecture that satisfies both constraints at once.

### Four things that make it different

> **In plain words**
> 1. **Two filing systems, not one.** Cards are filed both by the words on them and by what they're about. The word filing system files a word by its stem, so "running" also finds "run". "Part number 4021-B" needs the first. "How do I change the oil" needs the second.
> 2. **The desk is tiny.** Everything about the design follows from that.
> 3. **The privacy decision is made late.** The app looks at your pages first, and only then decides whether it needs outside help. If it does, it shows you how much would leave and why before anything does.
> 4. **A fact-checker that's allowed to say no.** Most AI tools always give you an answer. This one is allowed to refuse, and that's deliberate.

1. **A dual index.** SQLite FTS5 with BM25 for lexical retrieval, a memory-mapped BNNS vector store for dense retrieval, merged by rank fusion. Neither arm is sufficient alone. The lexical arm stems words with the Porter tokenizer, and the dense arm is one flat file of vectors that a search compares with the question one by one. (Corrected 2026-10-20: the plain-words line above said cards are filed "by the exact words on them".) `[evidence_level: code_verified, confidence: exact, evidence_source: SQLiteFullTextService.swift:242-253, BNNSVectorDatabase.swift:1036-1048, 1104-1201]`
2. **A hard token budget.** Compression, sibling expansion, positional reordering and tool-schema management are all consequences of a window of a few thousand tokens being the real ceiling. (Corrected 2026-10-20: contextual compression is built and runs in no mode, see step 4.7. `[evidence_level: grep_verified, confidence: exact, evidence_source: usesContextualCompression is read only at RAGService.swift:11654 in Standard's path, besides a logging dictionary and a Settings screen, grep run 2026-10-20]`)
3. **Post-retrieval routing.** The decision about whether anything leaves the device is made after evidence exists, and consent is requested for the exact minimized payload rather than in advance.
4. **Nine verification gates.** Deterministic, local and run once after generation. They label the answer, and in Standard they can also force an abstention, under the rule in section 04. Refusing to answer is a designed outcome, not a failure state. (Corrected 2026-10-20: this said the gates are "able to force an abstention" without saying when. `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:16660-16706]`)

## 01. How it is built

*One Swift codebase, no server, no backend. Everything below was counted and read from the source rather than described from a design document.*

> **In plain words**
> There's no website behind this app and no account server. The whole thing is one program that runs on your device.
> Inside, it splits cleanly in two: the screens you touch, and the machinery underneath that does the reading, searching and answering. The machinery is by far the bigger half.

### The five layers

| Layer | What lives there |
|---|---|
| `App/` | Launch, the root view, and a debug validation harness |
| `Core/` | Shared models, protocols and extensions used everywhere |
| `Features/` | Ten user-facing areas: Chat, Documents, Camera, Settings, Diagnostics, Telemetry, Database, Billing, Onboarding, Debug |
| `Services/` | Twelve subsystems. All the actual work |
| `SDK/` | A single engine-facing entry point, the beginning of a reusable boundary rather than a finished one |

> **Corrected 2026-10-27** against `1e4a718`. The `Features/` row said ten areas, the last of them Debug.
> `Features/Debug/` was removed in the 5.7 work (`2fae850` on 2026-10-20 deleted `EvidenceThreadDebugView.swift`,
> `a27658f` on 2026-10-21 deleted `EvidenceThreadDebugService.swift`), which leaves nine: Chat, Documents, Camera,
> Settings, Diagnostics, Telemetry, Database, Billing and Onboarding. The table also left out a sixth code layer,
> `UI/`, present since the first commit (`170121f`, 2026-04-15): `UI/Components/` (nine shared views and helpers,
> among them the cloud consent prompt, the glossary, the import queue overlay and the model status indicator) and
> `UI/DesignSystem/` (`SurfaceCard.swift`, `Theme.swift`). Beside the six, `OpenIntelligence/` holds `Resources/`
> (assets, Core ML models, the StoreKit configuration) and the vendored `swift-transformers/` package.
> `[evidence_level: code_verified, confidence: exact, evidence_source: git ls-tree at 1e4a718 of OpenIntelligence/, OpenIntelligence/Features/ and OpenIntelligence/UI/; git show --name-status 2fae850 a27658f; git log --diff-filter=A -- OpenIntelligence/UI/Components OpenIntelligence/UI/DesignSystem (170121f)]`

### The twelve subsystems

| Subsystem | Lines | Files | Responsibility |
|---|---|---|---|
| `RAG` | 32,014 | 29 | Orchestration, retrieval, context packing, verification, safety |
| `Document` | 25,669 | 25 | Parsing, OCR, layout, chunking, classification |
| `Infrastructure` | 18,368 | 25 | iCloud sync, GPU compute, device capability, background tasks, settings |
| `Agentic` | 11,631 | 11 | Multi-session reasoning, conversation memory, Siri intents |
| `Query` | 10,329 | 12 | Understanding, rewriting, intent, specification extraction, suggestions |
| `Storage` | 4,534 | 4 | SQLite and the full-text index |
| `LLM` | 3,687 | 6 | Prompt compilation and model execution |
| `Embedding` | 2,897 | 9 | Vector generation across the Core ML and Core AI providers |
| `Evaluation` | 1,743 | 8 | The benchmark runner and its metrics |
| `VectorStore` | 1,686 | 4 | The memory-mapped vector database |
| `AIPlatform` | 1,948 | 11 | Apple Foundation Models: sessions, tools, budgets, capability, routing policy |
| `Billing` | 1,405 | 8 | StoreKit, entitlements, quotas |

> **An honest structural note**
> Three files carry about a third of the service code between them: the retrieval orchestrator at 18,459 lines, the document processor at 9,562, and the agentic orchestrator at 7,932. That is not a shape anyone would choose deliberately. It is what happens when a pipeline grows stage by stage and each new stage lands next to the one before it. Splitting them is real work that has not been done, and a page explaining the architecture should say so rather than draw a tidy diagram that implies otherwise.
> Recounted 2026-10-20 in the working tree with `wc -l`: the retrieval orchestrator (`RAGService.swift`) is 22,696 lines (22,746 by 22:11 the same evening, as the 5.7 work goes on), the document processor 10,628 and the agentic orchestrator 9,381. `[evidence_level: code_verified, confidence: exact, evidence_source: wc -l on the three files, 2026-10-20]`

### What is actually on disk

> **In plain words**
> Two things get written for each library. A database file holding the text and everything the app learned about it, and a pair of binary files holding the meaning-map coordinates. Nothing else, and nothing anywhere but your device.

One shared SQLite database, isolated per library by a container column rather than by separate files. Nine tables:

| Table | Kind | Holds |
|---|---|---|
| `documents` | FTS5 | Whole-document text for full-text search |
| `document_meta` | standard | Counts, dates, size, container |
| `document_content` | standard | Raw text for direct extraction |
| `chunks` | FTS5 | Chunk-level search. Nine columns, of which only `section_title`, `section_path` and `content` are searchable |
| `chunk_structured` | standard | Structured elements recovered from a chunk |
| `chunk_table_rows` | standard | Table rows stored individually, so a row survives as a row |
| `document_pages` | FTS5 | Page-level search and context boundaries |
| `semantic_query_cache` | standard | Previously embedded queries, so a repeat question skips embedding |
| `documents_vocab` | fts5vocab | The vocabulary used to expand queries with this library's own words |

Vectors live outside SQLite in three files per library: a metadata JSON of roughly 5 to 10 MB, a `_vectors.bin` of contiguous 32-bit floats, and a `_norms.bin` of precomputed lengths. A new passage's vector is appended after the others, in the order passages arrive. There is no search index, no clustering and no grouping by topic: a search scores the question against every vector in the file and keeps the best (below). Topic clusters are computed only for the Knowledge Atlas and its visualizations, which are for browsing and play no part in answering. `[evidence_level: code_verified, confidence: exact, evidence_source: BNNSVectorDatabase.swift:1036-1048, 1104-1201, VectorStoreRouter.swift:124-185 (the HNSW route falls back to this store)]` `[evidence_level: grep_verified, confidence: exact, evidence_source: no VecturaKit in either Package.resolved, and k-means appears only in AtlasLabeling.swift, LibraryVisualizationEngine.swift, the two Telemetry visualization views and SpatialDocumentAnalyzer.swift, which groups text by its x position to find a page's columns, grep run 2026-10-20]` The vector file is memory-mapped rather than loaded, so a large library costs almost nothing in resident memory: about 10 MB for the metadata, essentially zero for the mapped vectors, and 200 KB for the norms.

### How a search physically runs

> **In plain words**
> Comparing your question against every card is just arithmetic, repeated a lot. For a small library the processor does it directly. Past about a thousand cards it becomes worth handing to the graphics chip, which does thousands of small sums at once. The app switches automatically when GPU Acceleration is set to Performance or Maximum; Efficiency and Balanced, the default, keep it on the processor. Either way it reads the numbers straight from the file rather than copying them into memory first.

Below 1,000 chunks, similarity is computed with Accelerate's `vDSP_dotpr` directly against the memory-mapped pointer. At or above 1,000 chunks, on the Performance or Maximum GPU profile, the same data is handed to a Metal compute shader through an unsafe buffer pointer over the same mapping, so the GPU path is near-zero-copy; Efficiency and Balanced, the default, keep it on the CPU. Neither path materialises the embeddings on the heap.

## 02. Reading your documents: six steps

*This happens once, when a file is added. Everything later is capped by how well this goes: a fact that never made it into the index cannot be retrieved by any amount of cleverness downstream.*

#### Step 1. Get the words out

> **In plain words**
> Easy if the file is a typed document. Harder if it's a photo of a page, where the app has to look at the picture and read it, like squinting at someone's handwriting. Hardest with tables, where *where* a number sits matters as much as the number itself: "$40" in the price column means something different from "$40" in the shipping column.

**How.** Type-specific extractors. PDFKit lifts the native text layer when one exists. Vision's `RecognizeDocumentsRequest` handles scans, photos and camera captures, parsing tables into rows and columns rather than reading order. Office formats are unzipped and their XML parsed. CSV goes through an RFC 4180 parse. Audio and video go through SpeechAnalyzer. Page rendering is zero-copy, converting `CIImage` straight to `CGImage` without a PNG round trip.

**Why it matters.** Extraction is the ceiling on the entire system. The zero-copy path is a memory decision as much as a speed one: rasterising a 400-page PDF through image buffers on a phone is a reliable way to get the app killed.

#### Step 2. Cut it into pieces

> **In plain words**
> Cut the document into index-card-sized pieces, aiming for about 260 words each and never more than 310. Two rules. Let the cards **overlap** slightly, so a sentence landing on a cut isn't sliced in half and lost. And **keep a table in one piece when it fits**, because a number without its column heading is worthless. A table longer than about 380 words is cut between rows, with its heading row repeated on each part, and it also gets a short summary card of its own.

**How.** Adaptive windows aiming at 260 words, with a hard ceiling of 310 words and an overlap of up to 50 words. A table, list or figure stays one chunk up to 380 words. A longer one is split by rows (a table's header row is repeated in the parts), and each table also gets a summary chunk. Each chunk carries a prefix naming its document and section before it is embedded.

**Why 310.** The chunk must fit under the embedding model's 510 word-piece token limit, and words are not tokens, so the cap leaves headroom. The binding limit is counted in tokens at step 4, which splits any chunk over 430 tokens. The prefix exists because a chunk read in isolation has lost what it is about, which measurably hurts retrieval.

> **Corrected 2026-10-20.** This step said "roughly 310 words", "character overlap", and that tables and lists are
> "never split". 310 is the ceiling and 260 the target, the overlap is counted in words (at most 50), and only a table
> of up to 380 words stays whole. The suggestion the pre-scan saves for a library (280 to 420 words, overlap 50 to 70)
> is clamped to the same 260 and 50 before chunking.
> `[evidence_level: code_verified, confidence: exact, evidence_source: SemanticChunker.swift:261-273, DocumentProcessor.swift:1054-1076, 5594-5660, 6572-6600, AdaptiveEmbeddingOptimizer.swift:296-336]`

#### Step 3. Highlight what matters

> **In plain words**
> Go through each card with a highlighter and mark the names, dates, places and the section heading it came from. Later, a match on a highlighted word counts for more than a match buried in ordinary prose.
> **Corrected 2026-10-20.** In the word search only the section heading and the section path count for more. The names and dates stay written on the card, but they don't raise its score there. `[evidence_level: code_verified, confidence: exact, evidence_source: SQLiteFullTextService.swift:242-253, 1458-1461]`

**How.** Apple's `NLTagger` performs named entity recognition. Keywords, authors and section headers are attached to each chunk record.

**Why.** BM25 column weights prioritise section titles and entity tags, so lexical search matches against high-signal fields rather than undifferentiated body text. The section path is also what the app uses later to work out which chunks are neighbours.

> **Corrected 2026-10-20.** Entity tags are not a searchable column. The chunk index searches three columns, weighted
> section title 10, section path 5 and body text 1. Entities are kept on each chunk's record, and the entity index the
> code declares for linking passages that share a name (`EntityIndexService`) is never filled, because nothing calls
> its indexing functions.
> `[evidence_level: code_verified, confidence: exact, evidence_source: SQLiteFullTextService.swift:242-253, 1458-1461, EntityIndexService.swift:92-139]` `[evidence_level: grep_verified, confidence: exact, evidence_source: nothing calls indexChunks, and indexChunk is called only inside it, grep run 2026-10-20]`

#### Step 4. Check it fits

> **In plain words**
> Make sure the card actually fits on the card. Write too much and the extra doesn't spill onto a second card, it falls off the edge and vanishes, with no warning. So it gets measured first. This step does not make citations more precise: they point at the whole card, with its page and a short quote, not at an exact sentence.

**How.** A Rust-backed tokenizer validates every chunk against the 510 word-piece ceiling before embedding. In code the check splits any chunk over 430 tokens (the 510 less 80 kept for the prefix) into parts of at most 420, each labelled `[Part N]`. `[evidence_level: code_verified, confidence: exact, evidence_source: DocumentProcessor.swift:6766-6773, 6880-6960]`

**Why.** Exceeding the limit does not raise an error, it silently truncates, producing an embedding of the first 510 tokens filed under the identity of the whole chunk. That is silent index corruption and nothing downstream can detect it. The chunker in step 2, not this pass, records each chunk's character positions in the extracted text, and no citation carries them: a citation names the chunk, with its page and a quote of up to 240 characters.

#### Step 5. Turn meaning into coordinates

> **In plain words**
> This is the one genuinely strange idea in the app, and it's worth getting.
> Imagine a map where things sit near each other if they *mean* similar things. "Dog" and "puppy" are neighbours. "Dog" and "tax return" are on opposite sides of town. Now imagine that map has 384 directions instead of two, because meaning is more complicated than north and east.
> Every card gets a pin on that map. Later, your question gets a pin too, and the app grabs the cards pinned nearby. That's how it finds "SAE 0W-20 synthetic" when you asked "what oil does my car take," even though those two phrases share no words at all.
> The map has no neighbourhoods filed in advance. To find the nearby pins, the app measures the distance from your question's pin to every pin there is, which is quick arithmetic for a computer.

**How.** 384-dimensional sentence embeddings from a bundled MiniLM model, generated on the device through Core ML or Apple's newer Core AI framework. From 5.7 a new library on iPhone and iPad uses the Core ML copy, which Core ML schedules on the Neural Engine where the device has one, and a new library on a Mac with macOS 27 uses the Core AI copy, which runs on the GPU. A library keeps the copy it was built with.

**Why 384.** Small enough that a whole library's vectors stay memory-mappable on a phone and similarity is a vectorised dot product rather than a search problem.

**A constraint worth knowing.** Chunk size, overlap and strategy can change mid-library without harm, because similarity is still defined across mixed chunks. Changing the embedding model or vector width changes the coordinate space itself; mixing widths makes similarity meaningless. So embedding changes are blocked during ingestion and require a full rebuild.

#### Step 6. File it twice, and leave bookmarks

> **In plain words**
> File every card **twice**: once alphabetically by the words on it, once by its pin on the meaning-map. Two systems because they fail in opposite ways. Alphabetical is perfect for "part number 4021-B" and useless for "how do I keep this thing running." The meaning-map is the reverse.
> Also drop a bookmark every few pages. A big PDF on a phone gets interrupted constantly, and without bookmarks you'd start from page one every time. The bookmark has to remember the document's *identity*, not just the page, or you end up filing a second copy of the same document.

**How.** Lexical tokens go to SQLite FTS5 with a Porter tokenizer and BM25 ranking. Dense vectors go to a memory-mapped binary store using cosine similarity. Both are isolated per library. The full-text index is written twice: the whole cleaned document and each of its pages before the text is cut into chunks, then each chunk after its vector is stored. The Porter tokenizer stems words and folds case, so the word index matches forms of a word, not only its exact spelling. The vectors are appended to one flat file in the order chunks arrive, with no index over them. `[evidence_level: code_verified, confidence: exact, evidence_source: DocumentProcessor.swift:1003-1015, RAGService.swift:7879-7895, 7936-7986, SQLiteFullTextService.swift:242-253, BNNSVectorDatabase.swift:1036-1048]` Page-level JSON checkpoints carry a stable document ID. Documents over 10MB use a streaming lane, 15 pages at a time, flushing after each batch. From 5.7, text and JSON Lines files over 8 MB are read the same way, in pieces of about 2 MB, with a checkpoint after each piece.

**Why two indexes.** Dense retrieval is strong on meaning and weak on exact strings such as part numbers and proper nouns. BM25 is the inverse. Running both and fusing them is cheaper and more reliable than making one arm do both jobs.

> **In plain words**
> **Skim before committing.** The app flips through the first ten pages before deciding how big to make the cards, because a physics textbook and a novel want different-sized cards, and redoing it later is the most expensive mistake available.
> **Deleted means deleted.** If you have the app on a phone and a laptop and delete a document on one, the other must not helpfully restore it. So deletions leave a note saying "this was removed on purpose," and that note wins any argument between devices.

**Predictive pre-scan.** Before page one, the first 10 pages or 10,000 characters are analysed for code and mathematics patterns, list and table density, multi-column layout and vocabulary characteristics. A chunking plan is resolved from those signals and applied to this document and subsequent imports, so the configuration is not discovered to be wrong after paying to embed everything. (Corrected 2026-10-20: every size the plan suggests, 280 to 420 words with 50 to 70 words of overlap, is above the chunker's ceilings, so chunking clamps it to a 260-word target and 50 words of overlap. What the plan still changes is its strategy. For code, mathematics or structured content it sets the minimum chunk size to 60 words, for multilingual text to at least 100, and either one turns topic detection on, which the code preset otherwise leaves off. Plain prose keeps its document type's preset. `[evidence_level: code_verified, confidence: exact, evidence_source: AdaptiveEmbeddingOptimizer.swift:296-336, DocumentProcessor.swift:1054-1077, SemanticChunker.swift:286-388 (presets and recommended(for:strategyOverride:)), RAGService.swift:10270-10280 (chunkingOverride)]`)
**Deletion-wins tombstones.** The ingestion queue is an iCloud-coordinated file, so a document dismissed on one device could otherwise be resurrected by a stale snapshot from another. Removal writes a bounded tombstone that is merged before queue items and survives an empty queue. Automatic index repair is single-flight and sequential, and is suppressed per library until an explicit import clears it.

## 03. Answering a question

*Six phases, listed in the order they run. Every stage below was read out of the shipped code rather than from a specification, so the numbering is the app's own and it has gaps and letters where stages were inserted between existing ones over time.*

*This is Standard's path, the default for a new install. Deep Think and Maximum leave it before step 0 and run their own front end and reading loop, described in section 07 (corrected 2026-10-20). `[evidence_level: code_verified, confidence: exact, evidence_source: SettingsStore.swift:616-624, RAGService.swift:11577-11595]`*

> **On the number 23**
> The app is usually described as a 29-step pipeline, six for reading a document and 23 for answering a question. That 23 counts steps 1 through 9 of the published specification, leaving out a step 0 that warms a vocabulary cache before any question exists and a step 10 that draws the finished answer on screen, since neither is part of turning a question into an answer.
> **The shipped code actually runs more than that.** Five stages below appear in no specification: two vocabulary expansions at 1.5b and 1.5c, a section boost at 3.5, cross-reference resolution alongside 4.6, and the specification-table search at 4.8. One documented stage, extractive answering at 5.10, is switched off. All of them are described here anyway, because the point of this page is what the app does rather than what was written down about it.
> **Corrected 2026-10-20: more stages than 5.10 do not run.** Query expansion at 1.5, and with it 1.5b and 1.5c, which sit inside it, runs in no mode. So does contextual compression at 4.7, and extractive summaries at 5.9 cannot run. Each step below says why. `[evidence_level: grep_verified, confidence: exact, evidence_source: usesQueryExpansion is read only at RAGService.swift:11649 and usesContextualCompression only at 11654, both in Standard's path, besides a logging dictionary and a Settings screen, and step 5.9's condition is at 15391, grep run 2026-10-20]`

> **In plain words**
> 1. **Work out what was actually asked.**
> 2. **Go find candidate cards**, both filing systems at once.
> 3. **Be picky about which ones survive.**
> 4. **Arrange them on the desk**, in a specific order, because that turns out to matter.
> 5. **Write the answer, then fact-check it.**
> 6. **Show it with sources you can tap.**

### Phase A · Understand the question

> **In plain words**
> People don't ask questions using the words that are in the document. You say "what oil does my car take," the manual says "SAE 0W-20 synthetic, 5.3 quarts." Not one word in common. The meaning search (step 2) is what bridges that gap. In Standard the app keeps your own words for the search, and asks the AI to reword a question only when it's genuinely unclear. In Deep Think and Maximum it writes the question a few different ways and searches each one (section 07).

Questions and documents do not share vocabulary. Embedding the raw question searches the wrong region of the space, so this phase reshapes it first. (Corrected 2026-10-20: the plain-words block above said that "before searching anything, the app rewrites the question a few different ways". In Standard the reshaping is narrow. A lookup is kept literal, any other question is rewritten by the model only when it reads as ambiguous, and the expansion steps below run in no mode. `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:11978-11984, 12117, QueryRewriterService.swift:83-90, RAGQualityMode.swift:237-243]`)

#### Step 1. Resolve what the question refers to

> **In plain words**
> Work out what "it" means. "What about the second one?" isn't searchable until you know what the second one *is*, so the app looks back at the conversation.

**How.** Pronoun resolution, normalisation and entity labelling. Conversation memory retains 5 turns in Standard, 10 in Deep Think and 20 in Maximum.

(Corrected 2026-10-27 against `1e4a718`: no mode keeps 5, 10 or 20 turns. Those are the values of `RAGQualityMode.maxConversationTurns`, which the app reads in one place, Standard's question rewriting, as `min(value, 3)`. Conversation memory runs on its default configuration, the only one the app uses: once it holds more than 8 turns it keeps the 3 it rates most important word for word, in time order, and folds the rest into a summary of at most 1,000 characters. The rewrite, when it runs (Phase A above), reads the questions of the last 3 turns memory holds. Standard's prompt carries at most 3 turns, chosen by relevance to the question once more than 2 are held, each reply cut to 300 characters or less, then as much of the summary as the budget allows and up to 5 key topics; with nothing in memory it falls back to the last 4 messages of the chat. Memory is on by default, and no Settings screen has a switch for it. Deep Think and Maximum read no conversation memory and no chat history: they return to `executeAgenticQuery` above both reads, and `AgenticOrchestrator` refers to neither. The exception is a precise-value question whose Deep Think or Maximum run fails for a model reason (unavailable, rate-limited, busy or a failed generation): Standard answers it again, and that run reads both. `[evidence_level: code_verified+grep_verified, confidence: exact, evidence_source: RAGQualityMode.swift:298-310, 315-337 (featureToggles also lists the value and has no caller, by git grep); RAGService.swift:11704 (the only other read of maxConversationTurns), 12028-12041 (when the rewrite runs), 12057-12095 (rewriting, min(value, 3)), 15790-15827 (prompt injection and the 4-message fallback), 11635 (agentic return), 10817-11413 (executeAgenticQuery), 11383-11396 and 20511-20525 (the precise-value fallback to Standard); ConversationMemoryService.swift:134-140 (default: 3 turns, 1,000 characters, threshold 5), 226-230 (configure(with:) has no caller), 296, 363-399 (turns by relevance, replies cut to 300, summary), 402-427 (key topics), 508-539 (the 3 kept, in time order, and the summary cap); SettingsStore.swift:567 (default true) and git grep enableConversationMemory (no Settings view reads it); git grep for ConversationMemory, conversation and history in AgenticOrchestrator.swift (no read)]`)

#### Step 1.5. Ask it several ways

> **In plain words**
> Ask the same question in several forms at once, using words the app learned from your own documents. Six versions in the fast mode, twelve in the thorough one. Several rough guesses beat one confident guess.
> **Corrected 2026-10-20: this step never runs.** Standard, the fast mode, has it switched off, so your question goes into the search as you typed it. Deep Think and Maximum have it switched on, but they leave this path before they reach it. They ask the question several ways in their own way instead: the app writes up to five versions and runs a full search for each one (section 07). `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:11577-11595, 12117, AgenticOrchestrator.swift:339, 1916-2061]`

**How.** Query variants generated from corpus and library vocabulary: up to 6, 8 or 12 by mode. Each variant is embedded separately, so expansion precedes embedding rather than following it.

**In code, this block runs only when the mode enables query expansion.** Standard does not (`usesQueryExpansion` is false), and Deep Think and Maximum, which do, return into the agentic orchestrator before this step. So steps 1.5, 1.5b and 1.5c run in no mode. Deep Think's and Maximum's own searches build a wider keyword query, the phrasing plus synonyms from the library's corpus vocabulary and up to five gazetteer terms, but in a library with its full-text index, the normal case, the keyword search runs the phrasing as written and tries the wider query only when that finds nothing. The vector half embeds the phrasing as written. `[evidence_level: code_verified, confidence: exact, evidence_source: RAGQualityMode.swift:237-252, RAGService.swift:11577-11595, 12117-12222 (steps 1.5 to 1.5c), 21876-21940 (performFullRetrievalPipeline), HybridSearchService.swift:246-261, 1230-1265 (searchWithFTS5)]` `[evidence_level: grep_verified, confidence: exact, evidence_source: usesQueryExpansion is read only at RAGService.swift:11649, grep run 2026-10-20]`

#### Step 1.5b. Add words this library uses

> **In plain words**
> Every library has its own dialect. A car manual, a medical file and a legal contract all name things differently. The app learns each library's vocabulary as it indexes, and expands the question using words from *that* library rather than generic synonyms.

**How.** Per-container vocabulary expansion, drawing on terms learned during ingestion from this library specifically. (Corrected 2026-10-20: this sits inside step 1.5's block and runs only with it, so in no mode. `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:12153-12175]`)

#### Step 1.5c. Add known domain terms

> **In plain words**
> On top of what it learned from your files, the app has prepared lists of terms for common subject areas, and pulls in the relevant ones.

**How.** Gazetteer-based domain vocabulary enrichment, layered on top of the corpus and container expansions. (Corrected 2026-10-20: in Standard's path this sits inside step 1.5's block too, so it runs in no mode there. Deep Think's and Maximum's own searches add up to five gazetteer terms to a wider keyword query, which the keyword search tries only when the phrasing as written finds nothing. `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:12176-12195, 21912-21922, HybridSearchService.swift:1253-1265]`)

#### Step 1.6. Work out what kind of question it is

> **In plain words**
> "What's the tyre pressure" is a look-up-a-number question. "How do I replace the filter" is a follow-the-steps question. "Summarise this" is a whole-document question. Each needs a different approach, so the app decides which it's facing before doing anything else.

**How.** Five intents: lookup, procedure, compare, summarize, general QA.

**Why.** Intent conditions the rest of the pipeline. Lookup gets a specification boost and can bypass generation entirely. Summarize routes to hierarchical summaries. Compare gets multi-hop handling. Without it, one pipeline shape serves five question shapes badly.

> **Corrected 2026-10-20.** The code has eight intents, chosen by keyword rules with no model call: lookup, table lookup,
> procedure, compare, summarize, investigate, compute and findings. A question that matches no rule counts as
> investigate. What each one changes: a lookup or table lookup is kept literal, gets the specification-table search
> and is packed as its best passage plus matching sentences (step 5), and an extracted value can replace the model's
> answer afterwards. Generation itself is bypassed only by Deep Think's and Maximum's shortcut for exact values
> (section 07). Summarize, findings and investigate questions get up to three document summaries beside the detail
> passages. Investigate, compare and findings questions get the graph-style packing of step 4.9. There is no summary
> hierarchy (step 2.5).
> `[evidence_level: code_verified, confidence: exact, evidence_source: QueryEnhancementService.swift:64-146, 342-660, RAGService.swift:12246, 13885-13930, 14558, 16502-16529]`

> **A deliberate default that looks like a bug**
> In the fast mode, several of these rewriting features are switched **off**. That is intentional. A hypothetical answer invented by a small model can pull an exact-value lookup off target, and an automated rewrite can drift away from a literal question. So the modes that need breadth enable them, and the mode that needs precision keeps the question literal.
> **Corrected 2026-10-20.** The query expansion and the hypothetical answer (HyDE) that Deep Think and Maximum switch on sit in this path, and those two modes leave it before reaching them, so no mode runs them. Deep Think and Maximum get their breadth from their own search phrasings instead (section 07). Standard's model rewrite stays on for a question that is not a lookup and reads as ambiguous. `[evidence_level: grep_verified, confidence: exact, evidence_source: usesHyDE is read only at RAGService.swift:11645 and usesQueryExpansion only at 11649, both in Standard's path, besides a logging dictionary and a Settings screen, grep run 2026-10-20]`

### Phase B · Find candidates

#### Step 2. Put the question on the map

> **In plain words**
> Pin the question to the meaning-map, so the app can see which cards are pinned nearby.

**How.** Each variant becomes a 384-dimensional vector in the same space as the chunks, from the same provider at the same width. (Corrected 2026-10-20: in Standard there are no variants, so the question becomes one vector. In Deep Think and Maximum each search phrasing becomes one vector inside its own search. No mode embeds a hypothetical answer (HyDE): Standard has it off, and Deep Think's searches embed the phrasing itself. `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:12280-12292, 12363, 21864-21868, RAGQualityMode.swift:189-195]`)

#### Step 2.5. Route whole-library questions to summaries

> **In plain words**
> If the question is about the *whole* library rather than one fact in it, don't go looking for individual cards. No ten cards can tell you what a hundred documents are about. Go to the summaries instead. It's the difference between "what's on page 40" and "what is this, generally."

**How.** Global or summary-shaped queries route to summary nodes built during chunking rather than to leaf chunks. Retrieval happens at whichever level of the hierarchy the question lives at.

> **Corrected 2026-10-20.** There is one level, not a hierarchy, and it is not built during chunking. Each document
> gets one overview aimed at 120 words or fewer (cut at 150), written by Apple's on-device model after the document is
> saved (through 5.6, before the save), stored as a single summary passage, with content tags and suggested questions
> beside it. If the model fails or times out, the document's first 150 words are used as its overview. The cluster and
> library levels are declared in the code and never built. When summaries exist and the router reads a question as an
> overview with a confidence of 0.5 or more, the search runs over the summary passages instead of the detail ones.
> Summaries are on by default, and so is the routing.
> `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:8291-8360 (enrichImportedDocument), 12434-12496 (step 2.5), DocumentSummaryService.swift:232-319, DocumentChunk.swift:89-104, SettingsStore.swift:571-574]` `[evidence_level: grep_verified, confidence: exact, evidence_source: .clusterSummary and .librarySummary appear only in their own declarations, grep run 2026-10-20]`

#### Step 3. Search both systems and merge

> **In plain words**
> Search both filing systems at once, then merge the two lists.
> Merging is trickier than it sounds. The two systems score things on totally different scales, like one judge marking out of 10 and another out of 100, except nobody knows the scales. So the app **throws the scores away** and keeps only the *rankings*. Anything both systems put near the top wins. The two scoring systems never have to be made to agree, which is fortunate, because they can't be.

**How.** BM25 over FTS5 and cosine similarity over the vector store run in parallel, and the two ranked lists merge by Reciprocal Rank Fusion at *k* = 60. Candidate depth starts at 30, 35 or 50 by mode and scales with library size.

(Corrected 2026-10-20.) The fusion is weighted: each list adds its weight divided by (60 + rank + 1). The weights are the library's, 0.50 and 0.50 by default, moved by the question's search intent and clamped between 0.35 and 0.65, so a lookup searches at 0.45 for meaning and 0.55 for words. The keyword arm searches the question itself, as the model reworded it when it was rewritten, and in the user's own words when it was translated for the vector search. A third list of table rows joins for specification and state questions. In Standard the depth starts at 30 or more, rises with library size, and goes to 50 or more when the cloud route is open, and two caps follow. A trivial question off the cloud route is held to 15. The device-pressure cap (section 07) holds a question of three words or fewer without a question mark to 10, a complex one to 50, any question to half its device tier's limit under critical memory pressure, and to 10 on a critically hot device. Deep Think's searches take 15 passages per phrasing and fuse them to 20 (section 07), and Maximum's big gather takes 50 plus 20 per rewording. `[evidence_level: code_verified, confidence: exact, evidence_source: HybridSearchService.swift:1209-1245, 1320-1341, RAGEngine.swift:1024-1040, QueryProfileService.swift:39-55, QueryEnhancementService.swift:44-57, RAGService.swift:11978-11980, 12625-12635, 11730-11745, AdaptivePipelineOptimizer.swift:204-260, 324-375, 606-632, AgenticOrchestrator.swift:2205-2265, 8045-8100]`

**Why rank fusion rather than score blending.** BM25 scores and cosine similarities are on incomparable scales with no stable mapping between them, so any weighted sum needs calibration that drifts per corpus. Rank fusion discards the scores and uses only position, which makes it calibration-free.

#### Step 3.5. Boost cards whose section fits the question

> **In plain words**
> Promote cards whose section heading matches what was asked. A card from a chapter called "Maintenance Schedule" is a better bet for a maintenance question than one from the middle of the warranty terms, even if the words happen to line up.

**How.** Section metadata boost, applied to the fused result set before reranking. This is the stage reported as `boosted` in the per-stage retrieval measurements further down.

### Phase C · Decide what survives

#### Step 4. Re-sort with a slower, better reader

> **In plain words**
> Now a slower, pickier reader looks at the question and each candidate card *side by side* and re-sorts them properly.
> Why not use the picky reader from the start? Because it's slow. Reading the question against every card in the library would take forever. So: a fast rough method narrows thousands of cards to fifty, then the slow careful method sorts those fifty. (Corrected 2026-10-20: in the code the shortlist is usually around a hundred cards, and up to 250 in a big library. `[evidence_level: code_verified, confidence: exact, evidence_source: RAGEngine.swift:334, RAGService.swift:12625-12631]`) Skim to shortlist, read to rank. That two-speed pattern is the backbone of the whole design.

**How.** A bundled Core ML cross-encoder rescores the fused candidates, degrading to a term-proximity heuristic if the model is unavailable rather than failing. (Corrected 2026-10-20: the shortlist is larger than fifty. The cross-encoder reads up to the smaller of the candidate count and max(100, min(250, topK × 5)), and Standard hands it about three times its depth. `[evidence_level: code_verified, confidence: exact, evidence_source: RAGEngine.swift:302-336, RAGService.swift:12625, 13070]`)

**Why.** The retrieval embedder encodes question and chunk separately and never sees them together. A cross-encoder runs attention over the pair, which is far more accurate and far too slow to run over a whole library. That asymmetry is precisely why the architecture retrieves first and reranks second.

#### Step 4.3. Discard the weak candidates

> **In plain words**
> A mediocre card on the desk is worse than an empty slot, because the app will use it and then cite it, and now there's a real-looking source that doesn't actually support the answer.

**How.** Candidates below a safety margin are pruned, on the reasoning that a weak chunk in context produces a citation pointing somewhere real but irrelevant.

#### Step 4.4. Spread across sources

> **In plain words**
> Don't let one document hog the desk. If a question spans three files and all five slots went to file one, the answer is confidently incomplete.

**How.** Source diversity is enforced separately from semantic diversity, because two chunks from two different documents can still be close in embedding space.

#### Step 4.5. Remove near-duplicates

> **In plain words**
> Taking the five best-scoring cards often gets you five copies of the same paragraph, because whatever made one score well made its neighbours score well too. So each new card has to earn its slot by being good *and* by saying something the chosen ones don't.

**How.** Maximal Marginal Relevance, which scores relevance to the query minus similarity to what is already selected. λ is 0.60, 0.55 or 0.50 by mode; the thorough mode favours breadth.

> **Corrected 2026-10-20.** λ is the library's own setting, 0.6 in the default preset (0.8 in High Accuracy, 0.5 in
> Exploratory and Technical Manual), raised to at least 0.85 for a procedure in Standard. The per-mode values 0.60, 0.55
> and 0.50 (`RAGQualityMode.mmrLambda`) go only into a logging dictionary that nothing reads. In Standard, MMR keeps
> the search depth (step 3, usually 30 or more), not five, and packing decides how many reach the model. Through 5.6
> this step changed nothing: the store hands passages back without their vectors, so MMR found every pair 0 alike.
> 5.7 loads the stored vectors first.
> `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:13667-13710, 21989-22000, 8877-8883, KnowledgeContainer.swift:262-305]` `[evidence_level: grep_verified, confidence: exact, evidence_source: RAGQualityMode.mmrLambda is read only into featureToggles (RAGQualityMode.swift:320), which nothing reads, grep run 2026-10-20]`

### Phase D · Arrange the desk

> **In plain words**
> Everything left goes on the desk. But the desk is tiny, so how it's arranged changes the answer. This phase is entirely about arrangement.

#### Step 4.6. Bring the neighbouring cards too

> **In plain words**
> For every card that survived, also grab the couple of cards on either side.
> Small cards are great for *finding* things and bad for *reading*. The card that matched often starts mid-argument, and the sentence that qualifies it ("...but only on models before 2019") is on the next card. So the app searches small and reads big.

**How.** Each surviving chunk is expanded with siblings from the same page or section: 2, 3 or 5 per side by mode. Expansion applies its own literal-text redundancy check so it cannot reintroduce duplicates.

**Why this runs after de-duplication rather than before.** It looks backwards, since expanding to adjacent text seems to reinject the redundancy just removed. It isn't. Diversity is enforced at *selection*, so the anchor chunks cover distinct topics; expansion then restores local context around each anchor, and siblings never compete for anchor slots. Two redundancy mechanisms operate at two levels, one in meaning-space for choosing and one in literal text for assembling.

#### Step 4.6b. Follow cross-references

> **In plain words**
> If a card says "see section 7.3," go and get section 7.3. Documents point at themselves constantly, and an answer built from a card that defers to another page is an answer that stops right before the useful part.

**How.** Cross-reference resolution, run alongside sibling expansion so that referenced sections are pulled in rather than left dangling. (Corrected 2026-10-20: in Standard this runs only for lookups and table lookups. Deep Think and Maximum follow cross-references for every haul, before they grade it. `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:14249-14275, AgenticOrchestrator.swift:515-536]`)

#### Step 4.8. Hunt directly for specification tables

> **In plain words**
> This one exists because of a measured flaw in the careful reader from step 4.
> That reader **prefers prose to tables.** Shown a paragraph and a table that answer the question equally well, it scores the paragraph roughly two and a half times higher. Which is a disaster for exactly the questions where tables matter most: dosages, torque specs, prices, legal section numbers.
> So for those questions the app runs a separate, blunt search that ignores meaning-matching and ignores the careful reader entirely, and just hunts for cards where the question's distinctive words sit next to numbers. That pattern is the signature of a specification table.

**How.** Targeted spec retrieval, internally the "Spec Table Sniper". It bypasses both semantic similarity and reranker scoring, searching all chunks for co-occurrence of discriminative query keywords with numeric or structured data. It runs for lookups and table lookups in Standard, and for those and precise-value questions in Deep Think's searches and its shortcut for exact values (corrected 2026-10-20). `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:14285-14308, 22013-22025, 10683-10687]`

**Why it exists.** The cross-encoder carries a measured prose bias, scoring roughly 0.78 for prose against roughly 0.30 for tables. Reranking is a net gain overall, but it systematically demotes exactly the content that answers specification, dosage, statute-number and financial-figure lookups. This stage routes around its known weakness rather than trying to retune it.

#### Step 4.7. Cross out the irrelevant sentences

> **In plain words**
> A card might hold four hundred words and only two useful sentences. The rest is taking up desk space and distracting the reader.

**How.** Query-irrelevant sentences are dropped per chunk. Enabled in Deep Think; disabled in the fast mode, where losing a detail from an exact-value lookup is the greater risk, and in the thorough mode, which has the budget to keep everything.

> **Corrected 2026-10-20: this step runs in no mode.** The compression code sits in Standard's path, where Standard has
> it switched off. Deep Think's mode setting switches it on, but Deep Think leaves that path before this step, and its
> own searches have no compression step. Maximum has it off.
> `[evidence_level: code_verified, confidence: exact, evidence_source: RAGQualityMode.swift:277-284, RAGService.swift:11577-11595, 14323-14506 (step 4.7), 21799-22165 (performFullRetrievalPipeline)]` `[evidence_level: grep_verified, confidence: exact, evidence_source: usesContextualCompression is read only at RAGService.swift:11654 in Standard's path, besides a logging dictionary and a Settings screen, grep run 2026-10-20]`

#### Step 4.9. Add a small map

> **In plain words**
> Note at the top of the desk which section each card came from and which names connect to which. Cheap context that helps the reader orient.

**How.** Entity paths, section outlines and reference tags are packed under an explicit token budget. This is graph-*style* packing over deterministic entities, not a derived knowledge graph, and the app does not claim otherwise. (Corrected 2026-10-20: it runs only for investigate, compare and findings questions. Its budget is 24,000 tokens when the cloud route is open, and otherwise three quarters of the device's window, between 1,500 and 6,000 tokens (5.7, where 5.6 used 6,000 on every device). `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:14558-14580, 3741-3753, QueryEnhancementService.swift:126-133]`)

#### Step 5. Put the best material at both ends

> **In plain words**
> Put the best cards at the **very top and the very bottom** of the pile, and the weaker ones in the middle.
> This sounds like superstition. It isn't. Language models pay much more attention to the start and end of what they're given and genuinely skim the middle, the same way you remember the first and last items on a shopping list. The effect is big enough to lose an answer that was right there. So this runs dead last, after every decision about *what* is on the desk is settled, because it's the only step about *where* things sit.
> **Corrected 2026-10-20.** That is the design, and the code differs in two ways. For a look-up-a-number question the first desk gets no shuffle: the single best card goes on top, whole, and the rest of the desk is filled with the sentences from other cards that mention what was asked. (If the desk has to be laid out again for the phone, which happens when the first pass was sized for the cloud and the answer stays on the phone, or a cloud request is denied, the cards are shuffled after all.) For other questions the shuffle happens before the app decides which cards fit, so the second-best card can end up at the bottom of a pile that's too tall and fall off the desk. That's a known bug. `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:14946-15058, 15834-15902, RAGEngine.swift:500-503]`
> **Corrected 2026-10-27.** That bug was fixed the next day, in 5.7. The app now picks the cards that fit in order of rank, best first, and only then shuffles the ones it picked, so the second-best card is never the one that falls off. With about three cards on a phone's desk there is no shuffle at all. `[evidence_level: code_verified, confidence: exact, evidence_source: fa80e71 (2026-10-21, in v5.7.0); RAGEngine.swift:496-501 and 683-691 at 1e4a718]`

**How.** The final chunk set is reordered by position so the highest-scoring evidence sits at the beginning and end. A set ranked [1,2,3,4,5,6] is emitted as [1,3,5,6,4,2].

**Why it is last.** It is a positional decision, so it runs after every content decision is final. Any stage that added or removed a chunk afterwards would undo it. The general rule the pipeline follows: content decisions first, position decisions last.

> **Corrected 2026-10-20: what reaches the model depends on the kind of question, and the reorder is not last.**
> - **How big the desk is.** In a 4,096-token window the app leaves about 3,190 tokens for passages, about 4,470
>   characters at its 1.4 characters a token, as logged on the owner's iPhone 16 Pro Max when the cloud route was not
>   open. That holds about three passages, trimmed at a sentence end where needed so that at least three fit. On the
>   default Hybrid route with a network, Standard first sizes this context for the cloud instead, a 32,768-token
>   window at 2.5 characters a token and at most 45,000 characters, and if the plan then keeps the answer on the
>   device it packs again, as whole passages, to what the device's window has left (section 05).
> - **A lookup** (not a procedure) gets no reorder in its first pass. From 5.7 the passage retrieval ranked first goes
>   in whole as [S1], taking up to three fifths of the budget, and sentences from the other candidates that match the
>   question fill the rest. Through 5.6 a lookup got the matching sentences only. When the context has to be packed
>   again for the device (a cloud-sized first pass whose answer stays on the device, or a denied request), it goes
>   through whole-passage packing like any other question, reorder included.
> - **A procedure** keeps document order.
> - **Every other question** goes through whole-passage packing, and there the reorder runs over all the candidates,
>   often 30 or more, *before* the cut to the budget. With about three passages fitting, the prompt holds ranks 1, 3
>   and 5, and rank 2, last in the reordered list, is cut. The rescue pass that adds sentences from dropped passages
>   reads the original order starting after the number packed, so it skips rank 2 too. That is a known defect, read
>   in the code and not yet run.
> - **In Deep Think and Maximum** each search reorders its own results with separate code, labelled as putting the
>   best passages at both ends. It puts the even ranks first and the odd ranks after them, [2, 4, 6, ..., 1, 3, 5, ...],
>   so the best passage lands in the middle. The fusion of the search phrasings then reads that order as a ranking.
>   Read in the code and the loop worked through by hand, not run in the app.
> - The [1,3,5,6,4,2] pattern above is what happens when exactly six passages are retrieved and all six fit.
> `[evidence_level: artifact_derived, confidence: high, evidence_source: the 3,190-token figure is a device log line (Context budget: base=4096 ... available=3190, 2026-10-16) quoted in the comment at RAGService.swift:3745-3747, not re-measured here]` `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:14784-14849 (the budget), 14946-15058 (packing), 3779-3803 (the whole first passage), 15834-15902 (the repack), 22121-22134 (Deep Think's reorder), AgenticOrchestrator.swift:2224-2258 (fusion by position), RAGEngine.swift:475-565, 779-799. The rank-2 loss and the Deep Think reorder are read in the code, not run]`

> **Corrected 2026-10-27 against `1e4a718`: the "Every other question" bullet above describes the code before
> `fa80e71` (2026-10-21, shipped in 5.7).** Whole-passage packing now chooses passages in rank order until the budget
> is spent, and only then places the ones it chose: best first, second best last, the rest in between, and only when
> four or more were chosen and the question is not a procedure. With about three passages fitting, the prompt holds
> ranks 1, 2 and 3 in that order; a passage skipped as a near-duplicate gives its place to the next rank. The rescue pass reads the candidates after the last one packed, so it no longer
> skips rank 2. The [1,3,5,6,4,2] pattern is what six chosen passages get. The Deep Think and Maximum bullet still
> holds: their per-search reorder is separate code that this commit did not change, and six results still come out
> as [2, 4, 6, 1, 3, 5].
> `[evidence_level: code_verified, confidence: exact, evidence_source: git show fa80e71 (merge-base: in 8f9621b, the 5.7 build, and in tag v5.7.0); RAGEngine.swift:496-501 (no reorder before the budget), 620-622 (a near-duplicate is skipped and the loop goes on), 683-691 (placement when packed.count >= 4), 785-804 (applyLostInMiddleReordering); RAGService.swift:14995 (off for a procedure), 4304-4317 (candidatesPastThePacked) and 15105 (the rescue reads it), 22192-22205 (Deep Think's reorder, loop worked through by hand)]`

#### Step 5.9. Assemble summaries directly for overview questions

> **In plain words**
> For "summarise this," build the answer by assembling the relevant passages rather than asking the model to compose from scratch. Faster, and it can't drift from the source.

**How.** Extractive paragraph assembly, conditioned on a summarize intent. (Corrected 2026-10-20: this step cannot run. Its condition asks for a summarize question that is also extractive-first, and only lookups and table lookups are extractive-first, so a summarize question always goes to the model. `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:15386-15391, QueryEnhancementService.swift:116-123]`)

#### Step 5.10. Extractive answers: built, then switched off

> **In plain words**
> There used to be a shortcut here: for a plain "what's the number" question, copy the number straight out of the table instead of asking the AI. It sounds obviously right, and at this step it was **turned off**, because it guessed wrong too often. Asked for fuel tank capacity, it once answered "three-quarters" because that phrase sat near the right words.
> **The same shortcut still runs at other points in the pipeline.** For a question that asks for a value, Deep Think and Maximum try it before the AI does anything, and in Standard it can replace the AI's answer afterwards. Nothing checks it when it is wrong: on 2026-09-25 it answered a question about a lease's notice period with "1 lb" from an air fryer manual.

**Status.** **Disabled at this step.** Step 5.10's own code path is commented out (`RAGService.swift:13350`). The recorded reason: heuristic extraction produced false positives, returning "three-quarters" for a fuel-tank-capacity query, and bypassed the model entirely when it fired.

**Still live elsewhere.** The same extractor answers at five other call sites of `RAGService.highPrecisionLookupOverrideAnswer`. The 5.4 source calls it in these places:

- Deep Think and Maximum return a locked span before the orchestrator runs. Step 4.8's targeted retrieval feeds one of those calls (`:8705` and `:8734`, reached from `:8904`).
- A locked span replaces the answer an agentic run generated (`:9199`).
- Standard replaces the model's answer after generation when the question is a lookup (`:14383`).
- The reliability fallback uses it when generation fails (`:15192`).

A locked answer skips the source-only check (`:17293`). The scoring rules, and what an 18-question probe found about them, are in `Docs/RETRIEVAL_PIPELINE.md` item 22. `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift at the lines named, read 2026-09-26; the 2026-09-25 device incident]`

The same five call sites in the working tree at 22:11 on 2026-10-20 (5.7): the shortcut before the orchestrator at `RAGService.swift:10688` (over the specification-table search's passages) and `:10717` (after one full retrieval), the agentic answer replaced at `:11194`, Standard at `:16504`, and the reliability fallback at `:17331`. The commented-out step 5.10 is at `:15470`, and the source-locked skip at `:19524`. From 5.7, Standard keeps the model's answer when it already states the extracted value. The lock is 0.82, or 0.90 when an extractive attempt is forced. `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift at the lines named, EvidenceScoringPolicyService.swift:82-84, read 2026-10-20]`

**Corrected 2026-09-26.** This section said "every query proceeds to model generation" and "every question now goes through the model". Under "What replaced it" it said that exact-value questions are "served by targeted retrieval at step 4.8 rather than by a generation bypass", and that "the model still writes the answer, so a wrong extraction becomes a wrong *candidate* that the verification checks can catch, instead of a wrong answer that skipped them". That holds for step 5.10's own path only. The claims are withdrawn rather than deleted, so the record shows what was claimed.

### Phase E · Write it, then check it

#### Step 6. Generate the answer

> **In plain words**
> Finally, write the answer using only what's on the desk.
> One detail worth knowing: the desk is shared by everything, not just your pages. The instructions, the list of tools the AI is allowed to use, the pages, and the answer being written all come out of the same four pages of room. The tool list alone eats about a quarter of it. So once the app has already fetched the right pages, it puts the tool list away, because advertising tools that are no longer needed is the most wasteful thing it could do.

**How.** The packed prompt goes into an Apple `LanguageModelSession` within the window the device reports (4,096 tokens in Apple's documentation, 8,192 on a Mac with macOS 27). Temperature is 0.4 in the standard modes and 0.3 in the most precise one. Tool schemas are removed once context has already been assembled, since they cost roughly 1,000 of the available tokens.

(Corrected 2026-10-20.) Before this call the post-retrieval planner picks the route: on device, Private Cloud Compute, or a refusal (section 05). The answer streams into the chat as it is written, through structured generation when the estimate fits 3,600 tokens and a plain stream otherwise, so it is on screen before step 7.5 runs. In Deep Think and Maximum no call is ever handed tools, and each step's temperature is its own value when it sets one, else the question's adaptive profile, else 0.5 (Maximum's sessions use 0.7, then 0.5, then 0.3). `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:14769-14775, 15779-15934 (route plan), 18752-18794 (structured generation), FoundationModelStructuredGenerator.swift:117-158, ChatScreen.swift:3291, AgenticOrchestrator.swift:9157-9185, 6886-6894]`

(Corrected 2026-10-27 against `1e4a718`: the temperature sentence in the How line above. Only Standard applies a mode temperature, and it applies it as a ceiling: `min(current, 0.4)`. It caps the temperature at 0.2 instead when it uses the evidence-first prompt for low-confidence retrieval, and at 0.2 for a library whose retrieval style is `.precise` (High Precision in Library Settings). Maximum's 0.3, and Deep Think's 0.4, in `RAGQualityMode.temperature` are never read: the app reads that value once, below the line where Deep Think and Maximum return to `executeAgenticQuery`. Maximum's own loop sets 0.7 for sessions 1 to 3, 0.5 for sessions 4 to 8 and 0.3 after that. `[evidence_level: code_verified+grep_verified, confidence: exact, evidence_source: RAGService.swift:15733-15735 (evidence-first, 0.2), 15738-15739 (mode cap), 15741-15745 (.precise, 0.2), 11635 (agentic return), 11686 (the only read of qualityMode.temperature by git grep, besides featureToggles at RAGQualityMode.swift:337, which has no caller); RAGQualityMode.swift:95-101; AgenticOrchestrator.swift:6894-6902]`)

(Corrected 2026-10-27 against `55fea8e`: "or a refusal" in the first note above. In Standard the planner's refusal is not what you see when reliability mode is on, its default: the reliability fallback answers from the same passages instead. Section 05's note under the ladder says what happens, and section 04's last note what it shows. `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:15966-15985, 17268-17296, 17384-17679; SettingsStore.swift:534-535]`)

#### Step 6.5 / 7. Tidy up and score it

> **In plain words**
> Fix the formatting, since small models produce broken bullet lists often enough that repairing them is cheaper than asking nicely. Then score how well the answer came out, which feeds the confidence number later.

**How.** Markdown normalisation, list indentation repair and output-structure enforcement, followed by a synthesis quality score that feeds calibration. (Corrected 2026-10-20: the score at step 7 reads the retrieval, not the answer: the top passage's reranked score, how many passages there are and how many sources. That score is the confidence the answer carries, adjusted only when the source-only check runs. For a lookup or a precise-value question, the extracted-value override also runs here, and can replace the model's answer when the answer does not already state the value (5.7, where 5.6 replaced it whenever a value locked). `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:16502-16545, 16845-16909, RAGEngine.swift:802-836 (assessResponseQuality)]`)

#### Step 7.5. Run the nine checks

> **In plain words**
> The fact-checker. Nine separate checks, run on the finished answer against the pages on the desk, before you see any of it. Full list in the next section.
> **Corrected 2026-10-20.** By the time the checks run you've usually watched the answer being written, so they don't come before you see it. They run once, on the finished answer, and put a label on it. Only in Standard, and only when the checks score badly enough, does the app take the answer back and refuse instead. `[evidence_level: code_verified, confidence: exact, evidence_source: ChatScreen.swift:3291, RAGService.swift:16568-16734]`

**How.** Nine deterministic verification gates, always local. Detailed in the next section. They run once, after generation, and are not run again: a failure never sends the answer back to be written again. In Standard they also decide which claims the Fact Check list under the answer keeps. `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:16568-16734 (step 7.5), 16846-16854, StructuredAnswer.swift:979-1047]`

#### Step 8 / 8.1. Package it and calibrate the confidence

> **In plain words**
> Bundle the answer with its citations, then convert the app's raw internal score into the confidence percentage you actually see. That conversion matters: a raw score of "0.8" doesn't mean "right 80% of the time," and showing it as though it did would be a lie with a number attached.
> **Corrected 2026-10-20.** The conversion is computed, but the app doesn't put it on the answer. It appears only as one of the steps in the thinking timeline. The confidence the answer carries is still the raw score from step 7. `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:16749-16776, 16969]`

**How.** The answer, citation index map and evidence record are assembled, then Platt scaling maps the raw quality score toward something closer to a probability. Calibration is only ever as good as the data it was fit on. (Corrected 2026-10-20: the calibrated probability is written to the log and shown as a thinking step, and the response is built with step 7's score. `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:16749-16776 (step 8.1), 16845, 16969]`)

### Phase F · Show it

#### Step 9 / 10. Render with tappable sources

> **In plain words**
> Show the answer with citations that point to the card each claim came from, with its page and a short quote, rather than to an exact sentence. The cards and their pages were made back when the document was read. Nothing in this app is only one component.

**How.** Timings, token footprint, cache hits and thermal state are recorded, then the answer renders with inline citation controls that resolve to a source chunk and its page rather than to an exact span; no citation carries byte or character offsets.

## 04. The nine checks

*Every answer is verified against its own evidence before it is shown. All nine checks are deterministic and run on your device, even when the writing happened elsewhere.*

> **Corrected 2026-10-20 against the working tree (`b868fc0` plus the 5.7 work in progress).** The checks run once, on
> the finished answer, after it has streamed into the chat, and they label it. Which answers they run on:
> - **Standard:** every answer with passages behind it. If any check fails, the answer is refused only when
>   reliability mode is off (it is on by default) or the average of the checks' scores falls below the mode's bar,
>   0.50 in Standard and 0.25 for a lookup. Otherwise it is shown labelled `unverified:` with the checks it failed,
>   and its badge reads Unverified. Nothing is retried. The text you read stays the answer as written, but the claim
>   list under it (Fact Check) leaves out every claim Gate B marked unsupported, and with reliability mode off an
>   answer whose claims Gate B all marked unsupported is shown as a refusal.
> - **Deep Think and Maximum:** in 5.6 these answers skipped the nine checks and read Not Checked unless the
>   source-only check ran. From 5.7 the nine checks run once at the end as a label, and never refuse or rewrite these
>   answers. The exception is a lookup not locked to an extracted value: it gets the source-only check instead, which
>   can rewrite the answer or, for a precise-value or state question, replace it with a refusal.
> - **The shortcut for exact values** (section 07) returns a value with no checks at all, so it reads Not Checked.
> - In Standard, a lookup that is shown after its checks failed then gets the source-only check: two more on-device
>   sessions that draft and rate claims from the passages, and the result can replace the answer, or refuse it when
>   the question asks for a precise value or a state. A lookup whose checks passed skips it.
> `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:16568-16734 (step 7.5), 16864-16909, 11212-11262, 18200-18253 (verifyAgenticAnswer), 19494-19631 (sourceOnlyOutcomeIfNeeded), 20072-20089 (resolvedDisplayResponse), StructuredAnswer.swift:979-1047 (sanitizeForVerification), GroundedAnswerView.swift:71-99, ConfidencePolicyService.swift:48-54, SettingsStore.swift:534-535, SourceOnlyAnswerService.swift:360-440, VerificationOutcome.swift:33-60, MessageBubbleV2.swift:715-745]`

> **In plain words**
> In plain terms the nine checks ask: *did it find anything good enough to answer with? does every sentence trace back to a page? do the numbers match? do the pages contradict each other? does the answer actually resemble what the pages say? did it mix up two similar-looking things? is it well formed? did it answer the whole question or only half? are these pages even about the same subject?*
> Fail an important one and the app refuses to answer rather than guessing.
> **Corrected 2026-10-20.** Not every check reads the answer. Some look at how well the search went, or at the pages alone. And failing doesn't usually mean a refusal: in Standard the app refuses only when the checks score badly overall, and otherwise shows the answer marked Unverified. In Deep Think and Maximum the checks only label the answer. A separate source-only check, run on look-up questions, can still rewrite or refuse an answer after it's written. `[evidence_level: code_verified, confidence: exact, evidence_source: VerificationGateService.swift:159-276, RAGService.swift:16660-16706, 11212-11262]`

| Check | Name | What it verifies |
|---|---|---|
| `A` | Retrieval Confidence | The best evidence clears a threshold *and* beats the runner-up by a margin. A high top score with no margin means the ranking did not actually discriminate. It reads the retrieval scores, not the answer. |
| `B` | Evidence Coverage | Every claim maps to a specific piece of evidence. Uncited assertions are the definition of ungrounded. |
| `C` | Numeric Sanity | Numbers in the answer appear in the sources. Checked against all retrieved candidates, not just the packed set, so a correct number that lost a packing slot is not falsely flagged. From 5.7 Apple's data detector also reads amounts, dates and measurements, and an amount the sources state only in another currency, another day of a month they give, or a value they state only with other units fails it. |
| `D` | Contradiction Sweep | Conflicting evidence across the retrieved set, including negation. It compares the passages with each other and does not read the answer. |
| `E` | Semantic Grounding | How closely the answer resembles the evidence in meaning, on both an absolute and a relative threshold, plus a topical alignment check. The strongest of the nine. Skipped when the passages' stored vectors can't be loaded. |
| `F` | Quote Faithfulness | Catches an abbreviation being expanded using a different document that happened to be in the same context. |
| `G` | Generation Quality | Structural soundness of the output itself. It reads the answer alone. |
| `H` | Answer Completeness | Multi-step and comparison answers where each step is individually plausible but the chain is not supported end to end. It needs the question's type, which Standard does not pass it, so in Standard it always passes. Deep Think and Maximum pass the type (5.7). |
| `I` | Domain Isolation | Rejects evidence drawn from unrelated subject areas before an answer is written. Relaxed when everything came from one document, since that is not mixing. From 5.7 it steps in only for a question that reads as lab science, two or more of its study-domain keywords as whole words; before, keywords matched inside everyday words ("um" in "number") and right answers about travel documents failed it. |

> **Corrected 2026-10-27** against `1e4a718`: rows A and B say more than the gates check. **Gate A** passes when the
> top retrieval score reaches the threshold, and nothing else. It computes the margin over the runner-up and writes it
> into the gate's details marked "info only"; the code's note reads "Margin requirement removed - multiple
> high-scoring chunks is GOOD, not bad". A separate helper that does require the margin, `checkRetrievalConfidence`,
> has no caller, and it is the only code that applies the margin threshold, so the per-mode margin raised in
> `ConfidencePolicyService` changes nothing. **Gate B** does not require every claim to map to evidence. It scores a
> supported claim 1 and a partly supported claim 0.5, and passes when that weighted share of the answer's claims is at
> least 0.40. With structured claims the bar is 0.55, and at least 80% of the claims must also carry a citation. Only
> Standard passes structured claims, so Deep Think and Maximum answers are always held to 0.40. Headings and claims
> worded as questions are left out before counting, and an answer with no claim left to check passes Gate B outright.
> `[evidence_level: code_verified+grep_verified, confidence: exact, evidence_source: VerificationGateService.swift:180 (Gate A is runGateA), 294-319 (runGateA; the margin is "info only" at 311), 279-288 (checkRetrievalConfidence; git grep finds no caller, and muMargin is applied only at 285; ConfidencePolicyService.swift:43 reads it only to raise it), 333-359 (headings and question-like claims dropped), 361-371 (no claims: passed), 391 (weighted coverage), 397 (structured: 0.55 and 0.80), 410 (otherwise 0.40); ConfidencePolicyService.swift:43; RAGService.swift:16685-16695 (Standard passes structuredClaims) and 18295-18304 (Deep Think and Maximum do not)]`

Thresholds rise with mode: 0.50 in Standard, 0.60 in Deep Think, 0.80 in Maximum. Failing a critical check produces a grounded abstention rather than a hedged answer.

> **Corrected 2026-10-20.** The bars 0.50, 0.60 and 0.80 exist, halved for a lookup with a floor of 0.25, and only
> Standard's refusal rule reads them, because Deep Think and Maximum answers are labelled and never refused. The
> gates themselves also tighten with the mode: the retrieval thresholds rise by 0.05 in Deep Think and 0.10 in Maximum
> (capped at 0.60, or 0.75 for a sensitive question), and the margin and grounding thresholds by half that.
> A failing critical check (A, C or E) does not by itself produce an abstention. The code marks such a result
> `shouldAbstain`, and that flag only adds a line to the answer's notes on missing evidence. The decision is the
> Standard rule above. So the checks that actually compare the answer with the passages are B, C, E and F, while A
> reads retrieval scores, D compares passages with each other, G reads the answer alone, H is inactive in Standard,
> and I, from 5.7, engages only for questions that read as lab science. Gate I's row above says it rejects evidence
> "before an answer is written". It runs with the other eight, after the answer is written, and reads the question
> and the passages, not the answer.
> `[evidence_level: code_verified, confidence: exact, evidence_source: VerificationGateService.swift:159-276, 426-480, 513-536, 887, 979-1050, ConfidencePolicyService.swift:22-58, RAGService.swift:16622-16706, StructuredAnswer.swift:974-976, DomainIsolationService.swift:141-146]`

> **Corrected 2026-10-27** against `55fea8e` (the 5.7 code): the list at the top of this section leaves out Standard's
> reliability fallback. When Standard's path throws after retrieval has found passages, the planner's abstain included
> (section 05, rung 1), or when the model returns an empty answer, and reliability mode is on, its default,
> `buildReliabilityFallbackResponse` writes the answer instead. The refusal rule above does not apply to it. What it
> shows:
> - **An extracted value** when one locks (a lookup or precise-value question): no model call and no check, so it
>   reads Not Checked.
> - **Otherwise a second on-device answer** over up to 6 of the passages, at most 3,600 characters, with Private Cloud
>   Compute off. The nine checks run on it once, and only when some passage scores above 0. If A, B, C, E or F fails,
>   up to 6 excerpts replace it, under "Here are the most relevant excerpts from your documents", and read Not
>   Checked. Otherwise the model's answer is shown and reads Partially Verified, whether or not D, G, H or I failed,
>   and also when the checks were skipped.
> - **If that call fails**, the same excerpts.
>
> After a planner abstain the outcome follows from the scores. The planner abstains only when every passage scores
> under 0.20, the fallback keeps those scores, and Gate A's bar in Standard is 0.40 (0.55 for a sensitive question).
> So the person gets the extracted value when one locks, the model's answer read Partially Verified when no passage
> scores above 0, and excerpts read Not Checked otherwise.
> `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:11894, 13015, 15182 (the fallback's passages), 16537-16559 (empty answer), 17268-17296 (the catch and reliabilityModeEnabled), 17384-17434 (extracted value, reliability_extractive_override), 17436-17459 (6 passages, 3,600 characters, device only), 17469-17547 (checks only with a score above 0), 17556-17572 (the five gates that bring excerpts), 17574-17607 (reliability_fallback), 17609-17679 (excerpts, excerpts_only), 20104-20135 (buildExtractiveChunks keeps each score); VerificationOutcome.swift:33-60 (reliability_fallback reads partial, excerpts_only and reliability_extractive_override read notChecked); VerificationGateService.swift:95-97 (0.40 and 0.55), 180 and 294-319 (Gate A); ConfidencePolicyService.swift:28-30, 41 (Standard adds nothing); ModelExecutionPlan.swift:104-106; SettingsStore.swift:534-535; read 2026-10-27, nothing built or run]`

> **Known behaviour worth stating**
> The checks are currently tuned conservatively enough that they sometimes hedge an answer that is correct and fully supported. In one measured case the verifier lowered its confidence because the answer did not supply a date and a name that the source documents never contained and the question never asked for. That trade is deliberate in direction, if not in degree: the app errs toward under-claiming rather than over-claiming, and tightening it is ongoing work.

## 05. Where your data goes

*Reading, indexing, searching and verifying all happen on your device. Only the final writing step can ever use Apple's Private Cloud Compute, and only with your explicit approval of a specific payload.*

*(Corrected 2026-10-20: "the final writing step" is Standard's one answer, or in Deep Think and Maximum the steps that write an answer, unless Private Cloud Compute is picked in the model picker, when their reasoning sessions can go too. "Explicit approval" is asked per request until you choose Always Allow or set Allow without asking. Details below, after the ladder. `[evidence_level: code_verified, confidence: exact, evidence_source: AgenticOrchestrator.swift:9157-9240, RAGService.swift:4391-4440]`)*

> **Superseded 2026-09-20: this runs for real users now**
> Private Cloud Compute shipped in **5.2** on 2026-09-10 and is live on both platforms. Apple's `PrivateCloudComputeLanguageModel` requires the iOS 27 SDK, which means Xcode 27, and Xcode Cloud's one workflow is pinned to the Xcode 27 release, build `27A266a`. The twelve `#if compiler(>=6.4)` sites therefore compile in, and the archive gate fails a 5.2-or-later build that carries zero `PrivateCloudCompute` symbols, so a toolchain regression cannot quietly take it back out.
>
> **What that replaces, kept because the record is the point.** From 2026-08-21 this section carried a correction headed *this has never run for a real user*: every build that had reached the App Store was compiled with **Xcode 26.6**, without the iOS 27 SDK, and took the on-device path unconditionally. That was true of every release up to and including 5.1. It was found by tracing the release toolchain rather than the code, and it is why the routing described below is written as *built and gated correctly* rather than assumed.

> **In plain words**
> Sometimes a question is too hard for the phone. There's a bigger service available, but using it means some of your text leaves your device.
> Most apps decide that *before* looking at anything, which means asking permission to send something nobody has seen yet. This one works the other way round on purpose. It finds your pages first, works out the smallest possible bundle it would need to send, **shows you that exact bundle**, and only then asks. Say no and it answers on your device instead.
> And the fact-checking never leaves. Even when the writing happens elsewhere, the checking happens here.
> **Corrected 2026-10-20.** What the request shows is the bundle's size, not its text: Show Details lists how many passages and characters would go, the payload's size, and why the cloud is needed. A new install starts on Hybrid, with Private Cloud Compute set to Ask when needed, so it asks each time until you choose Always Allow. After that, or with Allow without asking chosen in Settings, it sends without asking. `[evidence_level: code_verified, confidence: exact, evidence_source: CloudConsentPromptView.swift:170-197, SettingsStore.swift:50, RAGService.swift:4391-4440]`

### Routing after retrieval, not before

Three settings are available: On-Device, Hybrid and Private Cloud Compute. Hybrid does not decide up front. Local retrieval runs first and produces an evidence set; only then is a route selected, using that evidence together with entitlement state, live model availability, quota, network status, foreground state and exact token budgets.

(Corrected 2026-10-20.) A new install starts on Hybrid (stored as Automatic), and the separate Private Cloud Compute permission starts at "Ask when needed" (its other choices are "Never use" and "Allow without asking", which 5.6 names "Allow for Deep Think and Maximum" although it allows every mode). At send time the chat turns Hybrid into "prefer cloud" with Private Cloud Compute allowed. `[evidence_level: code_verified, confidence: exact, evidence_source: SettingsStore.swift:50, 453-461, LLMModel.swift:215-231, 246-268, ChatScreen.swift:3177-3190]`

Two reasons for that ordering. You cannot know whether a question needs more capability until you have seen what the evidence looks like, so routing on the question alone is guessing. And you cannot minimise a payload before you know what is in it, so consent asked in advance is consent to an unknown envelope.

### The decision, in the order it is actually made

The planner is a strict priority ladder, and the order matters more than any individual rule. The first condition that matches wins.

| # | Condition | Result |
|---|---|---|
| 1 | Evidence is insufficient | **Abstain.** Cloud use is prohibited outright, not merely skipped |
| 2 | You selected On-Device | Local. No further conditions are consulted |
| 3 | You selected Private Cloud Compute | Cloud only if entitlement, availability, quota, network and either foreground or prior consent all hold. Otherwise local, with the specific blocking reason recorded |
| 4 | The answer is an exact value and nothing contradicts it | Deterministic local path |
| 5 | Cloud is disallowed by privacy settings | Local |
| 6 | Otherwise (Hybrid) | Cloud only if the payload fits *and* either the evidence overflows the local window or the question needs multi-document synthesis in a non-Standard mode. Otherwise local |

Two consequences of that last rule are worth stating because they are easy to assume wrong. **Standard mode never escalates to the cloud on difficulty alone**; it escalates only when the evidence physically does not fit on device. And escalation additionally requires the minimized payload to fit the cloud budget, so a query too large for both stays local.

> **Corrected 2026-10-20: when each mode can reach Private Cloud Compute.** The ladder above matches the code. What it
> means per mode:
> - **When the route is decided.** After retrieval, per model call. Standard plans once, just before its answer is
>   written. Deep Think and Maximum plan inside every call made through their consent path
>   (`generateWithProperConsent`). Their helper calls run on a fresh on-device session, which never plans and never
>   leaves the device.
> - **Standard.** On Hybrid with a network, and permission not refused, Standard prepares its first context for the
>   cloud: 50 or more candidates and a 32,768-token window at 2.5 characters a token, at most 45,000 characters. If that
>   context does not fit what the device's window leaves (about 3,190 tokens on the owner's iPhone, a device-log figure,
>   step 5), rung 6 picks Private Cloud Compute when it is usable, and the request asks first. "Usable" means supported, entitled,
>   available and within quota, which needs iOS or macOS 27 and a build compiled with Swift 6.4 or later. Otherwise,
>   or after a denial, the context is packed again as whole passages to fit the device. Multi-document synthesis never
>   qualifies in Standard, because rung 6 counts it only outside Standard.
> - **Deep Think and Maximum.** Every reasoning session, research decision and running answer is pinned to the device,
>   and the helper calls (search phrasings, the relevance check, title routing) always run on a separate on-device
>   session. Only the calls that write an answer can be planned to Private Cloud Compute: Deep Think's synthesis,
>   Maximum's final synthesis and refinement, the exhaustive synthesis, the single synthesis of a moderate or low
>   haul, the decomposed pipeline's synthesis, research's closing synthesis when its rounds run out, and the
>   synthesis that follows a failed self-critique on the no-retrieval path. There, an answer drawing on more than one
>   document qualifies by itself. With Private Cloud Compute
>   picked in the model picker, the pin is lifted and the sessions can go too, each behind the same permission.
> - **On the device instead.** With On-Device picked, offline, in the Simulator, on iOS or macOS 26, with Never use
>   chosen, or when the quota is used up, every call runs on the device. A request you deny is written on the device
>   too.
> - **Rung 4's "deterministic" result** is handled like an on-device plan: the model still writes the answer, on the
>   device (`RAGService.swift:15877`, `AgenticOrchestrator.swift:9328`). The only value path that skips the model
>   altogether is Deep Think's and Maximum's shortcut (section 07), besides the reliability fallback when generation
>   fails (step 5.10).
> `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:11730-11745, 14516-14545, 14784-14849, 15779-15934 (route plan), 18400-18569 (makePostRetrievalModelPlan), 4391-4440 (ensureCloudConsentIfNeeded), QueryRuntimeCoordinator.swift:145-186, ModelExecutionPlanner.swift:24-135, ModelExecutionPlan.swift:146-148, FoundationModelSessionFactory.swift:84-110, AgenticOrchestrator.swift:9123-9152, 9157-9240, and the unpinned calls at 1535, 1607, 2778, 3209, 5857, 5939, 7432, 7482]` `[evidence_level: artifact_derived, confidence: high, evidence_source: the 3,190-token figure, a device log quoted at RAGService.swift:3745-3747]`

> **Corrected 2026-10-27** against `1e4a718`: rung 4 never fires in the app. The planner reaches it only when the
> evidence it is given says `requiresExactExtraction`, and the one place the app builds that evidence,
> `makePostRetrievalModelPlan`, always passes `false`. Standard's plan and every planned call in Deep Think and Maximum
> go through that function, so the "deterministic" result is reached nowhere, tests included: the one test that sets
> `requiresExactExtraction` also sets `requiresPCC`, so rung 3 wins and the test expects Private Cloud Compute. The
> 2026-10-20 note above, that it is handled like an on-device plan, describes what would happen and does not happen.
> `[evidence_level: code_verified+grep_verified, confidence: exact, evidence_source: ModelExecutionPlanner.swift:45 (rung 3) and 69-72 (rung 4); RAGService.swift:18507-18517 (the only PostRetrievalEvidence built in app code, requiresExactExtraction: false at 18515), 18588 and 18627 (the only makePlan calls, both in that function), 15855 (Standard's call), AgenticOrchestrator.swift:9277 (generateWithProperConsent's call); ModelExecutionPlannerTests.swift:217-229 (testCloudOnlyOverridesAutomaticExactExtractionShortcut); git grep over Swift: requiresExactExtraction otherwise only at ModelExecutionPlan.swift:101 and ModelExecutionPlannerTests.swift:56, 64, and no test names .deterministic]`

> **Corrected 2026-10-27** against `55fea8e` (the 5.7 code): rung 1 is the planner's decision, and what you then see
> depends on the mode. In Deep Think and Maximum a planned call that abstains returns a fixed refusal ("I couldn't
> find enough supporting evidence in this library to answer that reliably") without calling the model. In Standard
> the abstain is thrown as an error. With reliability mode on, its default, the reliability fallback catches it and
> answers from the same passages instead of refusing: an extracted value when one locks, and otherwise a second
> on-device call told "Answer using any available excerpts. If evidence is thin, say so", whose answer the nine checks
> then keep or replace with excerpts (section 04 has the outcomes). With reliability mode off the chat shows "I
> couldn't work out how to answer that from what your documents returned. Try rephrasing." The cloud half of the rung
> holds either way: the fallback's call runs on the device with Private Cloud Compute off. In Standard the planner can
> abstain only when every passage packed for the answer scores under 0.20 and the question has passed the relevance
> gate before it; how often that happens has not been measured.
> `[evidence_level: code_verified+grep_verified, confidence: exact, evidence_source: ModelExecutionPlanner.swift:37-40; ModelExecutionPlan.swift:104-106; RAGService.swift:15343-15346 (relevance gate), 15840-15863 (Standard plans over the packed passages), 18498 (the top score is their maximum), 15966-15985 (abstain thrown as routingAbstained), 11896 and 17268 (the do and catch around Standard's path), 17278-17296 (reliability mode sends it to buildReliabilityFallbackResponse), 17321 (otherwise rethrown), 17451-17459 (device only, PCC off, the prompt); ChatScreen.swift:3939-3942 (the chat's text); SettingsStore.swift:534-535 (reliability on by default); AgenticOrchestrator.swift:9350-9385 (Deep Think's and Maximum's refusal); git grep for routingAbstained over Swift finds only RAGService.swift:15985, 21714, 21733 and ChatScreen.swift:3939; read 2026-10-27, nothing built or run]`

### The shape of the plan itself

The privacy guarantee is not a convention that separate code paths happen to honour. Every plan is constructed with the same three stages and only the middle one is variable:

| Stage | Target |
|---|---|
| Retrieve | always deterministic and local |
| Synthesize | the routed target, the only stage that can leave the device |
| Verify | always deterministic and local |

The fallback attached to a cloud plan is always local and is explicitly marked as non-retrying, so a failed cloud attempt degrades once rather than oscillating.

### What the minimized payload actually is

> **In plain words**
> Not your document. Not even the full set of pages the app found. It takes the pages in order of how relevant they were, gives each one a character allowance, cuts each to that length, and stops when the budget runs out. It also counts how many pages it had to leave out, so the number you approve is honest about what it excludes.

Chunks are sorted by rank and each is granted an allowance of at most the total budget divided by the number of chunks capped at eight, with a floor of 240 characters, then truncated to it. The envelope records both its total character count and the number of chunks omitted. Availability and quota are rechecked immediately before the session is created, after consent rather than before.

### Fail-closed capability checks

The capability snapshot that feeds all of the above is deliberately pessimistic. In the Simulator, cloud support reports as unsupported with an explicit reason. Without a valid signed entitlement, quota reports as *unknown* rather than as available. Any future quota state the SDK might add that this code does not recognise also maps to unknown. Unknown never authorises cloud execution. The on-device context size is read from the SDK at runtime rather than assumed, and if the cloud context size cannot be read the snapshot marks itself partial rather than exact, so a budget decision made on incomplete information is labelled as such.

### The badge tells you what happened

> **In plain words**
> The little badge on each answer isn't a label for what you asked for, it's a record of what actually happened. If you chose the cloud and the cloud was unavailable so your device answered instead, the badge says so. The app is not allowed to imply a route it didn't take.

Each answer carries an execution receipt recording intended, attempted, actual, fallback and completed targets separately. The badge is computed from the receipt, so a cloud request served locally displays as an on-device fallback while the receipt preserves the original intent. On iOS and macOS 26 the app is local-only and never presents local execution as cloud execution.

## 06. Which AI actually answers

*The app tells you where a question ran. It deliberately does not tell you which model version served it, because that is not something any app can currently verify.*

> **In plain words**
> The AI doing the writing isn't part of this app. It's Apple's, built into the operating system. Apple doesn't tell apps which version they got or how large it is, and there's no way to ask.
> So this app never claims to know. It says "this ran on your device" or "this ran in the cloud," which are both things it can genuinely verify, and it stops there. Plenty of apps quote a model size. This one would rather only say what it can check.

- Local generation targets `SystemLanguageModel.default`. Cloud generation targets `PrivateCloudComputeLanguageModel` on iOS and macOS 27 or later.
- Apple's public Foundation Models SDK **exposes no model-size selector**. Session construction accepts a default model, a use case (a task selector, not a size selector), or an adapter. There is no API to request a specific variant and no API to observe which one served a request.
- Apple's own published figure for the on-device model is approximately 3 billion parameters, from their Foundation Models technical report. That is Apple's number about Apple's model, not a claim this app makes about its own routing.
- The larger on-device model announced at WWDC26 is real but managed by the operating system, with no developer-facing selection or observation.
- Accordingly the app labels routes rather than asserting parameter counts, and a continuous-integration check watches for the day Apple exposes selection.

> **Re-checked against the installed SDK on 10 August 2026**
> These are not claims carried forward from an old note. Each line below was compiled against `iPhoneSimulator27.0.sdk` today. A statement that something is *absent* is only worth as much as the check behind it, so here is the check.

> **Why the context window matters more than the size**
> The number that actually shapes this app is not parameter count, it is the context window: 4,096 tokens in Apple's documentation, 8,192 on a Mac with macOS 27. That is what makes retrieval quality decisive: with a small window there is nowhere to hide mediocre retrieval, because the model only ever sees what the pipeline chose to give it. A larger window would let several stages of this pipeline be deleted. It would also make the retrieval quality invisible.

## 07. Thinking in loops

*For harder questions the app does not run the pipeline once. Deep Think and Maximum search several ways first, read what they found across several fresh sessions with notes carried between them, and write the answer from the notes. Going back out for more comes after the reading, when the notes show a gap or the answer reads like a miss. Maximum's one big gather is the exception, because it comes before its reading.*

> **Corrected 2026-10-20** against the working tree (`b868fc0` plus the 5.7 work in progress). This section said the app
> "goes back out" between trips, picks "which tool to reach for" and "chooses its own tools", stops for "either" of two
> reasons, and turns "fifty separate lookups" into one piece of work. In the code no Deep Think or Maximum call is
> handed a tool, Deep Think's sessions read slices of one search and never search while they read, Deep Think stops
> early only when three conditions hold together or the model says the answer is complete (the two separate reasons
> belong to Maximum's own loop), and fifty is Maximum's ceiling, not Deep Think's. The rest of this section is rewritten from the code, with the lines
> cited at each part. The dated stop-rule measurements are kept as history.
> `[evidence_level: code_verified, confidence: exact, evidence_source: AgenticOrchestrator.swift, AgenticPolicyService.swift, RAGService.swift at the lines named below, read 2026-10-20, nothing built or run]`

> **In plain words**
> An ordinary app follows a fixed recipe: do A, then B, then C, then stop. This one makes a few choices while it works: how to word its searches, which sections to read first, when it has read enough, and sometimes what to search for next. It never picks up a tool. Every search is run by the app's own code.
> Picture the librarian on a hard question. First they search the shelves several ways at once and come back with one stack of cards. Then they read the stack a few cards at a time, at a clean desk each time, writing notes as they go. When the stack is read, or they're sure enough, they write the answer from their notes. Only if the notes show part of the question still unanswered, or the answer looks like a miss, do they go back to the shelves. (Maximum fetches one bigger stack before it starts reading.) **Deciding when to stop** is the hard part.

### Which modes loop, and how a question gets in

> **In plain words**
> Only Deep Think and Maximum loop. You pick one from the mode menu, or tap Go Deeper under a Standard answer to send that question through the loop. The app never moves a Standard question into the loop by itself.

A new install starts in Standard, which answers in one pass and has no loop (section 03, `SettingsStore.swift:616-624`). The live ways in are the mode menu (Deep Think or Maximum) and Go Deeper, which asks the last question again with the agentic path forced (`RAGService.swift:11370-11385`, `QueryRuntimeCoordinator.swift:213-216`). Go Deeper keeps the mode the chat is in, so from Standard it runs the loop on the device's Deep Think budget without Deep Think's Self-RAG check, which needs the Deep Think mode (`AgenticOrchestrator.swift:199-208`). A third way, planner escalation from Standard, is in the code and switched off whenever Apple's model service writes the answer, which is the case wherever Apple Intelligence is available. The other model services are a placeholder that refuses every request when it isn't, and stand-ins for UI tests and Simulator screenshots (`QueryRuntimeCoordinator.swift:209-211`, `RAGService.swift:11501`, `2320-2350`). `[evidence_level: grep_verified, confidence: exact, evidence_source: the LLMService types are AppleFoundationLLMService, AppleFoundationLLMServiceUnavailable, ScreenshotMockLLMService and a UI-test StandInModel, and the local-server services sit inside #if false, grep run 2026-10-20]` Deep Think and Maximum leave Standard's pipeline before any of its steps run (`RAGService.swift:11577-11595`). Deep Think runs on the device's own budget (below) and Maximum on a fixed one (`RAGService.swift:10863-10872`). If a run fails with an error on a precise-value question, the question is asked again in Standard (`RAGService.swift:11333-11348`).

### A shortcut for exact values

> **In plain words**
> If the question asks for one exact value, like a phone number or a torque figure, the app first tries to copy it straight out of your documents. If it finds one it's sure of, you get that value at once: no reading sessions, no AI writing, and no fact-checks, so the answer is marked Not Checked.

For a lookup or a precise-value question that is not conceptual, Deep Think and Maximum first run the specification-table search over every passage the question can draw on, and the value extractor on what it finds. If nothing locks, they run one full retrieval (the mode's depth with a floor of 24 passages, so 35 in Deep Think and 50 in Maximum, at a 0.03 similarity floor) and try the extractor again. A value that scores at the lock (0.82) is returned at once, with no session, no model call (the source-only check declines a source-locked answer) and none of the nine checks. Its status, `agentic_precision_extractive_override`, reads as Not Checked on the badge. Otherwise the orchestrator starts. `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:10561-10737 (executeAgenticPrecisionLookupIfAvailable), 10899-10912, 19524, EvidenceScoringPolicyService.swift:82-84, VerificationOutcome.swift:33-60, MessageBubbleV2.swift:722]`

### Before any session: searching several ways

> **In plain words**
> The app writes up to five ways of putting your question, searches your library in full for each one, and merges the results into one stack of the twenty best cards. It checks the stack is actually about your question, and stops with "I couldn't find that" if it plainly isn't. Then it grades the stack, and the grade decides what happens next. Only a strong stack gets the reading sessions. A middling or weak one gets a single written answer from what was found.

First a heuristic planner, with no model call, decides whether the question needs documents at all, and if not, the model answers it on the device without them, unless a word-based self-critique, also with no model call, finds the answer ungrounded, when one search and one synthesis follow (`AgenticOrchestrator.swift:296-305`, `3357-3510`, `3527-3544`). Otherwise, in order:

1. **Search phrasings.** Up to 5. They are the planner's own when it has 3 or more or reads the question as a direct lookup, and otherwise come from one on-device call of 200 tokens, with fixed phrasings as the fallback (`AgenticOrchestrator.swift:339`, `1916-2061`).
2. **A full search for each phrasing**, through Deep Think's own retrieval function at 15 passages and a 0.05 floor. Each one does summary routing for an overview question, embeds the phrasing (no HyDE), builds a wider keyword query from synonyms, the library's vocabulary and up to five gazetteer terms, which the keyword search tries only when the phrasing as written finds nothing, and runs the hybrid search, the cross-encoder, MMR with the library's λ, the similarity floor, the specification-table search for lookups and precise values, neighbouring passages within the on-device budget, and a reorder meant to put the best passages at both ends, which in fact puts the best one in the middle (step 5). It has no contextual compression (`RAGService.swift:21799-22165`, `HybridSearchService.swift:1230-1265`).
3. **Fusion.** The lists are fused by reciprocal rank (k = 60), counting each passage's place in its reordered list, each passage is scored 0.6 by its best reranker score and 0.4 by its normalised fusion score, and the top 20 are kept. If the phrasings found nothing, the original wording is searched again (`AgenticOrchestrator.swift:346-386`, `2185-2300`).
4. **Relevance gate.** A top score above 0.6, or half of the question's keywords found in the passages, passes with no model call. Under 10% of the keywords found fails. In between, one on-device YES or NO call decides. When the keyword overlap is under 10% and the intent check fails, the run ends with an answer saying the information wasn't found in your documents. An intent failure on an excellent or good stack downgrades it to moderate (`AgenticOrchestrator.swift:390-462`, `2306-2365`).
5. **More passages.** A moderate or low stack gets graph expansion: one on-device call names up to three search terms found in the passages, and each gets a full search of 4 passages. Every stack gets its cross-references followed (`AgenticOrchestrator.swift:487-536`, `2524-2600`).
6. **Quality band**, from the stack's scores against the device's escalation threshold (`AgenticPolicyService.swift:99-126`). On an A18 (threshold 0.40) excellent means a top score above 0.50 and a top-three average above 0.40, good means above 0.35 and 0.27, and moderate means a top score above 0.20 or a top-five average above 0.17. In Maximum (threshold 0.50) excellent needs above 0.60 and 0.50.

| Band | Deep Think | Maximum |
|---|---|---|
| excellent | The reasoning chain, then research rounds if coverage fell short, then the Self-RAG check | Maximum's own loop, then one Self-RAG 2.0 check |
| good | One reworded search, then the reasoning chain, then the Self-RAG check. No research rounds | One reworded search, then the reasoning chain with Maximum's settings. No Self-RAG check |
| moderate | One reworded search, then **one** synthesis call. No chain | The same |
| low | Speculative RAG (three candidate answers), and if that falls short of its bar, a decomposed pipeline for a many-sided question or one broader search, then one synthesis. No chain | The same |

So **the reading sessions run only on an excellent or good stack** (`AgenticOrchestrator.swift:544-1143`). From 5.7 Deep Think's Self-RAG check runs on every device, where through 5.6 an A17 Pro skipped it (`AgenticOrchestrator.swift:199-208`).

### Choosing tools

> **In plain words**
> In Deep Think and Maximum the AI is never handed a tool. It can't decide to search, open a document or count something. The app's own code does all the searching. What the AI decides is smaller: how to word the searches at the start, which sections to read first, and, in a research round, whether to answer now or which words to search for next. It writes that choice out as text, and the code acts on it.

Six tools are registered with Apple's framework: retrieve evidence, inspect a document, compare a topic across documents, a library overview, count a pattern and search an exact pattern (`FoundationModelToolRegistry.swift:326-378`). Two of Apple's own, OCRTool and SpotlightSearchTool, are added on iOS and macOS 27 only when the hidden settings `systemTools.ocr.enabled` and `systemTools.spotlightSearch.enabled` are on, and nothing in the app turns them on (`FoundationModelToolRegistry.swift:259-321`, `381-386`). A session gets them only when its call leaves tools on (`FoundationModelSessionFactory.swift:24-32`). No Deep Think or Maximum call does. Every chain session sets `disableToolsForSession = true`, every other call through `generateWithProperConsent` passes `disableTools: true`, and the helper calls (search phrasings, the relevance check, title routing, rewording) run on a fresh model service with no tool handler, which gets no tools (`AgenticOrchestrator.swift:5313`, `9123-9152`, `FoundationModelToolRegistry.swift:328-332`). Standard takes the tools away as soon as its context is assembled (`RAGService.swift:14769-14775`). So no step chooses a tool. A research round asks the model to reply `[ANSWER]` or `[SEARCH: words]`, and the code runs that search (`AgenticOrchestrator.swift:3091-3143`). `[evidence_level: grep_verified, confidence: exact, evidence_source: all 14 generateWithProperConsent calls in AgenticOrchestrator.swift pass disableTools: true or the session flag, all 10 generateWithFreshSession calls are in that file, the source-only sessions are created without tools, and nothing writes the two system-tool settings, grep run 2026-10-20]`

### Carrying a notepad between sessions

> **In plain words**
> The desk gets wiped clean between sessions. So the librarian carries a notepad from one session to the next: a short copy of the notes so far, and the parts of the question that still look unanswered. The stack itself was cut into separate handfuls before the first session, about four cards each on an iPhone, and each session reads the next handful. Nobody goes back to the shelves in between. The notepad is what turns several separate readings into one continuous piece of work.

Because a single session is capped at the device's window (4,096 or 8,192 tokens), complex questions are answered across a chain of sessions. Deep Think's chain runs up to 8 sessions on every device, research rounds can follow it, and Maximum's own loop runs up to 50. By device tier, Deep Think changes the confidence it aims for (85% to 95%), and its step and token budgets (`DeviceCapabilityService.optimizedAgenticConfig`, see How much each device gets). (Corrected 2026-10-20: this paragraph described a chain of "plan, search, analyse, synthesise, refine" and a fact bank that "accumulates verified facts". In the code a session only reads, and the bank's facts are sentences cut from the sessions' own notes that nothing checks against the passages. Its last sentence, "hierarchical compression" carrying facts forward, holds for Maximum's own loop, whose running answer and final synthesis read the bank (the code names this hierarchical compression), and not for Deep Think, where the next session reads the notes, not the bank. `[evidence_level: code_verified, confidence: exact, evidence_source: AgenticOrchestrator.swift:6522, 7027, 7275, 7292, 7352, 8233-8253]`)

The reasoning chain, as the code runs it (`AgenticOrchestrator.swift:4880-5970`):

- **Title routing, once.** One on-device call (256 tokens) sees a menu of section titles of up to 1,800 characters and names up to 8 to read first. The stack is reordered by that choice and nothing is dropped (`AgenticOrchestrator.swift:4760-4878`).
- **Every window is built before session 1**, as separate slices of the same stack: 4 passages a window on a 4,096-token window, and up to 7 on a window of 8,000 or more. From 5.6, when the system can count tokens, a window holds whole passages within at most 3,200 tokens (less on a small window, after the 700-token reply, the carried text and 656 tokens of fixed reserve). Otherwise the sentences that match the question are taken from the window's passages, up to 3,500 characters. On that sentence path the last window is pulled back to stay full, so when the stack is not a multiple of 4 it overlaps the one before (`AgenticOrchestrator.swift:4931-5130`, `5006`, `SessionEvidencePlan.swift:29-75`).
- **Building stops when the stack runs out**, so the number of sessions is the number of distinct windows, at most 8: about 5 for the usual 20-passage stack on an iPhone and about 3 on a Mac (`AgenticOrchestrator.swift:5105-5155`).
- **Each session**, in order: a one-second pause when iOS 27 asks apps to ease off, the stop check (from the fifth session, see Knowing when to stop), the next prebuilt window, then **one on-device model call** of at most 700 tokens with tools off and `forceOnDevice: true`, retried with the prompt cut to 70% and then 40% on a context overflow. **No session retrieves, reranks or packs anything new** (`AgenticOrchestrator.swift:5160-5420`).

What each session's prompt carries (`AgenticOrchestrator.swift:8200-8402`):

| Part | What it holds |
|---|---|
| QUESTION | The question as asked |
| STILL UNANSWERED | Up to 3 open sub-questions from the fact bank |
| PRIOR FINDINGS | Each earlier session's notes, cut to 400 characters at a sentence end, 1,200 in all. Past three sessions the older notes become one line of up to 250 characters each (800 in all), and the last two stay |
| SESSION OBJECTIVE | Built from the open sub-questions ("prioritize coverage for…"), or a request to pressure-test the answer when none are open |
| DOCUMENTS | The session's own window: whole passages when sized in tokens, or up to 4,000 characters in the first session and 2,200 after |

The first session carries only the question and its documents. The other parts start with the second.

**The fact bank** holds at most 1,500 characters of claim sentences cut from each session's notes, with their [S#] markers, and nothing checks them against the passages (`AgenticOrchestrator.swift:6070-6420`). Its sub-questions come from fixed templates, with no model call: "evidence", "benefits" and "effects" each followed by the question's first three topic words, one line for each of "effect", "affect", "benefit", "harm", "cognitive", "how" or "why" that the question contains (the first two give the same line), and always "specific details values numbers" and "notes warnings exceptions". A sub-question counts as answered once any claim shares one word of four or more letters with it (`AgenticOrchestrator.swift:6110-6192`). **In Deep Think the bank's claim text never goes into a prompt.** It drives the coverage, novelty and stop decisions and the STILL UNANSWERED line. Only Maximum's running answer and final synthesis read it (`AgenticOrchestrator.swift:6478`, read at `7292` and `7352`). `[evidence_level: grep_verified, confidence: exact, evidence_source: asContext() is called only at AgenticOrchestrator.swift:7292 and 7352, grep run 2026-10-20]`

**The synthesis.** With two or more usable notes, one call writes the answer from the notes alone, at most 3,000 characters in and 1,500 tokens out, with no passages in its prompt. It is the one chain call not pinned to the device, so on Hybrid it can be planned to Private Cloud Compute after consent. With one usable note, that note is the answer (`AgenticOrchestrator.swift:5879-5970`). On a good stack Maximum runs this same chain with its own settings: 50 sessions allowed but still one per distinct window (4 passages on an iPhone), no early stop before the ninth session, and an "exhaustive" synthesis at the end (`AgenticOrchestrator.swift:212-226`, `5788-5877`, `AgenticPolicyService.swift:296-332`).

### Maximum's own loop

> **In plain words**
> On a strong stack, Maximum first goes back to the shelves once for a much bigger pile. Then it reads three new cards per session, carrying its notes forward, and writes a fresh draft answer every five sessions. It can run up to fifty sessions, fewer for a small pile, enough to read the pile about one and a half times. Then it writes the final answer from its bank of facts and its latest notes.

On an excellent stack Maximum runs its own loop (`AgenticOrchestrator.swift:554-631`, `6536-7171`):

- **One big gather, before session 1:** a full retrieval of 50 passages plus three fixed rewordings of the question at 20 each, merged with the stack (`AgenticOrchestrator.swift:8045-8128`).
- **The ceiling** is min(50, max(8, ceil(pile ÷ 3) × 1.5)) sessions, so a pile of 60 passages allows 30 (`AgenticOrchestrator.swift:6572-6583`).
- **Each session** takes the next 3 passages it has not read (cycling back once all are read), takes the sentences that match the question into 2,500 characters, and makes one on-device call of up to 1,000 tokens with tools off, at temperature 0.7 for sessions 1 to 3, 0.5 up to session 8 and 0.3 after (`AgenticOrchestrator.swift:6810-6930`).
- **Every 5 sessions** an on-device call writes a running answer from the fact bank's claims and the two latest notes (`AgenticOrchestrator.swift:7077-7086`, `7277-7331`). What a session's prompt carries depends on its number: sessions 2 to 5 get the last two notes at 150 characters each, sessions 6 to 15 the first 300 characters of the running answer, and the first session and those after the fifteenth only the question and their passages (`AgenticOrchestrator.swift:7195-7267`).
- **After the loop**, one synthesis writes the answer from the fact bank's claims and recent notes, then a refinement call when there are more than 8 notes and the answer runs past 800 characters. Neither is pinned to the device (`AgenticOrchestrator.swift:7333-7500`). Self-RAG 2.0 then checks it once, with no retry, and blends its confidence with the loop's (`AgenticOrchestrator.swift:578-630`, `AgenticPolicyService.swift:153-165`).
- **Multi-chain clusters do not run.** `executeMultiChainReasoning` and its five-cluster configuration have no caller, so Maximum never splits the documents into parallel chains, whatever the comment at `AgenticOrchestrator.swift:539-541` says (`AgenticOrchestrator.swift:7533`, `4598-4631`). `[evidence_level: grep_verified, confidence: exact, evidence_source: the only match for executeMultiChainReasoning is its definition, grep run 2026-10-20]`
- **"200,000 tokens" is never enforced in either loop.** Maximum's configuration carries `maxTotalTokens: 200_000`, and that field is read in two places only, the decomposed pipeline and research rounds (`AgenticOrchestrator.swift:141-150`, `1751`, `2942`). `[evidence_level: grep_verified, confidence: exact, evidence_source: maxTotalTokens is read only at AgenticOrchestrator.swift:1751 and 2942, grep run 2026-10-20]` The 0.98 is the loop's target for "completed", and 50 is a ceiling that the pile's size cuts down.

### Knowing when to stop

> **In plain words**
> Two separate reasons to stop, and either alone is enough. **Either** the question is answered well enough, **or** the last few trips brought back nothing new and most of the library has already been seen, so more trips won't help.
> They have to be separate. An earlier version required both at once, and that combination turned out to be unreachable. The scoring could never climb high enough to trigger it, so the loop ran every one of its fifty trips, every time, long after it had what it needed. It knew it was finished and had no way to say so.
> **Corrected 2026-10-20.** Those two paragraphs describe **Maximum's own loop**, and "most of the library" is too strong: Maximum's "nothing new" means a run of sessions that added nothing, or every card in its pile read, once at least five sessions have run. **Deep Think works differently.** It reads every handful it has unless three things are true at once, from the fifth session on: it's as sure as this device asks for, enough parts of the question look answered, and the last sessions brought back nothing new. It also stops when the AI itself writes that the answer is complete, or that it isn't in the documents. On an iPhone with the usual stack, it usually reads all five handfuls. `[evidence_level: inferred, confidence: high, evidence_source: worked from the confidence formula below, not measured on a device]`

Two independent stop conditions. *Completed*: confidence and sub-question coverage both clear their targets. *Converged*: novelty is exhausted, measured as streak-based patience over low novelty, high saturation or 85% source coverage, and the chain is past a minimum session count so a cold start cannot be mistaken for exhaustion. These were previously conjoined with a 0.98 confidence requirement that was unreachable by construction, which meant the loop always ran to its ceiling.

(Corrected 2026-10-20: that paragraph is Maximum's own loop, where the source coverage that counts is every passage in the pile, not 85%. The 85% belongs to Deep Think's chain, which still requires all of its conditions together. The exact rules in the code, by mode, follow. `[evidence_level: code_verified, confidence: exact, evidence_source: AgenticPolicyService.swift:315-323, 349-355, AgenticOrchestrator.swift:6684-6690]`)

**Deep Think's chain** ends at the first of these (`AgenticOrchestrator.swift:5185-5219`, `5518-5534`, `AgenticPolicyService.swift:294-332`):

1. **The windows run out.** Sessions are capped at the number of distinct windows and at 8 on every device (`maxSessionsForMode = min(8, sessionCount + 4)`, with a starting length of 4 or 5).
2. **All three at once, checked from the fifth session** (`minSessionsBeforeEarlyStop` 4): confidence at the device's target (0.85 on an A17 Pro, 0.90 on an A18 or an M1, 0.92 on an A19, 0.95 on later M-series chips, the M1 Ultra and the A20), **and** sub-question coverage of 0.55 (0.70 with four or more sub-questions), **and** novelty exhausted, meaning two sessions in a row with novelty below 0.18, two in a row saturated (more than 85% of the latest notes' longer words already in earlier notes, with low novelty and no sub-question newly answered), or windows covering 85% of the stack's documents.
3. **The model's own signal**, from the second session: a reply containing "ANSWER COMPLETE", "NOT FOUND IN DOCUMENTS" or "DOCUMENTS DO NOT CONTAIN" ends the reading and goes to the synthesis.

The confidence it compares is mostly a function of how many sessions have run: log(n + 1) ÷ log(budget + 1) × 0.68, plus coverage × 0.18 and bonuses of at most 0.17, less a saturation penalty, with any `CONFIDENCE:` figure the model writes blended in at 20% (`AgenticPolicyService.swift:366-409`, `AgenticOrchestrator.swift:5569-5626`). On an A18 with the usual 20-passage stack, five windows, it cannot reach 0.90 by the fifth session's check: the formula gives at most about 0.85, and 0.88 with the model's own figure blended in, so the chain reads every window. `[evidence_level: inferred, confidence: high, evidence_source: worked from AgenticPolicyService.swift:366-409 with the 8-session budget the chain passes, not measured on a device]` A repetition stop also exists in the chain's code, in a branch that runs only when there is no evidence confidence, which Deep Think and Maximum always have, so it cannot run (`AgenticOrchestrator.swift:5632-5716`).

**Maximum's own loop** ends at the first of these (`AgenticOrchestrator.swift:6639-6730`, `6942`, `7012`, `AgenticPolicyService.swift:334-364`):

- **Completed:** confidence of at least 0.98 **and** sub-question coverage on target (0.55, or 0.70 with four or more sub-questions).
- **Converged:** novelty exhausted (two sessions in a row with novelty below 0.18, three in a row saturated, or every passage in the pile read) **and** checked from the sixth session on, so at least five sessions have run.
- The session ceiling, three failed or empty sessions in a row, or cancellation between sessions.

Its confidence uses the same formula with a 50-session budget, so the session term grows slowly, and the code's own note says device runs peaked at 89% (`AgenticOrchestrator.swift:6655-6668`). So in practice "converged" or the ceiling ends a run. `[evidence_level: inferred, confidence: medium, evidence_source: that code note, not measured here]`

> **In plain words**
> The obvious fix was "stop when you stop ticking off new parts of the question." It sounds right. Measured, it made things worse.
> The list of parts had been stuck since the first trip for a boring reason: one part of the question simply wasn't in the documents and never would be. But the librarian wasn't idle. They were still finding *better* evidence for the parts already covered. Stopping on the stuck list cut them off early, before they'd found the one solid quote that made the answer trustworthy.
> Not making progress *outward* isn't the same as not making progress. Sometimes you're going deeper. So that signal is still watched and recorded, but it is no longer allowed to end the work.

Measured on Maximum's own loop: three device runs on the same corpus and question, 2026-07-31 (the coverage-plateau entry in `Docs/Archive/CHANGELOG_2.0_to_5.2.md`). Kept as history.

| Stop rule | Sessions | Answer length | Verified citations |
|---|---|---|---|
| Ceiling only, no convergence | 50 | 48 | 0 |
| Saturation convergence | 23 | 209 | 1 of 2, accepted |
| Coverage plateau | 8 | 67 | 0 of 1, retried |

Coverage measures breadth, and it was flat from the first session because one sub-question was never present in the corpus. Novelty meanwhile held at 61 to 86% because the chain was accumulating depth for sub-questions already covered. Stopping on flat breadth removed the depth that eventually produced the one citation the verifier accepted. Coverage plateau is therefore instrumented and logged but deliberately not acted on. (In the current code the log line fires after 6 flat sessions in Maximum's loop, `AgenticOrchestrator.swift:6700-6716`.)

### Going back out for more

> **In plain words**
> Going back to the shelves happens in two places, and neither is in the middle of the reading. In Deep Think, after the answer is written from a strong stack, the app checks the notepad: if parts of the question still look unanswered, or the answer reads like a miss, it runs a few research rounds. In each one the AI looks at what it has and either answers or names the words to search for, and the app runs that search. In Maximum the going out happens before the reading, in one big gather, and the reading sessions work through that pile.

- **Research rounds (Deep Think, excellent stack only)** start after the chain's synthesis when sub-question coverage ended below its target or the answer reads like a miss (`AgenticOrchestrator.swift:685-700`). The search is the question plus "Still unanswered:" and up to three open sub-questions. Research begins with one full retrieval of 20 passages for it, then up to 5 rounds, each one on-device decision call of 900 tokens that replies `[ANSWER]` or `[SEARCH: words]`, followed by a new full retrieval for those words. The decision call sees only the first 2,000 characters of what research has gathered (cut to its last 6,000 once it passes 8,000), and a search's text lists its passages in the reordered order of step 5, so in the first round that view starts at the search's second-best passage, read in the code and not run (`AgenticOrchestrator.swift:1851-1900`, `3035-3039`, `3106`). It stops after 5 rounds, at the device's token budget, or after 180 seconds (`AgenticOrchestrator.swift:2886-3090`, `3091-3143`). Its answer replaces the synthesis only if it is not a miss, not a dump of raw evidence, passes `shouldAcceptReplacement` and agrees with the synthesis, and then it is returned at once, without the Self-RAG check (`AgenticOrchestrator.swift:744-791`).
- **The Self-RAG check (Deep Think, excellent or good stack)** scores the answer's relevance to the question by its words, and the share of its citations that point at a real passage. It retries when relevance is below 0.35, when the answer says its sources don't cover the question while citing them, or when half or fewer of the citations check out. A retry is a research run of 3 rounds, at most twice, because the third strike ends the loop before it researches (`AgenticOrchestrator.swift:3786-3955`, `3957-4024`, `AgenticPolicyService.swift:153-255`).
- **Maximum's gather** is its one trip, before its loop (see Maximum's own loop).
- **Maximum's mid-loop expansion cannot happen.** The branch that would add up to three more retrievals needs three saturated sessions in a row. Saturation is only scored once there are three notes, so that streak first exists at the top of the sixth session, and the "converged" check, which runs first in the same pass, is already true then and ends the loop (`AgenticOrchestrator.swift:6646-6807`, `AgenticPolicyService.swift:395-402`). `[evidence_level: code_verified, confidence: high, evidence_source: read, not run]`
- **The chain never retrieves again.** Everything it reads was retrieved before session 1.

### How much each device gets

> **In plain words**
> Newer devices aim higher. Deep Think on an iPhone 15 Pro aims to be 85% sure before it stops early, and on a recent Mac 95%. Every device gets at most eight reading sessions in Deep Think.

| Device tier | Steps | Token budget | Confidence target | Escalation threshold |
|---|---|---|---|---|
| A17 Pro | 5 | 20,000 | 0.85 | 0.35 |
| A18, A18 Pro, M1, M1 Pro, M1 Max | 8 | 32,000 | 0.90 | 0.40 |
| A19, A19 Pro | 10 | 40,000 | 0.92 | 0.45 |
| M2 and later, M1 Ultra, A20 | 12 × (memory ÷ 16 GB, at least 1), at most 32 | 56,000 × the same, at most 128,000 | 0.95 | 0.50 |
| Maximum, any device | 50 | 200,000 | 0.98 | 0.50 |

(`DeviceCapabilityService.swift:1044-1092`, `1225-1290`, `1336-1376`, `AgenticOrchestrator.swift:141-150`)

The step budget picks the chain's starting length (`.standard` below 8 steps, `.deep` from 8) and caps the decomposed pipeline's sub-searches at the step budget less 2. The token budget is checked only in the decomposed pipeline and in research rounds. Neither caps the chain, which stops at 8 sessions on every device, as the app's status line says from 5.7 ("a chain of up to 8 sessions"), where 5.6 showed the step budget instead, 5 on an iPhone 15 Pro (`AgenticOrchestrator.swift:212-226`, `1749-1751`, `2942`, `RAGService.swift:10875-10881`).

### Backing off when the device is under pressure

> **In plain words**
> If the device is hot or the battery is low, the app quietly does less work rather than grinding things to a halt. It has a fixed order for what to give up first, so the things that matter most survive longest.
> **Corrected 2026-10-20.** Only a critically hot device or critically low memory makes it do less. A low battery no longer does. `[evidence_level: code_verified, confidence: exact, evidence_source: AdaptivePipelineOptimizer.swift:54-70]`

Thermal state, battery level and available memory are read per query, selecting one of four levels with candidate depth capped at 50, 30, 20 or 10 and features dropped in priority order. A short cooldown may be applied before heavy generation.

(Corrected 2026-10-20.) The four levels are Full Quality, Balanced, Power Saver and Emergency. By default only two states lower the level: a critical thermal state picks Emergency, whose configuration allows 10 candidates and turns off rewriting, neighbouring passages, HyDE and compression, and critical memory pressure picks Power Saver, which halves the candidate cap and turns off HyDE and compression. Battery no longer lowers it, and Balanced is never picked automatically (`AdaptivePipelineOptimizer.swift:54-70`, `204-260`). At Full Quality the candidate cap comes from the device tier, 75 on an A17 Pro, 100 on an A18, 150 on an A19 and 250 on the top tier, and a question of three words or fewer without a question mark is capped at 10, a complex one (several parts, more than 25 words, or a word such as "explain" or "compare") at 50 (`AdaptivePipelineOptimizer.swift:117-198`, `324-375`, `606-632`). Between reasoning sessions, both loops pause one second whenever iOS 27 asks apps to ease off, without dropping a session (`AgenticOrchestrator.swift:5172-5177`, `6639-6645`). `[evidence_level: code_verified, confidence: exact, evidence_source: the AdaptivePipelineOptimizer.swift and AgenticOrchestrator.swift lines named]`

> **What this is not**
> This is not an autonomous agent that takes actions in the world. It has no ability to write, send or change anything, and it does not act outside answering a question. It is a multi-session *retrieval* loop: it writes its own search phrasings, takes its sub-questions from fixed templates, picks which sections to read first, decides from scores it computes when to stop reading, and in a Deep Think research round can name the words to search for next. It is never handed a tool. (Corrected 2026-10-20: this said it "plans its own sub-questions" and "chooses its own tools". `[evidence_level: code_verified, confidence: exact, evidence_source: AgenticOrchestrator.swift:1916-2061, 4760-4878, 6110-6163, 5185-5219, 3091-3143, 5313]`)

## 08. How well it works

*This section was rewritten on 2026-08-21. The figures it used to carry are withdrawn, and the reason is worth more than the figures were.*

> **In plain words**
> An earlier version of this page said the app answered 18 of 20 test questions correctly and never once invented an answer. Both numbers came from a test set written alongside the questions it was grading, and the run they came from has since been flagged as one where the answer-writing step probably never executed at all. So they are gone.
> What replaced them is a harder test on real research papers the project did not write, and the app does considerably worse on it. That is the more useful number, and the reason for the swap.

### Why the old figures were withdrawn

Three separate problems, each sufficient on its own.

- **The corpus graded itself.** The 20-case set was synthetic and authored alongside its own questions. It measured self-consistency, not retrieval quality.
- **The run is flagged.** `BenchmarkRuns/PROGRESSION.md` marks runs averaging under 60 seconds per case as ones where generation almost certainly did not run. The run behind "18 of 20" averaged **7 seconds per case** and carries that flag.
- **The stage table was measuring the ruler.** It showed reranking and final selection losing ground against a perfect vector stage. That turned out to be ground truth crediting one of the two documents each multi-hop question required. Corrected on 2026-08-11, after which every stage read 1.000, which is its own problem: a fixture at ceiling can detect a regression and cannot demonstrate an improvement.

### What is measured now

Real external ground truth, from QASPER: **40 research papers, 83 scored cases**, none of them written by this project.

| Measure | Result |
|---|---|
| Cases scored | 77 of 83 |
| Exact-match accuracy | **0.410** |
| Retrieval, gold document in top 10 | 0.649 |
| Reranking nDCG@5 | 0.431 |
| Final-context recall@10 | 0.549 |

> **Corrected 2026-10-27.** Three retrieval labels in this table name the wrong measures. In the `qasper-overnight`
> row of `BenchmarkRuns/PROGRESSION.md`, 0.649 is the lexical arm's MRR, 0.431 is the final context's recall@1 and
> 0.549 is the final context's MRR. The committed summary of the same run ("Retrieval, per stage", n=72) gives the
> measures the labels name: the gold document is in the top 10 at 0.54 to 0.82 depending on the stage, reranking
> nDCG@5 is 0.64, and final-context recall@10 is 0.81 (0.806 in `PROGRESSION.md`). And 0.410 is 34 correct over all
> 83 cases attempted. Over the 77 that were scored it is 34 of 77, 44%.
> `[evidence_level: artifact_derived, confidence: high, evidence_source: BenchmarkRuns/PROGRESSION.md header (correct, acc, lexical MRR, fusion MRR, rerank MRR, final r@1, final r@10, final MRR) and its qasper-overnight row; Docs/AuditArtifacts/Benchmarks/20260812-215108-matrix.md ("34/77 correct (44%) ... 83 attempted" and the per-stage table); Docs/EVALS.md QASPER row ("34 correct over all 83 attempted")]`

That accuracy is a floor rather than a quality score: it is exact-match against expected answer patterns, so a correct answer phrased differently counts as wrong.

### Where the failures actually are

Decomposed on 2026-08-21, and the answer surprised the project: it is **not one bottleneck, it is two of roughly equal size**.

- The answer-bearing passage **fails to reach the model** in 10 of 24 measurable cases.
- When it does reach the model, the answer is **still wrong** in 7 of 14.

Every prior plan had assumed one of those dominated. Retrieval and synthesis each account for about half.

> **What these numbers do not show**
> - **±1 case at n=24 is the measured noise floor.** Two runs of the same build, differing only in debug output printed after generation, scored 11/24 and 10/24. Nothing smaller than roughly a four-case swing resolves in the accuracy column. The per-stage columns are far more stable and are what a change should be judged on.
> - **Deep Think and Maximum have no valid accuracy figure and none is quoted anywhere.** The one Deep Think benchmark attempted scored 1 of 5 with a timeout at 1800 seconds.
>   **Corrected 2026-10-27,** to agree with `Docs/LIMITATIONS.md` (corrected 2026-09-29): Deep Think has been benchmarked, though not in a way that separates it from Standard, and only Maximum has no valid figure. On the QASPER pack Deep Think scored 2 of 8 against Standard's 4 of 7 in its first paired run (`paired-retry`, `1b700ed`, 2026-08-19) and 9 of 25 against Standard's 10 of 25 in its largest (`overnight-25case-nodeadlock`, `73fff4f`, run overnight from 2026-08-20). Each is a single run in the Mac benchmark harness at a forced temperature of 0.7, which the ledger found does not reproduce the shipping app, and 25 cases cannot resolve less than about a four-case swing, so the ledger does not read either gap as a difference between the modes. The 1-of-5 run (`overnight-smoke`, `0eb5d96`) was the first Deep Think benchmark attempted, not the only one, and its raw data was deleted on 2026-08-19, so that figure cannot be checked. `[evidence_level: artifact_derived, confidence: high, evidence_source: BenchmarkRuns/LEDGER.md rows overnight-smoke ("First Deep Think benchmark ever attempted"), paired-retry and overnight-25case-nodeadlock with its accuracy line "deep-think 9/25 (36%), standard 10/25 (40%)"; Docs/LIMITATIONS.md Product Limits and Technical Limits]`
> - **Three run directories were deleted before being re-read.** `BenchmarkRuns/*` is gitignored, so the conclusions drawn from them survive and their raw data does not. Those rows are marked unauditable in the ledger rather than quietly dropped.
> - Document-level recall credits a whole document when any chunk of it appears, which inflated `r@1` on runs where a summary was injected.

**The older figure was withdrawn from `README.md`, `Docs/LIMITATIONS.md` and `Docs/EVALS.md` on 2026-08-21**, each corrected in place with a dated note rather than deleted. `Docs/RELEASE_NOTES.md` deliberately keeps its two mentions: they are historical records of what was believed and re-scored at the time, not claims about the app now. The figure was never shown anywhere in the app itself.

The live record is `BenchmarkRuns/PROGRESSION.md` for the numbers and `BenchmarkRuns/LEDGER.md` for what each run was testing and what it settled. Read those rather than trusting any figure quoted here, including these.

## 09. What it can't do

*Stated plainly, because a tool that shows you its sources should also show you its edges.*

> **In plain words**
> Answers are only as good as what the app could read out of your files. If a scan is blurry or a layout is unusual, the words it extracted may be wrong, and everything after that inherits the mistake. Citations show you what supported an answer; they aren't proof the answer is right. And confidence percentages are a useful signal, not a guarantee.

### Known boundaries

### Not for these uses

## 10. Word bank

*Two parts. First every stage of both pipelines on one page, in running order. Then every concept that appears anywhere above, defined twice.*

### Every step, in order

#### Reading a document: six steps

*Corrected 2026-10-20: rows 2, 3 and 6 are corrected as in section 02, where each correction cites its lines. In row 4, 510 is the embedding model's limit, and in code a chunk is split above 430 tokens (the 510 less 80 for the prefix) into parts of at most 420. `[evidence_level: code_verified, confidence: exact, evidence_source: the lines cited in section 02, DocumentProcessor.swift:6766-6773, 6880-6960, read 2026-10-20]`*

| Step | In plain terms | Technical name |
|---|---|---|
| `1` | Get the words out of the file | Parsing and extraction: PDFKit text layer, Vision document recognition, Office XML, RFC 4180 CSV, speech transcription |
| `2` | Cut it into overlapping index cards, keep tables whole when they fit | Semantic and structure-aware chunking, ≤310 words, atomic table preservation, contextual prefixing. **Corrected 2026-10-20:** a 260-word target under the 310 ceiling, up to 50 words of overlap, and a table kept whole only up to 380 words (a longer one is split by rows and also gets a summary chunk) |
| `3` | Highlight names, dates and section headings | Named entity recognition and metadata tagging. **Corrected 2026-10-20:** entity tags are not a searchable column, and the entity index the code declares for linking passages is never filled |
| `4` | Check each card fits before filing it | Token gating, ≤510 word-piece tokens; citations are chunk-level, with page and quote, not byte offsets |
| `5` | Give each card a position on a map of meaning | Dense embedding generation, 384 dimensions, Core ML or Core AI |
| `6` | File every card twice, and leave bookmarks | Dual index storage: FTS5 lexical plus memory-mapped vector store, with page-level checkpointing. **Corrected 2026-10-20:** FTS5 stems words (Porter) and is written twice, the whole document and its pages before chunking and each chunk after its vector. The vectors sit in one flat file in arrival order and a search compares the question with every one, with no index or clusters. After the save, one overview summary per document, its tags and suggested questions are written |

#### Answering a question

*Corrected 2026-10-20: this table is Standard's path, the default. Deep Think and Maximum leave it before step 0 and run their own front end and reading loop (section 07). Cells marked Standard, Deep Think or Maximum say where a step behaves differently by mode. `[evidence_level: code_verified, confidence: exact, evidence_source: the lines cited at each step in section 03 and in section 07, read 2026-10-20]`*

| Step | In plain terms | Technical name |
|---|---|---|
| `0` | Load this library's word list | Corpus vocabulary cache build or retrieval |
| `1` | Work out what "it" refers to | Query understanding: pronoun resolution, normalisation, entity labelling. **Corrected 2026-10-20:** in **Standard** a lookup is kept literal, and another question is rewritten by the model only when it reads as ambiguous |
| `1.5` | Ask the question several ways | Corpus-aware query expansion. **Corrected 2026-10-20:** **runs in no mode.** Standard has it off, and Deep Think and Maximum leave this path before it. They write up to 5 search phrasings of their own and run a full search for each (section 07) |
| `1.5b` | Add words this library uses | Per-container vocabulary expansion **(undocumented)**. **Corrected 2026-10-20:** **runs in no mode**, because it sits inside step 1.5. Deep Think's and Maximum's searches put synonyms from the library's corpus vocabulary into a wider keyword query, tried only when the phrasing as written finds nothing |
| `1.5c` | Add known terms for the subject area | Gazetteer domain vocabulary enrichment **(undocumented)**. **Corrected 2026-10-20:** **runs in no mode here**, inside step 1.5. Deep Think's and Maximum's searches add up to 5 gazetteer terms to that wider keyword query |
| `1.6` | Decide what kind of question this is | Answer intent classification: lookup, procedure, compare, summarize, general. **Corrected 2026-10-20:** eight intents by keyword rules with no model call (lookup, table lookup, procedure, compare, summarize, investigate, compute, findings), and an unmatched question is investigate |
| `2` | Put the question on the map of meaning | Query embedding, 384 dimensions. **Corrected 2026-10-20:** one vector for the question in **Standard**, one per search phrasing in **Deep Think and Maximum**. HyDE runs in no mode |
| `2.5` | Send whole-library questions to summaries | Summary-first routing over a hierarchical summary tree. **Corrected 2026-10-20:** one model-written summary passage per document (its first 150 words when the model fails) and no tree. A question the router reads as an overview (confidence 0.5 or more) searches the summaries |
| `3` | Search both filing systems and merge by position | Hybrid search: BM25 plus vector similarity, merged by Reciprocal Rank Fusion at k=60. **Corrected 2026-10-20:** weighted fusion (a lookup weighs 0.45 meaning and 0.55 words), a third list of table rows for specification and state questions, and a vector arm that scans every vector |
| `3.5` | Promote cards from a fitting section | Section metadata boost **(undocumented)**, reported as `boosted` in the measurements |
| `4` | Re-sort with a slower, better reader | Cross-encoder reranking, with heuristic fallback. **Corrected 2026-10-20:** over up to max(100, min(250, topK × 5)) candidates |
| `4.3` | Bin the weak candidates | Low-confidence filtering |
| `4.4` | Don't let one document hog the desk | Multi-document representation |
| `4.5` | Drop near-duplicates | Maximal Marginal Relevance, λ 0.60 / 0.55 / 0.50 by mode. **Corrected 2026-10-20:** the library's λ (0.6 by default, at least 0.85 for a procedure in Standard), and the per-mode values are unused. It changed nothing through 5.6 and works from 5.7 |
| `4.6` | Bring the neighbouring cards too | Parent document retrieval, 2 / 3 / 5 siblings per side, with Jaccard dedup |
| `4.6b` | Follow "see section 7.3" pointers | Cross-reference resolution **(undocumented)**. **Corrected 2026-10-20:** **Standard:** lookups only. **Deep Think and Maximum:** every haul |
| `4.8` | Hunt directly for specification tables | Targeted spec retrieval, bypassing both similarity and the reranker **(undocumented)**. **Corrected 2026-10-20:** lookups only, and in **Deep Think and Maximum** precise-value questions too |
| `4.7` | Cross out irrelevant sentences | Contextual compression. **Corrected 2026-10-20:** **runs in no mode.** Standard has it off, and Deep Think's own searches have no such step |
| `4.9` | Add a small map of sections and names | Graph-style context packing under a token budget. **Corrected 2026-10-20:** for investigate, compare and findings questions only |
| `5` | Put the best material at both ends | Context assembly with Lost-in-the-Middle positional reordering. **Corrected 2026-10-20:** a lookup's first pass puts its best passage first and whole (5.7), then matching sentences, with no reorder, and a procedure keeps document order. Other questions, and a lookup whose context is packed again for the device, are reordered across all candidates before the budget cut, which can drop rank 2 (a known defect). Deep Think's searches use their own reorder, which puts the best passage in the middle. About 3,190 tokens are left for passages in a 4,096 window, a device-log figure from an iPhone 16 Pro Max (artifact_derived). **Corrected 2026-10-27:** the rank-2 defect was fixed in `fa80e71` (2026-10-21, 5.7): passages are chosen in rank order first and reordered after the budget cut, only when four or more fit `[evidence_level: code_verified, confidence: exact, evidence_source: RAGEngine.swift:496-501, 683-691 at 1e4a718]` |
| `5.9` | Assemble summaries directly | Extractive summarization for summarize intent. **Corrected 2026-10-20:** **cannot run**, because its condition also needs the question to be extractive-first, which a summarize question never is |
| `5.10` | Copy exact numbers instead of generating **(switched off)** | Extractive QA override, **disabled at this step**; the same extractor still answers value questions elsewhere (see step 5.10) |
| `6` | Write the answer from the desk | Generation within one session of the device's window, tool schemas withdrawn once evidence is assembled. **Corrected 2026-10-20:** the route (on device, Private Cloud Compute or a refusal) is planned after retrieval, and the answer streams as it is written |
| `6.5` | Repair the formatting | Response formatting and markdown normalisation. **Corrected 2026-10-20:** also citation repair, and for a lookup or precise value the extracted-value override, which can replace the answer |
| `7` | Score how well it came out | Quality assessment. **Corrected 2026-10-20:** it scores the retrieval (top score, passage and source counts), not the answer, and that score is the answer's confidence |
| `7.5` | Run the nine fact-checks | Verification gates A through I. **Corrected 2026-10-20:** once, after generation, as a label. **Standard** can refuse under the rule in section 04. **Deep Think and Maximum:** a label only, from 5.7 (not run in 5.6), unless the source-only check runs instead for a lookup. In Standard they also decide which claims Fact Check keeps. The shortcut for exact values gets none |
| `8` | Bundle answer, citations and evidence | Result packaging |
| `8.1` | Turn the raw score into a real percentage | Calibrated confidence via Platt scaling. **Corrected 2026-10-20:** logged and shown as a thinking step only, not as the answer's confidence |
| `9` | Record timings and system state | Response metadata |
| `10` | Draw it with tappable sources | Markdown rendering with inline citation resolution |

### Reading documents

**Chunk**
  One index card, about 310 words.The retrievable unit: ≤310 words with character overlap, carrying a document and section prefix. (Corrected 2026-10-20: about 260 words and never more than 310, with up to 50 words of overlap, and split if it runs over 430 tokens. `[evidence_level: code_verified, confidence: exact, evidence_source: SemanticChunker.swift:261-273, DocumentProcessor.swift:1054-1077, 6766-6773]`)

**Atomic chunk**
  A table kept whole, never cut up.A table or list preserved unsplit, so a cell never loses its column header. (Corrected 2026-10-20: only up to 380 words. A longer table is split by rows with its header row repeated, and every table also gets a summary chunk. `[evidence_level: code_verified, confidence: exact, evidence_source: DocumentProcessor.swift:5594-5660, 6572-6600]`)

**Contextual prefix**
  Writing the document and section name at the top of every card.A document and section label prepended before embedding, so an isolated chunk retains what it is about.

**Token**
  A piece of a word. The unit models count in, and there are more of them than there are words.Word-piece sub-word unit. Why a 310-word cap sits under a 510-token limit with headroom. (Corrected 2026-10-20: a chunk over 430 tokens is split. `[evidence_level: code_verified, confidence: exact, evidence_source: DocumentProcessor.swift:6766-6773]`)

**Embedding**
  A pin on a 384-direction map of meaning. Similar things land near each other.A 384-dimensional dense vector where cosine distance approximates semantic distance. (Corrected 2026-10-20: the vectors are stored in one flat file in the order they arrive, and a search compares the question with every one of them. `[evidence_level: code_verified, confidence: exact, evidence_source: BNNSVectorDatabase.swift:1036-1048, 1104-1201]`)

**OCR**
  Reading words out of a picture of a page.Optical character recognition. Here via Vision's document API, which also recovers table rows and columns rather than reading order alone.

**Full-text index**
  The alphabetical filing system.SQLite FTS5 with BM25 ranking and a Porter stemmer, so "documents" and "document" share a stem.

**Library isolation**
  Each library is a sealed room. A question is never answered from a room you didn't open.Every stored row and vector is tagged with a container identifier and queries are scoped to it.

**Checkpoint**
  A bookmark, so an interrupted import resumes instead of restarting.Page-level state plus a stable document identity, so resume continues rather than re-indexing as a new document.

### Finding evidence

**Retrieval**
  Fetching the handful of cards most likely to answer the question.Selecting candidate chunks from the index for a given query.

**Hybrid search**
  Searching both filing systems at once, because they fail on different questions.Dense and lexical retrieval run in parallel and merged, since they fail on different inputs.

**Rank fusion**
  Merging two result lists by *position* rather than score, so the two systems never have to agree on a scale.Reciprocal Rank Fusion at k=60, calibration-free because it uses only rank position.

**Reranking**
  The slow careful reader who looks at the question and each card side by side.A cross-encoder scoring query-chunk pairs jointly. More accurate than the retrieval encoder, too slow for corpus scale.

**Diversity selection**
  Don't pick five copies of the same paragraph. Each new card must add something.Maximal Marginal Relevance: relevance minus similarity to what is already selected.

**Small-to-big**
  Search with small cards, read with big ones.Embed small chunks for retrieval precision, then expand to neighbouring chunks for coherence.

**Lost in the middle**
  Models skim the middle of what they're given, so the good material goes at both ends.A documented attention bias toward the start and end of a context window, mitigated by positional reordering applied last. (Corrected 2026-10-20: in Standard the reorder applies to whole-passage packing, never to a procedure and to a lookup only when its context is packed again for the device, and it runs before the budget cut, not last. Deep Think's searches use their own reorder, which puts the best passage in the middle. `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:14946-15058, 15834-15902, 22121-22134, RAGEngine.swift:500-503]`) (Corrected 2026-10-27: from `fa80e71` (2026-10-21, 5.7) Standard's reorder runs after the budget cut, on the passages chosen, and only when four or more were chosen, so "before the budget cut" describes the code before that commit. Deep Think's own reorder is unchanged. `[evidence_level: code_verified, confidence: exact, evidence_source: RAGEngine.swift:496-501, 683-691, RAGService.swift:22192-22205 at 1e4a718]`)

**Summary routing**
  Whole-library questions go to summaries, because no ten cards can describe a hundred documents.Hierarchical summary nodes retrieved for global queries instead of leaf chunks. (Corrected 2026-10-20: one summary passage per document, written by Apple's model after import or taken from the document's first 150 words when the model fails, and no hierarchy. `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:8291-8360, DocumentSummaryService.swift:232-319, DocumentChunk.swift:89-104]`)

### Answering and checking

**Context window**
  The desk. About four pages. Everything competes for it, including the instructions.4,096 tokens in Apple's documentation, 8,192 on a Mac with macOS 27; the app reads the device's figure. Prompt, tool schemas, evidence, output schema and response all share it.
  (Corrected 2026-10-20: about 3,190 tokens of a 4,096 window are left for passages, a device-log figure from an iPhone 16 Pro Max quoted in the code. `[evidence_level: artifact_derived, confidence: high, evidence_source: RAGService.swift:3745-3747]`)

**Grounding**
  Every sentence in the answer traces back to a page on the desk.The property that every claim maps to retrieved evidence, measured as answer-to-evidence similarity.

**Hallucination**
  Stating something confidently that isn't in your documents.Ungrounded generation. Measured on trick questions where the correct behaviour is refusal.

**Abstention**
  Saying "that isn't in your documents" instead of guessing.Refusing to answer when evidence is insufficient. A designed outcome, not a failure.

**Verification check**
  One of nine fact-checks an answer must pass before you see it.A deterministic post-generation gate that can lower confidence or force abstention. Always local. (Corrected 2026-10-20: the checks run once on the finished answer, after it has streamed, and label it. Only Standard can refuse on them, under the rule in section 04, and in Standard they also keep unsupported claims out of the Fact Check list. `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:16568-16734, StructuredAnswer.swift:979-1047]`)

**Calibration**
  Turning the app's internal score into a percentage that means something.Platt scaling, mapping an uncalibrated score toward a probability.

**Citation**
  A tappable link back to the index card that supported a claim, with its page and a short quote.The chunk's ID, with its page, a quote of up to 240 characters, the document name and the section path; no byte or character offsets.

**Private Cloud Compute**
  Apple's secure cloud, used only for the writing step and only with your approval.Apple's stateless enclave-based inference service. Reached only after a minimized payload is built and consented to.

**Execution receipt**
  A record of what actually happened, not what was requested.Intended, attempted, actual, fallback and completed targets stored separately, so the route badge reports history.

**Agentic loop**
  Going back out for more, repeatedly, and deciding for yourself when to stop.Multi-session reasoning with a persistent fact bank and an independent convergence criterion. (Corrected 2026-10-20: Deep Think reads slices of one search in fresh sessions and goes back out only afterwards, in research rounds and the Self-RAG check's retries. It stops early on three conditions together or on the model's own word that it's done, and Maximum's own loop stops on either of two. No session has a tool. See section 07. `[evidence_level: code_verified, confidence: exact, evidence_source: AgenticOrchestrator.swift:4931-5155, 5185-5219, 5518-5534, 685-791, 3786-3860, 6684-6730]`)

## 11. Common questions

### Why not just give the whole document to an AI?

PlainBecause the AI on your device can only look at about four pages at once, and a document can be four hundred. And sending your files somewhere with more room would break the promise the app is built on. So there's no version of this that skips the hard part.
Two constraints, both hard. The on-device model has a context window of a few thousand tokens (4,096 in Apple's documentation, 8,192 on a Mac with macOS 27), so a document does not fit. And documents stay on the device by design, so sending the corpus to a larger model is not available either. Retrieval-augmented generation is the only architecture that satisfies both.

### How do I know it isn't making things up?

PlainNine checks run on every answer before you see it, and they're allowed to stop it. On the last measured run it never once invented an answer, and on every trick question it correctly said "not in here." Every claim also links to the sentence that supports it, so you can check yourself.
Nine deterministic verification gates run locally after generation, including a semantic grounding check that compares the answer against its evidence. On the most recent benchmark, trick questions produced zero confident answers and refusal correctness was 100%. Citations resolve to exact source spans rather than to whole documents.

> **Corrected 2026-10-20.** This answer said nine checks run "on every answer before you see it" and that every claim
> links to "the sentence that supports it". The checks run once on the finished answer, after it has streamed, and
> label it. Only Standard can refuse on them (section 04), Deep Think and Maximum answers are labelled from 5.7 and were not checked by the nine gates in 5.6, and
> a value returned by the shortcut for exact values is not checked at all. A citation resolves to a passage with its page
> and a quote of up to 240 characters, not to a sentence or an exact span (the 2026-09-29 correction at the top of this
> page). The benchmark sentence repeats the figures section 08 withdrew on 2026-08-21, because the run behind them is
> flagged as one where generation probably never ran. It is left here as written, and section 08 is the current record.
> `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:16568-16734, 11238-11262, 10561-10737, StructuredAnswer.swift:65-117]`

### Does anything leave my device?

PlainOnly if you say yes, only the final writing step, and only after the app shows you how much it would send and why. Reading, indexing, searching and fact-checking always happen on your device. Choose On-Device in settings and nothing ever leaves.
Ingestion, indexing, retrieval and all verification are local unconditionally. Only synthesis can target Private Cloud Compute, and only after a minimized evidence envelope is constructed and explicitly consented to for that exact payload. The On-Device setting is absolute.

> **Corrected 2026-10-20.** A new install is on Hybrid with Private Cloud Compute set to Ask when needed, so it asks
> each time until you choose Always Allow. After Always Allow, or with Allow without asking set (5.6 calls it "Allow for
> Deep Think and Maximum"), it sends without asking. On Hybrid, Deep Think's and Maximum's reasoning sessions stay on the device and only the steps that
> write an answer can go. With Private Cloud Compute picked in the model picker, the reasoning sessions can go too,
> behind the same permission (section 05).
> `[evidence_level: code_verified, confidence: exact, evidence_source: SettingsStore.swift:50, 453-461, RAGService.swift:4391-4440, AgenticOrchestrator.swift:9157-9240]`

### Why does it sometimes refuse to answer?

PlainBecause the answer wasn't in your documents, and inventing one would be worse than admitting it. That refusal is a feature, not a malfunction. It also occasionally hedges an answer that was actually fine, which is the cost of erring in that direction.
A failed critical verification gate produces a grounded abstention rather than a hedged answer. The gates are currently tuned conservatively, so a small number of correct, fully supported answers are also hedged. The trade is deliberate in direction; the degree is being tuned.

> **Corrected 2026-10-20.** Failed gates refuse an answer only in Standard, and only when reliability mode is off or
> the average of the gates' scores is below the mode's bar (0.50, or 0.25 for a lookup). Otherwise the answer is shown
> labelled Unverified. Other refusals come before any writing: when retrieval finds too little, and when the
> post-retrieval plan judges the evidence insufficient (rung 1 in section 05). In Deep Think and Maximum a relevance
> gate can end the run with a not-found answer before any reading session (section 07). Two more can come after the
> writing. The source-only check can turn a lookup's answer into a refusal when the question asks for a precise value
> or a state (in Standard after failed checks, in Deep Think and Maximum for any lookup not locked to a value). And
> with reliability mode off, an answer whose claims Gate B all marked unsupported is shown as a refusal.
> `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:16660-16706, 16864-16909, 11212-11236, 19494-19631 (sourceOnlyOutcomeIfNeeded), ModelExecutionPlanner.swift:37-40, AgenticOrchestrator.swift:390-453, StructuredAnswer.swift:979-1012]`

> **Corrected 2026-10-27** against `55fea8e`: "when the post-retrieval plan judges the evidence insufficient" refuses
> in Deep Think and Maximum. In Standard it refuses only with reliability mode off; with it on, the default, the
> reliability fallback answers from the same passages instead (section 05, under the ladder, and section 04's last
> note). `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:15966-15985, 17268-17296, 17321; ChatScreen.swift:3939-3942; AgenticOrchestrator.swift:9350-9385; SettingsStore.swift:534-535]`

### Does it work offline?

PlainYes. Importing, searching and answering all work in airplane mode. There's no account and no API key to set up.
The full local path requires no network. Only the optional cloud synthesis step does, and it degrades to local execution when unavailable, recording the fallback in the answer's receipt.

### Why 29 steps? What are they?

PlainSix for reading and filing a document, twenty-three for turning a question into a checked answer. Every one is listed in the word bank above, with a plain-English name. The app also runs a few extra stages that were never written into the specification, and those are listed too.
Six ingestion steps plus 23 query steps, where the 23 covers steps 1 through 9 of the specification. A step 0 warms a vocabulary cache before any question exists and a step 10 renders the finished answer; neither is part of the question-to-answer transformation, so neither is counted. The shipped code additionally runs five stages absent from any specification (1.5b, 1.5c, 3.5, cross-reference resolution at 4.6, and 4.8) and has one specified stage switched off (5.10). The pipeline is also adaptive and does not run every stage for every question.

> **Corrected 2026-10-20.** Of those five, 1.5b and 1.5c sit inside step 1.5, which runs in no mode, so they do not run
> either. Besides 5.10, contextual compression (4.7) runs in no mode and extractive summaries (5.9) cannot run. These
> steps are Standard's. Deep Think and Maximum run their own path (section 07).
> `[evidence_level: grep_verified, confidence: exact, evidence_source: usesQueryExpansion is read only at RAGService.swift:11649 and usesContextualCompression only at 11654, and step 5.9's condition is at 15391, grep run 2026-10-20]`