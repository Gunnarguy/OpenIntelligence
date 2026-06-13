# Phase 6: Feature Claim Verification Register - OpenIntelligence v4.1

This register catalogs marketing and technical claims found across documentation, release notes, and App Store copy, cross-referencing them directly with implementation reality in the codebase. Verified for OpenIntelligence v4.1.

## Claim Verification Matrix

| Claim | Source Location | Status | Evidence | Safer Wording | Action |
|---|---|---|---|---|---|
| **local-first** | README, PRIVACY | `VERIFIED_SHIPPED` | Ingestion, chunking, and vector search execute on-device using local CoreML and BNNS models. | "Runs locally on your device by default." | Keep. |
| **private** | README, PRIVACY | `VERIFIED_SHIPPED` | App relies on local execution; no server transmission of document texts occurs unless PCC is enabled. | "Designed for complete local privacy." | Keep. |
| **PCC routing** | WHATS_NEW, RELEASE_NOTES | `VERIFIED_SHIPPED` | Routed via `FoundationModelRoutePolicy` based on query complexity. | "Optional secure scaling to Apple Private Cloud Compute." | Keep. |
| **on-device standard queries** | README, ARCHITECTURE | `VERIFIED_SHIPPED` | Executes on `SystemLanguageModel.default` (iOS 26+). | "Standard queries execute natively on-device." | Keep. |
| **Deep Think** | WHATS_NEW, ARCHITECTURE | `VERIFIED_SHIPPED` | Policy routes deep inquiries to PCC reasoning models if consented. | "Deep Think routes to Apple PCC for enhanced reasoning." | Keep. |
| **Maximum** | WHATS_NEW, ARCHITECTURE | `VERIFIED_SHIPPED` | Policy routes maximum inquiries to PCC with deep reasoning. | "Maximum mode routes to Apple PCC with deep reasoning." | Keep. |
| **32K context** | README, RELEASE_NOTES | `VERIFIED_SHIPPED` | `PrivateCloudComputeLanguageModel` context size matches 32K. | "PCC supports up to a 32,768 token context window." | Keep. |
| **4K or 8K local context** | WHATS_NEW | `VERIFIED_SHIPPED` | `SystemLanguageModel.default.contextSize` provides 4,096 tokens. | "Supports a 4,096-token on-device context ceiling." | Keep. |
| **Foundation Models integration** | README, WHATS_NEW | `VERIFIED_SHIPPED` | Implemented in `FoundationModelSessionFactory` using the native framework. | "Integrates natively with Apple's Foundation Models on iOS 26.0+ and macOS 16.0+." | Keep. |
| **structured generation** | WHATS_NEW, RELEASE_NOTES | `VERIFIED_INTERNAL` | Structured generator maps JSON schema prompts. | "Leverages system models to generate structured outputs." | Keep. |
| **verified citations** | README, SOCIAL_POST_TEMPLATES | `VERIFIED_SHIPPED` | Verification gate checks grounding of answer text before presenting. | "Citations verified by local grounding gates." | Keep. |
| **citation-backed answers** | README, SOCIAL_POST_TEMPLATES | `VERIFIED_SHIPPED` | Source chips link dynamically to chunk offsets. | "Answers linked directly to source document citations." | Keep. |
| **guaranteed grounded** | README | `PARTIALLY_TRUE` | Answers pass verification checks but the system cannot mathematically guarantee 100% correctness. | "Designed to keep answers strictly grounded." | Soften wording in README. |
| **Metal GPU vector search** | README, SOCIAL_POST_TEMPLATES | `VERIFIED_SHIPPED` | `GPUComputeService` initializes Metal compute shaders. | "Metal-backed similarity search paths." | Keep. |
| **SIMD4** | SOCIAL_POST_TEMPLATES, RELEASE_NOTES | `VERIFIED_INTERNAL` | Metal shaders use SIMD4 thread groups for vector calculation. | "GPU batching utilizing native SIMD execution." | Keep. |
| **battery improvement** | README, SOCIAL_POST_TEMPLATES | `NEEDS_BENCHMARK` | Bypassing CPU for Metal vector calculations reduces power, but no energy benchmark reports exist. | "Optimized for Apple Silicon energy efficiency." | Soften until benchmark proof exists. |
| **4x speedup** | README, SOCIAL_POST_TEMPLATES | `NEEDS_BENCHMARK` | No canonical benchmark database in repo verifies the exact "4x" comparison factor for user devices. | "Accelerated vector search on the GPU." | Remove "4x" claims from public text. |
| **20% faster ingestion** | README, SOCIAL_POST_TEMPLATES | `NEEDS_BENCHMARK` | The 20% statistic has no backing raw dataset in the repository. | "Significantly speeds up ingestion by bypassing OCR on digital text." | Remove percentage claim. |
| **smart ingestion** | WHATS_NEW, SOCIAL_POST_TEMPLATES | `VERIFIED_SHIPPED` | Layout analyzer checks complexity before scanning. | "Intelligent page complexity analyzer." | Keep. |
| **page-complexity pre-scan** | WHATS_NEW, RELEASE_NOTES | `VERIFIED_SHIPPED` | `PageComplexityAnalyzer` counts digital characters. | "Automatic page-complexity scanning." | Keep. |
| **OCR skip on clean PDFs** | WHATS_NEW, RELEASE_NOTES | `VERIFIED_SHIPPED` | Pre-scan skips visual OCR on digital text PDF pages. | "Skips OCR scanning on clean digital PDFs." | Keep. |
| **table extraction** | README, SOCIAL_POST_TEMPLATES | `VERIFIED_SCAFFOLD` | `SpatialDocumentAnalyzer` contains stubs; layout parser does not rebuild tables for context. | "Scaffolded structural table detection." | Soften/Remove claims. |
| **image/visual evidence** | README, SOCIAL_POST_TEMPLATES | `PARTIALLY_TRUE` | Images can be scanned for text, but visual cropping/highlighting of evidence is stubbed. | "Extract text from images and photos." | Soften UI descriptions. |
| **audio/video import** | README | `VERIFIED_SCAFFOLD` | `AudioTranscriptionService` returns empty stubs. | "Audio transcription is scaffolded for future updates." | Remove from active list. |
| **code import** | README | `VERIFIED_SHIPPED` | Imports source code files as plain text. | "Supports code file ingestion." | Keep. |
| **CSV import** | README | `VERIFIED_SCAFFOLD` | No parser exists; treats CSV as flat text. | "Reads CSV documents as flat text structures." | Update description. |
| **Office/iWork import** | README | `UNSUPPORTED` | No RTF, docx, or Pages document extraction code is present in production targets. | "iWork and Office support coming soon." | Remove from active list. |
| **Core AI engine** | RELEASE_NOTES | `VERIFIED_SCAFFOLD` | Execution and Embedding backends under `CoreAI` namespace are empty stubs. | "Core AI compilation paths are scaffolded." | Clarify as scaffolding. |
| **Siri integration** | README, SOCIAL_POST_TEMPLATES | `VERIFIED_SHIPPED` | Mapped in `RAGAppIntents.swift`. | "Voice Shortcuts support for library search." | Keep. |
| **Spotlight indexing** | WHATS_NEW, RELEASE_NOTES | `VERIFIED_SHIPPED` | Chunks indexed via `CSSearchableIndex` in background. | "Integrates with Spotlight system search." | Keep. |
| **passage-level search** | SOCIAL_POST_TEMPLATES | `VERIFIED_SHIPPED` | `CSSearchableItemAttributeSet` indexes individual chunks. | "Indexes passages for Spotlight results." | Keep. |
| **App Entities** | RELEASE_NOTES | `VERIFIED_SHIPPED` | Mapped to `OIDocumentEntity` and `OILibraryEntity`. | "Supports native App Entities." | Keep. |
| **StoreKit tiers** | README, WHATS_NEW | `VERIFIED_SHIPPED` | `StoreKitConfiguration.storekit` defines Free, Pro, Lifetime, and Consumable pack IDs. | "StoreKit integration configured for upgrade plans." | Keep. |
| **Pro unlimited** | WHATS_NEW, README | `OUTDATED` | The docs claim Pro has "unlimited documents", but `QuotaPolicy` enforces a hard cap of 1,000 documents for Pro. | "Pro supports up to 1,000 documents." | Correct docs immediately. |
| **Pro 1,000 docs** | QuotaPolicy | `VERIFIED_INTERNAL` | Cap in code is exactly 1,000. | "Pro supports up to 1,000 documents." | Keep. |
| **Lifetime unlimited** | QuotaPolicy | `VERIFIED_INTERNAL` | Cap is `Int.max`. | "Lifetime plan supports unlimited documents." | Keep. |
| **open source** | README | `VERIFIED_SHIPPED` | Repository is public under MIT license. | "Open source under the MIT License." | Keep. |
| **RAG evaluation suite** | RELEASE_NOTES | `VERIFIED_SHIPPED` | Implemented in `RAGEvalRunner` and referenced by CLI benchmark tools. | "Local evaluation and quality verification framework." | Keep. |
| **recall/citation precision targets** | RELEASE_NOTES | `VERIFIED_SHIPPED` | Standard metrics targets checked in `RAGEvalMetrics`. | "Includes local quality metrics tracking." | Keep. |
| **benchmarks achieved** | WHATS_NEW | `VERIFIED_DEV_ONLY` | Benchmark runs folder contains local JSON validation logs showing test cases. | "Development test suites for quality verification." | Keep. |
| **zero third-party AI sharing** | README, PRIVACY | `VERIFIED_SHIPPED` | Code contains no third-party API configurations (OpenAI, Anthropic, etc.). | "No third-party AI data sharing." | Keep. |
| **Apple PCC only** | README, PRIVACY | `VERIFIED_SHIPPED` | External routing is restricted to Apple's native Private Cloud Compute enclaves. | "Exclusively routes cloud queries to Apple PCC." | Keep. |
| **no data stored** | PRIVACY | `VERIFIED_SHIPPED` | No telemetry analytics or logs are uploaded. | "No text or document metrics are stored externally." | Keep. |
| **iCloud sync** | README | `VERIFIED_SCAFFOLD` | `WorkspaceSyncService` contains stubs and does not execute sync logic. | "iCloud sync is scaffolded for a future release." | Remove active claims. |
| **abstention paths** | Alignment2 | `VERIFIED_SHIPPED` | `VerificationGateService` resolves `shouldAbstain` when critical gates fail. | "Triggers abstention responses when critical validation checks fail." | Keep. |
| **contradiction sweeps** | Alignment2 | `PARTIALLY_TRUE` | basic negation-indicators scanner exists (Gate D), but it does not trigger abstention. | "Performs basic lexical negation checks to discount confidence on conflicts." | Qualify in public claims. |
| **numeric sanity checks**| Alignment2 | `VERIFIED_SHIPPED` | Gate C matches numbers in responses to source chunks. | "Cross-checks response numbers against source documents." | Keep. |
| **semantic grounding** | Alignment2 | `VERIFIED_SHIPPED` | Gate E calculates cosine similarity of response vs chunk embeddings. | "Uses embedding similarity to verify response grounding." | Keep. |
| **cross-encoder reranking**| Alignment2 | `VERIFIED_SHIPPED` | `RAGEngine.rerank` executes TinyBERT cross-encoder scoring. | "Re-ranks retrieved candidates on-device using local models." | Keep. |
| **on-device reranking** | Alignment2 | `VERIFIED_SHIPPED` | Model inference runs locally using Core ML `MLModel` on device. | "Runs cross-encoder reranking locally on-device." | Keep. |
| **Core ML for reranking** | Alignment2 | `VERIFIED_SHIPPED` | Model loaded and run via Core ML framework. | "Uses Core ML to perform on-device reranking." | Keep. |
| **Core AI for reranking** | Alignment2 | `VERIFIED_SCAFFOLD` | Core AI execution pathways are empty stubs today. | "Core AI reranking pathways are scaffolded." | Correct public copy. |
| **Core AI scaffolding** | Alignment2 | `VERIFIED_SHIPPED` | `CoreAIExecutionBackend.swift` etc. exist as compiled stubs. | "Prepares scaffolding for future Core AI framework updates." | Keep. |
| **runs on ANE** | Alignment2 | `PARTIALLY_TRUE` | Core ML delegates to GPU/ANE/CPU dynamically; not restricted to ANE. | "Uses hardware-accelerated on-device models." | Soften ANE-exclusive claims. |
| **computeUnits .all** | Alignment2 | `VERIFIED_SHIPPED` | config.computeUnits = .all is configured in `RAGEngine.swift`. | "Uses Core ML computeUnits .all to schedule on CPU/GPU/ANE." | Keep. |
| **heuristic fallback** | Alignment2 | `VERIFIED_SHIPPED` | `RAGEngine.rerank` falls back to BM25, proximity, and TOC penalties if model fails. | "Falls back to heuristic ranking if the ML model is missing." | Keep. |
| **adaptive candidate pool**| Alignment2 | `VERIFIED_SHIPPED` | `adaptiveCeiling` bounds candidates between 100 and 250 chunks. | "Adaptive candidate pool bounds chunks based on query and database size." | Keep. |
| **candidate pool comments**| Alignment2 | `OUTDATED` | Comments claim no ceiling for <200 chunks, but formula enforces a 100 floor cutoff. | "Pool cutoff is calculated dynamically." | Align comments with formula or update formula. |
| **gates trigger abstention**| Alignment2 | `VERIFIED_SHIPPED` | Critical gate failures resolve to `shouldAbstain = true`. | "Critical verification gates trigger answer refusal." | Keep. |
| **contradictions abstain** | Alignment2 | `OUTDATED` | Gate D contradiction sweep is non-critical and does not trigger abstention. | "Contradictions do not force refusal but reduce confidence." | Correct docs immediately. |
| **contradictions reduce conf**| Alignment2 | `VERIFIED_SHIPPED` | runGateD reduces confidence by 0.2 per contradiction. | "Detected contradictions reduce answer confidence scores." | Keep. |
| **docs explain reranking** | Alignment2 | `PARTIALLY_TRUE` | Docs claim Core AI and ANE execution, which are stubs/simulated. | "Docs describe on-device Core ML execution with fallbacks." | Correct documentation. |
| **public copy reranking** | Alignment2 | `PARTIALLY_TRUE` | Social templates mention ANE and Core AI, which are stubs. | "Public templates focus on on-device Core ML execution." | Correct templates. |
| **local-only libraries** | PRIVACY | `VERIFIED_SHIPPED` | Library databases reside in the local app container. | "Local-only document containers." | Keep. |
