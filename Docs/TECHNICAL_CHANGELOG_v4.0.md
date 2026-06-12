# OpenIntelligence v4.0 Technical Changelog

Changes covered: commit `1702aef7dae510bafe7e28ffa7a53683aff61bc1` through `a4c70383ad60c22faab6a44135d289a15488396f`.

Audited range: 18 commits, 126 changed files, 9,515 insertions, and 3,145 deletions. This file summarizes the implementation-level changes behind the v4.0 release and keeps the user-facing changelog/social copy aligned with the actual diff.

---

## 0. WWDC26 Implementation Map

WWDC26 is the release driver for v4.0. The technical direction is to move OpenIntelligence from a large app-contained RAG engine toward an Apple Intelligence-native evidence runtime. The table below separates what Apple changed/unlocked from what this audited range actually implements.

| WWDC26 area | What changed or became newly important | v4.0 implementation in this range | Status |
| --- | --- | --- | --- |
| Foundation Models runtime | `LanguageModelSession`, tools, structured generation, transcripts, provider-aligned model routing, and prompt/runtime specialization became the right abstraction layer for app AI. | Split Apple Foundation Models code into `FoundationModelSessionFactory`, `FoundationModelToolRegistry`, `FoundationModelPromptCompiler`, `FoundationModelStructuredGenerator`, `FoundationModelErrorMapper`, `FoundationModelTranscriptStore`, and `FoundationModelTokenBudget`. | Implemented modular foundation. |
| Dynamic profiles | Apple pushed toward runtime profile changes for model behavior, tools, and instructions. | Added `FoundationModelDynamicProfileRegistry` with profiles for direct chat, grounded RAG, extractive RAG, tool-calling RAG, source-only verification, summarization, query planning, and visual evidence QA. | Implemented app-level profile mapping; not claiming full system-level profile orchestration. |
| Private Cloud Compute route | Eligible apps can use Apple Foundation Models through PCC for larger/complex workloads while preserving Apple's privacy model. | Added `FoundationModelRoute`, `FoundationModelRoutePolicy`, explicit `PrivateCloudComputeLanguageModel()` route checks, `ContextOptions(reasoningLevel:)`, active-route notifications, model status UI, and `PCCRouteEvaluator`. | Implemented route policy and UI transparency. |
| Evaluations | AI features need repeatable behavior checks beyond normal unit tests. | Added `RAGEvalCase`, `RAGEvalDataset`, `RAGEvalRunner`, `RAGEvalMetrics`, `RAGEvalReportWriter`, `AppleEvaluationsBridge`, and `Docs/EVALS.md`. | Implemented local eval framework and Apple bridge shape. |
| App Intents and entities | Siri, Shortcuts, and Apple Intelligence can work better when app content is modeled as entities. | Added `OIDocumentEntity`, `OILibraryEntity`, `OIEntityQueries`, and expanded document/library intents for ask, summarize, compare, search, list, add, and status workflows. | Implemented document/library entity layer. |
| Visual Intelligence | Camera/image input can become an action surface and evidence source. | Added visual/image intents that run Vision OCR and pass extracted text as `.imageOCR` external evidence; added `VisualEvidenceSource`, `VisualEvidenceCard`, and evidence metadata. | Implemented OCR-backed visual evidence path; not claiming full multimodal image prompt reasoning. |
| Core Spotlight | System search can expose more app content when indexing is more granular. | Expanded `SpotlightIndexService` to index containers, documents, chunks/sections, and parse Spotlight identifiers. | Implemented richer system indexing; direct query-time Spotlight retrieval is not shown in this diff. |
| Core AI | Apple introduced a path for custom on-device AI models with OS-level local execution. | Added `CoreAIModelRegistry`, `CoreAIExecutionBackend`, and `CoreAIEmbeddingBackend`. | Scaffolding for future local model work. |
| Liquid Glass | iOS 26-era apps have native glass material/effect APIs and a new visual language. | Added/tightened `DSGlass`, `glassEffectHelper`, `glassCircleEffectHelper`, and `glassCardEffectHelper`; refreshed core surfaces around denser glass UI. | Implemented UI adoption. |
| View annotations | On-screen content can become more understandable to Siri/Apple Intelligence-style workflows. | Added `ViewAnnotations.swift` and used the release work to align chat/system surfaces around richer state. | Groundwork only. |

---

## 1. Foundation Models Modularization

The first commit in the range decomposes the previously monolithic Apple Foundation Models implementation into focused helpers under `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/`. This is the main WWDC26 architectural move: Foundation Models are no longer treated as a single model wrapper, but as the app's native generation/runtime boundary.

- `FoundationModelSessionFactory`: constructs `LanguageModelSession` instances for on-device and PCC routes, including tools, instructions, transcript reuse, and prewarming.
- `FoundationModelToolRegistry`: registers native RAG tools such as corpus retrieval, document inspection, cross-document comparison, and library overview.
- `FoundationModelPromptCompiler`: compiles context-aware instructions and prompts while reducing unnecessary token overhead.
- `FoundationModelStructuredGenerator`: handles structured/guided JSON generation for grounded RAG answers.
- `FoundationModelErrorMapper`: maps Foundation Models errors into app-level failure handling.
- `FoundationModelTranscriptStore`: trims transcript history to preserve the available context budget.
- `FoundationModelTokenBudget`: centralizes token estimation, context sizing, transcript estimates, and compiler-gated reasoning transcript support.
- `FoundationModelRoute` and `FoundationModelRoutePolicy`: represent and select on-device, automatic, and Private Cloud Compute routes.
- `FoundationModelDynamicProfileRegistry`: supports runtime profile swaps such as direct chat and grounded RAG modes.

Related changes in `LLMService.swift` move session creation, prompt compilation, route selection, structured generation, token budgeting, and transcript handling through those helpers.

---

## 2. Dynamic Routing and Model Resolution

The runtime now resolves the model path explicitly instead of inferring it from rough UI behavior:

- `FoundationModelRoutePolicy` chooses on-device vs. PCC based on query type, estimated context tokens, user PCC permission, PCC availability, and quota state.
- `LLMService.swift` posts `ActiveModelRouteResolved` notifications with the selected execution path and resolved model name.
- `ModelResolutionState.swift` models execution path state, context length, route labels, and active processing status.
- `ModelResolutionService.swift` observes settings, active route notifications, and execution context changes to keep UI state current.
- `ModelStatusIndicator.swift` now exposes an "Under the Hood" popover with active/last route, resolved model, and route explanations.
- `PCCRouteEvaluator.swift` adds diagnostics scaffolding for large-context routing, exact lookup routing, PCC quota fallback, PCC unavailable fallback, and Deep Think routing behavior.

This directly addresses the WWDC26 shift from a single public on-device model assumption to explicit route-aware execution across on-device and PCC-capable paths.

---

## 3. RAG Runtime Decomposition and Retrieval Updates

The query path was reorganized around a dedicated runtime coordinator:

- `QueryRuntimeCoordinator.swift` extracts query mode resolution, execution policy mapping, PCC eligibility, adaptive optimization levels, and response metadata creation out of the larger `RAGService` flow.
- `RAGService.swift` was updated around the new coordinator while preserving the existing ingestion, retrieval, verification, and response finalization responsibilities.
- `RAPTORSummaryRouter.swift` adds RAPTOR-lite summary filtering for overview-style retrieval.
- `HybridSearchService.swift` applies RAPTOR-lite filtering for overview queries in vector and cached retrieval paths.
- `RAGQuery.swift` now carries execution route metadata.
- `QueryEnhancementService.swift`, `IterativeRetrievalService.swift`, `ContextPackingService.swift`, and `ConfidenceCalibrationService.swift` were adjusted around the new query/runtime behavior.
- `RAGService+KnowledgeRetrievalEngine.swift` received a small compatibility update.

Important alignment note: Spotlight is indexed by the ingestion pipeline, but the audited diff does not show the RAG query engine directly searching Spotlight as a retrieval source. Public copy should describe Spotlight as system-level indexing/discoverability, not as an active RAG retrieval plane.

---

## 4. Empty Response, Retry, and Partial-Draft Preservation

The generation path now handles failure modes more conservatively:

- Empty LLM responses route to reliability fallback handling instead of immediately surfacing model-unavailable behavior.
- Streaming capture can preserve a meaningful partial answer if the model fails after text has already been emitted.
- The partial-output preservation threshold was lowered so shorter useful drafts can be salvaged.
- Rate-limited and concurrent request failures get a short primary-model retry before fallback behavior.
- Missing-citation, context-overflow, and malformed-response paths were tightened with grounded repair, evidence-pack, and abstention handling.
- Thinking-event emission was moved after session reset so UI feedback is not lost during route/session changes.

---

## 5. Grounded Answer and Evidence Surfaces

The answer UI and metadata gained explicit evidence/fidelity concepts:

- `EvidenceSource.swift` adds document chunk, image OCR, image region, and barcode evidence variants.
- `VisualEvidenceSource.swift` carries OCR text, barcode results, bounding boxes, source image data, and visual evidence metadata.
- `StructuredAnswer.swift` was extended around evidence tracing, citations, unsupported claims, abstention, and rendering.
- `GroundedAnswerView.swift` renders verified, cited answer content.
- `SourceFidelityStatus.swift` displays Source-Locked, Partially Supported, and Not Enough Evidence states.
- `VisualEvidenceCard.swift` renders visual/OCR evidence in the response surface.
- `ResponseDetailsView.swift`, `AnswerIntelligenceView.swift`, `MessageBubbleV2.swift`, and `WritingToolsResultSheet.swift` were updated to fit the new grounded-answer model.
- `UnifiedMetricsBar.swift` now receives `ThinkingStreamView`/thinking events so users can see live processing state.
- `MessageListV2.swift` and `ChatScreen.swift` were updated for the new event handling, route state, and live pipeline preview behavior.
- `ViewAnnotations.swift` adds reusable view annotation helpers.

---

## 6. System Integrations: Spotlight, App Intents, Siri, and Visual Intelligence

The range adds deeper Apple system integration:

- `SpotlightIndexService.swift` now indexes containers, documents, and document chunks/sections into Core Spotlight and includes identifier parsing for Spotlight continuations.
- `ContentView.swift`, container services, and RAG deletion paths call Spotlight deindexing when libraries/documents are removed.
- `OIDocumentEntity.swift`, `OILibraryEntity.swift`, and `OIEntityQueries.swift` add persisted App Entity support for documents and libraries.
- `RAGAppIntents.swift` expands Siri/Shortcuts actions for querying documents, adding documents, listing documents, checking import status, asking/summarizing/comparing specific documents, searching libraries, and checking embedding provider state.
- `VisualIntelligenceIntents.swift` extracts OCR text from image inputs and passes it as external image OCR evidence into the RAG pipeline.
- `AgenticOrchestrator.swift` was adjusted around OCR-aware prompting and agentic retrieval behavior.

---

## 7. App-Wide UI, Ingestion, Onboarding, Library, and Queue Work

The UI work spans chat, answer review, Documents, onboarding, ingestion, settings, diagnostics, model status, and design-system surfaces:

- `ChatScreen.swift`, `MessageBubbleV2.swift`, and `MessageListV2.swift` were updated for route state, streaming behavior, grounded answers, live events, and pipeline preview changes.
- `GroundedAnswerView.swift`, `SourceFidelityStatus.swift`, `VisualEvidenceCard.swift`, `ResponseDetailsView.swift`, `AnswerIntelligenceView.swift`, `WritingToolsResultSheet.swift`, and `UnifiedMetricsBar.swift` were added/updated around answer review, source support, visual evidence, and thinking feedback.
- `ModelStatusIndicator.swift` was redesigned around active/last route state, route coloring, processing state, and an Under the Hood details card.
- `DocumentLibraryView.swift`, `DocumentCard.swift`, `EmptyDocumentsView.swift`, and `StatsFooter.swift` were updated for layout, empty-state, queue integration, and document workflow polish.
- `IngestionItem.swift` now carries richer metrics and state used by the queue UI.
- `RAGService.swift` persists/restores ingestion queue state, updates metric fields, reports chunking/embedding progress, generates RAPTOR-lite summaries, and tracks content tags.
- `OnboardingChecklistView.swift` now mirrors ingestion state locally, uses a timer publisher for smooth elapsed-time display, and shows clearer pipeline logs.
- `IngestionQueueOverlay.swift` was heavily refactored for a denser, integrated queue/stats presentation.
- `ProcessingOverlay.swift` was removed.
- `SampleDocumentManager.swift` now uses the ingestion queue so UI observers receive progress and renames the sample from "OpenIntelligence Pricing" to "OpenIntelligence Product Guide."
- `SettingsView.swift` was refreshed around the updated model/settings surfaces.
- `DeveloperDiagnosticsHubView.swift` exposes additional validation/diagnostic entry points.
- `Theme.swift` adds/tightens Liquid Glass helpers, typography, spacing, corner radii, and visual density.
- The app icon asset catalog was expanded across iPhone, iPad, and Mac sizes.
- `IngestionLiveActivityAttributes.swift` and `IngestionLiveActivityService.swift` were updated for richer import progress state.
- `WorkspaceSyncService.swift` received queue/sync-related updates.

---

## 8. Evaluations and Diagnostics

WWDC26 made evaluations a central part of AI app development. This release adds a first-class RAG evaluation framework so retrieval and answer quality can be measured as product behavior instead of relying only on manual spot checks:

- `RAGEvalCase.swift`: JSONL-backed evaluation case and result models.
- `RAGEvalDataset.swift`: dataset loading, filtering, and bundle loading.
- `RAGEvalRunner.swift`: async execution of evaluation cases against the RAG engine.
- `RAGEvalMetrics.swift`: retrieval recall@5, citation precision, exact-value accuracy, unsupported-claim rate, correct abstention rate, and context overflow rate.
- `RAGEvalReportWriter.swift`: Markdown and JSON report generation.
- `AppleEvaluationsBridge.swift`: export shape for Apple/fm CLI-style evaluation tooling.
- `Docs/EVALS.md` documents dataset format, metrics, and reporting.
- `DeveloperDiagnosticsHubView.swift` exposes additional validation/diagnostic entry points.

---

## 9. Core AI and SDK Compatibility

New support layers prepare the app for WWDC26/iOS 26 APIs while keeping compile-time behavior controlled:

- `CoreAIModelRegistry.swift`, `CoreAIExecutionBackend.swift`, and `CoreAIEmbeddingBackend.swift` add local Core AI backend scaffolding.
- `EngineSDKCompatibility.swift` provides fallback compatibility definitions when newer SDK symbols are unavailable.
- `test_extension.swift` adds a compatibility helper around streaming response signatures.
- `Package.swift` and `OpenIntelligence.xcodeproj/project.pbxproj` were updated for the new package/build settings.
- `OpenIntelligence/Core/Support/test_write.txt` appears in the audited range as a tiny support/probe artifact.

---

## 10. Liquid Glass, Branding, Assets, and Release Metadata

The release also includes broad polish and release preparation:

- `Theme.swift` adds/tightens glass-effect helpers, typography, spacing, corner radii, and visual density.
- Chat surfaces, answer review, document surfaces, settings, diagnostics, onboarding/import, queue surfaces, and model status UI were refreshed around the new visual system.
- App icon assets were added across iPhone, iPad, and Mac sizes, and `Contents.json` was expanded accordingly.
- `LLMModel.swift` and model copy were updated around Apple Intelligence branding.
- `CHANGELOG.md`, `WHATS_NEW.md`, `Docs/RELEASE_NOTES_4.0.md`, `Docs/ARCHITECTURE.md`, `Docs/RETRIEVAL_PIPELINE.md`, `Docs/Engineering/APPLE_MODELS.md`, `Docs/Engineering/HARD_LIMITS.md`, and `Docs/Engineering/PRIVATE_CLOUD_COMPUTE.md` were updated.
- `WWDC26.md`, `DeepThinkTrace.txt`, and `DeepThinkConsole.txt` were added as reference/debug artifacts.
- `fastlane/Fastfile` and `fastlane/metadata/en-US/release_notes.txt` were updated for v4.0 release automation and App Store metadata.
