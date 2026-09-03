# Module 05. Embeddings and vector semantics

Thirty-three concepts. Turning meaning into coordinates: the one genuinely strange idea in the app, and the machinery that keeps it honest.

## The ladder

**Like you're five.** Imagine a big map where things that mean the same sit close together. Dog and puppy are neighbours. Dog and tax return are far apart. Every card gets a pin on the map. When you ask a question, your question gets a pin too, and the phone looks at which cards are pinned nearby.

**Like an idiot.** An embedding is a list of 384 numbers that a small model produces from a chunk of text. Those numbers are coordinates. Chunks about similar things get similar coordinates. To search, embed the question the same way and find the closest chunks. That's how "what oil does my car take" finds "SAE 0W-20 synthetic" with zero words in common.

**Like less of an idiot.** The model is MiniLM-L6-v2, run through Core ML, or through Apple's newer Core AI path on the 27 operating systems. It reads the tokens, produces one vector per token, and the app averages those (ignoring padding) into one vector for the chunk, then scales it to length one. Length one matters: comparing two unit vectors is a single multiplication, which makes searching a whole library cheap. A library records a fingerprint of the model, dimension, tokenizer and pooling, and refuses to mix vectors from different fingerprints, because two 384-number lists from two different models are not in the same space and comparing them is meaningless.

**Average Joe.** Why 384? It's what this model makes, and it's small enough that a whole library's vectors stay in one file the phone can read without loading it. Why does the phone need to "pool"? Because the model doesn't export a sentence vector, it exports token vectors, and averaging them correctly under the attention mask turned out to be load-bearing; there's a whole engineering doc about re-exporting the model so pooling was right. Why is "on the Neural Engine" not a true sentence? Because the app can only tell Core ML which processors it's allowed to use, and Core ML decides.

**Dot-connector.** The provider is a protocol, and the fingerprint is the contract. Four providers exist: Core ML MiniLM (default), Core AI MiniLM (default on iOS 27 and macOS 27, same vector space, and saved Core ML defaults are migrated to it), NLContextualEmbedding and NLEmbedding (512-dimension compatibility options, different spaces), and an Apple Foundation Models provider that is a 1,024-dimension placeholder and does nothing. Switching a library between spaces means re-embedding everything, which is blocked while ingestion runs. The model is not loaded at launch; it loads on the first embed. The query is embedded with the same provider as the documents, and a semantic query cache can skip that step for a repeated question.

**Expert.** `CoreMLSentenceEmbeddingProvider`: tokenise, fill three pre-allocated `MLMultiArray` inputs of length 512 (ids, mask, type), predict, `meanPool` under the attention mask, L2 normalise; validate dimension, finite values, non-empty. `makeModel(computeUnits:)` takes the unit set from `DeviceCapabilityService`'s GPU execution profile: Efficiency and Balanced request `.cpuAndNeuralEngine`; Performance and Maximum request `.all`. Batches over four texts run in a task group of width `embeddingConcurrency` (2 to 64 by tier). `EmbeddingService` is the actor that owns provider selection, loading, validation, batching, caching and errors. `EmbeddingFingerprint` pins provider, model, dimension, tokenizer, pooling. `CoreAISentenceEmbeddingProvider` uses Apple's Core AI compilation path and exposes no compute-unit control. The 2026-08-26 fix corrected Maximum from `.cpuAndGPU` (which excluded the Neural Engine) to `.all`.

**Expert's expert.** Three corrections to the word bank. "Neural Engine, status Core" overstates: five lines in the app permit it, none place work there, and Core AI exposes nothing; say "requested." "Core AI, Conditional" understates: on the 27 systems `SettingsStore` makes it the default and migrates. And the Opus page's "generated on the Neural Engine through Apple's newer on-device inference path" collapses two different providers into one sentence. Also worth knowing: the zero-vector fallback exists so a provider failure doesn't corrupt array shape, which means a zero vector can be persisted and will simply never match anything; validation is what should catch it.

## Every concept

### Apple Foundation Models embedding provider (Dormant, verified as a placeholder)
- **Idiot:** a plug for a future socket. Nothing behind it.
- **Dot-connector:** a 1,024-dimension scaffold that keeps the provider interface ready for an Apple embedding capability that isn't there.
- **Expert:** `AppleFMEmbeddingProvider.swift`; must not be described as a shipped embedder.

### Attention mask (Core, verified)
- **Idiot:** a list of which slots are real words and which are empty filler.
- **Dot-connector:** without it, pooling would average in the padding and the vector would depend on batch shape instead of text.
- **Expert:** built with the token IDs into the 512-length input; reused for masked pooling.

### Attention-masked mean pooling (Core, verified)
- **Idiot:** average the word vectors, skipping the filler.
- **Dot-connector:** the model exports token states, not a sentence vector; correct pooling is load-bearing for retrieval quality.
- **Expert:** `meanPool` in the Core ML provider after inference, before L2 normalisation; see `EMBEDDING_MEAN_POOLING_REEXPORT.md`.

### Bi-encoder (Core, verified)
- **Idiot:** question and passage are each turned into a pin separately, then compared.
- **Dot-connector:** independent passage vectors can be precomputed once at ingestion, which is what makes searching a corpus feasible on a phone; the cross-encoder in module 08 is the slow, smarter opposite.
- **Expert:** the first semantic stage; `CoreMLSentenceEmbeddingProvider` plus `HybridSearchService`.

### Core AI sentence provider (Conditional, default on the 27 systems)
- **Idiot:** the same model, run through Apple's newer engine on newer phones.
- **Dot-connector:** same 384-dimension space, so no rebuild; the runtime changed, the coordinates didn't.
- **Expert:** `CoreAISentenceEmbeddingProvider`; `SettingsStore` defaults to it on iOS 27 and macOS 27 and migrates saved Core ML defaults; exposes no placement control.

### Core ML sentence provider (Core, verified)
- **Idiot:** the default reader-into-numbers.
- **Dot-connector:** loads the bundled model, builds tensors, runs inference, pools, normalises; Core ML schedules the work across processors.
- **Expert:** `CoreMLSentenceEmbeddingProvider`; compute units from the GPU profile; loads on first `embed()`.

### Cosine similarity (Core, verified)
- **Idiot:** how close two pins are, as an angle.
- **Dot-connector:** compares direction, not size, so a long chunk and a short chunk about the same thing score alike.
- **Expert:** dot product over the product of norms; with unit vectors it is the dot product alone. `BNNSVectorDatabase`.

### Default MiniLM provider (Core, verified)
- **Idiot:** the specific little model the app ships.
- **Dot-connector:** compact, local, fast exact similarity, manageable storage.
- **Expert:** MiniLM-L6-v2, 384 dimensions, through Core ML; provenance in `THIRD_PARTY_NOTICES.md`.

### Document-chunk embedding (Core, verified)
- **Idiot:** the pin for each card.
- **Dot-connector:** made once at ingestion from the prefixed text; searched by every later question.
- **Expert:** written after validation, before the document becomes queryable.

### Dot product (Core, verified)
- **Idiot:** multiply matching numbers and add them up.
- **Dot-connector:** with normalised vectors it is cosine similarity, and it maps directly onto Accelerate, BNNS and Metal.
- **Expert:** `vDSP_dotpr` per vector, `vDSP_mmul` for the batch path, Metal kernel above 1,000.

### Embedding (Core, verified)
- **Idiot:** the pin.
- **Dot-connector:** a fixed-length numeric representation whose geometry approximates meaning; lets the app find related text under different words.
- **Expert:** 384 floats, produced by `EmbeddingService` for chunks at ingestion and for the query at search time.

### Embedding batch (Core, verified)
- **Idiot:** do several cards at once.
- **Dot-connector:** amortises model setup and uses the matrix hardware properly.
- **Expert:** batches over four texts run in a task group; batch size 8 to 512 by device tier.

### Embedding concurrency (Support, verified)
- **Idiot:** how many batches run at the same time.
- **Dot-connector:** too few underuses hardware; too many fights Vision for memory.
- **Expert:** `embeddingConcurrency` from `DeviceCapabilityService`, 2 to 64 by tier.

### Embedding dimension (Core, verified)
- **Idiot:** how many numbers are in a pin: 384.
- **Dot-connector:** a mismatch is not a quality difference, it's incompatibility.
- **Expert:** declared by the provider, recorded in metadata, validated on write, read and before search.

### Embedding fingerprint (Core, verified)
- **Idiot:** the map's serial number.
- **Dot-connector:** provider, model, dimension, tokenizer and pooling; vectors with different fingerprints are never compared.
- **Expert:** `EmbeddingFingerprint`, written with library metadata, checked before ingestion, loading, querying and migration. An unknown fingerprint means "do not act," not "mismatched."

### Embedding space (Core, verified)
- **Idiot:** the map itself.
- **Dot-connector:** equal vector length does not mean same map; different models make unrelated geometries at the same dimension.
- **Expert:** a library stays in one space until a full re-embed migrates it.

### Embedding translation target (Conditional, verified)
- **Idiot:** translate a copy before pinning it.
- **Dot-connector:** cross-language retrieval improves when all vectors share a language; the original stays for display.
- **Expert:** `TranslationService` before embedding, only when configured.

### Embedding validation (Core, verified)
- **Idiot:** check the pin isn't broken.
- **Dot-connector:** NaN values, wrong widths and silent truncation all serialise fine and poison every search.
- **Expert:** dimension, finiteness, non-empty; after provider output and at vector-store boundaries.

### EmbeddingProvider (Core, verified)
- **Idiot:** the plug shape every embedder has to fit.
- **Dot-connector:** the library must know exactly which map made its pins while the engine picks any available implementation.
- **Expert:** protocol: model identity, dimension, sequence limit, availability, batching, `embed`.

### EmbeddingService (Core, verified)
- **Idiot:** the manager of the pin-maker.
- **Dot-connector:** one owner for provider selection, loading, validation, batching, caching and errors, so documents and queries can't drift onto different providers.
- **Expert:** an actor between chunk or query text and the vector store on both paths.

### L2 norm (Core, verified)
- **Idiot:** the length of the arrow.
- **Dot-connector:** you need it to normalise, and it's stored separately so the batch path can divide after the fact.
- **Expert:** sqrt of the sum of squares; persisted in `_norms.bin`.

### L2 normalization (Core, verified)
- **Idiot:** shrink or stretch every arrow to length one.
- **Dot-connector:** turns cosine into a dot product and keeps providers numerically consistent.
- **Expert:** the last transformation before validation and persistence.

### NLContextualEmbedding provider (Conditional, verified)
- **Idiot:** Apple's built-in embedder, a different map.
- **Dot-connector:** 512 dimensions, a compatibility option, incompatible with MiniLM libraries.
- **Expert:** per-library selectable; requires matching fingerprint and a rebuild on change.

### NLEmbedding provider (Conditional, verified)
- **Idiot:** an older Apple embedder that averages word vectors.
- **Dot-connector:** a fallback where the sentence model is unavailable; also 512 dimensions, also a different map.
- **Expert:** isolated to libraries configured for it.

### Provider agreement test (Support, verified)
- **Idiot:** a test that two embedders make the same pins.
- **Dot-connector:** a new backend must preserve the space existing libraries expect, not merely compile.
- **Expert:** `EmbeddingProviderAgreementTests`; migration validation, not a query stage.

### Query embedding (Core, verified)
- **Idiot:** the pin for your question.
- **Dot-connector:** same provider, same space, made after rewriting and expansion decisions.
- **Expert:** Step 2 of `queryInternal`; skipped on a semantic cache hit.

### Re-embedding (Core, verified)
- **Idiot:** redo every pin with a new map.
- **Dot-connector:** required when model, dimension, tokenizer or pooling changes; partial migration would mix maps.
- **Expert:** explicit rebuild in `RAGService`; blocked during ingestion.

### Semantic query cache (Support, verified as `semantic_query_cache`)
- **Idiot:** remember the pin for a question you've asked before.
- **Dot-connector:** skips the embedding call for repeated normalised questions.
- **Expert:** a SQLite table with a container index; checked before Step 2, updated after success.

### Sentence embedding (Core, verified)
- **Idiot:** one pin for the whole card.
- **Dot-connector:** a token-level model output isn't searchable as one passage; pooling reduces it.
- **Expert:** consumes prefixed, tokenised chunk text; produces the stored vector.

### Special tokens (Core, verified)
- **Idiot:** the "start" and "end" markers the model expects.
- **Dot-connector:** the model was trained with them, and they count against the limit.
- **Expert:** `[CLS]` and `[SEP]` inserted by the tokenizer before the 510 ceiling is evaluated.

### Token IDs (Core, verified)
- **Idiot:** the numbers that stand for the words.
- **Dot-connector:** their meaning depends entirely on the tokenizer-model pairing.
- **Expert:** integers into the 512-length `input_ids` array.

### Token-state tensor (Core, verified)
- **Idiot:** one vector per word, before averaging.
- **Dot-connector:** what the model actually emits; pooling turns it into one vector.
- **Expert:** model output reduced immediately by masked mean pooling.

### Zero-vector fallback (Support, verified)
- **Idiot:** if the pin-maker fails, put in a blank pin instead of crashing.
- **Dot-connector:** keeps array shape valid; the blank carries no meaning and validation should flag it.
- **Expert:** error containment inside `EmbeddingService` before persistence.
