# Retrieval and answer-generation practice for small-context, on-device RAG (evidence as of 2026-09-26)

Tag key: [primary, URL] = read in a fetched primary source (model README, paper repo, vendor post, raw benchmark data). [secondary, URL] = fetched blog or guide. [inferred (search summary), URL] = the number or claim is known only from a web-search summary of a page that could not be fetched (huggingface.co, arxiv.org, jina.ai, aclanthology.org, openreview.net and most vendor blogs were blocked). Items marked "pre-2023" may be superseded. "Computed" means I did the arithmetic on primary data myself; the inputs are cited. None of this touches the app's code; app facts come from the brief.

## 1. Which small (≤ ~600M) embedding models beat all-MiniLM-L6-v2, by how much, and at what cost (params, dims, max tokens, Matryoshka, license, languages, quantization)?

### Takeaway
all-MiniLM-L6-v2 (2021, 22.7M params, 384-d, truncates at 256 word pieces, trained at 128) scores 41.95 nDCG@10 on the 15-task MTEB/BEIR retrieval set. That is only ~2 points above plain BM25 (39.84) on the same tasks, and a statistical tie with BM25 on 13 common BEIR tasks (42.41 vs 41.83). Models of the same or similar size score 8 to 10 points higher: snowflake-arctic-embed-xs (same 22.7M / 384-d, built from MiniLM) 50.15; bge-small-en-v1.5 51.68; arctic-embed-s 51.98. Models between 150M and 600M score 13 to 14 points higher: gte-modernbert-base 55.26; Qwen3-Embedding-0.6B 55.52. On the newer MTEB(eng, v2) retrieval set the gaps are similar: MiniLM 0.4292, bge-small 0.5149, EmbeddingGemma-300m 0.5463. Binary quantization with rescoring keeps about 96%, and int8 is near-lossless if calibrated.

### Cited Findings
**Model facts.** Parameters, dimensions, max tokens, license and languages come from MTEB's model registry, read from the mteb 2.21.8 wheel (released 2026-09-23) [primary, https://pypi.org/pypi/mteb/json]. Retrieval scores are cited per row.

| Model (release) | Params | Dims | Max tokens | MRL | License | Languages | Retrieval nDCG@10 |
|---|---|---|---|---|---|---|---|
| all-MiniLM-L6-v2 (2021-08-30, pre-2023) | 22,713,216 | 384 | 256 | not claimed | Apache-2.0 | English | BEIR-15 **41.95** (Arctic README; also my recompute from raw MTEB results); MTEB(eng,v2) Retr. **0.4292** (HF Ettin blog) |
| snowflake-arctic-embed-xs (2024-07-08) | 22,713,216 | 384 | 512 | not claimed | Apache-2.0 | English | **50.15** (Arctic README) |
| bge-small-en-v1.5 (2023-09-12) | 33.4M | 384 per BGE README (registry says 512; see conflicts) | 512 | not claimed | MIT | English | **51.68**, MTEB avg 62.17 (BGE README); MTEB(eng,v2) Retr. **0.5149** (Ettin blog) |
| gte-small (2023-07-27) | 33,360,512 | 384 | 512 | not claimed | MIT | English | **49.46**, MTEB avg 61.36 (BGE README table) |
| snowflake-arctic-embed-s (v1, 2024-04-12) | 33.36M | 384 | 512 | not claimed | Apache-2.0 | English | **51.98** (Arctic README) |
| nomic-embed-text-v1.5 (2024-02-10) | 136.7M | 768 | 8192 | yes | Apache-2.0 | English | **53.01** or **53.25** (the Arctic README gives both; see conflicts); MTEB(eng,v2) Retr. **0.5226** (Ettin blog) |
| gte-modernbert-base (2025-01-21) | 149.0M | 768 | 8192 | not claimed | Apache-2.0 | English | BEIR-15 **55.26** (my recompute from raw results); ~55.2 (search summary) |
| snowflake-arctic-embed-m-v2.0 (2024-12-04) | 305M | 768 | 8192 | yes | Apache-2.0 | multilingual | BEIR(15) 55.4, MIRACL(4) 55.2, CLEF 53.9 (search summary of model card); 57.01 mean on 13 BEIR tasks from raw results |
| EmbeddingGemma-300m (2025-09-04) | 307.6M ("308M") | 768, MRL to 512/256/128 | 2048 | yes | "gemma" (Gemma Terms) | 100+ languages | MTEB(eng,v2) Retr. **0.5463** (Ettin blog); MTEB(eng,v2) mean 69.67 (search summary) |
| nomic-embed-text-v2-moe (2025-02-07) | 475.3M total, 305M active | 768, MRL to 256 | 512 | yes | Apache-2.0 | ~100 languages | BEIR 52.86, MIRACL 65.80 (search summary of model card) |
| bge-m3 (2024) | 568M | 1024 | 8192 | not claimed | MIT | 100+ languages | MMTEB mean 59.56, MMTEB retrieval 54.60 (Qwen3 README) |
| jina-embeddings-v3 (2024-09-18) | 572.3M | 1024 | 8192 | yes | **CC-BY-NC-4.0** | multilingual | English MTEB avg 65.52 (search summary); retrieval average not confirmed |
| Qwen3-Embedding-0.6B (2025-06-05) | 595.8M | 1024, MRL | 32,768 | yes | Apache-2.0 | 100+ languages | BEIR-15 **55.52** (my recompute); MTEB(eng,v2) retrieval 61.83 and MMTEB retrieval 64.64 (self-reported, with instructions, Qwen3 README) |
| multilingual-e5-small | 118M | 384 | 512 | not claimed | MIT | multilingual | BEIR-15 46.70 (my recompute) |
| BM25 (bm25s baseline) | – | – | – | – | – | – | BEIR-15 **39.84** (my recompute) |

**Sources for the table**
- The retrieval tables for all-MiniLM-L6-v2 41.95, arctic-xs 50.15, arctic-s 51.98, bge-small 51.68, e5-small-v2 49.04 and nomic-v1.5 are in the Snowflake Arctic README. It also states that arctic-embed-xs is "based on the all-MiniLM-L6-v2 model with only 22m parameters and 384 dimensions". Arctic v2.0 was released 2024-12-04 as **m-v2.0 and l-v2.0 only**; I found no "arctic-embed-s-v2.0" [primary, https://raw.githubusercontent.com/Snowflake-Labs/arctic-embed/main/README.md].
- BGE v1.5 MTEB table: bge-small 384-d / 512 tokens / avg 62.17 / retrieval 51.68; gte-small 49.46; all-mpnet-base-v2 retrieval 43.81 [primary, https://raw.githubusercontent.com/FlagOpen/FlagEmbedding/master/research/baai_general_embedding/README.md]. bge-m3 is described as "Multi-Linguality (100+ languages), Multi-Granularities (input length up to 8192), Multi-Functionality (dense, lexical, multi-vec/colbert)" [primary, https://raw.githubusercontent.com/FlagOpen/FlagEmbedding/master/README.md].
- Qwen3-Embedding README: 0.6B has 28 layers, 32K sequence, 1024 dims, MRL, instruction-aware. MMTEB mean(task) 64.33 and retrieval 64.64. MTEB(eng,v2) mean 70.70 and retrieval 61.83. The README says "using instructions typically yields an improvement of 1% to 5%" [primary, https://raw.githubusercontent.com/QwenLM/Qwen3-Embedding/main/README.md].
- MTEB(eng, v2) Retrieval, 10 tasks, retriever-only nDCG@10: static-retrieval-mrl-en-v1 0.3495, all-MiniLM-L6-v2 0.4292, bge-small-en-v1.5 0.5149, nomic-embed-text-v1.5 0.5226, embeddinggemma-300m 0.5463, jina-embeddings-v5-text-small-retrieval (596M) 0.5980. Source: "Introducing the Ettin Reranker Family", Hugging Face blog, May 19, 2026 [primary, https://raw.githubusercontent.com/huggingface/blog/main/ettin-reranker.md].
- EmbeddingGemma: 308M parameters, 2K context window, 100+ languages, MRL truncation 768→512/256/128. The comparison excluded models "trained on more than 20% of the MTEB data". Source: HF blog, Sep 4, 2025 [primary, https://raw.githubusercontent.com/huggingface/blog/main/embeddinggemma.md]. Search summaries add that it was trained with quantization-aware training, runs in under 200MB RAM, and is near-lossless at int8/int4. Truncating 768→256 costs about 2.4% [inferred (search summary), https://ai.google.dev/gemma/docs/embeddinggemma/model_card].
- nomic v1.5 supports "Matryoshka Representation Learning for flexible embedding sizes" [primary, https://raw.githubusercontent.com/nomic-ai/contrastors/main/README.md]. For v2-moe: 8 experts with top-2 routing, 475M total / 305M active, MRL 768→256, BEIR 52.86, MIRACL 65.80 [inferred (search summary), https://huggingface.co/nomic-ai/nomic-embed-text-v2-moe].
- arctic-embed-m-v2.0: BEIR 55.4, MIRACL(4) 55.2, CLEF(Full) 53.9. MRL truncation gives "3x smaller with ~3% degradation", and adding int4 gives "128 bytes per doc" [inferred (search summary), https://huggingface.co/Snowflake/snowflake-arctic-embed-m-v2.0].
- jina-embeddings-v3: 570M parameters, 8192 tokens, task-specific LoRA adapters, MRL, English MTEB average 65.52 [inferred (search summary), https://jina.ai/news/jina-embeddings-v3-a-frontier-multilingual-embedding-model/]. License CC-BY-NC-4.0 [primary, MTEB registry above].
- all-MiniLM-L6-v2 truncation: the model card says "input text longer than 256 word pieces is truncated", and the model was trained with sequence length limited to **128 tokens**. The underlying BERT tokenizer and position embeddings go to 512, and a GitHub issue discusses the 128 vs 256 confusion [inferred (search summary), https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2 and https://github.com/UKPLab/sentence-transformers/issues/1865]. MTEB's registry independently records max_tokens=256 [primary, https://pypi.org/pypi/mteb/json].

**Independent check from raw MTEB result files.** Revision-pinned per-task nDCG@10, test split, dev for MSMARCO [primary, https://raw.githubusercontent.com/embeddings-benchmark/results/main/results/sentence-transformers__all-MiniLM-L6-v2/8b3219a92973c328a8e22fadcfa821b5dc75636a/MSMARCO.json and sibling files; BM25 at .../results/mteb__baseline-bm25s/0_1_10/]:

| Task | BM25s | all-MiniLM-L6-v2 | mE5-small | gte-modernbert-base | Qwen3-Emb-0.6B |
|---|---|---|---|---|---|
| ArguAna | 49.3 | 50.2 | 39.1 | 74.6 | 71.0 |
| ClimateFEVER | 13.6 | 20.3 | 22.5 | 45.9 | 42.1 |
| DBPedia | 29.9 | 32.3 | 37.8 | 41.4 | 39.5 |
| FEVER | 48.1 | 51.9 | 75.3 | 94.0 | 88.1 |
| FiQA2018 | 25.1 | 36.9 | 33.1 | 49.5 | 46.6 |
| HotpotQA | 56.9 | 46.5 | 65.1 | 70.4 | 65.7 |
| NFCorpus | 32.1 | 31.6 | 31.1 | 34.3 | 36.7 |
| NQ | 28.5 | 43.9 | 56.3 | 56.1 | 53.5 |
| QuoraRetrieval | 80.4 | 87.6 | 88.2 | 88.6 | 87.8 |
| SCIDOCS | 15.8 | 21.6 | 13.9 | 20.4 | 24.4 |
| SciFact | 68.7 | 64.5 | 67.6 | 76.4 | 69.7 |
| Touche2020 | 33.1 | 16.9 | 21.2 | 18.0 | 33.2 |
| TRECCOVID | 62.3 | 47.2 | 72.3 | 75.7 | 90.5 |
| **Mean, 13 tasks** | **41.83** | **42.41** | **47.95** | **57.33** | **57.60** |
| **BEIR-15 avg** (adds MSMARCO dev and CQADupstack mean) | 39.84 | **41.95** | 46.70 | 55.26 | 55.52 |

- Using MSMARCO's "test" split (TREC-DL, 63.69) instead of "dev" (36.54) inflates MiniLM's BEIR-15 average to 43.76. With dev, my recomputation reproduces the published 41.95 exactly [primary, same file].
- snowflake-arctic-embed-m-v2.0 averages **57.01** on the same 13 tasks (its MSMARCO file is missing) [primary, https://raw.githubusercontent.com/embeddings-benchmark/results/main/results/Snowflake__snowflake-arctic-embed-m-v2.0/f2a7d59d80dfda5b1d14f096f3ce88bb6bf9ebdc/].
- BM25 beats all-MiniLM-L6-v2 on 5 of 13 tasks: HotpotQA, NFCorpus, SciFact, Touche2020 and TRECCOVID [primary, computed from the table above].

**Quantization and Matryoshka.**
- Binary quantization cuts memory and disk by 32x. It "preserve[s] roughly ~92.5%" of retrieval performance without rescoring and "up to ~96%" with float32-query rescoring, with retrieval "up to 32x" faster. Source: "Binary and Scalar Embedding Quantization", HF blog, Mar 22, 2024 [primary, https://raw.githubusercontent.com/huggingface/blog/main/embedding-quantization.md].
- int8 scalar quantization is 4x smaller. "The calibration dataset has a large influence on the performance, since it defines the buckets" [primary, https://raw.githubusercontent.com/UKPLab/sentence-transformers/master/examples/sentence_transformer/applications/embedding-quantization/README.md]. The retention of about 96–99% is known only from search summaries [inferred (search summary), https://github.com/huggingface/blog/blob/main/embedding-quantization.md].
- Matryoshka, measured on STSb (not retrieval): "Even at 8.3% of the embedding size, the Matryoshka model preserves 98.37% of the performance, much higher than the 96.46% by the standard model" [primary, https://raw.githubusercontent.com/UKPLab/sentence-transformers/master/examples/sentence_transformer/training/matryoshka/README.md].
- Static (lookup-table) embedders run "100x to 400x faster on CPU" (HF blog, Jan 15, 2025) [primary, https://raw.githubusercontent.com/huggingface/blog/main/static-embeddings.md]. But static-retrieval-mrl-en-v1 scores 0.3495 on MTEB(eng,v2) retrieval, below MiniLM's 0.4292 [primary, Ettin blog above]. They are not a quality upgrade.

**Conflicts to record**
- bge-small-en-v1.5 dimension: 384 in BGE's own README; `embed_dim=512` in the mteb 2.21.8 registry. The README is the authority, so the registry is probably wrong.
- nomic-embed-text-v1.5 MTEB retrieval: the Arctic README lists both 53.25 and 53.01 in different tables.
- MIRACL for arctic-embed-m-v2.0: 55.2 in Snowflake's "MIRACL(4)" versus 59.90 in Nomic's comparison table (search summary). The two sources use different MIRACL subsets.
- Qwen3-0.6B's self-reported MTEB(eng,v2) retrieval of 61.83 (with task instructions) is not directly comparable to the Ettin blog's third-party 0.5463 for EmbeddingGemma on the same named benchmark.

### Inferences
- **The dense arm is the weakest link in the current stack** (confidence: high on benchmarks, medium on transfer to personal documents). all-MiniLM-L6-v2 adds only about 2 nDCG points over BM25 on BEIR-15, and loses to BM25 on 5 of 13 tasks. A same-dimension swap (384-d) to bge-small-en-v1.5, arctic-embed-s or arctic-embed-xs is worth about +8 to +10 points. arctic-embed-xs is the minimal-cost swap: identical parameter count and dimensionality, built from MiniLM. Any swap requires re-embedding the corpus. Query prefixes and pooling differ by model and must be implemented exactly as each model card specifies.
- **The 256-token truncation matters if chunks exceed about 200 English words** (confidence: medium; the app's chunk size was not checked here). Text past token 256 never influences the dense vector, and the model was trained on only 128-token sequences, so long-chunk embeddings are out of distribution. Only BM25 sees the chunk tails. Longer-window small models (gte-modernbert-base at 8192; EmbeddingGemma at 2048) remove this failure mode.
- **Licensing filters the list for a paid App Store app** (confidence: high on the license strings, low on legal interpretation). jina-embeddings-v3 and jina-colbert-v2 are CC-BY-NC-4.0 (non-commercial). EmbeddingGemma is under the Gemma Terms of Use and needs a legal read. BGE and gte-small are MIT; Arctic, Nomic, gte-modernbert and Qwen3 are Apache-2.0.
- For English-only personal corpora, gte-modernbert-base (149M) matches Qwen3-0.6B (596M) on BEIR-15 (55.26 vs 55.52) at a quarter of the parameters. If multilingual matters, EmbeddingGemma (308M, MRL, QAT) and arctic-embed-m-v2.0 (305M, Apache-2.0, MRL plus int4) are the 300M-class candidates.

### Gaps
- No fetched source gives on-device (Apple Neural Engine or iPhone GPU) embedding latency for any of these models. Everything here is desktop CPU/GPU or unstated.
- jina-embeddings-v3's English retrieval average and gte-modernbert-base's MRL support were not confirmed from a primary source.
- MTEB results for nomic-v1.5 truncated to 64/128/256/512 dimensions are listed in the results index, but the files were not at the indexed paths, so the Matryoshka retrieval curve for that model is unconfirmed.
- The claim that all-MiniLM-L6-v2 was trained at 128 tokens rests on search summaries of the HF model card (blocked).

## 2. Does BM25 plus dense retrieval beat either alone, is RRF or a tuned weighted combination better, and when does fusion do worse than its better arm?

### Takeaway
Hybrid usually beats either arm, and the gain is largest when the arms have comparable quality but different strengths. That describes MiniLM versus BM25. RRF is the safe default without labeled data. With tens to hundreds of labeled queries, a tuned convex (weighted-score) combination beats it (Bruch et al. 2023; Elastic). Fusion loses to its better arm on a sizeable minority of queries: 24% in one measured SciFact run. A weak arm can drag the fusion down (the "weakest link"). The fixes are to strengthen the weak arm, tune or route the weights per query type, and evaluate reranking of the fused list rather than assuming it helps.

### Cited Findings
- Anthropic's evaluation: "Embeddings+BM25 is better than embeddings on their own". Contextual BM25 on top of contextual embeddings moved the failure reduction from 35% to 49% (Sep 19, 2024) [primary, https://www.anthropic.com/engineering/contextual-retrieval].
- **Measured third-party benchmark** (BEIR SciFact, 300 queries, Apple-silicon laptop, run 2026-09-21, 95% bootstrap CIs):
  - BM25 0.654, dense (multilingual-e5-small) 0.661, RRF hybrid **0.702**.
  - RRF vs BM25: **+0.049 [+0.028, +0.069]**. RRF vs dense: +0.042 [+0.015, +0.069]. Dense vs BM25: +0.007 [−0.030, +0.044], not significant.
  - "Fusion did worse than the better single mode" on **72 of 300** queries, beat both on 22 and tied on 206.
  - Adding ms-marco-MiniLM-L-6-v2 reranking of the top 20: −0.008 [−0.035, +0.020] vs RRF, at +357 ms per query. It repaired the 72 fusion failures (+0.125) and damaged the 22 fusion wins (−0.122).
  - [primary, https://raw.githubusercontent.com/regankight/es-hybrid-retrieval-benchmark/main/README.md] (individual's benchmark, not peer-reviewed).
- Bruch et al., "An Analysis of Fusion Functions for Hybrid Retrieval" (ACM TOIS, Aug 2023; arXiv 2210.11934):
  - A convex combination (CC) of normalized lexical and semantic scores outperforms RRF both in-domain and out-of-domain.
  - RRF is sensitive to its parameters.
  - CC is largely agnostic to the normalization choice and sample-efficient: it needs only a small set of examples to tune its single weight.
  - [inferred (search summary), https://arxiv.org/abs/2210.11934; https://www.pinecone.io/research/an-analysis-of-fusion-functions-for-hybrid-retrieval/]
- Original RRF (Cormack, Clarke & Buettcher, SIGIR 2009, pre-2023): k=60 gave the best average. RRF beat Condorcet Fuse and the best individual run in most experiments [inferred (search summary), https://cormack.uwaterloo.ca/cormacksigir09-rrf.pdf].
- Elastic (BM25 + ELSER across BEIR):
  - About **40 annotated queries** were enough for a tuned linear combination to start beating RRF.
  - With 300 calibration queries, the optimized linear combination gave **+6% nDCG@10** versus **+1.4%** for RRF over the same baseline.
  - Without calibration data, RRF is the safer default.
  - [inferred (search summary), https://www.elastic.co/search-labs/blog/improving-information-retrieval-elastic-stack-hybrid]
- Weaviate reported that relativeScoreFusion (min-max normalized score sum) gave about **6% higher recall** than rankedFusion (RRF-style) on FIQA and made it the default [inferred (search summary), https://weaviate.io/blog/hybrid-search-fusion-algorithms].
- MTEB (mteb 2.21.8) now ships hybrid baselines that fuse BM25s with multilingual-e5-small three ways:
  - `rrf`: weight·1/(k+rank), k=60, equal weights.
  - `dbsf`: normalize each arm by mean ± 3σ, then clip.
  - `rsf`: min-max normalization.
  - Each arm retrieves max(top_k, 100) candidates.
  - [primary, mteb/models/hybrid_wrappers.py and hybrid_models.py in the wheel at https://pypi.org/pypi/mteb/json]. Their scores were not found in the public results repo.
- "Balancing the Blend: An Experimental Analysis of Trade-offs in Hybrid Search" (arXiv 2508.01405, Aug 2025) covers 4 paradigms and 11 datasets. It reports a **"weakest link" phenomenon**: a weak retrieval path "can substantially degrade overall accuracy", which argues for assessing each path's quality before fusion [inferred (search summary), https://arxiv.org/abs/2508.01405].
- DAT, Dynamic Alpha Tuning (arXiv 2503.23013, Mar 2025): an LLM judges each arm's top-1 result per query and sets the fusion weight. It consistently beats fixed-weight hybrids [inferred (search summary), https://arxiv.org/abs/2503.23013].
- The BGE-M3 authors recommend "hybrid retrieval + re-ranking" [primary, https://raw.githubusercontent.com/FlagOpen/FlagEmbedding/master/research/BGE_M3/README.md].
- Per-dataset arm divergence, raw MTEB data:
  - BM25 far ahead of MiniLM: Touche2020 (33.1 vs 16.9), TRECCOVID (62.3 vs 47.2).
  - MiniLM far ahead of BM25: NQ (43.9 vs 28.5), FiQA (36.9 vs 25.1).
  - [primary, raw MTEB results, section 1]

### Inferences
- **RRF(k=60), equal weights, BM25 plus MiniLM is a defensible default but probably not the best available** (confidence: medium). The arms are about equal on average and win on different query types, which is where RRF helps most. The larger lever is upgrading the dense arm (+8 to +14 nDCG points, section 1). Switching RRF to a tuned combination is worth a few points at most (Elastic: +6% vs +1.4%).
- **Fusion falls below its better arm when one arm is confidently right and the other returns plausible noise** (confidence: medium). An equal-weight rank sum then promotes the noise; in the SciFact run this happened on 24% of queries. Keyword-style queries (proper nouns, part numbers, clause numbers such as "notice period") suit BM25. Paraphrase queries suit dense. Evidence-supported fixes:
  1. Tune the weight on a golden set of 40 or more queries (Elastic; Bruch).
  2. Use score-normalized fusion (RSF or DBSF) when scores are well-behaved.
  3. Route or weight per query (DAT).
  4. Improve the weak arm.
  5. Measure, rather than assume, the reranker's effect on the fused list; it can both repair and break fusion.
- FTS5 exposes bm25() scores, so RSF, DBSF or convex combination are implementable next to RRF without a new index (confidence: high that it is feasible; untested here).

### Gaps
- There is no accessible published measurement of RRF versus convex combination for BM25 plus all-MiniLM-L6-v2 specifically. MTEB's hybrid baseline results are not in the public results repo.
- Bruch et al.'s exact nDCG deltas were not fetched (arXiv blocked).
- Nothing found on personal-document corpora (manuals, leases, receipts), whose query mix may differ sharply from BEIR.

## 3. Rerankers: quality and latency by size, whether they help, ColBERT options, and whether small-LM listwise reranking is practical

### Takeaway
ms-marco-TinyBERT-L2-v2 is the least accurate member of its 2021 family: 69.84 vs 74.30 NDCG@10 on TREC-DL19, and 32.56 vs 39.01 MRR@10, compared with MiniLM-L6-v2. In 2026 benchmarks even MiniLM-L6-v2 adds only about +0.015 nDCG on average over retrieval alone. bge-reranker-base and mxbai-rerank-base-v1 average slightly below retrieval-only. Modern small rerankers are both faster and much better: ettin-reranker-17m (+0.064) and 32m/68m/150m (+0.085 to +0.106). Rerankers can make a strong first stage worse, and they degrade when fed more candidates. Every reranker, and every fallback, must be A/B-measured against "no rerank".

### Cited Findings
- **Sentence-Transformers MS MARCO cross-encoders** (2021 models, pre-2023), NDCG@10 TREC-DL19 / MRR@10 MS MARCO dev / docs per second (hardware not stated in the fetched page):
  - TinyBERT-L2-v2: 69.84 / 32.56 / 9000
  - MiniLM-L2-v2: 71.01 / 34.85 / 4100
  - MiniLM-L4-v2: 73.04 / 37.70 / 2500
  - MiniLM-L6-v2: 74.30 / 39.01 / 1800
  - MiniLM-L12-v2: 74.31 / 39.02 / 960
  - electra-base: 71.99 / 36.41 / 340
  - [primary, https://raw.githubusercontent.com/UKPLab/sentence-transformers/master/docs/cross_encoder/pretrained_models.md]
- **MTEB(eng, v2) Retrieval**, top-100 reranked, mean nDCG@10 over 6 first-stage embedders ("Introducing the Ettin Reranker Family", HF blog, May 19, 2026):
  - Qwen3-Reranker-4B 0.6367; mxbai-rerank-large-v2 (1.54B) 0.6115
  - ettin-1b 0.6114; ettin-400m 0.6091; **ettin-150m 0.5994**
  - Qwen3-Reranker-0.6B (596M) 0.5940; mxbai-rerank-base-v2 (494M) 0.5920
  - **ettin-68m 0.5915**; jina-reranker-m0 0.5856; gte-reranker-modernbert-base (150M) 0.5843
  - **ettin-32m 0.5779**; granite-reranker-english-r2 0.5656; **ettin-17m (17.6M) 0.5576**
  - bge-reranker-v2-m3 (568M) 0.5526; bge-reranker-large 0.5098
  - **ms-marco-MiniLM-L6-v2 (22.7M) 0.5082**; MiniLM-L12-v2 0.5066; mxbai-rerank-large-v1 0.5063; MiniLM-L4-v2 0.4979; mxbai-rerank-xsmall-v1 (70.8M) 0.4968
  - **bge-reranker-base (278M) 0.4890**; mxbai-rerank-base-v1 (184M) 0.4865
  - Retriever-only scores for the six embedders were 0.3495 to 0.5980 (listed in section 1).
  - [primary, https://raw.githubusercontent.com/huggingface/blog/main/ettin-reranker.md]
- **Computed from that table:** the retriever-only mean over the 6 embedders is 0.4934. Average gain over retrieval alone:
  - ms-marco-MiniLM-L6-v2 +0.015; MiniLM-L4 +0.005
  - bge-reranker-base −0.004; mxbai-rerank-base-v1 −0.007
  - bge-reranker-v2-m3 +0.059; ettin-17m +0.064; gte-reranker-modernbert-base +0.091; Qwen3-Reranker-0.6B +0.101; ettin-150m +0.106
  - [primary inputs, same URL; arithmetic mine]
- **CPU throughput** (Intel i7-13700K, NQ documents, max_length 512), pairs per second:
  - ettin-17m 267.4; MiniLM-L4 206.2; **MiniLM-L6 143.9**; ettin-32m 92.5; MiniLM-L12 75.9
  - mxbai-xsmall-v1 38.9; ettin-68m 31.2; bge-reranker-base 19.2
  - gte-reranker-modernbert-base 14.7; ettin-150m 14.0; mxbai-base-v1 13.4
  - bge-reranker-large 6.2; **bge-reranker-v2-m3 6.0**; ettin-400m 5.2; mxbai-base-v2 3.5; ettin-1b 2.1
  - On an H100 GPU, bf16 with FlashAttention-2 and unpadding gives 1.7x (17M) to 8.3x (1B) over fp32+SDPA.
  - [primary, same URL]
- **GooAQ, rerank top-30** (retriever alone 59.12). Source: "Training and Finetuning Reranker Models with Sentence Transformers", HF blog, Mar 26, 2025.
  - ms-marco-MiniLM-L6-v2 69.56; jina-reranker-v1-tiny 66.83
  - jina-reranker-v2-base-multilingual (278M) 74.87; bge-reranker-base 70.98; bge-reranker-v2-m3 73.56
  - mxbai-xsmall-v1 66.63; mxbai-base-v1 70.43; mxbai-large-v2 75.40
  - gte-reranker-modernbert-base 73.18
  - A **domain-finetuned** ModernBERT-base (150M): 77.14; ModernBERT-large: 79.42
  - [primary, https://raw.githubusercontent.com/huggingface/blog/main/train-reranker.md]
- **Rerankers can hurt a strong first stage.** In the Qwen3 reranker table, the first-stage Qwen3-Embedding-0.6B scores 61.82 on MTEB-R. Reranking with Jina-multilingual-reranker-v2-base gives 58.22, gte-multilingual-reranker-base 59.51, **BGE-reranker-v2-m3 57.03**, Qwen3-Reranker-0.6B 65.80 [primary, https://raw.githubusercontent.com/QwenLM/Qwen3-Embedding/main/README.md]. The candidates are the top 100 from Qwen3-Embedding-0.6B [inferred (search summary), https://huggingface.co/Qwen/Qwen3-Reranker-0.6B].
- "Drowning in Documents: Consequences of Scaling Reranker Inference" (arXiv 2411.11767, Nov 2024):
  - As more documents are reranked, Recall@10 fell below retrieval alone in **53.3% (academic) and 44.4% (enterprise)** of cases.
  - Pointwise cross-encoders give "phantom hits": high scores to documents with no lexical or semantic overlap.
  - Listwise LLM reranking was more robust as K scaled.
  - [inferred (search summary), https://arxiv.org/abs/2411.11767]
- mxbai-rerank v2 README: BEIR avg mxbai-rerank-large-v2 57.49, base-v2 55.57, large-v1 49.32; latency 0.89 / 0.67 / 2.24 s (hardware not stated) [primary, https://raw.githubusercontent.com/mixedbread-ai/mxbai-rerank/main/README.md]. On an 11-dataset BEIR subset, mxbai-rerank-xsmall-v1 scores 43.9 and base-v1 46.9 [inferred (search summary), https://www.mixedbread.com/docs/models/reranking/mxbai-rerank-xsmall-v1]. The two sources use different subsets and first stages, so they are not comparable.
- jina-reranker-v2-base-multilingual has 278M parameters and "15× higher throughput than bge-reranker-v2-m3" [inferred (search summary), https://jina.ai/news/jina-reranker-v2-for-agentic-rag-ultra-fast-multilingual-function-calling-and-code-search/]. jina-reranker-v3 (0.6B, **listwise**, Sep 2025) reports BEIR 61.94 vs mxbai-rerank-large-v2 61.44 [inferred (search summary), https://arxiv.org/abs/2509.25085].
- **ColBERT / late interaction**, BEIR average nDCG@10:
  - ColBERTv2 50.02; **answerai-colbert-small-v1 53.79**; jina-colbert-v2 53.1; GTE-ModernColBERT-v1 54.89
  - [primary, https://raw.githubusercontent.com/lightonai/pylate/main/docs/models/models.md]
  - answerai-colbert-small-v1 is 33M parameters, released Aug 13, 2024, "beats even bge-base" (53.25) [inferred (search summary), https://www.answer.ai/posts/2024-08-13-small-but-mighty-colbert.html]
  - jina-colbert-v2 is 559M parameters, 8192 tokens, CC-BY-NC-4.0 [primary, MTEB registry]. It reports 53.1 vs ColBERTv2 49.6 [inferred (search summary), https://arxiv.org/abs/2408.16672].
  - Conflict: ColBERTv2 is 49.6 in Jina's paper but 50.02 in PyLate's table, probably from different dataset subsets or versions. jina-colbert-v2's 53.1 matches in both.
- **Listwise with small LMs:**
  - FIRST (single-token listwise decoding, EMNLP 2024): about 40% efficiency gain over sequence-generation listwise rerankers without losing effectiveness.
  - LiT5 (Dec 2023): listwise reranking "with as few as 220M parameters", competitive with 7B RankZephyr.
  - [inferred (search summary), https://arxiv.org/abs/2406.15657; https://arxiv.org/pdf/2312.16098]
- "Rethinking Hybrid Retrieval" (arXiv 2506.00049, May 2025): **MiniLM-v6 plus GPT-4o reranking beat BGE-Large plus GPT-4o** on SciFact, FIQA and NFCorpus. The reranker was a large cloud LLM [inferred (search summary), https://arxiv.org/abs/2506.00049].

### Inferences
- TinyBERT-L2-v2 buys throughput the app probably does not need (confidence: medium-high). For 20–50 candidates, MiniLM-L6 takes about 0.14–0.35 s and ettin-17m about 0.07–0.19 s on the measured desktop CPU (computed from pairs per second). ettin-17m/32m, released 2026, are the obvious small candidates: better and faster than MiniLM. bge-reranker-v2-m3 at about 6 pairs/s (roughly 3–8 s for 20–50 pairs on desktop CPU) is likely impractical without Neural Engine conversion. Phone numbers need measuring.
- **Old MS MARCO rerankers barely help modern first stages and can hurt them** (confidence: medium-high). Evidence: Ettin averages, the Qwen table, the SciFact run and "Drowning". The honest default when the neural reranker is unavailable is to keep the fused order. A hand-written heuristic reranker has **no external evidence** behind it and should be evaluated against "no rerank" on the golden set.
- The largest reranker gains in the evidence come from **domain fine-tuning** (GooAQ: +3 to +8 points over the best general models) and from **listwise LLMs**. On-device, a listwise pass through Apple's model would compete for the same 4K context and add a generation call. That is plausible for 5–10 short candidates, but unmeasured.
- A reranker's raw score is not a calibrated relevance probability ("phantom hits"), so it should not by itself decide whether a source is good enough to answer from (confidence: medium).

### Gaps
- No fetched source reports ms-marco-TinyBERT-L2-v2 on MTEB(eng,v2) or NanoBEIR, or its parameter count.
- No on-device (iPhone/Mac Neural Engine) reranker latency measurements were found.
- Per-embedder reranker results (for example, all-MiniLM-L6-v2 first stage plus each reranker) exist only as images in the Ettin post.
- License terms for jina-reranker-v2/v3 were not confirmed.

## 4. Contextual retrieval, late chunking, parent-document (small-to-big) retrieval, and query rewriting (HyDE, multi-query, step-back): what works, especially with small models?

### Takeaway
Anthropic's contextual retrieval figures are confirmed on anthropic.com. With the top 20 chunks, retrieval failure fell 35% (5.7%→3.7%) with contextual embeddings, 49% (→2.9%) adding contextual BM25, and 67% (→1.9%) adding reranking. Those are Anthropic's own measurements with cloud models, and I found no independent replication of the exact numbers. Late chunking gives small, consistent gains but needs a long-context embedder, so it does not apply to MiniLM. LLM query rewriting helps weak retrievers and hurts strong ones. It fails when the LLM lacks knowledge of the domain, which is exactly the situation for a user's private documents.

### Cited Findings
- **Anthropic, "Introducing Contextual Retrieval"** (published Sep 19, 2024) [primary, https://www.anthropic.com/engineering/contextual-retrieval; same content at /news/contextual-retrieval]:
  - "Contextual Embeddings reduced the top-20-chunk retrieval failure rate by 35% (5.7% → 3.7%)."
  - "Combining Contextual Embeddings and Contextual BM25 reduced the top-20-chunk retrieval failure rate by 49% (5.7% → 2.9%)."
  - "Reranked Contextual Embedding and Contextual BM25 reduced the top-20-chunk retrieval failure rate by 67% (5.7% → 1.9%)."
  - Metric: 1 − recall@20. The context is "usually 50-100 tokens", prepended "before embedding it and before creating the BM25 index".
  - One-time cost is "$1.02 per million document tokens", assuming 800-token chunks, 8k-token documents, 50-token instructions, 100 tokens of context and prompt caching.
  - Reranking: top 150 reranked to top 20 with the Cohere reranker. Gemini Text 004 and Voyage were the best embedders.
  - "Passing the top-20 chunks to the model is more effective than just the top-10 or top-5."
  - For knowledge bases under 200,000 tokens (about 500 pages), "you can just include the entire knowledge base in the prompt".
- Independent comparison, "Reconstructing Context: Evaluating Advanced Chunking Strategies for RAG" (arXiv 2504.19754, Apr 2025; KEIR workshop). Contextual retrieval "preserves semantic coherence more effectively but requires greater computational resources"; late chunking is more efficient "but tends to sacrifice relevance and completeness" [inferred (search summary), https://arxiv.org/abs/2504.19754].
- Vendor evidence on contextual chunk headers (document and section titles prepended before embedding): dsRAG's KITE benchmark (50 questions) improved from 4.72 to 8.42 with headers plus relevant-segment extraction. FinanceBench baseline RAG scored 19% in the paper and 32% in their run [primary, https://raw.githubusercontent.com/D-Star-AI/dsRAG/main/README.md] (vendor claims).
- **Late chunking** (Jina, arXiv 2409.04701, Sep 2024), jina-embeddings-v2-small-en, 256-token chunks, nDCG@10 naive → late (no chunking):
  - SciFact 64.20 → 66.10 (63.89)
  - TRECCOVID 63.36 → 64.70 (65.18)
  - FiQA 33.25 → 33.84 (33.43)
  - NFCorpus 23.46 → 29.98 (30.40)
  - Quora 87.19 → 87.19
  - "The average length of the documents correlates with greater improvement."
  - [primary, https://raw.githubusercontent.com/jina-ai/late-chunking/main/README.md]
- Retrieval granularity, "Dense X Retrieval" (EMNLP 2024). Proposition-level units improved Recall@5 by 35% and 22.5% for unsupervised SimCSE and Contriever, but only 2.4–4.5% for supervised retrievers [inferred (search summary), https://arxiv.org/abs/2312.06648].
- Query expansion, Weller et al. (EACL Findings 2024; 11 methods, 12 datasets, 24 retrievers): "a strong negative correlation between retriever performance and gains from expansion: expansion improves scores for weaker models, but generally harms stronger models" [inferred (search summary), https://aclanthology.org/2024.findings-eacl.134/].
- Abe et al., "LLM-based Query Expansion Fails for Unfamiliar and Ambiguous Queries" (SIGIR 2025): expansion "can significantly degrade retrieval effectiveness when knowledge in the LLM is insufficient or query ambiguity is high" [inferred (search summary), https://arxiv.org/abs/2505.12694].
- HyDE (arXiv Dec 2022, ACL 2023; pre-2023 preprint): nDCG@10 61.3 on DL-20 vs 44.5 for Contriever alone. It depends on an instruction-following LLM writing a plausible hypothetical document [inferred (search summary), https://arxiv.org/abs/2212.10496]. One summary claimed that with Gemma 1B/4B HyDE added 43–60% latency and had "a high hallucination rate on personal queries"; the source is unclear [inferred (search summary), https://www.emergentmind.com/topics/hypothetical-document-embeddings-hyde] (low confidence).
- Step-back prompting (Oct 2023): PaLM-2L +7% and +11% on MMLU Physics and Chemistry, +27% TimeQA, +7% MuSiQue, with a 540B-class model [inferred (search summary), https://arxiv.org/abs/2310.06117].
- RAG-Fusion (multi-query plus RRF; Infineon, Feb 2024): answers were more comprehensive, but "some answers strayed off topic when the generated queries' relevance to the original query is insufficient" [inferred (search summary), https://arxiv.org/abs/2402.03367].
- "Searching for Best Practices in RAG" (Wang et al., EMNLP 2024): Hybrid plus HyDE scored highest but cost **11.71 s per query**, so the authors recommend "Hybrid" or "Original" retrieval. monoT5 was the best-balanced reranker, and "reverse" repacking helped [inferred (search summary), https://arxiv.org/abs/2407.01219].
- Instruction-aware embedders gain 1–5% from a one-sentence query-side task instruction, and lose that much without it (Qwen3) [primary, https://raw.githubusercontent.com/QwenLM/Qwen3-Embedding/main/README.md].

### Inferences
- **Contextual retrieval is feasible on-device in reduced form** (confidence: medium). Anthropic's recipe assumes a model that reads the whole document (8K tokens) per chunk. A 4K on-device model cannot. The cheap, evidence-backed subset is to prepend a deterministic contextual header (title, file name, section heading, date or parties) to each chunk before both embedding and FTS5 indexing. This is dsRAG's "contextual chunk headers" and Anthropic's direction without the LLM call. LLM-written context over a sliding window of about 2–3K tokens is possible at ingestion time but untested.
- Late chunking needs the token embeddings of a long window. all-MiniLM-L6-v2 caps at 256 tokens, so late chunking is not applicable without changing the embedder (confidence: high).
- **For private documents, HyDE and LLM query expansion are likely to hurt** (confidence: medium). The on-device model has no knowledge of the user's lease or manuals, which is the Abe et al. failure condition. Upgrading the dense arm moves the system toward the "strong retriever" regime, where Weller et al. find expansion harmful. Multi-query also multiplies latency. Safer levers: query-side instructions for instruction-aware embedders, and keyword or phrase extraction for BM25.
- Small-to-big (retrieve small, expand to the parent section for generation) matches the Dense X and OP-RAG evidence (section 5). Its direct benefit was not quantified in any source I could reach.

### Gaps
- I found no independent replication of Anthropic's exact 35/49/67% figures. Replications I found are qualitative (Reconstructing Context) or vendor-run (dsRAG).
- No controlled study of parent-document or small-to-big retrieval with numbers was reachable.
- No study of HyDE or multi-query with ~3B on-device models on personal corpora was found beyond an unverified summary.

## 5. Generation under a roughly 4K-token context: how many chunks and tokens, ordering, compression, citation format, and schema-constrained extraction instead of regex

### Takeaway
More context is not monotonically better. Answer quality follows an inverted U as passages are added, and irrelevant but similar ("hard negative") passages cost 6–11 accuracy points; smaller models are more distractible. In a ~4K window that must also hold instructions and the answer, the evidence favours a few high-precision chunks placed where the model attends (start or end, most relevant nearest the question, or original document order), sentence-level pruning, and a "quote first, then answer" structure. Apple's guided generation uses constrained sampling and generates fields in declaration order. That makes a schema of {answerable, quote, source, answer} feasible and suggests declaring evidence fields before the answer.

### Cited Findings
- **Lost in the Middle** (Liu et al.; arXiv Jul 2023, TACL 2024):
  - U-shaped accuracy by position of the relevant document.
  - For GPT-3.5-Turbo with 20 documents, worst-case accuracy fell below closed-book (**56.1%**); oracle was 88.3%. Drops exceeded 20 points.
  - [inferred (search summary), https://aclanthology.org/2024.tacl-1.9.pdf]
  - The experimental setup (20 total documents, gold at positions 0, 4, 9, 14, 19) is in the repo [primary, https://raw.githubusercontent.com/nelson-liu/lost-in-the-middle/main/README.md].
- **OP-RAG**, "In Defense of RAG in the Era of Long-Context LMs" (NVIDIA, Sep 2024): keeping retrieved chunks in their **original document order** improves answers. As the number of chunks grows, quality rises then falls (inverted U), with "sweet points" using far fewer tokens [inferred (search summary), https://arxiv.org/abs/2409.01666].
- "Long-Context LLMs Meet RAG" (ICLR 2025): quality "initially improves first, but then subsequently declines" as passages increase. Hard negatives are the cause, and stronger retrievers produce more harmful ones. Training-free **retrieval reordering** (most relevant at the edges) consistently helps [inferred (search summary), https://arxiv.org/abs/2410.05983].
- "The Distracting Effect" (ACL 2025): hard distracting passages cut accuracy by **6 to 11 points** depending on the LLM, even at Llama-3.3-70B. Fine-tuning on such passages recovers up to 7.5% [inferred (search summary), https://arxiv.org/abs/2505.06914]. Search summaries also state that 3B models are more susceptible than larger ones [inferred (search summary), https://arxiv.org/html/2505.21870v1] (low confidence).
- A March 2026 preprint on ≤7B models claims oracle retrieval still left 85–100% failure to extract the answer, and that adding context overturned 42–64% of previously correct answers [inferred (search summary), https://arxiv.org/abs/2603.11513]. This is **unverified and likely conditional on a subset**; treat it as a warning, not a figure.
- Wang et al. (EMNLP 2024): "reverse" repacking, with the most relevant passage last (nearest the question), performed best [inferred (search summary), https://arxiv.org/abs/2407.01219].
- Contrast: Anthropic found top-20 better than top-10 or top-5 for Claude with a large context [primary, https://www.anthropic.com/engineering/contextual-retrieval]. This does not transfer to a 4K window.
- Apple Foundation Models `GenerationOptions`: "All input to the model contributes tokens to the context window of the [session] — including the [Instructions], [Prompt], [Tool], and [Generable] types, and the model's responses". Enforcing a strict token limit "can lead to the model producing malformed results" [primary, https://developer.apple.com/tutorials/data/documentation/foundationmodels/generationoptions.json]. The symbol names were elided in the fetched JSON, so the bracketed names are my reading. The substance, that responses count toward the window, is in the text.
- **Compression:**
  - LongLLMLingua improves "RAG performance by up to 21.4% using only 1/4 of the tokens" and mitigates lost-in-the-middle. LLMLingua reaches up to 20x compression. LLMLingua-2 (a BERT-level token classifier) is 3–6x faster than LLMLingua [primary, https://raw.githubusercontent.com/microsoft/LLMLingua/main/README.md].
  - RECOMP (ICLR 2024): its abstractive compressor used 5% of tokens at −2 EM on NQ and −3.7 EM on TriviaQA [inferred (search summary), https://arxiv.org/abs/2310.04408].
  - Provence (ICLR 2025): a DeBERTa sequence-labelling sentence pruner unified with reranking in one forward pass, with "negligible to no drop in performance" [inferred (search summary), https://arxiv.org/abs/2501.16214].
- **Citations:**
  - ALCE (EMNLP 2023): on ELI5, "even the best models lack complete citation support 50% of the time". The metrics agree with humans 85.1% (citation recall) and 77.6% (citation precision) [inferred (search summary), https://arxiv.org/abs/2305.14627].
  - Anthropic Citations: documents are chunked into sentences, and Claude cites the exact passages used. Built-in citations "outperform most custom implementations, increasing recall accuracy by up to 15%" [primary, https://www.anthropic.com/news/introducing-citations-api] (page dated June 23, 2025).
  - Anthropic's hallucination guidance: allow "I don't know"; for long documents, "extract word-for-word quotes first"; "verify each claim by finding a supporting quote after it generates a response. If it can't find a quote, it must retract the claim" [primary, https://docs.claude.com/en/docs/test-and-evaluate/strengthen-guardrails/reduce-hallucinations].
- **Schema-constrained generation:**
  - Apple guided generation "gives strong guarantees that the response is in a format you expect". It "uses constrained sampling... prevents the model from producing malformed output". "The model generates [Generable] properties in the order they're declared." Guides can constrain values (for example ranges), and schemas can be built at runtime [primary, https://developer.apple.com/tutorials/data/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation.json]. The bracketed symbol name was elided in the fetched JSON; the declared-order statement itself is verbatim.
  - "Let Me Speak Freely?" (EMNLP 2024 Industry): strict JSON mode degraded reasoning, chiefly when the "answer" key precedes the "reasoning" key. Structured formats can *improve* classification, and generating natural language then converting to the format mitigates the loss [inferred (search summary), https://arxiv.org/abs/2408.02442].
  - JSONSchemaBench (Jan 2025): constrained decoding "consistently improves the performance of downstream tasks up to 4%" and can speed generation up to 50% [inferred (search summary), https://arxiv.org/abs/2501.10868].

### Inferences
- **Token budget sketch for a ~4,096-token window** (confidence: medium; tokenizer-dependent, and the 4K figure is the brief's, not verified here). Instructions and schema take ~300–600 tokens, the question ~50, and the output reserve ~200–400. That leaves roughly **2,800–3,300 tokens of evidence**: about 5–8 chunks of 350–500 tokens, or more if pruned to sentences. The evidence argues for filling it with fewer, higher-precision passages rather than maximizing count. Put the best passage adjacent to the question, or keep same-document chunks in document order.
- **Replace regex extraction with a guided-generation schema** (confidence: medium-high). Fields, declared in this order: `answerable` (bool), `evidenceQuote` (string), `sourceIndex` (int, constrained to the provided range), `answerType` (enum), `answer` (string). Then verify deterministically that the quote is a verbatim substring of the cited chunk, and that the answer is contained in or derivable from the quote. This follows Anthropic's quote-first guidance and Apple's declared-order generation. It avoids Let Me Speak Freely's answer-before-evidence pitfall by putting evidence first.
- Sentence-level pruning (Provence or LLMLingua-2 style, or a simple per-sentence reranker cut) is the most evidence-backed way to fit more distinct sources into 4K (confidence: medium).

### Gaps
- No published study measures Apple's on-device model on multi-passage QA: position sensitivity, optimal passage count, or citation accuracy.
- The actual tokens-per-chunk ratio for Apple's tokenizer was not checked.
- No evidence found on citation formats (inline [n] vs structured fields) specifically for ~3B models.

## 6. Checking answers: NLI/fact-checkers, answer relevance, expected-answer-type gates, small LLM judges, RAGAS/RAGChecker metrics, abstention and calibration, and what a "verified" label should mean

### Takeaway
Lexical or embedding overlap between answer and sources is not a grounding test: a sentence with a wrong number overlaps its source almost perfectly. Small purpose-built checkers exist: MiniCheck-Flan-T5 at 770M matches GPT-4 on LLM-AggreFact at 400x lower cost; HHEM-2.1-Open runs in under 600MB; LettuceDetect has 150M/396M models, and TinyLettuce 17–68M variants since Aug 2025. Even these checkers disagree with each other and are biased (Godbole & Jia 2025). Production systems separate **grounding** from **relevance**: Bedrock has two thresholds, and RAGAS separates faithfulness from answer relevancy. The strongest abstention signal is whether the context is *sufficient*: +2–10 points selective accuracy. Shipped "hallucination-free" or "verified" claims have repeatedly failed audits: 17–33% hallucination in legal RAG tools; only 51.5% of sentences fully citation-supported in generative search engines.

### Cited Findings
- **Small NLI cross-encoders**, accuracy on MNLI-mismatched: nli-deberta-v3-base 90.04; nli-deberta-v3-xsmall **87.77**; nli-deberta-v3-small 87.55; nli-MiniLM2-L6-H768 86.89; nli-distilroberta-base 83.98. These are sentence-pair NLI models, not trained on RAG grounding [primary, https://raw.githubusercontent.com/UKPLab/sentence-transformers/master/docs/cross_encoder/pretrained_models.md].
- **MiniCheck** (EMNLP 2024):
  - MiniCheck-Flan-T5-Large (770M) reaches **74.7%** balanced accuracy on LLM-AggreFact, vs GPT-4 75.3% and Claude-3 Opus 74.1%.
  - It is **400x cheaper**: $0.24 vs $107 on the 13K test set [inferred (search summary), https://aclanthology.org/2024.emnlp-main.499/].
  - The README says it is "a sentence-level fact-checking model... the claim should first be broken up into sentences". LLM-AggreFact aggregates 11 datasets. Bespoke-MiniCheck-7B was reported as SOTA in Aug 2024 [primary, https://raw.githubusercontent.com/Liyan06/MiniCheck/main/README.md].
- **HHEM-2.1-Open** (Vectara): balanced accuracy RAGTruth-Summ 64.42%, RAGTruth-QA 74.28%, AggreFact-SOTA 76.55%. It runs in under 600MB RAM, takes about 1.5 s for a 2k-token input on a modern x86 CPU, and has unlimited context vs HHEM-1.0's 512 tokens [inferred (search summary), https://huggingface.co/vectara/hallucination_evaluation_model]. A GitHub issue titled "HHEM2.1-Open is poor evaluator" contests it [inferred (search summary), https://github.com/vectara/hallucination-leaderboard/issues/128]. The Vectara leaderboard itself now uses the commercial HHEM-2.3 and was last updated Sep 22, 2026 [primary, https://raw.githubusercontent.com/vectara/hallucination-leaderboard/main/README.md].
- **LettuceDetect:**
  - v1 is token-level detection on ModernBERT, 150M (base) and 396M (large), processing 30–60 examples/s on GPU. The large model's example-level F1 on RAGTruth is **79.22** vs Luna (DeBERTa-large) 65.4 [primary, https://pypi.org/pypi/lettucedetect/0.1.3/json]. GPT-4-turbo scores 63.4 F1 and fine-tuned Llama-3-8B 83.9 [inferred (search summary), https://arxiv.org/abs/2502.17125].
  - v2 (June 22, 2026) emits typed spans, including a `contradiction/numerical` category. The README example flags "The population of France is 69 million" against a context saying 67 million. Unified-test span-F1 is 0.689 (Qwen-2B) and 0.642 (mmBERT-base); the RAGTruth slice is 0.574/0.528. TinyLettuce Ettin models of 17M, 32M and 68M shipped Aug 31, 2025 [primary, https://raw.githubusercontent.com/KRLabsOrg/LettuceDetect/main/README.md].
- "Verify with Caution: The Pitfalls of Relying on Imperfect Factuality Metrics" (ACL Findings 2025): five state-of-the-art metrics across 11 datasets "disagree sharply on individual examples", misestimate system error rates, and are biased against paraphrase and against evidence drawn from far-away parts of the source [inferred (search summary), https://arxiv.org/abs/2501.14883].
- **RAGAS definitions:**
  - Faithfulness = claims supported by retrieved context ÷ total claims.
  - Answer Relevancy = mean cosine similarity between the user question and N (default 3) questions generated back from the answer; it "penalizes answers that are incomplete or include unnecessary details".
  - Context Precision = rank-weighted precision@k of relevant chunks.
  - Context Recall = reference-answer claims supported by retrieved context ÷ total.
  - Noise Sensitivity = incorrect claims ÷ total claims.
  - [primary, https://raw.githubusercontent.com/explodinggradients/ragas/main/docs/concepts/metrics/available_metrics/faithfulness.md and sibling pages answer_relevance.md, context_precision.md, context_recall.md, noise_sensitivity.md]
  - The RAGAS paper reports agreement with human annotators on WikiEval of 95% (faithfulness), 78% (answer relevance) and 70% (context relevance) [inferred (search summary), https://arxiv.org/abs/2309.15217].
- **RAGChecker** (NeurIPS 2024 Datasets & Benchmarks) uses claim-level entailment. Overall metrics are precision, recall and F1. Retriever metrics are claim recall and context precision. Generator metrics are context utilization, noise sensitivity (relevant and irrelevant), hallucination, self-knowledge and faithfulness. The only required annotation is a ground-truth answer [primary, https://raw.githubusercontent.com/amazon-science/RAGChecker/main/README.md].
- **Small LLM-as-judge:** only the largest judges reach reasonable human alignment (Scott's Pi ≈ 0.88). Fine-tuned judges overfit in-domain. "Kappa deflation": raw agreement overstates chance-corrected agreement by 33–40% (a 2026 evaluation of 21 models and 541K judgments) [inferred (search summary), https://arxiv.org/abs/2606.19544; https://arxiv.org/html/2506.13639v1].
- **Sufficient context** (Joren et al., ICLR 2025): sufficiency means "could a diligent reader answer using only the provided context?". An autorater reaches 93% accuracy. Combining the sufficiency signal with confidence "lift[s] selective accuracy by 2–10 percentage points at the same coverage" [primary, https://raw.githubusercontent.com/hljoren/sufficientcontext/main/README.md].
- Trust-Align / Trust-Score (ICLR 2025) measures grounded refusals, answer correctness, citation support and citation relevance. Prompting and in-context learning fail to adapt LLMs well; alignment improved 26 of 27 models [inferred (search summary), https://arxiv.org/abs/2409.11242]. "Know Your Limits" (TACL 2025) surveys abstention methods and benchmarks [inferred (search summary), https://aclanthology.org/2025.tacl-1.26/]. Conformal factuality (ICML 2024) guarantees correctness with high probability by backing off to less specific outputs, calibrated on few labeled samples [inferred (search summary), https://arxiv.org/abs/2402.10978].
- **Expected answer type** (Li & Roth 2002, pre-2023): a 6-coarse / 50-fine answer-type taxonomy, including NUM subtypes, used to constrain and verify candidate answers in classic QA [inferred (search summary), https://www.semanticscholar.org/paper/Learning-Question-Classifiers-Li-Roth/2c8ac3e1f0edeed1fbd76813e61efdc384c319c7]. Quantity extraction: CQE (EMNLP 2023) beat the regex-based Quantulum3 and Recognizers-Text, reaching F1 92.0 for value detection and 85.6 for value+unit [inferred (search summary), https://aclanthology.org/2023.emnlp-main.793/].
- **How products define "grounded" or "verified":**
  - Amazon Bedrock Guardrails contextual grounding computes a **grounding** score and a separate **relevance** score. Responses under either threshold (for example 0.7) are blocked [inferred (search summary), https://docs.aws.amazon.com/bedrock/latest/userguide/guardrails-contextual-grounding-check.html].
  - Gemini's "double-check" highlights statements green where Google Search found similar content and orange where it found different content or none; no highlight means not evaluated or non-factual [inferred (search summary), https://support.google.com/gemini/answer/14143489].
  - Anthropic Citations returns cited spans per claim [primary, https://www.anthropic.com/news/introducing-citations-api].
- **Audits of verification claims:**
  - Magesh et al. (Journal of Empirical Legal Studies, 2025; preregistered). Despite "hallucination-free" marketing, Lexis+ AI answered 65% accurately and hallucinated about 17%; Westlaw AI-Assisted Research answered 42% accurately and hallucinated about 33% [inferred (search summary), https://onlinelibrary.wiley.com/doi/full/10.1111/jels.12413].
  - Liu, Zhang & Liang (EMNLP Findings 2023): across Bing Chat, NeevaAI, perplexity.ai and YouChat, only **51.5%** of generated sentences were fully supported by citations, and only **74.5%** of citations supported their sentence [inferred (search summary), https://arxiv.org/abs/2304.09848].

### Inferences
- **Overlap-based "verification gates" measure similarity, not entailment** (confidence: high). They pass exactly the dangerous cases: a correct-looking sentence with a wrong number, unit, party or negation. LettuceDetect's 69-vs-67-million example shows a trained detector catching what overlap cannot. A small entailment checker applied per answer sentence against the cited span is the evidence-backed replacement. Candidates: nli-deberta-v3-xsmall; MiniCheck-style claim checking; TinyLettuce 17–68M; HHEM-2.1-Open where memory allows. Calibrate its threshold on the app's golden set, since checkers disagree (Godbole & Jia).
- **Use at least three independent gates, as Bedrock and RAGAS do** (confidence: medium-high):
  1. **Grounding**: each answer sentence is entailed by a cited span.
  2. **Relevance and answer type**: the answer addresses the question, and its type matches the expected type (duration, money, date, quantity with a unit dimension).
  3. **Sufficiency**: the retrieved context could answer at all; otherwise abstain.

  The "1 lb" answer to a lease-notice question fails gate 2 twice: weight is not a duration, and the source is an air-fryer manual, not a lease. A cheap question-type classifier plus unit-dimension check would have blocked it regardless of grounding scores.
- **What "verified" should mean** (confidence: medium). A defined, measured procedure is required: every factual sentence is entailed by a quoted span (checker score ≥ a threshold calibrated to a stated false-accept rate on a golden set); the quoted span comes from a retrieved source judged relevant to the question; and the answer type matches the question. The label should expose the evidence (quote and source), not just a badge. Gemini's graded highlights are a precedent. Given the legal-tools audit, a binary "verified" badge without a published residual error rate is the pattern that has failed in production. Small LLM judges are the weakest option for this role.

### Gaps
- No modern (2023+) study quantifies expected-answer-type gating inside LLM RAG pipelines. The support is classic QA (2002) plus reasoning from quantity-extraction work.
- No on-device latency or memory figures were found for MiniCheck, TinyLettuce or HHEM on iPhone-class hardware.
- CQE's baseline F1 values for the regex tools were not in the summary.
- The TRUE benchmark (2022) comparison of overlap metrics vs NLI was not retrieved with numbers.

## 7. Extractive versus generative answers: when span extraction helps, and documented failure modes of pattern- or regex-based extraction

### Takeaway
Extraction is faithful to the characters, not to the question. Extractive readers only work well when paired with an explicit "no answer" decision: SQuAD 2.0 showed an 86→66 F1 drop once unanswerable questions were added. 30% of extractive summaries are misleading despite being verbatim. Regex and rule-based quantity extractors lose to parsers with unit models. Neural retrievers treat numbers as tokens. The evidence supports span extraction *as evidence for* a generated answer (quote plus citation, then verification), not regex output *overriding* the model.

### Cited Findings
- SQuAD 2.0 (Rajpurkar, Jia & Liang, ACL 2018, pre-2023): added over 50,000 adversarial unanswerable questions. "A strong neural system that gets 86% F1 on SQuAD 1.1 achieves only 66% F1 on SQuAD 2.0". Systems must "determine when no answer is supported by the paragraph and abstain" [inferred (search summary), https://arxiv.org/abs/1806.03822].
- "Extractive is not Faithful" (Zhang, Wan & Bansal, ACL 2023): over 1,600 summaries from 16 extractive systems, **30%** had at least one of five unfaithfulness problems (incorrect or incomplete coreference, incorrect or incomplete discourse, misleading information), and five existing faithfulness metrics correlated poorly with humans [inferred (search summary), https://aclanthology.org/2023.acl-long.120/].
- CQE (EMNLP 2023): Recognizers-Text "uses regular expressions"; Quantulum3 "uses regular expression[s]... and a dictionary of units". Both were outperformed by a dependency-parse-plus-unit-dictionary extractor (CQE F1 92.0 value, 85.6 value+unit) [inferred (search summary), https://aclanthology.org/2023.emnlp-main.793/].
- "Numbers Matter!" (EMNLP Findings 2024): search engines "apply the same ranking mechanisms for both words and quantities, overlooking magnitude and unit information". Queries with numeric conditions need quantity-aware ranking [inferred (search summary), https://arxiv.org/abs/2407.10283].
- LettuceDetect v2 distinguishes numerical contradictions as a category of RAG hallucination [primary, https://raw.githubusercontent.com/KRLabsOrg/LettuceDetect/main/README.md].
- RECOMP's extractive compressor selects sentences as evidence, rather than answers, for the generator: extraction as context selection [inferred (search summary), https://arxiv.org/abs/2310.04408].
- Apple guided generation can constrain a field's values ("guides") and deliver typed results, which enables typed span extraction without regex [primary, https://developer.apple.com/tutorials/data/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation.json].

### Inferences
- A regex/pattern shortcut that **replaces** the model's answer when a heuristic score passes a threshold is effectively an extractive reader with no answerability decision, no answer-type constraint and no relevance check (confidence: high, given the brief's description). These are the three safeguards the SQuAD 2.0, Li & Roth and Bedrock evidence treats as essential. The "1 lb" case matches the documented failure modes: a type and unit mismatch, and a context mismatch with a verbatim span taken from an irrelevant document.
- The evidence-aligned design is generate-then-verify (confidence: medium-high). Guided generation yields {answerable, quote, source, typed answer}. Deterministic code checks that the quote is verbatim in the cited chunk, the typed value parses from the quote, the unit dimension matches the question type, and the source passed the relevance gate. A pattern matcher should, at most, *propose* candidate spans or normalize values; it should never overwrite the answer.

### Gaps
- No study was found that directly compares regex-override extraction with LLM answers inside a RAG pipeline. The failure analysis above is an inference from adjacent evidence (SQuAD 2.0, extractive faithfulness, quantity extraction).

## 8. Evaluating RAG on small personal corpora: golden sets, per-stage metrics, determinism, and regression suites

### Takeaway
Use a small golden set with per-stage labels, and analyse it statistically. Retrieval metrics are recall@k, nDCG@10 and MRR, plus RAGChecker/RAGAS-style claim recall and context precision. Generation metrics are faithfulness, answer correctness and abstention. Cluster standard errors by source document and compare configurations with paired differences, because personal corpora have many questions per document. Tens of labeled queries are enough to tune fusion weights. A few hundred human labels are enough to calibrate automatic judges (ARES/PPI). Determinism is not guaranteed by temperature 0 on batched servers. Pin model and dataset revisions, as MTEB results do; that is what let me reproduce 41.95 exactly.

### Cited Findings
- Anthropic, "A statistical approach to model evaluations" (Nov 19, 2024) [primary, https://www.anthropic.com/research/statistical-approach-to-model-evals]. Five recommendations:
  1. Report the standard error of the mean (Central Limit Theorem).
  2. Cluster standard errors when questions are grouped, for example several questions on one passage.
  3. Reduce within-question variance.
  4. Analyse paired differences between models on the same questions.
  5. Use power analysis to decide whether an eval with few questions can detect the difference of interest.
- Paired bootstrap in practice: the SciFact hybrid benchmark reports per-mode 95% CIs over 10,000 resamples, notes that "the per-mode intervals overlap heavily", and decides on paired differences with win/loss/tie counts [primary, https://raw.githubusercontent.com/regankight/es-hybrid-retrieval-benchmark/main/README.md].
- ARES (NAACL 2024) fine-tunes lightweight judges for context relevance, answer faithfulness and answer relevance. It uses prediction-powered inference with "only a few hundred human annotations" and remains accurate across domain shifts [inferred (search summary), https://aclanthology.org/2024.naacl-long.20/].
- eRAG (SIGIR 2024) labels each retrieved document by the downstream answer quality it produces alone. This correlates better with end-to-end RAG quality than query-document relevance labels (Kendall's τ +0.168 to +0.494) and uses up to 50x less GPU memory than end-to-end evaluation [inferred (search summary), https://arxiv.org/abs/2404.13781].
- Per-stage metric definitions (RAGAS: context precision/recall, faithfulness, answer relevancy, noise sensitivity; RAGChecker: claim recall, context utilization, hallucination, self-knowledge) are in section 6 [primary, RAGAS docs and RAGChecker README URLs above].
- Lightweight retrieval benchmarks: Sentence Transformers ships NanoBEIR evaluators for both embedders and rerankers, used as quick, low-cost checks during development. Its reranker-training post notes that CrossEncoder models "overfit rather quickly", so an evaluator should be used during training [primary, https://raw.githubusercontent.com/huggingface/blog/main/train-reranker.md; https://raw.githubusercontent.com/huggingface/blog/main/static-embeddings.md].
- Fusion-weight sample size: about 40 annotated queries sufficed for a tuned linear combination to beat RRF, and 300 gave +6% nDCG@10 (Elastic) [inferred (search summary), https://www.elastic.co/search-labs/blog/improving-information-retrieval-elastic-stack-hybrid].
- Determinism: Thinking Machines Lab (Sep 2025) ran the same prompt 1,000 times at temperature 0 and got **80 unique completions**. The main cause is batch-size-dependent ("batch-invariance"-violating) kernels. Batch-invariant kernels made all 1,000 identical [inferred (search summary), https://thinkingmachines.ai/blog/defeating-nondeterminism-in-llm-inference/].
- Reproducibility through pinned revisions: MTEB result files are keyed by model revision hash and record `mteb_version` (for example 1.18.0 for the MiniLM run). Split choice alone moves MiniLM's BEIR-15 average from 41.95 to 43.76 (MSMARCO dev vs test) [primary, https://raw.githubusercontent.com/embeddings-benchmark/results/main/results/sentence-transformers__all-MiniLM-L6-v2/8b3219a92973c328a8e22fadcfa821b5dc75636a/MSMARCO.json].
- Checker validity: automated factuality metrics must be validated in-domain before being trusted (Godbole & Jia 2025) [inferred (search summary), https://arxiv.org/abs/2501.14883]. RAGAS's own agreement with humans ranges from 70% to 95% by metric [inferred (search summary), https://arxiv.org/abs/2309.15217].

### Inferences
- **Minimum viable golden set for this app** (confidence: medium):
  - Size: about 50–150 questions over a fixed fixture corpus of mixed personal documents (leases, manuals, receipts, notes).
  - Each question labelled with the gold chunk IDs, the expected answer type, the gold answer, and whether it is answerable. Deliberately unanswerable and cross-document "trap" questions are needed, such as a lease question when only an air-fryer manual mentions a number.
  - Report recall@k and nDCG@10 per retrieval arm, for the fusion and for the reranker; answer correctness; faithfulness; abstention precision and recall; and the false-"verified" rate.
  - Use paired comparisons with standard errors clustered by document.
  - 40+ labelled queries also allow fusion-weight tuning.
- **Determinism for regression suites** (confidence: medium). Single-stream on-device inference avoids the server batch-variance cause. However, OS updates can change Apple's model, so snapshot the retrieval stages (fully deterministic given pinned models and index) separately from generation. Assert on generation with tolerance-based checks (answer-type, entailment, citation-substring) rather than exact strings. Greedy sampling options in Apple's `GenerationOptions` were not verified in this pass.

### Gaps
- No published guidance was found on golden-set sizes specifically for single-user personal corpora; the numbers above are extrapolated from Elastic, ARES and Anthropic.
- Apple's sampling-mode documentation (greedy vs random) and whether on-device outputs are bitwise reproducible across runs and OS versions were not confirmed; the doc paths for SamplingMode could not be fetched.
- No public benchmark of RAG on personal-document corpora (mixed manuals, contracts, receipts) was found.
