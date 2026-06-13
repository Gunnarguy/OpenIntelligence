> **Documentation status:** Historical reference. This document may describe earlier implementation plans or deprecated architecture. Do not use as the source of truth for OpenIntelligence v4.1.

# RAG and Retrieval Research 2024-2026

**Updated**: April 24, 2026
**Use in this repo**: Supports the current hybrid retrieval, hierarchical summary, corrective retrieval, reranking, and verification design.

## Primary Sources

| Area                           | Source                                                                                                                 | Why It Matters for OpenIntelligence                                                                                                 |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| RAPTOR                         | [RAPTOR: Recursive Abstractive Processing for Tree-Organized Retrieval](https://arxiv.org/abs/2401.18059)              | Supports the repo's RAPTOR-lite summary chunks and overview-query routing.                                                          |
| GraphRAG                       | [From Local to Global: A Graph RAG Approach to Query-Focused Summarization](https://arxiv.org/abs/2404.16130)          | Useful for global corpus questions, but full LLM-derived entity/community graphing is heavier than this app should claim today.     |
| LightRAG                       | [LightRAG: Simple and Fast Retrieval-Augmented Generation](https://arxiv.org/abs/2410.05779)                           | Reinforces graph/vector hybrid indexing and incremental updates as a future direction.                                              |
| Corrective RAG                 | [Corrective Retrieval Augmented Generation](https://arxiv.org/abs/2401.15884)                                          | Supports retrieval quality checks, corrective retrieval, and selective refinement before generation.                                |
| RAG evaluation                 | [RAGChecker: A Fine-grained Framework for Diagnosing Retrieval-Augmented Generation](https://arxiv.org/abs/2408.08067) | Supports measuring retrieval and generation separately rather than relying on demos.                                                |
| RAG best practices             | [Searching for Best Practices in Retrieval-Augmented Generation](https://arxiv.org/abs/2407.01219)                     | Good diligence link for chunking, retrieval, reranking, and latency tradeoffs.                                                      |
| Self-reflective RAG            | [Self-RAG: Learning to Retrieve, Generate, and Critique through Self-Reflection](https://arxiv.org/abs/2310.11511)     | Older but still relevant for adaptive retrieval and critique/verification behavior.                                                 |
| Contextual retrieval           | [Anthropic: Contextual Retrieval](https://www.anthropic.com/research/contextual-retrieval)                             | Directly maps to this repo's contextual prefixes, BM25 + embeddings, and reranking/compression stack.                               |
| Agentic RAG                    | [Agentic Retrieval-Augmented Generation: A Survey on Agentic RAG](https://arxiv.org/abs/2501.09136)                    | Supports the repo's multi-step/agentic modes, while highlighting evaluation, coordination, memory, efficiency, and governance gaps. |
| Faithfulness/conflict modeling | [FaithfulRAG: Fact-Level Conflict Modeling for Context-Faithful RAG](https://arxiv.org/abs/2506.08938)                 | Supports source-only verification, contradiction checks, and conflict-aware answer policies.                                        |
| Heterogeneous docs/tables      | [TableRAG: A RAG Framework for Heterogeneous Document Reasoning](https://arxiv.org/abs/2506.10380)                     | Relevant to manuals, spec sheets, tables, and exact-value failures where flattening loses structure.                                |
| Context engineering            | [A Survey of Context Engineering for Large Language Models](https://arxiv.org/abs/2507.13334)                          | Useful framing for retrieval, compression, memory, tool schemas, and prompt budget management.                                      |

## PDF Links

- RAPTOR: https://arxiv.org/pdf/2401.18059
- GraphRAG: https://arxiv.org/pdf/2404.16130
- LightRAG: https://arxiv.org/pdf/2410.05779
- Corrective RAG: https://arxiv.org/pdf/2401.15884
- RAGChecker: https://arxiv.org/pdf/2408.08067
- Searching for Best Practices in RAG: https://arxiv.org/pdf/2407.01219
- Self-RAG: https://arxiv.org/pdf/2310.11511
- Agentic RAG Survey: https://arxiv.org/pdf/2501.09136
- FaithfulRAG: https://arxiv.org/pdf/2506.08938
- TableRAG: https://arxiv.org/pdf/2506.10380
- Context Engineering Survey: https://arxiv.org/pdf/2507.13334

## Current Implementation Fit

OpenIntelligence already implements the high-value RAG pattern for a small on-device model:

- Hybrid retrieval: vector + BM25/FTS5 + reciprocal rank fusion.
- Contextual chunking: document and section context is added before embedding and storage.
- Hierarchical summaries: document summary chunks act as RAPTOR-lite L1 nodes.
- Query routing: lookup, procedure, compare, summarize, and broad overview intents change the retrieval path.
- Corrective retrieval: low-confidence and exact-value cases can trigger stricter retrieval or extractive fallback.
- Reranking/diversity: MMR and source diversity reduce redundant chunks.
- Verification: gates A-I check evidence support after generation.

## What Not To Overclaim

- Do not call the current engine "full GraphRAG" unless entity graph extraction, entity resolution, community detection, and community summary retrieval are implemented and evaluated.
- Do not imply retrieval alone prevents hallucinations. RAG papers consistently treat retrieval quality, generation grounding, and evaluation as separate concerns.
- Do not market "Maximum" or multi-session reasoning as infinite truth. It is a repeated/evaluated pipeline over limited context windows.

## Best Next Additions

1. Add a small persistent eval set for each target document class: policy docs, technical manuals, product specs, and regulatory-style reference documents.
2. Record retrieval recall, exact numeric accuracy, abstention rate, and citation faithfulness.
3. Add a graph-lite artifact that is deterministic: entities, aliases, section references, and source spans before attempting LLM-generated knowledge graphs.
4. Keep exact-value lookups extractive-first.
