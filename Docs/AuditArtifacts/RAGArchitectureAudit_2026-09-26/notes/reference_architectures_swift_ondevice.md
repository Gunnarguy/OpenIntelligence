# Reference RAG architectures: open-source systems, commercial products, and Apple-platform on-device implementations (as of 2026-09-26)

How to read the tags: **[primary]** means I read it in a fetched primary source: GitHub source or README files on the default branch, fetched 2026-09-26; Apple DocC JSON and WWDC video transcripts on developer.apple.com; PyPI JSON; or GitHub API repository metadata. **[secondary]** means a fetched blog or guide. **[inferred (search summary)]** means I know it only from a WebSearch result summary. The network proxy blocked fetches from several hosts: docs.cloud.google.com, docs.aws.amazon.com, learn.microsoft.com, docs.glean.com, support.google.com, perplexity.ai, cjr.org, niemanlab.org, blog.google, dify.ai, arXiv, Hugging Face and api.github.com release endpoints. Claims from those hosts carry the "inferred" tag unless a GitHub mirror of the same doc was readable. Star counts and last-push dates come from the GitHub search API (via MCP) on 2026-09-26. Release versions and dates come from PyPI JSON. The "App:" remarks in the Inferences sections compare against the app facts the caller supplied. Those facts were not re-verified here.

## 1. Open-source RAG systems (2025–2026): parser, chunking, embedder, hybrid search and reranker, citations, verification, evaluation, and the defaults they converged on

### Takeaway
The open-source systems now share one skeleton:
- **Parsing:** layout-aware, and often swappable between DeepDoc, Docling, MinerU, OCR and vision models.
- **Chunking:** fixed-size or recursive chunks of about 200 words to 1,024 tokens, usually with little or no overlap.
- **Embedding:** a pluggable embedder. all-MiniLM-L6-v2 is still the shipped default in txtai, Open WebUI and AnythingLLM; quality-oriented systems default to nomic, gte, bge or OpenAI models.
- **Retrieval:** hybrid BM25 plus vector search is available almost everywhere, but is on by default in only some systems. It is fused either by RRF or by weighted sums.
- **Reranking:** a cross-encoder reranker that is optional and often off by default.
- **Citations:** numbered [n] citations, which the model emits because the prompt tells it to, or which similarity matching attaches afterwards.

Checking the answer against its sources at runtime is rare in open source. Where it exists, it takes the form of LLM relevance scores or warnings (Kotaemon). Entailment checking otherwise lives in evaluation tooling (the LlamaIndex and Haystack faithfulness judges), not in the answer path.

### Cited Findings

#### RAGFlow (infiniflow/ragflow): 91,310★, Apache-2.0, last push 2026-09-26; README pins v0.27.2; ragflow-sdk 0.27.2 on PyPI (2026-09-10)
- The README lists these features: "Deep document understanding-based knowledge extraction", "Template-based chunking", "Grounded citations with reduced hallucinations" (text-chunking visualisation for human intervention, plus "traceable citations"), and "Multiple recall paired with fused re-ranking" — [primary, RAGFlow README](https://github.com/infiniflow/ragflow/blob/main/README.md)
- Recent README news items:
  - 2025-08-01: agentic workflow and MCP.
  - 2025-10-15: "orchestrable ingestion pipeline".
  - 2025-10-23: "Supports MinerU & Docling as document parsing methods".
  - 2025-12-26: "Memory" for agents.
  - 2026-06-15: multiple chat channels.

  Source: [primary, RAGFlow README](https://github.com/infiniflow/ragflow/blob/main/README.md)
- **Parser.** The default `layout_recognize` is `"DeepDOC"`. The naive ("General") chunker dispatches PDFs to DeepDOC, MinerU, Docling, a plain-text parser or a vision parser (VisionParser/TCADP), and can call a vision LLM to enrich figure chunks — [primary, rag/app/naive.py](https://github.com/infiniflow/ragflow/blob/main/rag/app/naive.py), [primary, api/utils/api_utils.py L356-393](https://github.com/infiniflow/ragflow/blob/main/api/utils/api_utils.py)
- **Chunking defaults.** The naive method uses `chunk_token_num: 512`, `delimiter: "\n"`, `auto_keywords: 0`, `auto_questions: 0` and `parent_child.use_parent_child: False`. The knowledge-graph method uses `chunk_token_num: 8192`, and RAPTOR and GraphRAG are optional fields — [primary, api_utils.py](https://github.com/infiniflow/ragflow/blob/main/api/utils/api_utils.py)
- **Embedder.** The Docker template hard-codes no embedding model; it points `embedding_model` at a TEI host. A commented example names `bge-m3` as the embedder and `bge-reranker-v2` as the reranker. The README says images have shipped without bundled embedding models since v0.22.0 — [primary, docker/service_conf.yaml.template](https://github.com/infiniflow/ragflow/blob/main/docker/service_conf.yaml.template), [primary, README](https://github.com/infiniflow/ragflow/blob/main/README.md)
- **Hybrid retrieval.** Full-text and vector recall are fused with weights "term, vector" = `1 - vector_similarity_weight`, `vector_similarity_weight`. The default `vector_similarity_weight` is 0.3, so term matching gets 0.7 and vectors get 0.3. `retrieval()` defaults are `similarity_threshold=0.2`, `rerank_candidates_count=64` and `knn_top_k=1024`. Final ranking adds a PageRank "rank feature" term — [primary, rag/nlp/search.py L37-43, L708-760](https://github.com/infiniflow/ragflow/blob/main/rag/nlp/search.py)
- **Dialog defaults.** These are `similarity_threshold 0.2`, `vector_similarity_weight 0.3`, `top_n 6`, `top_k 1024`, an empty `rerank_id` (no rerank model by default) and `do_refer "1"`, which means "insert reference index into answer" is on — [primary, api/db/db_models.py L1476-1491](https://github.com/infiniflow/ragflow/blob/main/api/db/db_models.py)
- **Citations.** When quoting is enabled (the default) and the model's answer contains no citation markers, RAGFlow calls `insert_citations()`. That function:
  - splits the answer into sentences;
  - embeds each sentence;
  - scores each sentence against the retrieved chunks with a token/vector hybrid similarity;
  - attaches up to 4 chunk IDs per sentence whose similarity exceeds a threshold that starts at 0.63 and decays by ×0.8 down to 0.3.

  If no sentence clears the threshold, no citation is added. The citation is therefore a similarity match, not an entailment check — [primary, api/db/services/dialog_service.py ~L865-872](https://github.com/infiniflow/ragflow/blob/main/api/db/services/dialog_service.py), [primary, rag/nlp/search.py L422-495](https://github.com/infiniflow/ragflow/blob/main/rag/nlp/search.py)
- **Not-found behaviour.** The default system prompt requires the exact sentence "The answer you are looking for is not found in the knowledge base!" when information is unavailable, and the default `empty_response` is "Sorry! No relevant content was found in the knowledge base!" — [primary, admin/client/ragflow_client.py L1160](https://github.com/infiniflow/ragflow/blob/main/admin/client/ragflow_client.py), [primary, db_models.py L1476](https://github.com/infiniflow/ragflow/blob/main/api/db/db_models.py)

#### LlamaIndex (run-llama/llama_index): 52,321★, MIT; llama-index-core 0.14.25 (PyPI, 2026-09-21)
- The 2026 README says the company's "primary focus has shifted towards LlamaParse, along with liteparse" (a free parser) and ParseBench. The open-source framework "is still available as an open toolkit" — [primary, README](https://github.com/run-llama/llama_index/blob/main/README.md), [primary, PyPI](https://pypi.org/project/llama-index-core/)
- **Constants.**

  | Constant | Value |
  |---|---|
  | `DEFAULT_CHUNK_SIZE` | 1024 tokens |
  | `DEFAULT_CHUNK_OVERLAP` | 20 tokens |
  | `DEFAULT_SIMILARITY_TOP_K` | 2 |
  | `DEFAULT_CONTEXT_WINDOW` | 3900 tokens |
  | `DEFAULT_EMBEDDING_DIM` | 1536 ("for text-embedding-ada-002") |

  Source: [primary, core/constants.py](https://github.com/run-llama/llama_index/blob/main/llama-index-core/llama_index/core/constants.py)
- **SentenceSplitter.** It defaults to `chunk_size=1024` and `chunk_overlap=200` (`SENTENCE_CHUNK_OVERLAP`) — [primary, node_parser/text/sentence.py](https://github.com/run-llama/llama_index/blob/main/llama-index-core/llama_index/core/node_parser/text/sentence.py)
- **Embedder.** `embed_model="default"` resolves to `OpenAIEmbedding()`, whose default model is `text-embedding-ada-002`. The string `"local:<name>"` loads a HuggingFace model instead — [primary, core/embeddings/utils.py](https://github.com/run-llama/llama_index/blob/main/llama-index-core/llama_index/core/embeddings/utils.py), [primary, embeddings-openai base.py L279-280](https://github.com/run-llama/llama_index/blob/main/llama-index-integrations/embeddings/llama-index-embeddings-openai/llama_index/embeddings/openai/base.py)
- **Fusion.** `QueryFusionRetriever` modes are `reciprocal_rerank` (RRF with `k = 60.0`), `relative_score`, `dist_based_score` and `simple`, which is the default. `num_queries=4` generates query variants — [primary, retrievers/fusion_retriever.py](https://github.com/run-llama/llama_index/blob/main/llama-index-core/llama_index/core/retrievers/fusion_retriever.py)
- **Citations.** `CitationQueryEngine` re-splits retrieved nodes into citation chunks (`DEFAULT_CITATION_CHUNK_SIZE = 512`, overlap 20), labels them "Source N", and prompts: "Please provide an answer based solely on the provided sources… Every answer should include at least one source citation. Only cite a source when you are explicitly referencing it. If none of the sources are helpful, you should indicate that." — [primary, query_engine/citation_query_engine.py](https://github.com/run-llama/llama_index/blob/main/llama-index-core/llama_index/core/query_engine/citation_query_engine.py)
- **Evaluation.** `FaithfulnessEvaluator` is an LLM YES/NO judge: "Answer YES if **any part** of the context supports the information, even if most of the context is unrelated" — [primary, evaluation/faithfulness.py](https://github.com/run-llama/llama_index/blob/main/llama-index-core/llama_index/core/evaluation/faithfulness.py)

#### Haystack (deepset-ai/haystack): 26,605★, Apache-2.0; haystack-ai **3.2.0** on PyPI (2026-09-24)
Note that the brief says "Haystack 2.x"; the current major version is 3.
- Source: [primary, PyPI](https://pypi.org/project/haystack-ai/)
- **Chunking.** `DocumentSplitter` defaults to `split_by="word"`, `split_length=200`, `split_overlap=0` and `respect_sentence_boundary=False`. `RecursiveDocumentSplitter` defaults to 200 words with overlap 0 — [primary, preprocessors/document_splitter.py](https://github.com/deepset-ai/haystack/blob/main/haystack/components/preprocessors/document_splitter.py), [primary, recursive_splitter.py](https://github.com/deepset-ai/haystack/blob/main/haystack/components/preprocessors/recursive_splitter.py)
- **Embedder and reranker.** The Sentence Transformers components now live in `haystack-core-integrations`:
  - `SentenceTransformersDocumentEmbedder` defaults to `sentence-transformers/all-mpnet-base-v2`.
  - `SentenceTransformersSimilarityRanker` defaults to `cross-encoder/ms-marco-MiniLM-L-6-v2` with `top_k=10`.

  Sources: [primary, ST document embedder](https://github.com/deepset-ai/haystack-core-integrations/blob/main/integrations/sentence_transformers/src/haystack_integrations/components/embedders/sentence_transformers/sentence_transformers_document_embedder.py), [primary, ST similarity ranker](https://github.com/deepset-ai/haystack-core-integrations/blob/main/integrations/sentence_transformers/src/haystack_integrations/components/rankers/sentence_transformers/sentence_transformers_similarity.py)
- **Hybrid.** `InMemoryBM25Retriever` uses `top_k=10`. `DocumentJoiner` join modes are `concatenate` (the default), `merge`, `reciprocal_rank_fusion` and `distribution_based_rank_fusion` — [primary, bm25_retriever.py](https://github.com/deepset-ai/haystack/blob/main/haystack/components/retrievers/in_memory/bm25_retriever.py), [primary, joiners/document_joiner.py](https://github.com/deepset-ai/haystack/blob/main/haystack/components/joiners/document_joiner.py)
- **Citations.** `AnswerBuilder(reference_pattern="\\[(\\d+)\\]")` parses [n] references the model emits (1-based document indices). It can return only the referenced documents — [primary, builders/answer_builder.py](https://github.com/deepset-ai/haystack/blob/main/haystack/components/builders/answer_builder.py)
- **Evaluation.** In `FaithfulnessEvaluator`, "An LLM separates the answer into multiple statements and checks whether the statement can be inferred from the context". The score is the proportion of inferable statements, from 0 to 1 — [primary, evaluators/faithfulness.py](https://github.com/deepset-ai/haystack/blob/main/haystack/components/evaluators/faithfulness.py)
- **Agents.** The README covers Agents with lifecycle hooks, an "advanced RAG agent" in Agent Pack, and Hayhooks for serving pipelines as REST or MCP — [primary, README](https://github.com/deepset-ai/haystack/blob/main/README.md)

#### txtai (neuml/txtai): 12,983★, Apache-2.0; txtai 9.13.0 (PyPI, 2026-08-27)
- The README describes the "embeddings database" as "a union of vector indexes (sparse and dense), graph networks and relational databases". Its model guide recommends `all-MiniLM-L6-v2` for embeddings and "Gemma 4 31B" as the LLM — [primary, README](https://github.com/neuml/txtai/blob/master/README.md)
- **Embedder.** If no model is configured, `defaults()` sets `path = "sentence-transformers/all-MiniLM-L6-v2"`. The `hybrid` option adds a BM25 scoring index alongside the dense one. The `sparse` option uses `opensearch-neural-sparse-encoding-doc-v2-mini` — [primary, embeddings/base.py L835-880](https://github.com/neuml/txtai/blob/master/src/python/txtai/embeddings/base.py)
- **RAG pipeline.** It includes the top 3 context matches by default (`context`), with `minscore 0.0` and the template `"{question} {context}"`. With `output="reference"`, each answer gets the single best-matching context ID: the pipeline scores (query keyword terms + answer text) against the top-n contexts with the similarity model. That is similarity attribution, not verification — [primary, pipeline/llm/rag.py](https://github.com/neuml/txtai/blob/master/src/python/txtai/pipeline/llm/rag.py)
- **Extractive QA.** The RAG `task` can be `question-answering` (an extractive QA model). The README favours "smaller, more specialized models", including extractive QA — [primary, rag.py docstring](https://github.com/neuml/txtai/blob/master/src/python/txtai/pipeline/llm/rag.py), [primary, README](https://github.com/neuml/txtai/blob/master/README.md)

#### R2R (SciPhi-AI/R2R): 8,006★, MIT; last push 2025-11-07; r2r 3.6.6 on PyPI (2025-08-17). Activity appears to have slowed.
- The README describes "Agentic RAG", "Hybrid Search: Semantic + keyword search with reciprocal rank fusion", knowledge graphs, "RAG with citations" and a "Deep Research API" — [primary, py/README.md](https://github.com/SciPhi-AI/R2R/blob/main/py/README.md)
- **Default config.**
  - Chunking: `chunking_strategy = "recursive"`, `chunk_size = 1_024`, `chunk_overlap = 512` (the unit is not stated).
  - Embedding: `openai/text-embedding-3-small` with `base_dimension = 512`. The reranker line `mxbai-rerank-large-v1` is commented out.
  - PDF parsers: `["zerox","ocr"]`, with OCR provider `mistral-ocr-latest`.
  - Chunk enrichment is off by default.
  - Agent tools: `search_file_descriptions`, `search_file_knowledge` and `get_file_content`.

  Source: [primary, py/r2r/r2r.toml](https://github.com/SciPhi-AI/R2R/blob/main/py/r2r/r2r.toml)
- **Hybrid settings.** `HybridSearchSettings` defaults are `full_text_weight 1.0`, `semantic_weight 5.0`, `full_text_limit 200` and `rrf_k 50`. The chunk search `limit` defaults to 10. Search strategies are `vanilla`, `query_fusion` and `hyde`. The "basic" preset is semantic-only; the "advanced" preset turns on hybrid search — [primary, py/shared/abstractions/search.py L392-592](https://github.com/SciPhi-AI/R2R/blob/main/py/shared/abstractions/search.py)

#### Kotaemon (Cinnamon/kotaemon): 25,775★, Apache-2.0, last push 2026-07-14
- The README lists:
  - "Hybrid RAG pipeline… hybrid (full-text & vector) retriever and re-ranking".
  - "Advanced citations with document preview… View your citations (incl. relevant score)… in-browser PDF viewer with highlights. Warning when retrieval pipeline return low relevant articles".
  - Parsers: Azure Document Intelligence, Adobe PDF Extract, Docling and PaddleOCR, with Unstructured for other types.
  - GraphRAG, LightRAG and nano-GraphRAG options.

  Source: [primary, README](https://github.com/Cinnamon/kotaemon/blob/main/README.md)
- **Chunking.** `TokenSplitter` defaults to `chunk_size=1024` and `chunk_overlap=20` — [primary, kotaemon/indices/splitters/__init__.py](https://github.com/Cinnamon/kotaemon/blob/main/libs/kotaemon/kotaemon/indices/splitters/__init__.py)
- **Stores and models.**
  - Docstore is LanceDB; the vector store is Chroma.
  - OpenAI embeddings default to `text-embedding-3-large`. Local embeddings default to `nomic-embed-text` via Ollama, and FastEmbed is an option.
  - Rerankers: Cohere `rerank-v4.0-fast` and Voyage `rerank-2`.

  Source: [primary, flowsettings.py](https://github.com/Cinnamon/kotaemon/blob/main/flowsettings.py)
- **Retrieval defaults.** The class defaults are `retrieval_mode "hybrid"`, `top_k 5` and MMR off. The UI defaults are:
  - "Number of document chunks to retrieve" = 10.
  - Retrieval mode = hybrid.
  - "Use reranking" = True.
  - "Use LLM relevant scoring" = True, unless `USE_LOW_LLM_REQUESTS` is set.

  Source: [primary, ktem/index/file/pipelines.py](https://github.com/Cinnamon/kotaemon/blob/main/libs/ktem/ktem/index/file/pipelines.py)
- **Trust signals shipped in the UI.** This is the only OSS system in this survey with runtime answer-quality labels.
  - It shows "No evidence found." when no citations are produced.
  - It shows "WARNING! Context relevance score is low. Double check the model answer for correctness." when the maximum LLM (TruLens-style) relevance score falls below `CONTEXT_RELEVANT_WARNING_SCORE = 0.3`.
  - It shows "Answer confidence: {qa_score}", where `qa_score = exp(mean(token logprobs))`.

  Sources: [primary, ktem/reasoning/simple.py L223-275](https://github.com/Cinnamon/kotaemon/blob/main/libs/ktem/ktem/reasoning/simple.py), [primary, indices/qa/citation_qa.py L36-37, L275](https://github.com/Cinnamon/kotaemon/blob/main/libs/kotaemon/kotaemon/indices/qa/citation_qa.py)

#### Dify (langgenius/dify): 157,233★, "Dify Open Source License" (Apache 2.0 with conditions), last push 2026-09-26
- **Chunking.** The automatic rule uses `{"delimiter": "\n", "max_tokens": 500, "chunk_overlap": 50}`. Chunking modes are `automatic`, `custom` and `hierarchical` (parent-child) — [primary, api/models/dataset.py L409-416](https://github.com/langgenius/dify/blob/main/api/models/dataset.py)
- **Retrieval.** The default retrieval model is `SEMANTIC_SEARCH`, with `reranking_enable False`, `top_k 4` and the score threshold disabled — [primary, core/rag/datasource/retrieval_service.py L80-87](https://github.com/langgenius/dify/blob/main/api/core/rag/datasource/retrieval_service.py)
- **Citations.** The "retriever_resource" citation feature defaults to `{"enabled": False}` when an app config omits it — [primary, retrieval_resource/manager.py](https://github.com/langgenius/dify/blob/main/api/core/app/app_config/features/retrieval_resource/manager.py)
- **Observability.** The README lists integrations with Opik, Langfuse and Arize Phoenix, and a "RAG Pipeline" covering "text extraction from PDFs, PPTs" — [primary, README](https://github.com/langgenius/dify/blob/main/README.md)
- **Knowledge Pipeline.** Dify 1.9.0 (Sept 2025) introduced the Knowledge Pipeline: node-based ingestion, General / Parent-child / Q&A chunking, hybrid search with adjustable weights, and an optional rerank model — [inferred (search summary), Dify blog](https://dify.ai/blog/introducing-knowledge-pipeline), [inferred (search summary), GitHub discussion #26138](https://github.com/langgenius/dify/discussions/26138)

#### AnythingLLM (Mintplex-Labs/anything-llm): 66,477★, MIT, last push 2026-09-26
- **Embedder.** The native embedder defaults to `Xenova/all-MiniLM-L6-v2` — [primary, EmbeddingEngines/native/index.js](https://github.com/Mintplex-Labs/anything-llm/blob/master/server/utils/EmbeddingEngines/native/index.js)
- **Chunking.** `TextSplitter` defaults to `chunkSize = 1000` characters and `chunkOverlap = 20` — [primary, TextSplitter/index.js](https://github.com/Mintplex-Labs/anything-llm/blob/master/server/utils/TextSplitter/index.js)
- **Workspace defaults.** These are `topN 4`, `similarityThreshold 0.25` and `vectorSearchMode "default"`; the alternative mode is `"rerank"` — [primary, server/models/workspace.js](https://github.com/Mintplex-Labs/anything-llm/blob/master/server/models/workspace.js)
- **Reranker.** It is `Xenova/ms-marco-MiniLM-L-6-v2`. It was chosen over `mxbai-rerank-xsmall-v1` for CPU speed: "18docs = 1.6s" versus "6s". In LanceDB it reranks a candidate pool clamped to between 10 and 50 — [primary, EmbeddingRerankers/native/index.js](https://github.com/Mintplex-Labs/anything-llm/blob/master/server/utils/EmbeddingRerankers/native/index.js), [primary, vectorDbProviders/lance/index.js](https://github.com/Mintplex-Labs/anything-llm/blob/master/server/utils/vectorDbProviders/lance/index.js)
- **Not-found behaviour.** In "query" chat mode, when no context is found, the server returns the workspace's `queryRefusalResponse` or "There is no relevant information in this workspace to answer your query." — [primary, server/utils/chats/stream.js L102-105, L235-238](https://github.com/Mintplex-Labs/anything-llm/blob/master/server/utils/chats/stream.js)

#### PrivateGPT (zylon-ai/private-gpt): 57,540★, Apache-2.0, last push 2026-09-22
- The project was re-scoped in 2026. The README calls it an "open-source API layer… following the Claude API model", offering "Retrieval with citations and agentic RAG". Its example embedder is `mxbai-embed-large` via Ollama — [primary, README](https://github.com/zylon-ai/private-gpt/blob/main/README.md)
- **Defaults.**
  - Parser: Docling (`mode: api`, `use_ocr: true`, `ocr_model: easyocr`, `table_mode: accurate`), plus a `pdf_inspector` hybrid-OCR threshold.
  - Vector store: Qdrant, with `embed_dim 1024`.

  Source: [primary, settings.yaml](https://github.com/zylon-ai/private-gpt/blob/main/settings.yaml)
- **Retrieval settings.** `RetrievalSettings.top_k = 32` with `maximize_top_k = True`. Qdrant `hybrid_search` defaults to False — [primary, private_gpt/settings/settings.py L446-456, L1067-1069](https://github.com/zylon-ai/private-gpt/blob/main/private_gpt/settings/settings.py)

#### Khoj (khoj-ai/khoj): 37,503★, AGPL-3.0; repo push 2026-08-02; last PyPI release 1.42.10 (2025-07-15)
- **Models.** The bi-encoder defaults to `thenlper/gte-small` and the cross-encoder to `mixedbread-ai/mxbai-rerank-xsmall-v1`. `bi_encoder_confidence_threshold` is 0.18 — [primary, database/models/__init__.py L558-582](https://github.com/khoj-ai/khoj/blob/master/src/khoj/database/models/__init__.py)
- **Chunking.** Entries are split with `RecursiveCharacterTextSplitter(chunk_size=max_tokens=256, chunk_overlap=0)` — [primary, processor/content/text_to_entries.py L61-77](https://github.com/khoj-ai/khoj/blob/master/src/khoj/processor/content/text_to_entries.py)
- **Scope and evaluation.** Khoj reads PDFs, Markdown, org-mode, Word and Notion. The README links a post on "evaluate-khoj-quality" — [primary, README](https://github.com/khoj-ai/khoj/blob/master/README.md)

#### Onyx, formerly Danswer (onyx-dot-app/onyx): 32,252★, MIT (Community Edition), last push 2026-09-26
- **Embedder.** `DEFAULT_DOCUMENT_ENCODER_MODEL = "nomic-ai/nomic-embed-text-v1"` (`DOC_EMBEDDING_DIM 768`, normalised) with asymmetric prefixes `"search_query: "` and `"search_document: "`. The old default was `thenlper/gte-small` (384-d) — [primary, shared_configs/configs.py L38](https://github.com/onyx-dot-app/onyx/blob/main/backend/shared_configs/configs.py), [primary, onyx/configs/model_configs.py](https://github.com/onyx-dot-app/onyx/blob/main/backend/onyx/configs/model_configs.py)
- **Chunking.** `DOC_EMBEDDING_CONTEXT_SIZE = 512` tokens and `CHUNK_OVERLAP = 0`, with the code comment "unclear if overlaps actually help quality at all". Optional features:
  - multipass mini-chunks of 150 tokens and large chunks ×4;
  - contextual RAG, off by default;
  - `BLURB_SIZE 128`.

  Sources: [primary, onyx/indexing/chunker.py](https://github.com/onyx-dot-app/onyx/blob/main/backend/onyx/indexing/chunker.py), [primary, onyx/configs/app_configs.py](https://github.com/onyx-dot-app/onyx/blob/main/backend/onyx/configs/app_configs.py)
- **Retrieval.**
  - `HYBRID_ALPHA 0.5` (Vespa hybrid), `TITLE_CONTENT_RATIO 0.10` and `DOC_TIME_DECAY 0.5`.
  - `NUM_RETURNED_HITS 50`, of which `MAX_CHUNKS_FED_TO_CHAT 25` reach the LLM.
  - One neighbouring chunk above and one below are added.
  - There is no cross-encoder by default; a code comment says "For local, use: mixedbread-ai/mxbai-rerank-xsmall-v1".

  Sources: [primary, onyx/configs/chat_configs.py](https://github.com/onyx-dot-app/onyx/blob/main/backend/onyx/configs/chat_configs.py), [primary, shared_configs/configs.py L48-54](https://github.com/onyx-dot-app/onyx/blob/main/backend/shared_configs/configs.py)
- **Citations.** The citation processor maps [n] markers the LLM emits to SearchDocs, with modes REMOVE, KEEP_MARKERS and HYPERLINK — [primary, onyx/chat/citation_processor.py](https://github.com/onyx-dot-app/onyx/blob/main/backend/onyx/chat/citation_processor.py)
- **Positioning.** The README describes "Agentic RAG… hybrid index + a custom agent harness", "Deep Research" and connectors to "50+ applications" — [primary, README](https://github.com/onyx-dot-app/onyx/blob/main/README.md)

#### Open WebUI (open-webui/open-webui): 153,205★, custom licence; open-webui 0.11.4 (PyPI, 2026-09-21)
- **Defaults.**
  - Embedder: `RAG_EMBEDDING_MODEL = sentence-transformers/all-MiniLM-L6-v2`.
  - Chunking: `CHUNK_SIZE 1000`, `CHUNK_OVERLAP 100`, with the Markdown-header splitter on.
  - Top-k: `RAG_TOP_K 3` and `RAG_TOP_K_RERANKER 3`.
  - Thresholds and hybrid: `RAG_RELEVANCE_THRESHOLD 0.0`. `ENABLE_RAG_HYBRID_SEARCH` is off unless set; when on, `RAG_HYBRID_BM25_WEIGHT` is 0.5.
  - Reranker: `RAG_RERANKING_MODEL` is empty (none).
  - Extraction engines: the built-in default, plus Tika, Docling, Azure Document Intelligence, Mistral OCR, PaddleOCR-VL and an external loader.

  Source: [primary, backend/open_webui/config.py L955-1066](https://github.com/open-webui/open-webui/blob/main/backend/open_webui/config.py)
- **Chunk unit.** The default splitter is `RecursiveCharacterTextSplitter` (character-based) when `TEXT_SPLITTER` is empty — [primary, routers/retrieval.py](https://github.com/open-webui/open-webui/blob/main/backend/open_webui/routers/retrieval.py)
- **Answer template.** The default RAG template asks for inline `[id]` citations. It includes "If you don't know the answer, clearly state that", but also "If the answer isn't present in the context but you possess the knowledge, explain this to the user and provide the answer using your own understanding." That is a permissive fallback to the model's own knowledge — [primary, config.py L1070-1096](https://github.com/open-webui/open-webui/blob/main/backend/open_webui/config.py)

#### Perplexica, now **Vane** (ItzCrazyKns/Vane): 36,911★, MIT, last push 2026-09-01
- The repo has been renamed. Vane is a web "answering engine" that runs SearxNG search with Speed, Balanced and Quality modes and "cited sources". It does web RAG, not document RAG — [primary, README](https://github.com/ItzCrazyKns/Vane/blob/master/README.md)

#### Defaults side by side (primary sources above; "—" means not verified)

| System | Chunk size / overlap | Default embedder | Hybrid by default? | Reranker by default | Top-k to LLM | Citation mechanism |
|---|---|---|---|---|---|---|
| RAGFlow | 512 tok / – | none bundled (e.g. bge-m3) | yes (term 0.7 + vector 0.3) | none | 6 (from 1024 recalled, 64 rerank candidates) | model markers + post-hoc similarity insertion |
| LlamaIndex | 1024 tok / 200 | OpenAI ada-002 | no (RRF k=60 optional) | none | 2 | "Source N" prompt |
| Haystack 3.x | 200 words / 0 | all-mpnet-base-v2 | pipeline-defined (RRF joiner available) | ms-marco-MiniLM-L-6-v2 when used | 10 | [n] parsed by AnswerBuilder |
| txtai | — | all-MiniLM-L6-v2 | optional BM25+dense | none | 3 | best-match reference by similarity |
| R2R | 1024 / 512 (unit unstated) | text-embedding-3-small @512 | "advanced" preset: RRF k=50 | none (commented) | 10 | "RAG with citations" |
| Kotaemon | 1024 tok / 20 | pluggable | yes | on + LLM relevance scoring | 10 (UI) | citations with relevance score and PDF highlight |
| Dify | 500 tok / 50 | pluggable | no (semantic) | off | 4 | off unless enabled |
| AnythingLLM | 1000 chars / 20 | all-MiniLM-L6-v2 | no | off (MiniLM-L-6 in "rerank" mode) | 4 (threshold 0.25) | — |
| Khoj | 256 tok / 0 | gte-small | — | mxbai-rerank-xsmall-v1 | — (bi-encoder threshold 0.18) | — |
| Onyx | 512 tok / 0 | nomic-embed-text-v1 | yes (alpha 0.5) | none | ≤25 of 50 | [n] mapped to docs |
| Open WebUI | 1000 chars / 100 | all-MiniLM-L6-v2 | no | none | 3 | [id] per template |
| PrivateGPT | — (Docling-parsed) | pluggable (1024-d example) | no | — | 32 | "retrieval with citations" |

### Inferences
- **Chunk size.** Default chunks cluster between about 200 words and 512 tokens (Haystack, Khoj, Onyx, RAGFlow, Dify), with generic-framework defaults up to 1,024 tokens (LlamaIndex, Kotaemon, R2R). Overlap is usually 0–20 tokens; Onyx explicitly doubts it helps. App: its ~300–350-word chunks are inside the mainstream band, so size is not a sign of lagging.
- **Semantic chunking.** A NAACL 2025 Findings paper reports that semantic chunking's cost "is not justified by consistent performance gains", and that fixed-size chunking often did as well or better on realistic documents ([inferred (search summary), ACL Anthology](https://aclanthology.org/2025.findings-naacl.114/), [inferred (search summary), Vectara blog](https://www.vectara.com/blog/is-semantic-chunking-worth-the-computational-cost)). App: a custom semantic chunker is not an advantage the field recognises, but it is not a deficit either.
- **Embedder.** all-MiniLM-L6-v2 is still the shipped default in three widely used local-first stacks (txtai, Open WebUI, AnythingLLM native). The systems that tuned for quality (Onyx, Khoj, PrivateGPT's example, RAGFlow's example) default to nomic, gte, mxbai or bge models. App: MiniLM-L6-v2 at 384-d is a common default, not a leading choice.
- **Reranker.** Every reranker default I found is at least a 6-layer MiniLM cross-encoder (Haystack, AnythingLLM) or mxbai-rerank-xsmall (Khoj, Onyx's suggestion), and several systems ship with reranking off. App: ms-marco-TinyBERT-L2-v2 is smaller than any observed default. Having reranking on at all is not behind practice. Whether an L2 reranker helps or hurts should be measured.
- **Fusion.** RRF is one of two mainstream fusion styles: LlamaIndex (k=60), R2R (k=50), the Haystack joiner option and PocketMind (k=60) use it. The other is weighted linear fusion: RAGFlow 0.7/0.3, Onyx alpha 0.5, Open WebUI BM25 weight 0.5, VecturaKit 0.5. App: BM25 plus vector with RRF matches practice.
- **Verification.** No OSS system surveyed runs a claim-level entailment check in the answer path by default. Their citations are either markers the model is told to emit or similarity matches (RAGFlow, txtai). Kotaemon's labels are relevance warnings and a token-probability "confidence". Entailment judges exist, but only as evaluation tooling (LlamaIndex, Haystack). A real runtime check would therefore put the app ahead of open-source defaults. Claiming a check that did not run falls below them, because none of these systems claims to verify.
- **Not-found handling.** It varies. Some systems use hard refusals (RAGFlow's exact sentence, AnythingLLM's query-mode refusal) or instruct the model to decline (LlamaIndex). Open WebUI is permissive and falls back to the model's own knowledge.
- **Extractive fast path.** In the code I read, no system replaces a generated answer with a regex extraction. Extractive answering appears as a model task (txtai `question-answering`) or as context trimming (PocketMind, section 3). This is absence of evidence in the files read, not proof of absence.

### Gaps
- Several internals were not verified: txtai's and AnythingLLM's default parsers; Khoj and Onyx citation rendering; the unit of R2R's `chunk_size`; Dify's default hybrid weights (commonly described as 0.7 semantic / 0.3 keyword, but not found in the backend code I read); PrivateGPT's chunker; and how often RAGFlow's post-hoc citation insertion fires compared with model-emitted markers.
- I could not verify release dates or benchmark (MTEB/BEIR) scores for all-MiniLM-L6-v2, ms-marco-TinyBERT-L2-v2, ms-marco-MiniLM-L-6-v2 or mxbai-rerank-xsmall-v1, because Hugging Face and arXiv are blocked. From memory, the MiniLM and ms-marco cross-encoders date from about 2021, which is older than 2023 and possibly superseded. Treat this as unverified.
- I found no reliable per-system evaluation tooling for RAGFlow, R2R, Onyx or Open WebUI.

## 2. Commercial products (NotebookLM, Apple Intelligence semantic index, Microsoft 365 Copilot, Glean, Perplexity): how they signal supported, uncertain or not found, and which trust labels are honest

### Takeaway
Products converge on three signals:
- inline numbered citations that open the exact source passage (NotebookLM, M365 Copilot, Glean, Perplexity);
- permission-aware retrieval (Glean, M365);
- generic "AI can be wrong" disclaimers, which Microsoft hid by default in late 2025.

Explicit supported or unsupported labels are rare. Where they exist, an actual check sits behind them and they have at least three outcomes, with "not evaluated" kept distinct from "supported". Examples are Gemini's double-check, Google's check-grounding API, Azure groundedness detection and AWS contextual grounding. Research shows that citations raise user trust even when they are random, and that cited answers are often unsupported. A "Verified" label that appears without a check is therefore the pattern the evidence identifies as misleading.

### Cited Findings
- **NotebookLM (being rebranded "Gemini Notebook" in Google help pages).**
  - It answers only from user-uploaded sources and puts inline numbered citations on responses; hovering or clicking opens the exact passage.
  - When the answer is not in the sources, it reportedly says so.
  - The UI carries the disclaimer "NotebookLM can be inaccurate; please double-check its responses."

  Sources: [inferred (search summary), kzsoftworks](https://www.kzsoftworks.com/blog/notebooklm-this-ai-is-grounded-in-your-documents-not-the-whole-internet), [inferred (search summary), Google blog, May 2026](https://blog.google/innovation-and-ai/products/notebooklm/notebooklm-google-io-2026/), [inferred (search summary), Gemini Notebook Help](https://support.google.com/gemininotebook/answer/16164461), [inferred (search summary), Llewyn Paine, 2025-09](https://llewynpaine.consulting/blog/2025/9/18/using-notebooklm-for-user-research-useful-but-ultimately-just-another-llm). Blogs also report misquoted sources and omissions despite the grounding.
- **Gemini "double-check response" is a tri-state claim label.**
  - Green: Google Search found similar content.
  - Orange: search found content likely different from the claim, or found no relevant content.
  - No highlight: "not enough information to evaluate" or the statement is not factual.

  Google states the feature does not guarantee accuracy — [inferred (search summary), Gemini Apps Help](https://support.google.com/gemini/answer/14143489), [inferred (search summary), Hakky Handbook](https://book.st-hakky.com/en/data-science/gemini-pro-double-check-feature)
- **Microsoft 365 Copilot.**
  - Microsoft's docs say "Citations build trust that a Microsoft 365 Copilot response is accurate and grounded. The response body automatically includes citations…"
  - If a plugin does not map a source URL, "the response can still include a citation, but only with a representative pill or icon. The end user can't click through and confirm the data." (ms.date 2026-08-25.)
  - Source: [primary, MicrosoftDocs/m365copilot-docs plugin-citations.md (mirror of learn.microsoft.com)](https://github.com/MicrosoftDocs/m365copilot-docs/blob/main/docs/plugin-citations.md)
  - Copilot grounds on Microsoft Graph with "semantic indexing" ("advanced lexical and semantic understanding") and preserves organisational permissions. In Teams chat, "Responses include clickable citations" (ms.date 2026-03-24) — [primary, MicrosoftDocs microsoft-365-copilot-overview.md](https://github.com/MicrosoftDocs/microsoft-365-docs/blob/public/copilot/microsoft-365-copilot-overview.md)
  - The semantic index is described as a per-tenant vector index over Graph content — [inferred (search summary), Microsoft Learn](https://learn.microsoft.com/en-us/microsoftsearch/semantic-index-for-copilot)
  - Microsoft began hiding the "AI-generated content may be incorrect" disclaimer by default in M365 Copilot Chat from about November 2025. It added an admin policy, "AI Disclaimer with Heightened Awareness", that restores a bolder warning — [inferred (search summary), Windows Latest, 2025-11-02](https://www.windowslatest.com/2025/11/02/microsoft-365-copilot-drops-ai-can-make-mistakes-alert-by-default/)
- **Glean.**
  - Deep-linked citations take users "to the exact passage in the source that supports the statement".
  - Retrieval enforces existing permissions.
  - "Responses that rely only on the LLM's pre-trained knowledge won't have citations", and "thinking mode" is recommended "if consistent citations are important".

  Source: [inferred (search summary), Glean docs: Citations](https://docs.glean.com/user-guide/assistant/glean-chat/glean-chat-citations/glean-citations). The absence of a citation is therefore the only signal that an answer is ungrounded.
- **Perplexity.**
  - It shows numbered inline citations mapping claims to retrieved web pages. Descriptions of its internal pipeline (BM25 plus dense retrieval, a three-layer reranker) come from SEO blogs and are not verified; treat them as speculative — [inferred (search summary), ZipTie](https://ziptie.ai/blog/how-perplexity-ai-answers-work/)
  - The Tow Center / CJR study (2025-03-06) tested 8 AI search engines on quoting news excerpts. Collectively they answered more than 60% of queries incorrectly. Perplexity had the lowest failure rate at 37%; Grok-3 Search had the highest at 94%. Paid tiers were not more accurate — [inferred (search summary), CJR Tow Center](https://www.cjr.org/tow_center/we-compared-eight-ai-search-engines-theyre-all-bad-at-citing-news.php), [inferred (search summary), Nieman Lab](https://www.niemanlab.org/2025/03/ai-search-engines-fail-to-produce-accurate-citations-in-over-60-of-tests-according-to-new-tow-center-study/)
  - An earlier audit (EMNLP Findings 2023) of Bing Chat, NeevaAI, perplexity.ai and YouChat found that only 51.5% of generated sentences were fully supported by their citations, and only 74.5% of citations supported their sentence — [inferred (search summary), ACL Anthology](https://aclanthology.org/2023.findings-emnlp.467/)
- **Apple Intelligence semantic index and personal context, as far as Apple has published.**
  - Apple's WWDC26 developer guide says "Entity schemas contribute your app's content to the Spotlight semantic index, enabling personal context understanding with attribution back to your app" — [primary, WWDC26 Apple Intelligence guide](https://developer.apple.com/wwdc26/guides/apple-intelligence/)
  - In WWDC26 session 343, the `.indexAppEntities` method "populates the Spotlight semantic index". Depending on the App Intents domain, it "provides semantic search capabilities"; IndexedEntityQuery supports re-indexing — [primary, WWDC26 343 transcript](https://developer.apple.com/videos/play/wwdc2026/343/)
  - In WWDC26 session 240, entities adopting IndexedEntity are "indexed into the system semantic index", which lets Siri "match based on meaning" and "search your content, reason over it, and use it to answer questions" — [primary, WWDC26 240 transcript](https://developer.apple.com/videos/play/wwdc2026/240/)
  - `IndexedEntity` has been available since iOS 18 / macOS 15 and makes entities "discoverable by Apple Intelligence" — [primary, IndexedEntity docs](https://developer.apple.com/documentation/appintents/indexedentity)
  - The Core Spotlight index is "a private, entirely local index, that never leaves the device", and semantic search arrived in iOS 18 — [primary, WWDC24 10131 transcript](https://developer.apple.com/videos/play/wwdc2024/10131/)
  - Apple Newsroom (2026-09) announced "Siri AI" with personal context understanding, built on the Spotlight index and on-device plus PCC Apple Foundation Models — [inferred (search summary), Apple Newsroom](https://www.apple.com/newsroom/2026/09/siri-ai-a-profoundly-more-capable-and-personal-assistant-is-here/)
- **Runtime grounding-check services, and the outputs they label.**
  - **Google check-grounding API:** an overall support score from 0 to 1 plus per-claim scores and citations. Experimental "contradicting citations" are available. A claim that is "only partially entailed… is not considered grounded". Latency is under 500 ms — [inferred (search summary), Google Cloud docs](https://docs.cloud.google.com/generative-ai-app-builder/docs/check-grounding)
  - **Azure AI Content Safety groundedness detection:**
    - Non-Reasoning mode returns "binary grounded/ungrounded results without detailed explanations", for real-time use. Reasoning mode "Provides detailed explanations for detected ungrounded segments".
    - A correction feature returns a corrected text.
    - Domains are MEDICAL and GENERIC; tasks are QnA and Summarization.
    - Doc dates: ms.date 2025-11-21, overview 2026-02-18.
    - Sources: [primary, MicrosoftDocs/azure-ai-docs groundedness.md](https://github.com/MicrosoftDocs/azure-ai-docs/blob/main/articles/ai-services/content-safety/concepts/groundedness.md), [primary, groundedness-detection-overview include](https://github.com/MicrosoftDocs/azure-ai-docs/blob/main/articles/ai-services/content-safety/includes/groundedness-detection-overview.md)
  - **AWS Bedrock Guardrails contextual grounding check:** separate grounding and relevance scores from 0 to 1 with configurable thresholds. A response scoring below threshold "is blocked and the configured blocked message is returned" — [inferred (search summary), AWS docs](https://docs.aws.amazon.com/bedrock/latest/userguide/guardrails-contextual-grounding-check.html)
  - **Anthropic Citations API:**
    - Documents are chunked into sentences, or custom content blocks are used as-is.
    - `cited_text` is extracted from the source, so "citations are guaranteed to contain valid pointers to the provided documents".
    - Anthropic reports up to 15% better "recall accuracy" than custom implementations. The customer Endex reported "source hallucinations… from 10% to 0%".
    - Citations "cannot be used together with structured outputs".
    - Sources: [primary, Anthropic news (update note dated 2025-06-30)](https://www.anthropic.com/news/introducing-citations-api), [primary, Claude docs: Citations](https://docs.claude.com/en/docs/build-with-claude/citations). A valid pointer shows that the quoted text exists, not that it entails the claim.
- **Evidence on how trust labels act on users.**
  - Ding et al. (AAAI 2025) found a significant rise in self-reported trust when citations were present, "even when the citations were random". Trust fell significantly when participants checked the citations — [inferred (search summary), AAAI proceedings](https://ojs.aaai.org/index.php/AAAI/article/view/34550), [inferred (search summary), arXiv 2501.01303](https://arxiv.org/abs/2501.01303)
  - Stanford RegLab / HAI (J. Empirical Legal Studies, 2025) tested legal tools marketed as avoiding hallucinations or giving "hallucination-free" citations. Lexis+ AI and Westlaw AI-Assisted Research hallucinated on 17–33% of queries, and the paper calls the providers' claims "overstated" — [inferred (search summary), RegLab](https://reglab.stanford.edu/publications/hallucination-free-assessing-the-reliability-of-leading-ai-legal-research-tools/), [inferred (search summary), Wiley JELS](https://onlinelibrary.wiley.com/doi/full/10.1111/jels.12413)
- **Apple's own design guidance on confidence and verification labels (HIG).**
  - "If you're not sure how your confidence values correlate with the quality of your results, it's not a good idea to convey confidence to people."
  - Translate confidence into semantic categories ("high chance"/"low chance") or actionable suggestions.
  - At lower confidence, ask people to confirm.
  - For proactive features, "set a confidence threshold below which you don't offer results".
  - "Keep attributions factual and based on objective analysis."

  Source: [primary, HIG: Machine learning](https://developer.apple.com/design/human-interface-guidelines/machine-learning)
- The HIG's Generative AI page (updated 2026-06-08) says "Raise awareness about and minimize the chance of hallucinations… clearly communicate that AI-generated content may contain errors… Avoid requesting factual information unless you're confident the model has access to verified and up-to-date information" — [primary, HIG: Generative AI](https://developer.apple.com/design/human-interface-guidelines/generative-ai)

### Inferences
- **Honest labels in the evidence have three properties.** They are produced by a check that actually ran (Gemini, Vertex, Azure, AWS). They keep "not evaluated" or "insufficient info" separate from "supported" (Gemini's unhighlighted state, Azure's binary result plus reasons, AWS's block-below-threshold). And they are attached to the claim or passage, not to the whole answer (Vertex per-claim scores, Gemini per-sentence highlights).
- **Misleading labels in the evidence are of three kinds:** marketing-level guarantees ("hallucination-free", Stanford); citation presence used as a trust proxy (Ding et al. show it works on users even when the citations are random); and confidence numbers not validated against quality (Apple's HIG warns against them).
- **Kotaemon's "Answer confidence" is weaker than it looks.** It is an exponentiated mean token log-probability, which by HIG's criterion should not be shown unless it is calibrated.
- **App:** a "Verified" badge that defaults to Verified when no check ran combines two misleading patterns. It uses a trust cue users over-weight, and it has no "not checked" state. Every product-level label found here with verification semantics either runs a check or shows nothing. None defaults to positive.
- **App:** the permission-aware, source-deep-linked citation (Glean, M365, NotebookLM) is the product baseline. Removing the generic disclaimer, as Microsoft did, is defensible only if claim-level signals exist.

### Gaps
- Primary vendor docs for NotebookLM, Glean, Perplexity, Google Cloud grounding and AWS Guardrails were egress-blocked, so those claims are search-summary-level.
- Perplexity's retrieval and reranking internals are not publicly documented; I found only speculative third-party descriptions.
- Apple has not published the semantic index's embedding model, chunking or ranking. I found no Apple statement on how Siri AI signals unsupported answers.
- I found no published study that tests "default-positive" verification badges specifically. The inference relies on Ding et al., the HIG and the product patterns above.

## 3. Apple-platform on-device RAG: Swift libraries and apps (embedding model, storage, retrieval, fitting a small context, maturity)

### Takeaway
By late 2026 the Swift building blocks are mature enough for a serious local RAG stack:
- **Storage:** hybrid vector plus BM25 (VecturaKit), HNSW (ObjectBox, USearch), and SQLite vector tables (sqlite-vec, still pre-v1).
- **Embedders:** modern models through MLX (bge, nomic, Qwen3-Embedding, LFM2.5 embedding and ColBERT, bge-reranker-v2-m3) and MLTensor (MiniLM, ModernBERT, NomicBERT, Model2Vec).

Most published iOS and macOS "chat with your files" apps are still simple: MiniLM or NLEmbedding, brute-force cosine search, top-k. Popular local-LLM apps (PocketPal, Private LLM, Enchanted, fullmoon) do not do document RAG at all.

### Cited Findings
- **VecturaKit** (rryam/VecturaKit): 323★, MIT, last push 2026-08-31, SPM `from: "6.3.0"`, iOS 18+ / macOS 15+.
  - Described as a "Swift-based vector database designed for on-device apps"; it says it was inspired by Dripfarm's SVDB.
  - Embedders are pluggable: `NLContextualEmbedder` (Apple NaturalLanguage, "zero external dependencies"), `SwiftEmbedder` via VecturaEmbeddingsKit (swift-embeddings), `MLXEmbedder` via VecturaMLXKit, and `OpenAICompatibleEmbedder`.
  - "Hybrid Search: Combines vector similarity with BM25 text search". The config example shows `hybridWeight: 0.5`, `k1: 1.2`, `bm25NormalizationFactor 10`, `minThreshold 0.7`.
  - Memory strategies are "automatic, full-memory, or indexed" (`candidateMultiplier`). A `VecturaStorage` protocol supports custom backends such as SQLite or Core Data.

  Sources: [primary, README](https://github.com/rryam/VecturaKit/blob/main/README.md), [primary, Package.swift](https://github.com/rryam/VecturaKit/blob/main/Package.swift). Add-on packages: VecturaMLXKit (20★, created 2026-02) and VecturaEmbeddingsKit (5★, created 2026-04) — [primary, GitHub metadata](https://github.com/rryam/VecturaMLXKit)
- **SVDB** (Dripfarm/SVDB): 224★, MIT, last push 2025-12-07. The 1.7 KB README shows adding documents with OpenAI `textEmbeddingAda` or `NLEmbedding.wordEmbedding` vectors, and says "Not sure. I want to make it easier to add documents and take care of the embeddings for you." It is rudimentary — [primary, README](https://github.com/Dripfarm/SVDB/blob/master/README.md)
- **ObjectBox Swift** (objectbox/objectbox-swift): 619★, Apache-2.0, 5.3.0 released 2026-05-19.
  - "superfast on-device vector search", Sync optional — [primary, README](https://github.com/objectbox/objectbox-swift/blob/main/README.md), [primary, CHANGELOG](https://github.com/objectbox/objectbox-swift/blob/main/CHANGELOG.md)
  - The HNSW vector index arrived with ObjectBox Swift 4.0 in 2024 (`nearestNeighbors` query condition, "find with scores") — [inferred (search summary), ObjectBox blog](https://objectbox.io/swift-ios-on-device-vector-database-aka-semantic-index/). The CHANGELOG adds geo-distance vector search in 4.2.0 (2025-04-09) — [primary, CHANGELOG](https://github.com/objectbox/objectbox-swift/blob/main/CHANGELOG.md)
- **USearch** (unum-cloud/USearch): 4,320★, Apache-2.0, 2.26.2 (PyPI, 2026-08-31).
  - An HNSW library with Swift and Objective-C bindings covering iOS and macOS, quantisation (bf16, f16, i8, b1 and others) and an SQLite extension.
  - The Swift API is `USearchIndex.make(metric:dimensions:connectivity:quantization:)`.
  - The example app ashvardanian/SwiftSemanticSearch has 162★ and was last pushed 2024-12-20.

  Sources: [primary, README](https://github.com/unum-cloud/usearch/blob/main/README.md), [primary, swift/README.md](https://github.com/unum-cloud/usearch/blob/main/swift/README.md)
- **sqlite-vec** (asg017/sqlite-vec): 8,137★, Apache-2.0, 0.1.9 on PyPI (2026-03-31). The README warns: "sqlite-vec is a pre-v1, so expect breaking changes!"
  - It stores float, int8 and binary vectors in `vec0` virtual tables and is pure C, running "anywhere SQLite runs".
  - Mozilla Builders sponsors it.
  - Swift bindings: jkrukowski/SQLiteVec, 50★, MIT, `from: "0.0.9"`, pushed 2026-09-22.

  Sources: [primary, README](https://github.com/asg017/sqlite-vec/blob/main/README.md), [primary, PyPI](https://pypi.org/project/sqlite-vec/), [primary, SQLiteVec README](https://github.com/jkrukowski/SQLiteVec/blob/main/README.md)
- **MLX Swift.**
  - The reusable libraries (`MLXLLM`, `MLXVLM`, `MLXEmbedders`) moved from mlx-swift-examples (2,669★) to **mlx-swift-lm** (820★, MIT, created 2025-10, `from: "3.31.3"`, pushed 2026-09-22) — [primary, mlx-swift-examples README](https://github.com/ml-explore/mlx-swift-examples/blob/main/README.md), [primary, mlx-swift-lm README](https://github.com/ml-explore/mlx-swift-lm/blob/main/README.md)
  - MLXEmbedders registers these models:
    - all-MiniLM-L6-v2 and L12-v2;
    - bge-small, base, large-en-v1.5 and bge-m3;
    - **bge-reranker-v2-m3**;
    - snowflake-arctic-embed-xs and -l;
    - multilingual-e5-small;
    - nomic-embed-text-v1 and v1.5;
    - mxbai-embed-large-v1;
    - **Qwen3-Embedding-0.6B-4bit-DWQ**;
    - **LFM2.5-Embedding-350M** and **LFM2.5-ColBERT-350M** (late interaction);
    - gte-tiny and bge-micro.

    Sources: [primary, Libraries/MLXEmbedders/ModelFactory.swift](https://github.com/ml-explore/mlx-swift-lm/blob/main/Libraries/MLXEmbedders/ModelFactory.swift), [primary, MLXEmbedders README](https://github.com/ml-explore/mlx-swift-lm/blob/main/Libraries/MLXEmbedders/README.md)
- **swift-embeddings** (jkrukowski/swift-embeddings): 155★, MIT, pushed 2026-09-21. It runs embedding models "locally in Swift using MLTensor": BERT (including all-MiniLM-L6-v2), ModernBERT (including nomic-ai/modernbert-embed-base), NomicBERT (nomic-embed-text-v1.5), RoBERTa, XLM-RoBERTa, CLIP, Model2Vec (potion-base-2M/4M/8M/32M, potion-retrieval-32M) and static embeddings — [primary, README](https://github.com/jkrukowski/swift-embeddings/blob/main/README.md)
- **Apple NaturalLanguage `NLContextualEmbedding`** (iOS 17 / macOS 14).
  - It "computes sequences of embedding vectors" (per-token vectors, so callers must pool them into a sentence vector).
  - Assets must be requested with `requestAssets`. Its properties include `dimension` and `maximumSequenceLength`.

  Source: [primary, NLContextualEmbedding docs](https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding). The models are BERT masked-language-model embeddings covering "up to 27 different languages across three scripts", positioned for fine-tuning classifiers and taggers — [primary, WWDC23 10042 transcript](https://developer.apple.com/videos/play/wwdc2023/10042/)
- **Core Spotlight semantic search** (iOS 18 / macOS 15). `CSUserQuery` performs "lexical and semantic searches" over the app's own on-device index, returning ranked results and suggestions. `prepare()` warms resources, and `userEngaged(...)` feeds ranking — [primary, CSUserQuery](https://developer.apple.com/documentation/corespotlight/csuserquery), [primary, Building a search interface](https://developer.apple.com/documentation/corespotlight/building-a-search-interface-for-your-app)
- **SimilaritySearchKit** (ZachNagengast/similarity-search-kit): 535★, Apache-2.0, **last push 2024-06-04**, so stale for over two years.
  - Embedders: `NaturalLanguage` (NLEmbedding), `MiniLMAll` (all-MiniLM-L6-v2, 46 MB), `Distilbert` (msmarco-distilbert-base-tas-b, 86 MB quantised) and `MiniLMMultiQA`.
  - Metrics: cosine, dot or Euclidean.
  - Examples include a "ChatWithFilesExample" macOS app.

  Source: [primary, README](https://github.com/ZachNagengast/similarity-search-kit/blob/main/README.md). LLMFarm (below) and Sidekick (via a fork) both use it.
- **LocalLLMClient** (tattn/LocalLLMClient): 219★, MIT, "still experimental". It is a Swift package over llama.cpp (GGUF), MLX and the FoundationModels framework, with experimental tool calling. It has no retrieval layer — [primary, README](https://github.com/tattn/LocalLLMClient/blob/main/README.md)
- **LLM apps and whether they do document RAG.**
  - **PocketPal AI** (a-ghorbani/pocketpal-ai): 8,416★, MIT, React Native / llama.rn, on the App Store and Google Play. Its README lists Pals, tools, benchmarking and a leaderboard. **It lists no document RAG.** — [primary, README](https://github.com/a-ghorbani/pocketpal-ai/blob/main/README.md)
    - A search summary attributed a BM25 + BGE knowledge base to PocketPal. That feature belongs to the **PocketMind** fork (tokenbleed/pocketmind: 1★, created 2026-08-22, Android APKs).
    - PocketMind chunks documents at 1,200 characters with 200 overlap and embeds them with BGE Small EN v1.5 (Qwen3-Embedding optional) via llama.cpp. It fuses "BM25 + dense cosine, fused with RRF k=60", takes top-K "with a cosine floor", then does "Extractive trimming — query-relevant sentences only, 900 chars per hit" within a 3,000-character global budget.
    - It shows provenance chips ("KB badge… 'N KB excerpts from file'… so you always see whether retrieval fired").
    - Its design note: "Brute-force beats an index at phone scale."
    - Source: [primary, PocketMind README](https://github.com/tokenbleed/pocketmind/blob/main/README.md)
  - **Private LLM** (Numen Technologies; closed source) reportedly does not support reading documents or RAG yet. It offers 8K-token context on iPhone and iPad and 32K on Mac — [inferred (search summary), Private LLM FAQ](https://privatellm.app/en/faq)
  - **Enchanted** (gluonfield/enchanted): 6,004★, Apache-2.0. An Ollama client for iOS, macOS and visionOS with no RAG — [primary, README](https://github.com/gluonfield/enchanted/blob/main/README.md)
  - **fullmoon** (mainframecomputer/fullmoon-ios): 2,267★, MIT, last push 2025-05-05. An MLX chat app with no RAG — [primary, README](https://github.com/mainframecomputer/fullmoon-ios/blob/main/README.md)
  - **LLMFarm** (guinmoon/LLMFarm): 2,074★, MIT, last push 2026-01-30. A llama.cpp app for iOS and macOS with "RAG" and Apple Shortcuts. It credits similarity-search-kit — [primary, README](https://github.com/guinmoon/LLMFarm/blob/main/README.md)
  - **Sidekick** (johnbean393/Sidekick): 3,316★, MIT, macOS only, last push 2026-05-24.
    - Runs llama.cpp locally with "experts" holding files, folders and websites via RAG, plus web search and a "Deep Research" agent — [primary, README](https://github.com/johnbean393/Sidekick/blob/main/README.md)
    - Its dependencies include a fork of similarity-search-kit, ExtractKit-macOS and SQLite.swift — [primary, Package.resolved](https://github.com/johnbean393/Sidekick/blob/main/Sidekick.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved)
  - **GPT4All** (nomic-ai/gpt4all): 77,380★, MIT, **last push 2025-05-27**, so possibly stagnant. It has had "LocalDocs" for chatting with local files since July 2023, with a macOS installer — [primary, README](https://github.com/nomic-ai/gpt4all/blob/main/README.md)
  - **Cactus** (cactus-compute/cactus): 6,062★, licence not asserted. A cross-platform on-device engine with "embeddings, RAG, vision, vector index, cloud handoff" and Swift bindings — [primary, README](https://github.com/cactus-compute/cactus/blob/main/README.md)
  - **Hobby reference apps (0★, 2026).**
    - **hermit:** chunks at about 300 words, embeds with all-MiniLM-L6-v2 via MLXEmbedders, stores vectors in memory with JSON persistence, runs Accelerate/vDSP cosine top-K, and answers with Gemma 4 E2B 4-bit. It swaps the embedder and the LLM in and out of memory because both do not fit — [primary, README](https://github.com/JaviChulvi/hermit/blob/main/README.md)
    - **iOS-RAG:** defaults to the Apple NaturalLanguage embedder ("512d"), with a SQLite-backed vector store and llama.cpp GGUF models — [primary, README](https://github.com/jakob2411/iOS-RAG/blob/main/README.md)

### Inferences
- **On-device embedders.** The modern embedders and rerankers that server systems use (bge, nomic, mxbai, Qwen3-Embedding, bge-reranker-v2-m3, ColBERT-style LFM2.5) are now registered in an Apple-maintained Swift library (MLXEmbedders). App: staying on all-MiniLM-L6-v2 is a choice, not a platform limit.
- **Hybrid search in Swift.** Among the third-party Swift libraries surveyed, only VecturaKit ships hybrid BM25 plus vector search, using weighted fusion. ObjectBox's "hybrid" means vector plus database filters. Apple's Core Spotlight does lexical plus semantic search inside a system index. App: SQLite FTS5 BM25 plus a vector file plus RRF already equals or exceeds the typical Swift reference.
- **Vector storage at app scale.** A custom vector file is common in this segment: hermit uses JSON, SimilaritySearchKit is in-memory, and PocketMind uses a Float32 blob per document. PocketMind's note that brute force suffices at phone scale matches hermit and sqlite-vec's approach. HNSW (ObjectBox, USearch) matters only at far larger corpora. A caution: this rests on design notes, not measurements.
- **NLContextualEmbedding.** It is a masked-LM BERT that emits per-token outputs. Unlike MiniLM, bge and nomic, it is not a retrieval-trained sentence embedder, so using it for RAG requires pooling and gives no retrieval-quality guarantee. Apple's docs claim no retrieval quality for it.
- **Consumer-app segment.** App: an app with hybrid retrieval, reranking, citations and a verification step is already at or above the published Swift consumer-app norm. The gap is against server-grade systems (embedder and reranker choice, verification semantics), not against Apple-platform peers.

### Gaps
- I could not read GitHub release notes; api.github.com release endpoints are restricted in this session. So there are no exact latest-release dates for VecturaKit, swift-embeddings, mlx-swift-lm or LocalLLMClient; README pin versions and last-push dates stand in for them.
- The embedding model in Sidekick's fork of SimilaritySearchKit and GPT4All's current LocalDocs embedder are unverified.
- Whether MLXEmbedders exposes a cross-encoder scoring API for bge-reranker-v2-m3, as opposed to only loading it, is unverified.
- `NLContextualEmbedding.dimension` and `maximumSequenceLength` values were not retrievable from the docs JSON; iOS-RAG's "512d" is a hobby-project claim.
- I found no published retrieval-quality benchmark comparing NLContextualEmbedding, MiniLM and bge on-device.

## 4. Retrieval with Apple's Foundation Models framework: Apple docs, sample code, and WWDC 2025/2026 guidance (tool calling to search, guided generation, citations)

### Takeaway
Apple's own RAG guidance (TN3193, first published 2025-10-06 and updated 2026-03-31) prescribes the classic pipeline: chunk, embed with NaturalLanguage or Core ML, store, retrieve, then pass the snippets to the model. Retrieval runs either as a Tool or as a step before calling the model. The guidance assumes a 4,096-token session budget and a limit of 3–5 tools, and recommends retrieving directly when the model always needs the information.

The iOS 27 wave (WWDC26) added:
- PCC access (32K context, reasoning levels, a daily quota);
- `SpotlightSearchTool`, a first-party agentic RAG tool over the app's Core Spotlight index or files, with lexical and semantic search, pipeline stages, custom scoring stages and a compact output format for small contexts;
- `ToolCallingMode`;
- an Evaluations framework with result-coverage metrics.

No Apple sample uses guided generation to produce claim-level citations.

### Cited Findings
- **TN3193: RAG section.** Its steps are:
  - "Split your knowledge base into chunks, vectorize the chunks into embeddings, and store the result in a database."
  - "Gather a user query, vectorize it… retrieve the most relevant chunks."
  - "Feed the query and the most relevant chunks to the model."

  It suggests Core ML or NaturalLanguage for chunking and embedding models, and offline pre-vectorisation where possible. It adds: "RAG can be used as a tool call, or as a step you run before calling the on-device foundation model." — [primary, TN3193](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)
- **TN3193: context budget and tool use.**
  - "Apple's on-device foundation model has a context window of 4096 tokens per LanguageModelSession". A token is about 3–4 Latin characters, or about 1 character in CJK languages.
  - Tool definitions, schemas, tool I/O and responses all consume the window.
  - "Give the model a maximum of 3–5 tools… In the cases where the model should always have information from a tool, run the tool directly before you call the model and integrate the tool's output to the prompt directly."
  - Revision history: "2026-03-31 Updated with the new API introduced in… 26.4", "2025-10-06 First published".

  Source: [primary, TN3193](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)
- **"Managing the context window" article.** It repeats the 4,096-token figure and points to `tokenCount(for:)` and `contextSize`. When the context is exceeded, the framework throws `contextSizeExceeded` and you start a new session. It recommends:
  - map-reduce summarisation across sessions;
  - condensed transcripts (first plus last entry);
  - the Foundation Models Instruments template;
  - `@Guide(.maximumCount)` to bound generable arrays;
  - "Only use `maximumResponseTokens` to prevent verbose responses".

  Source: [primary, Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window)
- **`contextSize`.** It has been available since iOS 26 and is `@backDeployed(before: iOS 26.4…)`. "The context size represents the total number of tokens that can be used in a single session, including both input prompts and generated responses." — [primary, contextSize](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/contextsize)
- **WWDC26 session 241 ("What's new in the Foundation Models framework").**
  - A "new on-device model, rebuilt from the ground up… better at logic and tool calling".
  - The 26.4 context-size and token-count APIs are to be used "to adapt your app to the hardware it's running on".
  - The PCC model "has a 32,000 token context window" with reasoning.
  - PCC is "available with no cloud API costs to developers who have less than 2 million first time downloads".
  - New system tools: OCRTool, BarcodeReaderTool, and "a search tool powered by Spotlight for implementing fully local Retrieval-Augmented Generation… one of your most… requested features".
  - An Evaluations framework, the `fm` CLI and a Python SDK.

  Source: [primary, WWDC26 241 transcript](https://developer.apple.com/videos/play/wwdc2026/241/). The WWDC26 guide adds that the no-cost PCC offer applies to members of the App Store Small Business Program — [primary, WWDC26 Apple Intelligence guide](https://developer.apple.com/wwdc26/guides/apple-intelligence/)
- **PCC in the framework.**
  - `PrivateCloudComputeLanguageModel` is available on iOS, macOS, watchOS and visionOS 27 or later.
  - Apple's comparison table:

    | Capability | On-device | PCC |
    |---|---|---|
    | Context size | 4K | 32K |
    | Works offline | yes | no |
    | Usage limit | unlimited | limit per day |
    | Reasoning | not supported | light / moderate / deep |

  - The docs say "Start with the on-device model and evaluate it with the Evaluations framework". A `quotaUsage` API and a `quotaLimitReached` error exist, and apps should fall back to on-device if the network fails.

  Sources: [primary, Adding server-side intelligence with PCC](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute), [primary, PrivateCloudComputeLanguageModel](https://developer.apple.com/documentation/foundationmodels/privatecloudcomputelanguagemodel)
- **Framework scope in 2026.** The framework now "provides access to any large language model, like the on-device and Private Cloud Compute models". New topics include Dynamic profiles, a custom language-model provider (Core AI models), prompt attachments (images), and "Performance and evaluation" — [primary, Foundation Models overview](https://developer.apple.com/documentation/foundationmodels)
- **Tool calling (the retrieval hook).**
  - The model "calls the tool with additional arguments"; `Arguments` use guided generation. Tools let the model "Query entries from your app's database and reference them in its answer" and "ground responses in sources of truth that you provide".
  - New in 2026 is `ToolCallingMode` with `.allowed` (default), `.required` and `.disallowed`. With `.required` you must supply an exit condition, such as a DynamicProfile that switches to `.allowed` after the first call.

  Source: [primary, Expanding generation with tool calling](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling)
- **SpotlightSearchTool (iOS, iPadOS, macOS and visionOS 27).**
  - `let tool = SpotlightSearchTool(); LanguageModelSession(tools: [tool])`.
  - Sources are `CoreSpotlightSource` (the app's index) and `FileSource` (indexed files in the app's directories).
  - `fetchAttributes` controls what the model sees. A `ContactResolver` handles "I/me".
  - Guides are `complete`, `focused(_:)` (content domains: communications, documents, calendar, audio, visual media, items) and `dynamic(_:)`. `FormatLevel` is `.structured` or `.compact` ("Terse, line-oriented… Best for models with limited context").
  - "The default configuration… uses the `complete` option and Private Cloud Compute (PCC) models… if you configure it to use the on-device language model without providing a `focused(_:)` guide, Spotlight search exceeds the context window of the model and can't return results."
  - The model builds "a pipeline of work" (retrieve, count, score). Apps can add `CustomStage`s that emit `ScoredSearchableItem` (a caller-assigned relevance score); Apple's example is a recency boost.
  - Results stream to the app through `searchResults` as `SearchReply` values ("A set of search results with routing metadata for host app consumption").

  Sources: [primary, Making your indexed content available to Foundation Models](https://developer.apple.com/documentation/corespotlight/making-your-indexed-content-available-to-foundation-models), [primary, SpotlightSearchTool](https://developer.apple.com/documentation/corespotlight/spotlightsearchtool), [primary, FormatLevel](https://developer.apple.com/documentation/corespotlight/spotlightsearchtool/formatlevel), [primary, ContentDomain](https://developer.apple.com/documentation/corespotlight/spotlightsearchtool/contentdomain), [primary, searchResults](https://developer.apple.com/documentation/corespotlight/spotlightsearchtool/searchresults), [primary, SearchReply](https://developer.apple.com/documentation/corespotlight/spotlightsearchtool/searchreply), [primary, ScoredSearchableItem](https://developer.apple.com/documentation/corespotlight/scoredsearchableitem), [primary, FileSource](https://developer.apple.com/documentation/corespotlight/filesource)
- **WWDC26 session 246 ("LLM search using Core Spotlight").**
  - The tool's "trajectory" runs like this: the model generates a query, Spotlight executes it and returns "a description of the result set", and the model reasons and responds.
  - "some metadata in the Spotlight index, like text content and HTML, is stored in a highly-compact representation that can be searched, but not recovered in a way that a language model can read it". The fix is the index-delegate method `searchableItems(forIdentifiers:)`, which hydrates full items.
  - Capabilities range "from semantic search over text, to structured search over metadata, like dates, persons, locations". "On-device models have a more restricted model context size, so it's best to use focused guidance."
  - Each reply carries "a handy LLM-generated label".
  - Evaluation uses the Evaluations framework with a "result coverage" metric: expected item IDs per prompt, with seed samples expanded by Sample Generation APIs.

  Source: [primary, WWDC26 246 transcript](https://developer.apple.com/videos/play/wwdc2026/246/)
- **Apple sample "Searching indexed content with natural language"** (iOS 27, associated with WWDC26). It "runs searches on the on-device system language model" by default with the `focused()` guide. For "best search performance" it recommends PCC with the `complete` guide, and "creates a fresh session and tool for each search so every query starts with fresh context" — [primary, sample](https://developer.apple.com/documentation/corespotlight/searching-indexed-content-with-natural-language)
- **Apple on model limits.**
  - The on-device model should avoid basic math, creating code and logical reasoning. Tasks needing "extensive world-knowledge" should use guided generation or tool calling — [primary, Generating content and performing tasks](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)
  - "To generate accurate, hallucination-free responses, your prompt needs to be concise and specific". On-device few-shot works best with 2–15 simple examples, and a leading "reasoning field" is recommended in Generable types — [primary, Prompting an on-device foundation model](https://developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model)
- **Apple on evaluation.** Apple recommends combining rule-based checks, ground-truth comparison and "Model-based judgment… verify the judging model's assessment align with human judgment before relying on its scores". This works in Swift or the Python Foundation Models SDK — [primary, Evaluating prompts](https://developer.apple.com/documentation/foundationmodels/evaluating-prompts-to-measure-performance-and-improve-model-responses)
- **Apple WWDC25 sample.** "Adding intelligent app features with generative models" (iOS 26, WWDC25 session 259) shows guided generation (a `@Generable Itinerary`) and a custom points-of-interest tool, not document RAG — [primary, sample](https://developer.apple.com/documentation/foundationmodels/adding-intelligent-app-features-with-generative-models)
- **Third-party write-ups.** Posts describe SpotlightSearchTool as "local RAG with no embeddings pipeline, no vector store, and no server". A June 2026 post notes Apple docs still state 4,096 tokens on device, while sessions "hint at more on newer hardware" — [inferred (search summary), The Swift Dev](https://www.theswift.dev/posts/chat-with-your-apps-data-using-core-spotlight-spotlightsearchtool/), [inferred (search summary), Blake Crosley](https://blakecrosley.com/blog/on-device-ai-spotlight-media-ios-27), [inferred (search summary), Ivan Magda](https://ivanmagda.dev/posts/wwdc26-foundation-models-year-two/)

### Inferences
- **Apple endorses the app's shape.** App: its pipeline (own chunker, embedder, store and retrieval, with retrieved snippets injected into a 4K on-device session or a 32K PCC session) is the architecture Apple's TN3193 describes. TN3193 also says to run retrieval directly rather than as a tool when it is always needed, which matches an app that always retrieves.
- **SpotlightSearchTool as a baseline.** It is a new first-party baseline worth comparing against. It supplies lexical plus semantic retrieval, structured filters and model-planned multi-stage queries for free, and the default setup uses no custom embeddings.
  - It is less controllable: result text can be unrecoverable from the index without delegate hydration, and on-device use needs `focused` plus `compact` configuration.
  - Its default configuration relies on PCC models for query construction, which a strictly local-first product would have to override.
  - It returns item-level provenance (SearchReply items and labels), not claim-level citations.
- **Citations and structured output.** Apple gives no built-in citation or grounding primitive. Guided generation guarantees output structure: `@Generable` "provides strong guarantees that the model generates instances of your type". That could carry chunk IDs, but a well-formed ID list is not evidence of support; it has the same limit as Anthropic's "valid pointer" citations. Anthropic even disallows combining citations with structured outputs.
- **Hardware-dependent context.** Session 241's advice to adapt to "the hardware it's running on" via `contextSize` suggests the on-device window may no longer be a fixed 4,096 on every device in iOS 27. Apple's docs still say 4,096, so apps should read `contextSize` at runtime rather than hard-code it.

### Gaps
- I found no Apple sample or public write-up that uses guided generation to produce claim-level citations over retrieved chunks.
- I found no Apple statement of which embedding model or retrieval method backs Spotlight semantic search, or of its ranking quality.
- The iOS 27 on-device model's context size per device is not documented; the docs still say 4,096.
- I did not read the transcripts of "Meet the Evaluations framework" and "Create robust evaluations for agentic apps" (WWDC26).
- Third-party SpotlightSearchTool posts were egress-blocked.

## 5. Convergent patterns the field treats as baseline in 2026 (only what the evidence above supports)

### Takeaway
The evidence supports a baseline of nine parts, each detailed below:
- layout-aware parsing;
- a few-hundred-token chunk with small or no overlap;
- a swappable small dense embedder;
- hybrid lexical plus dense retrieval, fused by RRF or weights;
- an optional cross-encoder rerank over a wider candidate pool;
- a small top-k handed to the model with a relevance floor;
- numbered citations linking to the source passage;
- an explicit "not found in your sources" path;
- offline faithfulness evaluation.

Runtime claim-level verification and calibrated confidence labels are not baseline in open source. They appear as managed cloud APIs or a few product features, and when present they are check-backed and multi-state.

### Cited Findings
- **Layout-aware, swappable parsing** (DeepDoc, Docling, MinerU, OCR or VLM): RAGFlow (DeepDOC default, MinerU and Docling since 2025-10), Kotaemon (Docling, Azure DI, Adobe, PaddleOCR), PrivateGPT (Docling default), Open WebUI (Docling, Tika, Document Intelligence, Mistral OCR, PaddleOCR-VL), R2R (zerox, OCR, VLM), and LlamaIndex (pivoted to LlamaParse and LiteParse) — [primary, RAGFlow naive.py](https://github.com/infiniflow/ragflow/blob/main/rag/app/naive.py), [primary, Kotaemon README](https://github.com/Cinnamon/kotaemon/blob/main/README.md), [primary, PrivateGPT settings.yaml](https://github.com/zylon-ai/private-gpt/blob/main/settings.yaml), [primary, Open WebUI config.py](https://github.com/open-webui/open-webui/blob/main/backend/open_webui/config.py), [primary, R2R r2r.toml](https://github.com/SciPhi-AI/R2R/blob/main/py/r2r/r2r.toml), [primary, LlamaIndex README](https://github.com/run-llama/llama_index/blob/main/README.md)
- **Chunks of about 200 words to 512 tokens, with overlap usually 0–20 tokens or about 10%.** Haystack uses 200 words / 0; Khoj 256 tokens / 0; Onyx 512 / 0; RAGFlow 512; Dify 500 / 50; Open WebUI 1,000 characters / 100; AnythingLLM 1,000 characters / 20. Generic frameworks default larger: LlamaIndex 1,024 / 200, Kotaemon 1,024 / 20. Fixed-size chunking is not beaten consistently by semantic chunking (NAACL 2025) — sources in §1, plus [inferred (search summary), ACL Anthology](https://aclanthology.org/2025.findings-naacl.114/)
- **Small dense embedder by default, always swappable.** all-MiniLM-L6-v2 in txtai, Open WebUI and AnythingLLM; gte-small in Khoj; nomic-embed-text-v1 in Onyx; all-mpnet-base-v2 in Haystack; OpenAI small or ada in R2R and LlamaIndex. On Apple platforms, bge, nomic, Qwen3-Embedding and LFM2.5 are available through MLXEmbedders — sources in §1 and §3
- **Hybrid lexical plus dense retrieval, available almost everywhere and default-on in RAGFlow, Kotaemon and Onyx.** Fusion is either RRF (LlamaIndex k=60, R2R k=50, the Haystack joiner option, PocketMind k=60) or weighted (RAGFlow 0.7/0.3, Onyx alpha 0.5, Open WebUI BM25 weight 0.5, VecturaKit 0.5). Apple's Core Spotlight does both "lexical and semantic" search — sources in §1 and §3, plus [primary, CSUserQuery](https://developer.apple.com/documentation/corespotlight/csuserquery)
- **Cross-encoder rerank as an optional second stage over a wider candidate pool.** RAGFlow's `retrieval()` considers 64 rerank candidates by default and dialogs keep top_n 6; AnythingLLM reranks 10–50 candidates to a topN of 4; Onyx retrieves 50 hits and feeds 25. Default rerankers are ms-marco-MiniLM-L-6-v2 (Haystack, AnythingLLM) or mxbai-rerank-xsmall-v1 (Khoj, Onyx's suggestion). Reranking is off by default in RAGFlow, Dify, Open WebUI, AnythingLLM and Onyx — sources in §1
- **Small top-k to the generator plus a relevance floor.** Top-k is 2 in LlamaIndex, 3 in txtai and Open WebUI, 4 in Dify and AnythingLLM, and 6 in RAGFlow. Floors are 0.2 in RAGFlow, 0.25 in AnythingLLM, 0.18 in Khoj, and a cosine floor in PocketMind. The exceptions are Open WebUI (floor 0.0) and Dify (threshold disabled). LlamaIndex's `DEFAULT_CONTEXT_WINDOW` of 3,900 tokens is close to Apple's 4,096 on-device budget — sources in §1, [primary, LlamaIndex constants.py](https://github.com/run-llama/llama_index/blob/main/llama-index-core/llama_index/core/constants.py), [primary, TN3193](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)
- **Numbered inline citations mapped to retrieved chunks and clickable to the passage.**
  - Open source: LlamaIndex, Haystack, Onyx, Open WebUI, Kotaemon and RAGFlow.
  - Products: NotebookLM, M365 Copilot, Glean and Perplexity.
  - Sources: §1 and §2.
  - These citations are either model-emitted markers or similarity-attached (RAGFlow, txtai). Anthropic's API guarantees only that the pointers are valid — [primary, Claude docs: Citations](https://docs.claude.com/en/docs/build-with-claude/citations)
- **Explicit "not found" behaviour.** RAGFlow's required sentence and `empty_response`; AnythingLLM's query-mode refusal; LlamaIndex's "If none of the sources are helpful, you should indicate that"; Kotaemon's "No evidence found."; NotebookLM "says so" [inferred]. The counter-example is Open WebUI's template, which allows answering from the model's own knowledge — §1 and §2 sources
- **Offline evaluation of faithfulness and retrieval.** LlamaIndex FaithfulnessEvaluator (YES/NO); Haystack FaithfulnessEvaluator (statement-level fraction); Apple's Evaluations framework with result coverage and model-based judgment validated against humans; Dify observability integrations — [primary, LlamaIndex faithfulness.py](https://github.com/run-llama/llama_index/blob/main/llama-index-core/llama_index/core/evaluation/faithfulness.py), [primary, Haystack faithfulness.py](https://github.com/deepset-ai/haystack/blob/main/haystack/components/evaluators/faithfulness.py), [primary, WWDC26 246](https://developer.apple.com/videos/play/wwdc2026/246/), [primary, Apple: Evaluating prompts](https://developer.apple.com/documentation/foundationmodels/evaluating-prompts-to-measure-performance-and-improve-model-responses)
- **Agentic, tool-based retrieval as a growing layer on top of the pipeline.** R2R's agent tools, Onyx's "Agentic RAG", RAGFlow's agents and MCP, Haystack's Agents, PrivateGPT's "agentic RAG", and Apple's SpotlightSearchTool, where the model writes queries and plans pipeline stages — §1 and §4 sources
- **Not baseline, found only as managed services or single products:**
  - runtime claim-level grounding checks (Google check-grounding, Azure groundedness, AWS contextual grounding);
  - tri-state claim highlighting (Gemini);
  - runtime relevance warnings (Kotaemon).

  Sources: §2.

### Inferences
- **App against this baseline.** Measured against the checklist, its ingestion, storage, hybrid-RRF retrieval, reranking stage, citations and 4K/32K model routing are current practice, not behind it. Its weakest components against the field are replaceable parts, not the architecture: the embedder choice (MiniLM-L6-v2 while quality-focused systems default to bge, nomic or gte) and the reranker size (TinyBERT-L2 is below every default observed).
- **Where the app departs from the field.** The departures are on the answer side: a regex shortcut that can replace the model's answer, which no surveyed system does, and a default-positive "Verified" label, which contradicts both the field and Apple's HIG. The honest baseline is the one set by RAGFlow, AnythingLLM and Kotaemon: explicit not-found text, check-backed labels with a "not checked" state, and passage-linked citations.
- **Apple's SpotlightSearchTool** is a platform-level alternative retrieval baseline for iOS and macOS 27. It is worth benchmarking against, especially for metadata and date-style questions that plain chunk retrieval handles poorly.

### Gaps
- Star counts, push dates and defaults establish what systems ship, not what works best. I found no single 2025–2026 benchmark comparing these systems' default pipelines end to end.
- Default values change quickly: several, including RAGFlow's chunk size and Onyx's encoder, differ from older versions. All figures above are as of main on 2026-09-26.
