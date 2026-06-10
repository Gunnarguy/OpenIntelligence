# Architecture

OpenIntelligence is an Apple-native document intelligence product built around a SwiftUI app shell and a retrieval-oriented document engine.

The codebase keeps the engineering substance visible: document ingestion, chunking, indexing, retrieval, grounded answer generation, citation handling, confidence surfaces, and diagnostics. The public product story is local-first, with Apple-managed cloud capacity only where the platform explicitly provides it.

## Major Areas

- `OpenIntelligence/App`: application entry points and top-level composition.
- `OpenIntelligence/Features`: user-facing document, chat, settings, diagnostics, telemetry, camera, onboarding, and billing surfaces.
- `OpenIntelligence/Services/Document`: extraction, parsing, analysis, chunking, classification, and document processing.
- `OpenIntelligence/Services/RAG`: retrieval, context packing, orchestration, verification, source-only answering, confidence, and safety checks.
- `OpenIntelligence/Services/Embedding`: embedding providers and local embedding optimization experiments.
- `OpenIntelligence/Services/Storage`: full-text and local storage services.
- `OpenIntelligence/Services/VectorStore`: vector database abstractions and local vector search experiments.
- `OpenIntelligence/Services/AIPlatform/AppleFoundationModels`: monolithic split managing Apple Foundation Model session factory, route policies, dynamic profiles, prompt compilation, and token budgets.
- `OpenIntelligence/Services/AIPlatform/CoreAI`: core AI local execution engine, local model registry, and specialized silicon model runtimes (embedding, cross-encoder reranking).
- `OpenIntelligence/Services/Evaluation`: formal evaluation suite containing the RAG runner, JSONL datasets loader, report writer, and Apple evaluations bridge (for `fm CLI` compatibility).
- `OpenIntelligence/SDK`: experimental source package boundary for the engine-facing API.

## Data Flow (End-to-End Pipeline)

The OpenIntelligence execution lifecycle consists of a 29-step pipeline split into import-time ingestion and query-time response generation. It features adaptive runtime scaling, dynamic model routing, and automated validation.

### Ingestion Pipeline (Steps 1–6)
1. **Parse**: Files enter through Apple document workflows. Content is parsed using type-specific extractors. For PDFs, the system dynamically scales rendering (5x–6x) and applies [LayoutAwareExtractor](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/Document/Processing/LayoutAwareExtractor.swift) or Vision OCR when a native text layer is missing.
2. **Semantic Chunking**: [SemanticChunker](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/Document/Chunking/SemanticChunker.swift) splits text into retrievable units (typically $\le 310$ words) while identifying document structures like sections, lists, and tables.
3. **Entity Extraction**: The ingestion engine runs `NLTagger` Named Entity Recognition (NER) to extract key entities, formatting them in PascalCase to build the entity index.
4. **Token Validation**: Chunks are validated using local tokenizers (e.g. `BertTokenizer` $\le 510$ tokens) to guarantee compatibility with underlying embedding models.
5. **Embedding Generation**: Core AI runs dense embedding models (e.g., 384-dimensional MiniLM) using hardware-accelerated Apple Silicon libraries.
6. **Corpus Storage**: Text and layout metadata are indexed into a shared SQLite FTS5 database (using `container_id` isolation), and dense vectors are written into [BNNSVectorDatabase](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift) or Vectura/HNSW backends.

### Query-to-Response Pipeline (23 Steps)

#### Phase 1: Query Understanding & Routing (Steps 0–2.5)
* **Step 0: Corpus Analysis**: Resolves terminology by checking cached vocabulary.
* **Step 1: Query Understanding**: Resolves pronouns and extracts entities via `NLTagger` NER.
* **Step 1.5: Query Expansion**: Expands the query using corpus and container vocabularies (e.g., HyDE, synonyms).
* **Step 1.6: Intent Classification**: Classifies user intent (lookup, procedure, compare, or summarize) to select the optimal answering lane.
* **Step 2: Query Embedding**: Generates a 384-dimensional query vector.
* **Step 2.5: Dynamic Route Resolution**:
  The system decides the routing policy before retrieval based on user preference, hardware, and context size:
  * **On-Device Default**: Queries in standard quality mode default to local execution via `SystemLanguageModel.default`. This is subject to a 4,096-token context window limit.
  * **PCC Escalation**: If the context/history size exceeds 4,096 tokens, or if the user selects **Deep Think** or **Maximum** quality modes, the policy elevates the query to `PrivateCloudComputeLanguageModel` in Apple's secure Private Cloud Compute (PCC), supporting a larger 32K token context window.

#### Phase 2: Evidence Retrieval & Packing (Steps 3–5)
* **Step 3: Hybrid Search**: Runs a fused search merging vector similarity scores and FTS5 BM25 lexical scores using Reciprocal Rank Fusion (RRF).
* **Step 4: Cross-Encoder Rerank**: Scores candidate chunks using a local Core ML TinyBERT reranker.
* **Step 4.3–4.5: Filtering & Diversity**: Filters low-confidence results, ensures multi-document representation (source diversity), and applies MMR diversification ($\lambda = 0.6$).
* **Step 4.6–4.7: Context Expansion & Compression**: Expands matching chunks to include neighboring sibling chunks using [ParentDocumentService](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/RAG/Retrieval/ParentDocumentService.swift), then filters out query-irrelevant sentences using [ContextualCompressionService](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/Query/Enhancement/ContextualCompressionService.swift) to conserve the token budget.
* **Step 4.9: Graph Context Packing**: Packs related entity clusters and L1 summaries using a token-budget boundary.
* **Step 5: Context Assembly**: Arranges the surviving evidence using a **Lost-in-Middle** reordering algorithm (placing high-relevance chunks at the start and end of the prompt window to maximize LLM attention).

#### Phase 3: Generation & Safety Verification (Steps 5.9–10)
* **Step 5.9–5.10: Extractive Overrides**: Simple lookup queries and summaries bypass standard generation, returning direct high-precision text extractions early to eliminate hallucination risk.
* **Step 6: LLM Generation**: Invokes the resolved Apple foundation model (either on-device or PCC) using `LanguageModelSession` with the packed evidence context.
* **Step 6.5: Response Formatting**: Regulates and fixes Markdown layout issues.
* **Step 7: Quality Assessment**: Evaluates the response's semantic alignment with the retrieved context.
* **Step 7.5: Verification Gates**: Routes the generated response through **Verification Gates A–I** to analyze domain isolation, completeness, and check for hallucinations.
* **Step 8: Package Results**: Bundles the response, citations, and system diagnostics.
* **Step 8.1: Calibrated Confidence**: Computes final calibrated confidence scores using Platt scaling.
* **Step 9: Response Metadata**: Compiles final processing stats, tokens used, latency, and resolved routing paths.
* **Step 10: Markdown Rendering**: Formats the response on the UI using a custom block-level parser.

## Continuous Evaluation and Quality Gates

To prevent regressions, the entire RAG pipeline is validated against test datasets using the `Evaluation` framework. 

* **Test Suites**: Evaluations run JSONL test files containing ground-truth chunks and expected answers.
* **Compatibility**: The [AppleEvaluationsBridge](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/Evaluation/AppleEvaluationsBridge.swift) bridges evaluation data to Apple's native command-line testing suite (`fm CLI`).
* **Target Quality Gates**:
  * **Retrieval Recall@5**: $\ge 0.85$
  * **Citation Precision**: $\ge 0.90$
  * **Unsupported-claim Rate**: $\le 0.05$ (hallucination detection)
  * **Correct Abstention Rate**: $\ge 0.85$ (out-of-scope or ungrounded queries)

## Design Goals

- Keep user files under user-controlled workflows.
- Keep library or workspace boundaries visible in retrieval.
- Prefer source-backed answers over unconstrained model output.
- Make uncertainty inspectable instead of hiding it behind polished prose.
- Preserve enough diagnostics for engineering iteration.

## Package Boundary

The repository includes `Package.swift` and an `OpenIntelligenceEngine` target. That package boundary is experimental. It is useful for understanding how the document intelligence core can be separated from the app shell, but it should not be described as a finished SDK or production-ready handoff.
