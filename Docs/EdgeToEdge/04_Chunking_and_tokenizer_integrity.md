# Module 04. Chunking and tokenizer integrity

Twenty-one concepts. Cutting the document into index cards that fit the embedding model, without slicing a table in half, and without trusting a word count.

## The ladder

**Like you're five.** The phone cuts each paper into little cards, about a paragraph each. The cards overlap a tiny bit at the edges so no sentence gets cut in half. Tables are never cut. Then the phone measures each card to make sure it actually fits in the reader's mouth, because the reader just swallows the first bit and spits out the rest without telling anyone.

**Like an idiot.** A chunk is a passage-sized piece of a document. It's the unit that gets searched, ranked, cited and checked. Chunks are at most 310 words, overlap by up to 50, and never split a table or list. Each one gets a short prefix saying which document and section it's from. Then, and this is the important part, every chunk is run through the real tokenizer to make sure it's under the model's limit, because the model doesn't complain when a chunk is too long. It silently truncates.

**Like less of an idiot.** The embedding model reads at most 510 tokens. Tokens are not words: technical text runs about 1.5 tokens per word, so 510 tokens is roughly 340 words, and the contextual prefix eats about 30 of those, hence 310. But a word count is only an estimate, and the failure when you're wrong is the worst kind: the model embeds the first 510 tokens and files that vector under the identity of the whole chunk. Nothing downstream can detect it. So the app validates every chunk with the tokenizer paired to the model, at 430 tokens (510 minus 80 reserved for the prefix), and splits anything over. Chunk boundaries are chosen at sentence boundaries, section headings, structural blocks and a short list of discourse transitions ("However," "In conclusion,").

**Average Joe.** Why does chunking get its own module? Because it's where a real disaster happened. A padding block in the tokenizer wrapper once made the token counter return a constant. The 430-token guard could never fire. More than half of every document was silently truncated at embedding, every embedding was diluted, and every log line read healthy. A plausible-looking constant is the most expensive kind of wrong.

**Dot-connector.** Two independent knobs, two different consequences. Chunk size and overlap can change mid-library with no harm, because a vector for a bigger chunk and a vector for a smaller chunk still live in the same coordinate space; that's "mixed chunk strategy compatibility." Changing the embedding model, its dimension, its tokenizer or its pooling changes the coordinate space itself, which is why that requires a full re-embed and is blocked during ingestion. Also notice that offsets are computed here, and offsets are what let a citation jump to a character range instead of a page.

**Expert.** `SemanticChunker` walks sentence boundaries from `NLTokenizer`, forces breaks at detected headings, keeps `StructuredElement` tables and lists atomic, and breaks at transition phrases (the list at `SemanticChunker.swift:1115` includes "Additionally," "Nevertheless," "Consequently," "In conclusion," "To summarize,"). Container-level `chunkingConfig` carries `maxChunkWords`, target and `overlapWords`; hard ceiling 310, largest target 260, overlap capped at 50, smallest target 100. `DocumentProcessor.enforceTokenLimitOnChunks` validates at `safeTokenLimit = maxEmbeddableTokens - contextualPrefixTokens` (510 minus 80 = 430) with the Rust-backed tokenizer; sub-splits leave a 10-token margin for part markers; anything still oversized is logged as such and will be truncated by the model. Chunks record byte offsets, section path, page, sibling group, parent content, semantic type, semantic density and abstraction level.

**Expert's expert.** "Still oversized after splitting" is logged, not counted anywhere a user sees, so it belongs on the silent-drop list. The 80-token prefix reserve is a budget, not a measurement: the actual prefix is whatever the document title and section path tokenize to. The word-piece vocabulary is MiniLM's; `[CLS]` and `[SEP]` are inserted by the tokenizer and count against the 510. And the same tokenizer is loaded at launch for counting, which is the one model-adjacent thing that happens before the first embed.

## Every concept

### 510-token embedding ceiling (Core, verified)
- **Idiot:** the reader's mouth fits 510 pieces. No more.
- **Dot-connector:** MiniLM's usable sequence after special tokens; exceed it and the tail is silently dropped.
- **Expert:** `maxEmbeddableTokens` in `EmbeddingProvider`; rechecked at embedding time; the guard is at 430 because 80 are reserved for the prefix.

### Actual tokenizer validation (Core, verified)
- **Idiot:** measure with the real ruler, not by guessing.
- **Dot-connector:** word count is an estimate; the paired tokenizer is the truth; this is the step the padding bug bypassed.
- **Expert:** `enforceTokenLimitOnChunks` with the tokenizer from the embedding tokenizer bundle; splits over 430, re-checks, logs stragglers.

### Atomic structural block (Core, verified)
- **Idiot:** never cut a table in half.
- **Dot-connector:** a cell without its header, a warning without its conditions, is misleading evidence.
- **Expert:** `StructuredDocumentParser` flags them; `SemanticChunker` hands them through indivisibly when feasible.

### Chunk (Core, verified)
- **Idiot:** an index card.
- **Dot-connector:** whole documents are too broad to rank and too big for the model; chunks make retrieval granular while keeping local meaning.
- **Expert:** `DocumentChunk`: content, source identity, metadata, usually an embedding; the unit indexed, ranked, packed, cited and verified.

### Chunk offset (Core, verified)
- **Idiot:** where exactly in the document this card came from.
- **Dot-connector:** offsets are what make "jump to the sentence" and quote citations possible without fuzzy searching.
- **Expert:** start and end positions computed during chunking; consumed by citation and contextual compression.

### Chunk overlap (Core, verified as `overlapWords`)
- **Idiot:** the cards share a few words at the edges.
- **Dot-connector:** a fact on a boundary would otherwise be split out of both cards.
- **Expert:** trailing context repeated at the next chunk's start; capped at 50 words.

### Chunk semantic type (Core, verified)
- **Idiot:** a label: prose, table, list item, warning.
- **Dot-connector:** different structures get different ranking, packing and verification treatment.
- **Expert:** assigned at ingestion on `DocumentChunk`; consulted by boosts and intent-specific packing.

### Contextual prefix (Core, verified)
- **Idiot:** a sticky note on the card: "from the brake manual, section 4."
- **Dot-connector:** a chunk alone has lost what it's about; the prefix puts that back into the vector without changing the quoted text.
- **Expert:** document and section label prepended to the embedding text only; 80 tokens reserved for it.

### Cross-reference metadata (Conditional, verified)
- **Idiot:** "see page 12" is remembered as an arrow.
- **Dot-connector:** manuals answer indirectly; capturing the edge lets the graph fetch the target.
- **Expert:** on `DocumentChunk`, traversed by `GraphIndexService` after initial retrieval.

### Linguistic transition boundary (Core, verified)
- **Idiot:** words like "However" are good places to cut.
- **Dot-connector:** transitions signal a new argument or a summary; cutting there keeps passages coherent.
- **Expert:** a small English phrase list in `SemanticChunker`, considered after sentence and heading breaks.

### Maximum chunk size (Core, verified)
- **Idiot:** 310 words, tops.
- **Dot-connector:** the ceiling derived from the token limit and the prefix reserve; enforced while chunking, then double-checked by the tokenizer.
- **Expert:** `maxChunkWords` on the container config; hard cap 310.

### Mixed chunk strategy compatibility (Core, documented)
- **Idiot:** you can change the card size later without redoing everything.
- **Dot-connector:** boundaries change what a vector represents, not the coordinate system; old and new chunks stay comparable.
- **Expert:** documented in `HOW_IT_WORKS.md`; contrasts with embedding changes, which force a rebuild.

### Parent content (Core, verified)
- **Idiot:** the bigger paragraph the card was cut from, kept nearby.
- **Dot-connector:** small chunks rank precisely; generation and citation sometimes need the surrounding context to interpret them.
- **Expert:** attached at ingestion; restored by `ParentDocumentService` after ranking.

### Section-heading boundary (Core, verified)
- **Idiot:** a new heading means a new card.
- **Dot-connector:** the heading defines the local topic and is itself high-value metadata; crossing it mixes sections.
- **Expert:** evaluated as `SemanticChunker` walks sentences and structure.

### Semantic density (Support, verified)
- **Idiot:** how much information is packed into the card.
- **Dot-connector:** used to pick representative chunks for summaries and for diagnostics.
- **Expert:** heuristic score stored in chunk metadata; consumed by `DocumentSummaryService`.

### SemanticChunker (Core, verified)
- **Idiot:** the cutter.
- **Dot-connector:** sentence boundaries, headings, structural blocks and transitions instead of fixed character slicing; also supplies the metadata later stages need.
- **Expert:** 1,951 lines; runs after normalised text and structured elements exist.

### Sentence boundary (Core, verified)
- **Idiot:** don't cut in the middle of a sentence.
- **Dot-connector:** the smallest ordinary split point; breaking inside one hurts meaning, offsets and citations.
- **Expert:** `NLTokenizer` sentence segmentation before accumulation toward the target size.

### Sibling group (Core, verified)
- **Idiot:** cards from the same section know they're related.
- **Dot-connector:** one precise hit can pull its neighbours without a global search.
- **Expert:** assigned at ingestion; used by `ParentDocumentService` after rerank, with Jaccard dedup above 80% overlap.

### Target chunk size (Core, verified)
- **Idiot:** the size the cutter aims for.
- **Dot-connector:** balances completeness against precision and the token limit.
- **Expert:** resolved by document plan; largest target 260, smallest 100.

### Tokenizer-model pairing (Core, verified)
- **Idiot:** use the ruler that came with the reader.
- **Dot-connector:** a valid tensor from the wrong tokenizer represents the wrong text and quietly wrecks retrieval.
- **Expert:** recorded in `EmbeddingFingerprint`; validated when a provider is selected or rebuilt.

### Word-piece token (Core, verified)
- **Idiot:** the pieces the model actually reads; sometimes a word, sometimes half of one.
- **Dot-connector:** limits are in tokens, not words, and technical text burns them fast.
- **Expert:** produced immediately before inference for embedding and reranking; MiniLM vocabulary.
