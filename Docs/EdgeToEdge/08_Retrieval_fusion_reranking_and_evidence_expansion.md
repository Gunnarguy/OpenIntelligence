# Module 08. Retrieval, fusion, reranking, and evidence expansion

Sixty concepts. Finding the evidence: two searches in parallel, one merged ranking, a second opinion from a cross-encoder, then diversity and neighbours.

## The ladder

**Like you're five.** Two helpers run off at the same time. One looks for your exact words. The other looks at the meaning map. They come back with two piles, which get shuffled into one. Then a slow, careful reader goes through the top of the pile with your question in one hand and each card in the other, and reorders them. Then the librarian throws out the cards that don't fit, spreads out the ones that all say the same thing, and grabs the card before and after each good one.

**Like an idiot.** Vector search and keyword search fail differently, so both run and their results are merged by rank position. A cross-encoder then rescores the short list by reading question and passage together, which is much more accurate and much too slow for the whole library. Chunks under a similarity floor are dropped. A diversity step stops five copies of the same paragraph from crowding out a second document. Neighbours and parent sections get pulled in. If the result is weak, a corrective search looks specifically for the shape of evidence the question needs: a table row, a number, a referenced page.

**Like less of an idiot.** Reciprocal rank fusion gives each chunk points for its rank in each list (1 over k plus rank, k = 60), weighted 0.7 for the vector list and 0.3 for keywords, and needs no score calibration because the two arms produce scores on different scales. Keyword-only hits that fell below the cut are re-attached, so an exact part number is never buried by paraphrase. The cross-encoder is a small Core ML model reading 512-token query-passage pairs. Maximal marginal relevance trades a little relevance for coverage. Parent-document retrieval restores the paragraph around a precise hit and deduplicates by token overlap. For spec questions, a "sniper" path scores chunks that jointly match several concepts and contain numeric or key-value signals, then a deterministic extractor tries structured rows, then patterns, before any model is asked.

**Average Joe.** The numbers for a Standard query: 30 is the target; the vector side gathers 90 and the keyword side up to 60; fusion merges; up to 90 are reranked; the floor at 0.28 and diversity at λ 0.60 cut from there. Deep Think starts at 35 with a 0.25 floor and λ 0.55; Maximum at 50, 0.20, 0.50. Lower floor and lower lambda mean "gather more, spread wider, let later stages sort it out." Why does the cross-encoder only see the shortlist? Because it can't precompute anything; every pair is a fresh inference.

**Dot-connector.** Recall first, precision second, and never the other way around: a reranker can only reorder what it received, so the first stage must be broad enough to contain the answer. That single sentence explains why top-K is multiplied by three before rerank, why the floor is dynamic rather than fixed, why there's an acceptance override, why lexical survivors exist, and why a retrieval cascade re-runs wider with more lexical weight when the first pass is weak. Also note the hardware: the vector arm is module 06's CPU-or-Metal scan; the reranker is Core ML with all units permitted; the MMR pairwise matrix goes to Metal above 50 candidates when the profile allows.

**Expert.** `HybridSearchService.hybridSearch` launches vector and FTS arms with `async let`; vector top-K is K×3 (×2 above K 50), FTS min(K×3, 60), structured rows min(K×3, 36). RRF k 60, weights 0.7/0.3, off the main thread on a snapshot; deterministic tie-break by chunk ID because `sort` is not stable and equal scores are routine. Lexical survivors up to max(4, K/6). Keyword-match boost ≤ 0.20 at 0.05 per weighted match, with any keyword matching over 30% of candidates treated as zero-discriminative. Section title and path boosts. `RAGEngine.rerankWithCrossEncoder` on ms-marco-TinyBERT-L2-v2 (provenance in `THIRD_PARTY_NOTICES.md`), pairs encoded to 512, concurrent prediction, `computeUnits = .all`, low-precision GPU accumulation allowed, called with K×3 and trimmed to K×3. `RetrievalPolicyService` computes the dynamic threshold (mode floor adjusted by count, top score, spread, intent, vocabulary mismatch) and the acceptance override; `filterAndDiversify` applies the floor, a multi-document guarantee, and MMR with the mode lambda (matrix on Metal above 50 candidates with Metal vector ops enabled and a GPU present). `ParentDocumentService` expands parents and siblings with Jaccard dedup above 80%. `GraphIndexService` BFS over typed edges with hop and budget limits. `EvidenceScoringPolicyService` holds the spec sniper, state-anchor adjustment, specification boost and corrective retrieval. `SpecificationExtractor` tries explicit state structures, structured table rows, then pattern-based extraction, with extraction confidence and entity-aware disambiguation, before generation.

**Expert's expert.** Retrieval is nondeterministic across runs of one build: two runs return different chunk IDs for one question, and the cause is upstream of tie-breaking (the trace and the benchmark ledger both record it). One tie at a top-N cutoff cascades: it changes which candidates survive, which changes rerank input, which changes the answer. Until that is found, no retrieval A/B on this app is trustworthy. The fusion-stage regression in the ledger is the other lesson: on one fixture set, fusing a weak dense arm with a stronger lexical arm scored worse than BM25 alone, which is why the weights are measured, not assumed. Two bank corrections: the reranker's architecture name, TinyBERT, is documented provenance, not a guess (the earlier trace called it unverified; it is in the notices file); and "neural start/end span model" is dormant, so "extractive QA" in shipping builds means the heuristic scorer.

## Every concept

### Acceptance override (Core, verified as an audit flag)
- **Idiot:** let the best card through even if its score is technically low.
- **Dot-connector:** relative rank, margin, breadth or extractive intent can justify evidence a rigid floor would discard.
- **Expert:** `RetrievalPolicyService` after the dynamic threshold, before the empty-retrieval fallback; surfaced as `acceptanceOverride` on the audit snapshot.

### Breadth-first search (Conditional, verified)
- **Idiot:** look at the neighbours first, then the neighbours' neighbours.
- **Dot-connector:** bounded, interpretable expansion around an anchor; no diving down one arbitrary link.
- **Expert:** `GraphIndexService` from top chunks, stopped by hop, score or budget.

### Candidate generation (Core, verified)
- **Idiot:** grab more cards than you'll keep.
- **Dot-connector:** rerank can't recover what was never retrieved.
- **Expert:** the hybrid entry; metrics in `RetrievalStageMetrics`.

### Corrective retrieval (Conditional, verified)
- **Idiot:** when the first search finds the topic but not the fact, search specifically for the fact's shape.
- **Dot-connector:** rescans for terms, structured data, numeric patterns or reference destinations before giving up or generating.
- **Expert:** `EvidenceScoringPolicyService` and `RAGService` after weak evidence assessment.

### Cross-encoder reranking (Core, verified)
- **Idiot:** the slow smart reader.
- **Dot-connector:** joint encoding sees interactions bi-encoders can't; accurate on a shortlist, impossible on a corpus.
- **Expert:** `RAGEngine.rerankWithCrossEncoder`; Core ML, all units, concurrent pairs.

### Cross-reference repair (Conditional, verified)
- **Idiot:** follow "see page 12" and fetch page 12.
- **Dot-connector:** the pointer chunk is not the answer and can be a false positive.
- **Expert:** `GraphIndexService` plus the scoring policy; after the first retrieval exposes the reference.

### Dense retrieval (Core, verified)
- **Idiot:** the meaning-map search.
- **Dot-connector:** paraphrase and synonyms with no word overlap.
- **Expert:** `BNNSVectorDatabase.search` inside `HybridSearchService`; module 06 for the CPU/GPU switch.

### Document-order restoration (Conditional, verified)
- **Idiot:** put the summary sentences back in the order they appeared.
- **Dot-connector:** rank order can reverse chronology.
- **Expert:** last step of `ExtractiveSummarizationService`.

### Dynamic similarity threshold (Core, verified)
- **Idiot:** the pass mark moves depending on the exam.
- **Dot-connector:** absolute cosine scores aren't calibrated across corpora; relative evidence can be useful even when every score is low.
- **Expert:** `RetrievalPolicyService` after initial candidates; inputs are count, top score, spread, intent, suspected vocabulary mismatch.

### Entity expansion (Conditional, verified)
- **Idiot:** fetch every card that mentions the same name.
- **Dot-connector:** a concept discussed across sections without repeating the query phrase.
- **Expert:** `EntityIndexService` during graph or agentic expansion.

### Entity-aware disambiguation (Core, verified)
- **Idiot:** prefer the card that actually names the thing you asked about.
- **Dot-connector:** stops a similar product's spec from winning over the named one.
- **Expert:** `SpecificationExtractor` after scoring, before ambiguity failure.

### Evidence assessment (Conditional, verified)
- **Idiot:** "do we have enough yet?"
- **Dot-connector:** coverage, relevance and gaps; the loop needs an evidence-based reason to continue.
- **Expert:** `IterativeRetrievalService` and the orchestrator after each pass.

### Explicit state-structure lookup (Conditional, verified)
- **Idiot:** the light-colour table, read directly.
- **Dot-connector:** keeps the state and its meaning paired.
- **Expert:** an early branch in `SpecificationExtractor` for state queries.

### Extraction confidence (Core, verified)
- **Idiot:** how sure the copy-out is.
- **Dot-connector:** a deterministic extractor still has to abstain when several values are plausible.
- **Expert:** computed before returning a span; low or ambiguous escalates to the model.

### Extractive QA (Conditional, verified as the heuristic path)
- **Idiot:** copy the answer out instead of writing one.
- **Dot-connector:** the value must exist in the source, which kills a whole class of hallucination.
- **Expert:** `ExtractiveQAService` heuristic scorer plus `SpecificationExtractor`; the neural span model is a stub.

### Extractive summarization (Conditional, verified)
- **Idiot:** pick the best sentences rather than writing new ones.
- **Dot-connector:** traceable wording, less hallucination.
- **Expert:** segment, embed sentences, MMR, restore order.

### Fusion weight (Core, verified) and Fusion-stage regression (Support, documented)
- **Idiot:** how much each helper's pile counts, and the day it turned out one helper was dragging the other down.
- **Dot-connector:** 0.7 vector, 0.3 keyword; on one fixture set fusion scored below BM25 alone, which is why the mix is measured.
- **Expert:** `HybridSearchService`; sweep script `scripts/sweep_fusion_weight.py`; record in `Docs/EVALS.md` and the benchmark matrix.

### Graph edge (Conditional, verified), Graph hop (Conditional, verified), Graph index (Conditional, verified)
- **Idiot:** cards connected by string, and how many strings away.
- **Dot-connector:** typed edges (next, previous, sibling, reference, same section, shared entity) preserve why two things relate; hops bound the blast radius.
- **Expert:** `GraphIndexService`, built from chunk metadata, traversed after initial retrieval; hop counts considered by packing.

### Heuristic extractive QA (Conditional, verified)
- **Idiot:** the rule-based copy-out that actually runs.
- **Dot-connector:** keyword overlap, entity types, proximity, passage rank, question type.
- **Expert:** `ExtractiveQAService` when the span model is unavailable, which is always.

### Hybrid search (Core, verified)
- **Idiot:** both searches, then merge.
- **Dot-connector:** complementary failure modes; the main retrieval entry point.
- **Expert:** `HybridSearchService.hybridSearch`.

### Initial candidate breadth (Core, verified)
- **Idiot:** how many cards to grab first: 30, 35 or 50.
- **Dot-connector:** the reranker only improves what it sees.
- **Expert:** `RAGQualityMode.initialTopK`.

### Iterative retrieval (Conditional, verified)
- **Idiot:** search, look, search again.
- **Dot-connector:** the first search can reveal the terminology the second needs.
- **Expert:** `IterativeRetrievalService`; stops on quality, pass count or no improvement.

### Jaccard deduplication (Core, verified)
- **Idiot:** don't include a parent and child that are mostly the same text.
- **Dot-connector:** token-set overlap above 80% is redundant.
- **Expert:** `ParentDocumentService` during expansion merge.

### L0 chunk (Core, verified), L1 summary chunk (Conditional, verified), L2 and L3 abstraction levels (Future, reserved)
- **Idiot:** detail cards, one summary card per document, and two levels that don't exist yet.
- **Dot-connector:** L0 is evidence; L1 is routing; L2/L3 are enum names.
- **Expert:** `ChunkAbstractionLevel` on `DocumentChunk`.

### Lexical retrieval (Core, verified)
- **Idiot:** the exact-word search.
- **Dot-connector:** part numbers, standards, names, quotations, measurements.
- **Expert:** FTS5 through `SQLiteFullTextService`, in parallel with dense.

### Lexical survivor guarantee (Core, verified)
- **Idiot:** don't let paraphrase bury an exact match.
- **Dot-connector:** exact identifiers are often the answer.
- **Expert:** re-attach up to max(4, K/6) lexical-only hits below the top-K cut; `HybridSearchService.swift:379`.

### Maximal marginal relevance (Core, verified), MMR lambda (Core, verified), Redundancy penalty (Core, verified), Pairwise similarity matrix (Support, verified)
- **Idiot:** don't pick five cards that say the same thing; the dial says how much variety to insist on.
- **Dot-connector:** greedy selection: relevance minus the max similarity to anything already chosen; lower lambda means more variety; the matrix precomputes the similarities.
- **Expert:** `RAGEngine`; λ 0.60/0.55/0.50; matrix on Metal above 50 candidates when the profile allows and a GPU exists, else `BNNSGraphService`.

### Metadata boost (Core, verified)
- **Idiot:** extra credit for headings, names, tables, numbers.
- **Dot-connector:** a raw score can't see the evidence-quality signals ingestion attached.
- **Expert:** `HybridSearchService` and `EvidenceScoringPolicyService` after fusion.

### Minimum similarity (Core, verified)
- **Idiot:** the pass mark.
- **Dot-connector:** 0.28, 0.25, 0.20 by mode, then adjusted dynamically.
- **Expert:** `RAGQualityMode` plus `RetrievalPolicyService`.

### Multi-vector retrieval (Conditional, verified) and Supplementary vector search (Conditional, verified)
- **Idiot:** search with several pins, not one.
- **Dot-connector:** rewrite, expansion, HyDE and subquestion vectors each probe a facet; results merge and dedupe before rerank.
- **Expert:** `RAGService` supplementary searches; recorded in audit feature flags.

### Neural start/end span model (Dormant, verified as a stub)
- **Idiot:** a reader that's on the blueprint shelf.
- **Dot-connector:** would find exact answer spans; the placeholder returns nil.
- **Expert:** `ExtractiveQAService` protocol and template; never active.

### Parallel retrieval arms (Core, verified)
- **Idiot:** both helpers run at once.
- **Dot-connector:** latency is the slower arm, not the sum.
- **Expert:** `async let` at the top of `hybridSearch`.

### Parent-document retrieval (Core, verified) and Sibling expansion (Core, verified)
- **Idiot:** grab the paragraph around the hit, and the cards next door.
- **Dot-connector:** small chunks rank well but lose definitions, conditions and headings; procedures span boundaries.
- **Expert:** `ParentDocumentService` after rerank and MMR, capped by mode and budget, deduped by Jaccard.

### Pattern-based specification extraction (Core, verified)
- **Idiot:** regex for grades, sizes, codes, dates.
- **Dot-connector:** not every document has a clean table; exact-value answers need a deterministic fallback.
- **Expert:** `SpecificationExtractor` after structured lookups fail, before generation.

### RAPTOR-lite summary routing (Conditional, verified)
- **Idiot:** overview questions read the summaries.
- **Dot-connector:** whole-document questions are answered by representative summaries, not an incidental chunk.
- **Expert:** `RAPTORSummaryRouter` chosen by `QueryRouterService`.

### Reciprocal rank fusion (Core, verified) and RRF constant k (Core, verified)
- **Idiot:** points for being near the top of either pile.
- **Dot-connector:** ranks are comparable across arms; scores aren't. k smooths the top positions.
- **Expert:** sum over lists of 1/(k + rank), k exactly 60, weighted 0.7/0.3; `HybridSearchService` and `BNNSGraphService`.

### Rerank batch size (Core, verified) and Rerank score (Core, verified) and Reranker tokenizer (Core, verified)
- **Idiot:** how many pairs the smart reader takes at once, the score it gives, and its own ruler.
- **Dot-connector:** batch size from mode and device; the score reorders the fused list; the tokenizer must match the reranker's contract.
- **Expert:** `AdaptivePipelineOptimizer`/`DeviceCapabilityService`; score from `RAGEngine`; tokenizer bundle `reranker_tokenizer.bundle`.

### Retrieval cascade (Conditional, verified)
- **Idiot:** if the first search is thin, search wider with more weight on exact words.
- **Dot-connector:** weak retrieval may mean the mix was too semantic, not that evidence is absent.
- **Expert:** `RetrievalPolicyService` after first-stage metrics fail; `usedRetrievalCascade` on the audit.

### Sentence-level relevance (Conditional, verified)
- **Idiot:** score sentences, not just cards.
- **Dot-connector:** a relevant chunk still contains irrelevant sentences.
- **Expert:** query-versus-sentence cosine inside extractive summarisation and context rescue.

### Spec sniper (Conditional, verified) and Specification boost (Conditional, verified) and Structured table lookup (Core, verified)
- **Idiot:** the sharpshooter for "what's the exact number."
- **Dot-connector:** chunks matching several query concepts with numeric, code or table signals are surfaced; then the table rows are read directly before any model is asked.
- **Expert:** `specTableSniper` in `RAGService`; boosts in `EvidenceScoringPolicyService`; row lookup in `SpecificationExtractor` against `chunk_table_rows`.

### Stable tie-break (Core, verified)
- **Idiot:** when scores tie, always break the tie the same way.
- **Dot-connector:** Swift's sort isn't stable; unstable order makes tests flaky and citations shift.
- **Expert:** by chunk identifier in `HybridSearchService`; note the source comment that one tie at a cutoff cascades through rerank.

### State-anchor adjustment (Conditional, verified)
- **Idiot:** extra credit for "flashing" and "orange" when you asked about a flashing orange light.
- **Dot-connector:** matching "indicator" alone is not enough in a manual full of lights.
- **Expert:** `EvidenceScoringPolicyService` before extraction for state-lookup queries.

### TinyBERT reranker (Core, verified provenance)
- **Idiot:** the specific small smart reader.
- **Dot-connector:** compact enough to run joint scoring on a phone for a shortlist.
- **Expert:** `cross-encoder/ms-marco-TinyBERT-L2-v2` in `THIRD_PARTY_NOTICES.md`; `ReRankerModel.mlpackage`; loaded at engine init in a detached task.

### Top-k (Core, verified)
- **Idiot:** keep the best K.
- **Dot-connector:** different K at different stages trades recall against cost.
- **Expert:** applied at dense/lexical retrieval, after fusion, after rerank, and at packing.

### Vocabulary mismatch (Core, verified as policy)
- **Idiot:** lots of cards, all with low scores, bunched together.
- **Dot-connector:** specialised language makes absolute thresholds misleading; lower the floor selectively.
- **Expert:** inferred from top and average scores in `RetrievalPolicyService`.
