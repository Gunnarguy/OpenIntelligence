# Module 06. Lexical indexing, SQLite, and vector persistence

Forty-nine concepts. Two filing systems for the same cards, plus the machinery that searches the vectors, and the honest answer about the GPU.

## The ladder

**Like you're five.** Every card is filed twice. Once in an alphabetical index of the exact words on it, and once as a pin on the meaning map. The index is for when you know the exact word. The map is for when you don't.

**Like an idiot.** The word index is SQLite, the little database engine built into the phone, using its full-text search feature. It ranks by a formula called BM25, which is good at part numbers, names and rare words. The vector store is one flat file of numbers per library that the phone reads directly, plus a file of the vector lengths and a file of metadata saying which vector belongs to which chunk. Writes are atomic: the new files are written on the side and swapped in.

**Like less of an idiot.** Neither index is enough alone, which is why both exist. FTS5 keeps nine tables; the `chunks` table indexes section title, section path and content with weights 10, 5 and 1, so a match in a heading beats the same word in prose. The Porter stemmer makes "run" match "running." Write-ahead logging lets the UI read while ingestion writes, and a three-second busy timeout stops normal contention from becoming an error. Vectors are memory-mapped, so a library of tens of thousands of chunks costs almost no heap to search. Searching is an exact scan over every vector; there's no approximate index, because at phone-library scale exact is fast enough and never loses recall.

**Average Joe.** Where does the GPU come in? Only here, and only for one job: comparing your question's vector against a big library. If the library has a thousand or more vectors and a Metal device exists, the mapped buffer is handed to a small Metal program with no copy. Otherwise it's the CPU with Accelerate. That's the entire honest GPU story for search. The user's GPU profile setting does not decide this; it decides other things.

**Dot-connector.** The two stores have different failure shapes. SQLite is transactional inside itself. The vector store is atomic inside itself. Nothing is transactional across the two, which is why the ingestion module talks about a window where a document is in one and not the other. Also, the `VectorStoreRouter` keeps one live store instance per container file on purpose: two instances mapping the same file would be two truths about one library. And "persistentJSON" in a settings file is a historical name that now means the BNNS binary store, kept so old libraries keep working.

**Expert.** `SQLiteFullTextService` is the actor owning the connection. Nine tables: FTS5 virtual tables `documents`, `chunks`, `document_pages`, `documents_vocab`; ordinary tables `chunk_structured`, `chunk_table_rows`, `document_content`, `document_meta`, `semantic_query_cache`. `chunks` uses `tokenize='porter unicode61'`; unindexed columns get weight 0 in the `bm25()` call; `PRAGMA journal_mode=WAL` and `busy_timeout=3000`. Fallback BM25 in `HybridSearchService`: k1 1.5, b 0.5, lowered from 0.75 because chunks are near-uniform in length. `BNNSVectorDatabase`: `_vectors.bin` (contiguous Float32), `_norms.bin`, metadata JSON, mmap on load; `search` switches at `count >= 1000 && isGPUAvailable` (a Metal device and command queue) to `GPUComputeService.batchCosineSimilarity`, which picks a threadgroup kernel at 1,000 or more documents when safe, else a SIMD kernel; below that, CPU: one `vDSP_mmul` over the mapped buffer when the count is at least the device's batch threshold (16 on M-series, `Int.max` on unsupported), else per-vector `vDSP_dotpr`. Partial top-k selection avoids sorting the whole corpus. Metal buffers come from a size-bucketed pool with a residency set on supporting OS versions; the pool clears under memory warnings on iOS.

**Expert's expert.** Correction to the bank's caveat on the GPU threshold: the route does not depend on the user's GPU policy. The profile gates Core ML compute units, ingestion embedding units, the MMR similarity matrix (above 50 candidates and only if "use Metal for vector ops" is on) and concurrency ceilings. The word bank's "nine-column chunks FTS schema" is real and the column order is part of the scoring contract: a missing weight shifts every later weight silently. The `Vectura` adapter and its HNSW are kept only for libraries configured that way; they are not the default and not maintained as the architecture.

## Every concept

### 1,000-chunk GPU threshold (Conditional, verified)
- **Idiot:** small library, CPU; big library, graphics chip.
- **Dot-connector:** GPU setup costs fixed time; below a thousand vectors the CPU wins.
- **Expert:** `count >= 1000` in `BNNSVectorDatabase.search`; the second condition is `isGPUAvailable`; the profile is not consulted.

### _norms.bin (Core, verified)
- **Idiot:** the file of arrow lengths.
- **Dot-connector:** precomputed so the CPU batch path can normalise after one big multiply.
- **Expert:** written with persistence, mapped beside the vectors.

### _vectors.bin (Core, verified)
- **Idiot:** the file of all the pins.
- **Dot-connector:** flat Float32 layout is what makes mmap and matrix math possible with no object overhead.
- **Expert:** written at ingestion and rebuild, mapped for every dense search.

### Atomic vector-store persistence (Core, verified)
- **Idiot:** write the new files beside the old, then swap.
- **Dot-connector:** a crash between independent writes would pair new metadata with old vectors.
- **Expert:** temp files plus coordinated replacement; the final vector publication step.

### BM25 (Core, verified)
- **Idiot:** the formula that ranks exact-word matches.
- **Dot-connector:** rewards rare, informative terms, saturates on repetition, penalises length; the exact-language half of hybrid search.
- **Expert:** FTS5's native `bm25()` with column weights; the in-process fallback uses k1 1.5, b 0.5.

### BM25 b (Core, verified) and BM25 k1 (Core, verified)
- **Idiot:** two dials: how much length matters, how fast repeats stop counting.
- **Dot-connector:** b lowered to 0.5 because chunks are near-uniform in length; k1 1.5 balances one precise hit against many.
- **Expert:** `HybridSearchService.swift:48-49`; the same values in `RAGEngine`'s fallback.

### BNNSVectorDatabase (Core, verified)
- **Idiot:** the pin store.
- **Dot-connector:** compact metadata, contiguous vectors, precomputed norms, mmap, Accelerate, optional Metal; a serverless store for Apple unified memory.
- **Expert:** `Services/VectorStore/BNNSVectorDatabase.swift`; receives vectors after embedding, serves dense candidates before fusion.

### Busy timeout (Core, verified)
- **Idiot:** wait a few seconds if the database is busy, don't error.
- **Dot-connector:** ingestion and a query touch SQLite together routinely.
- **Expert:** `PRAGMA busy_timeout=3000`.

### chunk_structured table (Core, verified)
- **Idiot:** where tables, lists and warnings are kept as data, not prose.
- **Dot-connector:** the flattened search string loses structure; this keeps it recoverable.
- **Expert:** written with chunk records; read by extractive and response paths.

### chunk_table_rows table (Core, verified)
- **Idiot:** every table row, stored as its own row.
- **Dot-connector:** exact lookup needs the relationship among a row's cells.
- **Expert:** populated by `StructuredDocumentParser`; queried by `SpecificationExtractor` before regex fallback.

### chunks table (Core, verified)
- **Idiot:** the main word index of cards.
- **Dot-connector:** returns the same chunk IDs the vector search returns, so fusion can merge them.
- **Expert:** FTS5, nine columns, weights 10/5/1 on title, path, content.

### Container column scoping (Core, verified)
- **Idiot:** one database, a library column on every row.
- **Dot-connector:** simpler migrations than a file per library; isolation enforced by the filter.
- **Expert:** every document and chunk query includes the active container UUID.

### Content weight (Core, verified)
- **Idiot:** body text counts once.
- **Dot-connector:** searchable, but headings outrank it.
- **Expert:** weight 1.0 in the `bm25()` call.

### CPU vector path (Core, verified)
- **Idiot:** the normal-processor search.
- **Dot-connector:** below a thousand vectors, or without a GPU; SIMD is faster than GPU setup at that size.
- **Expert:** `vDSP_mmul` above the batch threshold, `vDSP_dotpr` per vector below it.

### Document-length normalization (Core, verified)
- **Idiot:** long cards don't win just for being long.
- **Dot-connector:** a short spec row can beat a long chapter that mentions the term in passing.
- **Expert:** the b term in BM25.

### document_content table (Core, verified)
- **Idiot:** the whole document's text.
- **Dot-connector:** for direct extraction and rebuilding citations, which chunks alone can't do.
- **Expert:** persisted after extraction; read by direct-answer, citation and maintenance paths.

### document_meta table (Core, verified)
- **Idiot:** counts, dates, size, which library.
- **Dot-connector:** typed metadata needs exact access, not full-text tokenisation.
- **Expert:** written with the document commit.

### document_pages table (Core, verified)
- **Idiot:** the word index per page.
- **Dot-connector:** page search, citation navigation and cross-reference repair need page granularity.
- **Expert:** FTS5; populated during extraction.

### documents table (Core, verified)
- **Idiot:** the word index of whole documents.
- **Dot-connector:** written early in extraction, before chunking; the source of the "searchable at document level but not chunk level" window.
- **Expert:** FTS5.

### documents_vocab (Support, verified)
- **Idiot:** the list of words this library actually uses.
- **Dot-connector:** query expansion from the corpus's own language beats a generic thesaurus.
- **Expert:** FTS5 vocabulary view; read by `ContainerVocabularyService` at Step 0.

### Exact vector scan (Core, verified)
- **Idiot:** check every pin.
- **Dot-connector:** no recall loss, no index maintenance, fast enough with mmap and SIMD or Metal at phone scale.
- **Expert:** the default dense operation before partial top-k.

### FTS column weight (Core, verified)
- **Idiot:** a multiplier per column.
- **Dot-connector:** matches in intentional fields count more than matches in prose.
- **Expert:** applied inside SQLite's ranking before results leave.

### FTS5 (Core, verified)
- **Idiot:** SQLite's built-in search engine.
- **Dot-connector:** substring `LIKE` is too slow and has no ranking; FTS5 has an inverted index, tokenisation, corpus statistics.
- **Expert:** four virtual tables in the schema.

### GPU vector path (Conditional, verified)
- **Idiot:** the graphics-chip search.
- **Dot-connector:** at a thousand or more vectors with Metal present, the mapped buffer goes to a kernel with no copy.
- **Expert:** `GPUComputeService.batchCosineSimilarity`; threadgroup kernel at 1,000+ when safe, else SIMD kernel; the bank's "enabled execution profile" condition is wrong.

### HNSW (Historical, verified only in the Vectura adapter)
- **Idiot:** a shortcut index the app doesn't use.
- **Dot-connector:** approximate graphs trade recall for speed at scales this app doesn't reach.
- **Expert:** associated with `VecturaVectorDatabase`; not part of the default pipeline.

### Inverse document frequency (Core, verified)
- **Idiot:** rare words count more.
- **Dot-connector:** identifiers and technical terms discriminate better than words that appear everywhere.
- **Expert:** log((N − df + 0.5) / (df + 0.5) + 1) in the fallback; FTS5 computes its own.

### Inverted index (Core, verified)
- **Idiot:** a list from each word to the cards it's on.
- **Dot-connector:** jump straight to matches instead of scanning every card.
- **Expert:** built by FTS5 at ingestion.

### Memory mapping (Core, verified)
- **Idiot:** read the file as if it were memory, without copying it.
- **Dot-connector:** a big library stays searchable with low resident memory and no copy per query.
- **Expert:** on store load; pointers handed to CPU or GPU search.

### Metal buffer pool (Support, verified)
- **Idiot:** reuse GPU memory instead of allocating fresh every time.
- **Dot-connector:** allocation dominates short GPU operations.
- **Expert:** size-bucketed `MTLBuffer`s with tier limits; cleared on memory warnings (iOS).

### Metal residency set (Conditional, verified)
- **Idiot:** keep the hot GPU buffers pinned.
- **Dot-connector:** fewer page faults for persistent vector workloads.
- **Expert:** `createResidencySet` on supporting OS versions; `makeResident` and `evictFromResidency`.

### Nine-column chunks FTS schema (Core, verified)
- **Idiot:** the chunk table has nine columns and the weights line up with them.
- **Dot-connector:** column order is part of the scoring contract.
- **Expert:** a missing weight shifts every later one silently; covered by `HybridSearchServiceTests`.

### Partial top-k selection (Core, verified)
- **Idiot:** keep the best few while scanning; don't sort everything.
- **Dot-connector:** you want tens of hits, not an ordering of thousands.
- **Expert:** during dense search before `RetrievedChunk` construction.

### persistentJSON vector-store label (Historical, verified)
- **Idiot:** an old name that still works.
- **Dot-connector:** it now routes to the BNNS binary store; kept so existing libraries load.
- **Expert:** interpreted by `VectorStoreRouter` from `KnowledgeContainer`.

### Porter tokenizer (Core, verified) and Stemming (Core, verified)
- **Idiot:** "run" finds "running."
- **Dot-connector:** grammatical variants become one search term.
- **Expert:** `porter unicode61` on the FTS tables.

### Section-path boost (Core, verified) and Section-title boost (Core, verified)
- **Idiot:** headings count five or ten times more than body text.
- **Dot-connector:** headings are concise labels and answer navigation questions directly.
- **Expert:** weights 5.0 and 10.0 in the `bm25()` call.

### SQLite (Core, verified) and SQLiteFullTextService (Core, verified)
- **Idiot:** the database and the one object allowed to touch it.
- **Dot-connector:** one serialised owner prevents connection races and keeps schema and ranking policy in one place.
- **Expert:** an actor; 3,608 lines; opens on first use, not at launch.

### SQLite transaction (Core, verified)
- **Idiot:** all the rows go in together or not at all.
- **Dot-connector:** metadata, chunks, pages and structured rows must never be partially visible.
- **Expert:** wraps multi-row ingestion, deletion and migration.

### Term frequency (Core, verified)
- **Idiot:** how often the word appears on the card.
- **Dot-connector:** more is better, with diminishing returns so stuffing doesn't win.
- **Expert:** the k1-saturated term in BM25.

### UNINDEXED FTS column (Core, verified)
- **Idiot:** stored on the row but not searchable.
- **Dot-connector:** IDs and control fields travel with hits without polluting the vocabulary.
- **Expert:** weight 0 in `bm25()`.

### Vector metadata JSON (Core, verified)
- **Idiot:** the list saying which pin is which card.
- **Dot-connector:** the float array has no identity, page, text or deletion semantics on its own.
- **Expert:** written atomically with vectors and norms; loaded before results are materialised.

### VectorDatabase protocol (Core, verified)
- **Idiot:** the plug shape for pin stores.
- **Dot-connector:** store, load, search, delete, audit; lets the physical store change under a stable contract.
- **Expert:** `VectorDatabase.swift`, beneath the router, above BNNS or Vectura.

### VectorStoreRouter (Core, verified)
- **Idiot:** picks the right pin store for the library.
- **Dot-connector:** one library, one store implementation, one live instance; the controlled switch point for migrations.
- **Expert:** consulted before persistence and every dense retrieval; compares an on-disk signature before reloading, which is what made the idle churn cheap.

### VecturaVectorDatabase (Conditional, verified)
- **Idiot:** the alternative pin store some old libraries use.
- **Dot-connector:** kept for compatibility, not the architecture.
- **Expert:** selected only when the library's vector kind requests it.

### Virtual table (Core, verified)
- **Idiot:** a table whose insides are run by a plugin.
- **Dot-connector:** FTS5 exposes search and ranking through SQL while keeping its own index.
- **Expert:** `documents`, `chunks`, `document_pages`, `documents_vocab`.

### Write-ahead logging (Core, verified)
- **Idiot:** write changes to a log first, merge later.
- **Dot-connector:** readers keep reading while ingestion writes; better crash recovery.
- **Expert:** `journal_mode=WAL` at open.
