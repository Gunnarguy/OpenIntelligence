# Storage and low-level search: the SQLite FTS5 text store and the "BNNS" vector store (OpenIntelligence at b37ab4c, shipped as 5.4)

This is a read-only audit of commit `b37ab4c` (merged 2026-09-25; the brief says its app source matches the shipped 5.4 build). Link targets are paths relative to `/home/user/OpenIntelligence`. Short names used in link text:

- `SQLFTS`: `OpenIntelligence/Services/Storage/SQLiteFullTextService.swift` (3,608 lines)
- `BNNS`: `OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift` (808 lines)
- `ROUTER`: `OpenIntelligence/Services/VectorStore/VectorStoreRouter.swift`
- `RAG`: `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift` (20,353 lines)
- `HYB`: `OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift`
- `SYNC`: `OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift`

"Repro" means I reproduced SQLite behaviour during this session with Python's `sqlite3` module (SQLite 3.45.1 with FTS5), using the app's exact DDL in an in-memory database. It shows how SQLite behaves. It says nothing about Apple's build or the owner's data. I read the Notion rows but did not edit them. A line number marked "≈" is within a few lines. I read those ranges with blank lines stripped.

## 1. Where the SQLite database lives, what is in it, and how rows are written and deleted

### Takeaway
The app keeps one SQLite file for all libraries, at `Application Support/OpenIntelligence/LocalCache/FTS5/fulltext.sqlite`. It holds:
- three FTS5 tables (`documents`, `chunks`, `document_pages`), all tokenized with `porter unicode61`, with no prefix index and no external content;
- four ordinary tables;
- a persistent query cache that is never invalidated.

Libraries are separated only by a `container_id` column, and that column is `UNINDEXED` inside every FTS5 table. There are no triggers, no `UPDATE` statements and no schema version. Writes delete and then insert, mostly outside transactions. Every per-document delete on an FTS5 table scans the whole table across all libraries.

### Cited Findings
- **File location.** There is one database file, `OpenIntelligenceRuntimePaths.localCacheDirectory()/FTS5/fulltext.sqlite`. The default is `applicationSupportRoot()/LocalCache`, which resolves to `~/Library/Application Support/OpenIntelligence/LocalCache` inside the sandbox. `[evidence_level: code_verified, confidence: exact]` — [SQLFTS:84-95](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L84-L95); [OpenIntelligenceRuntimePaths.swift:105-146](OpenIntelligence/Core/Support/OpenIntelligenceRuntimePaths.swift#L105-L146)
  - The actor reaches the path through `AppSupportPaths.localCacheDir()`. The nonisolated readers use `OpenIntelligenceRuntimePaths.localCacheDirectory()` directly. Both land on the same function. `[evidence_level: code_verified, confidence: exact]` — [KnowledgeContainer.swift:467-469](OpenIntelligence/Core/Models/KnowledgeContainer.swift#L467-L469)
- **Isolation is by column, not by table.** The file's own header says "Container isolation via separate tables per container" (line 15). The schema contradicts that: every table carries a `container_id` column. The hard-boundary doc describes it correctly: "Single shared SQLite file with `container_id` column isolation". `[evidence_level: code_verified, confidence: exact]` — [SQLFTS:15](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L15), [SQLFTS:190-347](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L190-L347), [03_FORBIDDEN_EDIT_BOUNDARIES.md:25](Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md)
- **The eight tables created in `initializeDatabase()`** `[evidence_level: code_verified, confidence: exact]` — [SQLFTS:169-350](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L169-L350):
  1. **`documents`**, FTS5. Columns: `document_id UNINDEXED, container_id UNINDEXED, content`. Tokenizer `porter unicode61`. Default `columnsize`, and it stores its own copy of the content. (L190-197)
  2. **`document_meta`**: `document_id TEXT PRIMARY KEY, container_id TEXT NOT NULL, character_count INTEGER NOT NULL, word_count INTEGER NOT NULL, created_at REAL NOT NULL`. (L211-219)
  3. **`document_content`**: `document_id TEXT PRIMARY KEY, container_id TEXT NOT NULL, content TEXT NOT NULL`. This is a second full copy of each document's text. It was added because looking up `WHERE document_id = ?` on the FTS table is a full scan, which caused "30+ second hangs". (L222-233)
  4. **`chunks`**, FTS5, nine columns in this order: `chunk_id, document_id, container_id, chunk_index, page_number` (all UNINDEXED), `section_title, section_path` (indexed), `structure_type` (UNINDEXED), `content` (indexed). Tokenizer `porter unicode61`, `columnsize=0`. (L241-255)
  5. **`chunk_structured`**, 17 columns: `chunk_id TEXT PK, document_id, container_id, chunk_index, page_number, section_title, section_path, structure_type, chunk_type, table_title, table_headers_json, table_rows_json, table_row_count, table_column_count, extraction_quality, extraction_source, search_text`. B-tree indexes on `container_id`, `document_id`, `structure_type` and `table_title`. (L261-286)
  6. **`chunk_table_rows`**, 15 columns: `row_id TEXT PK, chunk_id, document_id, container_id, chunk_index, page_number, table_title, row_index, headers_json, row_json, row_text, row_quality, is_low_quality, extraction_quality, extraction_source`. Indexes on `container_id`, `document_id` and `chunk_id`. (L288-310)
  7. **`document_pages`**, FTS5: `page_id, document_id, container_id, page_number` (all UNINDEXED) and `content`. Tokenizer `porter unicode61`. (L320-329)
  8. **`semantic_query_cache`**: `normalized_query, container_id, embedding_json, results_json, created_at`, with `PRIMARY KEY(normalized_query, container_id)` and an index on `container_id`. (L336-347)
- **A ninth table, `documents_vocab`, almost certainly never exists.** It is an `fts5vocab(documents,'row')` table created lazily, at query time, only when `checkVocabularyPresence` is called without a container. The only caller, HyDE grounding, always passes a `containerId`. `[evidence_level: grep_verified, confidence: high]` — [SQLFTS:3510-3515](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L3510-L3515); [HyDEService.swift:128-131](OpenIntelligence/Services/Query/Rewriting/HyDEService.swift#L128-L131)
- **What the file does not contain.** No `CREATE TRIGGER`, no external-content (`content=`) or contentless tables, no `prefix=` index, no `detail=` option and no `UPDATE … SET` anywhere in the file. `document_meta` and `document_content` have no index on `container_id`. `[evidence_level: grep_verified, confidence: exact]` — [SQLFTS](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift)
- **`store(text:append:)`** runs these steps, with no transaction and without checking whether the content and metadata inserts succeeded `[evidence_level: code_verified, confidence: exact]` — [SQLFTS:362-431](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L362-L431):
  1. If appending, read the existing text and concatenate the new text onto it.
  2. Call `delete(for:)`, which issues four DELETEs.
  3. `INSERT` into `documents`.
  4. `INSERT OR REPLACE` into `document_content`.
  5. `INSERT OR REPLACE` into `document_meta`.
  6. Run a PASSIVE WAL checkpoint.
- **`storeChunks`**. `[evidence_level: code_verified, confidence: exact]` — [SQLFTS:834-910](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L834-L910)
  - Unless appending, it runs `deleteChunks(for:)` in autocommit before `BEGIN` (L846-849, L858).
  - It prepares the INSERT again for every chunk (L861-862).
  - It builds `chunk_id = "<documentUUID>_<chunkIndex>"` (L864).
  - It ignores the result of `sqlite3_step` (L879), then commits and checkpoints (L907-908).
  - Structured table metadata goes into `chunk_structured` and per-row `chunk_table_rows` via `INSERT OR REPLACE`. Rows flagged low quality with a score below 0.28 are skipped (L1085-1087).
- **`storePages`** deletes the document's pages unless appending, then inserts one row per page inside a transaction with `page_id = "<doc>_p<n>"`. Failures are logged and the transaction commits anyway. `[evidence_level: code_verified, confidence: exact]` — [SQLFTS:438-501](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L438-L501)
- **Deletes are split across functions.** `[evidence_level: code_verified, confidence: exact]` — [SQLFTS:629-739](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L629-L739), [SQLFTS:974-1007](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L974-L1007)
  - `delete(for:)` removes rows from `documents`, `document_meta`, `document_pages` and `document_content`, but not from `chunks`.
  - `deleteChunks(for:)` removes `chunks`, `chunk_structured` and `chunk_table_rows`.
  - `deleteContainer` and `deleteChunksForContainer` do the same two jobs by `container_id`.
- **Nothing ever deletes from `semantic_query_cache`.** I checked two ways: the table name, and plausible invalidation method names. `[evidence_level: grep_verified, confidence: exact]` — [SQLFTS:3314-3435](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L3314-L3435)
- **Who writes.** `[evidence_level: code_verified, confidence: exact]`
  - Document text and pages are written by `DocumentProcessor` before chunks are embedded, including an `append:` variant — [DocumentProcessor.swift:642, 813, 822](OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift#L642)
  - Chunk rows are written by `RAGService` after the vectors are persisted — [RAG:6609-6613](OpenIntelligence/Services/RAG/Orchestration/RAGService.swift#L6609-L6613)
  - The streamed large-PDF import writes chunk rows per page batch with `append: true` — [RAGService+Streaming.swift:191-196](OpenIntelligence/Services/RAG/Orchestration/RAGService+Streaming.swift#L191-L196)
- **Filtering on UNINDEXED columns scans the whole table.** In the repro, `EXPLAIN QUERY PLAN` gave:
  - `SCAN chunks VIRTUAL TABLE INDEX 0:` for `DELETE FROM chunks WHERE document_id=?`;
  - the same for `SELECT content FROM documents WHERE document_id=?`;
  - `INDEX 0:M9` for `… MATCH ? AND container_id=?`, meaning the full-text match runs first and the container filter is applied row by row.

  `[evidence_level: code_verified (DDL) + repro, confidence: high]` — [SQLFTS:190-255](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L190-L255)

### Inferences
- **Per-document deletes cost the whole corpus.** Every delete by document on `documents`, `document_pages` or `chunks` scans the entire table, and that table spans all libraries. Re-ingesting, deleting or appending one document therefore costs work proportional to the total corpus.
  - Library deletion loops over each document's removal, so it costs about D × corpus — [LibraryDeletion.swift:98-101](OpenIntelligence/Features/Documents/Library/LibraryDeletion.swift)
  - The streamed import re-writes the document text on every batch through `store(text:append:true)` (read, concatenate, delete, insert), so a large PDF costs about O(batches × document size), plus the full-table scans.
- **Each document's text is stored about five times:**
  1. the `documents` FTS content shadow table;
  2. `document_content`;
  3. `document_pages`;
  4. `chunks` (with overlap);
  5. the vector store's `_meta.json`, which holds `content` and `parentContent` (see section 5).

### Gaps
- There is no on-device figure for `fulltext.sqlite` size or row counts. The only hint is a code comment about orphan rows (section 9).
- The SQLite version and compile options Apple ships (for example the default `synchronous` in WAL mode) were not checked on device.

## 2. BM25 weights at every call site, how query strings are built, and snippet/highlight use

### Takeaway
The nine-column / eight-weight defect is fixed. All four `bm25(chunks, …)` call sites pass nine weights aligned to the declared columns: `section_title` 10, `section_path` 5, `content` 1. No other `bm25(chunks …)` call exists.

The lexical arm is still weak in structural ways:
- Queries are AND-of-quoted-terms with an OR fallback, and they drop stopwords and one-character tokens.
- Porter stemming breaks identifiers, and there is no trigram or prefix index.
- `unicode61` cannot segment CJK text.
- BM25 statistics are computed over the shared table across all libraries.
- `highlight()` is advertised in the header and in a dashboard badge but never called.

### Cited Findings
- **`chunks` weights.** All four call sites pass `bm25(chunks, 0, 0, 0, 0, 0, 10.0, 5.0, 0, 1.0)`: two SELECT expressions and two ORDER BYs, for the container-scoped and unscoped queries. A comment pins the nine-column list next to the vector. `[evidence_level: code_verified, confidence: exact]` — [SQLFTS:1440-1473](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L1440-L1473) (L1458, 1461, 1468, 1471)
  - No other `bm25(chunks` exists in Swift source. The only other `bm25(` calls are unweighted `documents` and `document_pages` calls. `[evidence_level: grep_verified, confidence: exact]`
- **The recorded defect is now repaired.** It was eight weights at all four sites, which shifted every weight one column to the left: `section_path` got 0 and `section_title` got 5. `[evidence_level: doc_claim_only for the history, confidence: high]` — [Docs/Archive/CHANGELOG_2.0_to_5.2.md:402](Docs/Archive/CHANGELOG_2.0_to_5.2.md); [Notion: FTS5 bm25/trigram row](https://app.notion.com/3b149a74d54f81248feaf48022482a63)
  - In the repro, a chunk that matches only in `section_path` scores `-0.0` with eight weights and a non-zero score with nine. `[evidence_level: repro, confidence: exact for SQLite semantics]`
- **`documents` and `document_pages` use unweighted `bm25()`.** Each has exactly one indexed column, so weights would change nothing. `[evidence_level: code_verified, confidence: exact]` — [SQLFTS:516-523](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L516-L523), [SQLFTS:1566-1583](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L1566-L1583)
- **Score sign handling.** `ORDER BY bm25(...)` is ascending (more negative is better). `bm25Scores` negates the value and uses `limit: 1000`. `HybridSearchService` maps each score with `bm25Score < 0 ? -x : x`, which also absorbs the positive scores from the Swift-scored structured fallback. `[evidence_level: code_verified, confidence: exact]` — [SQLFTS:1760-1775](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L1760-L1775); [HYB:≈1108-1112](OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift#L1108-L1112); [SQLFTS:1264, 1384](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L1264)
- **How `escapeFTS5Query` builds a query.** `[evidence_level: code_verified, confidence: exact]` — [SQLFTS:3228-3293](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L3228-L3293)
  1. Lowercase the input and split on whitespace.
  2. Trim leading and trailing punctuation from each token and double any internal `"`.
  3. Drop tokens shorter than two characters and a fixed list of English stopwords and framing words (L3233-3243).
  4. Wrap each surviving token in double quotes and join with spaces, giving an implicit AND of quoted terms.
  5. If nothing survives, send the whole input as one quoted phrase.
  - The broad variant joins with ` OR ` instead.
  - There is no prefix `*`, no NEAR, no column filter and no synonym expansion.
- **`searchChunks` falls back in three steps:** the AND query, then the OR query, then a Swift-scored scan of structured tables. `[evidence_level: code_verified, confidence: exact]` — [SQLFTS:1529-1546](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L1529-L1546)
- **Tokenizer behaviour** (repro, same `porter unicode61` tokenizer). `[evidence_level: repro, confidence: high]`
  - "NSURLSession" is indexed as `nsurlsess`, so the query `"urlsession"` gets 0 hits.
  - `"90915"` gets 0 hits against "90915YZZD1".
  - Diacritics are folded: `"cafe"` matches "Café".
  - A Japanese sentence (`東京都の地下鉄は便利です`) is indexed as one token, so `"地下鉄"` gets 0 hits.

  The owner's row reports the same two identifier misses against sqlite3 3.54.0. — [Notion FTS5 row](https://app.notion.com/3b149a74d54f81248feaf48022482a63)
- **`termExistsInContainer` binds raw, unquoted terms into MATCH.** `[evidence_level: code_verified + repro, confidence: exact]` — [SQLFTS:3552-3565](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L3552-L3565)
  - In the repro, `x-ray` raises "no such column: ray". `don't`, `e.g`, `5w-30` and `c++` raise FTS5 syntax errors. The function then returns `false`, so the word is reported absent.
  - Its only consumer is HyDE grounding, which removes every word reported absent from the hypothetical document. — [HyDEService.swift:111-150](OpenIntelligence/Services/Query/Rewriting/HyDEService.swift#L111-L150)
- **The no-container vocabulary path has a stemming mismatch, but it is dead in practice.** It compares a hand-written stemmer against porter-stemmed `fts5vocab` terms. In the repro the vocabulary holds `engin`, `run` and `us`, while the hand stemmer turns "engine", "running" and "use" into `engine`, `runn` and `use`, so all three would be reported absent. The only caller always passes a container. `[evidence_level: code_verified + repro, confidence: high]` — [SQLFTS:3515-3601](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L3515-L3601)
- **Snippets are used; `highlight()` is not.** `[evidence_level: grep_verified, confidence: exact]` — [SQLFTS:14](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L14); [DatabaseDashboardView.swift:1016](OpenIntelligence/Features/Database/DatabaseDashboardView.swift#L1016)
  - `snippet(…, '<b>','</b>','...',32)` on `documents` and `document_pages`, and `snippet(documents, 2, '>>>>','<<<<','...', contextChars/6)` in `searchCorpus`.
  - `highlight()` is never called. `FTS5SearchResult.highlightedContent` is always `nil` (L1621, L1689), yet the header (L14) and a dashboard badge both claim `highlight()`.
- **Structured-table search does not use FTS.** It scans every `chunk_structured` or `chunk_table_rows` row for the container and scores with Swift `contains`. Quality gates: `extraction_quality >= 0.26` and `row_quality >= 0.38`. `[evidence_level: code_verified, confidence: exact]` — [SQLFTS:1189-1410](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L1189-L1410)
- **`countPatternInCorpus` and `searchCorpus`** load the full content of every matching document and count substrings in Swift. `[evidence_level: code_verified, confidence: exact]` — [SQLFTS:1698-1847](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L1698-L1847)

### Inferences
- **Scores depend on other libraries.** FTS5 computes bm25 statistics (row count, term document frequency, average column length) over the whole shared table, and `container_id` is only a post-match filter. A library's lexical scores therefore depend on every other library's content and on any orphan rows left behind (see the 4,077-document-id figure in section 9). The mechanism comes from how FTS5 defines bm25; the effect has not been measured. `[evidence_level: inferred, confidence: high]`
- **`columnsize=0` makes bm25 slower.** According to SQLite's documentation, with `columnsize=0` on a table that stores content, bm25 gets column sizes by re-tokenizing each matched row at query time. `[evidence_level: inferred, confidence: medium-high]`
- **Single-digit numbers are dropped.** The `count >= 2` filter removes values like "5" or "8" from lexical queries, so a spec lookup whose discriminating value is one digit loses that constraint. `[evidence_level: inferred, confidence: high]`
- **Non-English libraries.** Porter stemming is English-only and `unicode61` does not segment CJK, so the lexical arm is close to useless for CJK libraries. It stays degraded, though consistent, for other languages.

### Gaps
- No lexical latency or recall measurement at scale that separates tokenizer effects from ranking effects was found. The Notion row says trigram "cannot be demonstrated at ~21% retrieval reproducibility" and measured +104% to +263% database growth for it — [Notion FTS5 row](https://app.notion.com/3b149a74d54f81248feaf48022482a63)

## 3. Connections, durability, transactions, schema versioning and maintenance

### Takeaway
All access goes through one long-lived connection owned by a singleton actor, in WAL mode with a 3 s busy timeout. The dashboard's direct readers open extra ad-hoc connections. Nothing else is tuned. Batching is partial, and the chunk rewrite is not atomic. There is no schema version, only additive `ALTER TABLE` migrations. Maintenance (optimize, rebuild, integrity check) covers only the `documents` table and runs only when a user presses a button.

### Cited Findings
- **Connections.** `[evidence_level: code_verified, confidence: exact]` — [SQLFTS:45-165](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L45-L165), [SQLFTS:2888-3037](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L2888-L3037)
  - A singleton `actor SQLiteFullTextService` owns one `OpaquePointer` connection, opened lazily with `sqlite3_open` on first use. The actor serializes every call.
  - Extra connections, each opened per call:
    - `backgroundPopulateContentTable`: read-write, 5,000 ms busy timeout;
    - `readContentDirectly`: read-only, no busy timeout;
    - `migrateRowToContentTable`: read-write, 3,000 ms busy timeout.
- **PRAGMAs.** Only `journal_mode=WAL` and `busy_timeout=3000` are set. `synchronous`, `cache_size`, `mmap_size`, `temp_store` and `user_version` are only read, in diagnostics. `[evidence_level: code_verified + grep_verified, confidence: exact]` — [SQLFTS:183-184](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L183-L184), [SQLFTS:≈2292-2345](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L2292-L2345)
- **Checkpoints.** A PASSIVE `wal_checkpoint` runs after nearly every write method (for example L429, 498, 673, 737, 831, 908, 988, 1006, 3385). When the scene goes to the background, the app runs `TRUNCATE` and closes the connection. `[evidence_level: code_verified, confidence: exact]` — [SQLFTS:110-137](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L110-L137); [ContentView.swift:≈403-406](OpenIntelligence/App/ContentView.swift#L403-L406)
- **Transactions.** Only `storePages` and `storeChunks` wrap their work in `BEGIN`/`COMMIT`. The only rollback is when `storePages` fails to prepare a statement. `store(text:)`, the deletes and cache writes all autocommit statement by statement. `[evidence_level: code_verified, confidence: exact]` — [SQLFTS:139-158, 459-497, 858-907](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L139-L158)
- **Schema versioning.** `CREATE … IF NOT EXISTS` plus a closed enum of six additive `ALTER TABLE ADD COLUMN` migrations, checked through `PRAGMA table_info`. FTS5 virtual tables cannot be altered, so changing a tokenizer or column means dropping the table and rebuilding it. That is why the schema is a hard boundary ("Schema changes are destructive migrations"). `[evidence_level: code_verified, confidence: exact]` — [SQLFTS:3082-3156](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L3082-L3156); [03_FORBIDDEN_EDIT_BOUNDARIES.md:25](Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md)
- **Maintenance.** `[evidence_level: code_verified + grep_verified, confidence: exact]` — [SQLFTS:2715-2783](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L2715-L2783); [DatabaseDashboardView.swift:1305, 1342](OpenIntelligence/Features/Database/DatabaseDashboardView.swift#L1342)
  - `optimize()` runs `INSERT INTO documents(documents) VALUES('optimize')` and then `VACUUM`, on the actor's connection, from a Database dashboard button.
  - `rebuildIndex()` and the FTS5 `integrity-check` also touch only `documents`.
  - Nothing optimizes or merges `chunks` or `document_pages`, and there is no `PRAGMA optimize`.
- **`migrateRowToContentTable` can fail silently.** It binds `NULL` to `document_content.container_id` when the FTS row has none, but that column is `NOT NULL`, so the insert fails and nobody checks. `[evidence_level: code_verified, confidence: exact]` — [SQLFTS:3029-3033](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L3029-L3033) vs [SQLFTS:230](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L230)

### Inferences
- **Durability gaps.** `storeChunks` deletes a document's chunk rows before its transaction begins. A crash or kill between that DELETE and the COMMIT leaves the document with zero FTS chunk rows. Failed chunk INSERTs are also committed silently, because the step result is ignored.
- **Blocking.** `VACUUM` rewrites the whole database on the actor's only connection, so every FTS call, including those on the query path, waits until it finishes. It also needs free disk roughly equal to the database size.
- **Import overhead.** Re-preparing the INSERT per row and checkpointing after every call adds cost to bulk imports. This has not been measured.

### Gaps
- Apple's default `synchronous` level in WAL mode, and WAL file growth during large imports, are not observable from code.

## 4. The vector store: on-disk format, memory mapping, similarity, search, isolation, deletion, integrity, dimension change, quantization

### Takeaway
Each library gets a flat, exhaustive, Float32 cosine index:
- `_vectors.bin`: raw floats with no header, memory-mapped;
- `_norms.bin`: precomputed L2 norms;
- `_meta.json`: a JSON array holding every chunk's text and metadata, decoded fully into RAM.

There is no approximate-nearest-neighbour index, no quantization, and no stored dimension, version or checksum. Despite the class name, no BNNS API is called. Every persist, delete or update rewrites the whole library's files. The only integrity check is size arithmetic, and a mismatch either wipes all three files or truncates them into misaligned vectors.

### Cited Findings
- **Files.** A per-library base path, `baseDir()/vector_database_<containerUUID>.json`, is kept as a legacy name and used only to derive the three binary file names. `[evidence_level: code_verified, confidence: exact]` — [BNNS:119-139](OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift#L119-L139); [KnowledgeContainer.swift:≈483-486](OpenIntelligence/Core/Models/KnowledgeContainer.swift#L483-L486); [ROUTER:149-152](OpenIntelligence/Services/VectorStore/VectorStoreRouter.swift#L149-L152)
- **Record layout.** `[evidence_level: code_verified, confidence: exact]` — [BNNS:307-337](OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift#L307-L337), [BNNS:428-434](OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift#L428-L434)
  - `_vectors.bin` holds N × d contiguous `Float32` values, with no header, magic number, version, dimension or checksum.
  - `_norms.bin` holds N `Float32` values.
  - `_meta.json` is a `JSONEncoder` array of `DocumentChunk` with `embedding: []`.
- **The dimension lives outside the files.** It is `container.embeddingDim`, passed in when the store is constructed. The default is 384 (MiniLM through Core ML). `[evidence_level: code_verified, confidence: exact]` — [ROUTER:152](OpenIntelligence/Services/VectorStore/VectorStoreRouter.swift#L152); [KnowledgeContainer.swift:169, 224](OpenIntelligence/Core/Models/KnowledgeContainer.swift#L169)
- **Load.** `[evidence_level: code_verified, confidence: exact]` — [BNNS:143-282](OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift#L143-L282)
  - The whole `_meta.json` is decoded into `[DocumentChunk]`, which stays in the actor.
  - `_vectors.bin` is loaded with `Data(contentsOf:options:.alwaysMapped)`.
  - Norms are copied into RAM, or recomputed from the mapped vectors if the norms file has the wrong size.
  - A one-time path migrates the legacy JSON format and skips chunks whose dimension does not match.
- **The only integrity check is size arithmetic.** The expected size is `count × d × 4` bytes. `[evidence_level: code_verified, confidence: exact]` — [BNNS:179-204](OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift#L179-L204)
  - If the file is larger by an exact multiple, it is truncated to the prefix and rewritten ("Repairing oversized vector file").
  - Any other mismatch deletes `_meta.json`, `_vectors.bin` and `_norms.bin` ("Clearing corrupted files").
- **Writes.** `[evidence_level: code_verified, confidence: exact]` — [BNNS:420-473](OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift#L420-L473), [BNNS:307-343](OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift#L307-L343)
  - `storeBatch` buffers vectors in `pendingEmbeddings` and silently drops any chunk whose embedding length is not d. It logs a warning under `.vectorDB`, a category that code comments say never reaches the file logs a user can share.
  - `persist()` calls `saveToDisk()`, which:
    1. writes the entire `_meta.json` atomically;
    2. builds one heap `Data` of *all mapped vectors + pending vectors* and writes `_vectors.bin` atomically;
    3. writes `_norms.bin`.

    These are three separate atomic writes, in that order.
  - `store(chunk:)` persists on every call.
- **Search.** `[evidence_level: code_verified, confidence: exact]` — [BNNS:486-607](OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift#L486-L607); [DeviceCapabilityService.swift:611](OpenIntelligence/Services/Infrastructure/Monitoring/DeviceCapabilityService.swift#L611)
  - Every vector in the library is scored. Cosine is computed as dot / (‖q‖·‖d‖) using the stored norms.
  - Metal GPU path when N ≥ 1,000 and Metal vector ops are enabled.
  - Otherwise a CPU `vDSP_mmul` when N reaches a threshold that depends on the device tier, else a per-row `vDSP_dotpr`.
  - Top-K uses a min-heap partial sort only when k ≤ 20 and N > 100. In every other case it fully sorts all N scores.
- **No approximate index and no quantization.** `[evidence_level: grep_verified + code_verified, confidence: high]` — [ROUTER:158-166](OpenIntelligence/Services/VectorStore/VectorStoreRouter.swift#L158-L166); [VecturaVectorDatabase.swift:1-15](OpenIntelligence/Services/VectorStore/VecturaVectorDatabase.swift)
  - The `.vecturaHNSW` kind falls back to this store unless `canImport(VecturaKit)`. VecturaKit appears in no `Package.swift` or `Package.resolved`.
  - Vectors are Float32 only.
- **The class name is a misnomer.** No BNNS API is called anywhere in `BNNSVectorDatabase.swift`. The math is Accelerate `vDSP` plus Metal. The repo's own naming rule forbids labelling a mechanism with a technique it does not implement. `[evidence_level: code_verified, confidence: exact]` — [BNNS (whole file)](OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift); [.claude/rules/ingestion-and-indexing.md](.claude/rules/ingestion-and-indexing.md)
- **GPU "zero-copy" is conditional.** `GPUComputeService` first tries `makeBuffer(bytesNoCopy:)` on the mapped pointer. If that fails, it falls back to `makeBuffer(bytes:)`, a full copy of every vector for each query; the code comment says this happens when the "length isn't page-aligned". When writes are pending, `withAllVectorBytes` already builds a full combined copy for every search. `[evidence_level: code_verified, confidence: exact]` — [GPUComputeService.swift:741-805](OpenIntelligence/Services/Infrastructure/Compute/GPUComputeService.swift#L741-L805); [BNNS:386-416](OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift#L386-L416)
- **Isolation per library.** `VectorStoreRouter`, a `@MainActor` class, caches one store instance and one file set per container. `[evidence_level: code_verified, confidence: exact]` — [ROUTER:25-171](OpenIntelligence/Services/VectorStore/VectorStoreRouter.swift#L25-L171)
  - On a memory warning it persists and then evicts non-active stores.
  - On a mismatch in dimension or kind, it persists the outgoing store and builds a new one.
  - `clearAll()` reloads only stores whose on-disk size or modification date changed.
- **Deletion is compaction.** `[evidence_level: code_verified, confidence: exact]` — [BNNS:609-764](OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift#L609-L764)
  - `deleteChunks(forDocument:)` scans all chunks, writes the kept vectors to a `.tmp` file, deletes `_vectors.bin`, moves the temp file into place, remaps it, and then rewrites the full `_meta.json`.
  - `updateChunk` rewrites the whole file to change one vector.
  - `exists` and `getEmbeddings(forChunkIDs:)` are O(N) linear scans and do not wait for the initial load to finish.
- **Dimension changes.** `[evidence_level: code_verified, confidence: exact]` — [ContainerSettingsSheet.swift:694-713](OpenIntelligence/Features/Documents/Settings/ContainerSettingsSheet.swift#L694-L713); [RAG:7955-7960, 8120-8122](OpenIntelligence/Services/RAG/Orchestration/RAGService.swift#L7955-L7960); [RAG:≈4705-4722](OpenIntelligence/Services/RAG/Orchestration/RAGService.swift#L4705-L4722)
  - Settings now calls `invalidateVectorStore(clearStorage: false)` when the dimension or provider changes. The comment explains why: deleting the files before the "Rebuild embeddings now?" dialog left libraries with no vectors.
  - Re-embedding happens per document, in place. It reads the document's chunks via `allChunks()` (or from FTS5 if that returns nothing), then calls `deleteChunks` + `storeBatch` + `persist` on the same store.
  - The startup reconcile rewrites `container.embeddingDim` to the provider's actual dimension.

### Inferences
- **The loader can undo Settings' safety fix.** Whenever the store is next opened with a new dimension, the size check in `loadFromDisk` runs against the old file. `[evidence_level: inferred, confidence: high that the path exists; unverified on device]`
  - If the dimension grows (384→768), or the ratio is not an integer (384↔512), the loader deletes all three files.
  - If the old dimension is an exact multiple of the new one (768→384), the loader "repairs" the file by truncating it to its first half. Search then serves N misaligned half-vectors until re-embedding finishes.

  Either way, the "don't delete until the user agrees" fix in Settings is overridden as soon as anything opens the store.
- **Crash windows that wipe a library's vectors.** `[evidence_level: inferred, confidence: medium-high]`
  - `saveToDisk` writes meta, then vectors, then norms. A kill between the meta write and the vector write leaves `meta.count × d × 4` different from the vector file size, and the next load deletes all three files.
  - `deleteChunks` has the same exposure between swapping the vector file and writing meta.
  - Between `removeItem(_vectors.bin)` and `moveItem(tmp→_vectors.bin)` (BNNS:654-655), the vector file does not exist. A load in that window drops to the legacy path, which has no legacy file, and comes up empty. The next persist would then overwrite `_meta.json` with only the new chunks.
- **What actually scales badly.** Arithmetic is not the limit: at d = 384, 50,000 vectors is about 19M multiply-adds and about 73 MB read per query, acceptable on Apple silicon. What does not scale:
  - full-file rewrites on every import, delete, re-embed step and sync write, each O(library);
  - `_meta.json` decoding and residency (section 5);
  - the per-query full copy for the GPU whenever the no-copy buffer fails.

### Gaps
- No on-device search latency, `_meta.json` size, or GPU-copy frequency is recorded in the repo.
- Whether the GPU no-copy buffer normally succeeds depends on Metal's alignment rules and file lengths. I did not check this against Apple's documentation.

## 5. Where chunk text and metadata live, how DocumentChunk objects are loaded, and what `allChunks()` costs

### Takeaway
Every retrieval arm treats the vector store's `_meta.json` as the working copy of the chunks. It is decoded whole at load and kept resident for every cached library. `allChunks()` itself is cheap: no I/O, and a copy-on-write array. But many query-time callers then scan or index every chunk: the spec sniper on every Deep Think/Maximum precision lookup, the standard pipeline on every query, and hybrid search whenever FTS5 returns a chunk the vector arm did not.

### Cited Findings
- **`DocumentChunk` fields:** `id` (a random `UUID()` by default), `documentId`, `content`, `parentContent`, `contextualPrefix`, `embedding`, and `metadata`. `ChunkMetadata` has about 30 fields, including `chunkIndex`, `keywords`, `entities`, `abbreviations`, `sectionPath`, `bboxArray`, `abstractionLevel` and table/image fields. `[evidence_level: code_verified, confidence: exact]` — [DocumentChunk.swift:12-51, 115+](OpenIntelligence/Core/Models/DocumentChunk.swift#L12-L51)
- **Where text lives.** `[evidence_level: code_verified, confidence: exact]` — [SQLFTS:241-255](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L241-L255); [BNNS:428-434](OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift#L428-L434)
  - Chunk text is in both stores. FTS `chunks.content` holds the chunk text alone. `_meta.json` holds `content`, `parentContent`, `contextualPrefix` and all metadata.
  - Whole-document text and page text live only in SQLite.
- **`allChunks()` returns the in-memory array.** It is filled by `loadFromDisk` and not re-read from disk. `[evidence_level: code_verified, confidence: exact]` — [BNNS:695-698](OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift#L695-L698)
- **Query-time callers.** `[evidence_level: code_verified, confidence: exact]`
  - **Standard pipeline, every query:** the comment reads "Always load allChunks — needed for parent doc expansion, lexical recall…" — [RAG:9880-9910](OpenIntelligence/Services/RAG/Orchestration/RAGService.swift#L9880-L9910)
  - **Deep Think / Maximum precision lookup:** `allChunks()` feeds `specTableSniper`, which scores every chunk's text through `EvidenceScoringPolicyService.specSniperScore` and keeps the top 3 — [RAG:8697-8704](OpenIntelligence/Services/RAG/Orchestration/RAGService.swift#L8697-L8704), [RAG:2527-2575](OpenIntelligence/Services/RAG/Orchestration/RAGService.swift#L2527-L2575)
  - **Other retrieval entry points:** [RAG:19458, 19814](OpenIntelligence/Services/RAG/Orchestration/RAGService.swift#L19458)
  - **Hybrid search:** it builds a dictionary over *all* chunks whenever any FTS5 hit is missing from the vector results, and `lexicalRecallCandidates` iterates all chunks, in both cases when `cachedChunks` is not passed — [HYB:≈1085-1106](OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift#L1085-L1106), [HYB:737-790](OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift#L737-L790)
  - **Non-query callers:** getSampleChunks (RAG:4248), visualization (RAG:4194), streaming (RAGService+Streaming.swift:247), re-embed (RAG:7957), rebuild (RAG:7411), sync (SYNC:1903).
- **`lexicalRecallCandidates` probably never produces candidates with this store.** It skips any chunk whose `embedding.count` differs from the query embedding's length, and this store returns chunks with `embedding: []`. `[evidence_level: code_verified for both lines; combined effect inferred, confidence: high]` — [HYB:750-752](OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift#L750-L752); [BNNS:428-434, 695-698](OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift#L428-L434)
- **Memory claims in the file header:** "0 bytes heap for 73 MB of embeddings" (50K × 384 × 4), norms 200 KB, and `_meta.json` "~5-10 MB" for 50K chunks. The legacy JSON format peaked at about 650 MB. `[evidence_level: doc_claim_only (code comment), confidence: low for the meta figure]` — [BNNS:14-36](OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift#L14-L36)
- **Sync opens extra copies.** Every sync pass that is not skipped constructs a separate store instance per library per root, decodes all of `_meta.json`, and hydrates every embedding. A 2026-08-24 capture counted 128 store opens and 43,164 chunk records deserialised in one session with zero writes, 64 opens and 21,582 records of them before the first screen was drawn. A size-and-modification-date signature fast path now skips unchanged passes. `[evidence_level: measured per code comment; fast path code_verified, confidence: high]` — [SYNC:218-233](OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift#L218-L233), [SYNC:1893-1918](OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift#L1893-L1918)

### Inferences
- **What `allChunks()` really costs.** O(1) at the call, but in practice:
  1. every cached library's full text and metadata stays resident until a memory warning evicts non-active stores;
  2. several stages do O(N) Swift work on every query;
  3. a chunk missing from `_meta.json` is invisible to the dense arm, to FTS resolution (section 6) and to the spec sniper.

  So the precision-lookup "shortcut" can only extract from chunks the vector store holds.
- **The header's meta estimate is probably 6–12× too low.** A sync comment calls the rewrite of the largest store (about 1,451 chunks) a "4 MB write". Subtracting 2.23 MB of vectors (1,451 × 384 × 4) leaves about 1.2 KB of metadata JSON per chunk, or about 60 MB for 50K chunks, before Swift string overhead. `[evidence_level: inferred, confidence: low-medium]`

### Gaps
- No recorded `_meta.json` sizes or resident-memory measurements per library.

## 6. Consistency between the two stores: how IDs link, partial writes, chunks without vectors

### Takeaway
The two stores share no identifier. FTS rows are keyed `"<documentId>_<chunkIndex>"`, vector chunks carry random UUIDs, and hybrid search joins them on `(documentId, chunkIndex)`. It silently discards FTS hits with no vector-store twin. Writes to the two stores are independent, with no transaction or reconciliation, and there are several silent drop paths. The health check fires only when a library has zero vectors. Partial loss, such as the owner's 452 missing vectors, cannot trigger a repair.

### Cited Findings
- **The join key.** `[evidence_level: code_verified, confidence: exact]` — [SQLFTS:864](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L864); [DocumentChunk.swift:34-43](OpenIntelligence/Core/Models/DocumentChunk.swift#L34-L43); [HYB:≈1071-1128](OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift#L1071-L1128)
  - FTS `chunk_id` is `"\(documentId.uuidString)_\(chunkIndex)"`.
  - Ingestion builds `DocumentChunk` without an `id`, so each gets a random `UUID()`.
  - `HybridSearchService` looks chunks up by `"\(documentId)_\(metadata.chunkIndex)"`. Hits it cannot resolve fall into a branch whose comment reads "else: FTS5 hit doesn't match any known chunk — skip (stale index)".
- **Ingestion writes each store separately, in this order.** FTS failures are not surfaced. `[evidence_level: code_verified, confidence: exact]` — [DocumentProcessor.swift:642, 813, 822](OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift#L642); [RAG:6521-6523, 6609-6613, 6699, 6732](OpenIntelligence/Services/RAG/Orchestration/RAGService.swift#L6521-L6523)
  1. `DocumentProcessor` writes FTS `documents` and `document_pages`.
  2. Vectors: `storeBatch` + `persist` (a full-library rewrite).
  3. FTS `chunks`.
  4. The summary chunk: `storeBatch([summaryChunk])`.
  5. A second `persist`, another full-library rewrite.
- **Silent drop paths.** `[evidence_level: code_verified, confidence: exact]` — [RAG:6444](OpenIntelligence/Services/RAG/Orchestration/RAGService.swift#L6444); [BNNS:442-445](OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift#L442-L445); [SYNC:1906-1908](OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift#L1906-L1908); [DocumentProcessor.swift:675, 1074, 1090](OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift#L675)
  - `zip(zip(processedChunks, embeddings), contextualPrefixes)` truncates to the shortest array.
  - `storeBatch` drops chunks whose embedding has the wrong dimension.
  - Sync's `loadVectorChunks` drops chunks whose hydrated embedding has the wrong length before rewriting both roots.
  - Meanwhile `Document.totalChunks` is set to `processedChunks.count` by `DocumentProcessor`, so the document's recorded count never reflects what was dropped.
- **Zero-vector fallback.** When embedding fails, `EmbeddingService` returns `targetDimension` zeros. Those chunks are stored, with norm 0, and can never score above zero for cosine. `[evidence_level: code_verified, confidence: exact]` — [EmbeddingService.swift:382-385](OpenIntelligence/Services/Embedding/EmbeddingService.swift#L382-L385); [BNNS:356](OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift#L356)
- **Summary chunks are counted differently in each store.** A summary chunk has `chunkIndex: -1` and `abstractionLevel: .documentSummary`. At import it goes into the vector store only: it is not in FTS and not counted in `totalChunks`. `[evidence_level: code_verified, confidence: exact]` — [DocumentSummaryService.swift:147](OpenIntelligence/Services/Document/Analysis/DocumentSummaryService.swift#L147); [RAG:6699](OpenIntelligence/Services/RAG/Orchestration/RAGService.swift#L6699)
- **Health checks.** `[evidence_level: code_verified, confidence: exact]` — [RAG:≈7140-7210](OpenIntelligence/Services/RAG/Orchestration/RAGService.swift#L7140-L7210), [RAG:≈7215-7275](OpenIntelligence/Services/RAG/Orchestration/RAGService.swift#L7215-L7275)
  - `evaluateSemanticIndexHealth` repairs only when the vector count is 0. Its comment records a library that reported 420 ingested chunks with a vector store holding none.
  - `libraryStateTraceBlock` prints ingested and searchable counts side by side but flags only zero.
- **Rebuilding FTS from vectors changes what FTS holds.** `rebuildLocalSearchIndexesFromCanonicalState` treats the vector store as the source of truth. For each library it deletes the FTS rows, then rebuilds from `allChunks()` with no `abstractionLevel` filter, so summary chunks get included. `[evidence_level: code_verified, confidence: exact]` — [RAG:7396-7520](OpenIntelligence/Services/RAG/Orchestration/RAGService.swift#L7396-L7520)
  - Document text becomes the chunk texts joined with `\n\n`, overlaps duplicated and the summary first.
  - Chunk rows are rebuilt with `structuredMetadata: .none`, so `chunk_structured` and `chunk_table_rows` stay empty.
  - Pages are regrouped from chunks.
  - Vector chunks for documents missing from the catalogue are deleted, one full rewrite per orphan document.
- **Streamed import.** Each page batch is chunked separately by `processDocument(pageRange:)`. FTS rows are appended (`append: true`) and vectors are appended and persisted per batch. Re-ingesting a document through the normal path replaces its FTS chunk rows but never deletes its earlier vectors. `[evidence_level: code_verified, confidence: exact]` — [RAGService+Streaming.swift:77-199](OpenIntelligence/Services/RAG/Orchestration/RAGService+Streaming.swift#L77-L199); [RAG:6521-6523](OpenIntelligence/Services/RAG/Orchestration/RAGService.swift#L6521-L6523)
- **The owner's measurement.** Library `FF9333D1` (four surgical-equipment PDFs) shows 1,903 `totalChunks` against 1,451 vectors (`_norms.bin` size / 4): 452 missing, 24%. Six other libraries show exactly one *more* vector than chunks. `[evidence_level: measured by the owner, confidence: exact per row]` — [Notion: 452 chunks row](https://app.notion.com/3d749a74d54f812cb828d19ff84661e9)

### Inferences
- **The 452 chunks are not keyword-searchable either.** The row's title says a quarter of the library is "keyword-searchable only", which is optimistic for hybrid retrieval. Chunk-level FTS hits for those chunks are discarded because they have no vector-store twin, and the spec sniper cannot see them. At best they surface through the document- or page-level FTS paths (`searchPages` at RAG:18427, `searchCorpus` at RAG:20060). `[evidence_level: inferred from code_verified lines, confidence: high]`
- **The "+1 vector" pattern matches the summary chunk:** one per document, stored in vectors but not counted in `totalChunks`. In a one-document library that gives exactly +1. `[evidence_level: inferred, confidence: medium-high]`
- **Possible causes of the 452 absent vectors.** The code allows several; nothing in it says which one fired.
  1. The zip truncates the chunk list.
  2. `storeBatch` drops chunks of the wrong dimension.
  3. A sync merge drops or replaces chunks.
  4. The store is wiped by the size-check loader or deleted by sync, then partly re-ingested.
  5. Chunks counted in `processedChunks` never reached the vector write because a step was interrupted.
- **Possible key collisions in streamed imports.** If `chunkIndex` restarts at 0 for each page batch, `(documentId, chunkIndex)` repeats. FTS `chunk_id` then duplicates (FTS5 has no uniqueness constraint), and hybrid search's dictionary keeps only the last chunk per key. FTS hits could resolve to the wrong chunk, or collapse. `[evidence_level: inferred, confidence: medium]`
- **Rebuilt devices index different content.** On a device whose FTS index came from the rebuild path (for example an iCloud second device), table-row search returns nothing and document text includes LLM summaries. Lexical results for the same library therefore differ from device to device.

### Gaps
- Which drop path produced the 452 cannot be settled without the ingestion logs for those PDFs.
- Whether `chunkIndex` restarts per streamed batch was not checked (needs `SemanticChunker` with `pageRange`).

## 7. iCloud: which files sync, how, and whether SQLite files are synced while open

### Takeaway
SQLite never syncs. Live stores always stay in local Application Support. Sync copies files between that local root and `<ubiquity container>/Documents/OpenIntelligenceWorkspace`.

Vector-store files are written into, read from, and can be deleted inside the iCloud root by the vector store itself, with plain `FileManager`/`Data` I/O and no `NSFileCoordinator`. `NSFileVersion` conflict resolution covers only three metadata files. Per-library files (vectors, chat history, transcripts, conversation memory) never get their iCloud conflict versions resolved.

### Cited Findings
- **SQLite is local-only.** The FTS5 file lives under `LocalCache`, and both "FTS5" and "LocalCache" are in `localOnlyEntryNames`, which is used to skip entries during migration and change observation. The Atlas claim "NO SQLite Sync" is consistent with this. `[evidence_level: code_verified, confidence: exact]` — [SYNC:272-278, 1597, 3575](OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift#L272-L278); [Atlas §9](Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md)
- **Live stores stay local.** Both `activateLocalWorkspace` and `activateSharedWorkspace` call `configureBaseDir(nil)`. The shared root is `<ubiquity>/Documents/OpenIntelligenceWorkspace`. `[evidence_level: code_verified, confidence: exact]` — [SYNC:881-927](OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift#L881-L927)
- **Vector files in iCloud are handled without coordination.** `[evidence_level: code_verified, confidence: exact]` — [SYNC:2660-2674](OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift#L2660-L2674); [BNNS:307-343, 668-688](OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift#L307-L343)
  - `persistVectorChunks` builds a new store instance on the target root and calls `clear()` (plain `removeItem`), then `storeBatch`, then `persist()` (`Data.write(.atomic)` and `FileHandle`).
  - It does this to the local root and to the iCloud root.
  - Reads of the shared files go through the same loader, which memory-maps the files and can delete all three on a size mismatch — [SYNC:1893-1918](OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift#L1893-L1918)
- **Auxiliary files are copied under coordination.** `chat_history_`, `transcript_` and `conversation_memory_` JSON files, and EvidenceThreads files, go through `copyItem`, which calls `coordinatedCopyItem` (`NSFileCoordinator`) at this commit. Directories are copied with plain `FileManager.copyItem`. `[evidence_level: code_verified, confidence: exact]` — [SYNC:2676-2730, 3604-3614, 3805-3840](OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift#L2676-L2730)
- **Conflict resolution is narrow.** `NSFileVersion.unresolvedConflictVersionsOfItem` is resolved only for `containers.json`, `documents_metadata.json` and `ingestion_queue.json`. `[evidence_level: code_verified, confidence: exact]` — [SYNC:267-271, 3351-3362](OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift#L3351-L3362)
- **Safeguards in `synchronizeVectorStore`.** `[evidence_level: code_verified, confidence: exact]` — [SYNC:2341-2614](OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift#L2341-L2614)
  - It fails closed when a shared store is only an undownloaded placeholder.
  - It refuses to delete when the merge result is empty.
  - It skips rewrites whose content is identical, and skips whole passes whose signature is unchanged.
  - It still writes the merged set over *both* roots when anything differs.
- **Triggers.** Every vector persist or clear, and every coordinated write, posts `.localWorkspaceDidChange` when the file is under Application Support and no sync write is flagged. That notification is debounced for 2 s and then calls `reconfigureIfNeeded`. `isSyncWriteInProgress` is an advisory flag guarded by `objc_sync` that only suppresses the notification. `[evidence_level: code_verified, confidence: exact]` — [SYNC:251-263, 320-327](OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift#L320-L327); [BNNS:339-342](OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift#L339-L342)
- **Two instances on the same files.** The sync pass builds its own store instances over the same local files the router's live instance maps. The router's own comment says two live mappings of one file must not coexist. `[evidence_level: code_verified, confidence: exact]` — [ROUTER:240-245](OpenIntelligence/Services/VectorStore/VectorStoreRouter.swift#L240-L245); [SYNC:1900-1902, 2668-2670](OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift#L1900-L1902)
- **No CloudKit, CKSyncEngine or SwiftData+CloudKit in sync.** The grep for them found one match, in `LiveObjectDetectionService.swift`, an unrelated classification service that I did not inspect. `[evidence_level: grep_verified, confidence: high]`

### Inferences
- **The three vector files can arrive out of step.** iCloud Drive syncs the three files separately, and the code has no cross-file version check (only a placeholder check). A device can therefore see a newer `_meta.json` alongside an older `_vectors.bin`. The loader then deletes all three files in the iCloud root, and that delete propagates to other devices. This is a plausible mechanism for the "vector index metadata" loss in the conflict-copies row. `[evidence_level: inferred, confidence: medium]`
- **Lost updates.** The live store and the sync's rewrite share no lock. A live persist after the sync has read, or a sync write after a live persist, can overwrite the other. `[evidence_level: inferred, confidence: medium]`

### Gaps
- Real-world ordering and latency of iCloud delivery across the three files cannot be settled from code.

## 8. Status of the owner's roadmap rows against the code at b37ab4c

### Takeaway
Summary:

| Row | Verdict |
|---|---|
| bm25 half of the FTS5 row | Done |
| Trigram index | Absent |
| Embedding migration (additive-then-swap) | Not implemented; current flow is in-place per document with a destructive loader underneath |
| Six uncoordinated file families | Confirmed for the three vector families; outdated for the JSON copy step; root cause (no per-library conflict resolution) confirmed |
| 452 missing vectors | Consistent with the code's silent drop paths; cause unsettled |
| Library-deletion race | Partly mitigated (ingestion is fenced), otherwise likely still open |
| 420 reloads per import | Mechanism present, one guard added; current count unsettled |
| CKSyncEngine migration | Diagnosis confirmed |

### Cited Findings
- **"FTS5: weight bm25 columns and add a trigram index."** `[evidence_level: code_verified + grep_verified, confidence: exact]` — [Notion](https://app.notion.com/3b149a74d54f81248feaf48022482a63); [SQLFTS:1458-1471](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L1458-L1471)
  - Weights: done and aligned (section 2).
  - Trigram: no `tokenize='trigram'` table exists. The only "trigram" in the code is word-trigram key-phrase extraction in diagnostics (SQLFTS:2486-2517).
- **"Embedding migration flow: additive-then-swap re-embed."** Not implemented. `[evidence_level: code_verified, confidence: high]` — [Notion](https://app.notion.com/3b349a74d54f815fb979fc00edc9f962); [RAG:8120-8122](OpenIntelligence/Services/RAG/Orchestration/RAGService.swift#L8120-L8122)
  - There is one file path per container and no shadow store.
  - Re-embedding deletes and replaces vectors per document inside the live store.
  - Opening the store at a new dimension triggers the loader's delete-or-truncate path (section 4).
- **"Six file families sync to iCloud without NSFileCoordinator… 599 conflict copies."** — [Notion](https://app.notion.com/3ca49a74d54f8103b69be921f0335171); [SYNC:2660-2674, 3351-3356, 3604-3614](OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift#L2660-L2674)
  - **The row reports** (census of 2026-08-27):
    - 661 files where the app writes 62;
    - 599 conflict copies: `transcript_` 126, `chat_history_` 103, `_meta.json` 99, `conversation_memory_` 99, `_norms.bin` 87, `_vectors.bin` 85;
    - 136 zero-block stubs, with sync dead since 2026-08-10.

    It is filed as data loss and currently sits in Future Backlog, "first row of the next release".
  - **Confirmed:** the vector families are written, read and deleted in iCloud without coordination. `[evidence_level: code_verified, confidence: exact]`
  - **Outdated or different:** at this commit the three JSON families are copied through `coordinatedCopyItem`. `[evidence_level: code_verified, confidence: exact]`
  - **The underlying cause, which the code confirms:** conflict versions are resolved only for the three critical metadata files, so conflict copies of per-library files accumulate whether or not the copy was coordinated. `[evidence_level: code_verified, confidence: exact]`
- **"Move workspace metadata to CKSyncEngine or SwiftData + CloudKit."** The diagnosis holds: sync is hand-rolled last-writer-wins JSON merging over iCloud Drive in a 3,866-line service, `isSyncWriteInProgress` is an advisory flag, and no Apple sync framework is used. The proposal itself is untested. `[evidence_level: code_verified + grep_verified, confidence: high]` — [Notion](https://app.notion.com/3b149a74d54f816e9c52e814cf39e757); [SYNC:251-263](OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift#L251-L263)
- **"Deleting a library races its own background writers, which resurrect it."** (Captured on device 2026-08-20.) `[evidence_level: code_verified for the flow; the absence of other fences is grep-based, so inferred, confidence: medium]` — [Notion](https://app.notion.com/3c349a74d54f81beaad5c59162e58434); [LibraryDeletion.swift:66-114](OpenIntelligence/Features/Documents/Library/LibraryDeletion.swift)
  - `LibraryDeletion.delete` now calls `cancelAndPurgeIngestion` first, then removes each document, deletes the container, reloads, and clears the entity index.
  - I found no liveness fence for SelfTuning, Spotlight or metadata-save writers: a grep for liveness and tombstone names turned up only ingestion-queue tombstones.
  - The delete never calls `invalidateAndClearStorage`, so the empty vector files and the router cache entry remain. It never clears that library's `semantic_query_cache` rows either.
  - A code comment says the SDK's `OpenIntelligenceEngine.deleteLibrary` deletes only the container record and "leaves every document, chunk, vector and Spotlight entry behind". That is a claim in a comment; I did not fully read the function. — [LibraryDeletion.swift:27-30](OpenIntelligence/Features/Documents/Library/LibraryDeletion.swift); [OpenIntelligenceEngine.swift:416](OpenIntelligence/SDK/OpenIntelligenceEngine.swift#L416)
- **"One document import triggers 420 workspace reloads."** (macOS Debug build: 420 sequential `[WorkspaceReload]` entries for one 8-page PDF; 9,832 of 23,045 log lines were CoreUI relayout.) `[evidence_level: code_verified for the mechanism; current count unknown]` — [Notion](https://app.notion.com/3ca49a74d54f81a6b8c1e4827a6585fa); [ContentView.swift:456-457](OpenIntelligence/App/ContentView.swift#L456-L457); [RAG:3910-3935](OpenIntelligence/Services/RAG/Orchestration/RAGService.swift#L3910-L3935)
  - The pieces the row describes exist in code: vector persists post notifications, a 2 s debounced reconfigure follows, and `reloadWorkspaceData()` has several callers (the row says "seven").
  - The ContentView workspace-change handler now returns early while an ingestion is active.
  - Whether the reload count has actually dropped cannot be told from code.
- **"452 chunks in one library have no vector."** `[evidence_level: code_verified for paths; cause unknown]` — [Notion](https://app.notion.com/3d749a74d54f812cb828d19ff84661e9)
  - Consistent: the code has several silent drop paths, and the health check detects only zero (section 6).
  - Refinement: the "keyword-searchable only" claim does not hold for chunk-level hybrid retrieval.
  - The "+1" pattern is explained by the summary chunk.

### Inferences
- **Three of these rows share one cause.** The deletion race, the conflict-copies row and the 452-vector gap all come from a design with no transactional boundary spanning SQLite, the three vector files and the JSON metadata, and no cross-store reconciliation. Each point fix closes one window.

### Gaps
- The row statuses I quote come from Notion page content as of each page's last edit (2026-08-19 to 2026-09-10). I did not query the whole board.

## 9. Measured numbers found in the repository (with provenance)

### Takeaway
Nearly every storage number in the repo is a device capture recorded in a code comment or a Notion row, not a benchmark. None of them is a search-latency or memory figure for the vector store or FTS5 at scale.

### Cited Findings
- **Orphan rows.** The owner's real FTS5 index held **4,077 distinct document ids for roughly 15 documents**, from benchmark pollution through the cache-directory override. `[evidence_level: measured per code comment, confidence: medium]` — [OpenIntelligenceRuntimePaths.swift:44-47](OpenIntelligence/Core/Support/OpenIntelligenceRuntimePaths.swift#L44-L47)
- **Idle reloads.** **2,848 vector loads in 164 s** on an idle Mac, the same store re-read 288 times, with a 1.68 s trigger (captured 2026-08-29). `[evidence_level: measured per comment and Atlas §9, confidence: high]` — [ROUTER:247-255](OpenIntelligence/Services/VectorStore/VectorStoreRouter.swift#L247-L255); [Atlas §9](Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md)
- **Sync deserialisation.** **128 store opens and 43,164 chunk records deserialised** in one session with **zero writes**, 64 opens and 21,582 records of them before the first screen (2026-08-24). `[evidence_level: measured per comment, confidence: high]` — [SYNC:218-226](OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift#L218-L226)
- **Sync rewrites.** **96 store opens and 48 rewrites in one boot, about 200 MB written for zero content change**, roughly half of it queued to iCloud (2026-08-18). `[evidence_level: measured per comment, confidence: high]` — [SYNC:≈2532-2545](OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift#L2532-L2545)
- **Store sizes.** The largest device store needs about 557k float comparisons, which is 1,451 × 384 and matches the 452-row library, described as a "4 MB write". Device libraries range from 26 to 1,451 chunks. `[evidence_level: measured per comment, confidence: medium]` — [SYNC:≈2545-2550, ≈2629-2642](OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift#L2616-L2658)
- **Benchmark regression.** A benchmark with a 40-document pool went from **269–414 s to over 1,800 s** because of the O(chunks × 384) store-equality check. `[evidence_level: measured per comment and LEDGER, confidence: high]` — [SYNC:≈2629-2640](OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift#L2629-L2640); [BenchmarkRuns/LEDGER.md:168-175](BenchmarkRuns/LEDGER.md)
- **Vector-loss incidents recorded in comments.** `[evidence_level: device_log per comments, confidence: high]` — [RAG:≈7140-7200, 4123](OpenIntelligence/Services/RAG/Orchestration/RAGService.swift#L4123); [ROUTER:66-78](OpenIntelligence/Services/VectorStore/VectorStoreRouter.swift#L66-L78); [SYNC:≈2485-2500](OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift#L2485-L2500)
  - 2026-08-03: **239 chunks in FTS5 with no vector store**.
  - A library once reported **420 ingested chunks against 0 vectors**.
  - 2026-08-18: a document split across libraries.
  - 2026-08-20: **197 searchable chunks lost** after eviction.
  - 2026-08-24: sync deleted a just-written **196-chunk** store twice.
- **Rebuild speed.** A rebuild of **196 chunks took about four seconds** on device (2026-08-19). `[evidence_level: device_log per comment, confidence: medium]` — [RAG:≈4690](OpenIntelligence/Services/RAG/Orchestration/RAGService.swift#L4690)
- **Arm overlap in hybrid search** (captured 2026-08-14):
  - a manuals corpus: 120 vector + 60 FTS5 hits, 57 of them found only lexically;
  - a research corpus: 140 vector + 6 FTS5, with "serotonin" in 51% of chunks.

  `[evidence_level: measured per comment, confidence: high]` — [HYB:≈1198-1210](OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift#L1198-L1210)
- **Retrieval quality context** (owned by the query-path topic). Over 25 QASPER cases, the lexical arm ranks the gold document first in **60%** of cases against 8% for the dense arm, and fusion drops r@1 from 0.600 to 0.360. `[evidence_level: measured per archived changelog, confidence: high]` — [Docs/Archive/CHANGELOG_2.0_to_5.2.md:318](Docs/Archive/CHANGELOG_2.0_to_5.2.md)
- **Owner census and measurements from Notion.** `[evidence_level: measured by owner, confidence: exact per row]` — Notion rows linked in section 8.
  - 452 of 1,903 vectors missing.
  - 599 conflict copies and 136 stubs.
  - 420 reloads per import.
  - Trigram database growth of +104% to +263%.

### Inferences
- No figure bounds search latency, memory or file size at the "massive library" scale the comments anticipate. Scaling claims therefore rest on code arithmetic, not measurement.

### Gaps
- `BenchmarkRuns/*` run directories are gitignored (only `LEDGER.md` and `PROGRESSION.md` are tracked), so no raw storage timings were available.

## 10. Structural weaknesses and scaling limits

### Takeaway
The storage layer is less a place for a single bug than a set of design choices that each create silent failure modes:
- two unsynchronised stores joined by a positional key;
- a vector store whose integrity check deletes data;
- whole-file rewrites and whole-library in-memory metadata;
- a lexical index that is shared across libraries, cannot handle identifiers or CJK, and cannot be migrated without a rebuild;
- a persistent retrieval cache with no invalidation;
- iCloud writes of vector files with no coordination and no conflict resolution.

None of these is touched by a fix to the extractive-answer step. Several decide whether the chunk that step needs is retrievable at all.

### Cited Findings
- **W1. No cross-store atomicity or reconciliation.** Four independent write phases per import (section 6). Partial-loss detection only at zero. The rebuild path treats the vector store as truth and lossily regenerates FTS. — [RAG:6521-6732, 7140-7210, 7396-7520](OpenIntelligence/Services/RAG/Orchestration/RAGService.swift#L6521-L6732) `[evidence_level: code_verified, confidence: exact]`
- **W2. The vector store is the de facto chunk catalogue.** FTS hits resolve only through it. The spec sniper and the per-query `allChunks` consumers read only it. A chunk missing there is unreachable by every chunk-level arm. — [HYB:≈1085-1128](OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift#L1085-L1128); [RAG:8697-8704](OpenIntelligence/Services/RAG/Orchestration/RAGService.swift#L8697-L8704) `[evidence_level: code_verified, confidence: exact]`
- **W3. The integrity check destroys data.** A size mismatch deletes all three files or truncates them. There is no header, dimension or checksum. Saves are three separate atomic writes. A dimension change reaches the destructive branch as soon as anything opens the store (section 4). — [BNNS:179-204, 307-337](OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift#L179-L204) `[evidence_level: code_verified path; outcome inferred, confidence: high]`
- **W4. O(library) writes.** Every persist rewrites `_meta.json` and the whole `_vectors.bin`, building one heap `Data` of all vectors. Each import persists twice, and streamed imports persist per batch. Each document delete or update rewrites both. Re-embedding costs about 2D full rewrites. Sync rewrites both roots. — [BNNS:307-343, 609-752](OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift#L307-L343) `[evidence_level: code_verified, confidence: exact]`
- **W5. Resident metadata and O(N) query work.** Every cached library's full chunk text and metadata stays in RAM. Every query does O(N) Swift scans or dictionary builds (standard pipeline, hybrid FTS resolution, sniper). The vector search is a brute-force scan with a full sort when k > 20 and a possible full GPU-buffer copy per query. There is no ANN index and no quantization, and the HNSW option is compiled out. — [BNNS:486-571](OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift#L486-L571); [ROUTER:158-166](OpenIntelligence/Services/VectorStore/VectorStoreRouter.swift#L158-L166) `[evidence_level: code_verified, confidence: exact]`
- **W6. Shared FTS tables with UNINDEXED isolation.** Per-document and per-library deletes scan the whole table (repro). BM25 statistics are global across libraries and include orphan rows. Nothing sweeps orphans (no `NOT IN` delete exists). Maintenance covers only `documents`. — [SQLFTS:190-255, 629-739, 2715-2783](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L190-L255) `[evidence_level: code_verified + repro; IDF effect inferred, confidence: high]`
- **W7. Lexical-arm limits.** Porter stemming with no trigram or prefix index, so identifiers miss. No CJK segmentation. One-character tokens and English stopwords are dropped. AND-then-OR matching only. Unquoted MATCH in the vocabulary check produces syntax-error false negatives that HyDE grounding acts on. `highlight()` is advertised but unused. — [SQLFTS:3228-3293, 3552-3565](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L3228-L3293) `[evidence_level: code_verified + repro, confidence: high]`
- **W8. The persistent semantic query cache is never invalidated.** An exact normalised-text hit or a similarity hit (cosine ≥ 0.95) bypasses query rewriting, embedding and hybrid search entirely and returns the stored `[RetrievedChunk]`, chunk text included. `[evidence_level: code_verified + grep_verified; consequences inferred, confidence: high]` — [RAG:9831-9851, 10350-10366, 10650-10657](OpenIntelligence/Services/RAG/Orchestration/RAGService.swift#L9831-L9851); [SQLFTS:3303-3435](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L3303-L3435)
  - There is no TTL: `created_at` is written but never read.
  - There is no eviction or delete anywhere, including on document delete, library delete, re-embed or app update.
  - No setting gates the lookup at these lines.
  - The similarity lookup JSON-decodes every cached embedding for the library on every query.
- **W9. iCloud vector sync without coordination or conflict resolution.** A second store instance works on the live files. Placeholder-only fail-closed logic. Multi-file stores sync with no version pairing (section 7). — [SYNC:1893-1918, 2660-2674, 3351-3356](OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift#L2660-L2674) `[evidence_level: code_verified; skew effect inferred, confidence: medium-high]`
- **W10. Schema and format rigidity is a governance cost, not just a technical one.** Both files are hard boundaries because any tokenizer, column or format change forces every user to reindex. The code has no versioning or shadow-index mechanism to make such changes safe. The fix for W6/W7 (trigram) and for W3 (a format header) is therefore gated behind a migration capability that does not exist. — [03_FORBIDDEN_EDIT_BOUNDARIES.md:25-26](Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md); [SQLFTS:3082-3156](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift#L3082-L3156) `[evidence_level: code_verified + doc, confidence: high]`

### Inferences
- **What this means for the extractive-answer question.** A 10-line fix at the answer step leaves these untouched:
  - Chunks can be absent from the vector catalogue (the 452 row), and are then unreachable, including by the precision lookup and the spec sniper.
  - Identifier lookups can miss lexically.
  - Stale cached retrieval sets can bypass whatever retrieval improvements ship.
  - Lexical ranking is contaminated by other libraries' statistics.

  Whether the fix is "a band-aid" depends on the failure it targeted. At the storage layer there are independent, larger reliability problems that no answer-step fix can reach.
- **Verification risk from the cache.** W8 is the item most likely to confound verification of any retrieval or answer fix. A repeated test query can be served from the cache, computed by older code, across app updates.
- **Scaling estimate.** At the current per-chunk sizes (1,536 bytes of vectors plus about 1.2 KB or more of metadata JSON), a library of tens of thousands of chunks would mean:
  - tens of megabytes rewritten twice per import;
  - tens of megabytes of resident JSON-derived strings;
  - O(N) Swift passes per query.

  Brute-force cosine search stays computationally acceptable at d = 384 into the low hundreds of thousands of vectors. `[evidence_level: inferred, confidence: medium]`

### Gaps
- None of W3, W4, W5 or W8 has been measured on device at large library sizes.

## 11. Questions the code cannot settle

### Takeaway
Several conclusions above rest on code paths whose runtime frequency or trigger needs device evidence or a targeted experiment.

### Cited Findings
- Which drop path produced library FF9333D1's 452 missing vectors: zip truncation, the dimension filter, a sync merge, a wipe-and-partial-reingest, or an interrupted import. — [Notion 452 row](https://app.notion.com/3d749a74d54f812cb828d19ff84661e9); [RAG:6444](OpenIntelligence/Services/RAG/Orchestration/RAGService.swift#L6444) `[evidence_level: unknown, confidence: n/a]`
- Whether the six "+1" libraries each hold exactly one document with a stored summary, which would confirm the summary-chunk explanation. `[evidence_level: unknown]`
- Whether a dimension change has ever reached the loader's truncate-to-garbage or delete branch on a real device, and which embedding dimensions users can actually reach (384 is the default; 512 appears as a fallback in `dbFor` and the in-memory store). — [RAG:4174-4186](OpenIntelligence/Services/RAG/Orchestration/RAGService.swift#L4174-L4186) `[evidence_level: unknown]`
- How often iCloud delivers the three vector files out of step, and whether the conflict-copy pattern recurs after the 2026-08-27 cleanup. `[evidence_level: unknown]`
- How often the semantic-cache exact or similarity path hits in real use, and whether it has served chunks from deleted documents. `[evidence_level: unknown]`
- Whether `chunkIndex` restarts per streamed page batch (FTS `chunk_id` and join-key collisions); this needs `DocumentProcessor.processDocument(pageRange:)` and the chunker checked. `[evidence_level: unknown]`
- Whether the GPU no-copy Metal buffer usually succeeds or falls back to a full copy per query; this depends on alignment and file length. — [GPUComputeService.swift:741-805](OpenIntelligence/Services/Infrastructure/Compute/GPUComputeService.swift#L741-L805) `[evidence_level: unknown]`
- Apple's SQLite default `synchronous` in WAL mode, real `fulltext.sqlite` and WAL sizes, and FTS query latency on device for large libraries. `[evidence_level: unknown]`
- Whether the "420 reloads per import" behaviour persists after the active-ingestion guard. — [ContentView.swift:456-457](OpenIntelligence/App/ContentView.swift#L456-L457) `[evidence_level: unknown]`
- Whether other retrieval tools (`searchPages`, `searchCorpus`) can surface chunks that have no vector, and how answers use them. — [RAG:18427, 20060](OpenIntelligence/Services/RAG/Orchestration/RAGService.swift#L18427) `[evidence_level: unknown]`

### Inferences
- The cheapest experiments that would settle most of these:
  - a per-library count of FTS `chunks` rows versus vector count versus `totalChunks`;
  - a count of `semantic_query_cache` rows, with the documents their cached chunks point to;
  - a re-import of FF9333D1's PDFs with `.vectorDB` logging routed to the file log.

### Gaps
- No device access in this session. I ran no build, test or app launch.
