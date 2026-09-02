# OpenIntelligence Audio Study Guide, Version 2: Full Engine Edition

**Checked:** August 27, 2026  
**Repository:** `Gunnarguy/OpenIntelligence`  
**Source inventory:** 612 unique engine concepts  
**Coverage rule:** Every concept from the controlled word bank is named and taught below.  

> This replaces the first audio guide. The first version compressed the architecture too aggressively and omitted named systems, including RAPTOR-lite. This version is generated from the complete 612-entry manifest, and it retains explicit status, sequencing, code anchors, and caveats for every term.

---

# How to Listen

This is deliberately long. It has two layers:

1. **Part One, the causal tour:** a continuous explanation of the machine in pipeline order.
2. **Part Two, the complete concept progression:** every term gets an explain-it-like-I-am-five explanation, a layman’s explanation, and a technical explanation.

Listen to Part One first. Use Part Two as the exhaustive second pass and reference encyclopedia.

---

# Part One. The Causal Tour of the Entire Engine

## The single-sentence mental model

OpenIntelligence turns source files into structured, searchable evidence; turns a question into a retrieval and execution plan; searches meaning and exact wording in parallel; ranks, diversifies, expands, compresses, and packs the best evidence; generates or extracts an answer; verifies every important claim; and returns the result with citations, fidelity, diagnostics, and an execution receipt.

## 00. System architecture and boundaries

### Explain it like I am five

Before looking at the machinery, we need to know where the walls, rooms, and rules are. These concepts define what the app is, what belongs to one library, and which steps are rule-based versus model-generated.

### Layman’s explanation

This section establishes the system boundaries. It explains containers, local-first execution, retrieval-augmented generation, deterministic stages, generative stages, and the distinction between the engine, the app, and the query pipeline.

### Technical explanation

These concepts define the architectural invariants that all later services rely on: container scoping, storage isolation, orchestration boundaries, execution-stage typing, protocol abstractions, and the end-to-end RAG control flow.

This section contains **14 controlled concepts**. Part Two names every one.

## 01. Ingestion control, identity, and lifecycle

### Explain it like I am five

This is the receiving dock. It makes a work ticket for every file, remembers where the job stopped, prevents duplicate work, and makes sure deleting a job really wins over accidentally restarting it.

### Layman’s explanation

Ingestion is a durable workflow, not a single function call. It tracks queue items, leases, heartbeats, checkpoints, cancellation, resumption, deduplication, and atomic publication.

### Technical explanation

The ingestion lifecycle is a stateful, resumable process with stable document identity, content hashes, stage transitions, ownership leases, checkpoint persistence, tombstones, and all-or-nothing artifact publication.

This section contains **19 controlled concepts**. Part Two names every one.

## 02. File extraction and document understanding

### Explain it like I am five

This is the reading room. The app chooses whether to copy text, look at a page like a picture, read rows and columns, or listen to audio.

### Layman’s explanation

Different source types require different extraction lanes. Native PDF text, OCR, structured document parsing, CSV rules, Office parsers, image analysis, and speech transcription all produce normalized content plus provenance.

### Technical explanation

Extraction routes are selected by type and page complexity. They combine PDFKit, Vision OCR, layout reconstruction, structured parsers, standards-compliant delimited-text parsing, and on-device speech recognition while preserving pages, offsets, tables, figures, and confidence signals.

This section contains **52 controlled concepts**. Part Two names every one.

## 03. Document analysis, adaptation, and derived knowledge

### Explain it like I am five

After reading the file, the app adds labels: what kind of document is this, what names and codes are important, where are the references, and should it also make a short summary?

### Layman’s explanation

This layer derives metadata and higher-level knowledge from extracted content. It includes entities, specifications, document summaries, abstraction levels, reference-list detection, and RAPTOR-lite.

### Technical explanation

Analysis services enrich content before final indexing. They derive semantic categories, structured facts, entity indexes, cross-reference graphs, L1 document-summary chunks, and query-routing metadata.

### RAPTOR, explicitly

RAPTOR means a hierarchical retrieval design in which lower-level detail passages are summarized into higher-level nodes. OpenIntelligence currently implements **RAPTOR-lite**, not the full recursive hierarchy. Level zero is the ordinary detail chunk. Level one is one document-summary chunk generated after the detail chunks exist. Overview questions can be routed toward those level-one summaries. Level two topic-cluster summaries and level three library-wide summaries are reserved in the data model, but they are future layers rather than established active indexing stages. This distinction is load-bearing: OpenIntelligence has real L0-to-L1 hierarchical summary routing, but it must not be described as a fully recursive L0-to-L3 RAPTOR tree today.

This section contains **15 controlled concepts**. Part Two names every one.

## 04. Chunking and tokenizer integrity

### Explain it like I am five

This is where a big book becomes useful index cards. The cards must be small enough to fit, but large enough to still make sense.

### Layman’s explanation

Chunking balances precision against context. The engine respects sentence and section boundaries, preserves tables and lists, creates overlap, attaches parent context, and validates the real tokenizer ceiling.

### Technical explanation

SemanticChunker produces retrieval units under explicit target, minimum, maximum, and overlap constraints. It attaches offsets, semantic types, sibling groups, contextual prefixes, and validates WordPiece token counts against the embedding model limit.

This section contains **21 controlled concepts**. Part Two names every one.

## 05. Embeddings and vector semantics

### Explain it like I am five

Each chunk gets a location on a map of meaning. The question gets a location too, and nearby locations may talk about similar things.

### Layman’s explanation

Embeddings convert text into fixed-length numerical vectors. Provider identity, tokenizer, pooling, normalization, and dimension all determine what those coordinates mean.

### Technical explanation

The embedding subsystem defines provider contracts, tokenization, special tokens, attention masks, model tensor inputs, mean pooling, L2 normalization, validation, batching, and fingerprints that prevent incompatible vector spaces from being mixed.

This section contains **33 controlled concepts**. Part Two names every one.

## 06. Lexical indexing, SQLite, and vector persistence

### Explain it like I am five

The app keeps several filing systems. One remembers exact words, one remembers meaning coordinates, and one remembers facts about where everything came from.

### Layman’s explanation

SQLite and FTS5 support exact and lexical search, while the vector store supports semantic search. Binary vector files and norms provide efficient local persistence.

### Technical explanation

This layer includes relational tables, FTS5 virtual tables and weighted columns, BM25 parameters, transactions, WAL, container scoping, memory-mapped Float32 vector files, norm files, exact cosine scans, partial top-k selection, and vector-store routing.

This section contains **49 controlled concepts**. Part Two names every one.

## 07. Query understanding, intent, and execution planning

### Explain it like I am five

This is the dispatcher. It listens to the question and decides whether it is a tiny fact hunt, a comparison, a summary, a procedure, or a big investigation.

### Layman’s explanation

The query is normalized, profiled, classified, and converted into an execution plan. Intent and complexity determine search strategy, answer policy, and whether deeper reasoning is justified.

### Technical explanation

QueryProfile and QueryExecutionPlan centralize answer intent, search intent, abstraction routing, complexity, touchiness, literal-entity preservation, decomposition, tool eligibility, and grounded-answer policy.

This section contains **45 controlled concepts**. Part Two names every one.

## 08. Retrieval, fusion, reranking, and evidence expansion

### Explain it like I am five

Several search teams bring back possible answers. The app combines their lists, asks a smarter judge to reorder them, removes copies, and then looks around the best results for missing context.

### Layman’s explanation

Hybrid retrieval combines dense and lexical search. RRF merges rankings, boosts protect high-value signals, TinyBERT reranks candidates, MMR diversifies, and parent or sibling expansion adds context.

### Technical explanation

The retrieval stack covers candidate breadth, vector and lexical arms, fusion weights, RRF k, dynamic thresholds, lexical survivor guarantees, structured-table extraction, cross-encoder scores, MMR lambda, Jaccard deduplication, parent retrieval, graph expansion, and RAPTOR-lite summary routing.

This section contains **60 controlled concepts**. Part Two names every one.

## 09. Context selection, compression, and token packing

### Explain it like I am five

This is packing a suitcase. The app cannot bring the whole library, so it chooses the most useful evidence and fits it into the model’s limited space.

### Layman’s explanation

Compression removes irrelevant content and context packing allocates the final prompt budget among core chunks, parents, neighbors, references, instructions, safety, and output.

### Technical explanation

The context layer performs source-sentence selection, query-aware compression, expansion guards, budget accounting, intent-specific allocations, Lost-in-the-Middle ordering, evidence-packet construction, and hard context-window enforcement.

This section contains **27 controlled concepts**. Part Two names every one.

## 10. Model execution, routing, tools, and generation

### Explain it like I am five

Now the app chooses which answering engine is allowed to run, gives it the evidence and rules, and records what engine actually completed the answer.

### Layman’s explanation

The execution layer chooses deterministic, on-device, cloud-eligible, or abstention paths. It builds sessions, compiles prompts, optionally exposes tools, streams generation, and records execution receipts.

### Technical explanation

This section covers InferenceConfig, post-retrieval ModelExecutionPlan, FoundationModel route policy, fail-closed quota and consent logic, LanguageModelSession construction, @Generable constrained decoding, tool schemas, streaming, structured generation, attempts, fallbacks, and receipts.

This section contains **62 controlled concepts**. Part Two names every one.

## 11. Agentic, recursive, and multi-session reasoning

### Explain it like I am five

For hard questions, the app becomes a research team. It makes a checklist, searches one piece at a time, writes facts into a notebook, checks what is missing, and stops when the notebook is good enough.

### Layman’s explanation

Deep Think and Maximum use multiple sessions, subquestions, iterative retrieval, a FactBank, novelty and coverage tracking, critique, refinement, and evidence-driven stopping.

### Technical explanation

The agentic branch orchestrates plans, search actions, structured fact accumulation, convergence metrics, coverage plateaus, repetition checks, hard session caps, recursive synthesis, Self-RAG evaluation, and bounded repair.

This section contains **40 controlled concepts**. Part Two names every one.

## 12. Verification, grounding, confidence, and abstention

### Explain it like I am five

This is the fact-checking desk. It asks whether every important sentence is really supported, whether numbers match, and whether the safest answer is “I do not have enough evidence.”

### Layman’s explanation

Verification checks claims, citations, quotes, numeric values, contradictions, domain consistency, completeness, and evidence coverage. It calibrates trust and can remove claims or abstain.

### Technical explanation

The trust layer applies Gates A through I, source-only verification, claim verdicts, quote-span checks, numeric-unit validation, domain isolation, confidence policy, calibration parameters, abstention thresholds, answer-replacement guards, and fidelity rendering.

This section contains **40 controlled concepts**. Part Two names every one.

## 13. Response structure, provenance, rendering, and observability

### Explain it like I am five

The final report includes the answer, the receipts, the source labels, and clues showing how the machine got there.

### Layman’s explanation

The response is a structured package, not just prose. It includes claims, evidence IDs, citations, metadata, diagnostics, route information, source chips, and persisted evidence threads.

### Technical explanation

StructuredAnswer, OIQueryResult, RAGResponse, response metadata, citation namespaces, evidence records, Markdown rendering, route receipts, thinking events, audit snapshots, and EvidenceThread persistence make the output inspectable.

This section contains **35 controlled concepts**. Part Two names every one.

## 14. Evaluation, benchmarks, and quality measurement

### Explain it like I am five

This is the test track. It checks not only whether the final answer was right, but exactly where the correct evidence was lost if it was wrong.

### Layman’s explanation

Evaluation scores retrieval, ranking, citations, exact values, abstention, overflow, latency, and route honesty. Stage traces localize failure.

### Technical explanation

The evaluation layer computes Recall@k, Precision@k, MRR, nDCG, retrieval-stage metrics, end-to-end RAG gates, route invariants, benchmark overrides, and promotion criteria from trace and receipt data.

This section contains **31 controlled concepts**. Part Two names every one.

## 15. Device adaptation, compute, background work, sync, and product limits

### Explain it like I am five

This is the power manager and janitor. It decides how hard the phone can work, keeps local and shared copies safe, and makes long jobs survive when possible.

### Layman’s explanation

Runtime services adapt to hardware, thermal state, memory, background limits, sync state, entitlement limits, and user settings.

### Technical explanation

This layer includes DeviceCapabilityService, AdaptivePipelineOptimizer, GPU profiles, Core ML compute-unit policy, vDSP, BNNS, Metal, background continued-processing tasks, workspace synchronization, materialization guards, StoreKit entitlements, quotas, and settings persistence.

This section contains **44 controlled concepts**. Part Two names every one.

## 16. Dormant, future, superseded, and commonly misnamed mechanisms

### Explain it like I am five

Some blueprints are in the workshop but are not part of the machine that runs today. This section labels them clearly so you do not mistake a plan for a working gear.

### Layman’s explanation

The repository contains future levels, dormant providers, old names, removed backends, and claims that were corrected. These must be taught separately from active behavior.

### Technical explanation

Status classification distinguishes source presence from production execution. It identifies scaffolds, reserved enums, superseded terminology, nonshipping paths, and architecture claims that require capability or runtime evidence.

This section contains **25 controlled concepts**. Part Two names every one.

---

# Part Two. Complete Concept-by-Concept Progression

The next 612 capsules are the no-stone-unturned pass. Status is always stated because a future enum, dormant scaffold, or historical name must not be confused with a current load-bearing mechanism.

---

# 00. System architecture and boundaries

**Section orientation:** This section establishes the system boundaries. It explains containers, local-first execution, retrieval-augmented generation, deterministic stages, generative stages, and the distinction between the engine, the app, and the query pipeline.

## OI-0001. Container isolation

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a building blueprint and traffic rules. **Container isolation** means: The rule that exact-word rows, number coordinates stores, entity lookups, documents, threads, and queries are filtered by container identity. The reason it exists is: This prevents cross-library evidence leakage and makes deletion, rebuilding, and sync rule-based and repeatable per library.

### Layman’s explanation

The rule that lexical rows, vector stores, entity lookups, documents, threads, and queries are filtered by container identity. This prevents cross-library evidence leakage and makes deletion, rebuilding, and sync deterministic per library.

### Technical explanation

It is enforced in storage and retrieval before candidates can enter ranking or generation. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift; OpenIntelligence/Services/VectorStore/VectorStoreRouter.swift; OpenIntelligence/Services/Document/Analysis/EntityIndexService.swift.

### Why it is in this position

It is enforced in storage and retrieval before candidates can enter ranking or generation.

## OI-0002. Deep Think mode

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a building blueprint and traffic rules. **Deep Think mode** means: The multi-step path that enables question rewriting, expansion, HyDE, iterative search, and the agentic orchestrator with stronger verification thresholds. The reason it exists is: It spends additional search and reasoning work when a one-pass answer is likely incomplete or ambiguous.

### Layman’s explanation

The multi-step path that enables query rewriting, expansion, HyDE, iterative retrieval, and the agentic orchestrator with stronger verification thresholds. It spends additional retrieval and reasoning work when a one-pass answer is likely incomplete or ambiguous.

### Technical explanation

It replaces the Standard execution path after the runtime coordinator resolves the mode. Primary code anchors: OpenIntelligence/Core/Models/RAGQualityMode.swift; OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift.

### Why it is in this position

It replaces the Standard execution path after the runtime coordinator resolves the mode.

## OI-0003. Deterministic stage

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a building blueprint and traffic rules. **Deterministic stage** means: A stage whose result is produced by code, indexing, arithmetic, parsing, or fixed policy rather than free-form model generation. The reason it exists is: rule-based and repeatable stages are reproducible and cheap to verify. The engine deliberately keeps search and final verification rule-based and repeatable even when synthesis uses a language model.

### Layman’s explanation

A stage whose result is produced by code, indexing, arithmetic, parsing, or fixed policy rather than free-form model generation. Deterministic stages are reproducible and cheap to verify. The engine deliberately keeps retrieval and final verification deterministic even when synthesis uses a language model.

### Technical explanation

They dominate ingestion, retrieval, packing, route authorization, and verification. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/ModelExecutionPlan.swift.

### Why it is in this position

They dominate ingestion, retrieval, packing, route authorization, and verification.

## OI-0004. Engine status vocabulary

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a building blueprint and traffic rules. **Engine status vocabulary** means: The audit classification used in this word bank: Core, Conditional, Support, Dormant, Future, and Historical. The reason it exists is: The repository contains implemented, wired, optional, scaffolded, and superseded mechanisms. Treating all source files as equally active would teach a false architecture.

### Layman’s explanation

The audit classification used in this word bank: Core, Conditional, Support, Dormant, Future, and Historical. The repository contains implemented, wired, optional, scaffolded, and superseded mechanisms. Treating all source files as equally active would teach a false architecture.

### Technical explanation

It is an interpretive layer over the codebase, not an app runtime type. Primary code anchors: Docs/SHIPPED_CAPABILITIES.json; CHANGELOG.md.

### Why it is in this position

It is an interpretive layer over the codebase, not an app runtime type.

## OI-0005. Generative stage

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a building blueprint and traffic rules. **Generative stage** means: A stage that uses a language model to write, summarize, reformulate, classify, or synthesize text. The reason it exists is: Generation handles meaning-based composition that fixed rules cannot express, but it introduces uncertainty, token cost, and hallucination risk, so it is surrounded by rule-based and repeatable controls.

### Layman’s explanation

A stage that uses a language model to write, summarize, reformulate, classify, or synthesize text. Generation handles semantic composition that fixed rules cannot express, but it introduces uncertainty, token cost, and hallucination risk, so it is surrounded by deterministic controls.

### Technical explanation

It occurs only after evidence selection and before claim verification. Primary code anchors: OpenIntelligence/Services/LLM/LLMService.swift; OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelStructuredGenerator.swift.

### Why it is in this position

It occurs only after evidence selection and before claim verification.

## OI-0006. Ingestion pipeline

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a building blueprint and traffic rules. **Ingestion pipeline** means: The one-time transformation from an imported file into put into a consistent form text, structured elements, small source pieces, meaning map, exact-word rows, number coordinates artifacts, summaries, and labels and facts. The reason it exists is: Every later answer is bounded by what ingestion preserved. A fact omitted, scrambled, truncated, or assigned the wrong identity cannot be recovered by better search.

### Layman’s explanation

The one-time transformation from an imported file into normalized text, structured elements, chunks, embeddings, lexical rows, vector artifacts, summaries, and metadata. Every later answer is bounded by what ingestion preserved. A fact omitted, scrambled, truncated, or assigned the wrong identity cannot be recovered by better retrieval.

### Technical explanation

It runs when a document is added or rebuilt and finishes before that document becomes queryable. Primary code anchors: OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift; Docs/INGESTION_PIPELINE.md.

### Why it is in this position

It runs when a document is added or rebuilt and finishes before that document becomes queryable.

## OI-0007. Knowledge container / library

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a building blueprint and traffic rules. **Knowledge container / library** means: A user-visible library with its own documents, meaning map configuration, number coordinates artifacts, search settings, statistics, and sync mode. The reason it exists is: It is the primary isolation boundary. Without it, a question in one library could retrieve private or irrelevant small source pieces from another, and incompatible meaning map spaces could be mixed.

### Layman’s explanation

A user-visible library with its own documents, embedding configuration, vector artifacts, retrieval settings, statistics, and sync mode. It is the primary isolation boundary. Without it, a query in one library could retrieve private or irrelevant chunks from another, and incompatible embedding spaces could be mixed.

### Technical explanation

The container is selected before ingestion or querying and its UUID scopes every downstream read and write. Primary code anchors: OpenIntelligence/Core/Models/KnowledgeContainer.swift; OpenIntelligence/Services/Infrastructure/Integration/ContainerService.swift.

### Why it is in this position

The container is selected before ingestion or querying and its UUID scopes every downstream read and write.

## OI-0008. Local-first

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a building blueprint and traffic rules. **Local-first** means: Documents, full text, meaning map, indexes, search, generation, and rule-based and repeatable verification are designed to run on the user device. The reason it exists is: This is the privacy and availability constraint that determines the architecture. It removes the option of uploading the document collection to a remote number coordinates database or model and makes bounded local search necessary.

### Layman’s explanation

Documents, full text, embeddings, indexes, retrieval, generation, and deterministic verification are designed to run on the user device. This is the privacy and availability constraint that determines the architecture. It removes the option of uploading the corpus to a remote vector database or model and makes bounded local retrieval necessary.

### Technical explanation

It is a design constraint applied before every pipeline choice, not a single stage. Primary code anchors: Docs/HOW_IT_WORKS.md; Docs/PRIVACY_AND_ROUTING.md.

### Why it is in this position

It is a design constraint applied before every pipeline choice, not a single stage.

## OI-0009. Maximum mode

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a building blueprint and traffic rules. **Maximum mode** means: The broadest and strictest user-selectable path with larger possible result sets, more expansion, more agentic sessions, lower search floors, and the highest verification threshold. The reason it exists is: It is designed for difficult synthesis where missing evidence is more costly than latency.

### Layman’s explanation

The broadest and strictest user-selectable path with larger candidate sets, more expansion, more agentic sessions, lower retrieval floors, and the highest verification threshold. It is designed for difficult synthesis where missing evidence is more costly than latency.

### Technical explanation

It enters the agentic path at query start and uses evidence-driven stopping rather than a single fixed pass. Primary code anchors: OpenIntelligence/Core/Models/RAGQualityMode.swift; OpenIntelligence/Services/RAG/Tuning/AgenticPolicyService.swift.

### Why it is in this position

It enters the agentic path at query start and uses evidence-driven stopping rather than a single fixed pass.

## OI-0010. OpenIntelligence engine

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a building blueprint and traffic rules. **OpenIntelligence engine** means: The coordinated local document-intelligence runtime that accepts files, builds searchable representations, retrieves evidence, invokes Apple Foundation Models, verifies claims, and returns a cited answer. The reason it exists is: It gives one owner to the end-to-end contract. Without an coordinate engine, ingestion, storage, search, model execution, and verification could each be locally correct while disagreeing about identifiers, dimensions, token budgets, or source numbering.

### Layman’s explanation

The coordinated local document-intelligence runtime that accepts files, builds searchable representations, retrieves evidence, invokes Apple Foundation Models, verifies claims, and returns a cited answer. It gives one owner to the end-to-end contract. Without an orchestrated engine, ingestion, storage, retrieval, model execution, and verification could each be locally correct while disagreeing about identifiers, dimensions, token budgets, or source numbering.

### Technical explanation

It surrounds the entire lifecycle and is exposed through RAGService internally and OIEngine at the SDK boundary. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/RAGService.swift; OpenIntelligence/SDK/OpenIntelligenceEngine.swift.

### Why it is in this position

It surrounds the entire lifecycle and is exposed through RAGService internally and OIEngine at the SDK boundary.

## OI-0011. Quality mode

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a building blueprint and traffic rules. **Quality mode** means: The named policy bundle Standard, Deep Think, or Maximum that changes possible result breadth, similarity thresholds, expansion, iterative search, agentic sessions, confidence requirements, and memory depth. The reason it exists is: A mode must alter the whole pipeline coherently rather than only model temperature. Centralizing the policy prevents one screen or subsystem from silently using contradictory values.

### Layman’s explanation

The named policy bundle Standard, Deep Think, or Maximum that changes candidate breadth, similarity thresholds, expansion, iterative retrieval, agentic sessions, confidence requirements, and memory depth. A mode must alter the whole pipeline coherently rather than only model temperature. Centralizing the policy prevents one screen or subsystem from silently using contradictory values.

### Technical explanation

It is resolved at query start and influences every conditional stage afterward. Primary code anchors: OpenIntelligence/Core/Models/RAGQualityMode.swift; OpenIntelligence/Services/RAG/Orchestration/QueryRuntimeCoordinator.swift.

### Why it is in this position

It is resolved at query start and influences every conditional stage afterward.

## OI-0012. Query pipeline

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a building blueprint and traffic rules. **Query pipeline** means: The per-question path that profiles the request, retrieves possible result, ranks and expands evidence, packs context, chooses an execution route, generates or extracts an answer, and verifies it. The reason it exists is: It converts a broad document collection into a small evidence packet that fits the model and can be audited.

### Layman’s explanation

The per-question path that profiles the request, retrieves candidates, ranks and expands evidence, packs context, chooses an execution route, generates or extracts an answer, and verifies it. It converts a broad corpus into a small evidence packet that fits the model and can be audited.

### Technical explanation

It starts when the user submits a question and ends when the response object and provenance metadata are committed. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/QueryRuntimeCoordinator.swift; Docs/RETRIEVAL_PIPELINE.md.

### Why it is in this position

It starts when the user submits a question and ends when the response object and provenance metadata are committed.

## OI-0013. Retrieval-augmented generation (RAG)

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a building blueprint and traffic rules. **Retrieval-augmented generation (RAG)** means: A pattern in which the app retrieves relevant passages before asking the language model to answer from those passages. The reason it exists is: The on-device model cannot hold an entire library in its context window, and its pretrained memory is not the user document collection. search supplies the facts and citations that generation alone cannot know.

### Layman’s explanation

A pattern in which the app retrieves relevant passages before asking the language model to answer from those passages. The on-device model cannot hold an entire library in its context window, and its pretrained memory is not the user corpus. Retrieval supplies the facts and citations that generation alone cannot know.

### Technical explanation

It begins after ingestion has produced indexes and spans query understanding through retrieval, packing, generation, and verification. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/RAGService.swift; OpenIntelligence/UI/Components/Glossary.swift.

### Why it is in this position

It begins after ingestion has produced indexes and spans query understanding through retrieval, packing, generation, and verification.

## OI-0014. Standard mode

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a building blueprint and traffic rules. **Standard mode** means: The single-pass grounded path with hybrid search, reranking, MMR, citations, generation, and verification. The reason it exists is: It minimizes latency while preserving the non-negotiable evidence and trust controls.

### Layman’s explanation

The single-pass grounded path with hybrid retrieval, reranking, MMR, citations, generation, and verification. It minimizes latency while preserving the non-negotiable evidence and trust controls.

### Technical explanation

It is selected before query profiling and normally avoids iterative, HyDE, and agentic loops. Primary code anchors: OpenIntelligence/Core/Models/RAGQualityMode.swift.

### Why it is in this position

It is selected before query profiling and normally avoids iterative, HyDE, and agentic loops.

---

# 01. Ingestion control, identity, and lifecycle

**Section orientation:** Ingestion is a durable workflow, not a single function call. It tracks queue items, leases, heartbeats, checkpoints, cancellation, resumption, deduplication, and atomic publication.

## OI-0015. Atomic ingestion commit

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a receiving dock and work-ticket system. **Atomic ingestion commit** means: The final publication of mutually consistent document labels and facts, exact-word rows, small source pieces, and number coordinates artifacts only after the new set is ready. The reason it exists is: Publishing pieces independently creates states where SQLite says small source pieces exist but number coordinates are missing, or number coordinates refer to obsolete small source piece identities.

### Layman’s explanation

The final publication of mutually consistent document metadata, lexical rows, chunks, and vector artifacts only after the new set is ready. Publishing pieces independently creates states where SQLite says chunks exist but vectors are missing, or vectors refer to obsolete chunk identities.

### Technical explanation

It is the boundary between processing and making the rebuilt document visible to retrieval. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/RAGService.swift; OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift.

### Why it is in this position

It is the boundary between processing and making the rebuilt document visible to retrieval.

## OI-0016. Background continued processing

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a receiving dock and work-ticket system. **Background continued processing** means: An iOS 26 BGContinuedProcessingTask path that can continue a user-initiated import or question after the app leaves the foreground, with CPU/GPU resource policy and saved status. The reason it exists is: Long OCR and Maximum queries should not be discarded merely because the user switches apps.

### Layman’s explanation

An iOS 26 BGContinuedProcessingTask path that can continue a user-initiated import or query after the app leaves the foreground, with CPU/GPU resource policy and persisted status. Long OCR and Maximum queries should not be discarded merely because the user switches apps.

### Technical explanation

It is requested after user initiation and handed the same queue/query runner; it does not replace pipeline semantics. Primary code anchors: OpenIntelligence/Services/Infrastructure/Background/BackgroundTaskService.swift.

### Why it is in this position

It is requested after user initiation and handed the same queue/query runner; it does not replace pipeline semantics.

## OI-0017. Cancellation tombstone

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a receiving dock and work-ticket system. **Cancellation tombstone** means: A durable record that a queue item or document was intentionally discarded. The reason it exists is: Without a tombstone, sync or queue merge can resurrect work that another device or user explicitly removed.

### Layman’s explanation

A durable record that a queue item or document was intentionally discarded. Without a tombstone, sync or queue merge can resurrect work that another device or user explicitly removed.

### Technical explanation

It is written at cancellation/deletion and applied before merged queue or inventory items are accepted. Primary code anchors: OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift.

### Why it is in this position

It is written at cancellation/deletion and applied before merged queue or inventory items are accepted.

## OI-0018. Checkpoint

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a receiving dock and work-ticket system. **Checkpoint** means: A durable record of ingestion progress, commonly at page or batch boundaries, that lets a large document continue without restarting at page one. The reason it exists is: Mobile apps are interrupted frequently. Without checkpoints, long PDFs would repeat extraction and meaning map, increasing time, heat, and duplicate risk.

### Layman’s explanation

A durable record of ingestion progress, commonly at page or batch boundaries, that lets a large document continue without restarting at page one. Mobile apps are interrupted frequently. Without checkpoints, long PDFs would repeat extraction and embedding, increasing time, heat, and duplicate risk.

### Technical explanation

It is written during streaming ingestion before the next page batch is attempted. Primary code anchors: OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift; Docs/INGESTION_PIPELINE.md.

### Why it is in this position

It is written during streaming ingestion before the next page batch is attempted.

## OI-0019. Content hash

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a receiving dock and work-ticket system. **Content hash** means: A cryptographic or stable digest of source content used to identify unchanged files and artifacts. The reason it exists is: Hashes prevent duplicate ingestion, detect stale checkpoints, and support sync signatures without rereading or trusting filenames.

### Layman’s explanation

A cryptographic or stable digest of source content used to identify unchanged files and artifacts. Hashes prevent duplicate ingestion, detect stale checkpoints, and support sync signatures without rereading or trusting filenames.

### Technical explanation

It is computed near import and compared before expensive extraction or destructive synchronization. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/RAGService.swift; OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift.

### Why it is in this position

It is computed near import and compared before expensive extraction or destructive synchronization.

## OI-0020. Deduplication

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a receiving dock and work-ticket system. **Deduplication** means: The prevention or merging of logically repeated documents, small source pieces, or evidence based on IDs, hashes, source identity, or content overlap. The reason it exists is: Duplicates waste storage and context, distort rank metrics, and make one source appear more supported simply because it was indexed twice.

### Layman’s explanation

The prevention or merging of logically repeated documents, chunks, or evidence based on IDs, hashes, source identity, or content overlap. Duplicates waste storage and context, distort rank metrics, and make one source appear more supported simply because it was indexed twice.

### Technical explanation

It occurs at import, vector merge, parent expansion, and final evidence assembly using different identity rules. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/RAGService.swift; OpenIntelligence/Services/RAG/Retrieval/ParentDocumentService.swift.

### Why it is in this position

It occurs at import, vector merge, parent expansion, and final evidence assembly using different identity rules.

## OI-0021. Deletion-wins policy

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a receiving dock and work-ticket system. **Deletion-wins policy** means: A merge rule under which an explicit deletion marker defeats an older surviving copy. The reason it exists is: Distributed replicas otherwise tend to resurrect deleted files because one device still has the last full record.

### Layman’s explanation

A merge rule under which an explicit deletion marker defeats an older surviving copy. Distributed replicas otherwise tend to resurrect deleted files because one device still has the last full record.

### Technical explanation

It runs during workspace and queue reconciliation before files or vectors are copied. Primary code anchors: OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift; Docs/HOW_IT_WORKS.md.

### Why it is in this position

It runs during workspace and queue reconciliation before files or vectors are copied.

## OI-0022. Deterministic UUID

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a receiving dock and work-ticket system. **Deterministic UUID** means: A UUID generated from a stable string hash for cases that need reproducible identifiers. The reason it exists is: Reproducible IDs let derived artifacts reconnect after reload without a central server assigning identity.

### Layman’s explanation

A UUID generated from a stable string hash for cases that need reproducible identifiers. Reproducible IDs let derived artifacts reconnect after reload without a central server assigning identity.

### Technical explanation

It is used when the engine must derive identity from stable source material rather than create a random instance ID. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/RAGService.swift.

### Why it is in this position

It is used when the engine must derive identity from stable source material rather than create a random instance ID.

## OI-0023. Document enqueue

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a receiving dock and work-ticket system. **Document enqueue** means: The act of adding one or more URLs to the persistent ingestion queue instead of processing them directly in the UI callback. The reason it exists is: Queueing makes imports cancellable, resumable, observable, and safe across app backgrounding or termination.

### Layman’s explanation

The act of adding one or more URLs to the persistent ingestion queue instead of processing them directly in the UI callback. Queueing makes imports cancellable, resumable, observable, and safe across app backgrounding or termination.

### Technical explanation

It is the first engine action after a file picker, camera bridge, SDK request, or sample import supplies URLs. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/RAGService.swift; OpenIntelligence/Core/Models/IngestionItem.swift.

### Why it is in this position

It is the first engine action after a file picker, camera bridge, SDK request, or sample import supplies URLs.

## OI-0024. Foreground background-time fallback

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a receiving dock and work-ticket system. **Foreground background-time fallback** means: A shorter UIApplication background task used as a handoff window when the continued-processing task has not yet taken ownership. The reason it exists is: It closes the timing gap between app backgrounding and scheduler launch, reducing abrupt cancellation.

### Layman’s explanation

A shorter UIApplication background task used as a handoff window when the continued-processing task has not yet taken ownership. It closes the timing gap between app backgrounding and scheduler launch, reducing abrupt cancellation.

### Technical explanation

It sits between foreground execution and BGContinuedProcessingTask acquisition. Primary code anchors: OpenIntelligence/Services/Infrastructure/Background/BackgroundTaskService.swift.

### Why it is in this position

It sits between foreground execution and BGContinuedProcessingTask acquisition.

## OI-0025. Heartbeat

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a receiving dock and work-ticket system. **Heartbeat** means: A periodic timestamp proving that the worker holding an ingestion lease is still alive. The reason it exists is: It distinguishes slow but active OCR from a dead task whose lease should be reclaimed.

### Layman’s explanation

A periodic timestamp proving that the worker holding an ingestion lease is still alive. It distinguishes slow but active OCR from a dead task whose lease should be reclaimed.

### Technical explanation

It is updated during long-running stages and checked when restoring the queue. Primary code anchors: OpenIntelligence/Core/Models/IngestionItem.swift.

### Why it is in this position

It is updated during long-running stages and checked when restoring the queue.

## OI-0026. Ingestion lease

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a receiving dock and work-ticket system. **Ingestion lease** means: A time-bounded ownership marker indicating that one worker currently owns a queue item. The reason it exists is: After a crash or termination, an eternal processing flag would strand the item. A lease can expire so another run can safely resume it.

### Layman’s explanation

A time-bounded ownership marker indicating that one worker currently owns a queue item. After a crash or termination, an eternal processing flag would strand the item. A lease can expire so another run can safely resume it.

### Technical explanation

It is acquired before work, refreshed by heartbeats, and evaluated during recovery. Primary code anchors: OpenIntelligence/Core/Models/IngestionItem.swift; OpenIntelligence/Services/RAG/Orchestration/RAGService.swift.

### Why it is in this position

It is acquired before work, refreshed by heartbeats, and evaluated during recovery.

## OI-0027. Ingestion stage state machine

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a receiving dock and work-ticket system. **Ingestion stage state machine** means: The ordered states queued, loading, transcribing, extracting, chunking, analyzing, adapting, reindexing, meaning map, indexing, storing, complete, cancelled, and failed. The reason it exists is: Explicit states make progress and recovery auditable. A generic percentage cannot tell whether a failure corrupted extraction or merely failed to save number coordinates.

### Layman’s explanation

The ordered states queued, loading, transcribing, extracting, chunking, analyzing, adapting, reindexing, embedding, indexing, storing, complete, cancelled, and failed. Explicit states make progress and recovery auditable. A generic percentage cannot tell whether a failure corrupted extraction or merely failed to persist vectors.

### Technical explanation

Each processor transition updates the queue item before the next stage begins. Primary code anchors: OpenIntelligence/Core/Models/IngestionItem.swift.

### Why it is in this position

Each processor transition updates the queue item before the next stage begins.

## OI-0028. IngestionContext

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a receiving dock and work-ticket system. **IngestionContext** means: The reason and policy context for an import, such as user initiated, automatic rebuild, or onboarding. The reason it exists is: The same file-processing machinery may require different UI, tuning, retry, or self-healing behavior depending on why it runs.

### Layman’s explanation

The reason and policy context for an import, such as user initiated, automatic rebuild, or onboarding. The same file-processing machinery may require different UI, tuning, retry, or self-healing behavior depending on why it runs.

### Technical explanation

It is attached before processing begins and carried beside the queue item. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/RAGService.swift.

### Why it is in this position

It is attached before processing begins and carried beside the queue item.

## OI-0029. IngestionItem

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a receiving dock and work-ticket system. **IngestionItem** means: The saved state machine record for one imported file, including stage, progress, timestamps, lease, heartbeat, file identity, errors, and events. The reason it exists is: A long import needs an explicit durable state rather than an in-memory task. It lets the app distinguish paused, failed, cancelled, and genuinely active work.

### Layman’s explanation

The persisted state machine record for one imported file, including stage, progress, timestamps, lease, heartbeat, file identity, errors, and events. A long import needs an explicit durable state rather than an in-memory task. It lets the app distinguish paused, failed, cancelled, and genuinely active work.

### Technical explanation

It is created at enqueue and updated through every extraction, chunking, embedding, indexing, and storage stage. Primary code anchors: OpenIntelligence/Core/Models/IngestionItem.swift.

### Why it is in this position

It is created at enqueue and updated through every extraction, chunking, embedding, indexing, and storage stage.

## OI-0030. Resumable ingestion

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a receiving dock and work-ticket system. **Resumable ingestion** means: The combined behavior of queue saved storage, stable identity, leases, heartbeats, checkpoints, and stage-aware restart. The reason it exists is: It converts import from an all-or-nothing transaction into recoverable work while still protecting against double processing.

### Layman’s explanation

The combined behavior of queue persistence, stable identity, leases, heartbeats, checkpoints, and stage-aware restart. It converts import from an all-or-nothing transaction into recoverable work while still protecting against double processing.

### Technical explanation

It spans the entire ingestion lifecycle and is invoked after relaunch, background expiration, or rebuild interruption. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/RAGService.swift; OpenIntelligence/Services/Infrastructure/Background/BackgroundTaskService.swift.

### Why it is in this position

It spans the entire ingestion lifecycle and is invoked after relaunch, background expiration, or rebuild interruption.

## OI-0031. Stable document ID

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a receiving dock and work-ticket system. **Stable document ID** means: A UUID that continues to identify the logical document across checkpoints, sync, rebuilds, and derived small source pieces. The reason it exists is: Page-only or filename-only identity can create duplicates or attach rebuilt small source pieces to the wrong document. Stable identity is also the anchor for citations and deletion.

### Layman’s explanation

A UUID that continues to identify the logical document across checkpoints, sync, rebuilds, and derived chunks. Page-only or filename-only identity can create duplicates or attach rebuilt chunks to the wrong document. Stable identity is also the anchor for citations and deletion.

### Technical explanation

It is assigned before extraction and copied into every chunk, index row, entity mapping, and document record. Primary code anchors: OpenIntelligence/Core/Models/DocumentChunk.swift; OpenIntelligence/Services/RAG/Orchestration/RAGService.swift.

### Why it is in this position

It is assigned before extraction and copied into every chunk, index row, entity mapping, and document record.

## OI-0032. Streaming ingestion lane

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a receiving dock and work-ticket system. **Streaming ingestion lane** means: A bounded-memory path for large files that processes and flushes a page batch at a time instead of retaining the entire document working set. The reason it exists is: A hundreds-page PDF can exceed the process memory budget if all rendered pages and intermediate structures coexist.

### Layman’s explanation

A bounded-memory path for large files that processes and flushes a page batch at a time instead of retaining the entire document working set. A hundreds-page PDF can exceed the process memory budget if all rendered pages and intermediate structures coexist.

### Technical explanation

It is selected by size and document characteristics before extraction and writes checkpoints between batches. Primary code anchors: OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift; Docs/HOW_IT_WORKS.md.

### Why it is in this position

It is selected by size and document characteristics before extraction and writes checkpoints between batches.

## OI-0033. Weighted progress

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a receiving dock and work-ticket system. **Weighted progress** means: A mapping from stages to unequal progress contributions, with extraction receiving the largest share and storage the smallest. The reason it exists is: Import work is not evenly distributed. Weighted progress prevents the UI from sitting at 10 percent for most of a PDF or jumping from 50 to 100 during a tiny final write.

### Layman’s explanation

A mapping from stages to unequal progress contributions, with extraction receiving the largest share and storage the smallest. Import work is not evenly distributed. Weighted progress prevents the UI from sitting at 10 percent for most of a PDF or jumping from 50 to 100 during a tiny final write.

### Technical explanation

It is calculated throughout ingestion for overlays, Live Activities, background status, and diagnostics. Primary code anchors: OpenIntelligence/Core/Models/IngestionItem.swift.

### Why it is in this position

It is calculated throughout ingestion for overlays, Live Activities, background status, and diagnostics.

---

# 02. File extraction and document understanding

**Section orientation:** Different source types require different extraction lanes. Native PDF text, OCR, structured document parsing, CSV rules, Office parsers, image analysis, and speech transcription all produce normalized content plus provenance.

## OI-0034. Adaptive preprocessing

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **Adaptive preprocessing** means: Image enhancement chosen from page conditions, potentially including contrast, sharpening, denoising, thresholding, and orientation correction. The reason it exists is: One filter cannot help both faint receipts and high-contrast diagrams. Page-specific preprocessing improves recognition without permanently degrading clean pages.

### Layman’s explanation

Image enhancement chosen from page conditions, potentially including contrast, sharpening, denoising, thresholding, and orientation correction. One filter cannot help both faint receipts and high-contrast diagrams. Page-specific preprocessing improves recognition without permanently degrading clean pages.

### Technical explanation

It occurs after rasterization and before an OCR pass, with quality scoring selecting or escalating candidates. Primary code anchors: OpenIntelligence/Services/Document/Config/OCRConfiguration.swift; OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift.

### Why it is in this position

It occurs after rasterization and before an OCR pass, with quality scoring selecting or escalating candidates.

## OI-0035. Audio transcription

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **Audio transcription** means: On-device Speech.framework conversion of supported audio or video into text, duration, language, confidence, and timestamped segments. The reason it exists is: Recordings need a textual representation before the ordinary small source piece and search pipeline can operate on them.

### Layman’s explanation

On-device Speech.framework conversion of supported audio or video into text, duration, language, confidence, and timestamped segments. Recordings need a textual representation before the ordinary chunk and retrieval pipeline can operate on them.

### Technical explanation

It replaces text extraction for media files and feeds its formatted transcript into chunking. Primary code anchors: OpenIntelligence/Services/Document/Extraction/AudioTranscriptionService.swift.

### Why it is in this position

It replaces text extraction for media files and feeds its formatted transcript into chunking.

## OI-0036. Barcode detection

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **Barcode detection** means: Vision recognition of barcode symbology and payload text inside a camera frame. The reason it exists is: A barcode may contain the most exact identifier available and should not be approximated through OCR.

### Layman’s explanation

Vision recognition of barcode symbology and payload text inside a camera frame. A barcode may contain the most exact identifier available and should not be approximated through OCR.

### Technical explanation

It runs during live analysis and can be written into capture content before ingestion. Primary code anchors: OpenIntelligence/Features/Camera/CaptureToRAGBridge.swift.

### Why it is in this position

It runs during live analysis and can be written into capture content before ingestion.

## OI-0037. Camera-to-RAG bridge

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **Camera-to-RAG bridge** means: The actor that converts recognized camera text, structures, and optional image descriptions into a temporary Markdown document and queues it through normal ingestion. The reason it exists is: Camera captures should enter the same identity, chunking, meaning map, indexing, and verification pipeline as imported files.

### Layman’s explanation

The actor that converts recognized camera text, structures, and optional image descriptions into a temporary Markdown document and queues it through normal ingestion. Camera captures should enter the same identity, chunking, embedding, indexing, and verification pipeline as imported files.

### Technical explanation

It runs after capture recognition and before document enqueue. Primary code anchors: OpenIntelligence/Features/Camera/CaptureToRAGBridge.swift.

### Why it is in this position

It runs after capture recognition and before document enqueue.

## OI-0038. Column detection

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **Column detection** means: Histogram and gap-based clustering of text-block x coordinates into reading columns. The reason it exists is: A two-column paper read straight across produces semantically nonsensical passages and citations.

### Layman’s explanation

Histogram and gap-based clustering of text-block x coordinates into reading columns. A two-column paper read straight across produces semantically nonsensical passages and citations.

### Technical explanation

It runs after blocks are extracted and before top-to-bottom reading order is assembled within each column. Primary code anchors: OpenIntelligence/Services/Document/Processing/LayoutAwareExtractor.swift.

### Why it is in this position

It runs after blocks are extracted and before top-to-bottom reading order is assembled within each column.

## OI-0039. Compact cell anchor

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **Compact cell anchor** means: A precise row-column label attached to a cell value for smaller tables. The reason it exists is: Cell anchors improve exact lookup without repeating every large table cell and exhausting small source piece space.

### Layman’s explanation

A precise row-column label attached to a cell value for smaller tables. Cell anchors improve exact lookup without repeating every large table cell and exhausting chunk space.

### Technical explanation

They are generated after row records and before the canonical markdown table representation. Primary code anchors: OpenIntelligence/Services/Document/Processing/StructuredDocumentParser.swift.

### Why it is in this position

They are generated after row records and before the canonical markdown table representation.

## OI-0040. CoreMLDocumentClassifier

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **CoreMLDocumentClassifier** means: A local document-type classifier used to infer high-level document characteristics when available. The reason it exists is: Classification can guide extraction and chunking policy without sending document content to a server.

### Layman’s explanation

A local document-type classifier used to infer high-level document characteristics when available. Classification can guide extraction and chunking policy without sending document content to a server.

### Technical explanation

It runs during document analysis before the final ingestion plan is resolved. Primary code anchors: OpenIntelligence/Services/Document/Classification/CoreMLDocumentClassifier.swift.

### Why it is in this position

It runs during document analysis before the final ingestion plan is resolved.

## OI-0041. CoreMLRegionDetector

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **CoreMLRegionDetector** means: A local model path for detecting page-region classes such as tables, figures, or text regions. The reason it exists is: Region detection helps route visually complex areas to the correct extractor.

### Layman’s explanation

A local model path for detecting page-region classes such as tables, figures, or text regions. Region detection helps route visually complex areas to the correct extractor.

### Technical explanation

It runs after page rendering and before structured region processing when enabled. Primary code anchors: OpenIntelligence/Services/Document/Classification/CoreMLRegionDetector.swift.

### Why it is in this position

It runs after page rendering and before structured region processing when enabled.

## OI-0042. Detected data entity

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **Detected data entity** means: A structured email, phone number, URL, address, date, money amount, or measurement returned from visual document analysis. The reason it exists is: Explicit data types create searchable anchors and reduce ambiguity during extraction.

### Layman’s explanation

A structured email, phone number, URL, address, date, money amount, or measurement returned from visual document analysis. Explicit data types create searchable anchors and reduce ambiguity during extraction.

### Technical explanation

They are attached to table or page structure before chunk creation. Primary code anchors: OpenIntelligence/Services/Document/Processing/StructuredDocumentParser.swift.

### Why it is in this position

They are attached to table or page structure before chunk creation.

## OI-0043. Dynamic document vocabulary

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **Dynamic document vocabulary** means: A per-document list extracted from rough native text, including acronyms, alphanumeric codes, CamelCase words, compounds, and repeated proper-name bigrams. The reason it exists is: The document can teach OCR its own specialized vocabulary without hardcoding medical, engineering, or legal assumptions.

### Layman’s explanation

A per-document list extracted from rough native text, including acronyms, alphanumeric codes, CamelCase words, compounds, and repeated proper-name bigrams. The document can teach OCR its own specialized vocabulary without hardcoding medical, engineering, or legal assumptions.

### Technical explanation

It is derived before OCR and merged with universal custom words. Primary code anchors: OpenIntelligence/Services/Document/Config/OCRConfiguration.swift.

### Why it is in this position

It is derived before OCR and merged with universal custom words.

## OI-0044. Embedding translation

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **Embedding translation** means: Translation of text into the meaning map provider target language while retaining original source text for display and citation. The reason it exists is: A monolingual embedder may retrieve cross-language content poorly. Translating only the meaning map input improves meaning-based comparability without rewriting the source.

### Layman’s explanation

Translation of text into the embedding provider target language while retaining original source text for display and citation. A monolingual embedder may retrieve cross-language content poorly. Translating only the embedding input improves semantic comparability without rewriting the source.

### Technical explanation

It occurs immediately before embedding for affected documents or summaries. Primary code anchors: OpenIntelligence/Services/Document/Extraction/TranslationService.swift; OpenIntelligence/Services/Document/Analysis/DocumentSummaryService.swift.

### Why it is in this position

It occurs immediately before embedding for affected documents or summaries.

## OI-0045. Escalating DPI

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **Escalating DPI** means: A policy that begins at a practical render resolution and retries at higher resolution when small-text risk or confidence warrants it. The reason it exists is: Always rendering at maximum DPI wastes memory and heat; never escalating loses footnotes, labels, and measurements.

### Layman’s explanation

A policy that begins at a practical render resolution and retries at higher resolution when small-text risk or confidence warrants it. Always rendering at maximum DPI wastes memory and heat; never escalating loses footnotes, labels, and measurements.

### Technical explanation

It is decided by page analysis and OCR quality before accepting page text. Primary code anchors: OpenIntelligence/Services/Document/Config/OCRConfiguration.swift; OpenIntelligence/Services/Document/Chunking/PageComplexityAnalyzer.swift.

### Why it is in this position

It is decided by page analysis and OCR quality before accepting page text.

## OI-0046. Garbage-text detection

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **Garbage-text detection** means: Post-OCR rules that identify likely character salad, mixed-script misreads, improbable consonant patterns, and suspicious non-ASCII output while respecting detected document language. The reason it exists is: Rotated labels and diagrams can generate fluent-looking noise that contaminates small source pieces, vocabulary, and meaning map.

### Layman’s explanation

Post-OCR rules that identify likely character salad, mixed-script misreads, improbable consonant patterns, and suspicious non-ASCII output while respecting detected document language. Rotated labels and diagrams can generate fluent-looking noise that contaminates chunks, vocabulary, and embeddings.

### Technical explanation

It runs after OCR and language detection but before accepted text enters the corpus. Primary code anchors: OpenIntelligence/Services/Document/Config/OCRConfiguration.swift.

### Why it is in this position

It runs after OCR and language detection but before accepted text enters the corpus.

## OI-0047. ImageUnderstandingService

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **ImageUnderstandingService** means: The local service that classifies and interprets visual content found in documents or captures. The reason it exists is: Images and diagrams can contain evidence not represented in OCR text alone.

### Layman’s explanation

The local service that classifies and interprets visual content found in documents or captures. Images and diagrams can contain evidence not represented in OCR text alone.

### Technical explanation

It runs on selected visual regions after page analysis and before visual descriptions are attached to chunks. Primary code anchors: OpenIntelligence/Services/Document/Classification/ImageUnderstandingService.swift.

### Why it is in this position

It runs on selected visual regions after page analysis and before visual descriptions are attached to chunks.

## OI-0048. Language detection

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **Language detection** means: Identification of dominant document or extracted-text language using Natural Language APIs. The reason it exists is: Language affects OCR garbage rules, translation, tokenization expectations, and meaning map compatibility.

### Layman’s explanation

Identification of dominant document or extracted-text language using Natural Language APIs. Language affects OCR garbage rules, translation, tokenization expectations, and embedding compatibility.

### Technical explanation

It occurs after initial text is available and before language-sensitive normalization or translation. Primary code anchors: OpenIntelligence/Services/Document/Extraction/LanguageDetectionService.swift; OpenIntelligence/Services/Document/Config/OCRConfiguration.swift.

### Why it is in this position

It occurs after initial text is available and before language-sensitive normalization or translation.

## OI-0049. LanguageDetectionService

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **LanguageDetectionService** means: The Natural Language based service that identifies document or extracted-text language and confidence. The reason it exists is: Language affects OCR garbage rules, translation, tokenization expectations, and user-facing labels and facts.

### Layman’s explanation

The Natural Language based service that identifies document or extracted-text language and confidence. Language affects OCR garbage rules, translation, tokenization expectations, and user-facing metadata.

### Technical explanation

It runs after enough text is available and before language-dependent normalization or translation. Primary code anchors: OpenIntelligence/Services/Document/Extraction/LanguageDetectionService.swift.

### Why it is in this position

It runs after enough text is available and before language-dependent normalization or translation.

## OI-0050. Layout-aware extraction

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **Layout-aware extraction** means: Spatial reconstruction of text from bounding boxes rather than trusting raw PDF object order. The reason it exists is: PDF text is stored by coordinates, and multi-column pages can otherwise interleave unrelated lines.

### Layman’s explanation

Spatial reconstruction of text from bounding boxes rather than trusting raw PDF object order. PDF text is stored by coordinates, and multi-column pages can otherwise interleave unrelated lines.

### Technical explanation

It follows native or Vision block extraction and precedes page text assembly. Primary code anchors: OpenIntelligence/Services/Document/Processing/LayoutAwareExtractor.swift.

### Why it is in this position

It follows native or Vision block extraction and precedes page text assembly.

## OI-0051. Live camera analysis

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **Live camera analysis** means: Continuous Vision analysis of preview frames for text, document boundaries, barcodes, scenes, animals, faces, and humans. The reason it exists is: It provides immediate capture guidance and structured observations before the user commits an image.

### Layman’s explanation

Continuous Vision analysis of preview frames for text, document boundaries, barcodes, scenes, animals, faces, and humans. It provides immediate capture guidance and structured observations before the user commits an image.

### Technical explanation

It precedes capture-to-RAG ingestion and does not itself create a permanent document. Primary code anchors: OpenIntelligence/Features/Camera/CaptureToRAGBridge.swift; OpenIntelligence/Features/Camera/CameraManager.swift.

### Why it is in this position

It precedes capture-to-RAG ingestion and does not itself create a permanent document.

## OI-0052. OCR

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **OCR** means: Optical character recognition that converts pixels into searchable text. The reason it exists is: A scan or camera image contains no machine-readable words, so OCR is required before any exact-word or meaning-based indexing can occur.

### Layman’s explanation

Optical character recognition that converts pixels into searchable text. A scan or camera image contains no machine-readable words, so OCR is required before any lexical or semantic indexing can occur.

### Technical explanation

It follows rendering and preprocessing and precedes structure recovery, normalization, and chunking. Primary code anchors: OpenIntelligence/Services/Document/Config/OCRConfiguration.swift; OpenIntelligence/UI/Components/Glossary.swift.

### Why it is in this position

It follows rendering and preprocessing and precedes structure recovery, normalization, and chunking.

## OI-0053. OCR confidence

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **OCR confidence** means: A score associated with recognized observations or segments indicating recognition certainty. The reason it exists is: Confidence is used to reject weak blocks, trigger rescans, and report transcription or extraction quality rather than silently treating every character as exact.

### Layman’s explanation

A score associated with recognized observations or segments indicating recognition certainty. Confidence is used to reject weak blocks, trigger rescans, and report transcription or extraction quality rather than silently treating every character as exact.

### Technical explanation

It is produced during recognition and consumed before normalization and indexing. Primary code anchors: OpenIntelligence/Services/Document/Processing/LayoutAwareExtractor.swift; OpenIntelligence/Services/Document/Extraction/AudioTranscriptionService.swift.

### Why it is in this position

It is produced during recognition and consumed before normalization and indexing.

## OI-0054. OCRConfiguration

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **OCRConfiguration** means: The central factory and policy authority for recognition revision, accuracy, language correction, languages, minimum text height, custom words, put into a consistent form, and garbage filtering. The reason it exists is: Multiple independently configured Vision requests drift and produce inconsistent extraction. A central authority keeps ingestion and camera recognition aligned.

### Layman’s explanation

The central factory and policy authority for recognition revision, accuracy, language correction, languages, minimum text height, custom words, normalization, and garbage filtering. Multiple independently configured Vision requests drift and produce inconsistent extraction. A central authority keeps ingestion and camera recognition aligned.

### Technical explanation

It configures OCR requests before execution and normalizes results afterward. Primary code anchors: OpenIntelligence/Services/Document/Config/OCRConfiguration.swift.

### Why it is in this position

It configures OCR requests before execution and normalizes results afterward.

## OI-0055. On-device speech requirement

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **On-device speech requirement** means: Setting requiresOnDeviceRecognition on speech-recognition requests. The reason it exists is: It preserves the local-first privacy boundary for imported recordings.

### Layman’s explanation

Setting requiresOnDeviceRecognition on speech-recognition requests. It preserves the local-first privacy boundary for imported recordings.

### Technical explanation

It is applied before each transcription task is launched. Primary code anchors: OpenIntelligence/Services/Document/Extraction/AudioTranscriptionService.swift.

### Why it is in this position

It is applied before each transcription task is launched.

## OI-0056. OOXML / Office parsing

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **OOXML / Office parsing** means: Unzipping and streaming the XML parts of Office documents to recover text and structure. The reason it exists is: DOCX, PPTX, and XLSX are packages, not plain text. Parsing them directly avoids rendering every page as an image.

### Layman’s explanation

Unzipping and streaming the XML parts of Office documents to recover text and structure. DOCX, PPTX, and XLSX are packages, not plain text. Parsing them directly avoids rendering every page as an image.

### Technical explanation

It is selected by file type before normalization and chunking. Primary code anchors: OpenIntelligence/Services/Document/Processing/StreamingXMLProcessor.swift; OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift.

### Why it is in this position

It is selected by file type before normalization and chunking.

## OI-0057. Page complexity class

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **Page complexity class** means: The classification trivial, simple, moderate, complex, visual, or scanned. The reason it exists is: A compact label allows downstream extraction and resource policy to act consistently on many page signals.

### Layman’s explanation

The classification trivial, simple, moderate, complex, visual, or scanned. A compact label allows downstream extraction and resource policy to act consistently on many page signals.

### Technical explanation

It is emitted by page analysis and consumed by rendering, OCR, and structured parsing. Primary code anchors: OpenIntelligence/Services/Document/Chunking/PageComplexityAnalyzer.swift.

### Why it is in this position

It is emitted by page analysis and consumed by rendering, OCR, and structured parsing.

## OI-0058. Page rendering

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **Page rendering** means: Rasterization of a PDF page into an image when visual analysis or OCR is required. The reason it exists is: Scans and complex layouts contain meaning that the native text layer cannot supply.

### Layman’s explanation

Rasterization of a PDF page into an image when visual analysis or OCR is required. Scans and complex layouts contain meaning that the native text layer cannot supply.

### Technical explanation

It occurs after page complexity analysis and before Vision requests. Primary code anchors: OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift; OpenIntelligence/Services/Document/Processing/StructuredDocumentParser.swift.

### Why it is in this position

It occurs after page complexity analysis and before Vision requests.

## OI-0059. Page sentinel

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **Page sentinel** means: A marker inserted between page contents so later processing can preserve page boundaries in a combined text stream. The reason it exists is: Without explicit boundaries, small source pieces and citations could cross pages without knowing where evidence came from.

### Layman’s explanation

A marker inserted between page contents so later processing can preserve page boundaries in a combined text stream. Without explicit boundaries, chunks and citations could cross pages without knowing where evidence came from.

### Technical explanation

It is added during extraction and interpreted while creating page-aware chunks and offsets. Primary code anchors: OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift.

### Why it is in this position

It is added during extraction and interpreted while creating page-aware chunks and offsets.

## OI-0060. PageComplexityAnalyzer

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **PageComplexityAnalyzer** means: A router that combines native PDF structure, text coverage, layout, numeric density, tables, figures, forms, columns, annotations, and selective Vision signals. The reason it exists is: The engine needs to know which pages can use native text and which require expensive visual handling. This prevents both missed content and unnecessary OCR.

### Layman’s explanation

A router that combines native PDF structure, text coverage, layout, numeric density, tables, figures, forms, columns, annotations, and selective Vision signals. The engine needs to know which pages can use native text and which require expensive visual handling. This prevents both missed content and unnecessary OCR.

### Technical explanation

It evaluates pages before extraction strategy and concurrency are chosen. Primary code anchors: OpenIntelligence/Services/Document/Chunking/PageComplexityAnalyzer.swift.

### Why it is in this position

It evaluates pages before extraction strategy and concurrency are chosen.

## OI-0061. PDF text layer

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **PDF text layer** means: The native selectable text embedded in a digitally produced PDF. The reason it exists is: Reading it through PDFKit is faster and more accurate than OCR when it is trustworthy, and it preserves exact characters for offsets and citations.

### Layman’s explanation

The native selectable text embedded in a digitally produced PDF. Reading it through PDFKit is faster and more accurate than OCR when it is trustworthy, and it preserves exact characters for offsets and citations.

### Technical explanation

It is attempted before image recognition and may also seed dynamic OCR vocabulary. Primary code anchors: OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift; OpenIntelligence/Services/Document/Processing/LayoutAwareExtractor.swift.

### Why it is in this position

It is attempted before image recognition and may also seed dynamic OCR vocabulary.

## OI-0062. PDFKit extraction

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **PDFKit extraction** means: Use of PDFPage strings, selections, bounds, annotations, and page objects to recover text and layout directly from the PDF. The reason it exists is: PDFs store text spatially and may expose structure unavailable in a flat string. PDFKit is the first source of high-confidence native evidence.

### Layman’s explanation

Use of PDFPage strings, selections, bounds, annotations, and page objects to recover text and layout directly from the PDF. PDFs store text spatially and may expose structure unavailable in a flat string. PDFKit is the first source of high-confidence native evidence.

### Technical explanation

It precedes Vision OCR unless page analysis decides the text layer is absent or unreliable. Primary code anchors: OpenIntelligence/Services/Document/Processing/LayoutAwareExtractor.swift; OpenIntelligence/Services/Document/Chunking/PageComplexityAnalyzer.swift.

### Why it is in this position

It precedes Vision OCR unless page analysis decides the text layer is absent or unreliable.

## OI-0063. Reading-order reconstruction

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **Reading-order reconstruction** means: Ordering paragraphs, columns, and table regions according to their spatial position on the page. The reason it exists is: Chunking assumes coherent text sequence. Correct words in the wrong order still create a corrupted document collection.

### Layman’s explanation

Ordering paragraphs, columns, and table regions according to their spatial position on the page. Chunking assumes coherent text sequence. Correct words in the wrong order still create a corrupted corpus.

### Technical explanation

It is the final layout step before normalized page text enters document processing. Primary code anchors: OpenIntelligence/Services/Document/Processing/LayoutAwareExtractor.swift.

### Why it is in this position

It is the final layout step before normalized page text enters document processing.

## OI-0064. Recognition-language set

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **Recognition-language set** means: The prioritized language list supplied to Vision together with automatic language detection. The reason it exists is: Limiting OCR to English would corrupt multilingual documents, while unconstrained guessing can degrade recognition. The list defines supported possible result.

### Layman’s explanation

The prioritized language list supplied to Vision together with automatic language detection. Limiting OCR to English would corrupt multilingual documents, while unconstrained guessing can degrade recognition. The list defines supported candidates.

### Technical explanation

It is applied when OCR requests are configured. Primary code anchors: OpenIntelligence/Services/Document/Config/OCRConfiguration.swift.

### Why it is in this position

It is applied when OCR requests are configured.

## OI-0065. RecognizeDocumentsRequest

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **RecognizeDocumentsRequest** means: Vision document recognition that returns paragraphs, lists, tables, and related structure rather than only lines of text. The reason it exists is: A table flattened into reading order destroys row-column relationships. Structured recognition preserves the units that exact lookup and citation need.

### Layman’s explanation

Vision document recognition that returns paragraphs, lists, tables, and related structure rather than only lines of text. A table flattened into reading order destroys row-column relationships. Structured recognition preserves the units that exact lookup and citation need.

### Technical explanation

It is used on scanned or visually complex pages before structured elements are converted to chunks. Primary code anchors: OpenIntelligence/Services/Document/Processing/StructuredDocumentParser.swift.

### Why it is in this position

It is used on scanned or visually complex pages before structured elements are converted to chunks.

## OI-0066. RFC 4180 CSV parsing

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **RFC 4180 CSV parsing** means: Parsing comma-separated data with proper quoting, escaped quotes, embedded separators, and row boundaries. The reason it exists is: Naively splitting on commas corrupts valid cells and destroys table relationships.

### Layman’s explanation

Parsing comma-separated data with proper quoting, escaped quotes, embedded separators, and row boundaries. Naively splitting on commas corrupts valid cells and destroys table relationships.

### Technical explanation

It runs during CSV extraction before table rows are indexed and chunked. Primary code anchors: Docs/HOW_IT_WORKS.md; OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift.

### Why it is in this position

It runs during CSV extraction before table rows are indexed and chunked.

## OI-0067. Segmented transcription

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **Segmented transcription** means: Dividing media longer than the single-recognition limit into temporary time slices, transcribing each, and offsetting segment timestamps back into the full recording. The reason it exists is: Long recordings exceed one recognition task's practical duration and need isolated retries.

### Layman’s explanation

Dividing media longer than the single-recognition limit into temporary time slices, transcribing each, and offsetting segment timestamps back into the full recording. Long recordings exceed one recognition task's practical duration and need isolated retries.

### Technical explanation

It occurs after media duration validation and before combined transcript creation. Primary code anchors: OpenIntelligence/Services/Document/Extraction/AudioTranscriptionService.swift.

### Why it is in this position

It occurs after media duration validation and before combined transcript creation.

## OI-0068. SpatialDocumentAnalyzer

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **SpatialDocumentAnalyzer** means: The analyzer that derives spatial relationships, page regions, and layout-informed document signals. The reason it exists is: Position often carries meaning in forms, diagrams, tables, and multi-column documents.

### Layman’s explanation

The analyzer that derives spatial relationships, page regions, and layout-informed document signals. Position often carries meaning in forms, diagrams, tables, and multi-column documents.

### Technical explanation

It consumes extracted blocks before metadata and chunk construction. Primary code anchors: OpenIntelligence/Services/Document/Analysis/SpatialDocumentAnalyzer.swift.

### Why it is in this position

It consumes extracted blocks before metadata and chunk construction.

## OI-0069. StreamingXMLProcessor

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **StreamingXMLProcessor** means: A bounded-memory XML parser for large packaged document formats. The reason it exists is: Loading an entire XML document object model can create unnecessary memory spikes for large Office files.

### Layman’s explanation

A bounded-memory XML parser for large packaged document formats. Loading an entire XML document object model can create unnecessary memory spikes for large Office files.

### Technical explanation

It runs inside type-specific extraction before structured content is normalized. Primary code anchors: OpenIntelligence/Services/Document/Processing/StreamingXMLProcessor.swift.

### Why it is in this position

It runs inside type-specific extraction before structured content is normalized.

## OI-0070. Structured Office parser

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **Structured Office parser** means: Format-specific extraction of DOCX, PPTX, and related Office package contents by unzipping the container and parsing XML relationships and text nodes. The reason it exists is: Office documents contain native structure that should not be flattened through screenshots or OCR.

### Layman’s explanation

Format-specific extraction of DOCX, PPTX, and related Office package contents by unzipping the container and parsing XML relationships and text nodes. Office documents contain native structure that should not be flattened through screenshots or OCR.

### Technical explanation

It is selected by file type before normalization and chunking. Primary code anchors: OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift; OpenIntelligence/Services/Document/Processing/StreamingXMLProcessor.swift.

### Why it is in this position

It is selected by file type before normalization and chunking.

## OI-0071. StructuredElement

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **StructuredElement** means: A typed paragraph, title, list, table, or figure recovered from a page. The reason it exists is: Typed structure lets the chunker keep tables all-or-nothing, boost headings, and present figures differently from prose.

### Layman’s explanation

A typed paragraph, title, list, table, or figure recovered from a page. Typed structure lets the chunker keep tables atomic, boost headings, and present figures differently from prose.

### Technical explanation

It is emitted by structured parsing and converted into embedding text plus structured metadata. Primary code anchors: OpenIntelligence/Services/Document/Processing/StructuredDocumentParser.swift.

### Why it is in this position

It is emitted by structured parsing and converted into embedding text plus structured metadata.

## OI-0072. Table row record

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **Table row record** means: A labeled representation such as Row 2: Model=1688; Reference=1688-020-122. The reason it exists is: It preserves cross-cell relationships and makes a row independently retrievable.

### Layman’s explanation

A labeled representation such as Row 2: Model=1688; Reference=1688-020-122. It preserves cross-cell relationships and makes a row independently retrievable.

### Technical explanation

It is generated from TableData and stored with the containing chunk or row table. Primary code anchors: OpenIntelligence/Services/Document/Processing/StructuredDocumentParser.swift; OpenIntelligence/Services/Storage/SQLiteFullTextService.swift.

### Why it is in this position

It is generated from TableData and stored with the containing chunk or row table.

## OI-0073. Table schema view

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **Table schema view** means: A concise list of put into a consistent form column names. The reason it exists is: Schema terms are high-signal exact-word anchors for queries such as reference number, dosage, or limit.

### Layman’s explanation

A concise list of normalized column names. Schema terms are high-signal lexical anchors for queries such as reference number, dosage, or limit.

### Technical explanation

It is emitted before row and cell representations in table embedding text. Primary code anchors: OpenIntelligence/Services/Document/Processing/StructuredDocumentParser.swift.

### Why it is in this position

It is emitted before row and cell representations in table embedding text.

## OI-0074. TableData

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **TableData** means: A table representation retaining rows, optional header, caption, detected entities, alignments, and multiple search-oriented text views. The reason it exists is: A number is often meaningful only with its row and column labels. TableData keeps those relationships available to both exact extraction and the model.

### Layman’s explanation

A table representation retaining rows, optional header, caption, detected entities, alignments, and multiple search-oriented text views. A number is often meaningful only with its row and column labels. TableData keeps those relationships available to both exact extraction and the model.

### Technical explanation

It is created during structured recognition and stored as table chunks and row records. Primary code anchors: OpenIntelligence/Services/Document/Processing/StructuredDocumentParser.swift.

### Why it is in this position

It is created during structured recognition and stored as table chunks and row records.

## OI-0075. TextBlock

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **TextBlock** means: A recognized text unit with put into a consistent form bounding box, confidence, page number, and spatial helpers. The reason it exists is: Text must retain position long enough to reconstruct columns, lines, and tables.

### Layman’s explanation

A recognized text unit with normalized bounding box, confidence, page number, and spatial helpers. Text must retain position long enough to reconstruct columns, lines, and tables.

### Technical explanation

It is produced by PDFKit or Vision and consumed by layout clustering. Primary code anchors: OpenIntelligence/Services/Document/Processing/LayoutAwareExtractor.swift.

### Why it is in this position

It is produced by PDFKit or Vision and consumed by layout clustering.

## OI-0076. Transcription segment

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **Transcription segment** means: A recognized phrase or word span with start time, end time, and confidence. The reason it exists is: Timestamped segments allow the indexed text to retain a path back to the original media.

### Layman’s explanation

A recognized phrase or word span with start time, end time, and confidence. Timestamped segments allow the indexed text to retain a path back to the original media.

### Technical explanation

Segments are emitted during transcription and merged before document conversion. Primary code anchors: OpenIntelligence/Services/Document/Extraction/AudioTranscriptionService.swift.

### Why it is in this position

Segments are emitted during transcription and merged before document conversion.

## OI-0077. TranslationService

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **TranslationService** means: The service that translates text when a library or meaning map policy requests a target language while retaining source source history. The reason it exists is: It can improve cross-language meaning map consistency without replacing original evidence.

### Layman’s explanation

The service that translates text when a library or embedding policy requests a target language while retaining source provenance. It can improve cross-language embedding consistency without replacing original evidence.

### Technical explanation

It runs after language detection and before the optional translated embedding path. Primary code anchors: OpenIntelligence/Services/Document/Extraction/TranslationService.swift.

### Why it is in this position

It runs after language detection and before the optional translated embedding path.

## OI-0078. Type-specific extractor

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **Type-specific extractor** means: A parser chosen from the source file type rather than forcing every input through OCR. The reason it exists is: Native PDFs, Office XML, CSV, audio, and images preserve different structure. Using the wrong extractor loses information or performs expensive unnecessary rasterization.

### Layman’s explanation

A parser chosen from the source file type rather than forcing every input through OCR. Native PDFs, Office XML, CSV, audio, and images preserve different structure. Using the wrong extractor loses information or performs expensive unnecessary rasterization.

### Technical explanation

It is selected immediately after the file is loaded and before normalization or chunking. Primary code anchors: OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift.

### Why it is in this position

It is selected immediately after the file is loaded and before normalization or chunking.

## OI-0079. Universal custom words

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **Universal custom words** means: A domain-agnostic OCR vocabulary containing common units, symbols, document abbreviations, and safety labels. The reason it exists is: Vision is more likely to preserve short technical tokens such as mg/dL, N.m, or ISO when they are supplied as expected words.

### Layman’s explanation

A domain-agnostic OCR vocabulary containing common units, symbols, document abbreviations, and safety labels. Vision is more likely to preserve short technical tokens such as mg/dL, N.m, or ISO when they are supplied as expected words.

### Technical explanation

It is included in OCR configuration before a page is recognized. Primary code anchors: OpenIntelligence/Services/Document/Config/OCRConfiguration.swift.

### Why it is in this position

It is included in OCR configuration before a page is recognized.

## OI-0080. VisionOCRThrottle

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **VisionOCRThrottle** means: The semaphore and cooldown policy limiting concurrent Vision requests according to device and execution state. The reason it exists is: Vision and Metal workloads can race, exhaust command buffers, or destabilize memory when launched without bounds.

### Layman’s explanation

The semaphore and cooldown policy limiting concurrent Vision requests according to device and execution state. Vision and Metal workloads can race, exhaust command buffers, or destabilize memory when launched without bounds.

### Technical explanation

Every OCR/layout request acquires the throttle before Vision work and releases it afterward. Primary code anchors: OpenIntelligence/Services/Document/Config/VisionOCRThrottle.swift; OpenIntelligence/Services/Infrastructure/Monitoring/DeviceCapabilityService.swift.

### Why it is in this position

Every OCR/layout request acquires the throttle before Vision work and releases it afterward.

## OI-0081. Visual evidence source

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **Visual evidence source** means: A record showing where something came from describing an image, page region, or visual observation used as answer evidence. The reason it exists is: A generated caption should remain linked to the actual visual region rather than masquerade as ordinary document prose.

### Layman’s explanation

A provenance object describing an image, page region, or visual observation used as answer evidence. A generated caption should remain linked to the actual visual region rather than masquerade as ordinary document prose.

### Technical explanation

It is created during visual extraction and rendered or cited in the response evidence model. Primary code anchors: OpenIntelligence/Services/RAG/Evidence/VisualEvidenceSource.swift; OpenIntelligence/Features/Chat/Response/VisualEvidenceCard.swift.

### Why it is in this position

It is created during visual extraction and rendered or cited in the response evidence model.

## OI-0082. VisualCaptioningService

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **VisualCaptioningService** means: A service that converts selected visual regions into concise textual descriptions suitable for indexing. The reason it exists is: RAG search operates primarily over text and number coordinates, so visual evidence needs a textual bridge.

### Layman’s explanation

A service that converts selected visual regions into concise textual descriptions suitable for indexing. RAG retrieval operates primarily over text and vectors, so visual evidence needs a textual bridge.

### Technical explanation

It follows image detection/understanding and precedes chunk embedding. Primary code anchors: OpenIntelligence/Services/Document/Processing/VisualCaptioningService.swift.

### Why it is in this position

It follows image detection/understanding and precedes chunk embedding.

## OI-0083. VNRecognizeTextRequest

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **VNRecognizeTextRequest** means: Vision line-oriented text recognition used for OCR blocks, live camera frames, and layout extraction. The reason it exists is: It provides recognized strings, confidence, and bounding boxes for spatial reconstruction.

### Layman’s explanation

Vision line-oriented text recognition used for OCR blocks, live camera frames, and layout extraction. It provides recognized strings, confidence, and bounding boxes for spatial reconstruction.

### Technical explanation

It is one OCR route selected for text blocks and live analysis. Primary code anchors: OpenIntelligence/Services/Document/Config/OCRConfiguration.swift; OpenIntelligence/Services/Document/Processing/LayoutAwareExtractor.swift.

### Why it is in this position

It is one OCR route selected for text blocks and live analysis.

## OI-0084. YOLODetectionService

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **YOLODetectionService** means: An object-detection service using a YOLO-family model path for recognized visual objects. The reason it exists is: Object labels and bounds can enrich otherwise text-poor pages and camera captures.

### Layman’s explanation

An object-detection service using a YOLO-family model path for recognized visual objects. Object labels and bounds can enrich otherwise text-poor pages and camera captures.

### Technical explanation

It runs during image understanding and contributes visual metadata rather than replacing text retrieval. Primary code anchors: OpenIntelligence/Services/Document/Classification/YOLODetectionService.swift.

### Why it is in this position

It runs during image understanding and contributes visual metadata rather than replacing text retrieval.

## OI-0085. Zero-copy image path

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a reading room and scanner. **Zero-copy image path** means: Conversion and handoff designed to avoid serializing page images through PNG or repeatedly allocating full intermediate buffers. The reason it exists is: A 400-page document can be killed by memory pressure even when the text logic is correct. Avoiding round trips reduces peak memory and latency.

### Layman’s explanation

Conversion and handoff designed to avoid serializing page images through PNG or repeatedly allocating full intermediate buffers. A 400-page document can be killed by memory pressure even when the text logic is correct. Avoiding round trips reduces peak memory and latency.

### Technical explanation

It is used inside render-to-Vision paths before OCR and structured recognition. Primary code anchors: OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift; Docs/HOW_IT_WORKS.md.

### Why it is in this position

It is used inside render-to-Vision paths before OCR and structured recognition.

---

# 03. Document analysis, adaptation, and derived knowledge

**Section orientation:** This layer derives metadata and higher-level knowledge from extracted content. It includes entities, specifications, document summaries, abstraction levels, reference-list detection, and RAPTOR-lite.

## OI-0086. Chunk abstraction level

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a librarian adding labels and summaries. **Chunk abstraction level** means: labels and facts distinguishing detail L0, document summary L1, and reserved future cluster or library summaries L2-L3. The reason it exists is: Queries at different scopes need different evidence granularity. Explicit levels prevent a broad summary from competing invisibly with a precise detail small source piece.

### Layman’s explanation

Metadata distinguishing detail L0, document summary L1, and reserved future cluster or library summaries L2-L3. Queries at different scopes need different evidence granularity. Explicit levels prevent a broad summary from competing invisibly with a precise detail chunk.

### Technical explanation

It is assigned during chunk creation and used during query routing and context selection. Primary code anchors: OpenIntelligence/Core/Models/DocumentChunk.swift.

### Why it is in this position

It is assigned during chunk creation and used during query routing and context selection.

## OI-0087. Content tagging

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a librarian adding labels and summaries. **Content tagging** means: Foundation Models extraction of topics, actions, emotions, and objects with an NLTagger fallback and timeout. The reason it exists is: Tags improve library navigation and search vocabulary, but must not block ingestion if the model is unavailable.

### Layman’s explanation

Foundation Models extraction of topics, actions, emotions, and objects with an NLTagger fallback and timeout. Tags improve library navigation and retrieval vocabulary, but must not block ingestion if the model is unavailable.

### Technical explanation

It runs after enough representative text exists and before metadata is finalized. Primary code anchors: OpenIntelligence/Services/Document/Chunking/ContentTaggingService.swift.

### Why it is in this position

It runs after enough representative text exists and before metadata is finalized.

## OI-0088. Derived metadata

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a librarian adding labels and summaries. **Derived metadata** means: The set of section, page, offsets, keywords, entities, abbreviations, structure, numeric flags, siblings, bounds, table data, and summary level level attached to a small source piece. The reason it exists is: Ranking, expansion, citation, and verification need more than text and a number coordinates. labels and facts carries the document relationships that meaning map discard.

### Layman’s explanation

The set of section, page, offsets, keywords, entities, abbreviations, structure, numeric flags, siblings, bounds, table data, and abstraction level attached to a chunk. Ranking, expansion, citation, and verification need more than text and a vector. Metadata carries the document relationships that embeddings discard.

### Technical explanation

It is created during ingestion and travels with each chunk through retrieval and response construction. Primary code anchors: OpenIntelligence/Core/Models/DocumentChunk.swift.

### Why it is in this position

It is created during ingestion and travels with each chunk through retrieval and response construction.

## OI-0089. Document classification

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a librarian adding labels and summaries. **Document classification** means: Assignment of a broad document category or structural class from text and visual signals. The reason it exists is: Category can guide chunking, suggestions, and diagnostics without hardcoding a domain-specific parser.

### Layman’s explanation

Assignment of a broad document category or structural class from text and visual signals. Category can guide chunking, suggestions, and diagnostics without hardcoding a domain-specific parser.

### Technical explanation

It occurs during analysis before final metadata and derived services are stored. Primary code anchors: OpenIntelligence/Services/Document/Classification/CoreMLDocumentClassifier.swift; OpenIntelligence/Core/Models/DocumentChunk.swift.

### Why it is in this position

It occurs during analysis before final metadata and derived services are stored.

## OI-0090. Document summary chunk

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a librarian adding labels and summaries. **Document summary chunk** means: A short level-1 summary generated from representative detail small source pieces, embedded, and indexed as a special small source piece. The reason it exists is: Overview questions should not require retrieving dozens of detail passages. A summary provides an summary level-level entry point.

### Layman’s explanation

A short level-1 summary generated from representative detail chunks, embedded, and indexed as a special chunk. Overview questions should not require retrieving dozens of detail passages. A summary provides an abstraction-level entry point.

### Technical explanation

It is generated after detail chunks exist and before the document index is finalized. Primary code anchors: OpenIntelligence/Services/Document/Analysis/DocumentSummaryService.swift.

### Why it is in this position

It is generated after detail chunks exist and before the document index is finalized.

## OI-0091. Entity extraction

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a librarian adding labels and summaries. **Entity extraction** means: Identification of names, organizations, places, and other salient terms attached to small source piece labels and facts. The reason it exists is: Entities provide high-signal exact-word fields and enable cross-document expansion without another full number coordinates search.

### Layman’s explanation

Identification of names, organizations, places, and other salient terms attached to chunk metadata. Entities provide high-signal lexical fields and enable cross-document expansion without another full vector search.

### Technical explanation

It occurs while enriching chunks and before entity-index insertion. Primary code anchors: OpenIntelligence/Services/Document/Chunking/SemanticChunker.swift; OpenIntelligence/Services/Document/Analysis/EntityIndexService.swift.

### Why it is in this position

It occurs while enriching chunks and before entity-index insertion.

## OI-0092. Entity index

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a librarian adding labels and summaries. **Entity index** means: A saved forward and reverse mapping between put into a consistent form entity names and small source piece IDs, with document and container scope. The reason it exists is: It enables O(1)-style cross-document correlation and GraphRAG-lite expansion from entities already found in relevant small source pieces.

### Layman’s explanation

A persisted forward and reverse mapping between normalized entity names and chunk IDs, with document and container scope. It enables O(1)-style cross-document correlation and GraphRAG-lite expansion from entities already found in relevant chunks.

### Technical explanation

It is populated after chunks receive entities and queried during agentic or graph expansion. Primary code anchors: OpenIntelligence/Services/Document/Analysis/EntityIndexService.swift.

### Why it is in this position

It is populated after chunks receive entities and queried during agentic or graph expansion.

## OI-0093. Entity normalization

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a librarian adding labels and summaries. **Entity normalization** means: Lowercasing and removal of periods, hyphens, and whitespace to align variants such as U.S.A. and USA or Core Data and CoreData. The reason it exists is: Exact string identity would fragment the entity graph into spelling variants.

### Layman’s explanation

Lowercasing and removal of periods, hyphens, and whitespace to align variants such as U.S.A. and USA or Core Data and CoreData. Exact string identity would fragment the entity graph into spelling variants.

### Technical explanation

It happens when indexing and looking up entities. Primary code anchors: OpenIntelligence/Services/Document/Analysis/EntityIndexService.swift.

### Why it is in this position

It happens when indexing and looking up entities.

## OI-0094. GraphRAG-lite

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a librarian adding labels and summaries. **GraphRAG-lite** means: Expansion from retrieved small source pieces to other small source pieces connected by shared entities or explicit document relationships. The reason it exists is: number coordinates similarity may miss a relevant passage that uses a different wording but shares an important named entity or reference.

### Layman’s explanation

Expansion from retrieved chunks to other chunks connected by shared entities or explicit document relationships. Vector similarity may miss a relevant passage that uses a different wording but shares an important named entity or reference.

### Technical explanation

It occurs after initial retrieval and before final context packing in deeper paths. Primary code anchors: OpenIntelligence/Services/Document/Analysis/EntityIndexService.swift; OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift; OpenIntelligence/Services/RAG/Retrieval/GraphIndexService.swift.

**Important caveat:** Also participates in 08. Retrieval, fusion, reranking, and evidence expansion.

### Why it is in this position

It occurs after initial retrieval and before final context packing in deeper paths.

## OI-0095. Predictive pre-scan

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a librarian adding labels and summaries. **Predictive pre-scan** means: A sample-based analysis of early pages or characters that estimates code, mathematics, lists, tables, columns, and vocabulary before the full import. The reason it exists is: Chunking and OCR configuration are expensive to change after every page has been embedded. A pre-scan selects a reasonable plan up front.

### Layman’s explanation

A sample-based analysis of early pages or characters that estimates code, mathematics, lists, tables, columns, and vocabulary before the full import. Chunking and OCR configuration are expensive to change after every page has been embedded. A pre-scan selects a reasonable plan up front.

### Technical explanation

It occurs after the file is accessible but before bulk page extraction and chunking. Primary code anchors: Docs/HOW_IT_WORKS.md; OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift.

### Why it is in this position

It occurs after the file is accessible but before bulk page extraction and chunking.

## OI-0096. RAPTOR-lite

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a librarian adding labels and summaries. **RAPTOR-lite** means: A shallow hierarchical search design using level-0 detail small source pieces and level-1 document summaries. The reason it exists is: It offers fast overview routing without the cost and complexity of recursively clustering and summarizing the whole document collection.

### Layman’s explanation

A shallow hierarchical retrieval design using level-0 detail chunks and level-1 document summaries. It offers fast overview routing without the cost and complexity of recursively clustering and summarizing the whole corpus.

### Technical explanation

Summary chunks are created during ingestion and selected by overview query routing. Primary code anchors: OpenIntelligence/Services/Document/Analysis/DocumentSummaryService.swift; OpenIntelligence/Services/RAG/Retrieval/RAPTORSummaryRouter.swift.

### Why it is in this position

Summary chunks are created during ingestion and selected by overview query routing.

## OI-0097. Reference-list detection

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a librarian adding labels and summaries. **Reference-list detection** means: Identification of bibliography or reference sections so they can be penalized, excluded from samples, or treated differently. The reason it exists is: Reference pages contain dense names and numbers that can dominate search despite not answering the question.

### Layman’s explanation

Identification of bibliography or reference sections so they can be penalized, excluded from samples, or treated differently. Reference pages contain dense names and numbers that can dominate retrieval despite not answering the question.

### Technical explanation

It runs during document analysis and influences tagging, chunk metadata, and ranking policy. Primary code anchors: OpenIntelligence/Services/Document/Analysis/ReferenceListDetector.swift.

### Why it is in this position

It runs during document analysis and influences tagging, chunk metadata, and ranking policy.

## OI-0098. Representative-text sampling

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a librarian adding labels and summaries. **Representative-text sampling** means: Selection of the first small source piece, high-meaning-based-density small source pieces, and the final small source piece within a strict character budget for summary generation. The reason it exists is: Feeding the entire document exceeds context, while only taking the beginning misses conclusions and dense middle sections.

### Layman’s explanation

Selection of the first chunk, high-semantic-density chunks, and the final chunk within a strict character budget for summary generation. Feeding the entire document exceeds context, while only taking the beginning misses conclusions and dense middle sections.

### Technical explanation

It precedes document-summary generation. Primary code anchors: OpenIntelligence/Services/Document/Analysis/DocumentSummaryService.swift.

### Why it is in this position

It precedes document-summary generation.

## OI-0099. Spatial document analysis

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a librarian adding labels and summaries. **Spatial document analysis** means: Analysis of page positions and regions to connect visual or structured elements with surrounding text. The reason it exists is: Diagrams, captions, and table context can be lost if spatial relationships are discarded too early.

### Layman’s explanation

Analysis of page positions and regions to connect visual or structured elements with surrounding text. Diagrams, captions, and table context can be lost if spatial relationships are discarded too early.

### Technical explanation

It operates after page recognition and before final structured chunks are emitted. Primary code anchors: OpenIntelligence/Services/Document/Analysis/SpatialDocumentAnalyzer.swift.

### Why it is in this position

It operates after page recognition and before final structured chunks are emitted.

## OI-0100. Specification detection

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a librarian adding labels and summaries. **Specification detection** means: Domain-agnostic recognition of structural patterns such as codes, standards, measurements, grades, part numbers, percentages, ranges, and ratios. The reason it exists is: Exact values are often more reliably extracted by shape than inferred by a model. The detector also flags spec-heavy passages for ranking boosts.

### Layman’s explanation

Domain-agnostic recognition of structural patterns such as codes, standards, measurements, grades, part numbers, percentages, ranges, and ratios. Exact values are often more reliably extracted by shape than inferred by a model. The detector also flags spec-heavy passages for ranking boosts.

### Technical explanation

It runs on extracted text before or during chunk analysis and later reappears in extractive QA. Primary code anchors: OpenIntelligence/Services/Document/Analysis/SpecificationDetector.swift.

### Why it is in this position

It runs on extracted text before or during chunk analysis and later reappears in extractive QA.

---

# 04. Chunking and tokenizer integrity

**Section orientation:** Chunking balances precision against context. The engine respects sentence and section boundaries, preserves tables and lists, creates overlap, attaches parent context, and validates the real tokenizer ceiling.

## OI-0101. 510-token embedding ceiling

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a cutting a book into well-sized index cards. **510-token embedding ceiling** means: The maximum safe sequence length used by the default sentence embedder after reserving model special tokens. The reason it exists is: Exceeding it risks silent truncation and index corruption.

### Layman’s explanation

The maximum safe sequence length used by the default sentence embedder after reserving model special tokens. Exceeding it risks silent truncation and index corruption.

### Technical explanation

It constrains chunk construction and is rechecked at embedding time. Primary code anchors: OpenIntelligence/Services/Embedding/Providers/EmbeddingProvider.swift; Docs/HOW_IT_WORKS.md.

### Why it is in this position

It constrains chunk construction and is rechecked at embedding time.

## OI-0102. Actual tokenizer validation

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a cutting a book into well-sized index cards. **Actual tokenizer validation** means: Counting the exact word-piece tokens with the tokenizer paired to the meaning map model before accepting a small source piece. The reason it exists is: Word count is only an estimate. A small source piece that exceeds the model sequence limit may be silently truncated, creating an meaning map that represents only its beginning.

### Layman’s explanation

Counting the exact word-piece tokens with the tokenizer paired to the embedding model before accepting a chunk. Word count is only an estimate. A chunk that exceeds the model sequence limit may be silently truncated, creating an embedding that represents only its beginning.

### Technical explanation

It occurs after chunk construction and before embedding and indexing. Primary code anchors: OpenIntelligence/Services/Embedding/EmbeddingService.swift; OpenIntelligence/swift-transformers/Sources/TokenizersWrapper/Resources/embedding_tokenizer.bundle/tokenizer.json.

### Why it is in this position

It occurs after chunk construction and before embedding and indexing.

## OI-0103. Atomic structural block

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a cutting a book into well-sized index cards. **Atomic structural block** means: A table, list, warning, or other structure that the chunker avoids splitting internally. The reason it exists is: A cell without its header or a warning without its conditions can become misleading evidence.

### Layman’s explanation

A table, list, warning, or other structure that the chunker avoids splitting internally. A cell without its header or a warning without its conditions can become misleading evidence.

### Technical explanation

It is recognized during structure parsing and handed to chunking as an indivisible unit when feasible. Primary code anchors: OpenIntelligence/Services/Document/Processing/StructuredDocumentParser.swift; OpenIntelligence/Services/Document/Chunking/SemanticChunker.swift.

### Why it is in this position

It is recognized during structure parsing and handed to chunking as an indivisible unit when feasible.

## OI-0104. Chunk

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a cutting a book into well-sized index cards. **Chunk** means: A passage-sized search unit derived from a document, carrying content, source identity, labels and facts, and usually an meaning map. The reason it exists is: Whole documents are too broad for precise ranking and too large for model context. small source pieces make search granular while retaining enough local meaning.

### Layman’s explanation

A passage-sized retrieval unit derived from a document, carrying content, source identity, metadata, and usually an embedding. Whole documents are too broad for precise ranking and too large for model context. Chunks make retrieval granular while retaining enough local meaning.

### Technical explanation

Chunks are created after extraction and analysis and become the unit indexed, ranked, packed, cited, and verified. Primary code anchors: OpenIntelligence/Core/Models/DocumentChunk.swift; OpenIntelligence/UI/Components/Glossary.swift.

### Why it is in this position

Chunks are created after extraction and analysis and become the unit indexed, ranked, packed, cited, and verified.

## OI-0105. Chunk offset

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a cutting a book into well-sized index cards. **Chunk offset** means: The character or byte start and end positions locating a small source piece or selected sentence inside source content. The reason it exists is: Exact offsets enable source jumping, citation quotes, and post-search sentence selection without fuzzy text searches.

### Layman’s explanation

The character or byte start and end positions locating a chunk or selected sentence inside source content. Exact offsets enable source jumping, citation quotes, and post-retrieval sentence selection without fuzzy text searches.

### Technical explanation

They are computed during tokenization/chunking and consumed during citation and contextual compression. Primary code anchors: OpenIntelligence/Core/Models/DocumentChunk.swift; OpenIntelligence/Services/RAG/Tuning/EvidenceScoringPolicyService.swift.

### Why it is in this position

They are computed during tokenization/chunking and consumed during citation and contextual compression.

## OI-0106. Chunk overlap

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a cutting a book into well-sized index cards. **Chunk overlap** means: Repeated trailing context from one passage at the beginning of the next. The reason it exists is: Overlap protects facts and sentences near a boundary from being split out of both useful search units.

### Layman’s explanation

Repeated trailing context from one passage at the beginning of the next. Overlap protects facts and sentences near a boundary from being split out of both useful retrieval units.

### Technical explanation

It is added when one chunk closes and the next begins, before embedding. Primary code anchors: OpenIntelligence/Services/Document/Chunking/SemanticChunker.swift.

### Why it is in this position

It is added when one chunk closes and the next begins, before embedding.

## OI-0107. Chunk semantic type

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a cutting a book into well-sized index cards. **Chunk semantic type** means: A label such as prose, structural table, meaning-based table, list item, or warning. The reason it exists is: Different structures deserve different ranking, packing, and verification treatment.

### Layman’s explanation

A label such as prose, structural table, semantic table, list item, or warning. Different structures deserve different ranking, packing, and verification treatment.

### Technical explanation

It is assigned during ingestion and consulted during retrieval boosts and answer-intent packing. Primary code anchors: OpenIntelligence/Core/Models/DocumentChunk.swift.

### Why it is in this position

It is assigned during ingestion and consulted during retrieval boosts and answer-intent packing.

## OI-0108. Contextual prefix

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a cutting a book into well-sized index cards. **Contextual prefix** means: A short document and section label prepended to the text used for meaning map. The reason it exists is: A passage removed from its document can lose its subject. Prefixes restore that context in the number coordinates without altering the quoted source text.

### Layman’s explanation

A short document and section label prepended to the text used for embedding. A passage removed from its document can lose its subject. Prefixes restore that context in the vector without altering the quoted source text.

### Technical explanation

It is generated with chunk metadata immediately before embedding. Primary code anchors: OpenIntelligence/Core/Models/DocumentChunk.swift; Docs/HOW_IT_WORKS.md.

### Why it is in this position

It is generated with chunk metadata immediately before embedding.

## OI-0109. Cross-reference metadata

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a cutting a book into well-sized index cards. **Cross-reference metadata** means: References from one small source piece to a page, table, figure, section, chapter, appendix, or step. The reason it exists is: Manuals often answer a question indirectly by pointing elsewhere. Capturing the edge lets the graph fetch the target evidence.

### Layman’s explanation

References from one chunk to a page, table, figure, section, chapter, appendix, or step. Manuals often answer a question indirectly by pointing elsewhere. Capturing the edge lets the graph fetch the target evidence.

### Technical explanation

It is extracted during ingestion and traversed after initial retrieval. Primary code anchors: OpenIntelligence/Core/Models/DocumentChunk.swift; OpenIntelligence/Services/RAG/Retrieval/GraphIndexService.swift.

### Why it is in this position

It is extracted during ingestion and traversed after initial retrieval.

## OI-0110. Linguistic transition boundary

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a cutting a book into well-sized index cards. **Linguistic transition boundary** means: A break triggered by a small set of English discourse phrases such as However or In conclusion. The reason it exists is: Transitions often signal a new argument or summary and can improve passage coherence.

### Layman’s explanation

A break triggered by a small set of English discourse phrases such as However or In conclusion. Transitions often signal a new argument or summary and can improve passage coherence.

### Technical explanation

It is considered after sentence segmentation and heading detection. Primary code anchors: OpenIntelligence/Services/Document/Chunking/SemanticChunker.swift.

**Important caveat:** The phrase list is English-specific, and the implemented embedding-boundary path is currently inactive.

### Why it is in this position

It is considered after sentence segmentation and heading detection.

## OI-0111. Maximum chunk size

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a cutting a book into well-sized index cards. **Maximum chunk size** means: The hard ceiling, currently designed around no more than about 310 words before additional tokenizer validation. The reason it exists is: An overlong passage risks meaning map truncation and consumes too much generation context.

### Layman’s explanation

The hard ceiling, currently designed around no more than about 310 words before additional tokenizer validation. An overlong passage risks embedding truncation and consumes too much generation context.

### Technical explanation

It is enforced while chunking, then independently checked by the real tokenizer. Primary code anchors: OpenIntelligence/Services/Document/Chunking/SemanticChunker.swift; Docs/HOW_IT_WORKS.md.

### Why it is in this position

It is enforced while chunking, then independently checked by the real tokenizer.

## OI-0112. Mixed chunk strategy compatibility

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a cutting a book into well-sized index cards. **Mixed chunk strategy compatibility** means: The ability to retain small source pieces made with different sizes or overlap settings in one number coordinates space. The reason it exists is: small source piece boundaries change what a number coordinates represents but do not change the coordinate system, so old and new small source pieces remain comparable.

### Layman’s explanation

The ability to retain chunks made with different sizes or overlap settings in one vector space. Chunk boundaries change what a vector represents but do not change the coordinate system, so old and new chunks remain comparable.

### Technical explanation

It matters during incremental configuration changes and rebuild decisions. Primary code anchors: Docs/HOW_IT_WORKS.md.

**Important caveat:** This does not apply to changing the embedding model, dimension, tokenizer, or pooling recipe.

### Why it is in this position

It matters during incremental configuration changes and rebuild decisions.

## OI-0113. Parent content

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a cutting a book into well-sized index cards. **Parent content** means: A larger source span retained beside the smaller search small source piece. The reason it exists is: Small small source pieces rank precisely, but generation and citations may need the surrounding paragraph or row context to interpret them correctly.

### Layman’s explanation

A larger source span retained beside the smaller retrieval chunk. Small chunks rank precisely, but generation and citations may need the surrounding paragraph or row context to interpret them correctly.

### Technical explanation

It is attached during ingestion and restored after ranking or during context selection. Primary code anchors: OpenIntelligence/Core/Models/DocumentChunk.swift; OpenIntelligence/Services/RAG/Retrieval/ParentDocumentService.swift.

### Why it is in this position

It is attached during ingestion and restored after ranking or during context selection.

## OI-0114. Section-heading boundary

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a cutting a book into well-sized index cards. **Section-heading boundary** means: A forced or preferred small source piece break around detected headings. The reason it exists is: A heading defines local topic and is also valuable search labels and facts. Crossing it can mix unrelated sections.

### Layman’s explanation

A forced or preferred chunk break around detected headings. A heading defines local topic and is also valuable retrieval metadata. Crossing it can mix unrelated sections.

### Technical explanation

It is evaluated while the chunker walks sentences and structure. Primary code anchors: OpenIntelligence/Services/Document/Chunking/SemanticChunker.swift.

### Why it is in this position

It is evaluated while the chunker walks sentences and structure.

## OI-0115. Semantic density

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a cutting a book into well-sized index cards. **Semantic density** means: A heuristic indication of how information-rich a passage is. The reason it exists is: Density helps choose representative small source pieces for document summaries and can support diagnostics or prioritization.

### Layman’s explanation

A heuristic indication of how information-rich a passage is. Density helps choose representative chunks for document summaries and can support diagnostics or prioritization.

### Technical explanation

It is calculated during analysis and stored in chunk metadata. Primary code anchors: OpenIntelligence/Core/Models/DocumentChunk.swift; OpenIntelligence/Services/Document/Analysis/DocumentSummaryService.swift.

### Why it is in this position

It is calculated during analysis and stored in chunk metadata.

## OI-0116. SemanticChunker

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a cutting a book into well-sized index cards. **SemanticChunker** means: The small source piece-building service that uses sentence boundaries, section headings, structural blocks, and linguistic transition phrases to form bounded passages. The reason it exists is: It preserves coherent units better than fixed character slicing and supplies labels and facts required by later stages.

### Layman’s explanation

The chunk-building service that uses sentence boundaries, section headings, structural blocks, and linguistic transition phrases to form bounded passages. It preserves coherent units better than fixed character slicing and supplies metadata required by later stages.

### Technical explanation

It runs after normalized document text and structured elements are available. Primary code anchors: OpenIntelligence/Services/Document/Chunking/SemanticChunker.swift.

### Why it is in this position

It runs after normalized document text and structured elements are available.

## OI-0117. Sentence boundary

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a cutting a book into well-sized index cards. **Sentence boundary** means: A Natural Language tokenizer boundary used as the smallest ordinary prose split point. The reason it exists is: Breaking inside a sentence harms meaning, offsets, and citation quality.

### Layman’s explanation

A Natural Language tokenizer boundary used as the smallest ordinary prose split point. Breaking inside a sentence harms meaning, offsets, and citation quality.

### Technical explanation

Sentence segmentation happens before passages are accumulated toward target size. Primary code anchors: OpenIntelligence/Services/Document/Chunking/SemanticChunker.swift.

### Why it is in this position

Sentence segmentation happens before passages are accumulated toward target size.

## OI-0118. Sibling group

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a cutting a book into well-sized index cards. **Sibling group** means: labels and facts linking small source pieces created from the same section, page, or structural parent. The reason it exists is: search can recover one precise hit and then restore adjacent context without broadening the search globally.

### Layman’s explanation

Metadata linking chunks created from the same section, page, or structural parent. Retrieval can recover one precise hit and then restore adjacent context without broadening the search globally.

### Technical explanation

It is assigned at ingestion and used by ParentDocumentService after reranking. Primary code anchors: OpenIntelligence/Core/Models/DocumentChunk.swift; OpenIntelligence/Services/RAG/Retrieval/ParentDocumentService.swift.

### Why it is in this position

It is assigned at ingestion and used by ParentDocumentService after reranking.

## OI-0119. Target chunk size

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a cutting a book into well-sized index cards. **Target chunk size** means: The preferred word count toward which the chunker accumulates content. The reason it exists is: A target balances meaning-based completeness against search precision and meaning map limits.

### Layman’s explanation

The preferred word count toward which the chunker accumulates content. A target balances semantic completeness against retrieval precision and embedding limits.

### Technical explanation

It is resolved by document plan and used before the hard maximum is reached. Primary code anchors: OpenIntelligence/Services/Document/Chunking/SemanticChunker.swift; OpenIntelligence/Core/Models/KnowledgeContainer.swift.

### Why it is in this position

It is resolved by document plan and used before the hard maximum is reached.

## OI-0120. Tokenizer-model pairing

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a cutting a book into well-sized index cards. **Tokenizer-model pairing** means: The requirement that the tokenizer vocabulary and preprocessing recipe match the model that consumes the token IDs. The reason it exists is: A valid tensor produced by the wrong tokenizer does not represent the intended text and can destroy search quality without crashing.

### Layman’s explanation

The requirement that the tokenizer vocabulary and preprocessing recipe match the model that consumes the token IDs. A valid tensor produced by the wrong tokenizer does not represent the intended text and can destroy retrieval quality without crashing.

### Technical explanation

It is recorded in the embedding fingerprint and validated whenever a provider is selected or rebuilt. Primary code anchors: OpenIntelligence/Services/Embedding/EmbeddingFingerprint.swift.

### Why it is in this position

It is recorded in the embedding fingerprint and validated whenever a provider is selected or rebuilt.

## OI-0121. Word-piece token

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a cutting a book into well-sized index cards. **Word-piece token** means: A model vocabulary unit that may be a whole word, fragment, punctuation mark, or symbol. The reason it exists is: meaning map sequence limits are measured in tokens, not words or characters, so technical text can consume capacity unexpectedly quickly.

### Layman’s explanation

A model vocabulary unit that may be a whole word, fragment, punctuation mark, or symbol. Embedding sequence limits are measured in tokens, not words or characters, so technical text can consume capacity unexpectedly quickly.

### Technical explanation

Tokens are produced immediately before model inference for embedding or reranking. Primary code anchors: OpenIntelligence/Services/Embedding/Providers/EmbeddingProvider.swift.

### Why it is in this position

Tokens are produced immediately before model inference for embedding or reranking.

---

# 05. Embeddings and vector semantics

**Section orientation:** Embeddings convert text into fixed-length numerical vectors. Provider identity, tokenizer, pooling, normalization, and dimension all determine what those coordinates mean.

## OI-0122. Apple Foundation Models embedding provider

**Status:** Dormant, meaning it is implemented or scaffolded, but not a functioning ordinary shipping path.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **Apple Foundation Models embedding provider** means: A nominal 1,024-dimensional provider scaffold intended for future Apple Foundation Models meaning map support. The reason it exists is: The summary level anticipates a native Apple meaning map capability while preserving the provider interface.

### Layman’s explanation

A nominal 1,024-dimensional provider scaffold intended for future Apple Foundation Models embedding support. The abstraction anticipates a native Apple embedding capability while preserving the provider interface.

### Technical explanation

It is present in source but must not be treated as a working ingestion or query path. Primary code anchors: OpenIntelligence/Services/Embedding/Providers/AppleFMEmbeddingProvider.swift.

**Important caveat:** The current implementation is a nonfunctional placeholder, not a shipped 1,024-dimensional embedder.

### Why it is in this position

It is present in source but must not be treated as a working ingestion or query path.

## OI-0123. Attention mask

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **Attention mask** means: A tensor marking which token positions are real input and which are padding. The reason it exists is: Pooling padded positions would dilute the passage number coordinates and make output depend on batch padding rather than text.

### Layman’s explanation

A tensor marking which token positions are real input and which are padding. Pooling padded positions would dilute the passage vector and make output depend on batch padding rather than text.

### Technical explanation

It is built with token IDs, consumed by the model, and reused during masked pooling. Primary code anchors: OpenIntelligence/Services/Embedding/Providers/CoreMLSentenceEmbeddingProvider.swift.

### Why it is in this position

It is built with token IDs, consumed by the model, and reused during masked pooling.

## OI-0124. Attention-masked mean pooling

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **Attention-masked mean pooling** means: Averaging token-state number coordinates while excluding padded positions according to the attention mask. The reason it exists is: The model exports token meaning map, not a trustworthy ready-made sentence number coordinates. Correct pooling is load-bearing for search quality.

### Layman’s explanation

Averaging token-state vectors while excluding padded positions according to the attention mask. The model exports token embeddings, not a trustworthy ready-made sentence vector. Correct pooling is load-bearing for retrieval quality.

### Technical explanation

It follows inference and precedes L2 normalization. Primary code anchors: OpenIntelligence/Services/Embedding/Providers/CoreMLSentenceEmbeddingProvider.swift; Docs/Engineering/EMBEDDING_MEAN_POOLING_REEXPORT.md.

### Why it is in this position

It follows inference and precedes L2 normalization.

## OI-0125. Bi-encoder

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **Bi-encoder** means: An architecture that encodes the question and each passage independently into number coordinates, then compares those number coordinates. The reason it exists is: Independent passage number coordinates can be precomputed once during ingestion, making document collection-wide search fast enough on device.

### Layman’s explanation

An architecture that encodes the query and each passage independently into vectors, then compares those vectors. Independent passage vectors can be precomputed once during ingestion, making corpus-wide retrieval fast enough on device.

### Technical explanation

It is the first semantic retrieval stage and precedes the more expensive cross-encoder reranker. Primary code anchors: OpenIntelligence/Services/Embedding/Providers/CoreMLSentenceEmbeddingProvider.swift; OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift.

### Why it is in this position

It is the first semantic retrieval stage and precedes the more expensive cross-encoder reranker.

## OI-0126. Core AI sentence provider

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **Core AI sentence provider** means: An iOS/macOS 27 provider for the same 384-dimensional model through Apple's newer Core AI compilation path when available. The reason it exists is: It creates a future-facing execution path without changing the number coordinates space or forcing a library rebuild solely because the runtime backend changed.

### Layman’s explanation

An iOS/macOS 27 provider for the same 384-dimensional model through Apple's newer Core AI compilation path when available. It creates a future-facing execution path without changing the vector space or forcing a library rebuild solely because the runtime backend changed.

### Technical explanation

It is selected conditionally before falling back to the Core ML provider. Primary code anchors: OpenIntelligence/Services/Embedding/Providers/CoreAISentenceEmbeddingProvider.swift.

### Why it is in this position

It is selected conditionally before falling back to the Core ML provider.

## OI-0127. Core ML sentence provider

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **Core ML sentence provider** means: The default provider that loads the bundled meaning map model, builds tensors, runs model answering, pools token states, and normalizes the result. The reason it exists is: Core ML provides a supported on-device execution layer and lets Apple schedule work across CPU, GPU, and Neural Engine.

### Layman’s explanation

The default provider that loads the bundled embedding model, builds tensors, runs inference, pools token states, and normalizes the result. Core ML provides a supported on-device execution layer and lets Apple schedule work across CPU, GPU, and Neural Engine.

### Technical explanation

It implements the provider contract beneath EmbeddingService. Primary code anchors: OpenIntelligence/Services/Embedding/Providers/CoreMLSentenceEmbeddingProvider.swift.

### Why it is in this position

It implements the provider contract beneath EmbeddingService.

## OI-0128. Cosine similarity

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **Cosine similarity** means: The put into a consistent form dot product measuring the angle between question and passage number coordinates, conventionally in the range minus one to one. The reason it exists is: It compares meaning-based direction without allowing number coordinates magnitude to dominate.

### Layman’s explanation

The normalized dot product measuring the angle between query and passage vectors, conventionally in the range minus one to one. It compares semantic direction without allowing vector magnitude to dominate.

### Technical explanation

It is calculated during dense retrieval before hybrid fusion. Primary code anchors: OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift; OpenIntelligence/UI/Components/Glossary.swift.

### Why it is in this position

It is calculated during dense retrieval before hybrid fusion.

## OI-0129. Default MiniLM provider

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **Default MiniLM provider** means: The shipped 384-dimensional MiniLM-L6-v2 sentence embedder executed through Core ML. The reason it exists is: It offers a compact, local meaning-based space with manageable storage and fast exact similarity on Apple hardware.

### Layman’s explanation

The shipped 384-dimensional MiniLM-L6-v2 sentence embedder executed through Core ML. It offers a compact, local semantic space with manageable storage and fast exact similarity on Apple hardware.

### Technical explanation

It is the normal provider after tokenization and before vector persistence. Primary code anchors: OpenIntelligence/Services/Embedding/Providers/CoreMLSentenceEmbeddingProvider.swift; THIRD_PARTY_NOTICES.md.

### Why it is in this position

It is the normal provider after tokenization and before vector persistence.

## OI-0130. Document-chunk embedding

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **Document-chunk embedding** means: The number coordinates generated from a small source piece's contextualized text during ingestion. The reason it exists is: It is the reusable meaning-based representation searched by every later question.

### Layman’s explanation

The vector generated from a chunk's contextualized text during ingestion. It is the reusable semantic representation searched by every later question.

### Technical explanation

It is written after chunk validation and before the document becomes queryable. Primary code anchors: OpenIntelligence/Services/Embedding/EmbeddingService.swift; OpenIntelligence/Core/Models/DocumentChunk.swift.

### Why it is in this position

It is written after chunk validation and before the document becomes queryable.

## OI-0131. Dot product

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **Dot product** means: The sum of coordinate-wise products between two number coordinates. The reason it exists is: With put into a consistent form meaning map it is the computational core of cosine similarity and maps efficiently to Accelerate, BNNS, and Metal.

### Layman’s explanation

The sum of coordinate-wise products between two vectors. With normalized embeddings it is the computational core of cosine similarity and maps efficiently to Accelerate, BNNS, and Metal.

### Technical explanation

It runs for each query-vector and stored-vector comparison. Primary code anchors: OpenIntelligence/Services/Infrastructure/Compute/BNNSGraphService.swift; OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift.

### Why it is in this position

It runs for each query-vector and stored-vector comparison.

## OI-0132. Embedding

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **Embedding** means: A fixed-length numeric representation of a passage or question whose geometry approximates meaning-based similarity. The reason it exists is: It lets the engine retrieve conceptually related text even when the user and document use different words.

### Layman’s explanation

A fixed-length numeric representation of a passage or question whose geometry approximates semantic similarity. It lets the engine retrieve conceptually related text even when the user and document use different words.

### Technical explanation

Document chunks are embedded during ingestion; the question is embedded at query time; their vectors are compared before fusion and reranking. Primary code anchors: OpenIntelligence/Services/Embedding/EmbeddingService.swift; OpenIntelligence/UI/Components/Glossary.swift.

### Why it is in this position

Document chunks are embedded during ingestion; the question is embedded at query time; their vectors are compared before fusion and reranking.

## OI-0133. Embedding batch

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **Embedding batch** means: A group of passages processed together through one provider invocation. The reason it exists is: Batching amortizes model setup and uses matrix-oriented hardware more efficiently than one passage at a time.

### Layman’s explanation

A group of passages processed together through one provider invocation. Batching amortizes model setup and uses matrix-oriented hardware more efficiently than one passage at a time.

### Technical explanation

It occurs during ingestion and is sized by provider and device capability policy. Primary code anchors: OpenIntelligence/Services/Embedding/EmbeddingService.swift; OpenIntelligence/Services/Infrastructure/Monitoring/DeviceCapabilityService.swift.

### Why it is in this position

It occurs during ingestion and is sized by provider and device capability policy.

## OI-0134. Embedding concurrency

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **Embedding concurrency** means: The number of meaning map operations allowed to execute simultaneously. The reason it exists is: Too little concurrency underuses hardware, while too much competes for memory and can destabilize Core ML or Vision workloads.

### Layman’s explanation

The number of embedding operations allowed to execute simultaneously. Too little concurrency underuses hardware, while too much competes for memory and can destabilize Core ML or Vision workloads.

### Technical explanation

It is resolved from device and runtime policy before batch execution. Primary code anchors: OpenIntelligence/Services/Infrastructure/Monitoring/DeviceCapabilityService.swift.

### Why it is in this position

It is resolved from device and runtime policy before batch execution.

## OI-0135. Embedding dimension

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **Embedding dimension** means: The number of coordinates in one number coordinates, such as 384 or 512. The reason it exists is: Similarity requires both number coordinates to occupy the same dimensional space. A mismatch is a hard incompatibility rather than a small quality difference.

### Layman’s explanation

The number of coordinates in one vector, such as 384 or 512. Similarity requires both vectors to occupy the same dimensional space. A mismatch is a hard incompatibility rather than a small quality difference.

### Technical explanation

It is declared by the provider, recorded in metadata, validated on write and read, and checked before search. Primary code anchors: OpenIntelligence/Services/Embedding/Providers/EmbeddingProvider.swift; OpenIntelligence/Services/Embedding/EmbeddingFingerprint.swift.

### Why it is in this position

It is declared by the provider, recorded in metadata, validated on write and read, and checked before search.

## OI-0136. Embedding fingerprint

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **Embedding fingerprint** means: A saved identity for the provider, model, dimension, tokenizer, pooling behavior, and related number coordinates-space-defining settings. The reason it exists is: It prevents the engine from mixing number coordinates that look structurally valid but are semantically incompatible.

### Layman’s explanation

A persisted identity for the provider, model, dimension, tokenizer, pooling behavior, and related vector-space-defining settings. It prevents the engine from mixing vectors that look structurally valid but are semantically incompatible.

### Technical explanation

It is written with library/vector metadata and compared before ingestion, loading, querying, or migration. Primary code anchors: OpenIntelligence/Services/Embedding/EmbeddingFingerprint.swift.

### Why it is in this position

It is written with library/vector metadata and compared before ingestion, loading, querying, or migration.

## OI-0137. Embedding space

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **Embedding space** means: The coordinate system learned by one model and preprocessing recipe. The reason it exists is: Equal number coordinates lengths do not guarantee comparability. Different models, tokenizers, or pooling rules can produce unrelated geometries even at the same dimension.

### Layman’s explanation

The coordinate system learned by one model and preprocessing recipe. Equal vector lengths do not guarantee comparability. Different models, tokenizers, or pooling rules can produce unrelated geometries even at the same dimension.

### Technical explanation

A library remains in one space until a full re-embedding rebuild migrates it. Primary code anchors: OpenIntelligence/Services/Embedding/EmbeddingFingerprint.swift.

### Why it is in this position

A library remains in one space until a full re-embedding rebuild migrates it.

## OI-0138. Embedding translation target

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **Embedding translation target** means: An optional language into which meaning map text is translated before vectorization while preserving original source text for display and citation. The reason it exists is: Cross-language search can improve when all number coordinates share one meaning map language, but the quoted evidence must remain faithful to the original.

### Layman’s explanation

An optional language into which embedding text is translated before vectorization while preserving original source text for display and citation. Cross-language retrieval can improve when all vectors share one embedding language, but the quoted evidence must remain faithful to the original.

### Technical explanation

It occurs after extraction/chunking and before embedding only when configured. Primary code anchors: OpenIntelligence/Services/Document/Extraction/TranslationService.swift; OpenIntelligence/Services/Document/Analysis/DocumentSummaryService.swift.

### Why it is in this position

It occurs after extraction/chunking and before embedding only when configured.

## OI-0139. Embedding validation

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **Embedding validation** means: Checks for expected dimension, finite values, nonempty output, and other integrity conditions. The reason it exists is: NaN values, wrong widths, or silent truncation can poison every similarity result while still serializing successfully.

### Layman’s explanation

Checks for expected dimension, finite values, nonempty output, and other integrity conditions. NaN values, wrong widths, or silent truncation can poison every similarity result while still serializing successfully.

### Technical explanation

It runs immediately after provider output and again at vector-store boundaries. Primary code anchors: OpenIntelligence/Services/Embedding/EmbeddingService.swift; OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift.

### Why it is in this position

It runs immediately after provider output and again at vector-store boundaries.

## OI-0140. EmbeddingProvider

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **EmbeddingProvider** means: The protocol that standardizes model identity, number coordinates dimension, sequence limit, availability, batching, and meaning map generation across implementations. The reason it exists is: A library must know exactly which coordinate system produced its number coordinates while allowing the engine to select an available implementation.

### Layman’s explanation

The protocol that standardizes model identity, vector dimension, sequence limit, availability, batching, and embedding generation across implementations. A library must know exactly which coordinate system produced its vectors while allowing the engine to select an available implementation.

### Technical explanation

A provider is resolved before ingestion or query embedding and is recorded in the library fingerprint. Primary code anchors: OpenIntelligence/Services/Embedding/Providers/EmbeddingProvider.swift.

### Why it is in this position

A provider is resolved before ingestion or query embedding and is recorded in the library fingerprint.

## OI-0141. EmbeddingService

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **EmbeddingService** means: The actor that owns provider selection, model loading, validation, batching, caching, and error handling for meaning map. The reason it exists is: One authority prevents documents and queries from accidentally using different providers or number coordinates dimensions.

### Layman’s explanation

The actor that owns provider selection, model loading, validation, batching, caching, and error handling for embeddings. One authority prevents documents and queries from accidentally using different providers or vector dimensions.

### Technical explanation

It sits between chunk/query text and the vector store on both ingestion and retrieval paths. Primary code anchors: OpenIntelligence/Services/Embedding/EmbeddingService.swift.

### Why it is in this position

It sits between chunk/query text and the vector store on both ingestion and retrieval paths.

## OI-0142. L2 norm

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **L2 norm** means: The Euclidean length of a number coordinates, calculated as the square root of the sum of squared coordinates. The reason it exists is: number coordinates length must be known to normalize meaning map and compute cosine similarity efficiently.

### Layman’s explanation

The Euclidean length of a vector, calculated as the square root of the sum of squared coordinates. Vector length must be known to normalize embeddings and compute cosine similarity efficiently.

### Technical explanation

It is calculated after pooling and persisted separately for stored vectors. Primary code anchors: OpenIntelligence/Services/Infrastructure/Compute/BNNSGraphService.swift; OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift.

### Why it is in this position

It is calculated after pooling and persisted separately for stored vectors.

## OI-0143. L2 normalization

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **L2 normalization** means: Dividing every coordinate by the number coordinates's L2 norm so its length becomes one. The reason it exists is: For unit number coordinates, cosine similarity reduces to a dot product, which is faster and more numerically consistent across providers.

### Layman’s explanation

Dividing every coordinate by the vector's L2 norm so its length becomes one. For unit vectors, cosine similarity reduces to a dot product, which is faster and more numerically consistent across providers.

### Technical explanation

It is the final embedding transformation before validation and persistence. Primary code anchors: OpenIntelligence/Services/Embedding/Providers/CoreMLSentenceEmbeddingProvider.swift; OpenIntelligence/Services/Infrastructure/Compute/BNNSGraphService.swift.

### Why it is in this position

It is the final embedding transformation before validation and persistence.

## OI-0144. NLContextualEmbedding provider

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **NLContextualEmbedding provider** means: A 512-dimensional Natural Language framework provider retained as a compatibility option. The reason it exists is: It allows a system meaning map path on supported OS versions but represents a different number coordinates space from MiniLM.

### Layman’s explanation

A 512-dimensional Natural Language framework provider retained as a compatibility option. It allows a system embedding path on supported OS versions but represents a different vector space from MiniLM.

### Technical explanation

It may be selected per library and therefore requires a matching fingerprint and rebuild when changed. Primary code anchors: OpenIntelligence/Services/Embedding/Providers/NLContextualEmbeddingProvider.swift.

**Important caveat:** It is not the default and should not be described as interchangeable with 384-dimensional vectors.

### Why it is in this position

It may be selected per library and therefore requires a matching fingerprint and rebuild when changed.

## OI-0145. NLEmbedding provider

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **NLEmbedding provider** means: A 512-dimensional compatibility provider that averages available word meaning map from Apple's Natural Language framework. The reason it exists is: It supplies a fallback meaning-based representation where the preferred sentence model is unavailable.

### Layman’s explanation

A 512-dimensional compatibility provider that averages available word embeddings from Apple's Natural Language framework. It supplies a fallback semantic representation where the preferred sentence model is unavailable.

### Technical explanation

It is resolved before vector generation and remains isolated to libraries configured for that provider. Primary code anchors: OpenIntelligence/Services/Embedding/Providers/NLEmbeddingProvider.swift.

### Why it is in this position

It is resolved before vector generation and remains isolated to libraries configured for that provider.

## OI-0146. Provider agreement test

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **Provider agreement test** means: A test that compares output shape and meaning-based behavior across compatible meaning map backends. The reason it exists is: A new runtime backend should preserve the number coordinates space expected by existing libraries rather than merely compile.

### Layman’s explanation

A test that compares output shape and semantic behavior across compatible embedding backends. A new runtime backend should preserve the vector space expected by existing libraries rather than merely compile.

### Technical explanation

It is part of validation and migration testing, not a user query stage. Primary code anchors: OpenIntelligenceTests/Services/Embedding/EmbeddingProviderAgreementTests.swift.

### Why it is in this position

It is part of validation and migration testing, not a user query stage.

## OI-0147. Query embedding

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **Query embedding** means: The number coordinates generated from the user's effective search question. The reason it exists is: It places the question in the same meaning-based space as document small source pieces so nearest passages can be found.

### Layman’s explanation

The vector generated from the user's effective search query. It places the question in the same semantic space as document chunks so nearest passages can be found.

### Technical explanation

It is generated after query rewriting/expansion decisions and before dense search. Primary code anchors: OpenIntelligence/Services/Embedding/EmbeddingService.swift; OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift.

### Why it is in this position

It is generated after query rewriting/expansion decisions and before dense search.

## OI-0148. Re-embedding

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **Re-embedding** means: Regenerating every small source piece number coordinates in a library under a new meaning map fingerprint. The reason it exists is: Changing the model, dimension, tokenizer, or pooling invalidates all old similarities, so partial migration would mix coordinate systems.

### Layman’s explanation

Regenerating every chunk vector in a library under a new embedding fingerprint. Changing the model, dimension, tokenizer, or pooling invalidates all old similarities, so partial migration would mix coordinate systems.

### Technical explanation

It is an explicit rebuild path that occurs after text/chunk data is loaded and before the new vector store is published. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/RAGService.swift; OpenIntelligence/Services/Embedding/EmbeddingFingerprint.swift.

### Why it is in this position

It is an explicit rebuild path that occurs after text/chunk data is loaded and before the new vector store is published.

## OI-0149. Semantic query cache

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **Semantic query cache** means: A local table storing meaning map or meaning-based results for previously seen put into a consistent form questions. The reason it exists is: Repeated questions can skip model meaning map work and reduce latency and energy.

### Layman’s explanation

A local table storing embeddings or semantic results for previously seen normalized questions. Repeated questions can skip model embedding work and reduce latency and energy.

### Technical explanation

It is checked before generating a query embedding and updated after a successful result. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift.

### Why it is in this position

It is checked before generating a query embedding and updated after a successful result.

## OI-0150. Sentence embedding

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **Sentence embedding** means: An meaning map model optimized to place sentence- or passage-level meanings into one shared number coordinates space. The reason it exists is: A token-level model output is not directly searchable as one passage. Sentence meaning map reduces a sequence into one comparable number coordinates.

### Layman’s explanation

An embedding model optimized to place sentence- or passage-level meanings into one shared vector space. A token-level model output is not directly searchable as one passage. Sentence embedding reduces a sequence into one comparable vector.

### Technical explanation

It consumes tokenized chunk text after contextual prefixing and produces the vector stored with that chunk. Primary code anchors: OpenIntelligence/Services/Embedding/Providers/CoreMLSentenceEmbeddingProvider.swift.

### Why it is in this position

It consumes tokenized chunk text after contextual prefixing and produces the vector stored with that chunk.

## OI-0151. Special tokens

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **Special tokens** means: Model-specific boundary tokens such as classification and separator markers inserted around content. The reason it exists is: The pretrained model expects the same input framing it saw during training, and those tokens consume part of the sequence limit.

### Layman’s explanation

Model-specific boundary tokens such as classification and separator markers inserted around content. The pretrained model expects the same input framing it saw during training, and those tokens consume part of the sequence limit.

### Technical explanation

They are inserted by the tokenizer before the 510-token safe ceiling is evaluated. Primary code anchors: OpenIntelligence/Services/Embedding/Providers/CoreMLSentenceEmbeddingProvider.swift.

### Why it is in this position

They are inserted by the tokenizer before the 510-token safe ceiling is evaluated.

## OI-0152. Token IDs

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **Token IDs** means: Integer vocabulary identifiers produced by the paired tokenizer for each model input token. The reason it exists is: The model consumes numbers rather than strings, and their meaning depends entirely on the tokenizer-model pairing.

### Layman’s explanation

Integer vocabulary identifiers produced by the paired tokenizer for each model input token. The model consumes numbers rather than strings, and their meaning depends entirely on the tokenizer-model pairing.

### Technical explanation

They are produced after sequence validation and passed into embedding or reranking inference. Primary code anchors: OpenIntelligence/Services/Embedding/Providers/CoreMLSentenceEmbeddingProvider.swift.

### Why it is in this position

They are produced after sequence validation and passed into embedding or reranking inference.

## OI-0153. Token-state tensor

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **Token-state tensor** means: The model output containing one contextual number coordinates for every input token position. The reason it exists is: A sentence model must derive one passage representation from these many token-level states.

### Layman’s explanation

The model output containing one contextual vector for every input token position. A sentence model must derive one passage representation from these many token-level states.

### Technical explanation

It is emitted by model inference and immediately reduced by masked mean pooling. Primary code anchors: OpenIntelligence/Services/Embedding/Providers/CoreMLSentenceEmbeddingProvider.swift.

### Why it is in this position

It is emitted by model inference and immediately reduced by masked mean pooling.

## OI-0154. Zero-vector fallback

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a placing meaning pins on a map. **Zero-vector fallback** means: A correctly sized all-zero meaning map returned or substituted when a noncritical provider failure must not corrupt array shape. The reason it exists is: It prevents crashes and dimension mismatch, while downstream validation can identify that the meaning-based representation carries no information.

### Layman’s explanation

A correctly sized all-zero embedding returned or substituted when a noncritical provider failure must not corrupt array shape. It prevents crashes and dimension mismatch, while downstream validation can identify that the semantic representation carries no information.

### Technical explanation

It is an error-containment behavior inside EmbeddingService before persistence. Primary code anchors: OpenIntelligence/Services/Embedding/EmbeddingService.swift.

**Important caveat:** A zero vector is not a successful semantic embedding and should be surfaced in diagnostics or rebuild checks.

### Why it is in this position

It is an error-containment behavior inside EmbeddingService before persistence.

---

# 06. Lexical indexing, SQLite, and vector persistence

**Section orientation:** SQLite and FTS5 support exact and lexical search, while the vector store supports semantic search. Binary vector files and norms provide efficient local persistence.

## OI-0155. 1,000-chunk GPU threshold

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **1,000-chunk GPU threshold** means: The documented switching point near which large exact number coordinates search becomes eligible for Metal. The reason it exists is: It avoids paying GPU overhead on small libraries while exposing parallelism on larger ones.

### Layman’s explanation

The documented switching point near which large exact vector search becomes eligible for Metal. It avoids paying GPU overhead on small libraries while exposing parallelism on larger ones.

### Technical explanation

It is evaluated immediately before similarity computation. Primary code anchors: OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift; Docs/HOW_IT_WORKS.md.

**Important caveat:** The actual route also depends on device and user GPU policy, so the threshold alone does not guarantee GPU execution.

### Why it is in this position

It is evaluated immediately before similarity computation.

## OI-0156. _norms.bin

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **_norms.bin** means: The binary file of precomputed L2 norms corresponding to stored number coordinates. The reason it exists is: Precomputing avoids recalculating number coordinates lengths for every question and supports efficient cosine similarity.

### Layman’s explanation

The binary file of precomputed L2 norms corresponding to stored vectors. Precomputing avoids recalculating vector lengths for every question and supports efficient cosine similarity.

### Technical explanation

It is generated with vector persistence and loaded beside the vector mapping. Primary code anchors: OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift.

### Why it is in this position

It is generated with vector persistence and loaded beside the vector mapping.

## OI-0157. _vectors.bin

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **_vectors.bin** means: The contiguous binary file of Float32 meaning map coordinates for one library. The reason it exists is: A flat layout supports memory mapping and high-throughput matrix or dot-product operations without object overhead.

### Layman’s explanation

The contiguous binary file of Float32 embedding coordinates for one library. A flat layout supports memory mapping and high-throughput matrix or dot-product operations without object overhead.

### Technical explanation

It is written during ingestion/rebuild and mapped into address space for every dense search. Primary code anchors: OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift.

### Why it is in this position

It is written during ingestion/rebuild and mapped into address space for every dense search.

## OI-0158. Atomic vector-store persistence

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **Atomic vector-store persistence** means: Writing replacement labels and facts, number coordinates, and norm artifacts through temporary files and coordinated replacement rather than mutating live files in place. The reason it exists is: A crash between independent writes could pair new labels and facts with old number coordinates and make source identity incorrect.

### Layman’s explanation

Writing replacement metadata, vector, and norm artifacts through temporary files and coordinated replacement rather than mutating live files in place. A crash between independent writes could pair new metadata with old vectors and make source identity incorrect.

### Technical explanation

It is the final vector publication step after all replacement data is complete. Primary code anchors: OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift.

### Why it is in this position

It is the final vector publication step after all replacement data is complete.

## OI-0159. BM25

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **BM25** means: A probabilistic exact-word ranking function that rewards informative question-term matches while accounting for term frequency, document collection rarity, and field or document length. The reason it exists is: Exact words, codes, names, and measurements often carry decisive meaning that dense number coordinates blur. BM25 is the exact-language half of hybrid search.

### Layman’s explanation

A probabilistic lexical ranking function that rewards informative query-term matches while accounting for term frequency, corpus rarity, and field or document length. Exact words, codes, names, and measurements often carry decisive meaning that dense vectors blur. BM25 is the exact-language half of hybrid retrieval.

### Technical explanation

FTS5 computes it for lexical candidates before reciprocal rank fusion. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift; OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift.

### Why it is in this position

FTS5 computes it for lexical candidates before reciprocal rank fusion.

## OI-0160. BM25 b

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **BM25 b** means: The parameter controlling document-length put into a consistent form; the fallback implementation uses approximately 0.5. The reason it exists is: It determines how strongly long small source pieces are penalized relative to average length.

### Layman’s explanation

The parameter controlling document-length normalization; the fallback implementation uses approximately 0.5. It determines how strongly long chunks are penalized relative to average length.

### Technical explanation

It is applied with k1 during lexical scoring. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift.

### Why it is in this position

It is applied with k1 during lexical scoring.

## OI-0161. BM25 k1

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **BM25 k1** means: The parameter controlling how quickly additional term occurrences saturate; the fallback implementation uses approximately 1.5. The reason it exists is: It sets the balance between a single precise match and many repeated matches.

### Layman’s explanation

The parameter controlling how quickly additional term occurrences saturate; the fallback implementation uses approximately 1.5. It sets the balance between a single precise match and many repeated matches.

### Technical explanation

It is applied inside the lexical scoring equation before rank ordering. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift.

### Why it is in this position

It is applied inside the lexical scoring equation before rank ordering.

## OI-0162. BNNSVectorDatabase

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **BNNSVectorDatabase** means: The default exact number coordinates store using compact labels and facts, contiguous Float32 number coordinates, precomputed norms, memory mapping, Accelerate/BNNS, and optional Metal acceleration. The reason it exists is: It provides a serverless search store optimized for Apple unified memory and the document collection sizes expected on device.

### Layman’s explanation

The default exact vector store using compact metadata, contiguous Float32 vectors, precomputed norms, memory mapping, Accelerate/BNNS, and optional Metal acceleration. It provides a serverless search store optimized for Apple unified memory and the corpus sizes expected on device.

### Technical explanation

It receives vectors after embedding and serves dense candidates before hybrid fusion. Primary code anchors: OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift.

### Why it is in this position

It receives vectors after embedding and serves dense candidates before hybrid fusion.

## OI-0163. Busy timeout

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **Busy timeout** means: The wait period, approximately three seconds, allowed when SQLite is temporarily locked. The reason it exists is: Immediate failure on short-lived contention would turn normal concurrent ingestion and reads into user-visible errors.

### Layman’s explanation

The wait period, approximately three seconds, allowed when SQLite is temporarily locked. Immediate failure on short-lived contention would turn normal concurrent ingestion and reads into user-visible errors.

### Technical explanation

It is configured at connection setup and applies before a locked operation fails. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift.

### Why it is in this position

It is configured at connection setup and applies before a locked operation fails.

## OI-0164. chunk_structured table

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **chunk_structured table** means: A table-and-relationship store for structured elements associated with a small source piece. The reason it exists is: Tables, lists, warnings, and detected data need machine-readable recovery beyond the flattened search string.

### Layman’s explanation

A relational store for structured elements associated with a chunk. Tables, lists, warnings, and detected data need machine-readable recovery beyond the flattened search string.

### Technical explanation

It is written alongside chunk records and consulted by extractive and response paths. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift.

### Why it is in this position

It is written alongside chunk records and consulted by extractive and response paths.

## OI-0165. chunk_table_rows table

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **chunk_table_rows table** means: A table storing individual recovered table rows as rows rather than only as one flattened small source piece. The reason it exists is: Exact lookup often depends on preserving the relationship among cells in one row.

### Layman’s explanation

A table storing individual recovered table rows as rows rather than only as one flattened chunk. Exact lookup often depends on preserving the relationship among cells in one row.

### Technical explanation

It is populated from structured parsing and queried before regex fallback for table-style questions. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift; OpenIntelligence/Services/Query/Analysis/SpecificationExtractor.swift.

### Why it is in this position

It is populated from structured parsing and queried before regex fallback for table-style questions.

## OI-0166. chunks table

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **chunks table** means: The FTS5 surface containing small source piece identity, source relations, structural fields, and content used for exact-word search. The reason it exists is: small source pieces are the operational search unit, so exact-word ranking must return the same identities used by number coordinates search.

### Layman’s explanation

The FTS5 surface containing chunk identity, source relations, structural fields, and content used for lexical retrieval. Chunks are the operational retrieval unit, so lexical ranking must return the same identities used by vector search.

### Technical explanation

It is populated after chunking and queried in parallel with the vector store. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift.

### Why it is in this position

It is populated after chunking and queried in parallel with the vector store.

## OI-0167. Container column scoping

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **Container column scoping** means: Using a container UUID column in shared tables rather than one SQLite file per library. The reason it exists is: A shared schema simplifies migrations and global maintenance while queries still enforce library isolation.

### Layman’s explanation

Using a container UUID column in shared tables rather than one SQLite file per library. A shared schema simplifies migrations and global maintenance while queries still enforce library isolation.

### Technical explanation

Every document/chunk query includes the active container filter before results are returned. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift.

### Why it is in this position

Every document/chunk query includes the active container filter before results are returned.

## OI-0168. Content weight

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **Content weight** means: The baseline BM25 weight, approximately 1, for ordinary small source piece body text. The reason it exists is: Body text remains searchable but does not overpower more intentional structural fields.

### Layman’s explanation

The baseline BM25 weight, approximately 1, for ordinary chunk body text. Body text remains searchable but does not overpower more intentional structural fields.

### Technical explanation

It is the final searchable field weight in the chunks FTS query. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift.

### Why it is in this position

It is the final searchable field weight in the chunks FTS query.

## OI-0169. CPU vector path

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **CPU vector path** means: Accelerate or BNNS dot-product search used below the configured large-document collection threshold. The reason it exists is: GPU setup has fixed overhead, so CPU SIMD can be faster for smaller libraries.

### Layman’s explanation

Accelerate or BNNS dot-product search used below the configured large-corpus threshold. GPU setup has fixed overhead, so CPU SIMD can be faster for smaller libraries.

### Technical explanation

It is selected at dense-search runtime, currently below roughly 1,000 chunks under the relevant policy. Primary code anchors: OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift; OpenIntelligence/Services/Infrastructure/Compute/BNNSGraphService.swift.

### Why it is in this position

It is selected at dense-search runtime, currently below roughly 1,000 chunks under the relevant policy.

## OI-0170. Document-length normalization

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **Document-length normalization** means: The BM25 adjustment that prevents long passages from winning merely because they contain more words and therefore more opportunities to match. The reason it exists is: A concise specification row can be more relevant than a long chapter that mentions the term incidentally.

### Layman’s explanation

The BM25 adjustment that prevents long passages from winning merely because they contain more words and therefore more opportunities to match. A concise specification row can be more relevant than a long chapter that mentions the term incidentally.

### Technical explanation

It is applied while the lexical score is computed. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift.

### Why it is in this position

It is applied while the lexical score is computed.

## OI-0171. document_content table

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **document_content table** means: A table-and-relationship store for raw or put into a consistent form full document text used for direct extraction and citation reconstruction. The reason it exists is: The small source piece index alone may not preserve enough contiguous text for exact source views or rebuilds.

### Layman’s explanation

A relational store for raw or normalized full document text used for direct extraction and citation reconstruction. The chunk index alone may not preserve enough contiguous text for exact source views or rebuilds.

### Technical explanation

It is persisted after extraction and read by direct-answer, citation, and maintenance paths. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift.

### Why it is in this position

It is persisted after extraction and read by direct-answer, citation, and maintenance paths.

## OI-0172. document_meta table

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **document_meta table** means: A table-and-relationship table for counts, dates, size, container identity, and other document labels and facts. The reason it exists is: labels and facts needs exact typed access and updates rather than full-text tokenization.

### Layman’s explanation

A relational table for counts, dates, size, container identity, and other document metadata. Metadata needs exact typed access and updates rather than full-text tokenization.

### Technical explanation

It is written with the document commit and joined during library and source operations. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift.

### Why it is in this position

It is written with the document commit and joined during library and source operations.

## OI-0173. document_pages table

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **document_pages table** means: An FTS5 surface for page-level text and boundaries. The reason it exists is: Page search, citation navigation, and cross-reference repair need evidence at page granularity.

### Layman’s explanation

An FTS5 surface for page-level text and boundaries. Page search, citation navigation, and cross-reference repair need evidence at page granularity.

### Technical explanation

It is populated during page extraction and may be searched during corrective or reference-based retrieval. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift.

### Why it is in this position

It is populated during page extraction and may be searched during corrective or reference-based retrieval.

## OI-0174. documents table

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **documents table** means: An FTS5 surface for whole-document text. The reason it exists is: Some searches and diagnostics need document-level matching in addition to small source piece-level precision.

### Layman’s explanation

An FTS5 surface for whole-document text. Some searches and diagnostics need document-level matching in addition to chunk-level precision.

### Technical explanation

It is populated during ingestion and queried by document search or recovery paths. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift.

### Why it is in this position

It is populated during ingestion and queried by document search or recovery paths.

## OI-0175. documents_vocab

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **documents_vocab** means: An FTS5 vocabulary view exposing terms learned from the active library. The reason it exists is: question expansion can use the document collection's own language instead of a generic synonym list that may introduce unrelated concepts.

### Layman’s explanation

An FTS5 vocabulary view exposing terms learned from the active library. Query expansion can use the corpus's own language instead of a generic synonym list that may introduce unrelated concepts.

### Technical explanation

It is read during query enhancement before lexical retrieval. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift; OpenIntelligence/Services/RAG/Retrieval/ContainerVocabularyService.swift.

### Why it is in this position

It is read during query enhancement before lexical retrieval.

## OI-0176. Exact vector scan

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **Exact vector scan** means: Comparing the question against every stored number coordinates rather than traversing an approximate neighbor graph. The reason it exists is: At local document collection scale, exact search avoids approximate-recall loss and complex index maintenance while remaining fast with mmap and Apple SIMD/GPU hardware.

### Layman’s explanation

Comparing the query against every stored vector rather than traversing an approximate neighbor graph. At local corpus scale, exact search avoids approximate-recall loss and complex index maintenance while remaining fast with mmap and Apple SIMD/GPU hardware.

### Technical explanation

It is the default dense retrieval operation before top-k selection. Primary code anchors: OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift.

### Why it is in this position

It is the default dense retrieval operation before top-k selection.

## OI-0177. FTS column weight

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **FTS column weight** means: A per-column multiplier supplied to BM25 so matches in high-signal labels and facts count more than body-text matches. The reason it exists is: A question matching a section heading or section path is usually more intentional than one buried in prose.

### Layman’s explanation

A per-column multiplier supplied to BM25 so matches in high-signal metadata count more than body-text matches. A query matching a section heading or section path is usually more intentional than one buried in prose.

### Technical explanation

Weights are applied during FTS ranking before results leave SQLite. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift.

### Why it is in this position

Weights are applied during FTS ranking before results leave SQLite.

## OI-0178. FTS5

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **FTS5** means: SQLite's full-text-search virtual table engine. The reason it exists is: Normal SQL substring matching is too slow and does not provide relevance ranking, tokenization, or document collection statistics needed for exact-word search.

### Layman’s explanation

SQLite's full-text-search virtual table engine. Normal SQL substring matching is too slow and does not provide relevance ranking, tokenization, or corpus statistics needed for lexical retrieval.

### Technical explanation

Text is indexed into FTS5 during ingestion and queried in parallel with vector search. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift; OpenIntelligence/UI/Components/Glossary.swift.

### Why it is in this position

Text is indexed into FTS5 during ingestion and queried in parallel with vector search.

## OI-0179. GPU vector path

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **GPU vector path** means: Metal compute search over the memory-mapped number coordinates buffer for sufficiently large possible result sets and an enabled execution profile. The reason it exists is: Large batches expose enough parallel arithmetic to offset command-buffer setup and accelerate similarity computation.

### Layman’s explanation

Metal compute search over the memory-mapped vector buffer for sufficiently large candidate sets and an enabled execution profile. Large batches expose enough parallel arithmetic to offset command-buffer setup and accelerate similarity computation.

### Technical explanation

It replaces the CPU scan after the runtime threshold and device-policy gates pass. Primary code anchors: OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift; OpenIntelligence/Services/Infrastructure/Compute/GPUComputeService.swift.

### Why it is in this position

It replaces the CPU scan after the runtime threshold and device-policy gates pass.

## OI-0180. HNSW

**Status:** Historical, meaning it is superseded, removed, or misleading if described as current.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **HNSW** means: Hierarchical Navigable Small World approximate-nearest-neighbor indexing associated with the optional Vectura path. The reason it exists is: Approximate graphs can reduce search work at very large scale, but they add index complexity and may sacrifice recall.

### Layman’s explanation

Hierarchical Navigable Small World approximate-nearest-neighbor indexing associated with the optional Vectura path. Approximate graphs can reduce search work at very large scale, but they add index complexity and may sacrifice recall.

### Technical explanation

It is not part of the default BNNS exact-search pipeline. Primary code anchors: OpenIntelligence/Services/VectorStore/VecturaVectorDatabase.swift.

**Important caveat:** Do not describe OpenIntelligence generally as HNSW-based; the default shipping store is an exact memory-mapped scan.

### Why it is in this position

It is not part of the default BNNS exact-search pipeline.

## OI-0181. Inverse document frequency

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **Inverse document frequency** means: A weight that increases when a term is rare across the document collection and decreases when it is common. The reason it exists is: Rare identifiers and technical terms discriminate relevant passages better than words occurring everywhere.

### Layman’s explanation

A weight that increases when a term is rare across the corpus and decreases when it is common. Rare identifiers and technical terms discriminate relevant passages better than words occurring everywhere.

### Technical explanation

It is one BM25 input derived from corpus-level FTS statistics. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift.

### Why it is in this position

It is one BM25 input derived from corpus-level FTS statistics.

## OI-0182. Inverted index

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **Inverted index** means: A mapping from each indexed term to the rows and positions where it appears. The reason it exists is: It lets the database jump directly to matching small source pieces rather than scan every passage.

### Layman’s explanation

A mapping from each indexed term to the rows and positions where it appears. It lets the database jump directly to matching chunks rather than scan every passage.

### Technical explanation

FTS5 builds it at ingestion and consults it during lexical search. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift.

### Why it is in this position

FTS5 builds it at ingestion and consults it during lexical search.

## OI-0183. Memory mapping

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **Memory mapping** means: Mapping a file into virtual address space so number coordinates bytes can be accessed through pointers without reading the whole file into a heap array. The reason it exists is: Large libraries remain searchable with low resident memory and without a copy on every question.

### Layman’s explanation

Mapping a file into virtual address space so vector bytes can be accessed through pointers without reading the whole file into a heap array. Large libraries remain searchable with low resident memory and without a copy on every query.

### Technical explanation

It occurs when the vector store loads and supplies pointers to CPU or GPU search. Primary code anchors: OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift.

### Why it is in this position

It occurs when the vector store loads and supplies pointers to CPU or GPU search.

## OI-0184. Metal buffer pool

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **Metal buffer pool** means: A cache of reusable size-bucketed MTLBuffers with device-tier memory limits. The reason it exists is: Repeated allocation can dominate short GPU operations and increase memory fragmentation.

### Layman’s explanation

A cache of reusable size-bucketed MTLBuffers with device-tier memory limits. Repeated allocation can dominate short GPU operations and increase memory fragmentation.

### Technical explanation

Buffers are acquired before Metal kernels, released afterward, and cleared under memory pressure. Primary code anchors: OpenIntelligence/Services/Infrastructure/Compute/GPUComputeService.swift.

### Why it is in this position

Buffers are acquired before Metal kernels, released afterward, and cleared under memory pressure.

## OI-0185. Metal residency set

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **Metal residency set** means: A Metal 4 facility that can keep frequently reused buffers resident for lower page-fault overhead. The reason it exists is: Persistent number coordinates workloads benefit when buffers do not repeatedly migrate or fault into GPU-visible memory.

### Layman’s explanation

A Metal 4 facility that can keep frequently reused buffers resident for lower page-fault overhead. Persistent vector workloads benefit when buffers do not repeatedly migrate or fault into GPU-visible memory.

### Technical explanation

It is initialized on supported OS versions and applied to reusable allocations. Primary code anchors: OpenIntelligence/Services/Infrastructure/Compute/GPUComputeService.swift.

### Why it is in this position

It is initialized on supported OS versions and applied to reusable allocations.

## OI-0186. Nine-column chunks FTS schema

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **Nine-column chunks FTS schema** means: The small source piece search table whose nine columns align exactly with the BM25 weight number coordinates. The reason it exists is: Column order is part of the scoring contract. A missing weight shifts every later weight and silently changes ranking.

### Layman’s explanation

The chunk search table whose nine columns align exactly with the BM25 weight vector. Column order is part of the scoring contract. A missing weight shifts every later weight and silently changes ranking.

### Technical explanation

It is defined at schema creation and used by every chunk-level lexical query. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift; OpenIntelligenceTests/Services/RAG/Retrieval/HybridSearchServiceTests.swift.

### Why it is in this position

It is defined at schema creation and used by every chunk-level lexical query.

## OI-0187. Partial top-k selection

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **Partial top-k selection** means: Maintaining only the highest-scoring possible result while scanning instead of sorting every document collection score. The reason it exists is: The engine needs perhaps tens of hits, not a complete ordering of thousands, so partial selection reduces memory and sorting work.

### Layman’s explanation

Maintaining only the highest-scoring candidates while scanning instead of sorting every corpus score. The engine needs perhaps tens of hits, not a complete ordering of thousands, so partial selection reduces memory and sorting work.

### Technical explanation

It runs during dense search before RetrievedChunk objects are constructed. Primary code anchors: OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift.

### Why it is in this position

It runs during dense search before RetrievedChunk objects are constructed.

## OI-0188. persistentJSON vector-store label

**Status:** Historical, meaning it is superseded, removed, or misleading if described as current.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **persistentJSON vector-store label** means: A legacy configuration name that now routes to the BNNS binary/memory-mapped implementation rather than a number coordinates-inside-JSON database. The reason it exists is: Keeping the stored enum value preserves compatibility with existing libraries and settings.

### Layman’s explanation

A legacy configuration name that now routes to the BNNS binary/memory-mapped implementation rather than a vectors-inside-JSON database. Keeping the stored enum value preserves compatibility with existing libraries and settings.

### Technical explanation

It is interpreted by VectorStoreRouter before concrete store creation. Primary code anchors: OpenIntelligence/Core/Models/KnowledgeContainer.swift; OpenIntelligence/Services/VectorStore/VectorStoreRouter.swift.

**Important caveat:** The label is historical and should not be taught as the physical storage format.

### Why it is in this position

It is interpreted by VectorStoreRouter before concrete store creation.

## OI-0189. Porter tokenizer

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **Porter tokenizer** means: The FTS tokenizer configuration that applies English stemming so related word forms share a root. The reason it exists is: A question using run can match a passage using running, improving exact-word recall beyond exact surface strings.

### Layman’s explanation

The FTS tokenizer configuration that applies English stemming so related word forms share a root. A question using run can match a passage using running, improving lexical recall beyond exact surface strings.

### Technical explanation

It transforms text as FTS rows are indexed and queries are parsed. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift.

### Why it is in this position

It transforms text as FTS rows are indexed and queries are parsed.

## OI-0190. Section-path boost

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **Section-path boost** means: The current intermediate BM25 column weight, approximately 5, for a match in the section hierarchy. The reason it exists is: A section path preserves topic context that may not be repeated in every small source piece body.

### Layman’s explanation

The current intermediate BM25 column weight, approximately 5, for a match in the section hierarchy. A section path preserves topic context that may not be repeated in every chunk body.

### Technical explanation

It modifies lexical scoring before fusion and expansion. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift.

### Why it is in this position

It modifies lexical scoring before fusion and expansion.

## OI-0191. Section-title boost

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **Section-title boost** means: The current high BM25 column weight, approximately 10, for a match in the small source piece section title. The reason it exists is: Headings are concise meaning-based labels and often answer navigation-style queries directly.

### Layman’s explanation

The current high BM25 column weight, approximately 10, for a match in the chunk section title. Headings are concise semantic labels and often answer navigation-style queries directly.

### Technical explanation

It modifies lexical scoring before hybrid fusion. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift.

### Why it is in this position

It modifies lexical scoring before hybrid fusion.

## OI-0192. SQLite

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **SQLite** means: The embedded table-and-relationship database that stores document text, labels and facts, small source pieces, pages, structured content, table rows, vocabulary, and question cache. The reason it exists is: It provides transactional local saved storage and queryable structure without a server.

### Layman’s explanation

The embedded relational database that stores document text, metadata, chunks, pages, structured content, table rows, vocabulary, and query cache. It provides transactional local persistence and queryable structure without a server.

### Technical explanation

It receives records after ingestion and serves lexical retrieval and source reconstruction during queries. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift.

### Why it is in this position

It receives records after ingestion and serves lexical retrieval and source reconstruction during queries.

## OI-0193. SQLite transaction

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **SQLite transaction** means: A group of database writes that either commit together or roll back together. The reason it exists is: Document labels and facts, small source pieces, pages, and structured rows must not become partially visible.

### Layman’s explanation

A group of database writes that either commit together or roll back together. Document metadata, chunks, pages, and structured rows must not become partially visible.

### Technical explanation

Transactions wrap multi-row ingestion, deletion, and migration operations. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift.

### Why it is in this position

Transactions wrap multi-row ingestion, deletion, and migration operations.

## OI-0194. SQLiteFullTextService

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **SQLiteFullTextService** means: The actor that owns the shared SQLite connection, schema, transactions, FTS queries, labels and facts access, and container filters. The reason it exists is: One serialized database owner prevents connection races and keeps schema and ranking policy centralized.

### Layman’s explanation

The actor that owns the shared SQLite connection, schema, transactions, FTS queries, metadata access, and container filters. One serialized database owner prevents connection races and keeps schema and ranking policy centralized.

### Technical explanation

It sits between RAGService and the lexical/document persistence layer. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift.

### Why it is in this position

It sits between RAGService and the lexical/document persistence layer.

## OI-0195. Stemming

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **Stemming** means: Reduction of inflected words to a common search stem. The reason it exists is: exact-word search otherwise treats many grammatical variants as unrelated terms.

### Layman’s explanation

Reduction of inflected words to a common search stem. Lexical retrieval otherwise treats many grammatical variants as unrelated terms.

### Technical explanation

It is performed by the FTS tokenizer before term lookup and BM25 scoring. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift.

### Why it is in this position

It is performed by the FTS tokenizer before term lookup and BM25 scoring.

## OI-0196. Term frequency

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **Term frequency** means: How often a question term appears in one searchable row or field. The reason it exists is: Repeated occurrence increases relevance, but with diminishing returns so keyword stuffing does not dominate indefinitely.

### Layman’s explanation

How often a query term appears in one searchable row or field. Repeated occurrence increases relevance, but with diminishing returns so keyword stuffing does not dominate indefinitely.

### Technical explanation

It is one BM25 input calculated inside lexical ranking. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift.

### Why it is in this position

It is one BM25 input calculated inside lexical ranking.

## OI-0197. UNINDEXED FTS column

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **UNINDEXED FTS column** means: A field stored in an FTS row for search or joining but excluded from term indexing. The reason it exists is: IDs and control labels and facts must travel with hits without polluting the searchable vocabulary.

### Layman’s explanation

A field stored in an FTS row for retrieval or joining but excluded from term indexing. IDs and control metadata must travel with hits without polluting the searchable vocabulary.

### Technical explanation

It is declared in the FTS schema and receives a zero BM25 weight. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift.

### Why it is in this position

It is declared in the FTS schema and receives a zero BM25 weight.

## OI-0198. Vector metadata JSON

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **Vector metadata JSON** means: The file mapping number coordinates positions to small source piece/document identities and labels and facts required to reconstruct results. The reason it exists is: The binary float array alone has no source identity, page, text, or deletion semantics.

### Layman’s explanation

The file mapping vector positions to chunk/document identities and metadata required to reconstruct results. The binary float array alone has no source identity, page, text, or deletion semantics.

### Technical explanation

It is written atomically with vector and norm artifacts and loaded before search results are materialized. Primary code anchors: OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift.

### Why it is in this position

It is written atomically with vector and norm artifacts and loaded before search results are materialized.

## OI-0199. VectorDatabase protocol

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **VectorDatabase protocol** means: The summary level for storing, loading, searching, deleting, and auditing small source piece number coordinates. The reason it exists is: search and SDK code can depend on one contract while the physical store or migration backend changes.

### Layman’s explanation

The abstraction for storing, loading, searching, deleting, and auditing chunk vectors. Retrieval and SDK code can depend on one contract while the physical store or migration backend changes.

### Technical explanation

It sits below VectorStoreRouter and above the concrete BNNS or optional Vectura store. Primary code anchors: OpenIntelligence/Services/VectorStore/VectorDatabase.swift.

### Why it is in this position

It sits below VectorStoreRouter and above the concrete BNNS or optional Vectura store.

## OI-0200. VectorStoreRouter

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **VectorStoreRouter** means: The service that resolves the concrete number coordinates store for a library from its configured number coordinates database kind. The reason it exists is: One library must consistently read and write one store implementation, and migrations need a controlled switch point.

### Layman’s explanation

The service that resolves the concrete vector store for a library from its configured vector database kind. One library must consistently read and write one store implementation, and migrations need a controlled switch point.

### Technical explanation

It is consulted before ingestion persistence and every dense retrieval. Primary code anchors: OpenIntelligence/Services/VectorStore/VectorStoreRouter.swift.

### Why it is in this position

It is consulted before ingestion persistence and every dense retrieval.

## OI-0201. VecturaVectorDatabase

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **VecturaVectorDatabase** means: An optional adapter for the Vectura/HNSW-style store retained for compatible libraries or migration paths. The reason it exists is: It preserves access to previously configured approximate stores without making them the default architecture.

### Layman’s explanation

An optional adapter for the Vectura/HNSW-style store retained for compatible libraries or migration paths. It preserves access to previously configured approximate stores without making them the default architecture.

### Technical explanation

It is selected only when the library vector kind requests it. Primary code anchors: OpenIntelligence/Services/VectorStore/VecturaVectorDatabase.swift; OpenIntelligence/Services/VectorStore/VectorStoreRouter.swift.

### Why it is in this position

It is selected only when the library vector kind requests it.

## OI-0202. Virtual table

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **Virtual table** means: A SQLite table whose behavior is implemented by an extension such as FTS5 rather than ordinary row storage. The reason it exists is: It exposes full-text indexing and ranking through SQL while maintaining its own inverted index internally.

### Layman’s explanation

A SQLite table whose behavior is implemented by an extension such as FTS5 rather than ordinary row storage. It exposes full-text indexing and ranking through SQL while maintaining its own inverted index internally.

### Technical explanation

The documents, chunks, and pages search surfaces are created as FTS5 virtual tables. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift.

### Why it is in this position

The documents, chunks, and pages search surfaces are created as FTS5 virtual tables.

## OI-0203. Write-ahead logging (WAL)

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a set of filing cabinets and indexes. **Write-ahead logging (WAL)** means: A SQLite journaling mode that writes changes to a separate log before merging them into the main database. The reason it exists is: It improves read/write concurrency and crash recovery for a UI that may question while ingestion persists data.

### Layman’s explanation

A SQLite journaling mode that writes changes to a separate log before merging them into the main database. It improves read/write concurrency and crash recovery for a UI that may query while ingestion persists data.

### Technical explanation

It is configured when SQLiteFullTextService opens the database. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift.

### Why it is in this position

It is configured when SQLiteFullTextService opens the database.

---

# 07. Query understanding, intent, and execution planning

**Section orientation:** The query is normalized, profiled, classified, and converted into an execution plan. Intent and complexity determine search strategy, answer policy, and whether deeper reasoning is justified.

## OI-0204. Agentic query

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Agentic query** means: A request or mode whose answer is produced through multiple search and reasoning sessions rather than one generation pass. The reason it exists is: Some questions require evidence discovery, gap assessment, reformulation, and synthesis that cannot be decided upfront.

### Layman’s explanation

A request or mode whose answer is produced through multiple retrieval and reasoning sessions rather than one generation pass. Some questions require evidence discovery, gap assessment, reformulation, and synthesis that cannot be decided upfront.

### Technical explanation

It is routed into AgenticOrchestrator after the runtime coordinator resolves the plan. Primary code anchors: OpenIntelligence/Services/Query/Analysis/QueryExecutionPlannerService.swift; OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift.

### Why it is in this position

It is routed into AgenticOrchestrator after the runtime coordinator resolves the plan.

## OI-0205. Answer intent

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Answer intent** means: The classification of the form of answer requested, such as lookup, table lookup, procedure, comparison, summary, investigation, computation, or findings. The reason it exists is: The correct evidence and response shape differ radically between an exact value and a broad synthesis.

### Layman’s explanation

The classification of the form of answer requested, such as lookup, table lookup, procedure, comparison, summary, investigation, computation, or findings. The correct evidence and response shape differ radically between an exact value and a broad synthesis.

### Technical explanation

It is inferred before retrieval and controls candidate boosts, expansion, extraction, packing, prompting, and verification. Primary code anchors: OpenIntelligence/Services/Query/Enhancement/QueryEnhancementService.swift; OpenIntelligence/Core/Models/StructuredAnswer.swift.

### Why it is in this position

It is inferred before retrieval and controls candidate boosts, expansion, extraction, packing, prompting, and verification.

## OI-0206. Compare intent

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Compare intent** means: A request to contrast two or more entities, documents, methods, or states. The reason it exists is: Comparison requires balanced evidence for each side and explicit dimensions rather than one globally highest-ranked passage.

### Layman’s explanation

A request to contrast two or more entities, documents, methods, or states. Comparison requires balanced evidence for each side and explicit dimensions rather than one globally highest-ranked passage.

### Technical explanation

It influences query decomposition, source diversity, packing, and the structured answer type. Primary code anchors: OpenIntelligence/Services/Query/Enhancement/QueryEnhancementService.swift; OpenIntelligence/Core/Models/RAGStructuredResponse.swift.

### Why it is in this position

It influences query decomposition, source diversity, packing, and the structured answer type.

## OI-0207. Complex query

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Complex query** means: A multi-part, comparative, explanatory, or otherwise broad request that warrants more possible result and context. The reason it exists is: The probability that one passage covers the whole answer decreases as the question spans more concepts.

### Layman’s explanation

A multi-part, comparative, explanatory, or otherwise broad request that warrants more candidates and context. The probability that one passage covers the whole answer decreases as the question spans more concepts.

### Technical explanation

It receives expanded retrieval and may be decomposed or escalated. Primary code anchors: OpenIntelligence/Services/Query/Analysis/QueryComplexityAnalyzer.swift.

### Why it is in this position

It receives expanded retrieval and may be decomposed or escalated.

## OI-0208. Compute intent

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Compute intent** means: A request to calculate a result from values found in the document collection. The reason it exists is: The engine must retrieve exact operands, preserve units, and distinguish source facts from the derived calculation.

### Layman’s explanation

A request to calculate a result from values found in the corpus. The engine must retrieve exact operands, preserve units, and distinguish source facts from the derived calculation.

### Technical explanation

It is detected before retrieval and is represented explicitly in the structured answer contract. Primary code anchors: OpenIntelligence/Services/Query/Enhancement/QueryEnhancementService.swift; OpenIntelligence/Core/Models/StructuredAnswer.swift.

### Why it is in this position

It is detected before retrieval and is represented explicitly in the structured answer contract.

## OI-0209. Constrained-synthesis prompt mode

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Constrained-synthesis prompt mode** means: A prompt mode allowing composition across evidence while requiring source-grounded claims and citations. The reason it exists is: Procedures, comparisons, and explanations need synthesis but still must remain bounded by retrieved context.

### Layman’s explanation

A prompt mode allowing composition across evidence while requiring source-grounded claims and citations. Procedures, comparisons, and explanations need synthesis but still must remain bounded by retrieved context.

### Technical explanation

It follows evidence packing and precedes structured generation. Primary code anchors: OpenIntelligence/Services/Query/Analysis/GroundedAnswerPolicy.swift.

### Why it is in this position

It follows evidence packing and precedes structured generation.

## OI-0210. Container vocabulary expansion

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Container vocabulary expansion** means: Expansion using terms actually present in the active library's FTS vocabulary. The reason it exists is: document collection-native language is less likely than generic synonyms to pull search into unrelated domains.

### Layman’s explanation

Expansion using terms actually present in the active library's FTS vocabulary. Corpus-native language is less likely than generic synonyms to pull retrieval into unrelated domains.

### Technical explanation

It is consulted during enhancement before the lexical query is finalized. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/ContainerVocabularyService.swift; OpenIntelligence/Services/Storage/SQLiteFullTextService.swift.

### Why it is in this position

It is consulted during enhancement before the lexical query is finalized.

## OI-0211. Cross-reference query

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Cross-reference query** means: A question whose evidence may be located at a page, table, figure, or section referenced by another retrieved passage. The reason it exists is: Technical manuals frequently answer through see page X rather than repeating the data.

### Layman’s explanation

A question whose evidence may be located at a page, table, figure, or section referenced by another retrieved passage. Technical manuals frequently answer through see page X rather than repeating the data.

### Technical explanation

It activates graph/page repair after initial candidates expose the reference. Primary code anchors: OpenIntelligence/Services/RAG/Tuning/EvidenceScoringPolicyService.swift; OpenIntelligence/Services/RAG/Retrieval/GraphIndexService.swift.

### Why it is in this position

It activates graph/page repair after initial candidates expose the reference.

## OI-0212. Decomposed execution

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Decomposed execution** means: A plan that breaks the question into smaller subquestions whose evidence can be retrieved and combined. The reason it exists is: One meaning map for a multi-clause question can average away important components and retrieve passages that address only one part.

### Layman’s explanation

A plan that breaks the question into smaller subquestions whose evidence can be retrieved and combined. One embedding for a multi-clause question can average away important components and retrieve passages that address only one part.

### Technical explanation

Subquestions are generated before or during agentic retrieval and their answers are accumulated before synthesis. Primary code anchors: OpenIntelligence/Services/Query/Analysis/QueryExecutionPlannerService.swift; OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift.

### Why it is in this position

Subquestions are generated before or during agentic retrieval and their answers are accumulated before synthesis.

## OI-0213. Descriptive keyword

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Descriptive keyword** means: A non-identity question term that states the requested property, such as reference, capacity, route, or dosage. The reason it exists is: The entity identifies the thing; the descriptive keyword identifies which attribute of that thing is wanted.

### Layman’s explanation

A non-identity query term that states the requested property, such as reference, capacity, route, or dosage. The entity identifies the thing; the descriptive keyword identifies which attribute of that thing is wanted.

### Technical explanation

It is used to score lexical hits, table keys, and extraction candidates. Primary code anchors: OpenIntelligence/Services/Query/Analysis/SpecificationExtractor.swift.

### Why it is in this position

It is used to score lexical hits, table keys, and extraction candidates.

## OI-0214. Direct execution

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Direct execution** means: A plan that sends one effective question through the normal search, packing, generation, and verification path. The reason it exists is: It minimizes latency when decomposition is unnecessary.

### Layman’s explanation

A plan that sends one effective query through the normal retrieval, packing, generation, and verification path. It minimizes latency when decomposition is unnecessary.

### Technical explanation

It is selected before retrieval and remains within Standard unless user mode or policy says otherwise. Primary code anchors: OpenIntelligence/Services/Query/Analysis/QueryExecutionPlannerService.swift.

### Why it is in this position

It is selected before retrieval and remains within Standard unless user mode or policy says otherwise.

## OI-0215. Direct-extraction prompt mode

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Direct-extraction prompt mode** means: A model prompt that asks for an answer copied or tightly derived from the evidence rather than free-form synthesis. The reason it exists is: Even when rule-based and repeatable extraction cannot decide, lookup-style questions should minimize unsupported paraphrase.

### Layman’s explanation

A model prompt that asks for an answer copied or tightly derived from the evidence rather than free-form synthesis. Even when deterministic extraction cannot decide, lookup-style questions should minimize unsupported paraphrase.

### Technical explanation

It is selected for extractive-first intents immediately before model execution. Primary code anchors: OpenIntelligence/Services/Query/Analysis/GroundedAnswerPolicy.swift; OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelPromptCompiler.swift.

### Why it is in this position

It is selected for extractive-first intents immediately before model execution.

## OI-0216. Entity extraction from query

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Entity extraction from query** means: Detecting names, model numbers, standards, dates, products, and other high-value anchors in the question. The reason it exists is: Entities often determine which exact record or document the user means and guide disambiguation.

### Layman’s explanation

Detecting names, model numbers, standards, dates, products, and other high-value anchors in the question. Entities often determine which exact record or document the user means and guide disambiguation.

### Technical explanation

It occurs during profile and specification analysis before search and extraction. Primary code anchors: OpenIntelligence/Services/Query/Enhancement/QueryEnhancementService.swift; OpenIntelligence/Services/Query/Analysis/SpecificationExtractor.swift.

### Why it is in this position

It occurs during profile and specification analysis before search and extraction.

## OI-0217. Findings intent

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Findings intent** means: A research-style request for reported findings, authors, studies, outcomes, or evidence patterns. The reason it exists is: Research documents require evidence aggregation and source attribution rather than a generic topical answer.

### Layman’s explanation

A research-style request for reported findings, authors, studies, outcomes, or evidence patterns. Research documents require evidence aggregation and source attribution rather than a generic topical answer.

### Technical explanation

It influences query planning, source-only verification, and structured output. Primary code anchors: OpenIntelligence/Core/Models/StructuredAnswer.swift; OpenIntelligence/Services/Query/Analysis/GroundedAnswerPolicy.swift.

### Why it is in this position

It influences query planning, source-only verification, and structured output.

## OI-0218. Forced agentic execution

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Forced agentic execution** means: A user action such as Go Deeper that explicitly reruns or continues a question through the agentic path. The reason it exists is: The user can request additional search and reasoning even when the initial planner chose Standard.

### Layman’s explanation

A user action such as Go Deeper that explicitly reruns or continues a question through the agentic path. The user can request additional search and reasoning even when the initial planner chose Standard.

### Technical explanation

It overrides the normal path at runtime-context resolution. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/QueryRuntimeCoordinator.swift.

### Why it is in this position

It overrides the normal path at runtime-context resolution.

## OI-0219. GroundedAnswerPolicy

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **GroundedAnswerPolicy** means: The policy deciding whether an intent should use rule-based and repeatable extraction, direct-extraction prompting, constrained synthesis, and source-only verification. The reason it exists is: It keeps exact lookup from being needlessly generated and ensures high-risk answer shapes receive the right verification.

### Layman’s explanation

The policy deciding whether an intent should use deterministic extraction, direct-extraction prompting, constrained synthesis, and source-only verification. It keeps exact lookup from being needlessly generated and ensures high-risk answer shapes receive the right verification.

### Technical explanation

It is resolved after intent classification and before extraction or generation. Primary code anchors: OpenIntelligence/Services/Query/Analysis/GroundedAnswerPolicy.swift.

### Why it is in this position

It is resolved after intent classification and before extraction or generation.

## OI-0220. HyDE

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **HyDE** means: Hypothetical Document meaning map, where a model writes a plausible answer-like passage whose meaning map is used as an additional search question. The reason it exists is: A short or abstract question may embed poorly, while a hypothetical answer can occupy the meaning-based region of relevant documents.

### Layman’s explanation

Hypothetical Document Embeddings, where a model writes a plausible answer-like passage whose embedding is used as an additional retrieval query. A short or abstract question may embed poorly, while a hypothetical answer can occupy the semantic region of relevant documents.

### Technical explanation

It occurs after query analysis and before or beside dense retrieval in Deep Think and Maximum. Primary code anchors: OpenIntelligence/Services/Query/Rewriting/HyDEService.swift.

### Why it is in this position

It occurs after query analysis and before or beside dense retrieval in Deep Think and Maximum.

## OI-0221. Hypothetical document

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Hypothetical document** means: The generated answer-like text used by HyDE only as a search probe. The reason it exists is: It enriches meaning-based vocabulary without being treated as evidence or shown as a sourced answer.

### Layman’s explanation

The generated answer-like text used by HyDE only as a retrieval probe. It enriches semantic vocabulary without being treated as evidence or shown as a sourced answer.

### Technical explanation

It is generated before dense search, embedded, and discarded after contributing candidates. Primary code anchors: OpenIntelligence/Services/Query/Rewriting/HyDEService.swift.

### Why it is in this position

It is generated before dense search, embedded, and discarded after contributing candidates.

## OI-0222. Investigate intent

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Investigate intent** means: A broad exploratory request that may require multiple evidence threads, relationships, and iterative search. The reason it exists is: The answer cannot usually be reduced to one value or one top passage.

### Layman’s explanation

A broad exploratory request that may require multiple evidence threads, relationships, and iterative retrieval. The answer cannot usually be reduced to one value or one top passage.

### Technical explanation

It raises complexity and may trigger decomposition or the agentic orchestrator. Primary code anchors: OpenIntelligence/Services/Query/Enhancement/QueryEnhancementService.swift; OpenIntelligence/Services/Query/Analysis/QueryExecutionPlannerService.swift.

### Why it is in this position

It raises complexity and may trigger decomposition or the agentic orchestrator.

## OI-0223. Keyword search intent

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Keyword search intent** means: A signal that exact terms, codes, quoted phrases, or short identifiers are central to the question. The reason it exists is: Dense meaning map can blur rare identifiers, so exact-word possible result and lower extractive thresholds deserve more weight.

### Layman’s explanation

A signal that exact terms, codes, quoted phrases, or short identifiers are central to the question. Dense embeddings can blur rare identifiers, so lexical candidates and lower extractive thresholds deserve more weight.

### Technical explanation

It is detected before hybrid retrieval and informs the retrieval cascade and acceptance policy. Primary code anchors: OpenIntelligence/Services/Query/Analysis/QueryProfileService.swift; OpenIntelligence/Services/RAG/Tuning/RetrievalPolicyService.swift.

### Why it is in this position

It is detected before hybrid retrieval and informs the retrieval cascade and acceptance policy.

## OI-0224. Lookup intent

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Lookup intent** means: A request for a specific fact, value, code, date, name, or short answer. The reason it exists is: Lookup questions benefit from high precision, exact identifiers, structured extraction, and lower tolerance for synthesis.

### Layman’s explanation

A request for a specific fact, value, code, date, name, or short answer. Lookup questions benefit from high precision, exact identifiers, structured extraction, and lower tolerance for synthesis.

### Technical explanation

It is classified before retrieval and preferentially routes through deterministic or extractive answer paths. Primary code anchors: OpenIntelligence/Services/Query/Enhancement/QueryEnhancementService.swift; OpenIntelligence/Services/Query/Analysis/GroundedAnswerPolicy.swift.

### Why it is in this position

It is classified before retrieval and preferentially routes through deterministic or extractive answer paths.

## OI-0225. Overview query

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Overview query** means: A question asking what a document, document collection, or topic is generally about rather than for one local detail. The reason it exists is: Fine-grained small source pieces can overfit incidental mentions, while summary small source pieces better represent whole-document themes.

### Layman’s explanation

A question asking what a document, corpus, or topic is generally about rather than for one local detail. Fine-grained chunks can overfit incidental mentions, while summary chunks better represent whole-document themes.

### Technical explanation

It can be routed toward document summaries before normal detail retrieval. Primary code anchors: OpenIntelligence/Services/Query/Routing/QueryRouterService.swift; OpenIntelligence/Services/RAG/Retrieval/RAPTORSummaryRouter.swift.

### Why it is in this position

It can be routed toward document summaries before normal detail retrieval.

## OI-0226. Planner escalation

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Planner escalation** means: Automatic promotion from a nominal Standard request to the agentic path when the execution planner predicts that one pass is insufficient. The reason it exists is: It allows complexity rather than the mode label alone to control work.

### Layman’s explanation

Automatic promotion from a nominal Standard request to the agentic path when the execution planner predicts that one pass is insufficient. It allows complexity rather than the mode label alone to control work.

### Technical explanation

It is resolved by QueryRuntimeCoordinator before retrieval. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/QueryRuntimeCoordinator.swift.

**Important caveat:** Automatic escalation is deliberately disabled for Apple Foundation Models in current source to avoid pathological session loops; user-selected Deep Think or Maximum still enters agentic execution.

### Why it is in this position

It is resolved by QueryRuntimeCoordinator before retrieval.

## OI-0227. Primary entity

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Primary entity** means: The strongest identity-bearing token or phrase in a lookup, such as 1688, a device model, or a named product. The reason it exists is: A possible result containing the primary entity can resolve ambiguity among otherwise similar specifications.

### Layman’s explanation

The strongest identity-bearing token or phrase in a lookup, such as 1688, a device model, or a named product. A candidate containing the primary entity can resolve ambiguity among otherwise similar specifications.

### Technical explanation

It is extracted before candidate scoring and used as an override in deterministic specification extraction. Primary code anchors: OpenIntelligence/Services/Query/Analysis/SpecificationExtractor.swift.

### Why it is in this position

It is extracted before candidate scoring and used as an override in deterministic specification extraction.

## OI-0228. Procedure intent

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Procedure intent** means: A request for ordered steps, instructions, setup, troubleshooting, or a process. The reason it exists is: Procedures need adjacent sequence context and should not be answered from one isolated matching sentence.

### Layman’s explanation

A request for ordered steps, instructions, setup, troubleshooting, or a process. Procedures need adjacent sequence context and should not be answered from one isolated matching sentence.

### Technical explanation

It increases sibling/parent expansion and uses order-preserving context packing before generation. Primary code anchors: OpenIntelligence/Services/Query/Enhancement/QueryEnhancementService.swift; OpenIntelligence/Services/RAG/Tuning/RetrievalPolicyService.swift.

### Why it is in this position

It increases sibling/parent expansion and uses order-preserving context packing before generation.

## OI-0229. Query complexity

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Query complexity** means: A classification such as trivial, standard, complex, or agentic derived from length, conjunctions, comparisons, reasoning markers, entities, and intent. The reason it exists is: Complexity controls how much search, rewriting, context, time, and model work is justified.

### Layman’s explanation

A classification such as trivial, standard, complex, or agentic derived from length, conjunctions, comparisons, reasoning markers, entities, and intent. Complexity controls how much retrieval, rewriting, context, time, and model work is justified.

### Technical explanation

It is computed before the adaptive pipeline configuration and execution path are finalized. Primary code anchors: OpenIntelligence/Services/Query/Analysis/QueryComplexityAnalyzer.swift; OpenIntelligence/Services/RAG/Orchestration/QueryRuntimeCoordinator.swift.

### Why it is in this position

It is computed before the adaptive pipeline configuration and execution path are finalized.

## OI-0230. Query decomposition

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Query decomposition** means: Splitting one complex request into all-or-nothing subquestions or facets. The reason it exists is: Separate search probes reduce meaning-based averaging and make missing coverage visible.

### Layman’s explanation

Splitting one complex request into atomic subquestions or facets. Separate retrieval probes reduce semantic averaging and make missing coverage visible.

### Technical explanation

It occurs before iterative or agentic retrieval and precedes FactBank synthesis. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift; OpenIntelligence/Services/Query/Analysis/QueryExecutionPlannerService.swift.

### Why it is in this position

It occurs before iterative or agentic retrieval and precedes FactBank synthesis.

## OI-0231. Query expansion

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Query expansion** means: Adding synonyms, related terms, entities, abbreviations, or document collection vocabulary to improve recall. The reason it exists is: The relevant passage may use a technical term the user does not know or an acronym the user spelled out.

### Layman’s explanation

Adding synonyms, related terms, entities, abbreviations, or corpus vocabulary to improve recall. The relevant passage may use a technical term the user does not know or an acronym the user spelled out.

### Technical explanation

It runs after profile/rewrite and supplies additional lexical or semantic searches before fusion. Primary code anchors: OpenIntelligence/Services/Query/Enhancement/QueryEnhancementService.swift.

### Why it is in this position

It runs after profile/rewrite and supplies additional lexical or semantic searches before fusion.

## OI-0232. Query normalization

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Query normalization** means: Cleaning and canonicalizing the user question for stable comparison, tokenization, cache lookup, and downstream heuristics. The reason it exists is: Whitespace, punctuation, casing, and conversational phrasing can create accidental differences that do not change intent.

### Layman’s explanation

Cleaning and canonicalizing the user question for stable comparison, tokenization, cache lookup, and downstream heuristics. Whitespace, punctuation, casing, and conversational phrasing can create accidental differences that do not change intent.

### Technical explanation

It occurs immediately after submission and before profile, cache, rewrite, or retrieval decisions. Primary code anchors: OpenIntelligence/Services/Query/Analysis/QueryProfileService.swift; OpenIntelligence/Services/RAG/Orchestration/RAGService.swift.

### Why it is in this position

It occurs immediately after submission and before profile, cache, rewrite, or retrieval decisions.

## OI-0233. Query rewriting

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Query rewriting** means: Producing a cleaner, standalone, search-oriented version of the user's question. The reason it exists is: Conversational pronouns, ellipsis, vague phrasing, and extra words can lower both exact-word and dense search quality.

### Layman’s explanation

Producing a cleaner, standalone, retrieval-oriented version of the user's question. Conversational pronouns, ellipsis, vague phrasing, and extra words can lower both lexical and dense retrieval quality.

### Technical explanation

It occurs after profiling and conversation context but before final query embedding and search. Primary code anchors: OpenIntelligence/Services/Query/Rewriting/QueryRewriterService.swift.

### Why it is in this position

It occurs after profiling and conversation context but before final query embedding and search.

## OI-0234. Query variation

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Query variation** means: An alternative phrasing generated after weak or repetitive search. The reason it exists is: A different wording can access exact-word or meaning-based neighborhoods missed by the original expression.

### Layman’s explanation

An alternative phrasing generated after weak or repetitive retrieval. A different wording can access lexical or semantic neighborhoods missed by the original expression.

### Technical explanation

It is issued during iterative or agentic retrieval after evidence assessment identifies a gap. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift; OpenIntelligence/Services/RAG/Tuning/RetrievalPolicyService.swift.

### Why it is in this position

It is issued during iterative or agentic retrieval after evidence assessment identifies a gap.

## OI-0235. QueryExecutionPlan

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **QueryExecutionPlan** means: The explicit decision about direct execution, decomposition, tool use, agentic escalation, and response strategy for one question. The reason it exists is: A profile describes the question; a plan says what the engine will actually do about it.

### Layman’s explanation

The explicit decision about direct execution, decomposition, tool use, agentic escalation, and response strategy for one question. A profile describes the question; a plan says what the engine will actually do about it.

### Technical explanation

It is built after profiling and before either Standard or agentic execution begins. Primary code anchors: OpenIntelligence/Services/Query/Analysis/QueryExecutionPlannerService.swift.

### Why it is in this position

It is built after profiling and before either Standard or agentic execution begins.

## OI-0236. QueryProfile

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **QueryProfile** means: The per-question summary of word count, entities, answer intent, search intent, routing classification, complexity, and other decision signals. The reason it exists is: Every conditional stage needs one coherent interpretation of the question instead of independently reclassifying it.

### Layman’s explanation

The per-question summary of word count, entities, answer intent, search intent, routing classification, complexity, and other decision signals. Every conditional stage needs one coherent interpretation of the question instead of independently reclassifying it.

### Technical explanation

It is built near query start and consumed by retrieval, packing, extraction, and orchestration policy. Primary code anchors: OpenIntelligence/Services/Query/Analysis/QueryProfileService.swift.

### Why it is in this position

It is built near query start and consumed by retrieval, packing, extraction, and orchestration policy.

## OI-0237. Response strategy

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Response strategy** means: The plan to use rule-based and repeatable extraction, constrained synthesis, extractive summarization, or agentic synthesis. The reason it exists is: The safest and cheapest answer mechanism depends on intent and evidence structure.

### Layman’s explanation

The plan to use deterministic extraction, constrained synthesis, extractive summarization, or agentic synthesis. The safest and cheapest answer mechanism depends on intent and evidence structure.

### Technical explanation

It is chosen before answer generation and can fall back when a preferred path lacks confidence. Primary code anchors: OpenIntelligence/Services/Query/Analysis/GroundedAnswerPolicy.swift; OpenIntelligence/Services/Query/Analysis/QueryExecutionPlannerService.swift.

### Why it is in this position

It is chosen before answer generation and can fall back when a preferred path lacks confidence.

## OI-0238. Routing classification

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Routing classification** means: A question label describing whether the request is direct, cross-topic, overview, or otherwise needs a specialized search route. The reason it exists is: Search architecture should respond to the shape of the information need, not just the words in the question.

### Layman’s explanation

A query label describing whether the request is direct, cross-topic, overview, or otherwise needs a specialized retrieval route. Search architecture should respond to the shape of the information need, not just the words in the query.

### Technical explanation

It is built into QueryProfile and consumed by parent expansion and query planning. Primary code anchors: OpenIntelligence/Services/Query/Routing/QueryRouterService.swift; OpenIntelligence/Services/Query/Analysis/QueryProfileService.swift.

### Why it is in this position

It is built into QueryProfile and consumed by parent expansion and query planning.

## OI-0239. Search intent

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Search intent** means: The classification of how evidence is likely to be found, including meaning-based, keyword, hybrid, or overview-oriented search. The reason it exists is: A model number should lean exact-word while a paraphrased concept needs dense search; overview questions may target summaries.

### Layman’s explanation

The classification of how evidence is likely to be found, including semantic, keyword, hybrid, or overview-oriented search. A model number should lean lexical while a paraphrased concept needs dense retrieval; overview questions may target summaries.

### Technical explanation

It is resolved in the query profile and changes retrieval weights, routes, and thresholds. Primary code anchors: OpenIntelligence/Services/Query/Analysis/QueryProfileService.swift; OpenIntelligence/Services/Query/Routing/QueryRouterService.swift.

### Why it is in this position

It is resolved in the query profile and changes retrieval weights, routes, and thresholds.

## OI-0240. Semantic search intent

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Semantic search intent** means: A signal that meaning and paraphrase matter more than exact surface terms. The reason it exists is: The document may express the answer with different vocabulary than the user.

### Layman’s explanation

A signal that meaning and paraphrase matter more than exact surface terms. The document may express the answer with different vocabulary than the user.

### Technical explanation

It favors dense retrieval while still retaining lexical coverage through the hybrid path. Primary code anchors: OpenIntelligence/Services/Query/Analysis/QueryProfileService.swift.

### Why it is in this position

It favors dense retrieval while still retaining lexical coverage through the hybrid path.

## OI-0241. Specification-heavy query

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Specification-heavy query** means: A question likely to require codes, measurements, standards, capacities, or other exact technical values. The reason it exists is: These questions need structured and numeric evidence boosts and stricter unit verification.

### Layman’s explanation

A question likely to require codes, measurements, standards, capacities, or other exact technical values. These questions need structured and numeric evidence boosts and stricter unit verification.

### Technical explanation

It is detected before corrective retrieval, spec-sniper scoring, and extraction. Primary code anchors: OpenIntelligence/Services/Query/Analysis/SpecificationExtractor.swift; OpenIntelligence/Services/RAG/Tuning/EvidenceScoringPolicyService.swift.

### Why it is in this position

It is detected before corrective retrieval, spec-sniper scoring, and extraction.

## OI-0242. Standalone rewrite

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Standalone rewrite** means: A rewrite that resolves references such as it, that one, or the previous result into an explicit question. The reason it exists is: search does not see the human conversational context unless it is incorporated into the question.

### Layman’s explanation

A rewrite that resolves references such as it, that one, or the previous result into an explicit question. Retrieval does not see the human conversational context unless it is incorporated into the query.

### Technical explanation

It uses recent memory before retrieval and does not replace the original user message in the conversation. Primary code anchors: OpenIntelligence/Services/Query/Rewriting/QueryRewriterService.swift; OpenIntelligence/Services/Agentic/ConversationMemoryService.swift.

### Why it is in this position

It uses recent memory before retrieval and does not replace the original user message in the conversation.

## OI-0243. State-lookup query

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **State-lookup query** means: A request about indicator colors, solid/flashing states, status lights, or similar mappings. The reason it exists is: The requested answer depends on co-occurrence of a state and its meaning, so generic meaning-based similarity can choose the wrong row.

### Layman’s explanation

A request about indicator colors, solid/flashing states, status lights, or similar mappings. The requested answer depends on co-occurrence of a state and its meaning, so generic semantic similarity can choose the wrong row.

### Technical explanation

It activates color/state anchor scoring and structured evidence preferences before extraction. Primary code anchors: OpenIntelligence/Services/RAG/Tuning/EvidenceScoringPolicyService.swift.

### Why it is in this position

It activates color/state anchor scoring and structured evidence preferences before extraction.

## OI-0244. Subquestion

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Subquestion** means: One all-or-nothing information requirement derived from a larger user question. The reason it exists is: Coverage and stopping can be measured per requirement rather than by answer length or source count.

### Layman’s explanation

One atomic information requirement derived from a larger user question. Coverage and stopping can be measured per requirement rather than by answer length or source count.

### Technical explanation

Each subquestion may drive its own retrieval pass before final synthesis. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift; OpenIntelligence/Services/RAG/Tuning/AgenticPolicyService.swift.

### Why it is in this position

Each subquestion may drive its own retrieval pass before final synthesis.

## OI-0245. Summarize intent

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Summarize intent** means: A request to condense a document, section, topic, or result set. The reason it exists is: A summary should maximize coverage and reduce redundancy rather than retrieve only the single strongest exact hit.

### Layman’s explanation

A request to condense a document, section, topic, or result set. A summary should maximize coverage and reduce redundancy rather than retrieve only the single strongest exact hit.

### Technical explanation

It can route toward document-summary chunks or extractive sentence selection before optional synthesis. Primary code anchors: OpenIntelligence/Services/Query/Routing/QueryRouterService.swift; OpenIntelligence/Services/RAG/Extraction/ExtractiveSummarizationService.swift.

### Why it is in this position

It can route toward document-summary chunks or extractive sentence selection before optional synthesis.

## OI-0246. Table-lookup intent

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Table-lookup intent** means: A lookup whose answer is expected in a row, cell, key-value table, or other structured record. The reason it exists is: Flattened prose ranking can retrieve the right table but return the wrong cell. Structured lookup preserves the requested relationship.

### Layman’s explanation

A lookup whose answer is expected in a row, cell, key-value table, or other structured record. Flattened prose ranking can retrieve the right table but return the wrong cell. Structured lookup preserves the requested relationship.

### Technical explanation

It triggers structured-row and specification extraction before generative fallback. Primary code anchors: OpenIntelligence/Services/Query/Analysis/SpecificationExtractor.swift; OpenIntelligence/Core/Models/StructuredAnswer.swift.

### Why it is in this position

It triggers structured-row and specification extraction before generative fallback.

## OI-0247. Touchy query

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Touchy query** means: A question containing safety-critical categories or terms such as dosage, pressure, warning, hazard, maximum, or failure. The reason it exists is: Wrong precision on a critical limit has a higher cost than a minor descriptive omission, so thresholds should be stricter.

### Layman’s explanation

A query containing safety-critical categories or terms such as dosage, pressure, warning, hazard, maximum, or failure. Wrong precision on a critical limit has a higher cost than a minor descriptive omission, so thresholds should be stricter.

### Technical explanation

It is detected before verification policy and raises grounding and abstention requirements. Primary code anchors: OpenIntelligence/Services/RAG/Tuning/ConfidencePolicyService.swift.

### Why it is in this position

It is detected before verification policy and raises grounding and abstention requirements.

## OI-0248. Trivial query

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a dispatcher interpreting a request. **Trivial query** means: A short and simple request that can use a reduced possible result set and skip expensive enhancement stages. The reason it exists is: Running HyDE, iterative search, or agentic sessions on every easy lookup adds latency without proportional quality.

### Layman’s explanation

A short and simple request that can use a reduced candidate set and skip expensive enhancement stages. Running HyDE, iterative retrieval, or agentic sessions on every easy lookup adds latency without proportional quality.

### Technical explanation

It is identified at profile time and receives the smallest adaptive configuration. Primary code anchors: OpenIntelligence/Services/Query/Analysis/QueryComplexityAnalyzer.swift; OpenIntelligence/Services/Infrastructure/Optimization/AdaptivePipelineOptimizer.swift.

### Why it is in this position

It is identified at profile time and receives the smallest adaptive configuration.

---

# 08. Retrieval, fusion, reranking, and evidence expansion

**Section orientation:** Hybrid retrieval combines dense and lexical search. RRF merges rankings, boosts protect high-value signals, TinyBERT reranks candidates, MMR diversifies, and parent or sibling expansion adds context.

## OI-0249. Acceptance override

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Acceptance override** means: A rule allowing possible result through despite a nominal score floor when relative rank, score margin, breadth, or extractive intent provides sufficient evidence. The reason it exists is: It prevents rigid thresholds from discarding the best available exact evidence in a difficult number coordinates space.

### Layman’s explanation

A rule allowing candidates through despite a nominal score floor when relative rank, score margin, breadth, or extractive intent provides sufficient evidence. It prevents rigid thresholds from discarding the best available exact evidence in a difficult vector space.

### Technical explanation

It is evaluated after dynamic threshold calculation and before the empty-retrieval fallback. Primary code anchors: OpenIntelligence/Services/RAG/Tuning/RetrievalPolicyService.swift.

### Why it is in this position

It is evaluated after dynamic threshold calculation and before the empty-retrieval fallback.

## OI-0250. Breadth-first search (BFS)

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Breadth-first search (BFS)** means: A graph traversal that visits immediate neighbors before progressively more distant hops. The reason it exists is: BFS provides bounded, interpretable expansion around a retrieved anchor and avoids diving deeply down one arbitrary relationship.

### Layman’s explanation

A graph traversal that visits immediate neighbors before progressively more distant hops. BFS provides bounded, interpretable expansion around a retrieved anchor and avoids diving deeply down one arbitrary relationship.

### Technical explanation

It begins from top retrieved chunks and stops at hop, score, or budget limits. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/GraphIndexService.swift.

### Why it is in this position

It begins from top retrieved chunks and stops at hop, score, or budget limits.

## OI-0251. Candidate generation

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Candidate generation** means: The broad first search step that produces more possible small source pieces than will ultimately reach the model. The reason it exists is: High recall must come before high precision because reranking cannot recover evidence that was never retrieved.

### Layman’s explanation

The broad first retrieval step that produces more possible chunks than will ultimately reach the model. High recall must come before high precision because reranking cannot recover evidence that was never retrieved.

### Technical explanation

It follows query embedding/lexical preparation and precedes fusion, filtering, reranking, and packing. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift; OpenIntelligence/Services/Evaluation/RetrievalStageMetrics.swift.

### Why it is in this position

It follows query embedding/lexical preparation and precedes fusion, filtering, reranking, and packing.

## OI-0252. Corrective retrieval

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Corrective retrieval** means: A targeted fallback that rescans for question terms, structured data, numeric patterns, or cross-reference destinations when normal ranking missed the expected evidence shape. The reason it exists is: Dense and exact-word search can retrieve the right topic but not the exact row or page containing the answer.

### Layman’s explanation

A targeted fallback that rescans for query terms, structured data, numeric patterns, or cross-reference destinations when normal ranking missed the expected evidence shape. Dense and lexical retrieval can retrieve the right topic but not the exact row or page containing the answer.

### Technical explanation

It runs after weak evidence assessment and before abstention or generation. Primary code anchors: OpenIntelligence/Services/RAG/Tuning/EvidenceScoringPolicyService.swift; OpenIntelligence/Services/RAG/Orchestration/RAGService.swift.

### Why it is in this position

It runs after weak evidence assessment and before abstention or generation.

## OI-0253. Cross-encoder reranking

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Cross-encoder reranking** means: A second-stage model that reads the question and one possible result passage together and assigns a relevance score. The reason it exists is: Joint encoding captures fine-grained interactions that independently generated bi-encoder number coordinates cannot see.

### Layman’s explanation

A second-stage model that reads the query and one candidate passage together and assigns a relevance score. Joint encoding captures fine-grained interactions that independently generated bi-encoder vectors cannot see.

### Technical explanation

It receives the fused shortlist and reorders it before diversity selection and expansion. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/RAGEngine.swift; OpenIntelligence/UI/Components/Glossary.swift.

### Why it is in this position

It receives the fused shortlist and reorders it before diversity selection and expansion.

## OI-0254. Cross-reference repair

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Cross-reference repair** means: Following a detected page, table, figure, or section reference and retrieving the destination evidence. The reason it exists is: A reference-bearing small source piece is not itself the answer and can otherwise create a false positive.

### Layman’s explanation

Following a detected page, table, figure, or section reference and retrieving the destination evidence. A reference-bearing chunk is not itself the answer and can otherwise create a false positive.

### Technical explanation

It occurs after a first retrieval exposes the reference and before context is finalized. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/GraphIndexService.swift; OpenIntelligence/Services/RAG/Tuning/EvidenceScoringPolicyService.swift.

### Why it is in this position

It occurs after a first retrieval exposes the reference and before context is finalized.

## OI-0255. Dense retrieval

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Dense retrieval** means: Searching stored passage number coordinates by cosine similarity to the question number coordinates. The reason it exists is: It finds meaning-based equivalents and paraphrases with little or no exact word overlap.

### Layman’s explanation

Searching stored passage vectors by cosine similarity to the query vector. It finds semantic equivalents and paraphrases with little or no exact word overlap.

### Technical explanation

It runs in parallel with lexical retrieval and contributes one ranked list to fusion. Primary code anchors: OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift; OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift.

### Why it is in this position

It runs in parallel with lexical retrieval and contributes one ranked list to fusion.

## OI-0256. Document-order restoration

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Document-order restoration** means: Sorting selected summary sentences back into their original sequence after relevance and diversity selection. The reason it exists is: Reading a summary in rank order can reverse chronology or logical progression.

### Layman’s explanation

Sorting selected summary sentences back into their original sequence after relevance and diversity selection. Reading a summary in rank order can reverse chronology or logical progression.

### Technical explanation

It is the last extractive-summarization step before the text is returned. Primary code anchors: OpenIntelligence/Services/RAG/Extraction/ExtractiveSummarizationService.swift.

### Why it is in this position

It is the last extractive-summarization step before the text is returned.

## OI-0257. Dynamic similarity threshold

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Dynamic similarity threshold** means: A per-question adjustment of the configured score floor based on possible result count, top score, spread, intent, and suspected vocabulary mismatch. The reason it exists is: Absolute cosine scores are not universally adjusted against a trust rule. Relative evidence can show a useful result even when every score is low.

### Layman’s explanation

A per-query adjustment of the configured score floor based on candidate count, top score, spread, intent, and suspected vocabulary mismatch. Absolute cosine scores are not universally calibrated. Relative evidence can show a useful result even when every score is low.

### Technical explanation

It is computed after initial candidates and before filtering. Primary code anchors: OpenIntelligence/Services/RAG/Tuning/RetrievalPolicyService.swift.

### Why it is in this position

It is computed after initial candidates and before filtering.

## OI-0258. Entity expansion

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Entity expansion** means: Fetching small source pieces connected through entities shared with the question or current evidence. The reason it exists is: A concept may be discussed across distant sections and documents without repeating the full question phrase.

### Layman’s explanation

Fetching chunks connected through entities shared with the query or current evidence. A concept may be discussed across distant sections and documents without repeating the full query phrase.

### Technical explanation

It occurs during graph or agentic expansion after entities are identified. Primary code anchors: OpenIntelligence/Services/Document/Analysis/EntityIndexService.swift; OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift.

### Why it is in this position

It occurs during graph or agentic expansion after entities are identified.

## OI-0259. Entity-aware disambiguation

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Entity-aware disambiguation** means: Preferring a possible result that contains the question's primary entity when competing values are otherwise close. The reason it exists is: It prevents a nearby specification for a similar product from winning over the explicitly named one.

### Layman’s explanation

Preferring a candidate that contains the query's primary entity when competing values are otherwise close. It prevents a nearby specification for a similar product from winning over the explicitly named one.

### Technical explanation

It is applied after candidate scoring and before ambiguity failure. Primary code anchors: OpenIntelligence/Services/Query/Analysis/SpecificationExtractor.swift.

### Why it is in this position

It is applied after candidate scoring and before ambiguity failure.

## OI-0260. Evidence assessment

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Evidence assessment** means: Scoring whether the current results cover the question, contain enough relevance, and leave identifiable gaps. The reason it exists is: A loop needs an evidence-based reason to continue rather than a fixed number of redundant searches.

### Layman’s explanation

Scoring whether the current results cover the question, contain enough relevance, and leave identifiable gaps. A loop needs an evidence-based reason to continue rather than a fixed number of redundant searches.

### Technical explanation

It runs after each iterative or agentic retrieval pass and before refinement or stopping. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/IterativeRetrievalService.swift; OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift.

### Why it is in this position

It runs after each iterative or agentic retrieval pass and before refinement or stopping.

## OI-0261. Explicit state-structure lookup

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Explicit state-structure lookup** means: Direct extraction from structured mappings for indicator colors, flashing states, and their meanings. The reason it exists is: It preserves the exact pairing between a visible state and its interpretation.

### Layman’s explanation

Direct extraction from structured mappings for indicator colors, flashing states, and their meanings. It preserves the exact pairing between a visible state and its interpretation.

### Technical explanation

It is one of the first branches inside SpecificationExtractor for state-style queries. Primary code anchors: OpenIntelligence/Services/Query/Analysis/SpecificationExtractor.swift.

### Why it is in this position

It is one of the first branches inside SpecificationExtractor for state-style queries.

## OI-0262. Extraction confidence

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Extraction confidence** means: The score estimating how strongly a possible result value matches the question entity, requested attribute, structure, and proximity signals. The reason it exists is: A rule-based and repeatable extractor still needs to say there is not enough evidence when several values are plausible.

### Layman’s explanation

The score estimating how strongly a candidate value matches the query entity, requested attribute, structure, and proximity signals. A deterministic extractor still needs to abstain when several values are plausible.

### Technical explanation

It is calculated before returning a span; low confidence or ambiguity escalates to the model. Primary code anchors: OpenIntelligence/Services/Query/Analysis/SpecificationExtractor.swift.

### Why it is in this position

It is calculated before returning a span; low confidence or ambiguity escalates to the model.

## OI-0263. Extractive QA

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Extractive QA** means: Returning an answer span copied from retrieved evidence instead of generating new prose. The reason it exists is: Exact extraction eliminates a major class of hallucination because the returned value must exist in the source.

### Layman’s explanation

Returning an answer span copied from retrieved evidence instead of generating new prose. Exact extraction eliminates a major class of hallucination because the returned value must exist in the source.

### Technical explanation

It is selected for lookup-style intents after retrieval and before abstractive generation. Primary code anchors: OpenIntelligence/Services/RAG/Extraction/ExtractiveQAService.swift; OpenIntelligence/Services/Query/Analysis/SpecificationExtractor.swift.

### Why it is in this position

It is selected for lookup-style intents after retrieval and before abstractive generation.

## OI-0264. Extractive summarization

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Extractive summarization** means: Selecting source sentences rather than writing a new summary. The reason it exists is: It reduces model-written hallucination and preserves traceable wording for summary requests.

### Layman’s explanation

Selecting source sentences rather than writing a new summary. It reduces generative hallucination and preserves traceable wording for summary requests.

### Technical explanation

It segments retrieved chunks, embeds sentences, applies MMR, then restores document order. Primary code anchors: OpenIntelligence/Services/RAG/Extraction/ExtractiveSummarizationService.swift.

### Why it is in this position

It segments retrieved chunks, embeds sentences, applies MMR, then restores document order.

## OI-0265. Fusion weight

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Fusion weight** means: The relative influence assigned to exact-word and number coordinates arms around the rank-fusion result. The reason it exists is: The arms do not necessarily have equal quality in this document collection, so the mixture must be measured rather than assumed.

### Layman’s explanation

The relative influence assigned to lexical and vector arms around the rank-fusion result. The arms do not necessarily have equal quality in this corpus, so the mixture must be measured rather than assumed.

### Technical explanation

It is resolved before or during fusion and can be varied in benchmark-only experiments. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift; scripts/sweep_fusion_weight.py.

### Why it is in this position

It is resolved before or during fusion and can be varied in benchmark-only experiments.

## OI-0266. Fusion-stage regression

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Fusion-stage regression** means: The measured case where combining a weak dense arm with a stronger exact-word arm lowers rank quality relative to BM25 alone. The reason it exists is: It demonstrates why a theoretically sound architecture still needs instance-specific evaluation and tuning.

### Layman’s explanation

The measured case where combining a weak dense arm with a stronger lexical arm lowers rank quality relative to BM25 alone. It demonstrates why a theoretically sound architecture still needs instance-specific evaluation and tuning.

### Technical explanation

It is observed in benchmark analysis after separate vector, lexical, and fusion outputs are scored. Primary code anchors: Docs/EVALS.md; Docs/AuditArtifacts/Benchmarks/20260813-222128-matrix.md.

**Important caveat:** In the cited QASPER run, lexical MRR materially exceeded dense MRR and fusion underperformed lexical; this is a current tuning finding, not a reason to remove semantic retrieval categorically.

### Why it is in this position

It is observed in benchmark analysis after separate vector, lexical, and fusion outputs are scored.

## OI-0267. Graph edge

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Graph edge** means: A typed connection between two small source pieces or entities, such as next, previous, sibling, reference, same section, or shared entity. The reason it exists is: Edge type preserves why two items are related and supports controlled expansion rather than global search.

### Layman’s explanation

A typed connection between two chunks or entities, such as next, previous, sibling, reference, same section, or shared entity. Edge type preserves why two items are related and supports controlled expansion rather than global search.

### Technical explanation

Edges are created during indexing and followed during graph retrieval or context packing. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/GraphIndexService.swift.

### Why it is in this position

Edges are created during indexing and followed during graph retrieval or context packing.

## OI-0268. Graph hop

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Graph hop** means: One relationship traversal away from an anchor small source piece. The reason it exists is: Hop count approximates relationship distance and limits the blast radius of graph expansion.

### Layman’s explanation

One relationship traversal away from an anchor chunk. Hop count approximates relationship distance and limits the blast radius of graph expansion.

### Technical explanation

It is counted during BFS and considered by context packing. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/GraphIndexService.swift; OpenIntelligence/Services/RAG/Retrieval/ContextPackingService.swift.

### Why it is in this position

It is counted during BFS and considered by context packing.

## OI-0269. Graph index

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Graph index** means: An in-memory or derived adjacency structure connecting small source pieces through siblings, references, entities, sections, pages, and document relationships. The reason it exists is: Important evidence can be one relationship away from the exact-word or meaning-based hit.

### Layman’s explanation

An in-memory or derived adjacency structure connecting chunks through siblings, references, entities, sections, pages, and document relationships. Important evidence can be one relationship away from the lexical or semantic hit.

### Technical explanation

It is constructed from chunk metadata and traversed after initial retrieval. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/GraphIndexService.swift.

### Why it is in this position

It is constructed from chunk metadata and traversed after initial retrieval.

## OI-0270. Heuristic extractive QA

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Heuristic extractive QA** means: The active Natural Language and rule-based sentence/span scorer using keyword overlap, entity types, proximity, passage rank, and question type. The reason it exists is: It provides source-bounded extraction without requiring a trained neural start/end model.

### Layman’s explanation

The active Natural Language and rule-based sentence/span scorer using keyword overlap, entity types, proximity, passage rank, and question type. It provides source-bounded extraction without requiring a trained neural start/end model.

### Technical explanation

It runs when extractive QA is selected and the dedicated Core ML span model is unavailable. Primary code anchors: OpenIntelligence/Services/RAG/Extraction/ExtractiveQAService.swift.

### Why it is in this position

It runs when extractive QA is selected and the dedicated Core ML span model is unavailable.

## OI-0271. Hybrid search

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Hybrid search** means: The coordinated dense and exact-word search whose ranked results are merged and then reranked. The reason it exists is: The two arms have complementary failure modes, so retaining both increases coverage across conceptual and exact queries.

### Layman’s explanation

The coordinated dense and lexical search whose ranked results are merged and then reranked. The two arms have complementary failure modes, so retaining both increases coverage across conceptual and exact queries.

### Technical explanation

It is the main retrieval entry point after query preparation and before evidence expansion. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift; OpenIntelligence/UI/Components/Glossary.swift.

### Why it is in this position

It is the main retrieval entry point after query preparation and before evidence expansion.

## OI-0272. Initial candidate breadth

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Initial candidate breadth** means: The larger top-k used before expensive reranking, currently mode-dependent at roughly 30, 35, or 50. The reason it exists is: A cross-encoder can improve order only among possible result it receives, so the first stage must be broad enough to contain the answer.

### Layman’s explanation

The larger top-k used before expensive reranking, currently mode-dependent at roughly 30, 35, or 50. A cross-encoder can improve order only among candidates it receives, so the first stage must be broad enough to contain the answer.

### Technical explanation

It is resolved from quality mode before hybrid search. Primary code anchors: OpenIntelligence/Core/Models/RAGQualityMode.swift.

### Why it is in this position

It is resolved from quality mode before hybrid search.

## OI-0273. Iterative retrieval

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Iterative retrieval** means: A retrieve, assess, refine, and retrieve-again loop. The reason it exists is: The first question can miss evidence or reveal terminology needed for a better second search.

### Layman’s explanation

A retrieve, assess, refine, and retrieve-again loop. The first query can miss evidence or reveal terminology needed for a better second search.

### Technical explanation

It begins after an initial result set is judged insufficient and stops on quality, pass count, or no-improvement rules. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/IterativeRetrievalService.swift.

### Why it is in this position

It begins after an initial result set is judged insufficient and stops on quality, pass count, or no-improvement rules.

## OI-0274. Jaccard deduplication

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Jaccard deduplication** means: A token-set overlap check used to discard expanded content that is substantially redundant, around an 0.8 overlap threshold in the parent service. The reason it exists is: Parent and child passages naturally overlap, and including both verbatim can consume context without adding information.

### Layman’s explanation

A token-set overlap check used to discard expanded content that is substantially redundant, around an 0.8 overlap threshold in the parent service. Parent and child passages naturally overlap, and including both verbatim can consume context without adding information.

### Technical explanation

It is applied while expansion results are merged. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/ParentDocumentService.swift.

### Why it is in this position

It is applied while expansion results are merged.

## OI-0275. L0 chunk

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **L0 chunk** means: A normal source-level detail small source piece containing directly extracted document content. The reason it exists is: It is the primary evidence unit for exact facts and citations.

### Layman’s explanation

A normal source-level detail chunk containing directly extracted document content. It is the primary evidence unit for exact facts and citations.

### Technical explanation

It is created during chunking and searched in the standard retrieval path. Primary code anchors: OpenIntelligence/Core/Models/DocumentChunk.swift.

### Why it is in this position

It is created during chunking and searched in the standard retrieval path.

## OI-0276. L1 summary chunk

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **L1 summary chunk** means: A document-level summary small source piece derived from representative L0 content. The reason it exists is: It provides an summary level layer for overview search and broad routing.

### Layman’s explanation

A document-level summary chunk derived from representative L0 content. It provides an abstraction layer for overview retrieval and broad routing.

### Technical explanation

It is produced after ingestion analysis and searched only when summary routing is appropriate. Primary code anchors: OpenIntelligence/Core/Models/DocumentChunk.swift; OpenIntelligence/Services/Document/Analysis/DocumentSummaryService.swift.

### Why it is in this position

It is produced after ingestion analysis and searched only when summary routing is appropriate.

## OI-0277. L2 and L3 abstraction levels

**Status:** Future, meaning it is reserved for future architecture.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **L2 and L3 abstraction levels** means: Reserved section- and document collection-level summary layers in the DocumentChunk summary level enum. The reason it exists is: Hierarchical summaries could support larger libraries and multi-document overview questions.

### Layman’s explanation

Reserved section- and corpus-level summary layers in the DocumentChunk abstraction enum. Hierarchical summaries could support larger libraries and multi-document overview questions.

### Technical explanation

They are defined after L1 conceptually but are not established as active production retrieval layers. Primary code anchors: OpenIntelligence/Core/Models/DocumentChunk.swift.

### Why it is in this position

They are defined after L1 conceptually but are not established as active production retrieval layers.

## OI-0278. Lexical retrieval

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Lexical retrieval** means: Searching FTS5 for exact or stemmed question terms and ranking matches with BM25. The reason it exists is: It is strong on part numbers, standards, names, quotations, and measurements that meaning map may smooth away.

### Layman’s explanation

Searching FTS5 for exact or stemmed query terms and ranking matches with BM25. It is strong on part numbers, standards, names, quotations, and measurements that embeddings may smooth away.

### Technical explanation

It runs in parallel with dense retrieval and contributes the second ranked list to fusion. Primary code anchors: OpenIntelligence/Services/Storage/SQLiteFullTextService.swift; OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift.

### Why it is in this position

It runs in parallel with dense retrieval and contributes the second ranked list to fusion.

## OI-0279. Lexical survivor guarantee

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Lexical survivor guarantee** means: A fusion safeguard that retains a sufficiently strong exact-word-only result even if dense possible result would otherwise crowd it out. The reason it exists is: Exact identifiers are often the answer and should not disappear because the meaning-based arm returns many broadly related passages.

### Layman’s explanation

A fusion safeguard that retains a sufficiently strong lexical-only result even if dense candidates would otherwise crowd it out. Exact identifiers are often the answer and should not disappear because the semantic arm returns many broadly related passages.

### Technical explanation

It is enforced during hybrid result assembly before reranking. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift.

### Why it is in this position

It is enforced during hybrid result assembly before reranking.

## OI-0280. Maximal marginal relevance (MMR)

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Maximal marginal relevance (MMR)** means: A greedy selection algorithm that balances relevance to the question against similarity to already selected results. The reason it exists is: Top-ranked small source pieces often repeat the same paragraph, wasting context and hiding complementary evidence.

### Layman’s explanation

A greedy selection algorithm that balances relevance to the query against similarity to already selected results. Top-ranked chunks often repeat the same paragraph, wasting context and hiding complementary evidence.

### Technical explanation

It runs after reranking and before context expansion or packing. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/RAGEngine.swift; OpenIntelligence/Services/RAG/Extraction/ExtractiveSummarizationService.swift.

### Why it is in this position

It runs after reranking and before context expansion or packing.

## OI-0281. Metadata boost

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Metadata boost** means: A post-search score adjustment based on structural and meaning-based labels and facts such as headings, entities, table status, numeric data, and exact identifiers. The reason it exists is: A raw search score cannot capture every evidence-quality signal available from ingestion.

### Layman’s explanation

A post-retrieval score adjustment based on structural and semantic metadata such as headings, entities, table status, numeric data, and exact identifiers. A raw retrieval score cannot capture every evidence-quality signal available from ingestion.

### Technical explanation

It is applied after fusion and before or around reranking and filtering. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift; OpenIntelligence/Services/RAG/Tuning/EvidenceScoringPolicyService.swift.

### Why it is in this position

It is applied after fusion and before or around reranking and filtering.

## OI-0282. Minimum similarity

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Minimum similarity** means: The score floor below which dense or fused possible result may be rejected. The reason it exists is: A floor limits irrelevant evidence, but one fixed value fails across domains and meaning map vocabularies.

### Layman’s explanation

The score floor below which dense or fused candidates may be rejected. A floor limits irrelevant evidence, but one fixed value fails across domains and embedding vocabularies.

### Technical explanation

It is calculated after candidate scoring and before final acceptance or expansion. Primary code anchors: OpenIntelligence/Core/Models/RAGQualityMode.swift; OpenIntelligence/Services/RAG/Tuning/RetrievalPolicyService.swift.

### Why it is in this position

It is calculated after candidate scoring and before final acceptance or expansion.

## OI-0283. MMR lambda

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **MMR lambda** means: The tradeoff parameter between question relevance and novelty, with lower values putting more emphasis on diversity. The reason it exists is: Different quality modes can choose whether to concentrate on the strongest passage or cover more independent evidence.

### Layman’s explanation

The tradeoff parameter between query relevance and novelty, with lower values putting more emphasis on diversity. Different quality modes can choose whether to concentrate on the strongest passage or cover more independent evidence.

### Technical explanation

It is supplied during MMR selection after reranking. Primary code anchors: OpenIntelligence/Core/Models/RAGQualityMode.swift; OpenIntelligence/Services/Infrastructure/Optimization/AdaptivePipelineOptimizer.swift.

### Why it is in this position

It is supplied during MMR selection after reranking.

## OI-0284. Multi-vector retrieval

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Multi-vector retrieval** means: Using several meaning-based probes for one user request rather than a single question meaning map. The reason it exists is: It increases recall across facets while preserving the original question as the answer objective.

### Layman’s explanation

Using several semantic probes for one user request rather than a single query embedding. It increases recall across facets while preserving the original question as the answer objective.

### Technical explanation

It combines supplementary vector searches before fusion/reranking and is recorded in audit feature flags. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/RAGService.swift.

### Why it is in this position

It combines supplementary vector searches before fusion/reranking and is recorded in audit feature flags.

## OI-0285. Neural start/end span model

**Status:** Dormant, meaning it is implemented or scaffolded, but not a functioning ordinary shipping path.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Neural start/end span model** means: The planned TinyBERT or DistilBERT extractive QA model with start and end token heads. The reason it exists is: A trained model could identify exact answer spans more robustly than heuristics.

### Layman’s explanation

The planned TinyBERT or DistilBERT extractive QA model with start and end token heads. A trained model could identify exact answer spans more robustly than heuristics.

### Technical explanation

Its protocol and template exist, but the current placeholder returns nil and falls back. Primary code anchors: OpenIntelligence/Services/RAG/Extraction/ExtractiveQAService.swift.

**Important caveat:** The model is explicitly marked STUB and must not be described as shipping.

### Why it is in this position

Its protocol and template exist, but the current placeholder returns nil and falls back.

## OI-0286. Pairwise similarity matrix

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Pairwise similarity matrix** means: The matrix of possible result-to-possible result cosine similarities used to accelerate diversity calculations. The reason it exists is: MMR repeatedly asks how similar possible result are to selected items, and precomputing the matrix avoids duplicate dot products.

### Layman’s explanation

The matrix of candidate-to-candidate cosine similarities used to accelerate diversity calculations. MMR repeatedly asks how similar candidates are to selected items, and precomputing the matrix avoids duplicate dot products.

### Technical explanation

It is built before or during MMR for sufficiently large batches. Primary code anchors: OpenIntelligence/Services/Infrastructure/Compute/BNNSGraphService.swift; OpenIntelligence/Services/Infrastructure/Compute/GPUComputeService.swift.

### Why it is in this position

It is built before or during MMR for sufficiently large batches.

## OI-0287. Parallel retrieval arms

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Parallel retrieval arms** means: Executing number coordinates and FTS search concurrently rather than serially. The reason it exists is: The arms are independent and latency should approximate the slower one rather than their sum.

### Layman’s explanation

Executing vector and FTS search concurrently rather than serially. The arms are independent and latency should approximate the slower one rather than their sum.

### Technical explanation

They launch together at the beginning of HybridSearchService and join before fusion. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift.

### Why it is in this position

They launch together at the beginning of HybridSearchService and join before fusion.

## OI-0288. Parent-document retrieval

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Parent-document retrieval** means: Restoring larger parent content around a precisely retrieved child small source piece. The reason it exists is: Small children rank well but may omit definitions, conditions, or headings needed for correct interpretation.

### Layman’s explanation

Restoring larger parent content around a precisely retrieved child chunk. Small children rank well but may omit definitions, conditions, or headings needed for correct interpretation.

### Technical explanation

It occurs after reranking/MMR and before final context packing. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/ParentDocumentService.swift.

### Why it is in this position

It occurs after reranking/MMR and before final context packing.

## OI-0289. Pattern-based specification extraction

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Pattern-based specification extraction** means: Regex and proximity-based discovery of grades, measurements, codes, dates, and similar values in unstructured retrieved text. The reason it exists is: Not every document produces a clean table, so exact-value answering needs a rule-based and repeatable fallback.

### Layman’s explanation

Regex and proximity-based discovery of grades, measurements, codes, dates, and similar values in unstructured retrieved text. Not every document produces a clean table, so exact-value answering needs a deterministic fallback.

### Technical explanation

It runs after structured lookups fail and before generative fallback. Primary code anchors: OpenIntelligence/Services/Query/Analysis/SpecificationExtractor.swift; OpenIntelligence/Services/Document/Analysis/SpecificationDetector.swift.

### Why it is in this position

It runs after structured lookups fail and before generative fallback.

## OI-0290. RAPTOR-lite summary routing

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **RAPTOR-lite summary routing** means: Routing overview questions to precomputed document-summary small source pieces at a higher summary level level. The reason it exists is: Whole-document questions are better answered by representative summaries than by one incidental detailed small source piece.

### Layman’s explanation

Routing overview questions to precomputed document-summary chunks at a higher abstraction level. Whole-document questions are better answered by representative summaries than by one incidental detailed chunk.

### Technical explanation

It is chosen by QueryRouterService before or alongside ordinary detail retrieval. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/RAPTORSummaryRouter.swift; OpenIntelligence/Services/Document/Analysis/DocumentSummaryService.swift.

### Why it is in this position

It is chosen by QueryRouterService before or alongside ordinary detail retrieval.

## OI-0291. Reciprocal rank fusion (RRF)

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Reciprocal rank fusion (RRF)** means: A rank-based merge that gives each item a score proportional to the sum of one over k plus its rank in each search list. The reason it exists is: Dense and BM25 scores live on different scales, while ranks are comparable without fragile score adjusted against a trust rule.

### Layman’s explanation

A rank-based merge that gives each item a score proportional to the sum of one over k plus its rank in each retrieval list. Dense and BM25 scores live on different scales, while ranks are comparable without fragile score calibration.

### Technical explanation

It merges the two candidate lists before cross-encoder reranking. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift; OpenIntelligence/Services/Infrastructure/Compute/BNNSGraphService.swift.

### Why it is in this position

It merges the two candidate lists before cross-encoder reranking.

## OI-0292. Redundancy penalty

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Redundancy penalty** means: The MMR subtraction based on the maximum similarity between a possible result and any already selected item. The reason it exists is: It directly penalizes near-duplicate evidence even when each duplicate is individually relevant.

### Layman’s explanation

The MMR subtraction based on the maximum similarity between a candidate and any already selected item. It directly penalizes near-duplicate evidence even when each duplicate is individually relevant.

### Technical explanation

It is recalculated on every greedy MMR selection step. Primary code anchors: OpenIntelligence/Services/RAG/Extraction/ExtractiveSummarizationService.swift; OpenIntelligence/Services/RAG/Orchestration/RAGEngine.swift.

### Why it is in this position

It is recalculated on every greedy MMR selection step.

## OI-0293. Rerank batch size

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Rerank batch size** means: The number of question-passage pairs scored in one reranker batch. The reason it exists is: Batch size controls throughput, memory pressure, and latency on different devices.

### Layman’s explanation

The number of query-passage pairs scored in one reranker batch. Batch size controls throughput, memory pressure, and latency on different devices.

### Technical explanation

It is resolved from mode and device policy before cross-encoder execution. Primary code anchors: OpenIntelligence/Services/Infrastructure/Optimization/AdaptivePipelineOptimizer.swift; OpenIntelligence/Services/Infrastructure/Monitoring/DeviceCapabilityService.swift.

### Why it is in this position

It is resolved from mode and device policy before cross-encoder execution.

## OI-0294. Rerank score

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Rerank score** means: The model-derived relevance value used to reorder fused possible result. The reason it exists is: It is a more precise local comparison than the first-stage dense or exact-word scores but is calculated over fewer items.

### Layman’s explanation

The model-derived relevance value used to reorder fused candidates. It is a more precise local comparison than the first-stage dense or lexical scores but is calculated over fewer items.

### Technical explanation

It is produced after fusion and incorporated into the final candidate score or rank. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/RAGEngine.swift.

### Why it is in this position

It is produced after fusion and incorporated into the final candidate score or rank.

## OI-0295. Reranker tokenizer

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Reranker tokenizer** means: The tokenizer paired specifically with the cross-encoder model. The reason it exists is: The reranker reads a combined question-passage sequence and cannot safely reuse an arbitrary meaning map tokenizer unless the model contract matches.

### Layman’s explanation

The tokenizer paired specifically with the cross-encoder model. The reranker reads a combined query-passage sequence and cannot safely reuse an arbitrary embedding tokenizer unless the model contract matches.

### Technical explanation

It tokenizes each pair immediately before reranker inference. Primary code anchors: OpenIntelligence/swift-transformers/Sources/TokenizersWrapper/Resources/reranker_tokenizer.bundle/tokenizer.json.

### Why it is in this position

It tokenizes each pair immediately before reranker inference.

## OI-0296. Retrieval cascade

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Retrieval cascade** means: A second broader search with more possible result and a stronger exact-word weighting when the first result set is weak or sparse. The reason it exists is: Weak initial search may reflect an overly meaning-based mix or too-small possible result set rather than absent evidence.

### Layman’s explanation

A second broader search with more candidates and a stronger lexical weighting when the first result set is weak or sparse. Weak initial retrieval may reflect an overly semantic mix or too-small candidate set rather than absent evidence.

### Technical explanation

It runs after first-stage metrics fail policy and before the pipeline gives up or generates. Primary code anchors: OpenIntelligence/Services/RAG/Tuning/RetrievalPolicyService.swift.

### Why it is in this position

It runs after first-stage metrics fail policy and before the pipeline gives up or generates.

## OI-0297. RRF constant k

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **RRF constant k** means: The smoothing constant, conventionally 60 in this implementation, that reduces the dominance of the first few rank positions. The reason it exists is: It controls how quickly rank contribution decays and makes fusion less brittle to small ordering changes.

### Layman’s explanation

The smoothing constant, conventionally 60 in this implementation, that reduces the dominance of the first few rank positions. It controls how quickly rank contribution decays and makes fusion less brittle to small ordering changes.

### Technical explanation

It is applied to every item while the dense and lexical lists are fused. Primary code anchors: OpenIntelligence/Services/Infrastructure/Compute/BNNSGraphService.swift.

### Why it is in this position

It is applied to every item while the dense and lexical lists are fused.

## OI-0298. Sentence-level relevance

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Sentence-level relevance** means: The cosine similarity between the question meaning map and each possible result sentence meaning map. The reason it exists is: A relevant small source piece may contain many irrelevant sentences, so sentence scoring can improve context density.

### Layman’s explanation

The cosine similarity between the query embedding and each candidate sentence embedding. A relevant chunk may contain many irrelevant sentences, so sentence scoring can improve context density.

### Technical explanation

It is calculated inside extractive summarization and contextual rescue. Primary code anchors: OpenIntelligence/Services/RAG/Extraction/ExtractiveSummarizationService.swift.

### Why it is in this position

It is calculated inside extractive summarization and contextual rescue.

## OI-0299. Sibling expansion

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Sibling expansion** means: Adding adjacent small source pieces from the same page, section, or sibling group around a strong hit. The reason it exists is: Procedures and arguments often span small source piece boundaries, so one hit should pull its immediate neighborhood.

### Layman’s explanation

Adding adjacent chunks from the same page, section, or sibling group around a strong hit. Procedures and arguments often span chunk boundaries, so one hit should pull its immediate neighborhood.

### Technical explanation

It occurs after candidate precision has been established and is capped by mode and token budget. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/ParentDocumentService.swift; OpenIntelligence/Core/Models/RAGQualityMode.swift.

### Why it is in this position

It occurs after candidate precision has been established and is capped by mode and token budget.

## OI-0300. Spec sniper

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Spec sniper** means: A precision scoring path for small source pieces that jointly match multiple question concepts and contain numeric, code, key-value, or table signals. The reason it exists is: It is designed to surface the exact specification row hidden inside a large technical document.

### Layman’s explanation

A precision scoring path for chunks that jointly match multiple query concepts and contain numeric, code, key-value, or table signals. It is designed to surface the exact specification row hidden inside a large technical document.

### Technical explanation

It supplements normal candidates before deterministic specification extraction. Primary code anchors: OpenIntelligence/Services/RAG/Tuning/EvidenceScoringPolicyService.swift.

### Why it is in this position

It supplements normal candidates before deterministic specification extraction.

## OI-0301. Specification boost

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Specification boost** means: An increased score for small source pieces containing relevant measurements, standards, codes, key-value structures, or numeric patterns. The reason it exists is: Exact technical questions need the passage with the value, not a conceptual explanation of the topic.

### Layman’s explanation

An increased score for chunks containing relevant measurements, standards, codes, key-value structures, or numeric patterns. Exact technical questions need the passage with the value, not a conceptual explanation of the topic.

### Technical explanation

It is applied after candidate generation for specification-heavy intents. Primary code anchors: OpenIntelligence/Services/RAG/Tuning/EvidenceScoringPolicyService.swift; OpenIntelligence/Core/Models/RAGQualityMode.swift.

### Why it is in this position

It is applied after candidate generation for specification-heavy intents.

## OI-0302. Stable tie-break

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Stable tie-break** means: A rule-based and repeatable secondary order used when possible result have equal or nearly equal scores. The reason it exists is: Nondeterministic ordering makes tests flaky, citations shift between runs, and benchmark comparisons noisy.

### Layman’s explanation

A deterministic secondary order used when candidates have equal or nearly equal scores. Nondeterministic ordering makes tests flaky, citations shift between runs, and benchmark comparisons noisy.

### Technical explanation

It is applied whenever candidate scores are sorted in retrieval or reranking. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift.

### Why it is in this position

It is applied whenever candidate scores are sorted in retrieval or reranking.

## OI-0303. State-anchor adjustment

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **State-anchor adjustment** means: A positive or negative score change depending on whether an indicator-state possible result contains the requested color and behavior anchors. The reason it exists is: A manual may list many lights and meanings; matching only indicator is insufficient.

### Layman’s explanation

A positive or negative score change depending on whether an indicator-state candidate contains the requested color and behavior anchors. A manual may list many lights and meanings; matching only indicator is insufficient.

### Technical explanation

It is applied before extraction and final ranking for state-lookup queries. Primary code anchors: OpenIntelligence/Services/RAG/Tuning/EvidenceScoringPolicyService.swift.

### Why it is in this position

It is applied before extraction and final ranking for state-lookup queries.

## OI-0304. Structured table lookup

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Structured table lookup** means: Directly matching question entities and requested labels against parsed table rows or key-value structures. The reason it exists is: A rule-based and repeatable cell lookup has lower hallucination risk than asking the model to infer the value from a flattened table.

### Layman’s explanation

Directly matching query entities and requested labels against parsed table rows or key-value structures. A deterministic cell lookup has lower hallucination risk than asking the model to infer the value from a flattened table.

### Technical explanation

It is attempted after relevant chunks are retrieved and before pattern-based extraction or generation. Primary code anchors: OpenIntelligence/Services/Query/Analysis/SpecificationExtractor.swift.

### Why it is in this position

It is attempted after relevant chunks are retrieved and before pattern-based extraction or generation.

## OI-0305. Supplementary vector search

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Supplementary vector search** means: Additional dense searches using rewritten, expanded, HyDE, or subquestion number coordinates, followed by deduplicated merge. The reason it exists is: One question number coordinates cannot represent every facet of a complex question.

### Layman’s explanation

Additional dense searches using rewritten, expanded, HyDE, or subquestion vectors, followed by deduplicated merge. One query vector cannot represent every facet of a complex question.

### Technical explanation

It occurs after enhancement and before the final candidate pool is reranked. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/RAGService.swift.

### Why it is in this position

It occurs after enhancement and before the final candidate pool is reranked.

## OI-0306. TinyBERT reranker

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **TinyBERT reranker** means: The shipped ms-marco-TinyBERT-L2-v2 Core ML cross-encoder used for reranking. The reason it exists is: A compact model makes joint question-passage scoring feasible on device for a limited shortlist.

### Layman’s explanation

The shipped ms-marco-TinyBERT-L2-v2 Core ML cross-encoder used for reranking. A compact model makes joint query-passage scoring feasible on device for a limited shortlist.

### Technical explanation

It runs after RRF fusion and before MMR. Primary code anchors: OpenIntelligence/Resources/MLModels/ReRankerModel.mlpackage; THIRD_PARTY_NOTICES.md.

### Why it is in this position

It runs after RRF fusion and before MMR.

## OI-0307. Top-k

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Top-k** means: The requested number of highest-ranked results retained at a stage. The reason it exists is: The pipeline needs bounded work and context, but different stages require different k values to trade recall against cost.

### Layman’s explanation

The requested number of highest-ranked results retained at a stage. The pipeline needs bounded work and context, but different stages require different k values to trade recall against cost.

### Technical explanation

It is applied during dense/lexical retrieval, after fusion, after reranking, and again during final packing. Primary code anchors: OpenIntelligence/Core/Models/RAGQuery.swift; OpenIntelligence/Core/Models/RAGQualityMode.swift.

### Why it is in this position

It is applied during dense/lexical retrieval, after fusion, after reranking, and again during final packing.

## OI-0308. Vocabulary mismatch

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a search teams, judges, and evidence scouts. **Vocabulary mismatch** means: A detected pattern where many possible result exist but all meaning-based scores are unusually low and compressed together. The reason it exists is: Specialized document collection language can make absolute meaning map thresholds misleading. Lowering the floor selectively can preserve recall.

### Layman’s explanation

A detected pattern where many candidates exist but all semantic scores are unusually low and compressed together. Specialized corpus language can make absolute embedding thresholds misleading. Lowering the floor selectively can preserve recall.

### Technical explanation

It is inferred from top and average scores during filtering policy. Primary code anchors: OpenIntelligence/Services/RAG/Tuning/RetrievalPolicyService.swift.

### Why it is in this position

It is inferred from top and average scores during filtering policy.

---

# 09. Context selection, compression, and token packing

**Section orientation:** Compression removes irrelevant content and context packing allocates the final prompt budget among core chunks, parents, neighbors, references, instructions, safety, and output.

## OI-0309. 4,096-token on-device limit

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a packing a limited suitcase. **4,096-token on-device limit** means: The governing on-device Apple Foundation Models context ceiling used by the engine. The reason it exists is: A naive top-20 small source piece set plus prompt and output schema can overflow, causing failure or lost evidence.

### Layman’s explanation

The governing on-device Apple Foundation Models context ceiling used by the engine. A naive top-20 chunk set plus prompt and output schema can overflow, causing failure or lost evidence.

### Technical explanation

It is used to derive available evidence tokens after all overhead and reserves are subtracted. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelTokenBudget.swift; Docs/HOW_IT_WORKS.md.

### Why it is in this position

It is used to derive available evidence tokens after all overhead and reserves are subtracted.

## OI-0310. Available context tokens

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a packing a limited suitcase. **Available context tokens** means: The remainder after all fixed prompt, question, tool, safety, and output costs are subtracted from the model limit. The reason it exists is: This is the actual capacity the search evidence is allowed to consume.

### Layman’s explanation

The remainder after all fixed prompt, question, tool, safety, and output costs are subtracted from the model limit. This is the actual capacity the retrieval evidence is allowed to consume.

### Technical explanation

It is the input constraint for ContextPackingService immediately before generation. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/ContextPackingService.swift; OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelTokenBudget.swift.

### Why it is in this position

It is the input constraint for ContextPackingService immediately before generation.

## OI-0311. Compression expansion guard

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a packing a limited suitcase. **Compression expansion guard** means: Rejecting a compression output when it contains more estimated tokens than the original. The reason it exists is: Expansion indicates the model paraphrased or hallucinated instead of extracting.

### Layman’s explanation

Rejecting a compression output when it contains more estimated tokens than the original. Expansion indicates the model paraphrased or hallucinated instead of extracting.

### Technical explanation

It is checked immediately after compression and before the result enters context packing. Primary code anchors: OpenIntelligence/Services/Query/Enhancement/ContextualCompressionService.swift.

### Why it is in this position

It is checked immediately after compression and before the result enters context packing.

## OI-0312. Compression passthrough

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a packing a limited suitcase. **Compression passthrough** means: Returning the original small source piece unchanged when it is short, the model is unavailable, compression fails, time expires, or the output is unsafe. The reason it exists is: Compression is an optimization and must not become a single point of evidence loss.

### Layman’s explanation

Returning the original chunk unchanged when it is short, the model is unavailable, compression fails, time expires, or the output is unsafe. Compression is an optimization and must not become a single point of evidence loss.

### Technical explanation

It is the fallback at every contextual-compression guard. Primary code anchors: OpenIntelligence/Services/Query/Enhancement/ContextualCompressionService.swift.

### Why it is in this position

It is the fallback at every contextual-compression guard.

## OI-0313. Compression ratio

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a packing a limited suitcase. **Compression ratio** means: The fraction of estimated tokens retained after contextual compression. The reason it exists is: It measures whether a compression call actually saved context rather than expanded or duplicated it.

### Layman’s explanation

The fraction of estimated tokens retained after contextual compression. It measures whether a compression call actually saved context rather than expanded or duplicated it.

### Technical explanation

It is calculated after each compression response and before accepting the compressed content. Primary code anchors: OpenIntelligence/Services/Query/Enhancement/ContextualCompressionService.swift.

### Why it is in this position

It is calculated after each compression response and before accepting the compressed content.

## OI-0314. Compression time budget

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a packing a limited suitcase. **Compression time budget** means: A total wall-clock cap for compressing a batch of small source pieces. The reason it exists is: Multiple model calls can dominate question latency and accumulate session context.

### Layman’s explanation

A total wall-clock cap for compressing a batch of chunks. Multiple model calls can dominate query latency and accumulate session context.

### Technical explanation

The batch stops when the budget is reached and passes remaining chunks through unchanged. Primary code anchors: OpenIntelligence/Services/Query/Enhancement/ContextualCompressionService.swift.

### Why it is in this position

The batch stops when the budget is reached and passes remaining chunks through unchanged.

## OI-0315. Context window

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a packing a limited suitcase. **Context window** means: The maximum token sequence the language model can consider in one session, including instructions, tools, evidence, conversation, and output framing. The reason it exists is: The document collection cannot fit, so every upstream search and packing decision exists to choose what occupies this scarce space.

### Layman’s explanation

The maximum token sequence the language model can consider in one session, including instructions, tools, evidence, conversation, and output framing. The corpus cannot fit, so every upstream retrieval and packing decision exists to choose what occupies this scarce space.

### Technical explanation

It constrains the entire query pipeline and is enforced immediately before model execution. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelTokenBudget.swift; OpenIntelligence/UI/Components/Glossary.swift.

### Why it is in this position

It constrains the entire query pipeline and is enforced immediately before model execution.

## OI-0316. ContextPackingService

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a packing a limited suitcase. **ContextPackingService** means: The rule-based and repeatable service that chooses and orders core hits, parents, siblings, graph neighbors, and compressed content under a token ceiling. The reason it exists is: search rank alone does not solve budget, diversity, sequence, or supporting-context requirements.

### Layman’s explanation

The deterministic service that chooses and orders core hits, parents, siblings, graph neighbors, and compressed content under a token ceiling. Retrieval rank alone does not solve budget, diversity, sequence, or supporting-context requirements.

### Technical explanation

It runs after retrieval/expansion and before prompt compilation. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/ContextPackingService.swift.

### Why it is in this position

It runs after retrieval/expansion and before prompt compilation.

## OI-0317. Contextual compression

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a packing a limited suitcase. **Contextual compression** means: Using Apple Foundation Models to extract only question-relevant sentences from retrieved small source pieces while attempting to preserve exact wording. The reason it exists is: small source pieces often contain both useful and irrelevant text, and the 4,096-token window rewards higher evidence density.

### Layman’s explanation

Using Apple Foundation Models to extract only query-relevant sentences from retrieved chunks while attempting to preserve exact wording. Chunks often contain both useful and irrelevant text, and the 4,096-token window rewards higher evidence density.

### Technical explanation

It runs after retrieval but before final packing, mainly in Deep Think under current mode policy. Primary code anchors: OpenIntelligence/Services/Query/Enhancement/ContextualCompressionService.swift; OpenIntelligence/Core/Models/RAGQualityMode.swift.

### Why it is in this position

It runs after retrieval but before final packing, mainly in Deep Think under current mode policy.

## OI-0318. Core evidence chunk

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a packing a limited suitcase. **Core evidence chunk** means: A high-ranked retrieved passage treated as an anchor that should survive packing if possible. The reason it exists is: The packer must preserve the strongest direct evidence before spending tokens on context around it.

### Layman’s explanation

A high-ranked retrieved passage treated as an anchor that should survive packing if possible. The packer must preserve the strongest direct evidence before spending tokens on context around it.

### Technical explanation

Core chunks are selected first, then parents, neighbors, and graph hops compete for remaining budget. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/ContextPackingService.swift.

### Why it is in this position

Core chunks are selected first, then parents, neighbors, and graph hops compete for remaining budget.

## OI-0319. Evidence packet

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a packing a limited suitcase. **Evidence packet** means: The final minimized collection of source passages, labels, identifiers, and labels and facts supplied to the answer stage. The reason it exists is: It is the boundary between search and generation and defines what the model is allowed to know for this answer.

### Layman’s explanation

The final minimized collection of source passages, labels, identifiers, and metadata supplied to the answer stage. It is the boundary between retrieval and generation and defines what the model is allowed to know for this answer.

### Technical explanation

It is produced by packing and consumed by prompt compilation and verification. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/ContextPackingService.swift; OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelPromptCompiler.swift.

### Why it is in this position

It is produced by packing and consumed by prompt compilation and verification.

## OI-0320. Fresh compression session

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a packing a limited suitcase. **Fresh compression session** means: Resetting the Foundation Models session between small source piece compression calls. The reason it exists is: Retaining the transcript across small source pieces accumulates tokens and can overflow the 4,096-token context after several calls.

### Layman’s explanation

Resetting the Foundation Models session between chunk compression calls. Retaining the transcript across chunks accumulates tokens and can overflow the 4,096-token context after several calls.

### Technical explanation

It occurs before each chunk in a compression batch. Primary code anchors: OpenIntelligence/Services/Query/Enhancement/ContextualCompressionService.swift.

### Why it is in this position

It occurs before each chunk in a compression batch.

## OI-0321. Graph-hop allocation

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a packing a limited suitcase. **Graph-hop allocation** means: Budget reserved for relationship-derived evidence reached through references or entities. The reason it exists is: Graph evidence can complete an answer but is usually less directly ranked than the anchor that led to it.

### Layman’s explanation

Budget reserved for relationship-derived evidence reached through references or entities. Graph evidence can complete an answer but is usually less directly ranked than the anchor that led to it.

### Technical explanation

It receives lower priority after core, parent, and local-neighbor context. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/ContextPackingService.swift.

### Why it is in this position

It receives lower priority after core, parent, and local-neighbor context.

## OI-0322. Information-density rescue

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a packing a limited suitcase. **Information-density rescue** means: Selecting source sentences with numbers, entities, colons, codes, or other high-value signals when compression returns no relevant content. The reason it exists is: Blindly taking the first characters can lose a specification located in the middle or end of the passage.

### Layman’s explanation

Selecting source sentences with numbers, entities, colons, codes, or other high-value signals when compression returns no relevant content. Blindly taking the first characters can lose a specification located in the middle or end of the passage.

### Technical explanation

It is the fallback inside CompressionResult.effectiveContent before final context assembly. Primary code anchors: OpenIntelligence/Services/Query/Enhancement/ContextualCompressionService.swift.

### Why it is in this position

It is the fallback inside CompressionResult.effectiveContent before final context assembly.

## OI-0323. Intent-specific packing

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a packing a limited suitcase. **Intent-specific packing** means: Changing evidence allocation and ordering based on whether the user requested a lookup, procedure, comparison, summary, or investigation. The reason it exists is: The same top-ranked small source pieces should not be packed identically for every answer shape.

### Layman’s explanation

Changing evidence allocation and ordering based on whether the user requested a lookup, procedure, comparison, summary, or investigation. The same top-ranked chunks should not be packed identically for every answer shape.

### Technical explanation

It is resolved inside ContextPackingService after answer intent is known. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/ContextPackingService.swift.

### Why it is in this position

It is resolved inside ContextPackingService after answer intent is known.

## OI-0324. Lost-in-the-Middle mitigation

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a packing a limited suitcase. **Lost-in-the-Middle mitigation** means: Ordering evidence so high-value passages are placed at context positions less likely to be ignored, commonly at the beginning and end rather than burying all strong evidence centrally. The reason it exists is: Language models can underuse information located in the middle of long prompts.

### Layman’s explanation

Ordering evidence so high-value passages are placed at context positions less likely to be ignored, commonly at the beginning and end rather than burying all strong evidence centrally. Language models can underuse information located in the middle of long prompts.

### Technical explanation

It is applied after the final evidence set is selected and before prompt assembly. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/ContextPackingService.swift; Benchmarks/ResearchFixtures/tiny_research_suite/fixtures/synthetic/lost_in_middle/answer_at_middle.md.

### Why it is in this position

It is applied after the final evidence set is selected and before prompt assembly.

## OI-0325. Neighbor allocation

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a packing a limited suitcase. **Neighbor allocation** means: Budget reserved for adjacent or sibling passages. The reason it exists is: Procedural order and local definitions often cross one small source piece boundary.

### Layman’s explanation

Budget reserved for adjacent or sibling passages. Procedural order and local definitions often cross one chunk boundary.

### Technical explanation

Neighbors are selected after parent context according to intent and remaining capacity. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/ContextPackingService.swift.

### Why it is in this position

Neighbors are selected after parent context according to intent and remaining capacity.

## OI-0326. NO_RELEVANT_CONTENT sentinel

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a packing a limited suitcase. **NO_RELEVANT_CONTENT sentinel** means: The exact compression response indicating that the model found no useful sentence in a small source piece. The reason it exists is: A sentinel is easier to distinguish from an empty or malformed response than free-form language.

### Layman’s explanation

The exact compression response indicating that the model found no useful sentence in a chunk. A sentinel is easier to distinguish from an empty or malformed response than free-form language.

### Technical explanation

It is interpreted after compression and triggers information-dense source rescue or passthrough. Primary code anchors: OpenIntelligence/Services/Query/Enhancement/ContextualCompressionService.swift.

### Why it is in this position

It is interpreted after compression and triggers information-dense source rescue or passthrough.

## OI-0327. Parent allocation

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a packing a limited suitcase. **Parent allocation** means: Budget reserved for larger source spans surrounding core small source pieces. The reason it exists is: A precise hit may be uninterpretable without its defining paragraph or table context.

### Layman’s explanation

Budget reserved for larger source spans surrounding core chunks. A precise hit may be uninterpretable without its defining paragraph or table context.

### Technical explanation

Parents are considered after core evidence and before lower-priority graph expansion. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/ContextPackingService.swift.

### Why it is in this position

Parents are considered after core evidence and before lower-priority graph expansion.

## OI-0328. Query-echo stripping

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a packing a limited suitcase. **Query-echo stripping** means: Removing an echoed user question from model-compressed text. The reason it exists is: An echoed question can fool later keyword scoring into treating an irrelevant passage as highly relevant.

### Layman’s explanation

Removing an echoed user question from model-compressed text. An echoed query can fool later keyword scoring into treating an irrelevant passage as highly relevant.

### Technical explanation

It is applied to compression output before ratio and relevance checks. Primary code anchors: OpenIntelligence/Services/Query/Enhancement/ContextualCompressionService.swift.

### Why it is in this position

It is applied to compression output before ratio and relevance checks.

## OI-0329. Question-token cost

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a packing a limited suitcase. **Question-token cost** means: The actual or estimated tokens occupied by the user question and effective rewritten form. The reason it exists is: A long multi-part question leaves less room for evidence and can trigger decomposition.

### Layman’s explanation

The actual or estimated tokens occupied by the user question and effective rewritten form. A long multi-part question leaves less room for evidence and can trigger decomposition.

### Technical explanation

It is measured before final context capacity is determined. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelTokenBudget.swift.

### Why it is in this position

It is measured before final context capacity is determined.

## OI-0330. Reserved output tokens

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a packing a limited suitcase. **Reserved output tokens** means: Capacity withheld from input so the model has room to produce the answer and structured fields. The reason it exists is: Packing evidence to the absolute context ceiling can leave no generation budget and cause truncation or failure.

### Layman’s explanation

Capacity withheld from input so the model has room to produce the answer and structured fields. Packing evidence to the absolute context ceiling can leave no generation budget and cause truncation or failure.

### Technical explanation

It is subtracted before evidence selection and passed into inference configuration. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelTokenBudget.swift.

### Why it is in this position

It is subtracted before evidence selection and passed into inference configuration.

## OI-0331. Safety-token reserve

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a packing a limited suitcase. **Safety-token reserve** means: Additional headroom for tokenizer-estimation error, framework wrappers, and variable structured-decoding overhead. The reason it exists is: A budget that is correct only on average is unsafe under a hard model limit.

### Layman’s explanation

Additional headroom for tokenizer-estimation error, framework wrappers, and variable structured-decoding overhead. A budget that is correct only on average is unsafe under a hard model limit.

### Technical explanation

It is removed before available context tokens are handed to the packer. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelTokenBudget.swift.

### Why it is in this position

It is removed before available context tokens are handed to the packer.

## OI-0332. Source sentence selection

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a packing a limited suitcase. **Source sentence selection** means: Choosing exact sentences from evidence to maximize question relevance and information density before generation. The reason it exists is: search can identify the right small source piece while the actual answer sentence remains buried among unrelated prose.

### Layman’s explanation

Choosing exact sentences from evidence to maximize query relevance and information density before generation. Retrieval can identify the right chunk while the actual answer sentence remains buried among unrelated prose.

### Technical explanation

It occurs during extractive summarization, contextual compression, source-only answering, and context rescue. Primary code anchors: OpenIntelligence/Services/RAG/Extraction/ExtractiveSummarizationService.swift; OpenIntelligence/Services/RAG/Safety/SourceOnlyAnswerService.swift.

### Why it is in this position

It occurs during extractive summarization, contextual compression, source-only answering, and context rescue.

## OI-0333. System-prompt overhead

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a packing a limited suitcase. **System-prompt overhead** means: Tokens consumed by behavioral instructions, grounding rules, output format, and answer policy. The reason it exists is: Those instructions are necessary but leave less room for source evidence, so they must be measured in the same budget.

### Layman’s explanation

Tokens consumed by behavioral instructions, grounding rules, output format, and answer policy. Those instructions are necessary but leave less room for source evidence, so they must be measured in the same budget.

### Technical explanation

They are counted before evidence capacity is calculated. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelTokenBudget.swift; OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelPromptCompiler.swift.

### Why it is in this position

They are counted before evidence capacity is calculated.

## OI-0334. Token budget

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a packing a limited suitcase. **Token budget** means: The explicit accounting of total context limit, instructions, tool schemas, question, conversation, evidence, safety margin, and reserved output. The reason it exists is: Character or small source piece counts are not enough because model capacity is consumed by tokens across every prompt component.

### Layman’s explanation

The explicit accounting of total context limit, instructions, tool schemas, question, conversation, evidence, safety margin, and reserved output. Character or chunk counts are not enough because model capacity is consumed by tokens across every prompt component.

### Technical explanation

It is computed before packing and rechecked before session invocation. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelTokenBudget.swift; OpenIntelligence/Services/RAG/Orchestration/QueryRuntimeCoordinator.swift.

### Why it is in this position

It is computed before packing and rechecked before session invocation.

## OI-0335. Tool-schema overhead

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a packing a limited suitcase. **Tool-schema overhead** means: Tokens used to describe registered Foundation Models tools and their arguments. The reason it exists is: Tool calling expands capability but directly competes with evidence for the context window.

### Layman’s explanation

Tokens used to describe registered Foundation Models tools and their arguments. Tool calling expands capability but directly competes with evidence for the context window.

### Technical explanation

It is included only when tools are attached to a session and is subtracted before packing. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelToolRegistry.swift; OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelTokenBudget.swift.

### Why it is in this position

It is included only when tools are attached to a session and is subtracted before packing.

---

# 10. Model execution, routing, tools, and generation

**Section orientation:** The execution layer chooses deterministic, on-device, cloud-eligible, or abstention paths. It builds sessions, compiles prompts, optionally exposes tools, streams generation, and records execution receipts.

## OI-0336. @Generable

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **@Generable** means: The Foundation Models annotation defining a type the framework can produce through constrained decoding. The reason it exists is: It enforces field presence and types at generation time rather than repairing malformed free-form output afterward.

### Layman’s explanation

The Foundation Models annotation defining a type the framework can produce through constrained decoding. It enforces field presence and types at generation time rather than repairing malformed free-form output afterward.

### Technical explanation

It decorates RAG answer, claim, summary, comparison, and reasoning-chain structures consumed by the model. Primary code anchors: OpenIntelligence/Core/Models/RAGStructuredResponse.swift.

### Why it is in this position

It decorates RAG answer, claim, summary, comparison, and reasoning-chain structures consumed by the model.

## OI-0337. @Guide

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **@Guide** means: A field-level natural-language constraint attached to a generable property. The reason it exists is: The type says what data shape is required, while the guide says what meaning-based content belongs in the field.

### Layman’s explanation

A field-level natural-language constraint attached to a generable property. The type says what data shape is required, while the guide says what semantic content belongs in the field.

### Technical explanation

It is read by constrained generation before each structured field is decoded. Primary code anchors: OpenIntelligence/Core/Models/RAGStructuredResponse.swift.

### Why it is in this position

It is read by constrained generation before each structured field is decoded.

## OI-0338. Abstain execution target

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Abstain execution target** means: A plan target that intentionally returns no unsupported answer. The reason it exists is: No available model should be allowed to convert absent or contradictory evidence into fluent certainty.

### Layman’s explanation

A plan target that intentionally returns no unsupported answer. No available model should be allowed to convert absent or contradictory evidence into fluent certainty.

### Technical explanation

It is selected when evidence or authorization policy fails before model execution. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/ModelExecutionPlan.swift.

### Why it is in this position

It is selected when evidence or authorization policy fails before model execution.

## OI-0339. Active model

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Active model** means: The model or analysis path that is actually executing or most recently completed. The reason it exists is: Fallback, framework availability, or route policy may make it differ from the selected label.

### Layman’s explanation

The model or analysis path that is actually executing or most recently completed. Fallback, framework availability, or route policy may make it differ from the selected label.

### Technical explanation

It is resolved during execution and recorded in response metadata and model-resolution state. Primary code anchors: OpenIntelligence/Services/LLM/ModelResolutionService.swift; OpenIntelligence/Services/RAG/Orchestration/RAGService.swift.

### Why it is in this position

It is resolved during execution and recorded in response metadata and model-resolution state.

## OI-0340. AdapterManager

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **AdapterManager** means: The compatibility layer coordinating available LLM service adapters. The reason it exists is: It decouples the RAG engine from one backend implementation and contains legacy transitions.

### Layman’s explanation

The compatibility layer coordinating available LLM service adapters. It decouples the RAG engine from one backend implementation and contains legacy transitions.

### Technical explanation

It resolves an LLMService before query execution. Primary code anchors: OpenIntelligence/Services/LLM/AdapterManager.swift.

### Why it is in this position

It resolves an LLMService before query execution.

## OI-0341. advanced20B preference alias

**Status:** Historical, meaning it is superseded, removed, or misleading if described as current.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **advanced20B preference alias** means: A compatibility value that currently resolves to the on-device route rather than a selectable twenty-billion-parameter tier. The reason it exists is: It preserves stored preferences while avoiding false model identity claims.

### Layman’s explanation

A compatibility value that currently resolves to the on-device route rather than a selectable twenty-billion-parameter tier. It preserves stored preferences while avoiding false model identity claims.

### Technical explanation

It is canonicalized before routing. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelRoutePolicy.swift.

**Important caveat:** Apple may use larger internal models, but OpenIntelligence cannot choose or attest one by this label.

### Why it is in this position

It is canonicalized before routing.

## OI-0342. Apple Foundation Models

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Apple Foundation Models** means: Apple's on-device model-written model framework used for local answer generation, constrained structures, tools, and auxiliary model tasks. The reason it exists is: It supplies a private, system-managed language model without bundling a large model-written model inside the app.

### Layman’s explanation

Apple's on-device generative model framework used for local answer generation, constrained structures, tools, and auxiliary model tasks. It supplies a private, system-managed language model without bundling a large generative model inside the app.

### Technical explanation

It is invoked only after the engine has assembled a bounded evidence packet. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelSessionFactory.swift; OpenIntelligence/Services/LLM/LLMService.swift.

### Why it is in this position

It is invoked only after the engine has assembled a bounded evidence packet.

## OI-0343. Atomic claim

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Atomic claim** means: One independently verifiable assertion in the answer rather than a paragraph containing several facts. The reason it exists is: Verification and evidence mapping are more reliable when each claim can be supported or rejected separately.

### Layman’s explanation

One independently verifiable assertion in the answer rather than a paragraph containing several facts. Verification and evidence mapping are more reliable when each claim can be supported or rejected separately.

### Technical explanation

Claims are generated or extracted before Gate B and response sanitization. Primary code anchors: OpenIntelligence/Core/Models/RAGStructuredResponse.swift; OpenIntelligence/Core/Models/StructuredAnswer.swift.

### Why it is in this position

Claims are generated or extracted before Gate B and response sanitization.

## OI-0344. Citation namespace

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Citation namespace** means: The one-to-one mapping among prompt source labels, model citations, retrieved small source pieces, response chips, and source views. The reason it exists is: A cited answer is unsafe if S3 in the text can refer to a different source than chip 3 below it.

### Layman’s explanation

The one-to-one mapping among prompt source labels, model citations, retrieved chunks, response chips, and source views. A cited answer is unsafe if S3 in the text can refer to a different source than chip 3 below it.

### Technical explanation

It is created before generation and validated while the structured response is built. Primary code anchors: OpenIntelligence/Core/Models/StructuredAnswer.swift; OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift.

### Why it is in this position

It is created before generation and validated while the structured response is built.

## OI-0345. Cloud consent

**Status:** Dormant, meaning it is implemented or scaffolded, but not a functioning ordinary shipping path.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Cloud consent** means: The user decision allow once, allow and remember, or deny for a specific provider and minimized payload. The reason it exists is: Even privacy-preserving cloud compute should not receive document evidence without an explicit user policy.

### Layman’s explanation

The user decision allow once, allow and remember, or deny for a specific provider and minimized payload. Even privacy-preserving cloud compute should not receive document evidence without an explicit user policy.

### Technical explanation

It is requested after the exact payload is known and before a cloud attempt. Primary code anchors: OpenIntelligence/Core/Models/CloudTransmission.swift; OpenIntelligence/UI/Components/CloudConsentPromptView.swift.

### Why it is in this position

It is requested after the exact payload is known and before a cloud attempt.

## OI-0346. Cloud transmission record

**Status:** Dormant, meaning it is implemented or scaffolded, but not a functioning ordinary shipping path.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Cloud transmission record** means: The audit record of provider, model, prompt preview, character counts, small source piece count, content hashes, estimated bytes, plan ID, and route reason. The reason it exists is: A cloud badge alone cannot show what left the device or why.

### Layman’s explanation

The audit record of provider, model, prompt preview, character counts, chunk count, content hashes, estimated bytes, plan ID, and route reason. A cloud badge alone cannot show what left the device or why.

### Technical explanation

It would be recorded immediately before a cloud transmission and linked to the execution plan. Primary code anchors: OpenIntelligence/Core/Models/CloudTransmission.swift.

### Why it is in this position

It would be recorded immediately before a cloud transmission and linked to the execution plan.

## OI-0347. Constrained decoding

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Constrained decoding** means: Model decoding restricted to a declared output schema. The reason it exists is: It eliminates a class of parsing failures and lets downstream verification operate over explicit claims and citations.

### Layman’s explanation

Model decoding restricted to a declared output schema. It eliminates a class of parsing failures and lets downstream verification operate over explicit claims and citations.

### Technical explanation

It is the output mechanism inside FoundationModelStructuredGenerator. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelStructuredGenerator.swift.

### Why it is in this position

It is the output mechanism inside FoundationModelStructuredGenerator.

## OI-0348. core3B preference alias

**Status:** Historical, meaning it is superseded, removed, or misleading if described as current.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **core3B preference alias** means: A compatibility value that now means on-device execution, not selection of an observable three-billion-parameter model. The reason it exists is: Older settings and UI values must continue to resolve without claiming an API capability Apple does not expose.

### Layman’s explanation

A compatibility value that now means on-device execution, not selection of an observable three-billion-parameter model. Older settings and UI values must continue to resolve without claiming an API capability Apple does not expose.

### Technical explanation

It is canonicalized during route resolution. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelRoutePolicy.swift.

**Important caveat:** The app cannot select or verify an exact on-device parameter count through the public Foundation Models API.

### Why it is in this position

It is canonicalized during route resolution.

## OI-0349. Deterministic execution target

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Deterministic execution target** means: A plan target that returns an extractive or otherwise code-produced answer without model-written synthesis. The reason it exists is: When source structure already yields the answer, generation adds risk and latency without value.

### Layman’s explanation

A plan target that returns an extractive or otherwise code-produced answer without generative synthesis. When source structure already yields the answer, generation adds risk and latency without value.

### Technical explanation

It is selected after high-confidence extraction and skips the language-model call. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/ModelExecutionPlan.swift; OpenIntelligence/Services/Query/Analysis/GroundedAnswerPolicy.swift.

### Why it is in this position

It is selected after high-confidence extraction and skips the language-model call.

## OI-0350. DirectRAGAnswer

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **DirectRAGAnswer** means: A smaller structured answer shape without the explicit reasoning field. The reason it exists is: Exact or constrained paths may need less output overhead and less hidden analysis text.

### Layman’s explanation

A smaller structured answer shape without the explicit reasoning field. Exact or constrained paths may need less output overhead and less hidden analysis text.

### Technical explanation

It is selected by structured generation policy for direct-answer cases. Primary code anchors: OpenIntelligence/Core/Models/RAGStructuredResponse.swift.

### Why it is in this position

It is selected by structured generation policy for direct-answer cases.

## OI-0351. Evidence source label

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Evidence source label** means: A compact identifier such as S1, S2, or an evidence ID attached to each excerpt in the prompt. The reason it exists is: The model needs an unambiguous namespace it can cite, and downstream code needs to map that label back to the exact small source piece.

### Layman’s explanation

A compact identifier such as S1, S2, or an evidence ID attached to each excerpt in the prompt. The model needs an unambiguous namespace it can cite, and downstream code needs to map that label back to the exact chunk.

### Technical explanation

Labels are assigned during prompt assembly and preserved through structured output and citation rendering. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelPromptCompiler.swift; OpenIntelligence/Core/Models/StructuredAnswer.swift.

### Why it is in this position

Labels are assigned during prompt assembly and preserved through structured output and citation rendering.

## OI-0352. Execution attempt

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Execution attempt** means: One timed try against a target with a result such as succeeded, partial, failed, or skipped. The reason it exists is: A receipt needs the full chain to explain fallback and attest the completed route.

### Layman’s explanation

One timed try against a target with a result such as succeeded, partial, failed, or skipped. A receipt needs the full chain to explain fallback and attest the completed route.

### Technical explanation

Attempts are appended as routing and model calls occur. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/ModelExecutionReceipt.swift.

### Why it is in this position

Attempts are appended as routing and model calls occur.

## OI-0353. Execution context

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Execution context** means: The user/runtime policy automatic, on-device only, prefer cloud, or cloud only. The reason it exists is: It defines a privacy and routing constraint independent of answer quality mode.

### Layman’s explanation

The user/runtime policy automatic, on-device only, prefer cloud, or cloud only. It defines a privacy and routing constraint independent of answer quality mode.

### Technical explanation

It is resolved before planning and enforced again when the post-retrieval model plan is created. Primary code anchors: OpenIntelligence/SDK/OpenIntelligenceEngine.swift; OpenIntelligence/Services/RAG/Orchestration/QueryRuntimeCoordinator.swift.

### Why it is in this position

It is resolved before planning and enforced again when the post-retrieval model plan is created.

## OI-0354. Execution fallback

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Execution fallback** means: The approved alternative target used when the intended target cannot complete. The reason it exists is: A fallback must preserve user privacy policy and be explicit in telemetry.

### Layman’s explanation

The approved alternative target used when the intended target cannot complete. A fallback must preserve user privacy policy and be explicit in telemetry.

### Technical explanation

It is encoded in ModelExecutionPlan and realized through an attempt chain. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/ModelExecutionPlan.swift.

### Why it is in this position

It is encoded in ModelExecutionPlan and realized through an attempt chain.

## OI-0355. Fail-closed routing

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Fail-closed routing** means: The rule that denied, unknown, unsupported, unavailable, or exhausted cloud conditions choose a permitted local fallback or abstention rather than optimistically transmit. The reason it exists is: Privacy and authorization uncertainty must never be interpreted as permission.

### Layman’s explanation

The rule that denied, unknown, unsupported, unavailable, or exhausted cloud conditions choose a permitted local fallback or abstention rather than optimistically transmit. Privacy and authorization uncertainty must never be interpreted as permission.

### Technical explanation

It is enforced in planning, consent, quota checks, and receipt invariants. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/ModelExecutionPlanner.swift; OpenIntelligence/Services/Evaluation/RouteEvalMetrics.swift.

### Why it is in this position

It is enforced in planning, consent, quota checks, and receipt invariants.

## OI-0356. Foundation Model preference

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Foundation Model preference** means: The preference automatic, on-device aliases, or Private Cloud Compute used by model-route policy. The reason it exists is: It captures a user route choice while retaining compatibility with historical model labels.

### Layman’s explanation

The preference automatic, on-device aliases, or Private Cloud Compute used by model-route policy. It captures a user route choice while retaining compatibility with historical model labels.

### Technical explanation

It is stored in InferenceConfig and interpreted before session construction. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelRoutePolicy.swift; OpenIntelligence/Services/RAG/Orchestration/RAGService.swift.

### Why it is in this position

It is stored in InferenceConfig and interpreted before session construction.

## OI-0357. Foundation Model tool

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Foundation Model tool** means: A typed callable operation exposed to the language model during a session. The reason it exists is: Tools let the model request rule-based and repeatable search or document operations instead of fabricating results.

### Layman’s explanation

A typed callable operation exposed to the language model during a session. Tools let the model request deterministic retrieval or document operations instead of fabricating results.

### Technical explanation

A tool schema is attached at session creation and can be invoked during generation. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelToolRegistry.swift.

### Why it is in this position

A tool schema is attached at session creation and can be invoked during generation.

## OI-0358. FoundationModelSessionFactory

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **FoundationModelSessionFactory** means: The central creator of Apple Foundation Models sessions for answer generation and auxiliary use cases. The reason it exists is: Central construction keeps instructions, tools, use-case policy, routing, and transcript behavior consistent.

### Layman’s explanation

The central creator of Apple Foundation Models sessions for answer generation and auxiliary use cases. Central construction keeps instructions, tools, use-case policy, routing, and transcript behavior consistent.

### Technical explanation

It is called by LLMService or auxiliary services immediately before model execution. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelSessionFactory.swift.

### Why it is in this position

It is called by LLMService or auxiliary services immediately before model execution.

## OI-0359. FoundationModelToolRegistry

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **FoundationModelToolRegistry** means: The central registry of the app's approved Foundation Models tools and their schemas. The reason it exists is: An allowlisted registry controls capability, prompt overhead, and auditability.

### Layman’s explanation

The central registry of the app's approved Foundation Models tools and their schemas. An allowlisted registry controls capability, prompt overhead, and auditability.

### Technical explanation

It is consulted by the session factory before attaching tools. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelToolRegistry.swift.

### Why it is in this position

It is consulted by the session factory before attaching tools.

## OI-0360. InferenceConfig

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **InferenceConfig** means: The per-question bundle of generation parameters, Foundation Model preference, execution context, cloud permission, quality mode, prompts, and attached execution plan. The reason it exists is: All model calls in a question, including agentic synthesis, need one consistent expression of user and policy intent.

### Layman’s explanation

The per-query bundle of generation parameters, Foundation Model preference, execution context, cloud permission, quality mode, prompts, and attached execution plan. All model calls in a query, including agentic synthesis, need one consistent expression of user and policy intent.

### Technical explanation

It is resolved before execution and passed through session and generation layers. Primary code anchors: OpenIntelligence/Services/LLM/LLMService.swift; OpenIntelligence/Services/RAG/Orchestration/QueryRuntimeCoordinator.swift.

### Why it is in this position

It is resolved before execution and passed through session and generation layers.

## OI-0361. LanguageModelSession

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **LanguageModelSession** means: A Foundation Models conversation/model answering session that carries instructions, tools, transcript state, and generation calls. The reason it exists is: A session is the framework boundary for model interaction and may accumulate context across calls.

### Layman’s explanation

A Foundation Models conversation/inference session that carries instructions, tools, transcript state, and generation calls. A session is the framework boundary for model interaction and may accumulate context across calls.

### Technical explanation

It is created after route and budget resolution and disposed or reset according to the task. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelSessionFactory.swift.

### Why it is in this position

It is created after route and budget resolution and disposed or reset according to the task.

## OI-0362. LLMService

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **LLMService** means: The service that compiles requests, selects or invokes the active language-model backend, streams text, requests structured output, and records generation metrics. The reason it exists is: search should not know framework-specific session details, and UI should not directly own model state.

### Layman’s explanation

The service that compiles requests, selects or invokes the active language-model backend, streams text, requests structured output, and records generation metrics. Retrieval should not know framework-specific session details, and UI should not directly own model state.

### Technical explanation

It receives the packed evidence and inference configuration after retrieval and returns generated or structured content before verification. Primary code anchors: OpenIntelligence/Services/LLM/LLMService.swift.

### Why it is in this position

It receives the packed evidence and inference configuration after retrieval and returns generated or structured content before verification.

## OI-0363. Local OpenAI-compatible server backend

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Local OpenAI-compatible server backend** means: A developer or alternative backend that calls a user-specified local OpenAI-compatible server rather than Apple Foundation Models. The reason it exists is: It can support testing or external local model answering without changing the RAG search contract.

### Layman’s explanation

A developer or alternative backend that calls a user-specified local OpenAI-compatible server rather than Apple Foundation Models. It can support testing or external local inference without changing the RAG retrieval contract.

### Technical explanation

It is selected only when configured and receives the same packed prompt through its adapter. Primary code anchors: OpenIntelligence/Services/LLM/LocalOpenAIServerLLMService.swift.

**Important caveat:** It is not the default App Store answer path and may move data off-device if the configured server is remote.

### Why it is in this position

It is selected only when configured and receives the same packed prompt through its adapter.

## OI-0364. Matched terms

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Matched terms** means: The question concepts the model reports finding in the supplied sources. The reason it exists is: They provide an additional diagnostic signal about whether generation used the intended evidence.

### Layman’s explanation

The query concepts the model reports finding in the supplied sources. They provide an additional diagnostic signal about whether generation used the intended evidence.

### Technical explanation

They are produced with structured generation and may appear in diagnostics rather than determine truth by themselves. Primary code anchors: OpenIntelligence/Core/Models/RAGStructuredResponse.swift.

### Why it is in this position

They are produced with structured generation and may appear in diagnostics rather than determine truth by themselves.

## OI-0365. Maximum generation tokens

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Maximum generation tokens** means: The cap on how many output tokens a model call may produce. The reason it exists is: It bounds latency and prevents output from consuming capacity needed by later chained calls or UI.

### Layman’s explanation

The cap on how many output tokens a model call may produce. It bounds latency and prevents output from consuming capacity needed by later chained calls or UI.

### Technical explanation

It is reserved during budgeting and passed into generation options. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelTokenBudget.swift; OpenIntelligence/Services/LLM/LLMService.swift.

### Why it is in this position

It is reserved during budgeting and passed into generation options.

## OI-0366. Minimized cloud payload

**Status:** Dormant, meaning it is implemented or scaffolded, but not a functioning ordinary shipping path.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Minimized cloud payload** means: Only the selected evidence and prompt material required for the question, rather than the whole library. The reason it exists is: Late routing and data minimization reduce exposure and make consent concrete.

### Layman’s explanation

Only the selected evidence and prompt material required for the question, rather than the whole library. Late routing and data minimization reduce exposure and make consent concrete.

### Technical explanation

It is produced by local retrieval/packing before any potential transmission. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/ModelExecutionPlanner.swift; OpenIntelligence/Core/Models/CloudTransmission.swift.

### Why it is in this position

It is produced by local retrieval/packing before any potential transmission.

## OI-0367. Model availability state

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Model availability state** means: The resolved condition available, simulator unsupported, unsupported device, Apple Intelligence disabled, model preparing, or another unavailable reason. The reason it exists is: Model execution must fail explicitly and intelligibly rather than enter a path that cannot produce output.

### Layman’s explanation

The resolved condition available, simulator unsupported, unsupported device, Apple Intelligence disabled, model preparing, or another unavailable reason. Model execution must fail explicitly and intelligibly rather than enter a path that cannot produce output.

### Technical explanation

It is checked at SDK/query entry before any expensive retrieval or session work is committed. Primary code anchors: OpenIntelligence/SDK/OpenIntelligenceEngine.swift.

### Why it is in this position

It is checked at SDK/query entry before any expensive retrieval or session work is committed.

## OI-0368. ModelExecutionPlan

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **ModelExecutionPlan** means: The immutable post-search plan naming the intended synthesis target, reason, token estimates, fallback target, and policy version. The reason it exists is: Routing should be a checkable decision based on the exact minimized evidence payload, not a vague pre-question preference.

### Layman’s explanation

The immutable post-retrieval plan naming the intended synthesis target, reason, token estimates, fallback target, and policy version. Routing should be a checkable decision based on the exact minimized evidence payload, not a vague pre-query preference.

### Technical explanation

It is created after retrieval and packing but before consent and session execution. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/ModelExecutionPlan.swift; OpenIntelligence/Services/RAG/Orchestration/ModelExecutionPlanner.swift.

### Why it is in this position

It is created after retrieval and packing but before consent and session execution.

## OI-0369. ModelExecutionReceipt

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **ModelExecutionReceipt** means: The immutable record of intended, actual, and completed targets, attempts, quota, fallback reason, policy, and timing for one answer. The reason it exists is: It proves how the answer was produced and prevents UI route claims from being inferred from settings.

### Layman’s explanation

The immutable record of intended, actual, and completed targets, attempts, quota, fallback reason, policy, and timing for one answer. It proves how the answer was produced and prevents UI route claims from being inferred from settings.

### Technical explanation

It is built across execution and attached to response metadata after completion. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/ModelExecutionReceipt.swift.

### Why it is in this position

It is built across execution and attached to response metadata after completion.

## OI-0370. ModelResolutionService

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **ModelResolutionService** means: The observable single source of truth for what the user selected, what is actually active, the execution path, fallback reason, status, parameters, and history. The reason it exists is: A model picker label is not proof of the model or route that completed a question.

### Layman’s explanation

The observable single source of truth for what the user selected, what is actually active, the execution path, fallback reason, status, parameters, and history. A model picker label is not proof of the model or route that completed a query.

### Technical explanation

It observes settings and RAGService and updates the UI around query execution. Primary code anchors: OpenIntelligence/Services/LLM/ModelResolutionService.swift.

### Why it is in this position

It observes settings and RAGService and updates the UI around query execution.

## OI-0371. On-device execution target

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **On-device execution target** means: A plan target that invokes the local SystemLanguageModel. The reason it exists is: It preserves the local-first guarantee and is the only model-written target in shipping App Store builds.

### Layman’s explanation

A plan target that invokes the local SystemLanguageModel. It preserves the local-first guarantee and is the only generative target in shipping App Store builds.

### Technical explanation

It is selected post-retrieval when generation is needed and the local evidence packet fits. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/ModelExecutionPlanner.swift; OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelRoutePolicy.swift.

### Why it is in this position

It is selected post-retrieval when generation is needed and the local evidence packet fits.

## OI-0372. Partial stream completion

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Partial stream completion** means: A route outcome in which meaningful output was delivered before the stream failed or ended prematurely. The reason it exists is: Discarding all partial text can be worse than preserving an explicitly marked incomplete answer.

### Layman’s explanation

A route outcome in which meaningful output was delivered before the stream failed or ended prematurely. Discarding all partial text can be worse than preserving an explicitly marked incomplete answer.

### Technical explanation

It is recorded as an attesting attempt result and handled during receipt and UI finalization. Primary code anchors: OpenIntelligence/Services/Evaluation/RouteEvalMetrics.swift; OpenIntelligence/Services/RAG/Orchestration/ModelExecutionReceipt.swift.

### Why it is in this position

It is recorded as an attesting attempt result and handled during receipt and UI finalization.

## OI-0373. PCC quota state

**Status:** Dormant, meaning it is implemented or scaffolded, but not a functioning ordinary shipping path.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **PCC quota state** means: The framework-reported or put into a consistent form condition available, limit reached, unsupported, or unknown. The reason it exists is: Cloud execution must not be attempted when authorization or capacity is uncertain.

### Layman’s explanation

The framework-reported or normalized condition available, limit reached, unsupported, or unknown. Cloud execution must not be attempted when authorization or capacity is uncertain.

### Technical explanation

It is sampled at planning and recorded in the model execution receipt. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/ModelExecutionReceipt.swift; OpenIntelligence/Services/Evaluation/RouteEvalMetrics.swift.

### Why it is in this position

It is sampled at planning and recorded in the model execution receipt.

## OI-0374. PCC reasoning level

**Status:** Dormant, meaning it is implemented or scaffolded, but not a functioning ordinary shipping path.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **PCC reasoning level** means: The none, moderate, or deep reasoning request associated with a Private Cloud Compute route. The reason it exists is: Cloud execution could allocate more reasoning effort according to question mode.

### Layman’s explanation

The none, moderate, or deep reasoning request associated with a Private Cloud Compute route. Cloud execution could allocate more reasoning effort according to query mode.

### Technical explanation

It is attached only when a PCC route is actually available and selected. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelRoute.swift.

### Why it is in this position

It is attached only when a PCC route is actually available and selected.

## OI-0375. PCC suppression cooldown

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **PCC suppression cooldown** means: A temporary period after route failure during which the engine avoids retrying PCC and forces local execution. The reason it exists is: Repeatedly attempting an unavailable route wastes latency and can create loops.

### Layman’s explanation

A temporary period after route failure during which the engine avoids retrying PCC and forces local execution. Repeatedly attempting an unavailable route wastes latency and can create loops.

### Technical explanation

It is checked at QueryRuntimeCoordinator before model planning. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/RAGService.swift; OpenIntelligence/Services/RAG/Orchestration/QueryRuntimeCoordinator.swift.

### Why it is in this position

It is checked at QueryRuntimeCoordinator before model planning.

## OI-0376. Policy version

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Policy version** means: A version identifier attached to route plans and receipts. The reason it exists is: Routing logic evolves, and historical results need to be interpreted under the policy that produced them.

### Layman’s explanation

A version identifier attached to route plans and receipts. Routing logic evolves, and historical results need to be interpreted under the policy that produced them.

### Technical explanation

It is set at planning and persisted with execution evidence. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/ModelExecutionPlan.swift.

### Why it is in this position

It is set at planning and persisted with execution evidence.

## OI-0377. Post-retrieval routing

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Post-retrieval routing** means: Choosing rule-based and repeatable, on-device, say there is not enough evidence, or potential cloud synthesis only after evidence size and quality are known. The reason it exists is: Before search, the engine does not know whether the answer fits locally or what exact content would leave the device.

### Layman’s explanation

Choosing deterministic, on-device, abstain, or potential cloud synthesis only after evidence size and quality are known. Before retrieval, the engine does not know whether the answer fits locally or what exact content would leave the device.

### Technical explanation

It follows evidence packing and precedes consent and model invocation. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/ModelExecutionPlanner.swift; OpenIntelligence/Services/RAG/Orchestration/QueryRuntimeCoordinator.swift.

### Why it is in this position

It follows evidence packing and precedes consent and model invocation.

## OI-0378. Private Cloud Compute target

**Status:** Dormant, meaning it is implemented or scaffolded, but not a functioning ordinary shipping path.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Private Cloud Compute target** means: The source-level route for Apple Private Cloud Compute on compatible compiler, OS, entitlement, availability, quota, foreground, network, and consent conditions. The reason it exists is: It is designed to handle evidence packets that exceed the on-device route while preserving Apple's privacy architecture.

### Layman’s explanation

The source-level route for Apple Private Cloud Compute on compatible compiler, OS, entitlement, availability, quota, foreground, network, and consent conditions. It is designed to handle evidence packets that exceed the on-device route while preserving Apple's privacy architecture.

### Technical explanation

It would be selected after retrieval and consent, but it is compiled out of every current App Store build. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelRoutePolicy.swift; Docs/SHIPPED_CAPABILITIES.json.

**Important caveat:** Treat PCC as architecture-in-waiting, not a current production stage.

### Why it is in this position

It would be selected after retrieval and consent, but it is compiled out of every current App Store build.

## OI-0379. Prompt compiler

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Prompt compiler** means: The component that turns question intent, evidence excerpts, source labels, grounding rules, answer format, and route constraints into model instructions and prompt content. The reason it exists is: Prompt text is an executable interface to the model and must stay synchronized with citation and verification expectations.

### Layman’s explanation

The component that turns query intent, evidence excerpts, source labels, grounding rules, answer format, and route constraints into model instructions and prompt content. Prompt text is an executable interface to the model and must stay synchronized with citation and verification expectations.

### Technical explanation

It runs after context packing and immediately before the session request. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelPromptCompiler.swift.

### Why it is in this position

It runs after context packing and immediately before the session request.

## OI-0380. RAGAnswer

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **RAGAnswer** means: The structured model output containing reasoning, direct answer, confidence, citations, all-or-nothing claims, and matched terms. The reason it exists is: It carries the information needed to render, audit, and verify a model response.

### Layman’s explanation

The structured model output containing reasoning, direct answer, confidence, citations, atomic claims, and matched terms. It carries the information needed to render, audit, and verify a model response.

### Technical explanation

It is generated from the packed context and converted into StructuredAnswer. Primary code anchors: OpenIntelligence/Core/Models/RAGStructuredResponse.swift; OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelStructuredGenerator.swift.

### Why it is in this position

It is generated from the packed context and converted into StructuredAnswer.

## OI-0381. Reasoning-first field order

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Reasoning-first field order** means: Placing a reasoning or analysis field before the final answer in a generable type. The reason it exists is: Field order can encourage the model to identify supporting facts before committing to the answer.

### Layman’s explanation

Placing a reasoning or analysis field before the final answer in a generable type. Field order can encourage the model to identify supporting facts before committing to the answer.

### Technical explanation

It is used in RAGAnswer and reasoning-chain structures before the answer or insight field. Primary code anchors: OpenIntelligence/Core/Models/RAGStructuredResponse.swift.

### Why it is in this position

It is used in RAGAnswer and reasoning-chain structures before the answer or insight field.

## OI-0382. Registered retrieval tools

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Registered retrieval tools** means: The current group of approximately six model-callable tools for document search and related rule-based and repeatable operations. The reason it exists is: They support agentic evidence gathering while keeping model actions inside the app's local data boundary.

### Layman’s explanation

The current group of approximately six model-callable tools for document search and related deterministic operations. They support agentic evidence gathering while keeping model actions inside the app's local data boundary.

### Technical explanation

They are attached only to sessions whose execution plan allows tools. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelToolRegistry.swift.

**Important caveat:** The exact count can change; the source registry, not old marketing copy, is authoritative.

### Why it is in this position

They are attached only to sessions whose execution plan allows tools.

## OI-0383. Response-tail trimming

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Response-tail trimming** means: Removing obvious unfinished artifacts, duplicated schema fragments, or partial trailing structures after a terminated stream. The reason it exists is: A preserved partial answer should not expose broken serialization or misleading half-sentences.

### Layman’s explanation

Removing obvious unfinished artifacts, duplicated schema fragments, or partial trailing structures after a terminated stream. A preserved partial answer should not expose broken serialization or misleading half-sentences.

### Technical explanation

It occurs after stream termination and before the answer is committed and verified. Primary code anchors: OpenIntelligenceTests/Services/RAG/Orchestration/ResponseTailTrimmingTests.swift; OpenIntelligence/Services/RAG/Orchestration/RAGService.swift.

### Why it is in this position

It occurs after stream termination and before the answer is committed and verified.

## OI-0384. Route reason

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Route reason** means: The policy explanation for why a target was intended, such as exact extraction, local fit, user choice, or context overflow. The reason it exists is: A route without a reason is difficult to audit or reproduce.

### Layman’s explanation

The policy explanation for why a target was intended, such as exact extraction, local fit, user choice, or context overflow. A route without a reason is difficult to audit or reproduce.

### Technical explanation

It is assigned during planning and retained in receipt and transmission metadata. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/ModelExecutionPlan.swift.

### Why it is in this position

It is assigned during planning and retained in receipt and transmission metadata.

## OI-0385. Selected model

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Selected model** means: The model family or execution preference the user requested. The reason it exists is: User intent must be distinguished from the route the runtime can actually honor.

### Layman’s explanation

The model family or execution preference the user requested. User intent must be distinguished from the route the runtime can actually honor.

### Technical explanation

It is read at query start and compared with capability and execution results. Primary code anchors: OpenIntelligence/Core/Models/LLMModelType.swift; OpenIntelligence/Services/LLM/ModelResolutionService.swift.

### Why it is in this position

It is read at query start and compared with capability and execution results.

## OI-0386. Session transcript

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Session transcript** means: The accumulated instructions, prompts, tool calls, tool outputs, and model responses within a LanguageModelSession. The reason it exists is: The model sees this history on later calls, consuming context and influencing behavior.

### Layman’s explanation

The accumulated instructions, prompts, tool calls, tool outputs, and model responses within a LanguageModelSession. The model sees this history on later calls, consuming context and influencing behavior.

### Technical explanation

It grows during a session and is reset when isolation or token budget requires a fresh session. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelTranscriptStore.swift; OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelSessionFactory.swift.

### Why it is in this position

It grows during a session and is reset when isolation or token budget requires a fresh session.

## OI-0387. Session use case

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Session use case** means: A label distinguishing general answer generation from question enhancement, content tagging, contextual compression, or other focused work. The reason it exists is: Different tasks require different instructions and should not contaminate one shared transcript.

### Layman’s explanation

A label distinguishing general answer generation from query enhancement, content tagging, contextual compression, or other focused work. Different tasks require different instructions and should not contaminate one shared transcript.

### Technical explanation

It is chosen before session creation and controls factory configuration. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelSessionFactory.swift.

### Why it is in this position

It is chosen before session creation and controls factory configuration.

## OI-0388. Streaming generation

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Streaming generation** means: Receiving model output incrementally rather than waiting for the complete answer. The reason it exists is: It improves perceived latency, enables live progress, and can preserve meaningful partial text if a later error occurs.

### Layman’s explanation

Receiving model output incrementally rather than waiting for the complete answer. It improves perceived latency, enables live progress, and can preserve meaningful partial text if a later error occurs.

### Technical explanation

It begins after model invocation and feeds the UI and response accumulator until finalization. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/RAGService+Streaming.swift; OpenIntelligence/Services/LLM/LLMService.swift.

### Why it is in this position

It begins after model invocation and feeds the UI and response accumulator until finalization.

## OI-0389. Structured generation

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Structured generation** means: Requesting a typed output object instead of unconstrained text. The reason it exists is: Claims, citations, confidence, matched terms, and refusal state become machine-readable and do not depend on fragile JSON parsing.

### Layman’s explanation

Requesting a typed output object instead of unconstrained text. Claims, citations, confidence, matched terms, and refusal state become machine-readable and do not depend on fragile JSON parsing.

### Technical explanation

It is invoked after prompt compilation and converted into the durable StructuredAnswer model before verification. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelStructuredGenerator.swift; OpenIntelligence/Core/Models/RAGStructuredResponse.swift.

### Why it is in this position

It is invoked after prompt compilation and converted into the durable StructuredAnswer model before verification.

## OI-0390. SystemLanguageModel.default

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **SystemLanguageModel.default** means: The system-provided default on-device Apple language model exposed by FoundationModels. The reason it exists is: The OS owns model availability, updates, and final hardware scheduling, so the app must question capability rather than assume a named parameter count.

### Layman’s explanation

The system-provided default on-device Apple language model exposed by FoundationModels. The OS owns model availability, updates, and final hardware scheduling, so the app must query capability rather than assume a named parameter count.

### Technical explanation

It is checked during availability resolution and supplied to LanguageModelSession. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelSessionFactory.swift; OpenIntelligence/SDK/OpenIntelligenceEngine.swift.

### Why it is in this position

It is checked during availability resolution and supplied to LanguageModelSession.

## OI-0391. Temperature

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Temperature** means: The sampling parameter controlling output randomness, with lower values making generation more rule-based and repeatable. The reason it exists is: Grounded question answering benefits from consistency and low creative drift, especially for exact values.

### Layman’s explanation

The sampling parameter controlling output randomness, with lower values making generation more deterministic. Grounded question answering benefits from consistency and low creative drift, especially for exact values.

### Technical explanation

It is resolved by quality mode or settings and passed into the model generation call. Primary code anchors: OpenIntelligence/Core/Models/RAGQualityMode.swift; OpenIntelligence/UI/Components/Glossary.swift.

### Why it is in this position

It is resolved by quality mode or settings and passed into the model generation call.

## OI-0392. Time to first token

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Time to first token** means: The elapsed time from question execution start or generation request to the first delivered model token. The reason it exists is: It distinguishes search/setup latency from model streaming responsiveness.

### Layman’s explanation

The elapsed time from query execution start or generation request to the first delivered model token. It distinguishes retrieval/setup latency from model streaming responsiveness.

### Technical explanation

It is recorded at the first stream event and stored in diagnostics. Primary code anchors: OpenIntelligence/SDK/OpenIntelligenceEngine.swift; OpenIntelligence/Services/RAG/Orchestration/RAGService+Streaming.swift.

### Why it is in this position

It is recorded at the first stream event and stored in diagnostics.

## OI-0393. Tokens per second

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Tokens per second** means: Generated token count divided by active generation duration. The reason it exists is: It measures streaming throughput on a named device and route, not answer quality.

### Layman’s explanation

Generated token count divided by active generation duration. It measures streaming throughput on a named device and route, not answer quality.

### Technical explanation

It is computed after generation and exposed in diagnostics/evaluation. Primary code anchors: OpenIntelligence/SDK/OpenIntelligenceEngine.swift; OpenIntelligence/Services/Evaluation/RAGEvalMetrics.swift.

### Why it is in this position

It is computed after generation and exposed in diagnostics/evaluation.

## OI-0394. Tool call

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Tool call** means: One model request to execute an approved rule-based and repeatable tool with typed arguments. The reason it exists is: It separates deciding what to look up from actually reading the document collection.

### Layman’s explanation

One model request to execute an approved deterministic tool with typed arguments. It separates deciding what to look up from actually reading the corpus.

### Technical explanation

It occurs within an agentic or tool-enabled session and returns evidence to the model transcript. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelToolRegistry.swift.

### Why it is in this position

It occurs within an agentic or tool-enabled session and returns evidence to the model transcript.

## OI-0395. Tool-call counter

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Tool-call counter** means: A question-kept inside the right boundary count of model tool invocations. The reason it exists is: Tool loops need hard observability and limits to prevent runaway repeated searches.

### Layman’s explanation

A query-scoped count of model tool invocations. Tool loops need hard observability and limits to prevent runaway repeated searches.

### Technical explanation

It increments on tool execution and contributes to diagnostics and stopping policy. Primary code anchors: OpenIntelligence/Services/Agentic/ToolCallCounter.swift.

### Why it is in this position

It increments on tool execution and contributes to diagnostics and stopping policy.

## OI-0396. Top-p

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Top-p** means: Nucleus-sampling configuration limiting token choices to a cumulative probability mass. The reason it exists is: It can constrain sampling diversity when the backend supports it.

### Layman’s explanation

Nucleus-sampling configuration limiting token choices to a cumulative probability mass. It can constrain sampling diversity when the backend supports it.

### Technical explanation

It is stored in active parameters and may be applied at model invocation depending on framework support. Primary code anchors: OpenIntelligence/Services/LLM/ModelResolutionService.swift; OpenIntelligence/Services/LLM/LLMService.swift.

### Why it is in this position

It is stored in active parameters and may be applied at model invocation depending on framework support.

## OI-0397. Transcript persistence

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a choosing an engine and recording the trip. **Transcript persistence** means: Saving selected model transcript or question progress state for diagnostics or continuation. The reason it exists is: Long-running and background queries need recoverable state, while debugging needs evidence of what the engine actually sent and received.

### Layman’s explanation

Saving selected model transcript or query progress state for diagnostics or continuation. Long-running and background queries need recoverable state, while debugging needs evidence of what the engine actually sent and received.

### Technical explanation

It occurs around session boundaries and background handoff, subject to privacy controls. Primary code anchors: OpenIntelligence/Services/Infrastructure/Background/TranscriptPersistenceService.swift; OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelTranscriptStore.swift.

### Why it is in this position

It occurs around session boundaries and background handoff, subject to privacy controls.

---

# 11. Agentic, recursive, and multi-session reasoning

**Section orientation:** Deep Think and Maximum use multiple sessions, subquestions, iterative retrieval, a FactBank, novelty and coverage tracking, critique, refinement, and evidence-driven stopping.

## OI-0398. Agentic configuration

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Agentic configuration** means: The limits and policy for maximum sessions, search passes, tools, time, evidence thresholds, and stopping behavior. The reason it exists is: An open-ended model loop needs rule-based and repeatable resource and safety boundaries.

### Layman’s explanation

The limits and policy for maximum sessions, retrieval passes, tools, time, evidence thresholds, and stopping behavior. An open-ended model loop needs deterministic resource and safety boundaries.

### Technical explanation

It is resolved from quality mode, device policy, and user action before the first agentic step. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift; OpenIntelligence/Services/RAG/Tuning/AgenticPolicyService.swift.

### Why it is in this position

It is resolved from quality mode, device policy, and user action before the first agentic step.

## OI-0399. Agentic phase

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Agentic phase** means: A named state such as planning, searching, expanding, analyzing, synthesizing, refining, reformulating, or verifying. The reason it exists is: Explicit phases make the loop observable and allow rule-based and repeatable policy to control what actions are legal next.

### Layman’s explanation

A named state such as planning, searching, expanding, analyzing, synthesizing, refining, reformulating, or verifying. Explicit phases make the loop observable and allow deterministic policy to control what actions are legal next.

### Technical explanation

The orchestrator transitions among phases according to current evidence and gaps. Primary code anchors: OpenIntelligence/Core/Models/ThinkingEvent.swift; OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift.

### Why it is in this position

The orchestrator transitions among phases according to current evidence and gaps.

## OI-0400. AgenticOrchestrator

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **AgenticOrchestrator** means: The multi-session controller for planning, repeated search, evidence assessment, question reformulation, fact accumulation, synthesis, refinement, and verification. The reason it exists is: Complex questions need an adaptive loop whose next action depends on evidence found so far.

### Layman’s explanation

The multi-session controller for planning, repeated retrieval, evidence assessment, query reformulation, fact accumulation, synthesis, refinement, and verification. Complex questions need an adaptive loop whose next action depends on evidence found so far.

### Technical explanation

It replaces the Standard single-pass answer path in Deep Think, Maximum, forced, or eligible escalated execution. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift.

### Why it is in this position

It replaces the Standard single-pass answer path in Deep Think, Maximum, forced, or eligible escalated execution.

## OI-0401. Analyzing phase

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Analyzing phase** means: Evaluating evidence, extracting facts, resolving source identities, and identifying missing coverage. The reason it exists is: The loop must distinguish evidence quantity from answer completeness.

### Layman’s explanation

Evaluating evidence, extracting facts, resolving source identities, and identifying missing coverage. The loop must distinguish evidence quantity from answer completeness.

### Technical explanation

It follows retrieval/expansion and determines whether to synthesize, reformulate, or search again. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift.

### Why it is in this position

It follows retrieval/expansion and determines whether to synthesize, reformulate, or search again.

## OI-0402. ChainLink

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **ChainLink** means: A structured reasoning-chain output containing reasoning, a condensed insight, next focus, and cumulative confidence. The reason it exists is: It gives the next session a small explicit state rather than an unbounded transcript.

### Layman’s explanation

A structured reasoning-chain output containing reasoning, a condensed insight, next focus, and cumulative confidence. It gives the next session a small explicit state rather than an unbounded transcript.

### Technical explanation

It is produced by one recursive session and consumed by the next. Primary code anchors: OpenIntelligence/Core/Models/RAGStructuredResponse.swift.

### Why it is in this position

It is produced by one recursive session and consumed by the next.

## OI-0403. Convergence

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Convergence** means: The state in which additional search passes no longer add material facts or improve coverage enough to justify continued work. The reason it exists is: Maximum mode needs evidence-driven stopping rather than endless use of its high session allowance.

### Layman’s explanation

The state in which additional retrieval passes no longer add material facts or improve coverage enough to justify continued work. Maximum mode needs evidence-driven stopping rather than endless use of its high session allowance.

### Technical explanation

It is evaluated after each pass and can terminate the loop before the hard cap. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift; OpenIntelligence/Services/RAG/Tuning/AgenticPolicyService.swift.

### Why it is in this position

It is evaluated after each pass and can terminate the loop before the hard cap.

## OI-0404. Conversation summary

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Conversation summary** means: A compressed representation of older dialogue that preserves entities, decisions, and unresolved questions. The reason it exists is: It lets long conversations retain continuity without replaying every message verbatim.

### Layman’s explanation

A compressed representation of older dialogue that preserves entities, decisions, and unresolved questions. It lets long conversations retain continuity without replaying every message verbatim.

### Technical explanation

It is created when memory exceeds the direct-turn budget and used in later rewrites or prompts. Primary code anchors: OpenIntelligence/Services/Agentic/ConversationMemoryService.swift.

### Why it is in this position

It is created when memory exceeds the direct-turn budget and used in later rewrites or prompts.

## OI-0405. ConversationMemoryService

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **ConversationMemoryService** means: The service that summarizes and retrieves recent conversation context for standalone rewriting and continuity. The reason it exists is: Follow-up questions need prior entities and constraints, but full chat history cannot consume the entire model context.

### Layman’s explanation

The service that summarizes and retrieves recent conversation context for standalone rewriting and continuity. Follow-up questions need prior entities and constraints, but full chat history cannot consume the entire model context.

### Technical explanation

It is consulted before query rewriting and updated after answers. Primary code anchors: OpenIntelligence/Services/Agentic/ConversationMemoryService.swift.

### Why it is in this position

It is consulted before query rewriting and updated after answers.

## OI-0406. Coverage map

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Coverage map** means: The record of which subquestions or required answer dimensions have supporting facts. The reason it exists is: The loop needs a concrete definition of completeness to know when to stop.

### Layman’s explanation

The record of which subquestions or required answer dimensions have supporting facts. The loop needs a concrete definition of completeness to know when to stop.

### Technical explanation

It is updated after each fact-analysis pass and checked before synthesis. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift; OpenIntelligence/Services/RAG/Tuning/AgenticPolicyService.swift.

### Why it is in this position

It is updated after each fact-analysis pass and checked before synthesis.

## OI-0407. Critique step

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Critique step** means: A focused pass identifying unsupported claims, omissions, contradictions, or weak reasoning in a draft. The reason it exists is: Targeted critique gives the refinement phase a concrete repair objective.

### Layman’s explanation

A focused pass identifying unsupported claims, omissions, contradictions, or weak reasoning in a draft. Targeted critique gives the refinement phase a concrete repair objective.

### Technical explanation

It follows synthesis and precedes refinement or abstention. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift.

### Why it is in this position

It follows synthesis and precedes refinement or abstention.

## OI-0408. Default agentic profile

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Default agentic profile** means: The ordinary Deep Think multi-session configuration. The reason it exists is: It balances evidence depth and runtime for questions that exceed Standard.

### Layman’s explanation

The ordinary Deep Think multi-session configuration. It balances evidence depth and runtime for questions that exceed Standard.

### Technical explanation

It governs the typical agentic loop from planning through synthesis. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift.

### Why it is in this position

It governs the typical agentic loop from planning through synthesis.

## OI-0409. Evidence gap

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Evidence gap** means: A specific required fact, facet, comparison side, or condition that is not yet supported by the current document collection evidence. The reason it exists is: Naming the gap enables targeted search instead of generic more searching.

### Layman’s explanation

A specific required fact, facet, comparison side, or condition that is not yet supported by the current corpus evidence. Naming the gap enables targeted retrieval instead of generic more searching.

### Technical explanation

It is produced by evidence assessment and becomes the next reformulation or subquery. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift.

### Why it is in this position

It is produced by evidence assessment and becomes the next reformulation or subquery.

## OI-0410. Evidence-driven stopping

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Evidence-driven stopping** means: Stopping based on coverage, confidence, novelty, contradictions, and improvement rather than a fixed number of thoughts. The reason it exists is: A fixed loop count wastes work on easy questions and may stop too early on hard ones.

### Layman’s explanation

Stopping based on coverage, confidence, novelty, contradictions, and improvement rather than a fixed number of thoughts. A fixed loop count wastes work on easy questions and may stop too early on hard ones.

### Technical explanation

It is evaluated after each iterative or agentic cycle before another call is authorized. Primary code anchors: OpenIntelligence/Services/RAG/Tuning/AgenticPolicyService.swift.

### Why it is in this position

It is evaluated after each iterative or agentic cycle before another call is authorized.

## OI-0411. EvidenceThread

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **EvidenceThread** means: A local per-library conversation thread containing messages, title, timestamps, and labels and facts. The reason it exists is: It persists the user-visible evidence conversation separately from transient model sessions.

### Layman’s explanation

A local per-library conversation thread containing messages, title, timestamps, and metadata. It persists the user-visible evidence conversation separately from transient model sessions.

### Technical explanation

It is created around chat use, stored locally, and loaded before conversation-memory processing. Primary code anchors: OpenIntelligence/Core/Models/EvidenceThread.swift; OpenIntelligence/Services/Storage/EvidenceThreadStore.swift.

### Why it is in this position

It is created around chat use, stored locally, and loaded before conversation-memory processing.

## OI-0412. Expanding phase

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Expanding phase** means: Adding parents, siblings, cross-references, entities, graph neighbors, or broader possible result around promising hits. The reason it exists is: Initial search often finds an anchor rather than the complete answer.

### Layman’s explanation

Adding parents, siblings, cross-references, entities, graph neighbors, or broader candidates around promising hits. Initial search often finds an anchor rather than the complete answer.

### Technical explanation

It follows a search hit and precedes fact extraction or gap analysis. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift.

### Why it is in this position

It follows a search hit and precedes fact extraction or gap analysis.

## OI-0413. Fact

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Fact** means: An all-or-nothing evidence-backed proposition stored in the FactBank. The reason it exists is: all-or-nothing facts can be deduplicated, checked for contradictions, mapped to sources, and combined deliberately.

### Layman’s explanation

An atomic evidence-backed proposition stored in the FactBank. Atomic facts can be deduplicated, checked for contradictions, mapped to sources, and combined deliberately.

### Technical explanation

Facts are extracted after retrieval and before convergence or synthesis decisions. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift.

### Why it is in this position

Facts are extracted after retrieval and before convergence or synthesis decisions.

## OI-0414. Fact deduplication

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Fact deduplication** means: Merging or rejecting semantically repeated facts encountered across sessions. The reason it exists is: Repeated discovery should increase confidence or coverage, not consume state as if it were new information.

### Layman’s explanation

Merging or rejecting semantically repeated facts encountered across sessions. Repeated discovery should increase confidence or coverage, not consume state as if it were new information.

### Technical explanation

It occurs each time retrieved evidence is incorporated into the FactBank. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift.

### Why it is in this position

It occurs each time retrieved evidence is incorporated into the FactBank.

## OI-0415. Fact provenance

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Fact provenance** means: The source IDs, small source pieces, pages, or evidence labels attached to a FactBank fact. The reason it exists is: A recursive loop must not detach a condensed fact from the source that justified it.

### Layman’s explanation

The source IDs, chunks, pages, or evidence labels attached to a FactBank fact. A recursive loop must not detach a condensed fact from the source that justified it.

### Technical explanation

It is captured when the fact is added and reused in final citation construction. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift.

### Why it is in this position

It is captured when the fact is added and reused in final citation construction.

## OI-0416. FactBank

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **FactBank** means: The cumulative source-backed state that stores facts discovered across subquestions and sessions together with source history. The reason it exists is: Passing compact facts forward lets recursive RAG retain knowledge without carrying every full transcript or small source piece into each new session.

### Layman’s explanation

The cumulative source-backed state that stores facts discovered across subquestions and sessions together with provenance. Passing compact facts forward lets recursive RAG retain knowledge without carrying every full transcript or chunk into each new session.

### Technical explanation

It is initialized after planning, updated after evidence analysis, and consumed by final synthesis. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift.

### Why it is in this position

It is initialized after planning, updated after evidence analysis, and consumed by final synthesis.

## OI-0417. Fast agentic profile

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Fast agentic profile** means: A reduced multi-session configuration for limited deeper work. The reason it exists is: It provides some decomposition and verification without the full latency of thorough reasoning.

### Layman’s explanation

A reduced multi-session configuration for limited deeper work. It provides some decomposition and verification without the full latency of thorough reasoning.

### Technical explanation

It is selected before agentic execution under the relevant policy. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift.

### Why it is in this position

It is selected before agentic execution under the relevant policy.

## OI-0418. Hard session cap

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Hard session cap** means: The absolute maximum number of agentic model sessions allowed even if convergence never occurs. The reason it exists is: rule-based and repeatable safety bounds protect battery, heat, latency, quota, and cancellation behavior.

### Layman’s explanation

The absolute maximum number of agentic model sessions allowed even if convergence never occurs. Deterministic safety bounds protect battery, heat, latency, quota, and cancellation behavior.

### Technical explanation

It is checked before each additional agentic session. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift.

### Why it is in this position

It is checked before each additional agentic session.

## OI-0419. LLM call count

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **LLM call count** means: The number of separate model invocations used to produce an answer. The reason it exists is: It differentiates a Standard single pass from recursive RAG and helps explain latency and energy.

### Layman’s explanation

The number of separate model invocations used to produce an answer. It differentiates a Standard single pass from recursive RAG and helps explain latency and energy.

### Technical explanation

It increments per session and is committed with query audit data. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/RAGService.swift.

### Why it is in this position

It increments per session and is committed with query audit data.

## OI-0420. Memory turn limit

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Memory turn limit** means: The mode-dependent number of recent conversation turns retained or considered, roughly 5, 10, or 20. The reason it exists is: More context improves continuity but competes with document evidence and can introduce stale assumptions.

### Layman’s explanation

The mode-dependent number of recent conversation turns retained or considered, roughly 5, 10, or 20. More context improves continuity but competes with document evidence and can introduce stale assumptions.

### Technical explanation

It is resolved by quality mode before prompt or rewrite construction. Primary code anchors: OpenIntelligence/Core/Models/RAGQualityMode.swift; OpenIntelligence/Services/Agentic/ConversationMemoryService.swift.

### Why it is in this position

It is resolved by quality mode before prompt or rewrite construction.

## OI-0421. Planning phase

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Planning phase** means: The step that interprets the request, identifies subquestions, and chooses an initial evidence strategy. The reason it exists is: Searching before defining requirements can produce many relevant passages that still fail to answer the whole question.

### Layman’s explanation

The step that interprets the request, identifies subquestions, and chooses an initial evidence strategy. Searching before defining requirements can produce many relevant passages that still fail to answer the whole question.

### Technical explanation

It is the first agentic phase before focused retrieval. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift.

### Why it is in this position

It is the first agentic phase before focused retrieval.

## OI-0422. ReasonedInsight

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **ReasonedInsight** means: A structured output containing analysis, one key insight, discovered terms, and confidence. The reason it exists is: It standardizes what an intermediate evidence-analysis session passes forward.

### Layman’s explanation

A structured output containing analysis, one key insight, discovered terms, and confidence. It standardizes what an intermediate evidence-analysis session passes forward.

### Technical explanation

It is generated after examining a subset of context and before synthesis. Primary code anchors: OpenIntelligence/Core/Models/RAGStructuredResponse.swift.

### Why it is in this position

It is generated after examining a subset of context and before synthesis.

## OI-0423. ReasonedSynthesis

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **ReasonedSynthesis** means: A structured final integration of multiple insights with key points, confidence, and sources. The reason it exists is: The last step must reconcile accumulated findings rather than simply concatenate them.

### Layman’s explanation

A structured final integration of multiple insights with key points, confidence, and sources. The last step must reconcile accumulated findings rather than simply concatenate them.

### Technical explanation

It consumes intermediate insights at the end of a reasoning chain. Primary code anchors: OpenIntelligence/Core/Models/RAGStructuredResponse.swift.

### Why it is in this position

It consumes intermediate insights at the end of a reasoning chain.

## OI-0424. Reasoning session

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Reasoning session** means: One bounded LanguageModelSession call dedicated to a particular agentic objective. The reason it exists is: Fresh focused sessions avoid transcript overflow and isolate evidence assessment from final answer writing.

### Layman’s explanation

One bounded LanguageModelSession call dedicated to a particular agentic objective. Fresh focused sessions avoid transcript overflow and isolate evidence assessment from final answer writing.

### Technical explanation

Sessions occur sequentially or conditionally inside the agentic loop. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift.

### Why it is in this position

Sessions occur sequentially or conditionally inside the agentic loop.

## OI-0425. Reasoning trace

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Reasoning trace** means: A user-facing or diagnostic sequence of named progress events and condensed intermediate outcomes. The reason it exists is: It explains what stages ran without exposing raw hidden chain-of-thought.

### Layman’s explanation

A user-facing or diagnostic sequence of named progress events and condensed intermediate outcomes. It explains what stages ran without exposing raw hidden chain-of-thought.

### Technical explanation

Events are emitted during planning, retrieval, analysis, generation, and verification and returned through the SDK/UI. Primary code anchors: OpenIntelligence/Core/Models/ThinkingEvent.swift; OpenIntelligence/SDK/OpenIntelligenceEngine.swift.

### Why it is in this position

Events are emitted during planning, retrieval, analysis, generation, and verification and returned through the SDK/UI.

## OI-0426. Reasoning-chain token total

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Reasoning-chain token total** means: The sum of tokens consumed across every model call in recursive execution. The reason it exists is: One 4,096-token limit per session does not describe the total computational work of the answer.

### Layman’s explanation

The sum of tokens consumed across every model call in recursive execution. One 4,096-token limit per session does not describe the total computational work of the answer.

### Technical explanation

It is accumulated throughout the chain and stored in audit metadata. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/RAGService.swift.

### Why it is in this position

It is accumulated throughout the chain and stored in audit metadata.

## OI-0427. Recursive RAG

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Recursive RAG** means: A pattern that makes several bounded search and language-model calls, passing condensed facts or insights forward instead of forcing the full problem into one context window. The reason it exists is: Multiple 4,096-token sessions can collectively examine more evidence while each call remains within the local limit.

### Layman’s explanation

A pattern that makes several bounded retrieval and language-model calls, passing condensed facts or insights forward instead of forcing the full problem into one context window. Multiple 4,096-token sessions can collectively examine more evidence while each call remains within the local limit.

### Technical explanation

It begins after agentic planning and ends with a final synthesis over accumulated state. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift; OpenIntelligence/Services/RAG/Orchestration/RAGService.swift.

### Why it is in this position

It begins after agentic planning and ends with a final synthesis over accumulated state.

## OI-0428. Refining phase

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Refining phase** means: Improving an initial synthesis in response to verification failures, omissions, or unsupported claims. The reason it exists is: A generated answer can be mostly correct but require targeted repair rather than a full restart.

### Layman’s explanation

Improving an initial synthesis in response to verification failures, omissions, or unsupported claims. A generated answer can be mostly correct but require targeted repair rather than a full restart.

### Technical explanation

It follows verification and may precede another verification pass. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift.

### Why it is in this position

It follows verification and may precede another verification pass.

## OI-0429. Reformulating phase

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Reformulating phase** means: Changing the search question or decomposition when evidence is weak, redundant, or off-target. The reason it exists is: Repeating the same failed search cannot discover a different exact-word or meaning-based neighborhood.

### Layman’s explanation

Changing the search query or decomposition when evidence is weak, redundant, or off-target. Repeating the same failed retrieval cannot discover a different lexical or semantic neighborhood.

### Technical explanation

It follows gap analysis and precedes a new search pass. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift.

### Why it is in this position

It follows gap analysis and precedes a new search pass.

## OI-0430. Searching phase

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Searching phase** means: The execution of hybrid search for the current question or subquestion. The reason it exists is: The loop remains grounded by gathering source evidence before making claims.

### Layman’s explanation

The execution of hybrid retrieval for the current query or subquestion. The loop remains grounded by gathering source evidence before making claims.

### Technical explanation

It follows planning or reformulation and precedes evidence assessment. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift.

### Why it is in this position

It follows planning or reformulation and precedes evidence assessment.

## OI-0431. Self-RAG

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Self-RAG** means: A self-evaluation pattern in which the model or coordinate layer checks whether evidence supports the answer and may retrieve or revise again. The reason it exists is: Generation quality depends on the evidence and can be improved by explicitly detecting unsupported or incomplete output.

### Layman’s explanation

A self-evaluation pattern in which the model or orchestration layer checks whether evidence supports the answer and may retrieve or revise again. Generation quality depends on the evidence and can be improved by explicitly detecting unsupported or incomplete output.

### Technical explanation

It occurs after a draft or evidence assessment and before final verification/commit. Primary code anchors: OpenIntelligence/Core/Models/RAGQualityMode.swift; OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift.

### Why it is in this position

It occurs after a draft or evidence assessment and before final verification/commit.

## OI-0432. Standard reasoning chain

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Standard reasoning chain** means: A bounded multi-step reasoning sequence used within some Standard answer paths without invoking the full agentic orchestrator. The reason it exists is: A question can benefit from structured evidence analysis and synthesis while still avoiding open-ended search loops.

### Layman’s explanation

A bounded multi-step reasoning sequence used within some Standard answer paths without invoking the full agentic orchestrator. A question can benefit from structured evidence analysis and synthesis while still avoiding open-ended retrieval loops.

### Technical explanation

It follows final context selection and precedes answer verification. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/RAGService.swift.

### Why it is in this position

It follows final context selection and precedes answer verification.

## OI-0433. Synthesizing phase

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Synthesizing phase** means: Combining accumulated source-backed facts into a coherent answer. The reason it exists is: Multiple subquestions and documents require composition after their evidence is independently gathered.

### Layman’s explanation

Combining accumulated source-backed facts into a coherent answer. Multiple subquestions and documents require composition after their evidence is independently gathered.

### Technical explanation

It occurs only after coverage or stopping policy says enough evidence exists. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift.

### Why it is in this position

It occurs only after coverage or stopping policy says enough evidence exists.

## OI-0434. ThinkingEvent

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **ThinkingEvent** means: A typed progress event with phase, title, detail, icons, counters, confidence, and generation state. The reason it exists is: Typed events keep the live UI and SDK synchronized with the actual pipeline rather than parsing log strings.

### Layman’s explanation

A typed progress event with phase, title, detail, icons, counters, confidence, and generation state. Typed events keep the live UI and SDK synchronized with the actual pipeline rather than parsing log strings.

### Technical explanation

It is emitted throughout query execution and consumed by progress surfaces. Primary code anchors: OpenIntelligence/Core/Models/ThinkingEvent.swift.

### Why it is in this position

It is emitted throughout query execution and consumed by progress surfaces.

## OI-0435. Thorough agentic profile

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Thorough agentic profile** means: A broader configuration with more search and reasoning allowance. The reason it exists is: Cross-topic or incomplete-evidence questions may need more passes and source expansion.

### Layman’s explanation

A broader configuration with more retrieval and reasoning allowance. Cross-topic or incomplete-evidence questions may need more passes and source expansion.

### Technical explanation

It is selected for higher-effort planning before the loop begins. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift.

### Why it is in this position

It is selected for higher-effort planning before the loop begins.

## OI-0436. Unlimited agentic profile

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Unlimited agentic profile** means: The Maximum-mode configuration with a high but still finite safety cap, including up to roughly 50 sessions in current source. The reason it exists is: Maximum should stop when evidence converges, but a hard ceiling protects against pathological loops.

### Layman’s explanation

The Maximum-mode configuration with a high but still finite safety cap, including up to roughly 50 sessions in current source. Maximum should stop when evidence converges, but a hard ceiling protects against pathological loops.

### Technical explanation

It governs Maximum execution until convergence, timeout, cancellation, or the cap. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift; OpenIntelligence/Services/RAG/Tuning/AgenticPolicyService.swift.

### Why it is in this position

It governs Maximum execution until convergence, timeout, cancellation, or the cap.

## OI-0437. Verifying phase

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a research team with a shared notebook. **Verifying phase** means: Running source and claim checks over the agentic synthesis. The reason it exists is: More model calls do not make an answer trustworthy by themselves; the final output still needs rule-based and repeatable gates.

### Layman’s explanation

Running source and claim checks over the agentic synthesis. More model calls do not make an answer trustworthy by themselves; the final output still needs deterministic gates.

### Technical explanation

It follows synthesis/refinement and can trigger repair or abstention. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift; OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift.

### Why it is in this position

It follows synthesis/refinement and can trigger repair or abstention.

---

# 12. Verification, grounding, confidence, and abstention

**Section orientation:** Verification checks claims, citations, quotes, numeric values, contradictions, domain consistency, completeness, and evidence coverage. It calibrates trust and can remove claims or abstain.

## OI-0438. Absence assertion

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Absence assertion** means: The explicit claim that requested information is not present in the document collection, supported by sufficiently broad search and search checks. The reason it exists is: Saying not found is itself a factual assertion and should not be issued after a shallow miss.

### Layman’s explanation

The explicit claim that requested information is not present in the corpus, supported by sufficiently broad retrieval and search checks. Saying not found is itself a factual assertion and should not be issued after a shallow miss.

### Technical explanation

It is verified before final abstention wording for missing-information cases. Primary code anchors: OpenIntelligenceTests/Services/RAG/Tuning/AbsenceAssertionTests.swift; OpenIntelligence/Services/RAG/Safety/SourceOnlyAnswerService.swift.

### Why it is in this position

It is verified before final abstention wording for missing-information cases.

## OI-0439. Abstention

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Abstention** means: The deliberate decision to say the documents do not support an answer instead of guessing. The reason it exists is: A grounded system needs a valid no-answer outcome; otherwise every search miss becomes a hallucination opportunity.

### Layman’s explanation

The deliberate decision to say the documents do not support an answer instead of guessing. A grounded system needs a valid no-answer outcome; otherwise every retrieval miss becomes a hallucination opportunity.

### Technical explanation

It can occur before generation, after critical gate failure, after failed refinement, or during confidence calibration. Primary code anchors: OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift; OpenIntelligence/Core/Models/StructuredAnswer.swift.

### Why it is in this position

It can occur before generation, after critical gate failure, after failed refinement, or during confidence calibration.

## OI-0440. Abstention threshold

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Abstention threshold** means: The adjusted against a trust rule confidence floor below which the answer is refused, made stricter from Standard to Maximum and for touchy queries. The reason it exists is: A higher-effort mode should not merely search more; it should demand stronger evidence before asserting.

### Layman’s explanation

The calibrated confidence floor below which the answer is refused, made stricter from Standard to Maximum and for touchy queries. A higher-effort mode should not merely search more; it should demand stronger evidence before asserting.

### Technical explanation

It is resolved by ConfidencePolicyService and applied after calibration. Primary code anchors: OpenIntelligence/Services/RAG/Tuning/ConfidencePolicyService.swift.

### Why it is in this position

It is resolved by ConfidencePolicyService and applied after calibration.

## OI-0441. Answer replacement guard

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Answer replacement guard** means: A safeguard preventing a later transformation or fallback from replacing a stronger grounded answer with a weaker or unsupported one. The reason it exists is: Multi-stage pipelines can regress after producing a correct extractive answer.

### Layman’s explanation

A safeguard preventing a later transformation or fallback from replacing a stronger grounded answer with a weaker or unsupported one. Multi-stage pipelines can regress after producing a correct extractive answer.

### Technical explanation

It is evaluated when agentic, source-only, or formatting paths propose a replacement. Primary code anchors: OpenIntelligenceTests/Services/Agentic/AnswerReplacementGuardTests.swift; OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift.

### Why it is in this position

It is evaluated when agentic, source-only, or formatting paths propose a replacement.

## OI-0442. Bibliography penalty

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Bibliography penalty** means: A reduction or exclusion applied to small source pieces recognized as references when the question seeks substantive findings rather than citations. The reason it exists is: A bibliography contains question terms and author names but usually does not state the evidence being asked about.

### Layman’s explanation

A reduction or exclusion applied to chunks recognized as references when the query seeks substantive findings rather than citations. A bibliography contains query terms and author names but usually does not state the evidence being asked about.

### Technical explanation

It is applied during retrieval or verification before answer synthesis. Primary code anchors: OpenIntelligenceTests/Services/RAG/Orchestration/BibliographyPenaltyTests.swift; OpenIntelligence/Services/Document/Analysis/ReferenceListDetector.swift.

### Why it is in this position

It is applied during retrieval or verification before answer synthesis.

## OI-0443. Calibration caveat

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Calibration caveat** means: The fact that configured adjusted against a trust rule is a heuristic policy unless validated against held-out outcome frequencies. The reason it exists is: A displayed 80 percent should not be interpreted as a statistically proven 0.80 probability without empirical adjusted against a trust rule data.

### Layman’s explanation

The fact that configured calibration is a heuristic policy unless validated against held-out outcome frequencies. A displayed 80 percent should not be interpreted as a statistically proven 0.80 probability without empirical calibration data.

### Technical explanation

It governs how confidence should be taught and presented, not a runtime stage. Primary code anchors: OpenIntelligence/Services/RAG/Safety/ConfidenceCalibrationService.swift; Docs/EVALS.md.

### Why it is in this position

It governs how confidence should be taught and presented, not a runtime stage.

## OI-0444. Calibration parameters

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Calibration parameters** means: The slope, intercept, penalties, and conservative/default parameter set used to adjust confidence. The reason it exists is: Central parameters make confidence behavior testable and mode-dependent.

### Layman’s explanation

The slope, intercept, penalties, and conservative/default parameter set used to adjust confidence. Central parameters make confidence behavior testable and mode-dependent.

### Technical explanation

They are selected by ConfidencePolicyService and applied by ConfidenceCalibrationService. Primary code anchors: OpenIntelligence/Services/RAG/Tuning/ConfidencePolicyService.swift; OpenIntelligence/Services/RAG/Safety/ConfidenceCalibrationService.swift.

### Why it is in this position

They are selected by ConfidencePolicyService and applied by ConfidenceCalibrationService.

## OI-0445. Claim verification verdict

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Claim verification verdict** means: The supported, partial, or unsupported classification attached to one answer claim. The reason it exists is: A single global confidence hides which exact assertions are reliable.

### Layman’s explanation

The supported, partial, or unsupported classification attached to one answer claim. A single global confidence hides which exact assertions are reliable.

### Technical explanation

It is produced by Gate B and stored with each StructuredAnswer claim. Primary code anchors: OpenIntelligence/Core/Models/StructuredAnswer.swift; OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift.

### Why it is in this position

It is produced by Gate B and stored with each StructuredAnswer claim.

## OI-0446. Confidence calibration

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Confidence calibration** means: Transforming raw signals using configured parameters and verification results to produce a more conservative answer confidence. The reason it exists is: Raw model and similarity scores have different scales and can be overconfident.

### Layman’s explanation

Transforming raw signals using configured parameters and verification results to produce a more conservative answer confidence. Raw model and similarity scores have different scales and can be overconfident.

### Technical explanation

It runs after verification and before the response confidence and abstention decision are finalized. Primary code anchors: OpenIntelligence/Services/RAG/Safety/ConfidenceCalibrationService.swift.

### Why it is in this position

It runs after verification and before the response confidence and abstention decision are finalized.

## OI-0447. Confidence policy

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Confidence policy** means: The per-question thresholds and adjusted against a trust rule parameters derived from answer intent, touchy status, and quality mode. The reason it exists is: Confidence and abstention decisions should change coherently with risk and requested effort.

### Layman’s explanation

The per-query thresholds and calibration parameters derived from answer intent, touchy status, and quality mode. Confidence and abstention decisions should change coherently with risk and requested effort.

### Technical explanation

It is created before verification and used during gate combination and calibration. Primary code anchors: OpenIntelligence/Services/RAG/Tuning/ConfidencePolicyService.swift.

### Why it is in this position

It is created before verification and used during gate combination and calibration.

## OI-0448. Critical gate

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Critical gate** means: A verification gate whose failure can independently force abstention, currently including search confidence, numeric sanity, and meaning-based grounding. The reason it exists is: Some failures invalidate the answer regardless of how well other dimensions scored.

### Layman’s explanation

A verification gate whose failure can independently force abstention, currently including retrieval confidence, numeric sanity, and semantic grounding. Some failures invalidate the answer regardless of how well other dimensions scored.

### Technical explanation

Critical status is interpreted when gate results are combined. Primary code anchors: OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift.

### Why it is in this position

Critical status is interpreted when gate results are combined.

## OI-0449. DomainIsolationService

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **DomainIsolationService** means: The service that classifies claim/evidence domains and penalizes or blocks support crossing incompatible domains. The reason it exists is: Common terms can make an unrelated medical, legal, automotive, or computing passage appear semantically relevant.

### Layman’s explanation

The service that classifies claim/evidence domains and penalizes or blocks support crossing incompatible domains. Common terms can make an unrelated medical, legal, automotive, or computing passage appear semantically relevant.

### Technical explanation

It runs during verification after evidence mapping and before final support verdicts. Primary code anchors: OpenIntelligence/Services/RAG/Safety/DomainIsolationService.swift.

### Why it is in this position

It runs during verification after evidence mapping and before final support verdicts.

## OI-0450. Evidence-first mode

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Evidence-first mode** means: A policy that treats retrieved source content as the primary answer authority and model output as a constrained transformation. The reason it exists is: It reverses the unsafe pattern of generating first and searching for citations afterward.

### Layman’s explanation

A policy that treats retrieved source content as the primary answer authority and model output as a constrained transformation. It reverses the unsafe pattern of generating first and searching for citations afterward.

### Technical explanation

It is resolved before generation and activates source-only verification afterward. Primary code anchors: OpenIntelligence/Services/RAG/Safety/SourceOnlyAnswerService.swift; OpenIntelligence/Services/Query/Analysis/GroundedAnswerPolicy.swift.

### Why it is in this position

It is resolved before generation and activates source-only verification afterward.

## OI-0451. Fidelity

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Fidelity** means: The degree to which the visible answer remains locked to and fully supported by the cited sources. The reason it exists is: Confidence can reflect overall certainty, while fidelity specifically communicates source support.

### Layman’s explanation

The degree to which the visible answer remains locked to and fully supported by the cited sources. Confidence can reflect overall certainty, while fidelity specifically communicates source support.

### Technical explanation

It is derived after verification and rendered as source-locked, partially supported, or insufficient evidence. Primary code anchors: OpenIntelligence/Features/Chat/Response/SourceFidelityStatus.swift; OpenIntelligence/UI/Components/Glossary.swift.

### Why it is in this position

It is derived after verification and rendered as source-locked, partially supported, or insufficient evidence.

## OI-0452. Gate A: Retrieval Confidence

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Gate A: Retrieval Confidence** means: The check that the retrieved evidence has sufficient relevance and separation to justify answering. The reason it exists is: No downstream phrasing can compensate for an evidence set that never found the answer.

### Layman’s explanation

The check that the retrieved evidence has sufficient relevance and separation to justify answering. No downstream phrasing can compensate for an evidence set that never found the answer.

### Technical explanation

It is the first critical gate and can force abstention before claim-level approval. Primary code anchors: OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift.

### Why it is in this position

It is the first critical gate and can force abstention before claim-level approval.

## OI-0453. Gate B: Evidence Coverage

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Gate B: Evidence Coverage** means: The claim-by-claim check that answer assertions are supported by supplied evidence. The reason it exists is: An answer can cite sources globally while individual claims remain unsupported.

### Layman’s explanation

The claim-by-claim check that answer assertions are supported by supplied evidence. An answer can cite sources globally while individual claims remain unsupported.

### Technical explanation

It decomposes the draft into claims and assigns supported, partial, or unsupported outcomes. Primary code anchors: OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift; OpenIntelligence/Core/Models/StructuredAnswer.swift.

### Why it is in this position

It decomposes the draft into claims and assigns supported, partial, or unsupported outcomes.

## OI-0454. Gate C: Numeric Sanity

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Gate C: Numeric Sanity** means: The critical check that numbers, units, ranges, and exact values in the answer are present and consistent with evidence. The reason it exists is: Numeric hallucinations are especially dangerous because a small digit or unit change can invert meaning.

### Layman’s explanation

The critical check that numbers, units, ranges, and exact values in the answer are present and consistent with evidence. Numeric hallucinations are especially dangerous because a small digit or unit change can invert meaning.

### Technical explanation

It runs after claim extraction and can force abstention or remove unsupported values. Primary code anchors: OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift.

### Why it is in this position

It runs after claim extraction and can force abstention or remove unsupported values.

## OI-0455. Gate D: Contradiction Sweep

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Gate D: Contradiction Sweep** means: The check for conflicts among the answer, evidence passages, and potentially conflicting source statements. The reason it exists is: A high-similarity source can still disagree with another relevant source or with the generated claim.

### Layman’s explanation

The check for conflicts among the answer, evidence passages, and potentially conflicting source statements. A high-similarity source can still disagree with another relevant source or with the generated claim.

### Technical explanation

It runs after initial grounding checks and contributes to final confidence or abstention. Primary code anchors: OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift.

### Why it is in this position

It runs after initial grounding checks and contributes to final confidence or abstention.

## OI-0456. Gate E: Semantic Grounding

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Gate E: Semantic Grounding** means: The critical meaning-based check that the answer meaning remains close to the evidence meaning. The reason it exists is: Exact token overlap alone misses paraphrased fabrication, while meaning-based comparison can detect drift.

### Layman’s explanation

The critical semantic check that the answer meaning remains close to the evidence meaning. Exact token overlap alone misses paraphrased fabrication, while semantic comparison can detect drift.

### Technical explanation

It compares claims or answer text with source evidence before acceptance. Primary code anchors: OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift.

### Why it is in this position

It compares claims or answer text with source evidence before acceptance.

## OI-0457. Gate F: Quote Faithfulness

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Gate F: Quote Faithfulness** means: The check that quoted or extractive language actually appears in the attributed source and has not been materially altered. The reason it exists is: Quotation marks and citations imply a stronger source history guarantee than ordinary synthesis.

### Layman’s explanation

The check that quoted or extractive language actually appears in the attributed source and has not been materially altered. Quotation marks and citations imply a stronger provenance guarantee than ordinary synthesis.

### Technical explanation

It validates quote spans and citations after generation. Primary code anchors: OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift.

### Why it is in this position

It validates quote spans and citations after generation.

## OI-0458. Gate G: Generation Quality

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Gate G: Generation Quality** means: The check for empty, malformed, repetitive, truncated, or otherwise unusable model output. The reason it exists is: An answer can be grounded yet still fail as a response because the stream or schema was incomplete.

### Layman’s explanation

The check for empty, malformed, repetitive, truncated, or otherwise unusable model output. An answer can be grounded yet still fail as a response because the stream or schema was incomplete.

### Technical explanation

It runs over the generated structure before final rendering. Primary code anchors: OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift.

### Why it is in this position

It runs over the generated structure before final rendering.

## OI-0459. Gate H: Answer Completeness

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Gate H: Answer Completeness** means: The check that the response addresses the requested facets rather than answering only an easy subset. The reason it exists is: Partial coverage can be misleading when presented as a complete answer.

### Layman’s explanation

The check that the response addresses the requested facets rather than answering only an easy subset. Partial coverage can be misleading when presented as a complete answer.

### Technical explanation

It compares query requirements with claims and missing fields before commit. Primary code anchors: OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift.

### Why it is in this position

It compares query requirements with claims and missing fields before commit.

## OI-0460. Gate I: Domain Isolation

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Gate I: Domain Isolation** means: The check that specialized evidence and claims remain within the correct domain, document context, and citation scope. The reason it exists is: Shared words across medical, engineering, legal, and general domains can create plausible but cross-domain false support.

### Layman’s explanation

The check that specialized evidence and claims remain within the correct domain, document context, and citation scope. Shared words across medical, engineering, legal, and general domains can create plausible but cross-domain false support.

### Technical explanation

It runs near the end of verification and can remove or abstain on contaminated claims. Primary code anchors: OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift; OpenIntelligence/Services/RAG/Safety/DomainIsolationService.swift.

### Why it is in this position

It runs near the end of verification and can remove or abstain on contaminated claims.

## OI-0461. Missing-information list

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Missing-information list** means: The explicit fields, facts, or support the question requested but the document collection did not provide. The reason it exists is: A refusal is more useful when it identifies the gap rather than returning a generic failure.

### Layman’s explanation

The explicit fields, facts, or support the question requested but the corpus did not provide. A refusal is more useful when it identifies the gap rather than returning a generic failure.

### Technical explanation

It is populated during extraction, completeness verification, and StructuredAnswer construction. Primary code anchors: OpenIntelligence/Core/Models/StructuredAnswer.swift.

### Why it is in this position

It is populated during extraction, completeness verification, and StructuredAnswer construction.

## OI-0462. Not Enough Evidence

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Not Enough Evidence** means: The UI state for abstention or evidence too weak to safely verify an answer. The reason it exists is: The absence of a confident answer is itself important information about the document collection.

### Layman’s explanation

The UI state for abstention or evidence too weak to safely verify an answer. The absence of a confident answer is itself important information about the corpus.

### Technical explanation

It is assigned when the response abstains or fidelity collapses. Primary code anchors: OpenIntelligence/Features/Chat/Response/SourceFidelityStatus.swift.

### Why it is in this position

It is assigned when the response abstains or fidelity collapses.

## OI-0463. Numeric-unit verification

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Numeric-unit verification** means: Comparing numbers together with their units, qualifiers, ranges, and source context rather than checking digits alone. The reason it exists is: 5 mg and 5 mL are not interchangeable, and maximum versus typical changes the claim.

### Layman’s explanation

Comparing numbers together with their units, qualifiers, ranges, and source context rather than checking digits alone. 5 mg and 5 mL are not interchangeable, and maximum versus typical changes the claim.

### Technical explanation

It is part of Gate C and specification evidence scoring before answer acceptance. Primary code anchors: OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift; OpenIntelligence/Services/RAG/Tuning/EvidenceScoringPolicyService.swift.

### Why it is in this position

It is part of Gate C and specification evidence scoring before answer acceptance.

## OI-0464. Partially Supported

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Partially Supported** means: The UI state indicating useful answer content remains but some details did not receive full verification. The reason it exists is: It exposes uncertainty instead of flattening mixed claim support into one green badge.

### Layman’s explanation

The UI state indicating useful answer content remains but some details did not receive full verification. It exposes uncertainty instead of flattening mixed claim support into one green badge.

### Technical explanation

It is assigned after verification below the source-locked threshold and above abstention. Primary code anchors: OpenIntelligence/Features/Chat/Response/SourceFidelityStatus.swift.

### Why it is in this position

It is assigned after verification below the source-locked threshold and above abstention.

## OI-0465. Partially supported claim

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Partially supported claim** means: A claim for which evidence supports the main point but not every detail or degree of certainty. The reason it exists is: The engine can preserve useful information while explicitly lowering trust rather than pretending full support.

### Layman’s explanation

A claim for which evidence supports the main point but not every detail or degree of certainty. The engine can preserve useful information while explicitly lowering trust rather than pretending full support.

### Technical explanation

It is marked during Gate B and may be revised, caveated, or removed depending on policy. Primary code anchors: OpenIntelligence/Core/Models/StructuredAnswer.swift.

### Why it is in this position

It is marked during Gate B and may be revised, caveated, or removed depending on policy.

## OI-0466. Precision lock

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Precision lock** means: A high-confidence state where rule-based and repeatable or source-only evidence is strong enough to answer directly and block unnecessary model-written rewriting. The reason it exists is: Exact values can be degraded by paraphrase or accidental number changes.

### Layman’s explanation

A high-confidence state where deterministic or source-only evidence is strong enough to answer directly and block unnecessary generative rewriting. Exact values can be degraded by paraphrase or accidental number changes.

### Technical explanation

It is triggered by extractive scoring thresholds before model synthesis. Primary code anchors: OpenIntelligence/Services/RAG/Tuning/EvidenceScoringPolicyService.swift; OpenIntelligence/Services/RAG/Safety/SourceOnlyAnswerService.swift.

### Why it is in this position

It is triggered by extractive scoring thresholds before model synthesis.

## OI-0467. Quote-span verification

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Quote-span verification** means: Checking that a cited quote exists in the source text at the attributed location or within an accepted put into a consistent form match. The reason it exists is: A fabricated quote with a real citation is more misleading than an uncited paraphrase.

### Layman’s explanation

Checking that a cited quote exists in the source text at the attributed location or within an accepted normalized match. A fabricated quote with a real citation is more misleading than an uncited paraphrase.

### Technical explanation

It occurs during Gate F and citation construction. Primary code anchors: OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift; OpenIntelligence/Core/Models/StructuredAnswer.swift.

### Why it is in this position

It occurs during Gate F and citation construction.

## OI-0468. Raw confidence

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Raw confidence** means: An uncalibrated score derived from model output, search scores, claim support, or extraction strength. The reason it exists is: It is an internal signal, not automatically a probability that the answer is true.

### Layman’s explanation

An uncalibrated score derived from model output, retrieval scores, claim support, or extraction strength. It is an internal signal, not automatically a probability that the answer is true.

### Technical explanation

It is produced during extraction/generation and passed to calibration and UI mapping. Primary code anchors: OpenIntelligence/Services/RAG/Safety/ConfidenceCalibrationService.swift; OpenIntelligence/Core/Models/StructuredAnswer.swift.

### Why it is in this position

It is produced during extraction/generation and passed to calibration and UI mapping.

## OI-0469. Reliability mode

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Reliability mode** means: A user/runtime setting that favors grounded fallback, verification, and explicit uncertainty over permissive output. The reason it exists is: The product promise depends on failing safely when evidence or generation is weak.

### Layman’s explanation

A user/runtime setting that favors grounded fallback, verification, and explicit uncertainty over permissive output. The product promise depends on failing safely when evidence or generation is weak.

### Technical explanation

It is read by QueryRuntimeCoordinator and influences fallback and verification behavior. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/QueryRuntimeCoordinator.swift.

### Why it is in this position

It is read by QueryRuntimeCoordinator and influences fallback and verification behavior.

## OI-0470. Scientific-domain claim check

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Scientific-domain claim check** means: Special handling for research claims, statistical language, methods, results, and citation sections. The reason it exists is: Scientific text has recurring structures where bibliography or background language can be mistaken for study findings.

### Layman’s explanation

Special handling for research claims, statistical language, methods, results, and citation sections. Scientific text has recurring structures where bibliography or background language can be mistaken for study findings.

### Technical explanation

It is applied during domain isolation and evidence verification for research documents. Primary code anchors: OpenIntelligence/Services/RAG/Safety/DomainIsolationService.swift.

### Why it is in this position

It is applied during domain isolation and evidence verification for research documents.

## OI-0471. Source-Locked

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Source-Locked** means: The UI state indicating all material claims passed source grounding at the required fidelity threshold. The reason it exists is: It gives the user a stronger and more specific trust signal than a generic confidence number.

### Layman’s explanation

The UI state indicating all material claims passed source grounding at the required fidelity threshold. It gives the user a stronger and more specific trust signal than a generic confidence number.

### Technical explanation

It is assigned after verification when the answer is not abstained and fidelity is high. Primary code anchors: OpenIntelligence/Features/Chat/Response/SourceFidelityStatus.swift.

### Why it is in this position

It is assigned after verification when the answer is not abstained and fidelity is high.

## OI-0472. Source-only verification

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Source-only verification** means: Checking that the final answer can be reconstructed or supported from source passages without relying on model memory. The reason it exists is: Citations are meaningful only when the cited text actually entails the claim.

### Layman’s explanation

Checking that the final answer can be reconstructed or supported from source passages without relying on model memory. Citations are meaningful only when the cited text actually entails the claim.

### Technical explanation

It is required for evidence-first, citation-required, and several answer intents under GroundedAnswerPolicy. Primary code anchors: OpenIntelligence/Services/Query/Analysis/GroundedAnswerPolicy.swift; OpenIntelligence/Services/RAG/Safety/SourceOnlyAnswerService.swift.

### Why it is in this position

It is required for evidence-first, citation-required, and several answer intents under GroundedAnswerPolicy.

## OI-0473. SourceOnlyAnswerService

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **SourceOnlyAnswerService** means: A fallback and verification service that constructs or validates an answer exclusively from retrieved source sentences. The reason it exists is: When model-written grounding is uncertain, the safest useful result may be a concise extractive answer rather than no response or a fluent guess.

### Layman’s explanation

A fallback and verification service that constructs or validates an answer exclusively from retrieved source sentences. When generative grounding is uncertain, the safest useful result may be a concise extractive answer rather than no response or a fluent guess.

### Technical explanation

It runs after evidence retrieval and may replace a failed generative answer before abstention. Primary code anchors: OpenIntelligence/Services/RAG/Safety/SourceOnlyAnswerService.swift.

### Why it is in this position

It runs after evidence retrieval and may replace a failed generative answer before abstention.

## OI-0474. Supported claim

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Supported claim** means: A claim whose meaning and material details are directly justified by mapped evidence. The reason it exists is: It is eligible to remain in a source-locked answer.

### Layman’s explanation

A claim whose meaning and material details are directly justified by mapped evidence. It is eligible to remain in a source-locked answer.

### Technical explanation

It is retained after claim verification and contributes positively to fidelity. Primary code anchors: OpenIntelligence/Core/Models/StructuredAnswer.swift.

### Why it is in this position

It is retained after claim verification and contributes positively to fidelity.

## OI-0475. Unsupported claim

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Unsupported claim** means: A claim with no adequate evidence mapping or a contradiction with supplied evidence. The reason it exists is: It must not survive merely because the overall answer sounds plausible.

### Layman’s explanation

A claim with no adequate evidence mapping or a contradiction with supplied evidence. It must not survive merely because the overall answer sounds plausible.

### Technical explanation

It is identified during verification and triggers removal, refinement, or abstention. Primary code anchors: OpenIntelligence/Core/Models/StructuredAnswer.swift.

### Why it is in this position

It is identified during verification and triggers removal, refinement, or abstention.

## OI-0476. Verification configuration

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **Verification configuration** means: The threshold bundle for normal, touchy, margin, meaning-based grounding, and critical-category behavior. The reason it exists is: One centralized configuration prevents separate answer paths from using contradictory safety standards.

### Layman’s explanation

The threshold bundle for normal, touchy, margin, semantic grounding, and critical-category behavior. One centralized configuration prevents separate answer paths from using contradictory safety standards.

### Technical explanation

It is resolved per query by ConfidencePolicyService before the gates run. Primary code anchors: OpenIntelligence/Services/RAG/Tuning/ConfidencePolicyService.swift; OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift.

### Why it is in this position

It is resolved per query by ConfidencePolicyService before the gates run.

## OI-0477. VerificationGateService

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a fact-checking desk and safety inspector. **VerificationGateService** means: The rule-based and repeatable post-generation service that evaluates search confidence, evidence coverage, numeric sanity, contradictions, meaning-based grounding, quotes, generation quality, completeness, and domain isolation. The reason it exists is: A language model can produce fluent unsupported claims even from good evidence. Verification is the final enforcement boundary.

### Layman’s explanation

The deterministic post-generation service that evaluates retrieval confidence, evidence coverage, numeric sanity, contradictions, semantic grounding, quotes, generation quality, completeness, and domain isolation. A language model can produce fluent unsupported claims even from good evidence. Verification is the final enforcement boundary.

### Technical explanation

It runs after a draft answer and before the response is accepted, sanitized, or replaced by abstention. Primary code anchors: OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift.

### Why it is in this position

It runs after a draft answer and before the response is accepted, sanitized, or replaced by abstention.

---

# 13. Response structure, provenance, rendering, and observability

**Section orientation:** The response is a structured package, not just prose. It includes claims, evidence IDs, citations, metadata, diagnostics, route information, source chips, and persisted evidence threads.

## OI-0478. Enhanced code block

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **Enhanced code block** means: The response component that renders code with language labels, scrolling, and copy behavior. The reason it exists is: Code answers need formatting that preserves whitespace and supports practical reuse.

### Layman’s explanation

The response component that renders code with language labels, scrolling, and copy behavior. Code answers need formatting that preserves whitespace and supports practical reuse.

### Technical explanation

It is created by the Markdown response renderer for fenced code content. Primary code anchors: OpenIntelligence/Features/Chat/Response/EnhancedCodeBlock.swift.

### Why it is in this position

It is created by the Markdown response renderer for fenced code content.

## OI-0479. Evidence ID

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **Evidence ID** means: The stable identifier linking a claim citation to one source record and ultimately one small source piece. The reason it exists is: Human-readable source numbers can change with ordering; a stable ID preserves identity underneath.

### Layman’s explanation

The stable identifier linking a claim citation to one source record and ultimately one chunk. Human-readable source numbers can change with ordering; a stable ID preserves identity underneath.

### Technical explanation

It is assigned before generation and retained through response construction. Primary code anchors: OpenIntelligence/Core/Models/StructuredAnswer.swift.

### Why it is in this position

It is assigned before generation and retained through response construction.

## OI-0480. Evidence quote cap

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **Evidence quote cap** means: The response policy limiting stored evidence excerpts to roughly 240 characters. The reason it exists is: A concise quote is sufficient for inspection while bounding response size and accidental overexposure.

### Layman’s explanation

The response policy limiting stored evidence excerpts to roughly 240 characters. A concise quote is sufficient for inspection while bounding response size and accidental overexposure.

### Technical explanation

It is enforced when evidence records are added to StructuredAnswer. Primary code anchors: OpenIntelligence/Core/Models/StructuredAnswer.swift.

### Why it is in this position

It is enforced when evidence records are added to StructuredAnswer.

## OI-0481. Evidence record

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **Evidence record** means: A response-level source object containing evidence ID, page, quote, document name, and section path. The reason it exists is: Claims need a stable source representation independent of the transient RetrievedChunk object graph.

### Layman’s explanation

A response-level source object containing evidence ID, page, quote, document name, and section path. Claims need a stable source representation independent of the transient RetrievedChunk object graph.

### Technical explanation

It is created from selected evidence after verification and stored with the answer. Primary code anchors: OpenIntelligence/Core/Models/StructuredAnswer.swift.

### Why it is in this position

It is created from selected evidence after verification and stored with the answer.

## OI-0482. Evidence-thread persistence

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **Evidence-thread persistence** means: Saving user messages, answers, citations, and labels and facts into the selected local thread. The reason it exists is: A verified answer should remain reproducible and inspectable after the transient question task ends.

### Layman’s explanation

Saving user messages, answers, citations, and metadata into the selected local thread. A verified answer should remain reproducible and inspectable after the transient query task ends.

### Technical explanation

It occurs after response finalization and before the UI returns to idle. Primary code anchors: OpenIntelligence/Services/Storage/EvidenceThreadStore.swift; OpenIntelligence/Core/Models/EvidenceThread.swift.

### Why it is in this position

It occurs after response finalization and before the UI returns to idle.

## OI-0483. Execution-route metadata

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **Execution-route metadata** means: The user-facing path name, reason, policy version, and icon describing where synthesis ran. The reason it exists is: Route truth should come from execution evidence rather than the model picker.

### Layman’s explanation

The user-facing path name, reason, policy version, and icon describing where synthesis ran. Route truth should come from execution evidence rather than the model picker.

### Technical explanation

It is initialized during runtime resolution and finalized from the ModelExecutionReceipt. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/QueryRuntimeCoordinator.swift; OpenIntelligence/Services/RAG/Orchestration/ModelExecutionReceipt.swift.

### Why it is in this position

It is initialized during runtime resolution and finalized from the ModelExecutionReceipt.

## OI-0484. Grounded answer view

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **Grounded answer view** means: The response surface that presents answer text together with citations and source-grounding information. The reason it exists is: Grounding must be visible at the point the user reads the claim.

### Layman’s explanation

The response surface that presents answer text together with citations and source-grounding information. Grounding must be visible at the point the user reads the claim.

### Technical explanation

It consumes the verified structured response after the query completes or streams. Primary code anchors: OpenIntelligence/Features/Chat/Response/GroundedAnswerView.swift.

### Why it is in this position

It consumes the verified structured response after the query completes or streams.

## OI-0485. Hardware telemetry pulse

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **Hardware telemetry pulse** means: A short-lived signal indicating that OCR, number coordinates similarity, reranking, or another workload is active on the conceptual hardware display. The reason it exists is: It makes otherwise invisible local computation understandable to the user.

### Layman’s explanation

A short-lived signal indicating that OCR, vector similarity, reranking, or another workload is active on the conceptual hardware display. It makes otherwise invisible local computation understandable to the user.

### Technical explanation

It is emitted around compute-heavy stages and consumed by the Motherboard HUD. Primary code anchors: OpenIntelligence/Services/Infrastructure/Monitoring/HardwareTelemetryState.swift.

### Why it is in this position

It is emitted around compute-heavy stages and consumed by the Motherboard HUD.

## OI-0486. Inline citation

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **Inline citation** means: A source marker embedded next to the claim it supports inside the answer text. The reason it exists is: Claim-local citations reduce ambiguity compared with a detached source list.

### Layman’s explanation

A source marker embedded next to the claim it supports inside the answer text. Claim-local citations reduce ambiguity compared with a detached source list.

### Technical explanation

They are emitted by structured generation or inserted during answer sanitization and mapped to source chips. Primary code anchors: OpenIntelligence/Core/Models/StructuredAnswer.swift; OpenIntelligence/Features/Chat/Response/GroundedAnswerView.swift.

### Why it is in this position

They are emitted by structured generation or inserted during answer sanitization and mapped to source chips.

## OI-0487. Markdown renderer

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **Markdown renderer** means: The block-aware renderer for headings, lists, code, tables, emphasis, links, and horizontal rules in model responses. The reason it exists is: Technical answers lose usability or meaning if structured text is displayed as one plain string.

### Layman’s explanation

The block-aware renderer for headings, lists, code, tables, emphasis, links, and horizontal rules in model responses. Technical answers lose usability or meaning if structured text is displayed as one plain string.

### Technical explanation

It processes verified response text immediately before UI rendering. Primary code anchors: OpenIntelligence/Core/Extensions/MarkdownRenderer.swift.

### Why it is in this position

It processes verified response text immediately before UI rendering.

## OI-0488. OICitation

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **OICitation** means: The SDK citation value containing source name, optional page, and optional quote. The reason it exists is: External clients need a small stable citation contract independent of internal small source piece models.

### Layman’s explanation

The SDK citation value containing source name, optional page, and optional quote. External clients need a small stable citation contract independent of internal chunk models.

### Technical explanation

It is mapped from StructuredAnswer evidence after verification. Primary code anchors: OpenIntelligence/SDK/OpenIntelligenceEngine.swift.

### Why it is in this position

It is mapped from StructuredAnswer evidence after verification.

## OI-0489. OIEngine

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **OIEngine** means: The reusable public SDK facade for library management, ingestion, querying, streaming, progress, citations, diagnostics, and availability. The reason it exists is: It defines a stable product boundary above the internal RAGService mega-orchestrator.

### Layman’s explanation

The reusable public SDK facade for library management, ingestion, querying, streaming, progress, citations, diagnostics, and availability. It defines a stable product boundary above the internal RAGService mega-orchestrator.

### Technical explanation

External callers enter here, and it translates internal documents and responses into public value types. Primary code anchors: OpenIntelligence/SDK/OpenIntelligenceEngine.swift.

### Why it is in this position

External callers enter here, and it translates internal documents and responses into public value types.

## OI-0490. OIQueryProgressEvent

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **OIQueryProgressEvent** means: The SDK-safe version of live question progress with phase, title, detail, icon, counters, and confidence. The reason it exists is: A reusable engine must expose progress without requiring the app's SwiftUI types.

### Layman’s explanation

The SDK-safe version of live query progress with phase, title, detail, icon, counters, and confidence. A reusable engine must expose progress without requiring the app's SwiftUI types.

### Technical explanation

It is emitted during query execution through the progress callback. Primary code anchors: OpenIntelligence/SDK/OpenIntelligenceEngine.swift.

### Why it is in this position

It is emitted during query execution through the progress callback.

## OI-0491. OIQueryResult

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **OIQueryResult** means: The SDK result containing answer, citations, confidence, say there is not enough evidence state, warnings, model name, quality mode, reasoning trace, and diagnostics. The reason it exists is: SDK clients need the same source history and route truth available to the first-party UI.

### Layman’s explanation

The SDK result containing answer, citations, confidence, abstained state, warnings, model name, quality mode, reasoning trace, and diagnostics. SDK clients need the same provenance and route truth available to the first-party UI.

### Technical explanation

It is created from the verified internal response at the end of OIEngine.query. Primary code anchors: OpenIntelligence/SDK/OpenIntelligenceEngine.swift.

### Why it is in this position

It is created from the verified internal response at the end of OIEngine.query.

## OI-0492. Pipeline signpost

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **Pipeline signpost** means: A lightweight os-signpost marker around important pipeline intervals. The reason it exists is: Signposts allow Instruments to measure stage latency without parsing text logs.

### Layman’s explanation

A lightweight os-signpost marker around important pipeline intervals. Signposts allow Instruments to measure stage latency without parsing text logs.

### Technical explanation

They begin and end around extraction, retrieval, generation, and related operations. Primary code anchors: OpenIntelligence/Services/Infrastructure/Monitoring/PipelineSignposts.swift.

### Why it is in this position

They begin and end around extraction, retrieval, generation, and related operations.

## OI-0493. Pipeline trace

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **Pipeline trace** means: A chronological record of stage events, decisions, timing, route attempts, and selected evidence for one execution. The reason it exists is: A multi-stage engine cannot be debugged reliably from a final answer alone.

### Layman’s explanation

A chronological record of stage events, decisions, timing, route attempts, and selected evidence for one execution. A multi-stage engine cannot be debugged reliably from a final answer alone.

### Technical explanation

It is emitted during ingestion/query work and can be exported for inspection. Primary code anchors: OpenIntelligence/Features/Chat/Pipeline/PipelineTraceExporter.swift; scripts/pull_trace.sh.

### Why it is in this position

It is emitted during ingestion/query work and can be exported for inspection.

## OI-0494. PipelineTraceExporter

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **PipelineTraceExporter** means: The feature that serializes shareable pipeline evidence from instrumented question execution. The reason it exists is: Device-only failures require a reproducible artifact rather than a verbal report.

### Layman’s explanation

The feature that serializes shareable pipeline evidence from instrumented query execution. Device-only failures require a reproducible artifact rather than a verbal report.

### Technical explanation

It reads captured events after a run and produces an exportable trace. Primary code anchors: OpenIntelligence/Features/Chat/Pipeline/PipelineTraceExporter.swift.

### Why it is in this position

It reads captured events after a run and produces an exportable trace.

## OI-0495. RAG audit feature flags

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **RAG audit feature flags** means: Booleans recording whether rewrite, expansion, HyDE, iterative search, routing, summaries, parent search, corrective search, compression, graph packing, cascade, multi-number coordinates, or unlimited reasoning actually ran. The reason it exists is: Configured capability is not the same as executed capability.

### Layman’s explanation

Booleans recording whether rewrite, expansion, HyDE, iterative retrieval, routing, summaries, parent retrieval, corrective retrieval, compression, graph packing, cascade, multi-vector, or unlimited reasoning actually ran. Configured capability is not the same as executed capability.

### Technical explanation

They are toggled when stages run and included in the audit snapshot. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/RAGService.swift.

### Why it is in this position

They are toggled when stages run and included in the audit snapshot.

## OI-0496. RAGAuditSnapshot

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **RAGAuditSnapshot** means: The detailed per-question snapshot of provider, dimensions, small source piece policy, search configuration, score distribution, possible result counts, context budget, route, features, and recursive metrics. The reason it exists is: It preserves the exact operating conditions needed to reproduce or compare one question.

### Layman’s explanation

The detailed per-query snapshot of provider, dimensions, chunk policy, retrieval configuration, score distribution, candidate counts, context budget, route, features, and recursive metrics. It preserves the exact operating conditions needed to reproduce or compare one query.

### Technical explanation

It is assembled as stages complete and retained for diagnostics and evaluation. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/RAGService.swift.

### Why it is in this position

It is assembled as stages complete and retained for diagnostics and evaluation.

## OI-0497. RAGResponse

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **RAGResponse** means: The internal response object carrying answer text, retrieved small source pieces, confidence, abstention state, reasoning trace, labels and facts, and diagnostics. The reason it exists is: The engine needs a richer result than a string so verification, UI, SDK, and evaluation can agree on what happened.

### Layman’s explanation

The internal response object carrying answer text, retrieved chunks, confidence, abstention state, reasoning trace, metadata, and diagnostics. The engine needs a richer result than a string so verification, UI, SDK, and evaluation can agree on what happened.

### Technical explanation

It is assembled after generation and verification and converted into UI and SDK forms. Primary code anchors: OpenIntelligence/Core/Models/RAGQuery.swift; OpenIntelligence/Services/RAG/Orchestration/RAGService.swift.

### Why it is in this position

It is assembled after generation and verification and converted into UI and SDK forms.

## OI-0498. Refuse flag

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **Refuse flag** means: The explicit Boolean marking that the engine declined to provide a substantive answer. The reason it exists is: A refusal should be machine-readable rather than inferred from wording.

### Layman’s explanation

The explicit Boolean marking that the engine declined to provide a substantive answer. A refusal should be machine-readable rather than inferred from wording.

### Technical explanation

It is set during abstention and propagated through UI and SDK result types. Primary code anchors: OpenIntelligence/Core/Models/StructuredAnswer.swift.

### Why it is in this position

It is set during abstention and propagated through UI and SDK result types.

## OI-0499. Response metadata

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **Response metadata** means: The attached route, token budget, model, timing, search, quality-mode, and feature information describing how the answer was produced. The reason it exists is: The same answer text can have very different trust and cost implications depending on execution path and evidence.

### Layman’s explanation

The attached route, token budget, model, timing, retrieval, quality-mode, and feature information describing how the answer was produced. The same answer text can have very different trust and cost implications depending on execution path and evidence.

### Technical explanation

It is accumulated through the pipeline and committed beside the final answer. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/RAGService.swift; OpenIntelligence/Features/Chat/Response/ResponseDetailsView.swift.

### Why it is in this position

It is accumulated through the pipeline and committed beside the final answer.

## OI-0500. Response transformation

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **Response transformation** means: A post-answer operation such as rewriting, summarizing, or formatting the verified response through an approved service. The reason it exists is: Users may want a different presentation while preserving the underlying sourced result.

### Layman’s explanation

A post-answer operation such as rewriting, summarizing, or formatting the verified response through an approved service. Users may want a different presentation while preserving the underlying sourced result.

### Technical explanation

It occurs only after the primary answer exists and should not silently replace provenance. Primary code anchors: OpenIntelligence/Services/Agentic/ResponseTransformService.swift.

### Why it is in this position

It occurs only after the primary answer exists and should not silently replace provenance.

## OI-0501. Retrieval diagnostics

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **Retrieval diagnostics** means: Counts and timings for possible result, reranked small source pieces, context small source pieces, meaning map provider, warnings, and feature flags. The reason it exists is: A bad answer can originate in extraction, search, packing, or generation, and diagnostics narrow the failing stage.

### Layman’s explanation

Counts and timings for candidates, reranked chunks, context chunks, embedding provider, warnings, and feature flags. A bad answer can originate in extraction, retrieval, packing, or generation, and diagnostics narrow the failing stage.

### Technical explanation

They are captured during the query and displayed or returned after completion. Primary code anchors: OpenIntelligence/Core/Models/RAGStructuredResponse.swift; OpenIntelligence/SDK/OpenIntelligenceEngine.swift.

### Why it is in this position

They are captured during the query and displayed or returned after completion.

## OI-0502. RetrievalLogEntry

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **RetrievalLogEntry** means: A timestamped record of the question, active library, and small source pieces returned by search. The reason it exists is: It supports inspection of what the answer stage actually received.

### Layman’s explanation

A timestamped record of the query, active library, and chunks returned by retrieval. It supports inspection of what the answer stage actually received.

### Technical explanation

It is written after retrieval and before later response stages can obscure the original candidate set. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/RAGService.swift.

### Why it is in this position

It is written after retrieval and before later response stages can obscure the original candidate set.

## OI-0503. RetrievalTraceCollector

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **RetrievalTraceCollector** means: A per-question thread-safe collector of rank-ordered output at number coordinates, exact-word, fusion, boosted, possible result, rerank, and final stages. The reason it exists is: Counts cannot show whether the correct small source piece survived. Stage traces preserve identity and order for recall and ranking metrics.

### Layman’s explanation

A per-query thread-safe collector of rank-ordered output at vector, lexical, fusion, boosted, candidate, rerank, and final stages. Counts cannot show whether the correct chunk survived. Stage traces preserve identity and order for recall and ranking metrics.

### Technical explanation

It records each retrieval stage during evaluation and is discarded after scoring. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/RetrievalTraceCollector.swift.

### Why it is in this position

It records each retrieval stage during evaluation and is discarded after scoring.

## OI-0504. Source chip

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **Source chip** means: The tappable UI representation of a response evidence source. The reason it exists is: It lets the user inspect the actual document passage rather than trust the model or badge.

### Layman’s explanation

The tappable UI representation of a response evidence source. It lets the user inspect the actual document passage rather than trust the model or badge.

### Technical explanation

It is rendered after the StructuredAnswer citation namespace is finalized. Primary code anchors: OpenIntelligence/Features/Chat/Response/SourceChipsView.swift; OpenIntelligence/Features/Chat/Response/RetrievalSourcesTray.swift.

### Why it is in this position

It is rendered after the StructuredAnswer citation namespace is finalized.

## OI-0505. Structured answer type

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **Structured answer type** means: The lookup, table lookup, procedure, compare, summarize, investigate, compute, findings, or refused label stored with the answer. The reason it exists is: The response renderer and evaluator need to know the intended answer shape.

### Layman’s explanation

The lookup, table lookup, procedure, compare, summarize, investigate, compute, findings, or refused label stored with the answer. The response renderer and evaluator need to know the intended answer shape.

### Technical explanation

It is derived from AnswerIntent and committed with the StructuredAnswer. Primary code anchors: OpenIntelligence/Core/Models/StructuredAnswer.swift.

### Why it is in this position

It is derived from AnswerIntent and committed with the StructuredAnswer.

## OI-0506. StructuredAnswer

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **StructuredAnswer** means: The durable claim-oriented answer model containing refusal state, answer type, answer text, all-or-nothing claims, evidence records, missing information, and debug data. The reason it exists is: It is the source history contract between generation, verification, storage, and rendering.

### Layman’s explanation

The durable claim-oriented answer model containing refusal state, answer type, answer text, atomic claims, evidence records, missing information, and debug data. It is the provenance contract between generation, verification, storage, and rendering.

### Technical explanation

It is built from deterministic extraction or structured model generation and sanitized before display. Primary code anchors: OpenIntelligence/Core/Models/StructuredAnswer.swift.

### Why it is in this position

It is built from deterministic extraction or structured model generation and sanitized before display.

## OI-0507. TelemetryCenter

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **TelemetryCenter** means: The central emitter of typed runtime telemetry events for system, pipeline, and user-visible diagnostics. The reason it exists is: Structured telemetry keeps monitoring decoupled from UI and raw print statements.

### Layman’s explanation

The central emitter of typed runtime telemetry events for system, pipeline, and user-visible diagnostics. Structured telemetry keeps monitoring decoupled from UI and raw print statements.

### Technical explanation

Services emit events as work changes state; dashboards and traces consume them. Primary code anchors: OpenIntelligence/Services/Infrastructure/Monitoring/TelemetryCenter.swift.

### Why it is in this position

Services emit events as work changes state; dashboards and traces consume them.

## OI-0508. Thinking stream

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **Thinking stream** means: The live UI sequence of typed progress events during search, reasoning, generation, and verification. The reason it exists is: Long Deep Think and Maximum queries need observable progress without exposing private raw reasoning.

### Layman’s explanation

The live UI sequence of typed progress events during retrieval, reasoning, generation, and verification. Long Deep Think and Maximum queries need observable progress without exposing private raw reasoning.

### Technical explanation

It subscribes to ThinkingEvents until the response is finalized. Primary code anchors: OpenIntelligence/Features/Chat/Response/ThinkingStreamView.swift.

### Why it is in this position

It subscribes to ThinkingEvents until the response is finalized.

## OI-0509. Timing breakdown

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **Timing breakdown** means: The display and data model separating search, generation, and other stage durations. The reason it exists is: Total latency alone cannot show which subsystem should be optimized.

### Layman’s explanation

The display and data model separating retrieval, generation, and other stage durations. Total latency alone cannot show which subsystem should be optimized.

### Technical explanation

It is derived from query diagnostics after completion. Primary code anchors: OpenIntelligence/Features/Chat/Response/TimingBreakdownView.swift.

### Why it is in this position

It is derived from query diagnostics after completion.

## OI-0510. Token-budget metadata

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **Token-budget metadata** means: The total, prompt, evidence, generation, and remaining token counts attached to a response. The reason it exists is: It explains why some evidence was compressed or omitted and makes hard model constraints observable.

### Layman’s explanation

The total, prompt, evidence, generation, and remaining token counts attached to a response. It explains why some evidence was compressed or omitted and makes hard model constraints observable.

### Technical explanation

It is calculated before generation and finalized after actual packing. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/QueryRuntimeCoordinator.swift; OpenIntelligence/Features/Chat/Response/ContextUsageIndicator.swift.

### Why it is in this position

It is calculated before generation and finalized after actual packing.

## OI-0511. Unified metrics bar

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **Unified metrics bar** means: The response UI combining timing, model route, confidence, search, context, and source metrics. The reason it exists is: The user needs one place to understand the answer's operating evidence without opening raw diagnostics.

### Layman’s explanation

The response UI combining timing, model route, confidence, retrieval, context, and source metrics. The user needs one place to understand the answer's operating evidence without opening raw diagnostics.

### Technical explanation

It renders after metadata and verification are available. Primary code anchors: OpenIntelligence/Features/Chat/Response/UnifiedMetricsBar.swift.

### Why it is in this position

It renders after metadata and verification are available.

## OI-0512. Writing Tools integration

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a final evidence report and receipt. **Writing Tools integration** means: The local service exposing proofread, rewrite, and summarize operations for answer or user text. The reason it exists is: Presentation changes can use Apple intelligence features without entering the search pipeline again.

### Layman’s explanation

The local service exposing proofread, rewrite, and summarize operations for answer or user text. Presentation changes can use Apple intelligence features without entering the retrieval pipeline again.

### Technical explanation

It runs after answer generation as an explicit user action. Primary code anchors: OpenIntelligence/Services/Agentic/WritingToolsService.swift; OpenIntelligence/Features/Chat/Response/WritingToolsResultSheet.swift.

### Why it is in this position

It runs after answer generation as an explicit user action.

---

# 14. Evaluation, benchmarks, and quality measurement

**Section orientation:** Evaluation scores retrieval, ranking, citations, exact values, abstention, overflow, latency, and route honesty. Stage traces localize failure.

## OI-0513. Abstention accuracy

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Abstention accuracy** means: How often the engine correctly refuses unanswerable questions and answers answerable ones. The reason it exists is: Always answering and always refusing are both poor systems; the decision boundary must be measured.

### Layman’s explanation

How often the engine correctly refuses unanswerable questions and answers answerable ones. Always answering and always refusing are both poor systems; the decision boundary must be measured.

### Technical explanation

It is calculated across labeled answerable and unanswerable cases. Primary code anchors: OpenIntelligence/Services/Evaluation/RAGEvalMetrics.swift.

### Why it is in this position

It is calculated across labeled answerable and unanswerable cases.

## OI-0514. Answer accuracy

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Answer accuracy** means: The proportion of cases judged correct under the dataset scoring rule. The reason it exists is: It gives a headline outcome but must be decomposed because search, synthesis, and errors can produce the same aggregate.

### Layman’s explanation

The proportion of cases judged correct under the dataset scoring rule. It gives a headline outcome but must be decomposed because retrieval, synthesis, and errors can produce the same aggregate.

### Technical explanation

It is reported after a complete benchmark run. Primary code anchors: OpenIntelligence/Services/Evaluation/RAGEvalMetrics.swift; Docs/EVALS.md.

### Why it is in this position

It is reported after a complete benchmark run.

## OI-0515. Benchmark baseline

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Benchmark baseline** means: A frozen reference result and configuration against which later runs are compared. The reason it exists is: Without a baseline, code changes can alter quality while individual runs still look plausible.

### Layman’s explanation

A frozen reference result and configuration against which later runs are compared. Without a baseline, code changes can alter quality while individual runs still look plausible.

### Technical explanation

It is created from a clean versioned run and loaded during regression comparison. Primary code anchors: Benchmarks/baselines/README.md.

### Why it is in this position

It is created from a clean versioned run and loaded during regression comparison.

## OI-0516. Benchmark ledger

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Benchmark ledger** means: The chronological record of benchmark runs, versions, configurations, and findings. The reason it exists is: Evaluation conclusions need source history and should survive the machine that produced them.

### Layman’s explanation

The chronological record of benchmark runs, versions, configurations, and findings. Evaluation conclusions need provenance and should survive the machine that produced them.

### Technical explanation

It is appended after runs and used to interpret progression. Primary code anchors: BenchmarkRuns/LEDGER.md; BenchmarkRuns/PROGRESSION.md.

### Why it is in this position

It is appended after runs and used to interpret progression.

## OI-0517. Completed-route attestation

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Completed-route attestation** means: The invariant that the target claimed as completed appears in the attempt chain with an attesting success or allowed partial outcome. The reason it exists is: A UI cannot truthfully say PCC or on-device completed based only on the intended plan.

### Layman’s explanation

The invariant that the target claimed as completed appears in the attempt chain with an attesting success or allowed partial outcome. A UI cannot truthfully say PCC or on-device completed based only on the intended plan.

### Technical explanation

It is checked against ModelExecutionReceipt after execution. Primary code anchors: OpenIntelligence/Services/Evaluation/RouteEvalMetrics.swift.

### Why it is in this position

It is checked against ModelExecutionReceipt after execution.

## OI-0518. Credited relevance

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Credited relevance** means: The evaluation rule mapping retrieved small source pieces to ground-truth evidence with exact or accepted equivalence criteria. The reason it exists is: small source piece boundaries and parent expansion can produce evidence that is relevant without sharing the exact original small source piece ID.

### Layman’s explanation

The evaluation rule mapping retrieved chunks to ground-truth evidence with exact or accepted equivalence criteria. Chunk boundaries and parent expansion can produce evidence that is relevant without sharing the exact original chunk ID.

### Technical explanation

It is applied before retrieval metrics are calculated. Primary code anchors: OpenIntelligence/Services/Evaluation/RetrievalStageMetrics.swift.

### Why it is in this position

It is applied before retrieval metrics are calculated.

## OI-0519. Distractor document

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Distractor document** means: An irrelevant or partially related document included with the target source during evaluation. The reason it exists is: search quality cannot be measured if the document collection contains only the answer document.

### Layman’s explanation

An irrelevant or partially related document included with the target source during evaluation. Retrieval quality cannot be measured if the corpus contains only the answer document.

### Technical explanation

Distractors are ingested beside the target before each benchmark query. Primary code anchors: Benchmarks/ResearchFixtures/qasper_external_v1/README.md.

### Why it is in this position

Distractors are ingested beside the target before each benchmark query.

## OI-0520. Error rate

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Error rate** means: The proportion of cases that terminate through an execution, timeout, parsing, or infrastructure error rather than a valid answer or abstention. The reason it exists is: Infrastructure failures should not be hidden inside answer-quality metrics.

### Layman’s explanation

The proportion of cases that terminate through an execution, timeout, parsing, or infrastructure error rather than a valid answer or abstention. Infrastructure failures should not be hidden inside answer-quality metrics.

### Technical explanation

It is counted separately during the evaluation run. Primary code anchors: OpenIntelligence/Services/Evaluation/RAGEvalMetrics.swift.

### Why it is in this position

It is counted separately during the evaluation run.

## OI-0521. Evaluation case

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Evaluation case** means: One question with document collection scope, expected answer or evidence, answerability, and scoring labels and facts. The reason it exists is: Quality must be measured against explicit ground truth rather than selected anecdotes.

### Layman’s explanation

One question with corpus scope, expected answer or evidence, answerability, and scoring metadata. Quality must be measured against explicit ground truth rather than selected anecdotes.

### Technical explanation

It is loaded before a benchmark query and scored after the result completes. Primary code anchors: OpenIntelligence/Services/Evaluation/RAGEvalCase.swift.

### Why it is in this position

It is loaded before a benchmark query and scored after the result completes.

## OI-0522. Evaluation dataset

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Evaluation dataset** means: A versioned collection of evaluation cases with schema validation and attribution. The reason it exists is: A stable document collection allows before-and-after comparisons and prevents cherry-picking.

### Layman’s explanation

A versioned collection of evaluation cases with schema validation and attribution. A stable corpus allows before-and-after comparisons and prevents cherry-picking.

### Technical explanation

It is loaded by the evaluation runner before executing cases. Primary code anchors: OpenIntelligence/Services/Evaluation/RAGEvalDataset.swift.

### Why it is in this position

It is loaded by the evaluation runner before executing cases.

## OI-0523. Evaluation report writer

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Evaluation report writer** means: The component that serializes metrics, case outcomes, configuration, and warnings into a durable report. The reason it exists is: A console summary is insufficient for later audit and comparison.

### Layman’s explanation

The component that serializes metrics, case outcomes, configuration, and warnings into a durable report. A console summary is insufficient for later audit and comparison.

### Technical explanation

It runs after the evaluator aggregates results. Primary code anchors: OpenIntelligence/Services/Evaluation/RAGEvalReportWriter.swift.

### Why it is in this position

It runs after the evaluator aggregates results.

## OI-0524. Evidence level

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Evidence level** means: A label distinguishing code-verified, test-verified, simulator-verified, device-verified, measured, inferred, or unverified claims. The reason it exists is: A source file proves implementation, not necessarily runtime behavior or performance.

### Layman’s explanation

A label distinguishing code-verified, test-verified, simulator-verified, device-verified, measured, inferred, or unverified claims. A source file proves implementation, not necessarily runtime behavior or performance.

### Technical explanation

It is attached to documentation and audit conclusions rather than executed in the answer pipeline. Primary code anchors: Docs/HOW_IT_WORKS.md; Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md.

### Why it is in this position

It is attached to documentation and audit conclusions rather than executed in the answer pipeline.

## OI-0525. Exact match

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Exact match** means: A strict answer metric indicating whether the put into a consistent form output exactly equals the expected answer. The reason it exists is: It is useful for short factual lookups where paraphrase should not change the value.

### Layman’s explanation

A strict answer metric indicating whether the normalized output exactly equals the expected answer. It is useful for short factual lookups where paraphrase should not change the value.

### Technical explanation

It is calculated after each evaluation answer and averaged across compatible cases. Primary code anchors: OpenIntelligence/Services/Evaluation/RAGEvalMetrics.swift.

### Why it is in this position

It is calculated after each evaluation answer and averaged across compatible cases.

## OI-0526. Exact sign test

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Exact sign test** means: A nonparametric test of whether wins and losses between two paired systems are symmetric, ignoring ties. The reason it exists is: It quantifies whether one search arm consistently beats another without assuming normally distributed metric differences.

### Layman’s explanation

A nonparametric test of whether wins and losses between two paired systems are symmetric, ignoring ties. It quantifies whether one retrieval arm consistently beats another without assuming normally distributed metric differences.

### Technical explanation

It is applied to paired benchmark outcomes such as lexical versus fusion rank. Primary code anchors: Docs/EVALS.md.

### Why it is in this position

It is applied to paired benchmark outcomes such as lexical versus fusion rank.

## OI-0527. Fail-closed route invariant

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Fail-closed route invariant** means: The requirement that denied consent and unavailable, exhausted, unsupported, or unknown cloud quota do not complete on PCC. The reason it exists is: Authorization uncertainty must never become a cloud attempt.

### Layman’s explanation

The requirement that denied consent and unavailable, exhausted, unsupported, or unknown cloud quota do not complete on PCC. Authorization uncertainty must never become a cloud attempt.

### Technical explanation

It is evaluated over route test cases and production receipts. Primary code anchors: OpenIntelligence/Services/Evaluation/RouteEvalMetrics.swift.

### Why it is in this position

It is evaluated over route test cases and production receipts.

## OI-0528. Fallback attribution invariant

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Fallback attribution invariant** means: The requirement that a completed target different from the intended target has an explicit fallback reason and attempt history. The reason it exists is: Silent fallback makes route badges and debugging misleading.

### Layman’s explanation

The requirement that a completed target different from the intended target has an explicit fallback reason and attempt history. Silent fallback makes route badges and debugging misleading.

### Technical explanation

It is checked after receipt creation. Primary code anchors: OpenIntelligence/Services/Evaluation/RouteEvalMetrics.swift.

### Why it is in this position

It is checked after receipt creation.

## OI-0529. Hallucination rate

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Hallucination rate** means: The proportion of answers containing unsupported material under the evaluation definition. The reason it exists is: A system can improve exact match by answering more aggressively while becoming less safe.

### Layman’s explanation

The proportion of answers containing unsupported material under the evaluation definition. A system can improve exact match by answering more aggressively while becoming less safe.

### Technical explanation

It is scored from answer and evidence results and reported beside accuracy. Primary code anchors: OpenIntelligence/Services/Evaluation/RAGEvalMetrics.swift.

### Why it is in this position

It is scored from answer and evidence results and reported beside accuracy.

## OI-0530. Mean reciprocal rank (MRR)

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Mean reciprocal rank (MRR)** means: The average reciprocal position of the first relevant result. The reason it exists is: It captures how quickly the pipeline surfaces at least one usable evidence item.

### Layman’s explanation

The average reciprocal position of the first relevant result. It captures how quickly the pipeline surfaces at least one usable evidence item.

### Technical explanation

It is calculated from rank-ordered stage traces and compared across retrieval arms. Primary code anchors: OpenIntelligence/Services/Evaluation/RetrievalStageMetrics.swift.

### Why it is in this position

It is calculated from rank-ordered stage traces and compared across retrieval arms.

## OI-0531. Normalized discounted cumulative gain (nDCG)

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Normalized discounted cumulative gain (nDCG)** means: A ranking metric that rewards placing highly relevant items early while supporting graded relevance. The reason it exists is: It evaluates more of the ranking than first-hit MRR and respects relevance strength.

### Layman’s explanation

A ranking metric that rewards placing highly relevant items early while supporting graded relevance. It evaluates more of the ranking than first-hit MRR and respects relevance strength.

### Technical explanation

It is calculated for stage outputs with graded ground truth. Primary code anchors: OpenIntelligence/Services/Evaluation/RetrievalStageMetrics.swift.

### Why it is in this position

It is calculated for stage outputs with graded ground truth.

## OI-0532. Paired comparison

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Paired comparison** means: Comparing two search configurations on the same cases rather than only comparing aggregate means. The reason it exists is: Per-case wins, losses, and ties show whether an apparent improvement is consistent or driven by a few outliers.

### Layman’s explanation

Comparing two retrieval configurations on the same cases rather than only comparing aggregate means. Per-case wins, losses, and ties show whether an apparent improvement is consistent or driven by a few outliers.

### Technical explanation

It is calculated after both systems produce aligned case results. Primary code anchors: scripts/compare_benchmark_runs.py; Docs/EVALS.md.

### Why it is in this position

It is calculated after both systems produce aligned case results.

## OI-0533. Physical-device verification

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Physical-device verification** means: Testing user-visible and hardware-dependent behavior on a real supported device rather than only in the simulator. The reason it exists is: Apple Intelligence, thermal behavior, Neural Engine scheduling, PCC, background processing, and memory pressure differ materially from simulation.

### Layman’s explanation

Testing user-visible and hardware-dependent behavior on a real supported device rather than only in the simulator. Apple Intelligence, thermal behavior, Neural Engine scheduling, PCC, background processing, and memory pressure differ materially from simulation.

### Technical explanation

It is the final evidence tier after build, unit, and simulator validation. Primary code anchors: scripts/run_device_tests.sh; Docs/AuditArtifacts/Implementation.

### Why it is in this position

It is the final evidence tier after build, unit, and simulator validation.

## OI-0534. Precision at k

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Precision at k** means: The fraction of the top k results that are relevant. The reason it exists is: High recall with mostly irrelevant evidence wastes context and can confuse generation.

### Layman’s explanation

The fraction of the top k results that are relevant. High recall with mostly irrelevant evidence wastes context and can confuse generation.

### Technical explanation

It is calculated per retrieval stage from trace identities. Primary code anchors: OpenIntelligence/Services/Evaluation/RetrievalStageMetrics.swift.

### Why it is in this position

It is calculated per retrieval stage from trace identities.

## OI-0535. QASPER fixture

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **QASPER fixture** means: The external research-paper question-answering benchmark adapted into local Markdown fixtures with distractor papers. The reason it exists is: Externally authored questions reduce the self-authored-fixture bias that made earlier tests too easy.

### Layman’s explanation

The external research-paper question-answering benchmark adapted into local Markdown fixtures with distractor papers. Externally authored questions reduce the self-authored-fixture bias that made earlier tests too easy.

### Technical explanation

It is prepared before benchmarking and queried through the normal engine. Primary code anchors: Benchmarks/ResearchFixtures/qasper_external_v1/README.md; Benchmarks/rag_eval_qasper_v1.jsonl.

### Why it is in this position

It is prepared before benchmarking and queried through the normal engine.

## OI-0536. Quality matrix

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Quality matrix** means: A batch evaluation across modes, routes, or configurations that produces comparable rows and columns. The reason it exists is: Many quality regressions are interactions rather than one isolated setting.

### Layman’s explanation

A batch evaluation across modes, routes, or configurations that produces comparable rows and columns. Many quality regressions are interactions rather than one isolated setting.

### Technical explanation

It is executed by the quality-matrix script and stored under audit artifacts. Primary code anchors: scripts/run_quality_matrix.py; Docs/AuditArtifacts/Benchmarks.

### Why it is in this position

It is executed by the quality-matrix script and stored under audit artifacts.

## OI-0537. RAGEvalRunner

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **RAGEvalRunner** means: The harness that ingests fixtures, runs queries, captures outputs and stage traces, and aggregates metrics. The reason it exists is: Manual testing cannot consistently measure hundreds of stage-level outcomes.

### Layman’s explanation

The harness that ingests fixtures, runs queries, captures outputs and stage traces, and aggregates metrics. Manual testing cannot consistently measure hundreds of stage-level outcomes.

### Technical explanation

It orchestrates evaluation outside normal user queries and writes reports afterward. Primary code anchors: OpenIntelligence/Services/Evaluation/RAGEvalRunner.swift.

### Why it is in this position

It orchestrates evaluation outside normal user queries and writes reports afterward.

## OI-0538. Recall at k

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Recall at k** means: The fraction of relevant evidence items present in the top k results. The reason it exists is: It measures whether the search stage found the needed small source pieces before later ranking or generation.

### Layman’s explanation

The fraction of relevant evidence items present in the top k results. It measures whether the retrieval stage found the needed chunks before later ranking or generation.

### Technical explanation

It is calculated independently for vector, lexical, fusion, rerank, and final traces. Primary code anchors: OpenIntelligence/Services/Evaluation/RetrievalStageMetrics.swift.

### Why it is in this position

It is calculated independently for vector, lexical, fusion, rerank, and final traces.

## OI-0539. Route invariant

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Route invariant** means: A Boolean property that must hold for execution receipts, such as completed route attempted, fallback attributed, and denied/unknown cloud failing closed. The reason it exists is: Routing truth is a correctness property separate from answer content.

### Layman’s explanation

A Boolean property that must hold for execution receipts, such as completed route attempted, fallback attributed, and denied/unknown cloud failing closed. Routing truth is a correctness property separate from answer content.

### Technical explanation

It is evaluated after each receipt in route benchmarks and tests. Primary code anchors: OpenIntelligence/Services/Evaluation/RouteEvalMetrics.swift.

### Why it is in this position

It is evaluated after each receipt in route benchmarks and tests.

## OI-0540. Stage survival

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Stage survival** means: Whether the relevant small source piece remains present from number coordinates/exact-word through fusion, boosts, truncation, reranking, and final search. The reason it exists is: A stage can preserve counts while dropping the only correct evidence item.

### Layman’s explanation

Whether the relevant chunk remains present from vector/lexical through fusion, boosts, truncation, reranking, and final retrieval. A stage can preserve counts while dropping the only correct evidence item.

### Technical explanation

It is derived by comparing RetrievalTraceCollector outputs in pipeline order. Primary code anchors: OpenIntelligence/Services/RAG/Retrieval/RetrievalTraceCollector.swift; OpenIntelligence/Services/Evaluation/RetrievalStageMetrics.swift.

### Why it is in this position

It is derived by comparing RetrievalTraceCollector outputs in pipeline order.

## OI-0541. Synthetic fixture bias

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Synthetic fixture bias** means: The tendency of tests authored alongside their expected questions to flatter the same assumptions and vocabulary built into the engine. The reason it exists is: A perfect score on self-authored examples can hide weak generalization and abstention.

### Layman’s explanation

The tendency of tests authored alongside their expected questions to flatter the same assumptions and vocabulary built into the engine. A perfect score on self-authored examples can hide weak generalization and abstention.

### Technical explanation

It is considered when interpreting benchmark evidence and motivates external fixtures. Primary code anchors: Docs/EVALS.md.

### Why it is in this position

It is considered when interpreting benchmark evidence and motivates external fixtures.

## OI-0542. Tiny research suite

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Tiny research suite** means: A compact synthetic suite covering exact lookup, missing information, multi-hop search, rank search, and lost-in-the-middle behavior. The reason it exists is: Small rule-based and repeatable cases are fast regression tests even though they cannot estimate real-world accuracy.

### Layman’s explanation

A compact synthetic suite covering exact lookup, missing information, multi-hop retrieval, rank retrieval, and lost-in-the-middle behavior. Small deterministic cases are fast regression tests even though they cannot estimate real-world accuracy.

### Technical explanation

It runs in development and CI before larger external evaluations. Primary code anchors: Benchmarks/ResearchFixtures/tiny_research_suite/README.md.

### Why it is in this position

It runs in development and CI before larger external evaluations.

## OI-0543. Token F1

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a test track and scoreboard. **Token F1** means: The harmonic mean of token-level answer precision and recall against the expected answer. The reason it exists is: It gives partial credit to substantively correct answers that differ in wording.

### Layman’s explanation

The harmonic mean of token-level answer precision and recall against the expected answer. It gives partial credit to substantively correct answers that differ in wording.

### Technical explanation

It is calculated after normalization for each answer and aggregated. Primary code anchors: OpenIntelligence/Services/Evaluation/RAGEvalMetrics.swift.

### Why it is in this position

It is calculated after normalization for each answer and aggregated.

---

# 15. Device adaptation, compute, background work, sync, and product limits

**Section orientation:** Runtime services adapt to hardware, thermal state, memory, background limits, sync state, entitlement limits, and user settings.

## OI-0544. AdaptivePipelineOptimizer

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **AdaptivePipelineOptimizer** means: The runtime policy that adjusts enhancement features, possible result limits, context, rerank batch, agentic steps, cooldowns, timeout, thresholds, and MMR from device state and question complexity. The reason it exists is: The engine should degrade gracefully under critical heat or memory pressure instead of crashing or silently returning partial work.

### Layman’s explanation

The runtime policy that adjusts enhancement features, candidate limits, context, rerank batch, agentic steps, cooldowns, timeout, thresholds, and MMR from device state and query complexity. The engine should degrade gracefully under critical heat or memory pressure instead of crashing or silently returning partial work.

### Technical explanation

It resolves a per-query configuration after query complexity and current device state are known. Primary code anchors: OpenIntelligence/Services/Infrastructure/Optimization/AdaptivePipelineOptimizer.swift.

### Why it is in this position

It resolves a per-query configuration after query complexity and current device state are known.

## OI-0545. Balanced optimization level

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Balanced optimization level** means: A reduced configuration that disables some repeated work and lowers possible result/context limits. The reason it exists is: It trades a modest amount of quality work for sustained responsiveness.

### Layman’s explanation

A reduced configuration that disables some repeated work and lowers candidate/context limits. It trades a modest amount of quality work for sustained responsiveness.

### Technical explanation

It is applied when selected by user or policy before query execution. Primary code anchors: OpenIntelligence/Services/Infrastructure/Optimization/AdaptivePipelineOptimizer.swift.

### Why it is in this position

It is applied when selected by user or policy before query execution.

## OI-0546. Balanced profile

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Balanced profile** means: The default profile allowing GPU for indexing and page rendering while keeping answer generation primarily on CPU plus Neural Engine policy. The reason it exists is: It captures most throughput gains without enabling every high-heat path.

### Layman’s explanation

The default profile allowing GPU for indexing and page rendering while keeping answer generation primarily on CPU plus Neural Engine policy. It captures most throughput gains without enabling every high-heat path.

### Technical explanation

It is applied during device execution-envelope resolution. Primary code anchors: OpenIntelligence/Services/Infrastructure/Monitoring/DeviceCapabilityService.swift.

### Why it is in this position

It is applied during device execution-envelope resolution.

## OI-0547. BGTaskScheduler maintenance

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **BGTaskScheduler maintenance** means: Scheduled background tasks for index maintenance, Spotlight reindexing, and app refresh. The reason it exists is: Search artifacts and OS integrations need upkeep that should not block foreground use.

### Layman’s explanation

Scheduled background tasks for index maintenance, Spotlight reindexing, and app refresh. Search artifacts and OS integrations need upkeep that should not block foreground use.

### Technical explanation

They are registered at app launch and submitted under power/network constraints. Primary code anchors: OpenIntelligence/Services/Infrastructure/Background/BackgroundTaskService.swift.

### Why it is in this position

They are registered at app launch and submitted under power/network constraints.

## OI-0548. BNNSGraphService

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **BNNSGraphService** means: The Accelerate-based service for batch put into a consistent form, matrix cosine similarity, softmax, RRF arithmetic, and pairwise similarity. The reason it exists is: It centralizes optimized number coordinates math and provides a CPU/Apple-Silicon path below or beside Metal.

### Layman’s explanation

The Accelerate-based service for batch normalization, matrix cosine similarity, softmax, RRF arithmetic, and pairwise similarity. It centralizes optimized vector math and provides a CPU/Apple-Silicon path below or beside Metal.

### Technical explanation

It is invoked during embedding normalization, dense search, reranking normalization, fusion, and MMR. Primary code anchors: OpenIntelligence/Services/Infrastructure/Compute/BNNSGraphService.swift.

### Why it is in this position

It is invoked during embedding normalization, dense search, reranking normalization, fusion, and MMR.

## OI-0549. Continued ingestion task

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Continued ingestion task** means: A BGContinuedProcessingTask carrying user-started document ingestion through background execution. The reason it exists is: Large imports should survive app switching and preserve visible progress.

### Layman’s explanation

A BGContinuedProcessingTask carrying user-started document ingestion through background execution. Large imports should survive app switching and preserve visible progress.

### Technical explanation

It is submitted when ingestion starts and invokes the same persisted queue runner. Primary code anchors: OpenIntelligence/Services/Infrastructure/Background/BackgroundTaskService.swift.

### Why it is in this position

It is submitted when ingestion starts and invokes the same persisted queue runner.

## OI-0550. Continued query task

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Continued query task** means: A BGContinuedProcessingTask carrying a long Deep Think or Maximum question after the app backgrounds. The reason it exists is: A long answer should not disappear simply because the user leaves the app.

### Layman’s explanation

A BGContinuedProcessingTask carrying a long Deep Think or Maximum query after the app backgrounds. A long answer should not disappear simply because the user leaves the app.

### Technical explanation

It is submitted after query initiation and invokes the active query continuation. Primary code anchors: OpenIntelligence/Services/Infrastructure/Background/BackgroundTaskService.swift.

### Why it is in this position

It is submitted after query initiation and invokes the active query continuation.

## OI-0551. Core ML compute units

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Core ML compute units** means: The allowed hardware set such as CPU and Neural Engine or all units for a model invocation. The reason it exists is: It expresses execution preference while Apple retains the final scheduling decision.

### Layman’s explanation

The allowed hardware set such as CPU and Neural Engine or all units for a model invocation. It expresses execution preference while Apple retains the final scheduling decision.

### Technical explanation

It is derived from GPU execution profile and provider policy before Core ML model loading or prediction. Primary code anchors: OpenIntelligence/Services/Infrastructure/Monitoring/DeviceCapabilityService.swift; OpenIntelligence/Services/Embedding/Providers/CoreMLSentenceEmbeddingProvider.swift.

### Why it is in this position

It is derived from GPU execution profile and provider policy before Core ML model loading or prediction.

## OI-0552. Debounced workspace change

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Debounced workspace change** means: Waiting briefly, about two seconds, to combine rapid local-change notifications into one sync pass. The reason it exists is: Ingestion writes many related artifacts and should not launch a full merge for each one.

### Layman’s explanation

Waiting briefly, about two seconds, to combine rapid local-change notifications into one sync pass. Ingestion writes many related artifacts and should not launch a full merge for each one.

### Technical explanation

It occurs between local change notification and WorkspaceSyncService reconfiguration. Primary code anchors: OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift.

### Why it is in this position

It occurs between local change notification and WorkspaceSyncService reconfiguration.

## OI-0553. Device capability tier

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Device capability tier** means: The baseline, enhanced, advanced, ultra-advanced, or unsupported classification derived from hardware identity. The reason it exists is: The tier provides a stable policy input for possible result breadth, concurrency, and agentic limits.

### Layman’s explanation

The baseline, enhanced, advanced, ultra-advanced, or unsupported classification derived from hardware identity. The tier provides a stable policy input for candidate breadth, concurrency, and agentic limits.

### Technical explanation

It is detected at launch and consumed whenever adaptive configuration is resolved. Primary code anchors: OpenIntelligence/Services/Infrastructure/Monitoring/DeviceCapabilityService.swift.

### Why it is in this position

It is detected at launch and consumed whenever adaptive configuration is resolved.

## OI-0554. DeviceCapabilityService

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **DeviceCapabilityService** means: The central detector and policy source for chip, device tier, form factor, memory, Metal limits, batch sizes, concurrency, and GPU profile. The reason it exists is: One hardcoded pipeline configuration would underuse Macs and destabilize thermally constrained phones.

### Layman’s explanation

The central detector and policy source for chip, device tier, form factor, memory, Metal limits, batch sizes, concurrency, and GPU profile. One hardcoded pipeline configuration would underuse Macs and destabilize thermally constrained phones.

### Technical explanation

It initializes at runtime and supplies execution envelopes to ingestion, retrieval, and background policy. Primary code anchors: OpenIntelligence/Services/Infrastructure/Monitoring/DeviceCapabilityService.swift.

### Why it is in this position

It initializes at runtime and supplies execution envelopes to ingestion, retrieval, and background policy.

## OI-0555. Efficiency profile

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Efficiency profile** means: The profile keeping models on CPU plus Neural Engine and avoiding GPU number coordinates/render work where possible. The reason it exists is: It minimizes heat and contention for sustained battery use.

### Layman’s explanation

The profile keeping models on CPU plus Neural Engine and avoiding GPU vector/render work where possible. It minimizes heat and contention for sustained battery use.

### Technical explanation

It is applied before compute routes are chosen. Primary code anchors: OpenIntelligence/Services/Infrastructure/Monitoring/DeviceCapabilityService.swift.

### Why it is in this position

It is applied before compute routes are chosen.

## OI-0556. Efficient optimization level

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Efficient optimization level** means: A power-saving configuration that disables HyDE, compression, and iterative search and reduces batch/possible result limits. The reason it exists is: Expensive auxiliary model calls are the first features to remove under resource pressure.

### Layman’s explanation

A power-saving configuration that disables HyDE, compression, and iterative retrieval and reduces batch/candidate limits. Expensive auxiliary model calls are the first features to remove under resource pressure.

### Technical explanation

It is applied before query stages are authorized. Primary code anchors: OpenIntelligence/Services/Infrastructure/Optimization/AdaptivePipelineOptimizer.swift.

### Why it is in this position

It is applied before query stages are authorized.

## OI-0557. Full optimization level

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Full optimization level** means: The runtime state with the device-tier base configuration and all permitted quality features enabled. The reason it exists is: It maximizes quality when thermal and memory conditions allow.

### Layman’s explanation

The runtime state with the device-tier base configuration and all permitted quality features enabled. It maximizes quality when thermal and memory conditions allow.

### Technical explanation

It is normally selected except under critical constraints or an explicit override. Primary code anchors: OpenIntelligence/Services/Infrastructure/Optimization/AdaptivePipelineOptimizer.swift.

### Why it is in this position

It is normally selected except under critical constraints or an explicit override.

## OI-0558. GPU execution profile

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **GPU execution profile** means: The user policy Efficiency, Balanced, Performance, or Maximum controlling which workloads may use GPU and at what concurrency. The reason it exists is: A discrete policy communicates real behavior without implying an exact utilization percentage the app cannot guarantee.

### Layman’s explanation

The user policy Efficiency, Balanced, Performance, or Maximum controlling which workloads may use GPU and at what concurrency. A discrete policy communicates real behavior without implying an exact utilization percentage the app cannot guarantee.

### Technical explanation

It is resolved before rendering, model inference, and large vector operations. Primary code anchors: OpenIntelligence/Services/Infrastructure/Monitoring/DeviceCapabilityService.swift.

### Why it is in this position

It is resolved before rendering, model inference, and large vector operations.

## OI-0559. GPUComputeService

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **GPUComputeService** means: The Metal service providing batch cosine similarity, put into a consistent form, and MMR diversity kernels with CPU fallback. The reason it exists is: Large number coordinates batches are highly parallel and can benefit from custom compute kernels.

### Layman’s explanation

The Metal service providing batch cosine similarity, normalization, and MMR diversity kernels with CPU fallback. Large vector batches are highly parallel and can benefit from custom compute kernels.

### Technical explanation

It is called by vector and diversity operations after device-policy gates pass. Primary code anchors: OpenIntelligence/Services/Infrastructure/Compute/GPUComputeService.swift.

### Why it is in this position

It is called by vector and diversity operations after device-policy gates pass.

## OI-0560. Hardware execution envelope

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Hardware execution envelope** means: The resolved snapshot of chip, memory, Metal limits, compute route, OCR concurrency, render slots, meaning map batch, number coordinates batch, and GPU concurrency. The reason it exists is: Pipeline decisions need the concrete device constraints that produced them.

### Layman’s explanation

The resolved snapshot of chip, memory, Metal limits, compute route, OCR concurrency, render slots, embedding batch, vector batch, and GPU concurrency. Pipeline decisions need the concrete device constraints that produced them.

### Technical explanation

It is built from DeviceCapabilityService and displayed or consumed before heavy work. Primary code anchors: OpenIntelligence/Services/Infrastructure/Monitoring/DeviceCapabilityService.swift.

### Why it is in this position

It is built from DeviceCapabilityService and displayed or consumed before heavy work.

## OI-0561. iCloud-shared sync mode

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **iCloud-shared sync mode** means: A per-library policy that mirrors supported workspace artifacts through the app's iCloud container. The reason it exists is: It enables multi-device continuity while retaining explicit library-level control.

### Layman’s explanation

A per-library policy that mirrors supported workspace artifacts through the app's iCloud container. It enables multi-device continuity while retaining explicit library-level control.

### Technical explanation

It is set on the container and interpreted by WorkspaceSyncService after local commits. Primary code anchors: OpenIntelligence/Core/Models/KnowledgeContainer.swift; OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift.

### Why it is in this position

It is set on the container and interpreted by WorkspaceSyncService after local commits.

## OI-0562. Ingestion Live Activity

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Ingestion Live Activity** means: The lock-screen or Dynamic Island progress representation for active ingestion. The reason it exists is: Long imports benefit from durable progress without reopening the app.

### Layman’s explanation

The lock-screen or Dynamic Island progress representation for active ingestion. Long imports benefit from durable progress without reopening the app.

### Technical explanation

It subscribes to ingestion status and ends on completion, cancellation, or failure. Primary code anchors: OpenIntelligence/Services/Infrastructure/Background/IngestionLiveActivityService.swift; OpenIntelligenceLiveActivities/IngestionLiveActivityWidget.swift.

### Why it is in this position

It subscribes to ingestion status and ends on completion, cancellation, or failure.

## OI-0563. Local-only sync mode

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Local-only sync mode** means: A library policy that keeps its artifacts in the device application-support workspace and excludes them from iCloud sharing. The reason it exists is: Some users or corpora require strict device locality independent of general app settings.

### Layman’s explanation

A library policy that keeps its artifacts in the device application-support workspace and excludes them from iCloud sharing. Some users or corpora require strict device locality independent of general app settings.

### Technical explanation

It is set on the KnowledgeContainer before storage and sync routing. Primary code anchors: OpenIntelligence/Core/Models/KnowledgeContainer.swift; OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift.

### Why it is in this position

It is set on the KnowledgeContainer before storage and sync routing.

## OI-0564. LoggingConfiguration

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **LoggingConfiguration** means: The centralized control over log levels, categories, file buffering, redaction, and shareable trace inclusion. The reason it exists is: Diagnostic evidence must be useful without leaking arbitrary document content or flooding storage.

### Layman’s explanation

The centralized control over log levels, categories, file buffering, redaction, and shareable trace inclusion. Diagnostic evidence must be useful without leaking arbitrary document content or flooding storage.

### Technical explanation

It is consulted whenever services emit logs and when trace files are built. Primary code anchors: OpenIntelligence/Services/Infrastructure/Configuration/LoggingConfiguration.swift.

### Why it is in this position

It is consulted whenever services emit logs and when trace files are built.

## OI-0565. Maximum GPU profile

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Maximum GPU profile** means: The highest concurrency and GPU-ceiling policy using the same engines as Performance with fewer internal limits. The reason it exists is: It exists for hardware and users who prioritize maximum throughput over heat and battery.

### Layman’s explanation

The highest concurrency and GPU-ceiling policy using the same engines as Performance with fewer internal limits. It exists for hardware and users who prioritize maximum throughput over heat and battery.

### Technical explanation

It is applied before compute-intensive ingestion or retrieval. Primary code anchors: OpenIntelligence/Services/Infrastructure/Monitoring/DeviceCapabilityService.swift.

### Why it is in this position

It is applied before compute-intensive ingestion or retrieval.

## OI-0566. Maximum-mode quota

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Maximum-mode quota** means: The tracked allowance for high-cost Maximum queries under the relevant product tier. The reason it exists is: Maximum can use substantially more local model sessions and background time than Standard.

### Layman’s explanation

The tracked allowance for high-cost Maximum queries under the relevant product tier. Maximum can use substantially more local model sessions and background time than Standard.

### Technical explanation

It is checked before Maximum execution and updated after authorized use. Primary code anchors: OpenIntelligence/Services/Billing/MaximumModeQuotaStore.swift.

### Why it is in this position

It is checked before Maximum execution and updated after authorized use.

## OI-0567. Memory pressure

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Memory pressure** means: The runtime condition nominal, warning, or critical indicating process or system memory stress. The reason it exists is: Image and model buffers can cause jetsam termination before ordinary Swift errors occur.

### Layman’s explanation

The runtime condition nominal, warning, or critical indicating process or system memory stress. Image and model buffers can cause jetsam termination before ordinary Swift errors occur.

### Technical explanation

It is monitored and can clear GPU caches or reduce pipeline work. Primary code anchors: OpenIntelligence/Services/Infrastructure/Optimization/AdaptivePipelineOptimizer.swift; OpenIntelligence/Services/Infrastructure/Compute/GPUComputeService.swift.

### Why it is in this position

It is monitored and can clear GPU caches or reduce pipeline work.

## OI-0568. Metal Performance Shaders

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Metal Performance Shaders** means: Apple GPU primitives and infrastructure used alongside custom Metal kernels. The reason it exists is: They support optimized matrix and buffer operations on unified-memory hardware.

### Layman’s explanation

Apple GPU primitives and infrastructure used alongside custom Metal kernels. They support optimized matrix and buffer operations on unified-memory hardware.

### Technical explanation

They are initialized within GPUComputeService for eligible workloads. Primary code anchors: OpenIntelligence/Services/Infrastructure/Compute/GPUComputeService.swift.

### Why it is in this position

They are initialized within GPUComputeService for eligible workloads.

## OI-0569. Minimal optimization level

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Minimal optimization level** means: The emergency configuration retaining only essential search and generation with small limits and no agentic steps. The reason it exists is: Critical thermal state needs a rule-based and repeatable safe mode rather than a best-effort full pipeline.

### Layman’s explanation

The emergency configuration retaining only essential retrieval and generation with small limits and no agentic steps. Critical thermal state needs a deterministic safe mode rather than a best-effort full pipeline.

### Technical explanation

It is selected under critical thermal conditions before query execution. Primary code anchors: OpenIntelligence/Services/Infrastructure/Optimization/AdaptivePipelineOptimizer.swift.

### Why it is in this position

It is selected under critical thermal conditions before query execution.

## OI-0570. Neural Engine

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Neural Engine** means: Apple's dedicated machine-learning accelerator available through Core ML scheduling. The reason it exists is: meaning map, OCR, and model model answering can run efficiently without treating CPU or GPU as the only compute resources.

### Layman’s explanation

Apple's dedicated machine-learning accelerator available through Core ML scheduling. Embedding, OCR, and model inference can run efficiently without treating CPU or GPU as the only compute resources.

### Technical explanation

Core ML may choose it at inference time according to the configured compute units and system policy. Primary code anchors: OpenIntelligence/Services/Infrastructure/Monitoring/DeviceCapabilityService.swift; OpenIntelligence/UI/Components/Glossary.swift.

### Why it is in this position

Core ML may choose it at inference time according to the configured compute units and system policy.

## OI-0571. Performance profile

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Performance profile** means: The profile allowing all compute units and moving sufficiently large searches to GPU. The reason it exists is: It prioritizes latency when the user accepts higher energy and thermal cost.

### Layman’s explanation

The profile allowing all compute units and moving sufficiently large searches to GPU. It prioritizes latency when the user accepts higher energy and thermal cost.

### Technical explanation

It is checked before Core ML and vector route selection. Primary code anchors: OpenIntelligence/Services/Infrastructure/Monitoring/DeviceCapabilityService.swift.

### Why it is in this position

It is checked before Core ML and vector route selection.

## OI-0572. Query timeout

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Query timeout** means: The maximum wall-clock allowance for a question configuration. The reason it exists is: search or model loops need a hard latency boundary and a path to cancellation or partial result.

### Layman’s explanation

The maximum wall-clock allowance for a query configuration. Retrieval or model loops need a hard latency boundary and a path to cancellation or partial result.

### Technical explanation

It is resolved before execution and checked by Standard or agentic orchestration. Primary code anchors: OpenIntelligence/Services/Infrastructure/Optimization/AdaptivePipelineOptimizer.swift.

### Why it is in this position

It is resolved before execution and checked by Standard or agentic orchestration.

## OI-0573. QuotaPolicy

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **QuotaPolicy** means: The centralized limits for libraries, documents, and feature access by workspace tier. The reason it exists is: Scattered magic limits create inconsistent behavior and difficult migrations.

### Layman’s explanation

The centralized limits for libraries, documents, and feature access by workspace tier. Scattered magic limits create inconsistent behavior and difficult migrations.

### Technical explanation

It is consulted before create/import/query operations that consume quota. Primary code anchors: OpenIntelligence/Services/Infrastructure/Configuration/QuotaPolicy.swift.

### Why it is in this position

It is consulted before create/import/query operations that consume quota.

## OI-0574. SettingsStore

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **SettingsStore** means: The saved central source for user model, routing, quality, GPU, RAG tuning, privacy, and presentation settings. The reason it exists is: question execution must snapshot one coherent setting state rather than reread mutable UI values during the run.

### Layman’s explanation

The persisted central source for user model, routing, quality, GPU, RAG tuning, privacy, and presentation settings. Query execution must snapshot one coherent setting state rather than reread mutable UI values during the run.

### Technical explanation

It is read by QueryRuntimeCoordinator at query start and by device/model policy where needed. Primary code anchors: OpenIntelligence/Services/Infrastructure/Configuration/SettingsStore.swift.

### Why it is in this position

It is read by QueryRuntimeCoordinator at query start and by device/model policy where needed.

## OI-0575. Shared vector-store materialization guard

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Shared vector-store materialization guard** means: The rule that sync aborts if iCloud reports a number coordinates store but the file contents have not downloaded and cannot be read. The reason it exists is: An unavailable shared file can look like an empty library and cause destructive overwrite.

### Layman’s explanation

The rule that sync aborts if iCloud reports a vector store but the file contents have not downloaded and cannot be read. An unavailable shared file can look like an empty library and cause destructive overwrite.

### Technical explanation

It is checked before vector reconciliation and fails closed on uncertainty. Primary code anchors: OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift.

### Why it is in this position

It is checked before vector reconciliation and fails closed on uncertainty.

## OI-0576. Spotlight indexing

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Spotlight indexing** means: Publishing document and library labels and facts to Core Spotlight for OS-level discovery. The reason it exists is: Users can find an indexed document from system search without exposing the document collection to a remote service.

### Layman’s explanation

Publishing document and library metadata to Core Spotlight for OS-level discovery. Users can find an indexed document from system search without exposing the corpus to a remote service.

### Technical explanation

It occurs after ingestion and is removed on deletion or wipe. Primary code anchors: OpenIntelligence/Services/Infrastructure/Background/SpotlightIndexService.swift.

### Why it is in this position

It occurs after ingestion and is removed on deletion or wipe.

## OI-0577. Step cooldown

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Step cooldown** means: A short delay inserted between expensive stages under the resolved adaptive policy. The reason it exists is: Cooldowns allow heat, memory, and asynchronous hardware work to settle during sustained multi-step queries.

### Layman’s explanation

A short delay inserted between expensive stages under the resolved adaptive policy. Cooldowns allow heat, memory, and asynchronous hardware work to settle during sustained multi-step queries.

### Technical explanation

It is applied between agentic or heavy pipeline steps when configured. Primary code anchors: OpenIntelligence/Services/Infrastructure/Optimization/AdaptivePipelineOptimizer.swift.

### Why it is in this position

It is applied between agentic or heavy pipeline steps when configured.

## OI-0578. StoreKit entitlement

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **StoreKit entitlement** means: The verified purchase or subscription state controlling library count, document limits, sync, and higher-cost modes. The reason it exists is: Product limits must be enforced consistently across UI and engine entry points.

### Layman’s explanation

The verified purchase or subscription state controlling library count, document limits, sync, and higher-cost modes. Product limits must be enforced consistently across UI and engine entry points.

### Technical explanation

It is resolved before restricted ingestion, sync, or Maximum work is authorized. Primary code anchors: OpenIntelligence/Services/Billing/EntitlementStore.swift; OpenIntelligence/Services/Billing/MonetizationPolicy.swift.

### Why it is in this position

It is resolved before restricted ingestion, sync, or Maximum work is authorized.

## OI-0579. Sync bootstrap conflict

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Sync bootstrap conflict** means: The state where both local and iCloud workspaces contain meaningful independent libraries and the engine cannot safely choose one automatically. The reason it exists is: Blind replacement could delete unique documents or duplicate libraries.

### Layman’s explanation

The state where both local and iCloud workspaces contain meaningful independent libraries and the engine cannot safely choose one automatically. Blind replacement could delete unique documents or duplicate libraries.

### Technical explanation

It is detected before the first shared-workspace merge and presented for resolution. Primary code anchors: OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift.

### Why it is in this position

It is detected before the first shared-workspace merge and presented for resolution.

## OI-0580. Sync merge plan

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Sync merge plan** means: The rule-based and repeatable mapping of source libraries/documents to canonical identities across local and shared roots. The reason it exists is: Merging must preserve identity, deletion, and source-container relations rather than concatenate files.

### Layman’s explanation

The deterministic mapping of source libraries/documents to canonical identities across local and shared roots. Merging must preserve identity, deletion, and source-container relations rather than concatenate files.

### Technical explanation

It is built after both inventories are read and before writes begin. Primary code anchors: OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift.

### Why it is in this position

It is built after both inventories are read and before writes begin.

## OI-0581. Sync write-in-progress guard

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Sync write-in-progress guard** means: The process-wide flag preventing local change notifications from recursively starting another sync while a sync write is active. The reason it exists is: Sync writes themselves create filesystem changes that could otherwise trigger loops.

### Layman’s explanation

The process-wide flag preventing local change notifications from recursively starting another sync while a sync write is active. Sync writes themselves create filesystem changes that could otherwise trigger loops.

### Technical explanation

It is set around reconfiguration and cleared after all required passes finish. Primary code anchors: OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift.

### Why it is in this position

It is set around reconfiguration and cleared after all required passes finish.

## OI-0582. Thermal state

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Thermal state** means: The ProcessInfo classification nominal, fair, serious, or critical. The reason it exists is: Sustained OCR, meaning map, and model work can heat mobile devices and trigger throttling or termination.

### Layman’s explanation

The ProcessInfo classification nominal, fair, serious, or critical. Sustained OCR, embedding, and model work can heat mobile devices and trigger throttling or termination.

### Technical explanation

It is monitored continuously and used by adaptive and background policy. Primary code anchors: OpenIntelligence/Services/Infrastructure/Optimization/AdaptivePipelineOptimizer.swift.

### Why it is in this position

It is monitored continuously and used by adaptive and background policy.

## OI-0583. TOPS lookup

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **TOPS lookup** means: A device-identifier table of approximate or projected trillion-operations-per-second figures shown for explanatory hardware context. The reason it exists is: Apple exposes no public live Neural Engine occupancy or throughput measurement API.

### Layman’s explanation

A device-identifier table of approximate or projected trillion-operations-per-second figures shown for explanatory hardware context. Apple exposes no public live Neural Engine occupancy or throughput measurement API.

### Technical explanation

It is resolved at device detection and shown in diagnostics/onboarding. Primary code anchors: OpenIntelligence/Services/Infrastructure/Monitoring/DeviceCapabilityService.swift.

**Important caveat:** It is a lookup or projection, not a measurement of the current import or query.

### Why it is in this position

It is resolved at device detection and shown in diagnostics/onboarding.

## OI-0584. Unified memory

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Unified memory** means: Apple's memory architecture in which CPU and GPU can access the same physical memory pool. The reason it exists is: It enables near-zero-copy number coordinates and image paths but also means every subsystem competes within one process memory budget.

### Layman’s explanation

Apple's memory architecture in which CPU and GPU can access the same physical memory pool. It enables near-zero-copy vector and image paths but also means every subsystem competes within one process memory budget.

### Technical explanation

It is a hardware constraint behind mmap and shared Metal-buffer design. Primary code anchors: OpenIntelligence/Services/Infrastructure/Monitoring/DeviceCapabilityService.swift; OpenIntelligence/UI/Components/Glossary.swift.

### Why it is in this position

It is a hardware constraint behind mmap and shared Metal-buffer design.

## OI-0585. vDSP

**Status:** Core, meaning it is active and load-bearing.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **vDSP** means: Accelerate's vectorized digital signal processing primitives used for dot products, sums, division, clipping, and matrix multiplication. The reason it exists is: It provides highly optimized SIMD arithmetic without handwritten CPU loops.

### Layman’s explanation

Accelerate's vectorized digital signal processing primitives used for dot products, sums, division, clipping, and matrix multiplication. It provides highly optimized SIMD arithmetic without handwritten CPU loops.

### Technical explanation

It executes inside embedding normalization and CPU retrieval paths. Primary code anchors: OpenIntelligence/Services/Infrastructure/Compute/BNNSGraphService.swift.

### Why it is in this position

It executes inside embedding normalization and CPU retrieval paths.

## OI-0586. Vector sync signature cache

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **Vector sync signature cache** means: A conservative signature of file attributes and document/source sets recorded after a sync proves local and shared number coordinates stores already match. The reason it exists is: It avoids repeatedly deserializing every number coordinates record merely to decide that no write is necessary.

### Layman’s explanation

A conservative signature of file attributes and document/source sets recorded after a sync proves local and shared vector stores already match. It avoids repeatedly deserializing every vector record merely to decide that no write is necessary.

### Technical explanation

It is checked on later sync passes and invalidated by any uncertain or changed input. Primary code anchors: OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift.

### Why it is in this position

It is checked on later sync passes and invalidated by any uncertain or changed input.

## OI-0587. WorkspaceSyncService

**Status:** Conditional, meaning it is active only in particular modes, settings, file types, or situations.

### Explain it like I am five

Think of this part of the app as a power manager, janitor, and warehouse coordinator. **WorkspaceSyncService** means: The per-library iCloud workspace synchronizer for containers, documents, number coordinates artifacts, queue state, tombstones, and conflict resolution. The reason it exists is: Users need the same indexed library across devices without a custom backend.

### Layman’s explanation

The per-library iCloud workspace synchronizer for containers, documents, vector artifacts, queue state, tombstones, and conflict resolution. Users need the same indexed library across devices without a custom backend.

### Technical explanation

It runs after local workspace changes and during bootstrap or explicit sync actions. Primary code anchors: OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift.

### Why it is in this position

It runs after local workspace changes and during bootstrap or explicit sync actions.

---

# 16. Dormant, future, superseded, and commonly misnamed mechanisms

**Section orientation:** The repository contains future levels, dormant providers, old names, removed backends, and claims that were corrected. These must be taught separately from active behavior.

## OI-0588. 18-of-20 zero-hallucination result

**Status:** Historical, meaning it is superseded, removed, or misleading if described as current.

### Explain it like I am five

Think of this part of the app as a blueprint shelf for prototypes and retired parts. **18-of-20 zero-hallucination result** means: A withdrawn accuracy claim from an invalidly fast synthetic run where generation likely did not execute as assumed. The reason it exists is: Untrustworthy evaluation evidence should be removed rather than updated cosmetically.

### Layman’s explanation

A withdrawn accuracy claim from an invalidly fast synthetic run where generation likely did not execute as assumed. Untrustworthy evaluation evidence should be removed rather than updated cosmetically.

### Technical explanation

It is not a valid current benchmark and must not appear in product claims. Primary code anchors: Docs/HOW_IT_WORKS.md; BenchmarkRuns/PROGRESSION.md.

### Why it is in this position

It is not a valid current benchmark and must not appear in product claims.

## OI-0589. 32K PCC window

**Status:** Historical, meaning it is superseded, removed, or misleading if described as current.

### Explain it like I am five

Think of this part of the app as a blueprint shelf for prototypes and retired parts. **32K PCC window** means: A compatibility fallback and historical documentation value for potential cloud context. The reason it exists is: The public shipping runtime has not verified this as an active OpenIntelligence production limit.

### Layman’s explanation

A compatibility fallback and historical documentation value for potential cloud context. The public shipping runtime has not verified this as an active OpenIntelligence production limit.

### Technical explanation

It must not be used to describe current user execution. Primary code anchors: Docs/Engineering/HARD_LIMITS.md; Docs/HOW_IT_WORKS.md.

### Why it is in this position

It must not be used to describe current user execution.

## OI-0590. 3B versus 20B selector

**Status:** Historical, meaning it is superseded, removed, or misleading if described as current.

### Explain it like I am five

Think of this part of the app as a blueprint shelf for prototypes and retired parts. **3B versus 20B selector** means: The withdrawn implication that the app can choose between exact on-device parameter-count tiers. The reason it exists is: The framework exposes availability and execution, not a reliable selector or attestation for these sizes.

### Layman’s explanation

The withdrawn implication that the app can choose between exact on-device parameter-count tiers. The framework exposes availability and execution, not a reliable selector or attestation for these sizes.

### Technical explanation

Compatibility preference aliases resolve to on-device execution instead. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelRoutePolicy.swift; Docs/HOW_IT_WORKS.md.

### Why it is in this position

Compatibility preference aliases resolve to on-device execution instead.

## OI-0591. AFM 3 Core Advanced label

**Status:** Historical, meaning it is superseded, removed, or misleading if described as current.

### Explain it like I am five

Think of this part of the app as a blueprint shelf for prototypes and retired parts. **AFM 3 Core Advanced label** means: A withdrawn user-facing model-tier name not selectable or observable through the public SDK. The reason it exists is: A precise name implied control the app did not have.

### Layman’s explanation

A withdrawn user-facing model-tier name not selectable or observable through the public SDK. A precise name implied control the app did not have.

### Technical explanation

It has been replaced by truthful on-device or Apple Intelligence route language. Primary code anchors: CHANGELOG.md; OpenIntelligence/Core/Models/LLMModelType.swift.

### Why it is in this position

It has been replaced by truthful on-device or Apple Intelligence route language.

## OI-0592. Approximate confidence probability

**Status:** Historical, meaning it is superseded, removed, or misleading if described as current.

### Explain it like I am five

Think of this part of the app as a blueprint shelf for prototypes and retired parts. **Approximate confidence probability** means: The mistaken interpretation that a displayed heuristic confidence value is a statistically adjusted against a trust rule probability of truth. The reason it exists is: adjusted against a trust rule requires held-out outcome frequencies and reliability analysis.

### Layman’s explanation

The mistaken interpretation that a displayed heuristic confidence value is a statistically calibrated probability of truth. Calibration requires held-out outcome frequencies and reliability analysis.

### Technical explanation

Current values are policy-calibrated trust signals and should be taught with that limitation. Primary code anchors: OpenIntelligence/Services/RAG/Safety/ConfidenceCalibrationService.swift; Docs/EVALS.md.

### Why it is in this position

Current values are policy-calibrated trust signals and should be taught with that limitation.

## OI-0593. Automatic online self-training

**Status:** Historical, meaning it is superseded, removed, or misleading if described as current.

### Explain it like I am five

Think of this part of the app as a blueprint shelf for prototypes and retired parts. **Automatic online self-training** means: The idea that the app continuously retrains or autonomously changes its models from ordinary user activity. The reason it exists is: The current engine adjusts policy and configuration but does not train the bundled meaning map or reranker models on user documents.

### Layman’s explanation

The idea that the app continuously retrains or autonomously changes its models from ordinary user activity. The current engine adjusts policy and configuration but does not train the bundled embedding or reranker models on user documents.

### Technical explanation

It does not occur during ingestion or querying. Primary code anchors: OpenIntelligence/Services/RAG/Tuning/AutoTuneService.swift; OpenIntelligence/Services/Embedding/EmbeddingService.swift.

### Why it is in this position

It does not occur during ingestion or querying.

## OI-0594. AutoTuneService

**Status:** Support, meaning it is supporting diagnostics, evaluation, compatibility, or operations.

### Explain it like I am five

Think of this part of the app as a blueprint shelf for prototypes and retired parts. **AutoTuneService** means: The service intended to update selected search thresholds or policies from measured evaluation data under explicit constraints. The reason it exists is: Tuning should be evidence-driven and bounded rather than silently self-modifying from user answers.

### Layman’s explanation

The service intended to update selected retrieval thresholds or policies from measured evaluation data under explicit constraints. Tuning should be evidence-driven and bounded rather than silently self-modifying from user answers.

### Technical explanation

It operates outside the critical live answer path and consumes evaluation or policy inputs when invoked. Primary code anchors: OpenIntelligence/Services/RAG/Tuning/AutoTuneService.swift.

### Why it is in this position

It operates outside the critical live answer path and consumes evaluation or policy inputs when invoked.

## OI-0595. Bundled Core ML generative backend

**Status:** Historical, meaning it is superseded, removed, or misleading if described as current.

### Explain it like I am five

Think of this part of the app as a blueprint shelf for prototypes and retired parts. **Bundled Core ML generative backend** means: A removed custom local model-written model path distinct from Apple Foundation Models. The reason it exists is: The current product relies on the system language model and rule-based and repeatable analysis paths.

### Layman’s explanation

A removed custom local generative model path distinct from Apple Foundation Models. The current product relies on the system language model and deterministic analysis paths.

### Technical explanation

It no longer participates in model resolution. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/RAGService.swift.

### Why it is in this position

It no longer participates in model resolution.

## OI-0596. Default HNSW architecture

**Status:** Historical, meaning it is superseded, removed, or misleading if described as current.

### Explain it like I am five

Think of this part of the app as a blueprint shelf for prototypes and retired parts. **Default HNSW architecture** means: The incorrect generalization that OpenIntelligence always uses an approximate HNSW number coordinates index. The reason it exists is: The default current store is BNNSVectorDatabase exact scan; HNSW belongs only to the optional Vectura path.

### Layman’s explanation

The incorrect generalization that OpenIntelligence always uses an approximate HNSW vector index. The default current store is BNNSVectorDatabase exact scan; HNSW belongs only to the optional Vectura path.

### Technical explanation

It does not occur in normal persistentJSON/BNNS libraries. Primary code anchors: OpenIntelligence/Services/VectorStore/VectorStoreRouter.swift.

### Why it is in this position

It does not occur in normal persistentJSON/BNNS libraries.

## OI-0597. Dynamic Foundation Model profiles

**Status:** Dormant, meaning it is implemented or scaffolded, but not a functioning ordinary shipping path.

### Explain it like I am five

Think of this part of the app as a blueprint shelf for prototypes and retired parts. **Dynamic Foundation Model profiles** means: A registry intended to describe runtime Foundation Model capability profiles. The reason it exists is: It anticipated a more observable model-tier API.

### Layman’s explanation

A registry intended to describe runtime Foundation Model capability profiles. It anticipated a more observable model-tier API.

### Technical explanation

The file exists but has no active call sites in the shipped execution path. Primary code anchors: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelDynamicProfileRegistry.swift.

### Why it is in this position

The file exists but has no active call sites in the shipped execution path.

## OI-0598. Embedding-based chunk boundary detection

**Status:** Dormant, meaning it is implemented or scaffolded, but not a functioning ordinary shipping path.

### Explain it like I am five

Think of this part of the app as a blueprint shelf for prototypes and retired parts. **Embedding-based chunk boundary detection** means: The implemented path that would compare adjacent sentence meaning map and split where meaning-based similarity falls. The reason it exists is: It could add language-independent topical boundaries beyond headings and transition phrases.

### Layman’s explanation

The implemented path that would compare adjacent sentence embeddings and split where semantic similarity falls. It could add language-independent topical boundaries beyond headings and transition phrases.

### Technical explanation

The method exists inside SemanticChunker but returns no boundaries because the chunker is never assigned an EmbeddingService. Primary code anchors: OpenIntelligence/Services/Document/Chunking/SemanticChunker.swift.

### Why it is in this position

The method exists inside SemanticChunker but returns no boundaries because the chunker is never assigned an EmbeddingService.

## OI-0599. Fixed 384-dimensional architecture

**Status:** Historical, meaning it is superseded, removed, or misleading if described as current.

### Explain it like I am five

Think of this part of the app as a blueprint shelf for prototypes and retired parts. **Fixed 384-dimensional architecture** means: The oversimplified claim that all OpenIntelligence meaning map are 384-dimensional. The reason it exists is: 384 is the default MiniLM space, while configured Natural Language providers use 512 and the dormant AppleFM scaffold declares 1,024.

### Layman’s explanation

The oversimplified claim that all OpenIntelligence embeddings are 384-dimensional. 384 is the default MiniLM space, while configured Natural Language providers use 512 and the dormant AppleFM scaffold declares 1,024.

### Technical explanation

Dimension is resolved per library through the embedding fingerprint. Primary code anchors: OpenIntelligence/Services/Embedding/Providers/EmbeddingProvider.swift; OpenIntelligence/UI/Components/Glossary.swift.

### Why it is in this position

Dimension is resolved per library through the embedding fingerprint.

## OI-0600. Late chunking

**Status:** Historical, meaning it is superseded, removed, or misleading if described as current.

### Explain it like I am five

Think of this part of the app as a blueprint shelf for prototypes and retired parts. **Late chunking** means: A research technique that embeds a long document jointly and pools token states for each later small source piece span. The reason it exists is: It could preserve cross-small source piece context, but that is not what the current SemanticChunker does.

### Layman’s explanation

A research technique that embeds a long document jointly and pools token states for each later chunk span. It could preserve cross-chunk context, but that is not what the current SemanticChunker does.

### Technical explanation

It does not occur in the shipping ingestion path. Primary code anchors: Docs/Research/EMBEDDING_AND_INGESTION_UPGRADE_2026-08.md; OpenIntelligence/Services/Document/Chunking/SemanticChunker.swift.

**Important caveat:** The former UI and comment claim was withdrawn; current chunks are embedded independently.

### Why it is in this position

It does not occur in the shipping ingestion path.

## OI-0601. Live Neural Engine utilization

**Status:** Future, meaning it is reserved for future architecture.

### Explain it like I am five

Think of this part of the app as a blueprint shelf for prototypes and retired parts. **Live Neural Engine utilization** means: A hypothetical percentage or occupancy metric for the Apple Neural Engine. The reason it exists is: No public API currently supplies live ANE utilization to this app.

### Layman’s explanation

A hypothetical percentage or occupancy metric for the Apple Neural Engine. No public API currently supplies live ANE utilization to this app.

### Technical explanation

The HUD can report conceptual activity pulses and device lookup data, not a measured utilization percentage. Primary code anchors: OpenIntelligence/Services/Infrastructure/Monitoring/HardwareTelemetryState.swift; OpenIntelligence/Services/Infrastructure/Monitoring/DeviceCapabilityService.swift.

### Why it is in this position

The HUD can report conceptual activity pulses and device lookup data, not a measured utilization percentage.

## OI-0602. Local GGUF backend

**Status:** Historical, meaning it is superseded, removed, or misleading if described as current.

### Explain it like I am five

Think of this part of the app as a blueprint shelf for prototypes and retired parts. **Local GGUF backend** means: A previously supported or considered local model-written model format removed from the current architecture. The reason it exists is: The app consolidated on Apple Intelligence and On-Device Analysis rather than maintaining bundled third-party model-written runtimes.

### Layman’s explanation

A previously supported or considered local generative model format removed from the current architecture. The app consolidated on Apple Intelligence and On-Device Analysis rather than maintaining bundled third-party generative runtimes.

### Technical explanation

It no longer runs in RAGService. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/RAGService.swift.

### Why it is in this position

It no longer runs in RAGService.

## OI-0603. Local MLX generative backend

**Status:** Historical, meaning it is superseded, removed, or misleading if described as current.

### Explain it like I am five

Think of this part of the app as a blueprint shelf for prototypes and retired parts. **Local MLX generative backend** means: A removed local model-written model path based on MLX-style execution. The reason it exists is: Maintaining several model runtimes increased complexity and fragmented routing.

### Layman’s explanation

A removed local generative model path based on MLX-style execution. Maintaining several model runtimes increased complexity and fragmented routing.

### Technical explanation

It is explicitly absent from the current LLM path. Primary code anchors: OpenIntelligence/Services/RAG/Orchestration/RAGService.swift.

### Why it is in this position

It is explicitly absent from the current LLM path.

## OI-0604. Model judges

**Status:** Historical, meaning it is superseded, removed, or misleading if described as current.

### Explain it like I am five

Think of this part of the app as a blueprint shelf for prototypes and retired parts. **Model judges** means: The withdrawn claim that a separate model grades answer correctness. The reason it exists is: No implemented model-as-judge service exists in the active engine; rule-based and repeatable verification and benchmark ground truth serve different roles.

### Layman’s explanation

The withdrawn claim that a separate model grades answer correctness. No implemented model-as-judge service exists in the active engine; deterministic verification and benchmark ground truth serve different roles.

### Technical explanation

It does not occur after generation. Primary code anchors: CHANGELOG.md; OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift.

### Why it is in this position

It does not occur after generation.

## OI-0605. Neural extractive QA model

**Status:** Dormant, meaning it is implemented or scaffolded, but not a functioning ordinary shipping path.

### Explain it like I am five

Think of this part of the app as a blueprint shelf for prototypes and retired parts. **Neural extractive QA model** means: The planned Core ML start/end-span model represented by a stub protocol implementation. The reason it exists is: The design is present, but the active answer path uses heuristic extraction and specification logic.

### Layman’s explanation

The planned Core ML start/end-span model represented by a stub protocol implementation. The design is present, but the active answer path uses heuristic extraction and specification logic.

### Technical explanation

It is bypassed when the placeholder returns nil. Primary code anchors: OpenIntelligence/Services/RAG/Extraction/ExtractiveQAService.swift.

### Why it is in this position

It is bypassed when the placeholder returns nil.

## OI-0606. PCC simulation

**Status:** Historical, meaning it is superseded, removed, or misleading if described as current.

### Explain it like I am five

Think of this part of the app as a blueprint shelf for prototypes and retired parts. **PCC simulation** means: The withdrawn description that older OS versions simulate Private Cloud Compute. The reason it exists is: A simulation would misstate privacy and route behavior.

### Layman’s explanation

The withdrawn description that older OS versions simulate Private Cloud Compute. A simulation would misstate privacy and route behavior.

### Technical explanation

Older or unsupported builds stay on device or fail; no PCC simulation stage runs. Primary code anchors: Docs/ARCHITECTURE.md; PRIVACY.md.

### Why it is in this position

Older or unsupported builds stay on device or fail; no PCC simulation stage runs.

## OI-0607. Production PCC

**Status:** Dormant, meaning it is implemented or scaffolded, but not a functioning ordinary shipping path.

### Explain it like I am five

Think of this part of the app as a blueprint shelf for prototypes and retired parts. **Production PCC** means: The source architecture for live Private Cloud Compute completion. The reason it exists is: The route is intended for oversized evidence and deeper reasoning, but current App Store binaries were built without the required SDK path.

### Layman’s explanation

The source architecture for live Private Cloud Compute completion. The route is intended for oversized evidence and deeper reasoning, but current App Store binaries were built without the required SDK path.

### Technical explanation

It is excluded at compile time in shipping builds as of the checked date. Primary code anchors: Docs/SHIPPED_CAPABILITIES.json; Docs/HOW_IT_WORKS.md.

### Why it is in this position

It is excluded at compile time in shipping builds as of the checked date.

## OI-0608. RAPTOR L2/L3 hierarchy

**Status:** Future, meaning it is reserved for future architecture.

### Explain it like I am five

Think of this part of the app as a blueprint shelf for prototypes and retired parts. **RAPTOR L2/L3 hierarchy** means: Section- and document collection-level summary level layers above current document summaries. The reason it exists is: They could support hierarchical search across very large libraries.

### Layman’s explanation

Section- and corpus-level abstraction layers above current document summaries. They could support hierarchical retrieval across very large libraries.

### Technical explanation

They are reserved in the data model but not established as current indexed stages. Primary code anchors: OpenIntelligence/Core/Models/DocumentChunk.swift.

### Why it is in this position

They are reserved in the data model but not established as current indexed stages.

## OI-0609. Single 29-step pipeline

**Status:** Historical, meaning it is superseded, removed, or misleading if described as current.

### Explain it like I am five

Think of this part of the app as a blueprint shelf for prototypes and retired parts. **Single 29-step pipeline** means: The older documentation shorthand that represented the engine as one fixed numbered sequence. The reason it exists is: Current execution branches by file type, intent, quality mode, evidence, device state, and route, so no one number captures every path.

### Layman’s explanation

The older documentation shorthand that represented the engine as one fixed numbered sequence. Current execution branches by file type, intent, quality mode, evidence, device state, and route, so no one number captures every path.

### Technical explanation

The architecture should be taught as a shared spine with conditional subpipelines. Primary code anchors: Docs/HOW_IT_WORKS.md; Docs/RETRIEVAL_PIPELINE.md.

### Why it is in this position

The architecture should be taught as a shared spine with conditional subpipelines.

## OI-0610. Single recursive thought loop

**Status:** Historical, meaning it is superseded, removed, or misleading if described as current.

### Explain it like I am five

Think of this part of the app as a blueprint shelf for prototypes and retired parts. **Single recursive thought loop** means: The oversimplified label for several distinct mechanisms: execution planning, iterative search, recursive multi-session RAG, Self-RAG, critique/refinement, and rule-based and repeatable verification. The reason it exists is: Collapsing them hides which component retrieves, which reasons, which stores facts, and which enforces truth.

### Layman’s explanation

The oversimplified label for several distinct mechanisms: execution planning, iterative retrieval, recursive multi-session RAG, Self-RAG, critique/refinement, and deterministic verification. Collapsing them hides which component retrieves, which reasons, which stores facts, and which enforces truth.

### Technical explanation

The current study guide should teach each mechanism separately and then reconnect them in sequence. Primary code anchors: OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift; OpenIntelligence/Services/RAG/Retrieval/IterativeRetrievalService.swift.

### Why it is in this position

The current study guide should teach each mechanism separately and then reconnect them in sequence.

## OI-0611. Unmeasured speed multipliers

**Status:** Historical, meaning it is superseded, removed, or misleading if described as current.

### Explain it like I am five

Think of this part of the app as a blueprint shelf for prototypes and retired parts. **Unmeasured speed multipliers** means: Withdrawn claims such as 1,000x, 240x, 100x, or 4x improvements without supporting benchmark artifacts. The reason it exists is: Mechanism changes can be real while exact performance factors remain unproven.

### Layman’s explanation

Withdrawn claims such as 1,000x, 240x, 100x, or 4x improvements without supporting benchmark artifacts. Mechanism changes can be real while exact performance factors remain unproven.

### Technical explanation

The engine still contains the optimizations, but documentation should describe mechanisms or measured device-specific results only. Primary code anchors: CHANGELOG.md; Docs/RELEASE_NOTES.md.

### Why it is in this position

The engine still contains the optimizations, but documentation should describe mechanisms or measured device-specific results only.

## OI-0612. Zero latency

**Status:** Historical, meaning it is superseded, removed, or misleading if described as current.

### Explain it like I am five

Think of this part of the app as a blueprint shelf for prototypes and retired parts. **Zero latency** means: The withdrawn description of on-device generation as having no latency. The reason it exists is: Physical-device measurements show nonzero time to first token and throughput limits.

### Layman’s explanation

The withdrawn description of on-device generation as having no latency. Physical-device measurements show nonzero time to first token and throughput limits.

### Technical explanation

It is not a current route or performance characteristic. Primary code anchors: CHANGELOG.md; Docs/HOW_IT_WORKS.md.

### Why it is in this position

It is not a current route or performance characteristic.

---

# Part Three. Equations You Should Be Able to Explain Out Loud

## Cosine similarity

cos(q,d) = (q . d) / (||q||_2 ||d||_2). With unit-normalized vectors, this reduces to q . d.

## BM25

score(q,d) = sum IDF(t) * [f(t,d)(k1+1)] / [f(t,d) + k1(1-b+b|d|/avgdl)], plus configured FTS column weights.

## Reciprocal rank fusion

RRF(d) = sum_r 1 / (k + rank_r(d)), with k approximately 60 in the current implementation.

## Maximal marginal relevance

MMR(d) = lambda * relevance(d,q) - (1-lambda) * max similarity(d, already_selected).

## Evidence capacity

available_evidence_tokens = model_context - instructions - tools - question - conversation - safety_reserve - output_reserve.

## Recall at k

Recall@k = relevant items retrieved in top k / total relevant items.

## Precision at k

Precision@k = relevant items retrieved in top k / k.

## Reciprocal rank

RR = 1 / rank of the first relevant item; MRR is the mean across cases.

---

# Part Four. Terms That Must Never Be Blurred Together

## Embedding versus Vector search

Embedding creates coordinates; vector search compares those stored coordinates to the query.

## FTS5 versus BM25

FTS5 is the SQLite full-text indexing/search engine; BM25 is the relevance function used to rank its matches.

## Bi-encoder retrieval versus Cross-encoder reranking

The bi-encoder searches the full corpus cheaply; the cross-encoder jointly reads query and passage for a smaller shortlist.

## RRF versus Reranking

RRF merges independent ranked lists; reranking uses another model to reorder the merged candidates.

## Reranking versus MMR

Reranking maximizes relevance; MMR trades some relevance for nonredundant coverage.

## Retrieval versus Context packing

Retrieval finds candidates; packing decides what the model actually receives under a hard token budget.

## Iterative retrieval versus Agentic reasoning

Iterative retrieval repeats search and refinement; the agentic system also plans, accumulates facts, synthesizes, critiques, and verifies.

## Self-RAG versus Verification gates

Self-RAG can trigger model-guided retrieval or revision; gates are deterministic final enforcement checks.

## Confidence versus Fidelity

Confidence is a calibrated trust signal from several inputs; fidelity specifically describes support by cited sources.

## Selected model versus Completed route

The selection is user intent; the ModelExecutionReceipt attests what actually completed.

## PCC source code versus Production PCC

A route can exist in source while current App Store builds compile it out.

## Chunking strategy change versus Embedding-space change

Chunk sizes can coexist; changing model, dimension, tokenizer, or pooling requires full re-embedding.

---

# Part Five. End-to-End Pipeline Recitations

## Ingestion

Step 1. Choose the target library and create a durable ingestion item.

Step 2. Identify the file type, stable document identity, content hash, and processing lane.

Step 3. Extract native text or route pages/media through OCR, structured Vision, XML/CSV parsing, or speech transcription.

Step 4. Normalize text while preserving page, layout, table, list, figure, and offset provenance.

Step 5. Analyze document structure, entities, specifications, complexity, references, and language.

Step 6. Resolve an adaptive chunking plan, build coherent chunks, preserve atomic structures, and validate the real tokenizer ceiling.

Step 7. Attach source metadata, parent/sibling relations, contextual prefixes, and cross-reference edges.

Step 8. Generate and validate embeddings in the library's single fingerprinted vector space.

Step 9. Write lexical FTS5 rows, relational source data, vector files, norms, and optional summaries/entity indexes.

Step 10. Publish the mutually consistent artifact set atomically, then update sync, Spotlight, and progress surfaces.

## Standard Query

Step 1. Snapshot settings, device state, quality mode, user route preference, and model availability.

Step 2. Normalize and profile the question, classify answer/search intent, estimate complexity, and build an execution plan.

Step 3. Optionally rewrite, expand, use corpus vocabulary, or generate a HyDE probe.

Step 4. Generate the query embedding and run dense vector search and FTS5/BM25 lexical search in parallel.

Step 5. Fuse rankings with RRF, apply structure/identifier boosts, run corrective cascades if needed, and keep strong lexical survivors.

Step 6. Cross-encode the shortlist with TinyBERT, then apply MMR to reduce redundancy.

Step 7. Attempt deterministic table/state/specification extraction or source-only answering when the intent permits it.

Step 8. Expand high-value hits through parent content, siblings, entities, and document graph references.

Step 9. Select or compress source sentences and pack evidence under the actual token budget with Lost-in-the-Middle ordering.

Step 10. Create a post-retrieval ModelExecutionPlan and choose deterministic, on-device generation, abstention, or a permitted fallback.

Step 11. Generate a typed answer and claim structure, stream progress, and preserve the actual execution receipt.

Step 12. Run verification gates A through I, calibrate confidence, remove unsupported claims, or abstain.

Step 13. Build the final StructuredAnswer, map citations, render source/fidelity metadata, and persist the Evidence Thread.

## Agentic Branch

Step 1. Plan atomic information requirements and initialize the FactBank and coverage map.

Step 2. Retrieve evidence for the highest-priority subquestion using the same hybrid retrieval stack.

Step 3. Expand and analyze evidence, extract source-backed facts, and identify explicit gaps.

Step 4. Reformulate or decompose the next query when novelty or coverage remains insufficient.

Step 5. Repeat bounded sessions until evidence converges, policy says stop, cancellation occurs, or the hard cap is reached.

Step 6. Synthesize accumulated facts, critique and refine the draft, then run the same deterministic verification and abstention boundary.

---

# Part Six. Coverage Manifest

Every ID below has a full three-level capsule in Part Two.

- **00. System architecture and boundaries:** OI-0001, OI-0002, OI-0003, OI-0004, OI-0005, OI-0006, OI-0007, OI-0008, OI-0009, OI-0010, OI-0011, OI-0012, OI-0013, OI-0014
- **01. Ingestion control, identity, and lifecycle:** OI-0015, OI-0016, OI-0017, OI-0018, OI-0019, OI-0020, OI-0021, OI-0022, OI-0023, OI-0024, OI-0025, OI-0026, OI-0027, OI-0028, OI-0029, OI-0030, OI-0031, OI-0032, OI-0033
- **02. File extraction and document understanding:** OI-0034, OI-0035, OI-0036, OI-0037, OI-0038, OI-0039, OI-0040, OI-0041, OI-0042, OI-0043, OI-0044, OI-0045, OI-0046, OI-0047, OI-0048, OI-0049, OI-0050, OI-0051, OI-0052, OI-0053, OI-0054, OI-0055, OI-0056, OI-0057, OI-0058, OI-0059, OI-0060, OI-0061, OI-0062, OI-0063, OI-0064, OI-0065, OI-0066, OI-0067, OI-0068, OI-0069, OI-0070, OI-0071, OI-0072, OI-0073, OI-0074, OI-0075, OI-0076, OI-0077, OI-0078, OI-0079, OI-0080, OI-0081, OI-0082, OI-0083, OI-0084, OI-0085
- **03. Document analysis, adaptation, and derived knowledge:** OI-0086, OI-0087, OI-0088, OI-0089, OI-0090, OI-0091, OI-0092, OI-0093, OI-0094, OI-0095, OI-0096, OI-0097, OI-0098, OI-0099, OI-0100
- **04. Chunking and tokenizer integrity:** OI-0101, OI-0102, OI-0103, OI-0104, OI-0105, OI-0106, OI-0107, OI-0108, OI-0109, OI-0110, OI-0111, OI-0112, OI-0113, OI-0114, OI-0115, OI-0116, OI-0117, OI-0118, OI-0119, OI-0120, OI-0121
- **05. Embeddings and vector semantics:** OI-0122, OI-0123, OI-0124, OI-0125, OI-0126, OI-0127, OI-0128, OI-0129, OI-0130, OI-0131, OI-0132, OI-0133, OI-0134, OI-0135, OI-0136, OI-0137, OI-0138, OI-0139, OI-0140, OI-0141, OI-0142, OI-0143, OI-0144, OI-0145, OI-0146, OI-0147, OI-0148, OI-0149, OI-0150, OI-0151, OI-0152, OI-0153, OI-0154
- **06. Lexical indexing, SQLite, and vector persistence:** OI-0155, OI-0156, OI-0157, OI-0158, OI-0159, OI-0160, OI-0161, OI-0162, OI-0163, OI-0164, OI-0165, OI-0166, OI-0167, OI-0168, OI-0169, OI-0170, OI-0171, OI-0172, OI-0173, OI-0174, OI-0175, OI-0176, OI-0177, OI-0178, OI-0179, OI-0180, OI-0181, OI-0182, OI-0183, OI-0184, OI-0185, OI-0186, OI-0187, OI-0188, OI-0189, OI-0190, OI-0191, OI-0192, OI-0193, OI-0194, OI-0195, OI-0196, OI-0197, OI-0198, OI-0199, OI-0200, OI-0201, OI-0202, OI-0203
- **07. Query understanding, intent, and execution planning:** OI-0204, OI-0205, OI-0206, OI-0207, OI-0208, OI-0209, OI-0210, OI-0211, OI-0212, OI-0213, OI-0214, OI-0215, OI-0216, OI-0217, OI-0218, OI-0219, OI-0220, OI-0221, OI-0222, OI-0223, OI-0224, OI-0225, OI-0226, OI-0227, OI-0228, OI-0229, OI-0230, OI-0231, OI-0232, OI-0233, OI-0234, OI-0235, OI-0236, OI-0237, OI-0238, OI-0239, OI-0240, OI-0241, OI-0242, OI-0243, OI-0244, OI-0245, OI-0246, OI-0247, OI-0248
- **08. Retrieval, fusion, reranking, and evidence expansion:** OI-0249, OI-0250, OI-0251, OI-0252, OI-0253, OI-0254, OI-0255, OI-0256, OI-0257, OI-0258, OI-0259, OI-0260, OI-0261, OI-0262, OI-0263, OI-0264, OI-0265, OI-0266, OI-0267, OI-0268, OI-0269, OI-0270, OI-0271, OI-0272, OI-0273, OI-0274, OI-0275, OI-0276, OI-0277, OI-0278, OI-0279, OI-0280, OI-0281, OI-0282, OI-0283, OI-0284, OI-0285, OI-0286, OI-0287, OI-0288, OI-0289, OI-0290, OI-0291, OI-0292, OI-0293, OI-0294, OI-0295, OI-0296, OI-0297, OI-0298, OI-0299, OI-0300, OI-0301, OI-0302, OI-0303, OI-0304, OI-0305, OI-0306, OI-0307, OI-0308
- **09. Context selection, compression, and token packing:** OI-0309, OI-0310, OI-0311, OI-0312, OI-0313, OI-0314, OI-0315, OI-0316, OI-0317, OI-0318, OI-0319, OI-0320, OI-0321, OI-0322, OI-0323, OI-0324, OI-0325, OI-0326, OI-0327, OI-0328, OI-0329, OI-0330, OI-0331, OI-0332, OI-0333, OI-0334, OI-0335
- **10. Model execution, routing, tools, and generation:** OI-0336, OI-0337, OI-0338, OI-0339, OI-0340, OI-0341, OI-0342, OI-0343, OI-0344, OI-0345, OI-0346, OI-0347, OI-0348, OI-0349, OI-0350, OI-0351, OI-0352, OI-0353, OI-0354, OI-0355, OI-0356, OI-0357, OI-0358, OI-0359, OI-0360, OI-0361, OI-0362, OI-0363, OI-0364, OI-0365, OI-0366, OI-0367, OI-0368, OI-0369, OI-0370, OI-0371, OI-0372, OI-0373, OI-0374, OI-0375, OI-0376, OI-0377, OI-0378, OI-0379, OI-0380, OI-0381, OI-0382, OI-0383, OI-0384, OI-0385, OI-0386, OI-0387, OI-0388, OI-0389, OI-0390, OI-0391, OI-0392, OI-0393, OI-0394, OI-0395, OI-0396, OI-0397
- **11. Agentic, recursive, and multi-session reasoning:** OI-0398, OI-0399, OI-0400, OI-0401, OI-0402, OI-0403, OI-0404, OI-0405, OI-0406, OI-0407, OI-0408, OI-0409, OI-0410, OI-0411, OI-0412, OI-0413, OI-0414, OI-0415, OI-0416, OI-0417, OI-0418, OI-0419, OI-0420, OI-0421, OI-0422, OI-0423, OI-0424, OI-0425, OI-0426, OI-0427, OI-0428, OI-0429, OI-0430, OI-0431, OI-0432, OI-0433, OI-0434, OI-0435, OI-0436, OI-0437
- **12. Verification, grounding, confidence, and abstention:** OI-0438, OI-0439, OI-0440, OI-0441, OI-0442, OI-0443, OI-0444, OI-0445, OI-0446, OI-0447, OI-0448, OI-0449, OI-0450, OI-0451, OI-0452, OI-0453, OI-0454, OI-0455, OI-0456, OI-0457, OI-0458, OI-0459, OI-0460, OI-0461, OI-0462, OI-0463, OI-0464, OI-0465, OI-0466, OI-0467, OI-0468, OI-0469, OI-0470, OI-0471, OI-0472, OI-0473, OI-0474, OI-0475, OI-0476, OI-0477
- **13. Response structure, provenance, rendering, and observability:** OI-0478, OI-0479, OI-0480, OI-0481, OI-0482, OI-0483, OI-0484, OI-0485, OI-0486, OI-0487, OI-0488, OI-0489, OI-0490, OI-0491, OI-0492, OI-0493, OI-0494, OI-0495, OI-0496, OI-0497, OI-0498, OI-0499, OI-0500, OI-0501, OI-0502, OI-0503, OI-0504, OI-0505, OI-0506, OI-0507, OI-0508, OI-0509, OI-0510, OI-0511, OI-0512
- **14. Evaluation, benchmarks, and quality measurement:** OI-0513, OI-0514, OI-0515, OI-0516, OI-0517, OI-0518, OI-0519, OI-0520, OI-0521, OI-0522, OI-0523, OI-0524, OI-0525, OI-0526, OI-0527, OI-0528, OI-0529, OI-0530, OI-0531, OI-0532, OI-0533, OI-0534, OI-0535, OI-0536, OI-0537, OI-0538, OI-0539, OI-0540, OI-0541, OI-0542, OI-0543
- **15. Device adaptation, compute, background work, sync, and product limits:** OI-0544, OI-0545, OI-0546, OI-0547, OI-0548, OI-0549, OI-0550, OI-0551, OI-0552, OI-0553, OI-0554, OI-0555, OI-0556, OI-0557, OI-0558, OI-0559, OI-0560, OI-0561, OI-0562, OI-0563, OI-0564, OI-0565, OI-0566, OI-0567, OI-0568, OI-0569, OI-0570, OI-0571, OI-0572, OI-0573, OI-0574, OI-0575, OI-0576, OI-0577, OI-0578, OI-0579, OI-0580, OI-0581, OI-0582, OI-0583, OI-0584, OI-0585, OI-0586, OI-0587
- **16. Dormant, future, superseded, and commonly misnamed mechanisms:** OI-0588, OI-0589, OI-0590, OI-0591, OI-0592, OI-0593, OI-0594, OI-0595, OI-0596, OI-0597, OI-0598, OI-0599, OI-0600, OI-0601, OI-0602, OI-0603, OI-0604, OI-0605, OI-0606, OI-0607, OI-0608, OI-0609, OI-0610, OI-0611, OI-0612

**Total covered concepts: 612 of 612.**
