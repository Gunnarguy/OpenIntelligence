# Research Papers Reference Sheet (OpenIntelligence Core Foundations)

This document is the exhaustive engineering-academic bibliography for **OpenIntelligence**. It maps every core search, retrieval, layout extraction, sampling, and Apple Silicon execution feature of the application directly to its theoretical foundations, research papers, and technical specifications.

---

## Part 1: Search, Retrieval, & Reranking Foundations

### 1. BM25 (Best Matching 25) Okapi Relevance
*   **Paper/Resource**: *The Probabilistic Relevance Framework: BM25 and Beyond* (Stephen Robertson and Hugo Zaragoza)
*   **Link**: [Robertson & Zaragoza (2009)](https://www.nowpublishers.com/article/Details/INR-019)
*   **Core Concept**: A probabilistic term-frequency model that ranks documents based on the query terms appearing in each document, applying term-frequency saturation and document-length normalization.
*   **Literal Codebase Mapping**: 
    - [SQLiteFullTextService.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/Storage/SQLiteFullTextService.swift): Configures the FTS5 virtual table using Okapi BM25 rankings.
    - [HybridSearchService.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift): Triggers tokenized lexical searches using BM25 weights.

### 2. Reciprocal Rank Fusion (RRF)
*   **Paper**: *Reciprocal Rank Fusion out-performs Joint Clean and Individual Runs* (Cormack et al., 2009)
*   **Link**: [Cormack et al. (ACM)](https://dl.acm.org/doi/10.1145/1571941.1572114)
*   **Core Concept**: A rank-fusion algorithm that combines rankings from multiple retrieval systems (lexical and vector) without needing score calibration. Chunks are scored based on the inverse of their rank position plus a constant parameter $k$ (typically 60).
*   **Literal Codebase Mapping**:
    - [HybridSearchService.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift): Implements `reciprocalRankFusion()` to merge FTS5 lexical ranks and BNNS vector ranks.

### 3. Maximal Marginal Relevance (MMR) Reranking
*   **Paper**: *The Use of MMR in Multi-Document Summarization* (Carbonell and Goldstein, 1998)
*   **Link**: [Carbonell & Goldstein (ACM)](https://dl.acm.org/doi/10.1145/290941.291025)
*   **Core Concept**: A similarity/diversity trade-off algorithm that ranks retrieved chunks by maximizing similarity to the query while minimizing similarity to already selected chunks (using a parameter $\lambda$).
*   **Literal Codebase Mapping**:
    - [HybridSearchService.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift): Implements `performMMRReranking()` to filter out redundant vector chunks.

### 4. HyDE (Hypothetical Document Embeddings)
*   **Paper**: *Precise Zero-Shot Dense Retrieval without Relevance Labels* (Gao et al., 2022)
*   **Link**: [arXiv:2212.10496](https://arxiv.org/abs/2212.10496)
*   **Core Concept**: A query expansion technique where the LLM generates a hypothetical, ungrounded response to the user query. This hypothetical answer is embedded and used to run the vector search, mapping "answer-to-answer" space.
*   **Literal Codebase Mapping**:
    - [HyDEService.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/Query/Rewriting/HyDEService.swift): Generates hypothetical drafts.
    - [QueryRuntimeCoordinator.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/RAG/Orchestration/QueryRuntimeCoordinator.swift): Coordinates HyDE query rewriting before submitting to the retrieval pipeline.

### 5. Parent Document Expansion & Sibling Chunking
*   **Methodology**: *Parent Document Retrieval* (Industry Best Practices / LangChain Architecture)
*   **Core Concept**: Divides documents into small child chunks for embedding/vector search (improving search resolution) but retrieves and feeds the larger parent or adjacent sibling chunks to the LLM context window (improving reading context).
*   **Literal Codebase Mapping**:
    - [ParentDocumentService.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/RAG/Retrieval/ParentDocumentService.swift): Expands retrieved chunk segments to include parent or surrounding sibling blocks from FTS5.

### 6. Sentence-BERT (Dense Embedding Vectors)
*   **Paper**: *Sentence-BERT: Sentence Embeddings using Siamese BERT-Networks* (Reimers and Gurevych, 2019)
*   **Link**: [arXiv:1908.10084](https://arxiv.org/abs/1908.10084)
*   **Core Concept**: Fine-tunes BERT-style transformers in a Siamese network structure to generate dense vectors where cosine similarity maps semantic closeness, making large-scale semantic search computationally feasible.
*   **Literal Codebase Mapping**:
    - [EmbeddingService.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/Research/COREML_METAL_ON_DEVICE_AI.md): Generates 384-dimensional dense vectors.
    - [CoreMLSentenceEmbeddingProvider.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/Embedding/Providers/CoreAISentenceEmbeddingProvider.swift): Runs the local Sentence-Transformer model (`EmbeddingModel.mlpackage`) on older OS configurations.

---

## Part 2: Context Engineering & Document Structure

### 7. RAPTOR: Tree-Organized Hierarchical Summaries
*   **Paper**: *RAPTOR: Recursive Abstractive Processing for Tree-Organized Retrieval* (Sarthi et al., Stanford, 2024)
*   **Link**: [arXiv:2401.18059](https://arxiv.org/abs/2401.18059)
*   **Core Concept**: Recursively clusters and summarizes document chunks to build a hierarchical summary tree. Retrieves high-level abstract nodes for global corpus queries and leaf nodes for local lookups.
*   **Literal Codebase Mapping**:
    - [RAPTORSummaryRouter.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/RAG/Retrieval/RAPTORSummaryRouter.swift): Routes global, summary-oriented queries to summary tree parent nodes.
    - [SemanticChunker.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/Document/Chunking/SemanticChunker.swift): Generates document-level summary blocks preserved as level-1 nodes.

### 8. Contextual Prefixing (Contextual Retrieval)
*   **Technical Report**: *Contextual Retrieval* (Anthropic Research, September 2024)
*   **Link**: [Anthropic Blog](https://www.anthropic.com/research/contextual-retrieval)
*   **Core Concept**: Appending document-level and section-level context labels to text segments before vector embedding, ensuring the chunk preserves high-level semantics even when searched in isolation.
*   **Literal Codebase Mapping**:
    - [ContentTaggingService.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/Document/Chunking/ContentTaggingService.swift): Extracts document and section context prefixes.
    - [SemanticChunker.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/Document/Chunking/SemanticChunker.swift): Prepends `[Document: name | Section: title]` tokens to the raw string before generating the embeddings.

### 9. TableRAG: Heterogeneous Document Reasoning
*   **Paper**: *TableRAG: A RAG Framework for Heterogeneous Document Reasoning* (2025)
*   **Link**: [arXiv:2506.10380](https://arxiv.org/abs/2506.10380)
*   **Core Concept**: Flattening structural tables into raw text breaks layout relationships (columns/rows). TableRAG parses table coordinates explicitly and groups cell structures as atomic, non-split RAG chunks.
*   **Literal Codebase Mapping**:
    - [StructuredDocumentParser.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/Document/Processing/StructuredDocumentParser.swift): Uses Vision OCR to parse column-row structures, converting tables into row-column grids preserved as unified `TableData` chunks.
    - [DocumentProcessor.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift): Prevents table chunks from being split by the standard text chunker.

### 10. Cache-Augmented Generation (CAG)
*   **Paper**: *Don't Do RAG: When Cache-Augmented Generation is All You Need for Knowledge Tasks* (2024)
*   **Link**: [arXiv:2412.15605](https://arxiv.org/abs/2412.15605)
*   **Core Concept**: Storing small static knowledge bases directly inside the model's KV-cache, bypassing the vector database query steps entirely.
*   **Role in OpenIntelligence**: Serves as a reference model for small, static document caching in `CAG_AND_CONTEXT_ENGINEERING_2024_2026.md`.

---

## Part 3: Agentic Feedback Loops & Critique

### 11. COMPILOT: LLM-Guided Loop Scheduling & Verification
*   **Paper**: *Agentic Auto-Scheduling: An Experimental Study of LLM-Guided Loop Optimization* (Merouani et al., NYU Abu Dhabi, December 2025)
*   **Link**: [arXiv:2511.00592](https://arxiv.org/abs/2511.00592)
*   **Core Concept**: An LLM agent iteratively proposes code scheduling transformations to a compiler, which runs correctness checks (legality/safety) and performance execution checks, feeding these outcomes back into the LLM's prompt.
*   **Role in OpenIntelligence**: Inspires the multi-hop reasoning loops in `Deep Think` and `Maximum` quality modes (`QueryRuntimeCoordinator.swift` & `RAGEngine.swift`). The engine queries the local SLM, runs the response through verification gates (citation calibration, contradiction checking), and feeds the failure diagnostics back to the SLM in iterative retrieval sessions.

### 12. Self-RAG (Self-Reflection and Critiquing)
*   **Paper**: *Self-RAG: Learning to Retrieve, Generate, and Critique through Self-Reflection* (2023)
*   **Link**: [arXiv:2310.11511](https://arxiv.org/abs/2310.11511)
*   **Core Concept**: LLM self-reflection and grading where the generation is critiqued dynamically to assess if the output is fully supported by the retrieved facts.
*   **Literal Codebase Mapping**:
    - [ConfidenceCalibrationService.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/RAG/Safety/ConfidenceCalibrationService.swift): Generates self-reflective grading matrices for SLM output.

### 13. Corrective RAG (CRAG)
*   **Paper**: *Corrective Retrieval Augmented Generation* (2024)
*   **Link**: [arXiv:2401.15884](https://arxiv.org/abs/2401.15884)
*   **Core Concept**: Uses a retrieval quality evaluator to determine if retrieved vector segments are relevant, executing corrective actions (such as abstractive summaries or fallback modes) if similarity bounds fail.
*   **Literal Codebase Mapping**:
    - [VerificationGateService.swift (in target/targets)](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/RAG/Safety/ConfidenceCalibrationService.swift): Runs domain checks to abort or trigger corrective fallbacks.

### 14. FaithfulRAG: Fact-Level Conflict Modeling
*   **Paper**: *FaithfulRAG: Fact-Level Conflict Modeling for Context-Faithful RAG* (2025)
*   **Link**: [arXiv:2506.08938](https://arxiv.org/abs/2506.08938)
*   **Core Concept**: Isolates and scores fact-level conflicts between the retrieved context and generated response, enforcing strict source-only answer policies.
*   **Literal Codebase Mapping**:
    - [ConfidenceCalibrationService.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/RAG/Safety/ConfidenceCalibrationService.swift): Implements fact-conflict parsing to label answers as `[Needs Verification]` or source-locked.

---

## Part 4: LLM Decoding & Sampling Theory

### 15. Top-P (Nucleus Sampling)
*   **Paper**: *The Curious Case of Neural Text Degeneration* (Holtzman et al., 2019)
*   **Link**: [arXiv:1904.09751](https://arxiv.org/abs/1904.09751)
*   **Core Concept**: Selects tokens from a dynamic vocabulary subset whose cumulative probability exceeds parameter $p$ (typically 0.9), preventing repetitive loops and ensuring lexical diversity.
*   **Literal Codebase Mapping**:
    - `TopPLogitsWarper.swift` inside `swift-transformers`: Filters the logits output of on-device foundation model runs.

### 16. Repetition Penalty
*   **Paper**: *CTRL: A Conditional Transformer Language Model for Controllable Generation* (Keskar et al., 2019)
*   **Link**: [arXiv:1909.05858](https://arxiv.org/abs/1909.05858)
*   **Core Concept**: Penalizes logits of tokens that have already been generated in the active session by dividing them by a penalty parameter (typically 1.1 - 1.2).
*   **Literal Codebase Mapping**:
    - `RepetitionPenaltyLogitsProcessor.swift` inside `swift-transformers`: Applies penalties to the logits vector.

### 17. DFA-Guided Generation (JSON Grammars)
*   **Paper**: *Efficient Guided Generation for Large Language Models* (Willard and Louf, 2023)
*   **Link**: [arXiv:2307.09702](https://arxiv.org/abs/2307.09702)
*   **Core Concept**: Modifies the output logit distribution at each decoding token step to force compliance with a formal grammar or regular expression, guaranteeing structurally valid outputs (e.g., JSON or Swift schemas).
*   **Literal Codebase Mapping**:
    - Apple's Guided Generation API (`LanguageModelSession.outputFormat = .json(schema: ...)`), integrated within `FoundationModelStructuredGenerator.swift`.

---

## Part 5: Apple Silicon Execution & Security

### 18. Apple Intelligence Foundation Language Models
*   **Technical Report**: *Introducing Apple Foundation Models* / *Apple Intelligence Foundation Language Models Technical Report* (Apple, August 2025)
*   **Link**: [arXiv:2507.13575](https://arxiv.org/abs/2507.13575)
*   **Core Concept**: Apple's 3B and larger server-based models using quantization-aware training, low-latency NAND Flash paging, and secured cloud enclaves.
*   **Literal Codebase Mapping**:
    - [FoundationModelSessionFactory.swift (in target/targets)](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/Engineering/APPLE_MODELS.md): Sets up model session configurations.
    - [CoreAISentenceEmbeddingProvider.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/Embedding/Providers/CoreAISentenceEmbeddingProvider.swift): Coordinates embedding execution targets on local Neural Engines.

### **19. Apple Silicon Unified Memory Acceleration & BNNS (Accelerate)**
*   **Technical Resource**: *Basic Neural Network Subroutines (BNNS) & Accelerate Framework* (Apple Developer Documentation)
*   **Link**: [Apple Developer - BNNS](https://developer.apple.com/documentation/accelerate/bnns)
*   **Core Concept**: Zero-copy matrix multiplication and SIMD operations on unified memory architectures.
*   **Literal Codebase Mapping**:
    - [EmbeddingService.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/Research/COREML_METAL_ON_DEVICE_AI.md): Resolves local sentence embedding targets.
    - [BNNSVectorDatabase.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift): Leverages memory-mapped vectors and Accelerate vDSP dot products.

### 20. Apple Developer Technote TN3193
*   **Technical Note**: *TN3193: Managing the on-device foundation model's context window* (Apple Developer Technotes, 2025)
*   **Link**: [TN3193 Technote](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)
*   **Core Concept**: Hard bounds for 4K on-device token context budgets, and why tool schema sizes must be strictly budgeted.
*   **Literal Codebase Mapping**:
    - [LLMService.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/Engineering/RAG_TECHNICAL.md): Enforces 4096-token session budgets.
    - [FoundationModelPromptCompiler.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/Engineering/RAG_TECHNICAL.md): Compresses prompt structures to fit context limits.

### 21. Private Cloud Compute (PCC) Security
*   **Technical Resource**: *Private Cloud Compute security and privacy architecture* (Apple Security, 2024-2026)
*   **Link**: [Apple Security - PCC](https://security.apple.com/blog/private-cloud-compute/)
*   **Core Concept**: Secure, stateless enclaved processing for LLM workloads exceeding local ANE limits, with end-to-end encryption.
*   **Literal Codebase Mapping**:
    - [FoundationModelRoutePolicy.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/Engineering/PRIVATE_CLOUD_COMPUTE.md): Routes queries to PCC enclaves (`.privateCloudCompute`) during Maximum mode.

### 22. Siri App Intents SSU (Semantic Schema Understanding)
*   **Technical Resource**: *App Intents and Siri semantic layers* (Apple Developer Documentation, 2025-2026)
*   **Link**: [Apple Developer - App Intents](https://developer.apple.com/documentation/appintents)
*   **Core Concept**: Registers app entities and intents directly to the Siri NLU training compiler, allowing hands-free voice triggers to resolve parameters in-process.
*   **Literal Codebase Mapping**:
    - [RAGAppIntents.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/Agentic/RAGAppIntents.swift) & [ScreenAwarenessIntents.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/Agentic/ScreenAwarenessIntents.swift): Register entities (`OILibraryEntity`, `OIDocumentEntity`) and Intents.

### 23. RAGChecker: Quantitative Evaluation
*   **Paper**: *RAGChecker: A Fine-grained Framework for Diagnosing Retrieval-Augmented Generation* (2024)
*   **Link**: [arXiv:2408.08067](https://arxiv.org/abs/2408.08067)
*   **Core Concept**: Evaluation loops for measuring RAG pipeline accuracy using citation precision and hallucination rates.
*   **Literal Codebase Mapping**:
    - [RAGEvalRunner.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/RAG/Evaluations/RAGEvalRunner.swift): Evaluates dataset scores dynamically.

---

## Part 6: Core NLP & Spatial Algorithms

### 24. Porter Stemming / Snowball Stemmer
*   **Paper/Resource**: *An Algorithm for Suffix Stripping* (Martin Porter, 1980)
*   **Link**: [Porter Stemmer (1980)](https://tartarus.org/martin/PorterStemmer/)
*   **Core Concept**: A rule-based algorithm that strips suffixes from English words (e.g., mapping plural "documents" and singular "document" to the root stem "document") to improve lexical retrieval recall.
*   **Literal Codebase Mapping**:
    - Integrated directly in SQLite FTS5 index stemmer triggers inside [SQLiteFullTextService.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/Storage/SQLiteFullTextService.swift).

### 25. DBSCAN Bounding Box Spatial Clustering (Layout Reconstruction)
*   **Paper**: *A Density-Based Algorithm for Discovering Clusters in Large Spatial Databases with Noise* (Ester et al., 1996)
*   **Core Concept**: Groups spatial points (in this case, word bounding boxes from OCR) based on local density thresholds (epsilon horizontal and vertical gaps) to cluster text characters into unified lines and columns.
*   **Literal Codebase Mapping**:
    - [LayoutAwareExtractor.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/Document/Processing/LayoutAwareExtractor.swift): Groups text line bounding boxes spatially to reconstruct paragraphs.
    - [StructuredDocumentParser.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/Document/Processing/StructuredDocumentParser.swift): Identifies tabular grid bounds based on word coordinates intersection matrices.

---

## Part 7: 3D Telemetry & Dimension Reduction

### 26. t-SNE (t-Distributed Stochastic Neighbor Embedding)
*   **Paper**: *Visualizing Data using t-SNE* (van der Maaten and Hinton, 2008)
*   **Link**: [van der Maaten & Hinton (JMLR)](https://www.jmlr.org/papers/volume9/vandermaaten08a/vandermaaten08a.pdf)
*   **Core Concept**: A non-linear dimensionality reduction technique that maps high-dimensional vectors to a lower-dimensional space (2D/3D) by converting Euclidean distances between data points into conditional probabilities that represent similarities.
*   **Literal Codebase Mapping**:
    - [ProjectionService.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/Infrastructure/Presentation/ProjectionService.swift): Implements `tsne3D()`, utilizing adaptive iterations and sparse $k$-NN matrices.
    - [AdaptiveVisualizationsView.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Features/Telemetry/Visualizations/AdaptiveVisualizationsView.swift): Renders the interactive 3D point cloud via `CompactAtlasSceneView` and `Fullscreen3DAtlasView`.

### 27. UMAP (Uniform Manifold Approximation and Projection)
*   **Paper**: *UMAP: Uniform Manifold Approximation and Projection for Dimension Reduction* (McInnes et al., 2018)
*   **Link**: [arXiv:1802.03426](https://arxiv.org/abs/1802.03426)
*   **Core Concept**: A dimension reduction technique based on manifold learning and fuzzy simplicial sets representing local connectivity, optimizing low-dimensional layouts via cross-entropy minimization.
*   **Literal Codebase Mapping**:
    - [ProjectionService.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/Infrastructure/Presentation/ProjectionService.swift): Implements `umap3D()` including binary searches for local connectivity ($\sigma$) and fuzzy membership alignments.
    - [AdaptiveVisualizationsView.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Features/Telemetry/Visualizations/AdaptiveVisualizationsView.swift): Feeds UMAP coordinates to SceneKit spatial layouts.

### 28. Principal Component Analysis (PCA) Power Iteration
*   **Paper/Resource**: *Finding Structure with Randomness: Probabilistic Algorithms for Constructing Approximate Matrix Decompositions* (Halko et al., 2011)
*   **Link**: [arXiv:0909.4061](https://arxiv.org/abs/0909.4061)
*   **Core Concept**: Computes orthogonal axes of maximum variance (eigenvectors of the covariance matrix) recursively using randomized power iteration combined with Gram-Schmidt orthonormalization.
*   **Literal Codebase Mapping**:
    - [ProjectionService.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/Infrastructure/Presentation/ProjectionService.swift): Implements `pca3D_powerIteration()`, calculating top-3 components dynamically over mean-centered embedding vectors.

### 29. Fibonacci Sphere Distribution
*   **Paper**: *Distributing many points on a sphere* (Saff and Kuijlaars, 1997)
*   **Link**: [Saff & Kuijlaars (Mathematical Intelligencer)](https://link.springer.com/article/10.1007/BF03024331)
*   **Core Concept**: Distributes $N$ points on a sphere uniformly by wrapping a golden-ratio spiral around the sphere surface.
*   **Literal Codebase Mapping**:
    - [AdaptiveVisualizationsView.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Features/Telemetry/Visualizations/AdaptiveVisualizationsView.swift): Historically used to distribute document cluster nodes on a 3D sphere coordinate layout (now archived/pruned for raw vector scatter projections).

---

## Part 8: The Document Ingestion Pipeline (6 Steps)
This defines how imported physical files and digital assets are processed into isolated search indices.

*   **Step 1: Parse & Extract**
    - Bypasses raw pixel rendering. Extracts digital text layers via PDFKit or parses Office XML files. If the digital layer is missing or garbled, the layout-aware Vision OCR is invoked, rendering pages as raw `CGImage` memory pointers directly under `CIContext` to avoid OOM memory spikes.
    - *Mapping*: [DocumentProcessor.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift) & [StructuredDocumentParser.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/Document/Processing/StructuredDocumentParser.swift)
*   **Step 2: Semantic & Structure-Aware Chunking**
    - Segments raw text into paragraph blocks ($\le 310$ words) using a sliding character overlap. Structural assets (tables and lists) are parsed into row-column grids and marked as atomic chunks so they are not broken apart by text split boundaries.
    - *Mapping*: [SemanticChunker.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/Document/Chunking/SemanticChunker.swift)
*   **Step 3: Entity & Metadata Extraction**
    - Runs Apple's Natural Language NLTagger framework to extract entities, PascalCase keywords, document authors, and section headers to tag chunk records.
    - *Mapping*: [ContentTaggingService.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/Document/Chunking/ContentTaggingService.swift)
*   **Step 4: Token Gating and Validation**
    - Validates word-piece token boundaries using local tokenizers (e.g. `BertTokenizer`) to enforce subword limits ($\le 510$ tokens) before indexing.
    - *Mapping*: `BertTokenizer.swift` / `Tokenizers` target
*   **Step 5: Dense Embedding Vector Generation**
    - Generates 384-dimensional dense semantic vectors. Executes zero-copy sentence embedding models natively on Apple Neural Engines (ANE) on compatible OS versions, falling back to local Core ML compilation models.
    - *Mapping*: [CoreAISentenceEmbeddingProvider.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/Embedding/Providers/CoreAISentenceEmbeddingProvider.swift) & `EmbeddingService.swift`
*   **Step 6: Dual Index Storage & Checkpointing**
    - Lexical tokens are committed to the SQLite FTS5 table, and dense floating-point vector arrays are saved under container-isolated binary files (`_vectors.bin`). Temporary progress coordinates are cached as page-level JSON checkpoints under `localCacheDir()/IngestionCheckpoints/<docFingerprint>/` to allow instant resumes if the queue is paused or terminated.
    - *Mapping*: [SQLiteFullTextService.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/Storage/SQLiteFullTextService.swift) & [BNNSVectorDatabase.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift)

---

## Part 9: The Query & Retrieval Pipeline (23 Steps)
This outlines the execution stages from user input query down to SwiftUI rendering.

*   **Step 0: Corpus Analysis**
    - Pre-loads vocabulary caches and metadata stats from the selected active container workspace.
*   **Step 1: Query Understanding**
    - Resolves pronoun references, performs query normalization, and labels named entities.
*   **Step 1.5: Query Expansion**
    - Injects container vocabulary and synonyms to broaden candidate coverage.
*   **Step 1.6: Intent Classification**
    - Classifies the user request into five core intents: Lookup (extractive overrides), Procedure (sequential tracking), Compare (multi-hop mapping), Summarize (global overview routing), or General QA.
*   **Step 2: Query Embedding**
    - Converts the expanded query into a 384-dimensional dense query vector.
*   **Step 2.5: RAPTOR-lite Routing**
    - Evaluates query scope; if global or summary-related, routes the search directly to hierarchical parent summary nodes.
*   **Step 3: Hybrid Search (RRF)**
    - Executes dual search paths: retrieves lexical BM25 rankings from FTS5 tables and semantic similarity rankings from the container's vector binary store. Integrates findings using Reciprocal Rank Fusion (RRF) with parameter $k=60$.
*   **Step 4: Cross-Encoder Reranking**
    - Runs a local Core ML TinyBERT model as a cross-encoder to calculate query-chunk joint attention scores, replacing RRF ranks.
*   **Step 4.3: Low-Confidence Filtering**
    - Prunes all candidate segments falling below safety confidence margins.
*   **Step 4.4: Multi-Document Representation**
    - Enforces document source diversity to prevent single-page clusters from crowding out other relevant sources.
*   **Step 4.5: MMR Diversification**
    - Applies Maximal Marginal Relevance (MMR) with $\lambda = 0.6$ to filter out semantically redundant overlapping chunks.
*   **Step 4.6: Parent Document Retrieval**
    - Expands selected child vector chunks to pull adjacent sibling chunks (typically $\pm 5$ sentences) to restore surrounding reading context.
*   **Step 4.7: Contextual Compression**
    - Compresses text structures to drop uninformative vocabulary, saving prompt token overhead.
*   **Step 4.9: Graph Context Packing**
    - Packs semantic entity paths, section outlines, and reference tags into the final context block.
*   **Step 5: Context Assembly (Lost-in-the-Middle)**
    - Reorders context chunks so that the highest scoring segments sit at the absolute beginning and end of the prompt window, mitigating model middle-context neglect.
*   **Step 5.9: Extractive Summarization**
    - Bypasses generative synthesis for broad summary queries, executing rapid extractive paragraph assembly.
*   **Step 5.10: Extractive QA**
    - Pulls numbers, values, and specifications directly from table matrices for Lookup queries, enforcing numeric precision.
*   **Step 6: LLM Generation**
    - Passes the packed prompt into Apple's public `LanguageModelSession` framework, enforcing a 4096-token budget.
*   **Step 6.5: Response Formatting**
    - Normalizes raw output to fix broken list indentations, correct markdown syntax, and enforce guided output structures.
*   **Step 7: Quality Assessment**
    - Evaluates synthesis likelihood, tracking token probabilities.
*   **Step 7.5: Verification Gates A-I**
    - Evaluates outputs through local verification checks (negation, entity matching, overlap, and container-isolation checks) to detect contradictions and trigger refusals/abstentions if validation checks fail.
*   **Step 8: Package Results**
    - Packages the final answer, citation mapping indices, and evidence thread payloads.
*   **Step 8.1: Calibrated Confidence**
    - Performs Platt scaling calculations on quality assessments to return user-facing confidence ratings.
*   **Step 9: Response Metadata**
    - Records system execution metrics, token footprints, database cache hits, and device thermal levels.
*   **Step 10: Markdown Presentation**
    - Renders the final text in SwiftUI using block-level styling, inline citation buttons, and quality gauge metrics.

---

## Part 10: SQLite Core Database Configuration & PRAGMA Settings
All local relational metadata and lexical indexes are stored in a single shared SQLite file optimized for Apple Silicon hardware storage constraints.

### 1. Database Schema Tables
*   `documents` (FTS5 virtual table): Stores document contents for full-text lexical indexing.
*   `document_meta` (Standard table): Tracks document counts, modification dates, size, and container isolation.
*   `document_content` (Standard table): Fast raw text database used for direct extractive overrides.
*   `chunks` (FTS5 virtual table): Stores segment-level FTS5 lexical indexes for local lookups.
*   `document_pages` (FTS5 virtual table): Page-isolated indexes for context bounds tracking.

### 2. SQLite Performance Optimization Parameters (PRAGMAs)
*   `PRAGMA journal_mode = WAL`
    - *Purpose*: Write-Ahead Logging. Permits concurrent reads and write steps, preventing transactional locks from blocking the active UI thread.
*   `PRAGMA busy_timeout = 3000`
    - *Purpose*: Prevents write deadlocks under busy locks. Sets database connection lock retry to 3000ms.
*   `PRAGMA synchronous = NORMAL`
    - *Purpose*: WAL writes bypass immediate storage sync operations, relying on OS file sync to improve database write speeds by 2x+.
*   `PRAGMA temp_store = MEMORY`
    - *Purpose*: Forces temporary indices, caching tables, and sorting buffers to reside in memory rather than page swapping to SSD disk storage.
*   `PRAGMA cache_size = -64000`
    - *Purpose*: Allocates a maximum database page cache size of 64MB (negative values indicate memory allocations in KB).
*   `PRAGMA mmap_size = 268435456`
    - *Purpose*: Configures memory-mapped IO (mmap) up to 256MB. This permits direct zero-copy read boundaries, reading data pages straight out of system caches without copying blocks to heap registers.
*   `tokenize = 'porter unicode61'`
    - *Purpose*: Configures the FTS5 virtual table tokenizer. Porter strips English suffixes (e.g. mapping "synthetics" to "synthetic") while unicode61 enforces case-insensitive word matching.
