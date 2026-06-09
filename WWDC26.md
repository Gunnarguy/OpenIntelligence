Expert Role

iOS AI platform architect and RAG systems reviewer specializing in Apple Intelligence, Foundation Models, Core AI, App Intents, Core Spotlight, Vision, on-device model execution, and large Swift codebase decomposition.

Objective

Create a full AI-workspace-agent handoff for OpenIntelligence that tells the agent exactly what to inspect, what Apple WWDC26 technologies matter, how those technologies map onto the current repo, and how to attack the massive RAGService.swift without destroying working behavior.

Reasoning

OpenIntelligence is not a simple wrapper around Apple Foundation Models. The repository describes it as a local-first Apple-platform RAG product with import-time indexing and query-time retrieval/generation phases. The README documents ingestion, extraction, chunking, metadata enrichment, FTS/vector indexing, retrieval planning, verification, scoring, and cited output rendering.

The app already contains many advanced systems: HyDE, RAPTOR-lite summaries, vector + BM25 hybrid retrieval, cross-encoder reranking, MMR, parent expansion, contextual compression, graph-style context packing, exact-value extraction, verification gates, Deep Think / Maximum agentic modes, and adaptive thermal/battery optimization. The repo’s own RAG technical spec calls this a 29-step adaptive pipeline and notes that the implementation has 107 Swift service files under OpenIntelligence/Services.

WWDC26 changes the target architecture. Apple’s current AI & Machine Learning page says Foundation Models now supports direct access to Apple’s on-device model, any language model provider conforming to the Language Model protocol, multimodal prompts, on-device Vision tools, Dynamic Profiles, Apple Foundation Models on Private Cloud Compute for eligible apps, and the Evaluations framework.   Apple also introduced Core AI as an OS-level, Apple Silicon-oriented framework for loading, specializing, and running your own AI models on-device with a memory-safe Swift API, zero server dependencies, zero token costs, ahead-of-time compilation, zero-copy data paths, and stateful execution.

So the agent’s job is not “add WWDC26 AI.” The job is to convert OpenIntelligence from a powerful but overgrown RAG app into a modular Apple Intelligence-native agent runtime.

Answer

Bottom-line synthesis

OpenIntelligence should become this:

OpenIntelligence vNext
Documents / Images / Audio / User Questions
  ↓
Ingestion Runtime
  ↓
Evidence Index Layer
  ├─ SQLite FTS5
  ├─ Local vector store
  ├─ Core Spotlight semantic/system index
  ├─ Structured table/list index
  ├─ Vision/OCR evidence
  └─ Future Core AI local model outputs
  ↓
Retrieval Router
  ├─ exact lookup
  ├─ spec/table sniper
  ├─ hybrid vector + BM25
  ├─ RAPTOR-lite summary routing
  ├─ parent/chunk expansion
  ├─ graph/cross-reference expansion
  └─ Core Spotlight LLM search
  ↓
Evidence Pack Compiler
  ↓
Model Router
  ├─ extractive-only answer
  ├─ Foundation Models on-device
  ├─ Apple Foundation Model via PCC
  ├─ provider conforming to Language Model protocol
  └─ Core AI / Core ML specialized local models
  ↓
Structured Answer Generator
  ↓
Verification + Source-only Fidelity Gate
  ↓
UI + App Intents + Spotlight + Siri + Evaluations

Your agent should treat RAGService.swift as a legacy mega-orchestrator that must be strangled gradually, not rewritten. It is currently doing ingestion, model routing, cloud consent, query planning, retrieval, context packing, answer generation, verification, telemetry, haptics, transcript persistence, live activity state, Spotlight indexing, and self-tuning. That is too much for one component.

The correct strategy is:

Preserve behavior first.
Extract boundaries second.
Swap Apple WWDC26 primitives into those boundaries third.
Only then optimize.

⸻

What WWDC26 actually means for OpenIntelligence

Apple capability map

Apple WWDC26 area	What Apple released / emphasized	OpenIntelligence relevance	Priority
Foundation Models Language Model protocol	Work with Apple models, Claude/Gemini/cloud models, or any provider conforming to Apple’s protocol	Replace your ad hoc LLMService backend abstraction with an Apple-aligned backend interface	10/10
Multimodal prompts	Images + text in model prompts	Upgrade camera/photo/screenshot analysis from OCR-only into true multimodal evidence reasoning	9/10
Vision tools callable by models	OCR/barcode/custom tools callable on-device	Let model choose OCR/barcode/image evidence tools during visual RAG	8/10
Dynamic Profiles	Swap models, tools, instructions during a continuous session	Replace repeated session resets/tool toggles with profile-based execution states	9/10
Apple Foundation Model on PCC	Larger Apple model via Private Cloud Compute for eligible apps	Use for complex Deep Think / Maximum tasks, with explicit consent and fallback	9/10
Evaluations framework	Systematic testing for AI behavior beyond unit tests	Turn your RAG diagnostics into formal evals	10/10
Core AI	Bring custom models on-device with Swift API, specialization, AOT compile, memory control	Future home for local rerankers, embeddings, classifiers, compact VLMs, custom extractors	8/10
MLX improvements	Mac-side local agentic AI, training, fine-tuning	Use for Mac eval/training workflows, not iOS runtime first	5/10
Core Spotlight LLM search	LLM-aware search using Spotlight	Promote Spotlight from document discoverability to retrieval plane	9/10
App Intents schemas/entities	Make app content/actions available to Siri/Apple Intelligence	Convert current intents into entity-native Apple Intelligence actions	9/10
View Annotations	Make on-screen content available to Siri/Apple Intelligence	Let Siri operate on the active document, selected answer, citations, and current query	8/10
App Intents Testing	Test intents and Apple Intelligence integrations	Add regression tests for Siri/Shortcut workflows	7/10
Visual Intelligence	Image actions and entity results	Connect camera/image flows to real evidence packs	8/10

⸻

Repo diagnosis

Your actual app is already advanced

The repo’s README lists the main engine files by responsibility:

Area	Existing files	Current role
Ingestion	DocumentProcessor, IntelligentDocumentProcessor, StructuredDocumentParser, LayoutAwareExtractor	PDF/image/text/audio extraction and recovery
Chunking	SemanticChunker, ContentTaggingService, EntityIndexService	Chunks, metadata, entities, tags
Indexing	EmbeddingService, SQLiteFullTextService, VectorStoreRouter, BNNSVectorDatabase	Local FTS5 + vector index
Query planning	QueryProfileService, QueryRewriterService, HyDEService	Intent, rewriting, HyDE
Retrieval	HybridSearchService, IterativeRetrievalService, ParentDocumentService, ContextPackingService	Hybrid retrieval and context shaping
Orchestration	ExtractiveQAService, LLMService, AgenticOrchestrator, RAGService	Generation, validation, agentic flows
Diagnostics	RAGPipelineAuditView, DebugRAGValidationHarness, run_rag_benchmarks.py	Pipeline inspection and benchmark path

Source: repo file map.

The repo also states hard technical constants: 4,096 total token context, 384-dimensional embeddings, SQLite FTS5 BM25 tuning, and a 0.70 semantic evidence-overlap confidence gate.

RAGService.swift is doing too much

RAGService.swift is 16,631 lines in the fetched file. It imports Foundation, CryptoKit, NaturalLanguage, UIKit when available, and FoundationModels when available. It also notes that GGUF/CoreML/MLX local LLM support was removed and the app now uses Apple Intelligence plus On-Device Analysis.

The class owns dependencies for document processing, embeddings, containers, vector routing, library intelligence, document summaries, query routing, graph indexing, context packing, extractive summarization, specification extraction, entitlement state, settings, cloud consent, ingestion state, live activity tracking, and cache state.

That means RAGService currently has at least 12 responsibilities:

Responsibility	Should remain in RAGService?	Target owner
Public facade for app queries	Yes	RAGService thin facade
Document ingestion queue	No	DocumentIngestionCoordinator
Extraction/chunking pipeline	No	DocumentProcessingPipeline
Embedding provider resolution	No	EmbeddingRoutingService
Vector store access	No	already partly VectorStoreRouter
Spotlight indexing	No	SpotlightEvidenceIndexService
Chat history persistence	No	ConversationStateStore
FoundationModels transcript persistence	No	FoundationModelTranscriptStore
PCC consent	No	CloudExecutionConsentService
Query planning	No	QueryPlanningPipeline
Retrieval/reranking/filtering	No	RetrievalPipeline
Context packing	No	EvidencePackCompiler
Generation/fallback	No	AnswerGenerationPipeline
Verification/source-only refinement	No	AnswerVerificationPipeline
Telemetry/haptics	No	PipelineTelemetrySink

The goal is not to delete RAGService. The goal is to reduce it to a stable façade:

@MainActor
final class RAGService: ObservableObject, KnowledgeRetrievalEngine, RAGToolHandler {
    private let queryRuntime: QueryRuntimeCoordinator
    private let ingestionRuntime: DocumentIngestionCoordinator
    private let conversationStore: ConversationStateStore
    func query(_ request: RetrievalRequest) async throws -> RAGResponse {
        try await queryRuntime.query(request)
    }
    func enqueueDocuments(_ urls: [URL], context: IngestionContext) -> [UUID] {
        ingestionRuntime.enqueue(urls, context: context)
    }
}

⸻

Existing strengths the agent should preserve

1. Precision/extractive path

You already have direct source extraction before deeper agentic reasoning. executeAgenticPrecisionLookupIfAvailable classifies answer intent, checks extractive/precision-value cases, and can build a direct source extraction response without using generated tokens.

Preserve this. It is probably one of the app’s strongest differentiators.

Rule for agent:

Never route exact-value, count, table, code, dosage, specification, statute, or numeric lookup questions directly to free-form generation when extractive evidence is available.

2. Spec Table Sniper

You have a targeted retrieval path that bypasses semantic similarity and searches all chunks for query keywords plus numeric/structured data. The code comments explicitly state that the reranker has a prose bias and that this method is designed for specification tables, medical dosages, legal statute numbers, financial figures, and factual lookup targets.

Preserve this. Core Spotlight and Apple Foundation Models should augment it, not replace it.

3. Sentence-level extraction

For lookup queries, the app can extract relevant sentences from all candidates and fit targeted lines from 10–15+ chunks instead of packing only a few whole chunks.   The implementation uses unit/spec/code regexes for numeric and structured evidence.

Preserve this as SentenceEvidenceExtractor.

4. Query planning and quality modes

You have user-visible Standard, Deep Think, and Maximum modes. The quality mode file maps them to topK, similarity thresholds, temperature, agentic usage, HyDE, reranking, MMR, verification, query expansion, and contextual compression.

Preserve the mode semantics, but move them into an execution policy layer.

5. RAG audit snapshot

RAGAuditSnapshot already tracks embedding provider, vector DB kind, chunking, retrieval config, similarity metrics, context strategy, token budget, execution context, PCC allowance, network state, reliability mode, feature flags, and recursive RAG metrics.

This should become the schema for formal Evaluations.

6. Core Spotlight already exists

My earlier hypothesis that Spotlight was missing was too broad. You already have SpotlightIndexService. It indexes containers and documents for Spotlight, Siri, and system-wide search.

But it currently indexes document-level metadata and a text preview, not section/chunk/table/citation-level evidence. The document indexing API stores title, content description, container metadata, optional page/chunk count, keywords, kind, and expiration.

So the WWDC26 upgrade is not “add Spotlight.” It is:

Upgrade Spotlight from discoverability index → semantic retrieval plane.

⸻

Major gaps against WWDC26

Gap 1 – Foundation Models integration is powerful but monolithic

AppleFoundationLLMService owns session lifecycle, transcripts, tools, token estimation, prompts, streaming, haptics, telemetry, post-processing, continuation, structured generation, and error mapping.

It also infers on-device vs PCC from time-to-first-token. The code labels <1.0s as on-device and otherwise as Private Cloud Compute.   The same code correctly notes that it cannot force PCC and that Apple’s system routing depends on factors like context size, complexity, thermals, battery, and consent.

Agent instruction:

Do not expose TTFT-based PCC/on-device detection as truth in user-facing UI. Keep it as diagnostics only.

Gap 2 – Token budgeting is still heuristic

ContextPackingService uses tokensPerChar = 0.71, and LLMService.swift uses a 1.4 chars/token estimate.

WWDC26 Foundation Models should push the app toward official context/token APIs when available. Apple’s page specifically emphasizes current Foundation Models changes including Dynamic Profiles, multimodal prompts, provider protocol, PCC, and Evaluations, which makes static 4K heuristics brittle.

Gap 3 – Visual Intelligence path does not fully use image evidence

AnalyzeImageIntent extracts OCR text from an image, but when a question is provided it calls ragService.query(question, topK: 3, config: config) without passing the extracted OCR text as evidence.

That means the image analysis path can display OCR but not necessarily ground the answer in that OCR.

Fix:

Image OCR/multimodal evidence must become a first-class EvidenceSource.

Gap 4 – App Intents are command wrappers, not entity-native Apple Intelligence surfaces

RAGAppIntents.swift has useful intents for querying, listing documents, and import status.

But WWDC26’s App Intents push is deeper: entity schemas can contribute app content to Spotlight’s semantic index, and View Annotations can make onscreen content available to Siri/Apple Intelligence.

Your agent should build:

OIDocumentEntity
OILibraryEntity
OIChunkEntity
OICitationEntity
OIAnswerEntity
OIIngestionJobEntity

Gap 5 – Evaluations are not yet first-class

The repo has diagnostics and run_rag_benchmarks.py, but WWDC26’s Evaluations framework should become the governing layer. Apple says the Evaluations framework lets you test prompts and validate intelligence-powered features reliably in development workflows.

Your app should not ship future RAG changes without eval deltas.

⸻

The architecture the agent should build toward

Target module tree

OpenIntelligence/Services/AIPlatform/
  AppleFoundationModels/
    FoundationModelBackend.swift
    FoundationModelSessionFactory.swift
    FoundationModelDynamicProfileRegistry.swift
    FoundationModelToolRegistry.swift
    FoundationModelPromptCompiler.swift
    FoundationModelTokenBudget.swift
    FoundationModelStructuredGenerator.swift
    FoundationModelErrorMapper.swift
    FoundationModelTranscriptStore.swift
  CoreAI/
    CoreAIModelRegistry.swift
    CoreAIExecutionBackend.swift
    CoreAIEmbeddingBackend.swift
    CoreAIRerankerBackend.swift
    CoreAIImageUnderstandingBackend.swift
  ModelRouting/
    ModelRouter.swift
    ModelRoute.swift
    ModelExecutionPolicy.swift
    ModelAvailabilitySnapshot.swift
    CloudExecutionPolicy.swift
    ModelResolutionService.swift
OpenIntelligence/Services/RAGPipeline/
  QueryPlanning/
    QueryRuntimeCoordinator.swift
    QueryPlan.swift
    QueryPlanCompiler.swift
    QueryModePolicy.swift
  Retrieval/
    RetrievalPipeline.swift
    RetrievalRequestContext.swift
    HybridRetrievalStage.swift
    SpotlightRetrievalStage.swift
    SpecTableSniperStage.swift
    CrossReferenceResolutionStage.swift
    ParentExpansionStage.swift
    RerankingStage.swift
    MMRStage.swift
    EvidenceFilteringStage.swift
  Evidence/
    EvidenceSource.swift
    EvidencePack.swift
    EvidencePackCompiler.swift
    SentenceEvidenceExtractor.swift
    CitationAnchorResolver.swift
    VisualEvidenceSource.swift
    TableEvidenceSource.swift
  Generation/
    AnswerGenerationPipeline.swift
    ExtractiveAnswerRoute.swift
    StructuredFoundationModelRoute.swift
    ToolCallingFoundationModelRoute.swift
    AgenticAnswerRoute.swift
    DirectChatRoute.swift
  Verification/
    AnswerVerificationPipeline.swift
    SourceOnlyFidelityGate.swift
    CitationVerifier.swift
    NumericSanityVerifier.swift
    AbstentionPolicy.swift
OpenIntelligence/Services/SystemIntegration/
  Spotlight/
    SpotlightEvidenceIndexService.swift
    SpotlightReindexCoordinator.swift
  Intents/
    OIDocumentEntity.swift
    OILibraryEntity.swift
    OIQueryDocumentsIntent.swift
    OISummarizeDocumentIntent.swift
    OICompareDocumentsIntent.swift
    OIAskCurrentDocumentIntent.swift
    OpenIntelligenceShortcutsProvider.swift
  VisualIntelligence/
    VisualEvidenceIngestionService.swift
    ImageQuestionAnsweringService.swift
OpenIntelligence/Services/Evaluation/
  RAGEvalCase.swift
  RAGEvalDataset.swift
  RAGEvalRunner.swift
  RAGEvalMetrics.swift
  RAGEvalReportWriter.swift
  AppleEvaluationsBridge.swift

⸻

PR backlog for the AI workspace agent

PR 0 – Repo reconnaissance and safety rails

Goal: Do not touch behavior yet.

Agent tasks:

1. Count lines and public APIs of RAGService.swift.
2. Generate a call graph for:
   - query(...)
   - queryInternal(...)
   - addDocument(...)
   - runIngestionLoop()
   - generateWithFallback(...)
   - executeAgenticQuery(...)
3. Generate a dependency graph of:
   - FoundationModels
   - AppIntents
   - CoreSpotlight
   - Vision
   - CoreML
   - NaturalLanguage
   - Accelerate/BNNS/Metal
4. Add Docs/AI_AGENT_MAP.md documenting all major service boundaries.
5. Do not change runtime behavior.

Acceptance criteria:

Metric	Target
Runtime behavior changed	0
New docs	1+
Build status	Passing
Agent can identify entry points	Yes

⸻

PR 1 – Extract token budgeting

Why: Token budget estimates are duplicated and heuristic.

Agent tasks:

Create:
OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelTokenBudget.swift
Move:
- context window constants
- chars/token fallback
- transcript token estimation
- prompt/context/output reserve calculations
- overflow retry budget calculations
Use official FoundationModels token/context APIs where available.
Keep current 1.4 chars/token and 0.71 tokens/char only as fallback.

Current code to inspect:

OpenIntelligence/Services/LLM/LLMService.swift
OpenIntelligence/Services/RAG/Retrieval/ContextPackingService.swift
OpenIntelligence/Services/RAG/Orchestration/RAGService.swift

Expected improvement:

Outcome	Estimated impact
Context overflow reduction	30–60%
Over-trimming reduction	15–35%
Regression risk	20–30%

⸻

PR 2 – Split AppleFoundationLLMService

Why: Foundation Models behavior is too centralized.

Agent tasks:

Extract behavior-preserving components:
1. FoundationModelSessionFactory
2. FoundationModelToolRegistry
3. FoundationModelPromptCompiler
4. FoundationModelStructuredGenerator
5. FoundationModelErrorMapper
6. FoundationModelTranscriptStore
Keep AppleFoundationLLMService as a thin facade.
Do not rewrite prompts in this PR.

Preserve:

* Tool surface: retrieve_corpus_evidence, inspect_document, compare_topic_across_documents, get_library_overview
* Streaming behavior
* Structured generation
* Existing error handling
* Transcript restore semantics
* Prewarm behavior

Your current tool surface is already close to Apple guidance because it consolidated many tools into 4 core tools.

⸻

PR 3 – Replace session-reset patterns with Dynamic Profiles where possible

Apple says Dynamic Profiles let apps swap models, tools, and instructions within a continuous session.

Current issue:

ensureSession() rebuilds sessions depending on tools, system prompts, transcripts, and context.

Agent tasks:

Create:
FoundationModelDynamicProfileRegistry.swift
Profiles:
- directChat
- groundedRAG
- extractiveRAG
- toolCallingRAG
- sourceOnlyVerifier
- summarization
- queryPlanning
- visualEvidenceQA
Do not enable Dynamic Profiles unless the local SDK confirms availability.
Add compile-time gating and fallback to current session recreation.

Expected improvement:

Metric	Target
Session churn	-30–50%
Prompt/tool mismatch bugs	-20–40%
First-token latency variance	-10–25%

⸻

PR 4 – Create QueryRuntimeCoordinator

Why: queryInternal is carrying too many pipeline stages.

Current query path includes:

* Reliability mode
* PCC/network routing
* quality mode
* query profile
* query execution plan
* force-agentic logic
* adaptive thermal/battery config
* embedding context
* agentic route
* standard route
* telemetry and audit

This is visible in the queryInternal section.

Agent tasks:

Create QueryRuntimeCoordinator.
Move from RAGService:
- query mode resolution
- execution policy resolution
- adaptive config selection
- model/cloud eligibility calculation
- query plan creation
- branch to standard vs agentic pipeline
Leave RAGService.query(...) as the public facade.

No behavior change target: 100%.

⸻

PR 5 – Extract RetrievalPipeline

The retrieval section is doing query expansion, intent classification, HyDE, embedding, caching, RAPTOR-lite, hybrid retrieval, cascade, keyword retry, rerank, filtering, spec rescue, enumeration pass, parent expansion, cross-reference resolution, spec sniper, compression, MMR, and context candidates.

Agent tasks:

Create RetrievalPipeline.swift.
Break into stages:
1. QueryExpansionStage
2. IntentClassificationStage
3. HyDEStage
4. QueryEmbeddingStage
5. RetrievalCacheStage
6. RAPTORRoutingStage
7. HybridRetrievalStage
8. RetrievalCascadeStage
9. KeywordRetryStage
10. RerankingStage
11. EvidenceFilteringStage
12. SpecPreservationStage
13. EnumerationRetrievalStage
14. ParentExpansionStage
15. CrossReferenceResolutionStage
16. SpecTableSniperStage
17. ContextualCompressionStage
18. MMRCandidateSelectionStage
Each stage should emit stage metrics into RAGAuditSnapshot or a new PipelineTrace.

Preserve specific behavior:

* HyDE disabled for extractive intents.
* RAPTOR-lite summary routing.
* retrieval cascade.
* keyword retry.
* spec preservation.
* enumeration iterative retrieval.
* parent expansion.
* cross-reference resolution and spec sniper.
* contextual compression gating.

⸻

PR 6 – Upgrade Spotlight into an evidence retrieval plane

You already index documents and containers in Spotlight.

Now upgrade it.

Agent tasks:

Create SpotlightEvidenceIndexService.swift.
Index these item types:
1. Library
2. Document
3. Section
4. Page
5. Table
6. List
7. Figure/OCR block
8. Citation anchor
9. Saved answer
10. Saved query
Each searchable item should include:
- stable uniqueIdentifier
- domainIdentifier = library/container id
- title
- contentDescription
- textContent or searchable content
- section path
- page number
- document id
- chunk id
- deep link URL
- content tags
- structured metadata for table/list/figure

Retrieval integration:

Hybrid retrieval score =
  vector score
  + FTS5/BM25 score
  + Core Spotlight semantic/search score
  + exact/spec/table score

Expected impact:

Outcome	Estimate
Spotlight/Siri discoverability	+70–90%
Section-level recall	+20–40%
System integration quality	+50–70%
Index consistency risk	25–35%

⸻

PR 7 – Make Visual Intelligence actually evidence-grounded

Current bug/weakness: AnalyzeImageIntent extracts OCR text but does not pass it into the answer context when answering the user’s question.

Agent tasks:

Create VisualEvidenceSource.swift.
For image/photo/screenshot questions:
1. Extract OCR text.
2. Extract barcode/QR if available.
3. Preserve bounding boxes if Vision returns them.
4. Optionally pass image + text into multimodal Foundation Models route.
5. Convert OCR output into temporary EvidenceSource.
6. Merge with document-library evidence.
7. Cite evidence source as:
   - [Image OCR]
   - [Image Region]
   - [Document, p.X]

Do not just query with:

ragService.query(question)

Instead route:

ragService.query(
    RetrievalRequest(
        question: question,
        externalEvidence: [.imageOCR(extractedText, metadata)]
    )
)

⸻

PR 8 – Build entity-native App Intents

Current: Useful but simple command intents.

Target:

struct OIDocumentEntity: AppEntity
struct OILibraryEntity: AppEntity
struct OICitationEntity: AppEntity
struct OIIngestionJobEntity: AppEntity

Agent tasks:

Replace fresh RAGService() inside intents with persistent storage-backed entity resolution.
Add intents:
- AskDocumentIntent
- SummarizeDocumentIntent
- CompareDocumentsIntent
- SearchLibraryIntent
- ExplainCurrentAnswerIntent
- ShowCitationSourceIntent
- CheckImportStatusIntent
- AddDocumentToLibraryIntent
Add AppShortcutsProvider phrases:
- "Ask OpenIntelligence about \(.applicationName)"
- "Summarize \(\.$document) in OpenIntelligence"
- "Compare \(\.$documentA) and \(\.$documentB)"
- "Find documents about \(\.$topic)"
- "What is OpenIntelligence importing?"

Why: Apple says App Intents are the way to connect app actions/content to Apple Intelligence and Siri, with schemas, entity schemas, Spotlight semantic indexing, View Annotations, and App Intents Testing.

⸻

PR 9 – Add ModelResolutionService for real

You have a disabled ModelResolutionService.swift behind #if false. The file says it should centralize what model the user selected, what model is actually running, and why.

Rebuild it.

Agent tasks:

Create compiling ModelResolutionService.
Track:
- selected model
- actual backend
- route type
- extractive-only vs generated
- Foundation Models availability
- Apple Intelligence not enabled
- model not ready
- device not eligible
- PCC allowed/denied/not determined
- network availability
- provider fallback reason
- whether TTFT-based execution location is only estimated

Do not say:

"Ran on PCC"

unless Apple exposes that directly.

Say:

"System-routed Apple Foundation Model"
"Execution location estimated from latency"
"Cloud eligible"
"Cloud blocked by user setting"

⸻

PR 10 – Formal Evaluations

Apple’s Evaluations framework exists specifically to validate AI features under dynamic conditions.   Your repo already has diagnostics and run_rag_benchmarks.py.

Agent tasks:

Create:
OpenIntelligence/Services/Evaluation/
Docs/EVALS.md
Tests/RAGEvaluationTests/
JSONL eval format:
{
  "id": "oil_capacity_exact_001",
  "libraryFixture": "car_manual_fixture",
  "query": "How much engine oil does this car take?",
  "answerType": "exact_value",
  "expectedAnswerContains": ["0W-20", "5.1 qt"],
  "expectedCitations": ["Recommended lubricants"],
  "forbiddenClaims": ["5W-30", "diesel"],
  "minConfidence": 0.85,
  "shouldAbstain": false
}

Metrics:

Metric	Target
retrieval recall@5	≥ 0.85
citation precision	≥ 0.90
exact-value accuracy	≥ 0.95
unsupported-claim rate	≤ 0.05
correct abstention rate	≥ 0.85
context overflow rate	≤ 0.02
no-doc fallback correctness	≥ 0.95
visual OCR evidence use	≥ 0.90
median TTFT on-device	≤ 1.5s
median total Standard query	≤ 6s
Deep Think completion without cancellation	≥ 0.90

⸻

WWDC26-specific implementation map

Feature	Existing code	Required change
Foundation Models provider protocol	LLMService custom protocol	Create LanguageModelBackend aligned with Apple’s Language Model protocol
Dynamic Profiles	ensureSession() rebuilds sessions	Add profile registry and fallback to current session behavior
Multimodal prompts	Vision OCR + text-only query	Add VisualEvidenceSource and multimodal route
Vision tools callable by model	Manual Vision OCR	Add tool-wrapped OCR/barcode/image tools
PCC Apple model	Cloud consent + execution context	Move to CloudExecutionPolicy; do not infer execution as fact
Evaluations	scripts + diagnostics	Add formal eval datasets + Apple Evaluations bridge
Core AI	Core ML embeddings/reranker today	Add CoreAIModelRegistry for future custom local models
Core Spotlight LLM search	document/container Spotlight index	Index chunks/sections/tables/citations and query as retrieval plane
App Intents schemas	classic intents	AppEntity + EntityQuery + AppShortcutsProvider
View Annotations	not confirmed in inspected files	Annotate active doc/answer/citations for Siri/Apple Intelligence
App Intents Testing	not confirmed	Add tests for entity resolution and Siri workflows

⸻

Full AI workspace agent prompt

Paste this into your agent.

You are working in the repository:
https://github.com/Gunnarguy/OpenIntelligence
Mission:
Modernize OpenIntelligence for WWDC26 Apple Intelligence, Foundation Models, Core AI, App Intents, Core Spotlight, Visual Intelligence, and Evaluations. Do not rewrite the app. Decompose the existing mega-orchestrator safely and preserve behavior.
Context:
OpenIntelligence is a local-first Apple-native RAG/document intelligence app. The repo already contains a sophisticated RAG pipeline with:
- document ingestion
- PDF/image/OCR extraction
- structured table/list handling
- SQLite FTS5
- local vector embeddings
- BNNS/Metal vector search
- hybrid vector + BM25 retrieval
- query planning
- HyDE
- RAPTOR-lite summaries
- cross-encoder reranking
- MMR
- parent/sibling expansion
- cross-reference resolution
- spec/table sniper
- sentence-level extraction
- contextual compression
- graph-style context packing
- direct extractive answers
- FoundationModels generation
- structured answers
- verification gates
- Deep Think / Maximum agentic modes
- telemetry and audit views
Read these files first:
1. README.md
2. Docs/ARCHITECTURE.md
3. Docs/Engineering/RAG_TECHNICAL.md
4. Package.swift
5. OpenIntelligence/Services/RAG/Orchestration/RAGService.swift
6. OpenIntelligence/Services/LLM/LLMService.swift
7. OpenIntelligence/Services/RAG/Retrieval/ContextPackingService.swift
8. OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift
9. OpenIntelligence/Services/RAG/Retrieval/IterativeRetrievalService.swift
10. OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift
11. OpenIntelligence/Services/RAG/Tuning/EvidenceScoringPolicyService.swift
12. OpenIntelligence/Services/Query/Analysis/QueryProfileService.swift
13. OpenIntelligence/Services/Query/Routing/QueryRouterService.swift
14. OpenIntelligence/Services/Query/Rewriting/HyDEService.swift
15. OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift
16. OpenIntelligence/Services/Embedding/EmbeddingService.swift
17. OpenIntelligence/Services/VectorStore/VectorStoreRouter.swift
18. OpenIntelligence/Services/Infrastructure/Background/SpotlightIndexService.swift
19. OpenIntelligence/Services/Agentic/RAGAppIntents.swift
20. OpenIntelligence/Services/Agentic/VisualIntelligenceIntents.swift
21. OpenIntelligence/Services/Agentic/WritingToolsService.swift
22. OpenIntelligence/Services/LLM/ModelResolutionService.swift
Apple WWDC26 research URLs:
https://developer.apple.com/apple-intelligence/
https://developer.apple.com/apple-intelligence/whats-new/
https://developer.apple.com/machine-learning/
https://developer.apple.com/machine-learning/whats-new/
https://developer.apple.com/documentation/foundationmodels
https://developer.apple.com/documentation/Updates/FoundationModels
https://developer.apple.com/documentation/foundationmodels/languagemodelsession
https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel
https://developer.apple.com/documentation/foundationmodels/tool
https://developer.apple.com/documentation/foundationmodels/generable
https://developer.apple.com/documentation/foundationmodels/generationoptions
https://developer.apple.com/documentation/foundationmodels/prompt
https://developer.apple.com/documentation/foundationmodels/instructions
https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation
https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling
https://developer.apple.com/documentation/foundationmodels/analyzing-the-runtime-performance-of-your-foundation-models-app
https://developer.apple.com/documentation/FoundationModels/evaluating-prompts-to-measure-performance-and-improve-model-responses
https://developer.apple.com/documentation/corespotlight
https://developer.apple.com/documentation/appintents
https://developer.apple.com/documentation/vision
https://developer.apple.com/documentation/coreml
https://github.com/ml-explore/mlx
Critical Apple WWDC26 concepts to map:
1. Foundation Models Language Model protocol
2. Dynamic Profiles
3. Multimodal prompts
4. Vision tools callable by models
5. Apple Foundation Model on Private Cloud Compute
6. Evaluations framework
7. fm CLI and Python SDK
8. Core AI
9. MLX improvements
10. LLM search using Core Spotlight
11. App Intents schemas
12. Entity schemas
13. View Annotations
14. App Intents Testing
15. Visual Intelligence actions and result types
Hard constraints:
- Do not rewrite RAGService in one PR.
- Preserve exact-value/direct extraction paths.
- Preserve spec/table sniper behavior.
- Preserve sentence-level extraction.
- Preserve container/library isolation.
- Preserve local-first privacy posture.
- Do not expose TTFT-based PCC detection as confirmed execution location.
- Do not attach more than 5 tools to a Foundation Models session unless there is a measured reason.
- Do not send extracted private document content to a cloud/provider path without explicit policy/consent.
- Use official FoundationModels token/context APIs where available. Keep char/token heuristics only as fallback.
- Every refactor must compile and must be behavior-preserving unless explicitly marked as a feature PR.
PR sequence:
PR 0: Create Docs/AI_AGENT_MAP.md with call graph and module map.
PR 1: Extract FoundationModelTokenBudget.
PR 2: Split AppleFoundationLLMService into session factory, tool registry, prompt compiler, structured generator, error mapper, transcript store.
PR 3: Add Dynamic Profile registry with fallback to current session recreation.
PR 4: Create QueryRuntimeCoordinator and move top-level query routing out of RAGService.
PR 5: Create RetrievalPipeline and extract retrieval stages one by one.
PR 6: Upgrade Spotlight from document-level discoverability to chunk/section/table/citation evidence retrieval.
PR 7: Fix VisualIntelligenceIntents so OCR/multimodal image evidence is actually included in answer evidence packs.
PR 8: Convert RAGAppIntents into entity-native App Intents with AppEntity and EntityQuery.
PR 9: Rebuild ModelResolutionService as a compiling model/backend/execution route truth surface.
PR 10: Add formal RAG evaluations with JSONL eval cases and metrics.
Acceptance metrics:
- Build passes.
- Existing behavior preserved.
- RAGService line count decreases by at least 15% after PR 5.
- Exact-value accuracy does not regress.
- Retrieval recall@5 does not regress.
- Citation precision does not regress.
- Context overflow rate decreases.
- Visual image question-answering uses image evidence.
- App Intents resolve persisted entities, not fresh empty RAGService instances.
- Evaluation harness produces JSON/Markdown reports.

⸻

Agent reading list: repo URLs

https://github.com/Gunnarguy/OpenIntelligence
https://github.com/Gunnarguy/OpenIntelligence/blob/main/README.md
https://github.com/Gunnarguy/OpenIntelligence/blob/main/Docs/ARCHITECTURE.md
https://github.com/Gunnarguy/OpenIntelligence/blob/main/Docs/Engineering/RAG_TECHNICAL.md
https://github.com/Gunnarguy/OpenIntelligence/blob/main/Package.swift
https://github.com/Gunnarguy/OpenIntelligence/blob/main/OpenIntelligence/Services/RAG/Orchestration/RAGService.swift
https://github.com/Gunnarguy/OpenIntelligence/blob/main/OpenIntelligence/Services/RAG/Orchestration/RAGService%2BKnowledgeRetrievalEngine.swift
https://github.com/Gunnarguy/OpenIntelligence/blob/main/OpenIntelligence/Core/Protocols/EngineInterfaces.swift
https://github.com/Gunnarguy/OpenIntelligence/blob/main/OpenIntelligence/Core/Models/RAGQualityMode.swift
https://github.com/Gunnarguy/OpenIntelligence/blob/main/OpenIntelligence/Services/LLM/LLMService.swift
https://github.com/Gunnarguy/OpenIntelligence/blob/main/OpenIntelligence/Services/LLM/ModelResolutionService.swift
https://github.com/Gunnarguy/OpenIntelligence/blob/main/OpenIntelligence/Services/LLM/PromptEvaluationService.swift
https://github.com/Gunnarguy/OpenIntelligence/blob/main/OpenIntelligence/Services/RAG/Retrieval/ContextPackingService.swift
https://github.com/Gunnarguy/OpenIntelligence/blob/main/OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift
https://github.com/Gunnarguy/OpenIntelligence/blob/main/OpenIntelligence/Services/RAG/Retrieval/IterativeRetrievalService.swift
https://github.com/Gunnarguy/OpenIntelligence/blob/main/OpenIntelligence/Services/RAG/Retrieval/ParentDocumentService.swift
https://github.com/Gunnarguy/OpenIntelligence/blob/main/OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift
https://github.com/Gunnarguy/OpenIntelligence/blob/main/OpenIntelligence/Services/RAG/Tuning/EvidenceScoringPolicyService.swift
https://github.com/Gunnarguy/OpenIntelligence/blob/main/OpenIntelligence/Services/Query/Analysis/QueryProfileService.swift
https://github.com/Gunnarguy/OpenIntelligence/blob/main/OpenIntelligence/Services/Query/Analysis/SpecificationExtractor.swift
https://github.com/Gunnarguy/OpenIntelligence/blob/main/OpenIntelligence/Services/Query/Routing/QueryRouterService.swift
https://github.com/Gunnarguy/OpenIntelligence/blob/main/OpenIntelligence/Services/Query/Rewriting/HyDEService.swift
https://github.com/Gunnarguy/OpenIntelligence/blob/main/OpenIntelligence/Services/Query/Rewriting/QueryRewriterService.swift
https://github.com/Gunnarguy/OpenIntelligence/blob/main/OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift
https://github.com/Gunnarguy/OpenIntelligence/blob/main/OpenIntelligence/Services/Agentic/RAGAppIntents.swift
https://github.com/Gunnarguy/OpenIntelligence/blob/main/OpenIntelligence/Services/Agentic/VisualIntelligenceIntents.swift
https://github.com/Gunnarguy/OpenIntelligence/blob/main/OpenIntelligence/Services/Agentic/WritingToolsService.swift
https://github.com/Gunnarguy/OpenIntelligence/blob/main/OpenIntelligence/Services/Embedding/EmbeddingService.swift
https://github.com/Gunnarguy/OpenIntelligence/blob/main/OpenIntelligence/Services/VectorStore/VectorStoreRouter.swift
https://github.com/Gunnarguy/OpenIntelligence/blob/main/OpenIntelligence/Services/Infrastructure/Background/SpotlightIndexService.swift

⸻

Agent reading list: Apple URLs

https://developer.apple.com/apple-intelligence/
https://developer.apple.com/apple-intelligence/whats-new/
https://developer.apple.com/apple-intelligence/get-started/
https://developer.apple.com/apple-intelligence/resources/
https://developer.apple.com/machine-learning/
https://developer.apple.com/machine-learning/whats-new/
https://developer.apple.com/machine-learning/resources/
https://developer.apple.com/documentation/foundationmodels
https://developer.apple.com/documentation/Updates/FoundationModels
https://developer.apple.com/documentation/foundationmodels/languagemodelsession
https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel
https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/default
https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/usecase
https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/guardrails
https://developer.apple.com/documentation/foundationmodels/tool
https://developer.apple.com/documentation/foundationmodels/generable
https://developer.apple.com/documentation/foundationmodels/guide%28description%3A%29
https://developer.apple.com/documentation/foundationmodels/prompt
https://developer.apple.com/documentation/foundationmodels/instructions
https://developer.apple.com/documentation/foundationmodels/generationoptions
https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation
https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling
https://developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model
https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models
https://developer.apple.com/documentation/foundationmodels/categorizing-and-organizing-data-with-content-tags
https://developer.apple.com/documentation/FoundationModels/updating-prompts-for-new-model-versions
https://developer.apple.com/documentation/foundationmodels/analyzing-the-runtime-performance-of-your-foundation-models-app
https://developer.apple.com/documentation/FoundationModels/evaluating-prompts-to-measure-performance-and-improve-model-responses
https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output
https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework/
https://developer.apple.com/documentation/corespotlight
https://developer.apple.com/documentation/corespotlight/adding-your-app-s-content-to-spotlight-indexes
https://developer.apple.com/documentation/corespotlight/searching-for-information-in-your-app
https://developer.apple.com/documentation/corespotlight/building-a-search-interface-for-your-app
https://developer.apple.com/documentation/corespotlight/cssearchableitem
https://developer.apple.com/documentation/corespotlight/cssearchableindex
https://developer.apple.com/documentation/corespotlight/csuserquerycontext
https://developer.apple.com/documentation/appintents
https://developer.apple.com/documentation/appintents/appintent
https://developer.apple.com/documentation/appintents/app-intents
https://developer.apple.com/documentation/appintents/app-intent-domains
https://developer.apple.com/documentation/appintents/assistantschema
https://developer.apple.com/documentation/appintents/integrating-actions-with-siri-and-apple-intelligence
https://developer.apple.com/documentation/AppIntents/Making-onscreen-content-available-to-siri-and-apple-intelligence
https://developer.apple.com/documentation/appintents/making-in-app-search-actions-available-to-siri-and-apple-intelligence
https://developer.apple.com/documentation/vision
https://developer.apple.com/documentation/visionkit
https://developer.apple.com/documentation/imageplayground
https://developer.apple.com/documentation/coreml
https://github.com/ml-explore/mlx
https://github.com/huggingface/swift-transformers

⸻

Final ranked attack plan

Rank	Workstream	Payoff	Risk	Sequence
1	Token budget extraction	10/10	3/10	First
2	AppleFoundationLLMService decomposition	9/10	6/10	Early
3	QueryRuntimeCoordinator	9/10	5/10	Early
4	RetrievalPipeline stages	10/10	7/10	Mid
5	Formal eval harness	10/10	2/10	Start early, expand continuously
6	Visual evidence grounding	8/10	3/10	Early-mid
7	Spotlight evidence index	9/10	5/10	Mid
8	Entity-native App Intents	8/10	5/10	Mid
9	ModelResolutionService	7/10	3/10	Mid
10	Dynamic Profiles	8/10	6/10	After SDK confirmation
11	Core AI model registry	7/10	7/10	Later
12	MLX training/eval workflow	5/10	4/10	Later / Mac-first

The main instruction to the agent should be:

OpenIntelligence is not missing intelligence. It is missing clean boundaries.
Preserve the weird high-performing retrieval tricks.
Modularize RAGService.
Use WWDC26 APIs to replace brittle hand-built infrastructure only where Apple now provides a better primitive.
Build evals before making behavior-changing improvements.
