# OpenIntelligence Current State and Gaps

**Updated**: April 24, 2026
**Scope**: Repo-grounded final analysis of the app, SDK surface, storage model, RAG pipeline, and sales-readiness constraints.

This document is the plain-English map of what OpenIntelligence is today. It should be read before pitching, pricing, or refactoring the engine.

Deeper companion docs:

- [Implementation Analysis](./IMPLEMENTATION_ANALYSIS_2026_04_24.md)
- [Storage and Pipeline Trace](./STORAGE_AND_PIPELINE_TRACE.md)
- [Buyer Readiness and Evaluation Plan](./BUYER_READINESS_AND_EVALUATION.md)

## What This App Is

OpenIntelligence is an Apple-native document intelligence engine. The core value is local-first retrieval and question answering over private user documents, with source citations and verification gates wrapped around Apple's Foundation Models framework.

The repo currently contains:

- A full iOS/iPadOS/macOS app under `OpenIntelligence/`.
- A public Swift wrapper at `OpenIntelligence/SDK/OpenIntelligenceEngine.swift`.
- A generated buyer/evaluation package under `output/OpenIntelligence-SDK-Package/`, including an `OpenIntelligenceEngine.xcframework`, install docs, API docs, and sample host app.
- 107 Swift service files under `OpenIntelligence/Services/`.
- A logical 29-step RAG pipeline in the docs and a much more adaptive implementation in `RAGService.swift`.

The strongest commercial story is not "a chatbot." It is an offline/private Apple-platform document QA engine for regulated, field, medical-device, enterprise-support, compliance, and technical-manual workflows where the buyer cares about document provenance, no third-party model dependency for core behavior, and cited evidence.

## How It Works

### Ingestion

1. The app accepts documents, images, code, CSV, Office XML formats, and audio/video transcription paths.
2. `DocumentProcessor.swift` extracts text with PDFKit when possible, falls back to Vision OCR when text layers are missing or suspected to be garbled, and uses Metal-backed Core Image preprocessing for OCR-heavy pages.
3. OCR output is normalized, page-split, filtered for garbage text, and stored for exact lookup.
4. Documents are split into semantic, structure-aware chunks with page/section metadata, parent content, entities, keywords, table hints, section paths, and contextual prefixes.
5. Embeddings are produced by the current Core ML/Natural Language embedding providers. `AppleFMEmbeddingProvider.swift` is explicitly a scaffold and is not an active public Apple embedding path.
6. Chunks are stored in both a full-text index and a vector index.

### Storage

The current storage design is split by retrieval need:

- SQLite FTS5: `SQLiteFullTextService.swift` stores whole-document, chunk, and page-level searchable text in a single SQLite database with `container_id` isolation.
- Fast B-tree content reads: `document_content` provides direct lookup for full document text without scanning FTS tables.
- Per-container vector stores: `VectorStoreRouter.swift` maintains vector database instances per knowledge container and can search all containers when needed.
- Memory-mapped vectors: `BNNSVectorDatabase.swift` persists metadata in `_meta.json`, raw Float32 vectors in `_vectors.bin`, and norms in `_norms.bin`. Large searches use Metal when available; smaller searches use Accelerate/vDSP.

The important correction: container isolation is a `container_id` field inside shared SQLite tables, not one SQLite database per library. Vector stores are per container.

### Query

The query path is adaptive. The 29-step diagram is best understood as a logical/audit model, not a guarantee that every query runs every step.

The current implementation includes:

- Query understanding, pronoun handling, container vocabulary, and corpus-aware expansion.
- HyDE for synthesis-style queries, with extractive/lookup paths protected from hallucinated hypotheticals.
- Hybrid retrieval with vector search, BM25/FTS5, reciprocal rank fusion, MMR, parent-document expansion, and source diversity.
- RAPTOR-lite document-summary routing for overview and "what did this document find" questions.
- Corrective second-pass behavior for low-confidence or exact-value queries.
- Contextual compression and graph-style context packing for multi-hop queries.
- Tool calling when the model needs to choose tools, and direct retrieval injection when the context is already assembled.
- Apple FoundationModels generation through `LanguageModelSession`.
- Structured answer paths using `@Generable`.
- Verification gates A-I, including retrieval confidence, evidence coverage, numeric sanity, contradiction sweep, semantic grounding, quote faithfulness, generation quality, answer completeness, and domain isolation.
- Calibrated confidence and response metadata.

## Hard Truths

### Foundation Models Context

Apple's public Foundation Models framework is the right default, but its context budget is small. Apple's TN3193 says the on-device model has a 4096-token context window per `LanguageModelSession`, and tool schemas, prompts, instructions, `@Generable` schemas, retrieved context, and responses all consume that same budget.

This app should not pitch a 65K-token third-party Apple FoundationModels path unless a future Apple API actually exposes it and the build verifies it. The code currently assumes the safe limit: 4096 tokens for the public FoundationModels path.

### PCC

Private Cloud Compute is Apple's privacy architecture for Apple Intelligence cloud inference. OpenIntelligence can expose consent/config affordances around Apple-managed execution, but it does not own a PCC API, a server model endpoint, or a guaranteed larger context window. In buyer language, say "local-first and Apple Intelligence-aligned," not "we get Apple's server model."

### CAG

Cache-Augmented Generation is useful when the complete knowledge base fits in a long-context model and can be cached. That is not the default shape here. With a 4096-token public FoundationModels session, CAG should be limited to tiny summaries, session continuation, and precomputed library memos. The primary architecture should remain retrieval, compression, verification, and multi-session synthesis.

### Embeddings

Foundation Models are used for generation, guided output, and tool use. Current public code should not imply that Apple's Foundation Models provide a usable embedding API. The active embedding story is Core ML/Natural Language providers plus vector search.

## What's Implemented Well

- Privacy-first document QA with local storage and retrieval.
- Strong exact-value protections for numeric/specification queries.
- Hybrid retrieval instead of vector-only search.
- Page/chunk/document storage that supports both semantic and literal lookup.
- Verification gates that can abstain instead of fabricating.
- Public SDK wrapper and a generated evaluation package.
- Apple-native acceleration through Vision, Core ML, Metal, Accelerate, and FoundationModels.

## Loose Ends Before Selling

1. **PCC copy must stay precise.** App metadata and docs should not promise a 65K FoundationModels context or direct access to Apple's server model.
2. **Pricing source of truth needs one decision.** Code and fastlane still include `doc_pack_addon`; the current Terms view says legacy document packs are no longer sold in-app. Pick one policy before release or buyer demos.
3. **The service count is real, but orchestration is concentrated.** `RAGService.swift` and `DocumentProcessor.swift` carry a lot of behavior. That is fine for a founder demo, but enterprise buyers will eventually ask about maintainability, test boundaries, and deterministic evaluation.
4. **Claims need evaluation artifacts.** For healthcare, EHR, and medical-device sales, do not claim HIPAA compliance, clinical decision support readiness, or diagnostic correctness without a formal security/compliance/evaluation packet.
5. **The SDK exists, but packaging should be treated as evaluation-stage until reproducible.** The generated buyer packet and xcframework are strong demo collateral; the next step is a clean repeatable package build and versioned release process.
6. **Global corpus understanding is partial.** RAPTOR-lite summaries and graph context packing help, but full GraphRAG-style community extraction/summarization is not the current engine. That is an optional future direction, not a shipped claim.

## Sales Framing

Use this positioning:

> OpenIntelligence turns private technical documents into a local-first, cited question-answering engine on Apple devices. It indexes documents into local full-text and vector stores, retrieves only the relevant evidence, answers through Apple Foundation Models, and verifies the answer against source material before showing it.

Best target accounts:

- EHR vendors that need private, device-local document and policy assistance.
- Medical device sales teams that need offline answers from manuals, IFUs, reimbursement docs, and product binders.
- Field service organizations with technical manuals and no-reception environments.
- Legal/compliance teams that need cited source inspection but cannot send documents to third-party APIs.
- Enterprise knowledge teams already standardized on Apple hardware.

Do not lead with consumer subscription pricing in enterprise conversations. Lead with an evaluation pilot: scoped dataset, device requirements, no third-party model egress for core flows, evaluation rubric, and a path to license, acquisition, or design-partner integration.

## Research Index

The split research notes live here:

- [RAG and Retrieval 2024-2026](./Research/RAG_AND_RETRIEVAL_2024_2026.md)
- [CAG and Context Engineering 2024-2026](./Research/CAG_AND_CONTEXT_ENGINEERING_2024_2026.md)
- [Apple Intelligence and Foundation Models](./Research/APPLE_INTELLIGENCE_AND_FOUNDATION_MODELS.md)
- [Core ML, Metal, and On-Device AI](./Research/COREML_METAL_ON_DEVICE_AI.md)
- [Document Intelligence and OCR](./Research/DOCUMENT_INTELLIGENCE_AND_OCR.md)
- [Healthcare, EHR, and Medical-Device RAG](./Research/HEALTHCARE_EHR_AND_MEDICAL_DEVICE_RAG.md)
