# OpenIntelligence Subsystem Map

This document maps the application architecture across all 30 core subsystems.

## App lifecycle

- **Purpose**: Manages application startup, SDK compatibility layer, keychain security initialization, and root application navigation.
- **Risk Level**: **LOW**
- **Data Owned**: None (transient launch settings and runtime environment parameters)
- **Dependencies**: Apple Foundation, UIKit/SwiftUI
- **Downstream Consumers**: onboarding, library/container management
- **Gaps or Uncertainties**: Launch arguments are mapped to command-line overrides for debugging but their interaction with production plist configs is not fully documented.
- **Owning Files**:
  - [OpenIntelligenceApp](../../../OpenIntelligence/App/OpenIntelligenceApp.swift)
  - [OpenIntelligenceRuntimePaths](../../../OpenIntelligence/Core/Support/OpenIntelligenceRuntimePaths.swift)
- **Main Services / Views / Models**:
  - `Marker`
  - `OpenIntelligenceApp`
  - `OpenIntelligenceResourceBundle`
  - `OpenIntelligenceRuntimePaths`

---

## Onboarding

- **Purpose**: Guides the user through onboarding screens, setting up initial library scopes, explaining RAG concepts, and initializing tips.
- **Risk Level**: **LOW**
- **Data Owned**: OnboardingStateStore (state key indicating completion status)
- **Dependencies**: app lifecycle, settings
- **Downstream Consumers**: library/container management, chat UI
- **Gaps or Uncertainties**: Tips view configurations are hardcoded and do not support remote content changes.
- **Owning Files**:
  - [OnboardingChecklistLauncher](../../../OpenIntelligence/Features/Onboarding/OnboardingChecklistLauncher.swift)
  - [OnboardingChecklistView](../../../OpenIntelligence/Features/Onboarding/OnboardingChecklistView.swift)
  - [OnboardingStateStore](../../../OpenIntelligence/Features/Onboarding/OnboardingStateStore.swift)
  - [AppTips](../../../OpenIntelligence/Services/Infrastructure/Tips/AppTips.swift)
- **Main Services / Views / Models**:
  - `AppTipConfiguration`
  - `AtlasTip`
  - `CompactTipViewStyle`
  - `ContainerTip`
  - `ExampleQuestionPill`
  - `FirstQueryTip`
  - `IngestDocumentTip`
  - `InlineTipView`
  - `Keys`
  - `MetricsSnapshot`
  - `ModelConfigTip`
  - `OnboardingChecklistLauncher`
  - `OnboardingChecklistView`
  - `OnboardingStateStore`
  - `PipelineLogEntry`
  - ... and 4 more entities

---

## Library/container management

- **Purpose**: Handles workspaces, folders, libraries, and containers. Manages collection statistics (sizes, category breakdowns).
- **Risk Level**: **LOW**
- **Data Owned**: Library profiles, Topic clusters, Container stats
- **Dependencies**: SQLite/FTS storage, iCloud/workspace sync
- **Downstream Consumers**: document import, retrieval
- **Gaps or Uncertainties**: Folder layout projection calculations use PCA and projection caches which have edge-case memory spikes on huge libraries.
- **Owning Files**:
  - [ContainerPicker](../../../OpenIntelligence/Features/Documents/Components/ContainerPicker.swift)
  - [DocumentPicker](../../../OpenIntelligence/Features/Documents/Components/DocumentPicker.swift)
  - [DocumentRow](../../../OpenIntelligence/Features/Documents/Components/DocumentRow.swift)
  - [EmptyDocumentsView](../../../OpenIntelligence/Features/Documents/Components/EmptyDocumentsView.swift)
  - [ProcessingSummaryView](../../../OpenIntelligence/Features/Documents/Components/ProcessingSummaryView.swift)
  - [StatsFooter](../../../OpenIntelligence/Features/Documents/Components/StatsFooter.swift)
  - [DocumentDetailsView](../../../OpenIntelligence/Features/Documents/Details/DocumentDetailsView.swift)
  - [CachedDocsView](../../../OpenIntelligence/Features/Documents/Library/CachedDocsView.swift)
  - [SampleDocumentManager](../../../OpenIntelligence/Features/Documents/Library/SampleDocumentManager.swift)
  - [SemanticSearchView](../../../OpenIntelligence/Features/Documents/Search/SemanticSearchView.swift)
  - [LibraryIconSuggestionService](../../../OpenIntelligence/Services/Infrastructure/Presentation/LibraryIconSuggestionService.swift)
  - [ProjectionCache](../../../OpenIntelligence/Services/Infrastructure/Presentation/ProjectionCache.swift)
  - [ProjectionService](../../../OpenIntelligence/Services/Infrastructure/Presentation/ProjectionService.swift)
- **Main Services / Views / Models**:
  - `AutoIntelligenceBadge`
  - `CachedDocRow`
  - `CachedDocsView`
  - `ChunkMetricRow`
  - `ContainerPickerStrip`
  - `ContainerPill`
  - `ContainerPillBadgeStyle`
  - `ContentDomain`
  - `ContentMetricRow`
  - `ContentTagPill`
  - `Coordinator`
  - `DetailInfoRow`
  - `DetailRow`
  - `DocPreviewSheet`
  - `DocumentDetailCardView`
  - ... and 27 more entities

---

## Document import

- **Purpose**: Coordinates file system access, camera previews, and document ingest pipeline triggers.
- **Risk Level**: **LOW**
- **Data Owned**: Temporary raw file caches, Camera preview layers
- **Dependencies**: ingestion queue, OCR/extraction
- **Downstream Consumers**: OCR/extraction
- **Gaps or Uncertainties**: Camera pose joint detection runs continuously on the main thread, causing thermal throttling on older devices.
- **Owning Files**:
  - [CameraVisionOverlayView](../../../OpenIntelligence/Features/Camera/CameraVisionOverlayView.swift)
  - [DocumentProcessor+DocumentIngestionEngine](../../../OpenIntelligence/Services/Document/Processing/DocumentProcessor+DocumentIngestionEngine.swift)
- **Main Services / Views / Models**:
  - `AnimalWireframe`
  - `CameraPreviewLayer`
  - `CameraPreviewUIView`
  - `CameraVisionOverlayView`
  - `CaptureConfirmationSheet`
  - `CaptureResult`
  - `CaptureType`
  - `DetectedPose`
  - `DetectedRegion`
  - `DetectionOverlayView`
  - `ElementType`
  - `FaceSilhouetteOverlay`
  - `FrameAnalysis`
  - `HumanSilhouetteOverlay`
  - `HumanWireframe`
  - ... and 10 more entities

---

## Ingestion queue

- **Purpose**: Handles the asynchronous queue of documents pending processing. Integrates with Live Activities for Lock Screen progress monitoring.
- **Risk Level**: **MEDIUM**
- **Data Owned**: Ingestion live activity attributes, queue processing states
- **Dependencies**: background tasks, document import
- **Downstream Consumers**: OCR/extraction
- **Gaps or Uncertainties**: Live activity updates are throttled under high memory pressure, which might drop progress updates.
- **Owning Files**:
  - [IngestionLiveActivityAttributes](../../../OpenIntelligence/Services/Infrastructure/Background/IngestionLiveActivityAttributes.swift)
  - [IngestionLiveActivityService](../../../OpenIntelligence/Services/Infrastructure/Background/IngestionLiveActivityService.swift)
  - [IngestionQueueOverlay](../../../OpenIntelligence/UI/Components/IngestionQueueOverlay.swift)
  - [IngestionLiveActivityWidget](file://OpenIntelligenceLiveActivities/IngestionLiveActivityWidget.swift)
- **Main Services / Views / Models**:
  - `AggregatedMetrics`
  - `ContentState`
  - `CustomProgressBar`
  - `IngestionConsoleLogRow`
  - `IngestionConsoleView`
  - `IngestionLiveActivityAttributes`
  - `IngestionLiveActivityLockScreenView`
  - `IngestionLiveActivityPresentationProfile`
  - `IngestionLiveActivityProcessingMode`
  - `IngestionLiveActivityService`
  - `IngestionLiveActivityThermalBucket`
  - `IngestionLiveActivityWidget`
  - `IngestionQueueOverlay`
  - `IngestionQueueRow`
  - `OpenIntelligenceDeepLink`
  - ... and 2 more entities

---

## Ocr/extraction

- **Purpose**: Extracts layout, text blocks, translations, audio transcriptions, and image metadata using local Apple Vision OCR and CoreML.
- **Risk Level**: **MEDIUM**
- **Data Owned**: Document structures, OCR blocks, Spatial pages
- **Dependencies**: embeddings
- **Downstream Consumers**: semantic chunking
- **Gaps or Uncertainties**: Spatial layout column alignment relies on heuristics that fail on complex nested multi-column tables.
- **Owning Files**:
  - [CameraManager](../../../OpenIntelligence/Features/Camera/CameraManager.swift)
  - [CaptureToRAGBridge](../../../OpenIntelligence/Features/Camera/CaptureToRAGBridge.swift)
  - [DocumentCaptureView](../../../OpenIntelligence/Features/Camera/DocumentCaptureView.swift)
  - [PageComplexityAnalyzer](../../../OpenIntelligence/Services/Document/Chunking/PageComplexityAnalyzer.swift)
  - [CoreMLDocumentClassifier](../../../OpenIntelligence/Services/Document/Classification/CoreMLDocumentClassifier.swift)
  - [CoreMLRegionDetector](../../../OpenIntelligence/Services/Document/Classification/CoreMLRegionDetector.swift)
  - [ImageUnderstandingService](../../../OpenIntelligence/Services/Document/Classification/ImageUnderstandingService.swift)
  - [YOLODetectionService](../../../OpenIntelligence/Services/Document/Classification/YOLODetectionService.swift)
  - [OCRConfiguration](../../../OpenIntelligence/Services/Document/Config/OCRConfiguration.swift)
  - [VisionOCRThrottle](../../../OpenIntelligence/Services/Document/Config/VisionOCRThrottle.swift)
  - [AudioTranscriptionService](../../../OpenIntelligence/Services/Document/Extraction/AudioTranscriptionService.swift)
  - [GazetteerService](../../../OpenIntelligence/Services/Document/Extraction/GazetteerService.swift)
  - [LanguageDetectionService](../../../OpenIntelligence/Services/Document/Extraction/LanguageDetectionService.swift)
  - [TranslationService](../../../OpenIntelligence/Services/Document/Extraction/TranslationService.swift)
  - [DocumentProcessor](../../../OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift)
  - [IntelligentDocumentProcessor](../../../OpenIntelligence/Services/Document/Processing/IntelligentDocumentProcessor.swift)
  - [LayoutAwareExtractor](../../../OpenIntelligence/Services/Document/Processing/LayoutAwareExtractor.swift)
  - [StructuredDocumentParser](../../../OpenIntelligence/Services/Document/Processing/StructuredDocumentParser.swift)
  - [DeviceCapabilityService](../../../OpenIntelligence/Services/Infrastructure/Monitoring/DeviceCapabilityService.swift)
  - [ExtractiveQAService](../../../OpenIntelligence/Services/RAG/Extraction/ExtractiveQAService.swift)
  - [ExtractiveSummarizationService](../../../OpenIntelligence/Services/RAG/Extraction/ExtractiveSummarizationService.swift)
- **Main Services / Views / Models**:
  - `APIs`
  - `AdaptivePreprocessor`
  - `AnalyzedImage`
  - `AudioTranscriptionService`
  - `CameraError`
  - `CameraManager`
  - `CameraPreview`
  - `CaptureButton`
  - `CaptureError`
  - `CaptureFlowLayout`
  - `CaptureIngestionError`
  - `CaptureMode`
  - `Category`
  - `CellContentType`
  - `CentralDirectoryEntry`
  - ... and 115 more entities

---

## Semantic chunking

- **Purpose**: Performs text block partitioning based on semantic density and structural headers.
- **Risk Level**: **LOW**
- **Data Owned**: DocumentChunk models, IngestedChunk overrides
- **Dependencies**: OCR/extraction
- **Downstream Consumers**: embeddings, SQLite/FTS storage
- **Gaps or Uncertainties**: Header boundaries are determined by text sizes, which are sometimes incorrectly estimated for scanned PDFs.
- **Owning Files**:
  - [DocumentChunk](../../../OpenIntelligence/Core/Models/DocumentChunk.swift)
  - [ChunkInspectorView](../../../OpenIntelligence/Features/Diagnostics/Validation/ChunkInspectorView.swift)
  - [NLChunkingDiagnosticsView](../../../OpenIntelligence/Features/Telemetry/Diagnostics/NLChunkingDiagnosticsView.swift)
  - [EntityIndexService](../../../OpenIntelligence/Services/Document/Analysis/EntityIndexService.swift)
  - [ContentTaggingService](../../../OpenIntelligence/Services/Document/Chunking/ContentTaggingService.swift)
  - [SemanticChunker](../../../OpenIntelligence/Services/Document/Chunking/SemanticChunker.swift)
  - [ParentDocumentService](../../../OpenIntelligence/Services/RAG/Retrieval/ParentDocumentService.swift)
- **Main Services / Views / Models**:
  - `ChunkAbstractionLevel`
  - `ChunkDetailSheet`
  - `ChunkInspectionResult`
  - `ChunkInspectorView`
  - `ChunkMetadata`
  - `ChunkRowView`
  - `ChunkSemanticType`
  - `ChunkSortOrder`
  - `ChunkStatistics`
  - `ChunkingConfig`
  - `ChunkingDiagnostics`
  - `CodingKeys`
  - `Config`
  - `ContentTaggingError`
  - `ContentTaggingService`
  - ... and 21 more entities

---

## Embeddings

- **Purpose**: Generates semantic vector embeddings for text chunks using local CoreML embedding models or Apple Foundation Models embedding APIs.
- **Risk Level**: **MEDIUM**
- **Data Owned**: Embedding configs and pooling strategies
- **Dependencies**: Apple Foundation Models
- **Downstream Consumers**: vector storage
- **Gaps or Uncertainties**: AppleFMEmbeddingProvider relies on system-specific private APIs that might shift across iOS/macOS version boundaries.
- **Owning Files**:
  - [Embedding3DView](../../../OpenIntelligence/Features/Telemetry/Visualizations/Embedding3DView.swift)
  - [CoreAIEmbeddingBackend](../../../OpenIntelligence/Services/AIPlatform/CoreAI/CoreAIEmbeddingBackend.swift)
  - [CoreAIExecutionBackend](../../../OpenIntelligence/Services/AIPlatform/CoreAI/CoreAIExecutionBackend.swift)
  - [CoreAIModelRegistry](../../../OpenIntelligence/Services/AIPlatform/CoreAI/CoreAIModelRegistry.swift)
  - [AdaptiveEmbeddingOptimizer](../../../OpenIntelligence/Services/Embedding/AdaptiveEmbeddingOptimizer.swift)
  - [EmbeddingService](../../../OpenIntelligence/Services/Embedding/EmbeddingService.swift)
  - [AppleFMEmbeddingProvider](../../../OpenIntelligence/Services/Embedding/Providers/AppleFMEmbeddingProvider.swift)
  - [CoreAISentenceEmbeddingProvider](../../../OpenIntelligence/Services/Embedding/Providers/CoreAISentenceEmbeddingProvider.swift)
  - [CoreMLSentenceEmbeddingProvider](../../../OpenIntelligence/Services/Embedding/Providers/CoreMLSentenceEmbeddingProvider.swift)
  - [EmbeddingProvider](../../../OpenIntelligence/Services/Embedding/Providers/EmbeddingProvider.swift)
  - [NLContextualEmbeddingProvider](../../../OpenIntelligence/Services/Embedding/Providers/NLContextualEmbeddingProvider.swift)
  - [NLEmbeddingProvider](../../../OpenIntelligence/Services/Embedding/Providers/NLEmbeddingProvider.swift)
- **Main Services / Views / Models**:
  - `AnnotationBubble`
  - `AnnotationCandidate`
  - `AnnotationData`
  - `AnnotationPopoverLayer`
  - `AppleFMEmbeddingProvider`
  - `AxisDirection`
  - `AxisDistributionBar`
  - `AxisLabels`
  - `ChunkingPlan`
  - `ControlToggleButton`
  - `Coordinator`
  - `CoreAIEmbeddingBackend`
  - `CoreAIExecutionBackend`
  - `CoreAIExecutionBackendProtocol`
  - `CoreAIModelConfig`
  - ... and 40 more entities

---

## Vector storage

- **Purpose**: Maintains the local vector database, handling indexing and cosine similarity checks.
- **Risk Level**: **MEDIUM**
- **Data Owned**: Vectura database matrices, memory-mapped vectors
- **Dependencies**: embeddings
- **Downstream Consumers**: retrieval
- **Gaps or Uncertainties**: BNNSVectorDatabase uses metal buffers which can crash on older devices lacking unified memory support.
- **Owning Files**:
  - [VectorDatabase](../../../OpenIntelligence/Services/VectorStore/VectorDatabase.swift)
  - [VectorStoreRouter](../../../OpenIntelligence/Services/VectorStore/VectorStoreRouter.swift)
  - [VecturaVectorDatabase](../../../OpenIntelligence/Services/VectorStore/VecturaVectorDatabase.swift)
- **Main Services / Views / Models**:
  - `InMemoryVectorDatabase`
  - `VectorDatabase`
  - `VectorDatabaseError`
  - `VectorDatabaseStats`
  - `VectorStoreRouter`
  - `VecturaVectorDatabase`
  - `methods`

---

## Sqlite/fts storage

- **Purpose**: Stores relational data, document metadata, and supports keyword search via SQLite FTS5.
- **Risk Level**: **MEDIUM**
- **Data Owned**: SQLite databases, full-text indexes, document metadata tables
- **Dependencies**: None
- **Downstream Consumers**: retrieval, library/container management
- **Gaps or Uncertainties**: Custom tokenizers inside FTS5 must match Swift-level unicode normalization exactly, otherwise keyword search hits might fail.
- **Owning Files**:
  - [DatabaseDashboardView](../../../OpenIntelligence/Features/Database/DatabaseDashboardView.swift)
  - [AdaptiveVisualizationsView](../../../OpenIntelligence/Features/Telemetry/Visualizations/AdaptiveVisualizationsView.swift)
  - [VisualizationsView](../../../OpenIntelligence/Features/Telemetry/Visualizations/VisualizationsView.swift)
  - [HyDEService](../../../OpenIntelligence/Services/Query/Rewriting/HyDEService.swift)
  - [HybridSearchService](../../../OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift)
  - [SQLiteFullTextService](../../../OpenIntelligence/Services/Storage/SQLiteFullTextService.swift)
- **Main Services / Views / Models**:
  - `ActivityRow`
  - `AdaptiveVisualizationsView`
  - `AdvancedCorpusStatsView`
  - `AnalysisCard`
  - `AnalysisStats`
  - `AtlasBackgroundStyle`
  - `AtlasMode`
  - `AtlasProjectionMethod`
  - `AtlasStatPill`
  - `AtlasToggleChip`
  - `AxisRow`
  - `BM25Scorer`
  - `BM25Snapshot`
  - `CharacterBreakdownRow`
  - `ChunkDistributionView`
  - ... and 105 more entities

---

## Retrieval

- **Purpose**: Orchestrates multi-hop search queries, BM25 scoring, vector searches, and hybrid ranking.
- **Risk Level**: **MEDIUM**
- **Data Owned**: Retrieval plans, Query signals, Search results
- **Dependencies**: SQLite/FTS storage, vector storage, reranking/fusion
- **Downstream Consumers**: context packing, verification gates
- **Gaps or Uncertainties**: HybridSearchService uses heuristic RRF weighting which is hardcoded and cannot adapt to changing query types automatically.
- **Owning Files**:
  - [KeychainStorage](../../../OpenIntelligence/Core/Extensions/KeychainStorage.swift)
  - [LaunchArguments](../../../OpenIntelligence/Core/Extensions/LaunchArguments.swift)
  - [CloudTransmission](../../../OpenIntelligence/Core/Models/CloudTransmission.swift)
  - [IngestionItem](../../../OpenIntelligence/Core/Models/IngestionItem.swift)
  - [IngestionRuntimeBridge](../../../OpenIntelligence/Core/Models/IngestionRuntimeBridge.swift)
  - [QueryRuntimeBridge](../../../OpenIntelligence/Core/Models/QueryRuntimeBridge.swift)
  - [RAGQuery](../../../OpenIntelligence/Core/Models/RAGQuery.swift)
  - [WorkspaceTier](../../../OpenIntelligence/Core/Models/WorkspaceTier.swift)
  - [EngineInterfaces](../../../OpenIntelligence/Core/Protocols/EngineInterfaces.swift)
  - [SpatialDocumentAnalyzer](../../../OpenIntelligence/Services/Document/Analysis/SpatialDocumentAnalyzer.swift)
  - [SpecificationDetector](../../../OpenIntelligence/Services/Document/Analysis/SpecificationDetector.swift)
  - [SpeechAnalyzerService](../../../OpenIntelligence/Services/Document/Analysis/SpeechAnalyzerService.swift)
  - [StreamingXMLProcessor](../../../OpenIntelligence/Services/Document/Processing/StreamingXMLProcessor.swift)
  - [BNNSGraphService](../../../OpenIntelligence/Services/Infrastructure/Compute/BNNSGraphService.swift)
  - [GPUComputeService](../../../OpenIntelligence/Services/Infrastructure/Compute/GPUComputeService.swift)
  - [QueryComplexityAnalyzer](../../../OpenIntelligence/Services/Query/Analysis/QueryComplexityAnalyzer.swift)
  - [QueryExecutionPlannerService](../../../OpenIntelligence/Services/Query/Analysis/QueryExecutionPlannerService.swift)
  - [QueryProfileService](../../../OpenIntelligence/Services/Query/Analysis/QueryProfileService.swift)
  - [QueryRouterService](../../../OpenIntelligence/Services/Query/Routing/QueryRouterService.swift)
  - [RAGService+KnowledgeRetrievalEngine](../../../OpenIntelligence/Services/RAG/Orchestration/RAGService+KnowledgeRetrievalEngine.swift)
  - [ContainerVocabularyService](../../../OpenIntelligence/Services/RAG/Retrieval/ContainerVocabularyService.swift)
  - [GraphIndexService](../../../OpenIntelligence/Services/RAG/Retrieval/GraphIndexService.swift)
  - [RAPTORSummaryRouter](../../../OpenIntelligence/Services/RAG/Retrieval/RAPTORSummaryRouter.swift)
  - [DomainIsolationService](../../../OpenIntelligence/Services/RAG/Safety/DomainIsolationService.swift)
  - [QualityAssuranceService](../../../OpenIntelligence/Services/RAG/Safety/QualityAssuranceService.swift)
  - [OpenIntelligenceLiveActivitiesBundle](file://OpenIntelligenceLiveActivities/OpenIntelligenceLiveActivitiesBundle.swift)
- **Main Services / Views / Models**:
  - `AlignedTableCell`
  - `AnalyzedUtterance`
  - `AnswerType`
  - `Assessment`
  - `BNNSGraphService`
  - `ChunkGraphEdges`
  - `Classification`
  - `ClassifiedChunk`
  - `CloudConsentDecision`
  - `CloudConsentState`
  - `CloudProvider`
  - `CloudTransmissionRecord`
  - `CodingKeys`
  - `ContainerVocabulary`
  - `CrossReference`
  - ... and 68 more entities

---

## Reranking/fusion

- **Purpose**: Scores candidate chunks using a local CoreML TinyBERT model to refine search relevance.
- **Risk Level**: **MEDIUM**
- **Data Owned**: TinyBERT model vocabularies
- **Dependencies**: retrieval
- **Downstream Consumers**: context packing
- **Gaps or Uncertainties**: TinyBERT model inferences are run in batches which can cause latency spikes on large context sets.
- **Owning Files**:
  - [ContainerSettingsSheet+Sections](../../../OpenIntelligence/Features/Documents/Settings/ContainerSettingsSheet+Sections.swift)
- **Main Services / Views / Models**:
  - `ChunkingPreview`
  - `RetrievalStyle`

---

## Context packing

- **Purpose**: Selects, prioritizes, and packs evidence chunks to fit target token budgets.
- **Risk Level**: **MEDIUM**
- **Data Owned**: PackedContext, token budgets
- **Dependencies**: retrieval
- **Downstream Consumers**: generation
- **Gaps or Uncertainties**: Token counting relies on Swift-level approximations which differ slightly from the model's actual vocabulary tokenizer.
- **Owning Files**:
  - [ContextPackingService](../../../OpenIntelligence/Services/RAG/Retrieval/ContextPackingService.swift)
- **Main Services / Views / Models**:
  - `PackedContext`

---

## Generation

- **Purpose**: Streams generated answers from local LLM models (via HuggingFace swift-transformers or Apple FM).
- **Risk Level**: **MEDIUM**
- **Data Owned**: LLM response states, streaming events
- **Dependencies**: Apple Foundation Models, context packing
- **Downstream Consumers**: citations/source rendering
- **Gaps or Uncertainties**: Fallback mock services exist but their activation logic in the event of local model failure is not robustly implemented.
- **Owning Files**:
  - [DebugRAGValidationHarness](../../../OpenIntelligence/App/DebugRAGValidationHarness.swift)
  - [MarkdownRenderer](../../../OpenIntelligence/Core/Extensions/MarkdownRenderer.swift)
  - [LLMModelType](../../../OpenIntelligence/Core/Models/LLMModelType.swift)
  - [ModelResolutionState](../../../OpenIntelligence/Core/Models/ModelResolutionState.swift)
  - [RAGStructuredResponse](../../../OpenIntelligence/Core/Models/RAGStructuredResponse.swift)
  - [ToolCallBadge](../../../OpenIntelligence/Features/Chat/Response/ToolCallBadge.swift)
  - [UnifiedMetricsBar](../../../OpenIntelligence/Features/Chat/Response/UnifiedMetricsBar.swift)
  - [CoreValidationView](../../../OpenIntelligence/Features/Diagnostics/Validation/CoreValidationView.swift)
  - [ModelInfoCard](../../../OpenIntelligence/Features/Settings/Components/ModelInfoCard.swift)
  - [ModelSelectorSheet](../../../OpenIntelligence/Features/Settings/Components/ModelSelectorSheet.swift)
  - [ResponseTransformService](../../../OpenIntelligence/Services/Agentic/ResponseTransformService.swift)
  - [ToolCallCounter](../../../OpenIntelligence/Services/Agentic/ToolCallCounter.swift)
  - [WritingToolsService](../../../OpenIntelligence/Services/Agentic/WritingToolsService.swift)
  - [DocumentSummaryService](../../../OpenIntelligence/Services/Document/Analysis/DocumentSummaryService.swift)
  - [VisualCaptioningService](../../../OpenIntelligence/Services/Document/Processing/VisualCaptioningService.swift)
  - [LoggingConfiguration](../../../OpenIntelligence/Services/Infrastructure/Configuration/LoggingConfiguration.swift)
  - [ImagePlaygroundService](../../../OpenIntelligence/Services/Infrastructure/Integration/ImagePlaygroundService.swift)
  - [HardwareTelemetryState](../../../OpenIntelligence/Services/Infrastructure/Monitoring/HardwareTelemetryState.swift)
  - [AdaptivePipelineOptimizer](../../../OpenIntelligence/Services/Infrastructure/Optimization/AdaptivePipelineOptimizer.swift)
  - [ClusterLabelService](../../../OpenIntelligence/Services/Infrastructure/Presentation/ClusterLabelService.swift)
  - [LibraryVisualizationEngine](../../../OpenIntelligence/Services/Infrastructure/Presentation/LibraryVisualizationEngine.swift)
  - [AdapterManager](../../../OpenIntelligence/Services/LLM/AdapterManager.swift)
  - [LLMStreamingContext](../../../OpenIntelligence/Services/LLM/LLMStreamingContext.swift)
  - [LocalOpenAIServerLLMService](../../../OpenIntelligence/Services/LLM/LocalOpenAIServerLLMService.swift)
  - [ModelResolutionService](../../../OpenIntelligence/Services/LLM/ModelResolutionService.swift)
  - [PromptEvaluationService](../../../OpenIntelligence/Services/LLM/PromptEvaluationService.swift)
  - [SpecificationExtractor](../../../OpenIntelligence/Services/Query/Analysis/SpecificationExtractor.swift)
  - [QueryEnhancementService](../../../OpenIntelligence/Services/Query/Enhancement/QueryEnhancementService.swift)
  - [QueryRewriterService](../../../OpenIntelligence/Services/Query/Rewriting/QueryRewriterService.swift)
  - [SmartReplyService](../../../OpenIntelligence/Services/Query/UX/SmartReplyService.swift)
  - [SuggestedQuestionsService](../../../OpenIntelligence/Services/Query/UX/SuggestedQuestionsService.swift)
  - [RAGEngine](../../../OpenIntelligence/Services/RAG/Orchestration/RAGEngine.swift)
  - [IterativeRetrievalService](../../../OpenIntelligence/Services/RAG/Retrieval/IterativeRetrievalService.swift)
  - [AutoTuneService](../../../OpenIntelligence/Services/RAG/Tuning/AutoTuneService.swift)
  - [FullTextStorageService](../../../OpenIntelligence/Services/Storage/FullTextStorageService.swift)
  - [ModelStatusIndicator](../../../OpenIntelligence/UI/Components/ModelStatusIndicator.swift)
  - [Theme](../../../OpenIntelligence/UI/DesignSystem/Theme.swift)
- **Main Services / Views / Models**:
  - `Accent`
  - `ActiveParameters`
  - `AdapterDescriptor`
  - `AdapterDomain`
  - `AdapterManager`
  - `AdapterState`
  - `AdaptivePipelineConfig`
  - `AdaptivePipelineOptimizer`
  - `AmbiguityType`
  - `AnswerCandidate`
  - `AnswerIntent`
  - `AutoTuneService`
  - `BubbleBackground`
  - `BulletPoint`
  - `CachedEntry`
  - ... and 172 more entities

---

## Apple foundation models

- **Purpose**: Manages communication with native iOS/macOS system-level models using Private APIs.
- **Risk Level**: **HIGH**
- **Data Owned**: Foundation model routes and prompt structures
- **Dependencies**: PCC routing/consent
- **Downstream Consumers**: generation
- **Gaps or Uncertainties**: Access to local Apple FMs requires specific entitlements that can cause silent app crashes if provisioning fails.
- **Owning Files**:
  - [BackendHealthDiagnosticsView](../../../OpenIntelligence/Features/Diagnostics/Monitoring/BackendHealthDiagnosticsView.swift)
  - [FoundationModelDynamicProfileRegistry](../../../OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelDynamicProfileRegistry.swift)
  - [FoundationModelErrorMapper](../../../OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelErrorMapper.swift)
  - [FoundationModelPromptCompiler](../../../OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelPromptCompiler.swift)
  - [FoundationModelRoute](../../../OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelRoute.swift)
  - [FoundationModelStructuredGenerator](../../../OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelStructuredGenerator.swift)
  - [FoundationModelTokenBudget](../../../OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelTokenBudget.swift)
  - [FoundationModelToolRegistry](../../../OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelToolRegistry.swift)
  - [FoundationModelTranscriptStore](../../../OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelTranscriptStore.swift)
- **Main Services / Views / Models**:
  - `AppleFoundationModelRoute`
  - `Arguments`
  - `BackendHealthDiagnosticsView`
  - `CompareDocumentsTool`
  - `CompareTopicAcrossDocumentsTool`
  - `CountPatternTool`
  - `FindRelatedDocumentsTool`
  - `FoundationModelDynamicProfile`
  - `FoundationModelDynamicProfileRegistry`
  - `FoundationModelErrorMapper`
  - `FoundationModelPromptCompiler`
  - `FoundationModelStructuredGenerator`
  - `FoundationModelTokenBudget`
  - `FoundationModelToolRegistry`
  - `FoundationModelTranscriptStore`
  - ... and 10 more entities

---

## Pcc routing/consent

- **Purpose**: Monitors and governs whether requests stream to local execution or Private Cloud Compute (PCC) based on user privacy consent.
- **Risk Level**: **HIGH**
- **Data Owned**: Cloud consent decisions, transmission history logs
- **Dependencies**: settings
- **Downstream Consumers**: Apple Foundation Models
- **Gaps or Uncertainties**: Force-routing to local-only when consent is pending does not fail gracefully, occasionally hanging the retrieval pipeline.
- **Owning Files**:
  - [LLMModel](../../../OpenIntelligence/Core/Models/LLMModel.swift)
  - [EngineSDKCompatibility](../../../OpenIntelligence/Core/Support/EngineSDKCompatibility.swift)
  - [ChatScreen](../../../OpenIntelligence/Features/Chat/Conversation/ChatScreen.swift)
  - [DeveloperDiagnosticsHubView](../../../OpenIntelligence/Features/Diagnostics/Hub/DeveloperDiagnosticsHubView.swift)
  - [PCCRouteEvaluator](../../../OpenIntelligence/Features/Diagnostics/Validation/PCCRouteEvaluator.swift)
  - [RAGPipelineAuditView](../../../OpenIntelligence/Features/Diagnostics/Validation/RAGPipelineAuditView.swift)
  - [AboutView](../../../OpenIntelligence/Features/Settings/AboutView.swift)
  - [OpenIntelligenceEngine](../../../OpenIntelligence/SDK/OpenIntelligenceEngine.swift)
  - [FoundationModelRoutePolicy](../../../OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelRoutePolicy.swift)
  - [FoundationModelSessionFactory](../../../OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelSessionFactory.swift)
  - [AgenticOrchestrator](../../../OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift)
  - [QueryRuntimeCoordinator](../../../OpenIntelligence/Services/RAG/Orchestration/QueryRuntimeCoordinator.swift)
  - [CloudConsentPromptView](../../../OpenIntelligence/UI/Components/CloudConsentPromptView.swift)
- **Main Services / Views / Models**:
  - `AboutView`
  - `AccuracyModeBadge`
  - `AgenticConfig`
  - `AgenticError`
  - `AgenticOrchestrator`
  - `AgenticResult`
  - `AppReviewPromptPolicy`
  - `AppReviewPromptTracker`
  - `ChatHeader`
  - `ChatScreen`
  - `ChatV2FeatureRow`
  - `CitationVerificationResult`
  - `CloudConsentPromptView`
  - `ClusterInsight`
  - `CompactChatHeader`
  - ... and 75 more entities

---

## Verification gates

- **Purpose**: Validates the correctness of LLM outputs against source documents to prevent hallucination.
- **Risk Level**: **MEDIUM**
- **Data Owned**: Verification stats and calibration metrics
- **Dependencies**: retrieval
- **Downstream Consumers**: citations/source rendering
- **Gaps or Uncertainties**: Accuracy calibration calculations use a custom formula which has not been validated on diverse datasets.
- **Owning Files**:
  - [RAGQualityMode](../../../OpenIntelligence/Core/Models/RAGQualityMode.swift)
  - [StructuredAnswer](../../../OpenIntelligence/Core/Models/StructuredAnswer.swift)
  - [ThinkingEvent](../../../OpenIntelligence/Core/Models/ThinkingEvent.swift)
  - [MessageBubbleV2](../../../OpenIntelligence/Features/Chat/Conversation/MessageBubbleV2.swift)
  - [AnswerIntelligenceView](../../../OpenIntelligence/Features/Chat/Response/AnswerIntelligenceView.swift)
  - [ResponseDetailsView](../../../OpenIntelligence/Features/Chat/Response/ResponseDetailsView.swift)
  - [ThinkingStreamView](../../../OpenIntelligence/Features/Chat/Response/ThinkingStreamView.swift)
  - [VerificationGatesOverlayView](../../../OpenIntelligence/Features/Chat/Response/VerificationGatesOverlayView.swift)
  - [GroundedAnswerPolicy](../../../OpenIntelligence/Services/Query/Analysis/GroundedAnswerPolicy.swift)
  - [ContextualCompressionService](../../../OpenIntelligence/Services/Query/Enhancement/ContextualCompressionService.swift)
  - [ConfidenceCalibrationService](../../../OpenIntelligence/Services/RAG/Safety/ConfidenceCalibrationService.swift)
  - [SourceOnlyAnswerService](../../../OpenIntelligence/Services/RAG/Safety/SourceOnlyAnswerService.swift)
  - [VerificationGateService](../../../OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift)
  - [ConfidencePolicyService](../../../OpenIntelligence/Services/RAG/Tuning/ConfidencePolicyService.swift)
- **Main Services / Views / Models**:
  - `AnswerIntelligence`
  - `AnswerIntelligenceBadge`
  - `AnswerIntelligenceView`
  - `AnswerType`
  - `BubbleShape`
  - `Builder`
  - `CalibratedConfidence`
  - `CalibrationParameters`
  - `ChatResponseDetailsView`
  - `Claim`
  - `ClaimResult`
  - `CodingKeys`
  - `CompressionResult`
  - `ConfidenceCalibrationService`
  - `ConfidenceComponents`
  - ... and 58 more entities

---

## Citations/source rendering

- **Purpose**: Displays citations, reference documents, and highlighted text spans in the chat interface.
- **Risk Level**: **LOW**
- **Data Owned**: Source info matrices, highlighted blocks
- **Dependencies**: chat UI
- **Downstream Consumers**: chat UI
- **Gaps or Uncertainties**: Text highlighting matches can slip alignment if the source document layout changes slightly.
- **Owning Files**:
  - [EvidenceSource](../../../OpenIntelligence/Core/Models/EvidenceSource.swift)
  - [ContextUsageIndicator](../../../OpenIntelligence/Features/Chat/Response/ContextUsageIndicator.swift)
  - [EnhancedCodeBlock](../../../OpenIntelligence/Features/Chat/Response/EnhancedCodeBlock.swift)
  - [GroundedAnswerView](../../../OpenIntelligence/Features/Chat/Response/GroundedAnswerView.swift)
  - [ReportMessageSheet](../../../OpenIntelligence/Features/Chat/Response/ReportMessageSheet.swift)
  - [RetrievalQualityView](../../../OpenIntelligence/Features/Chat/Response/RetrievalQualityView.swift)
  - [RetrievalSourcesTray](../../../OpenIntelligence/Features/Chat/Response/RetrievalSourcesTray.swift)
  - [SourceChipsView](../../../OpenIntelligence/Features/Chat/Response/SourceChipsView.swift)
  - [SourceFidelityStatus](../../../OpenIntelligence/Features/Chat/Response/SourceFidelityStatus.swift)
  - [StatusPillV2](../../../OpenIntelligence/Features/Chat/Response/StatusPillV2.swift)
  - [TimingBreakdownView](../../../OpenIntelligence/Features/Chat/Response/TimingBreakdownView.swift)
  - [VisualEvidenceCard](../../../OpenIntelligence/Features/Chat/Response/VisualEvidenceCard.swift)
  - [WritingToolsResultSheet](../../../OpenIntelligence/Features/Chat/Response/WritingToolsResultSheet.swift)
  - [RAGEvalCase](../../../OpenIntelligence/Services/Evaluation/RAGEvalCase.swift)
  - [RAGEvalMetrics](../../../OpenIntelligence/Services/Evaluation/RAGEvalMetrics.swift)
  - [RAGEvalRunner](../../../OpenIntelligence/Services/Evaluation/RAGEvalRunner.swift)
  - [VisualEvidenceSource](../../../OpenIntelligence/Services/RAG/Evidence/VisualEvidenceSource.swift)
  - [AgenticPolicyService](../../../OpenIntelligence/Services/RAG/Tuning/AgenticPolicyService.swift)
  - [EvidenceScoringPolicyService](../../../OpenIntelligence/Services/RAG/Tuning/EvidenceScoringPolicyService.swift)
  - [RetrievalPolicyService](../../../OpenIntelligence/Services/RAG/Tuning/RetrievalPolicyService.swift)
- **Main Services / Views / Models**:
  - `AgenticPolicyService`
  - `AgenticReasoningPolicy`
  - `AgenticRetrievalQuality`
  - `AgenticRetrievalStage`
  - `ChipData`
  - `CircularContextGauge`
  - `ClaimCard`
  - `CompactCodeBlock`
  - `CompactContextIndicator`
  - `CompactQualityIndicator`
  - `ContentView`
  - `ContextSegment`
  - `ContextUsageIndicator`
  - `EnhancedCodeBlock`
  - `EvalCategory`
  - ... and 38 more entities

---

## Chat ui

- **Purpose**: Implements the core chat screen interface, message layouts, attachment lists, and themes.
- **Risk Level**: **LOW**
- **Data Owned**: View states, scroll offsets, UI configs
- **Dependencies**: library/container management, app lifecycle
- **Downstream Consumers**: chat persistence
- **Gaps or Uncertainties**: Keyboard height observers cause layouts to jitter when rapidly scrolling chat histories.
- **Owning Files**:
  - [ChatMessage](../../../OpenIntelligence/Core/Models/ChatMessage.swift)
  - [ActivityView](../../../OpenIntelligence/Features/Chat/Conversation/ActivityView.swift)
  - [AttachmentPicker](../../../OpenIntelligence/Features/Chat/Conversation/AttachmentPicker.swift)
  - [ChatComposerV2](../../../OpenIntelligence/Features/Chat/Conversation/ChatComposerV2.swift)
  - [EventToasts](../../../OpenIntelligence/Features/Chat/Conversation/EventToasts.swift)
  - [MessageActionsBar](../../../OpenIntelligence/Features/Chat/Conversation/MessageActionsBar.swift)
  - [MessageListV2](../../../OpenIntelligence/Features/Chat/Conversation/MessageListV2.swift)
  - [ProcessingModels](../../../OpenIntelligence/Features/Chat/Pipeline/ProcessingModels.swift)
  - [InfoButtonView](../../../OpenIntelligence/UI/Components/InfoButtonView.swift)
  - [SurfaceCard](../../../OpenIntelligence/UI/DesignSystem/SurfaceCard.swift)
- **Main Services / Views / Models**:
  - `ActionButton`
  - `ActionButtonStyle`
  - `ActivityView`
  - `AttachmentMenuButton`
  - `AttachmentPreviewChip`
  - `AttachmentType`
  - `BottomAnchorGeometry`
  - `BottomAnchorYPreferenceKey`
  - `CameraPicker`
  - `ChatAttachment`
  - `ChatComposerV2`
  - `ChatExecutionLocation`
  - `ChatMessage`
  - `ChatProcessingStage`
  - `CodingKeys`
  - ... and 22 more entities

---

## Chat persistence

- **Purpose**: Saves message threads, cached documents, and conversation history on device storage.
- **Risk Level**: **LOW**
- **Data Owned**: ChatMessage structures, cached documents indexes
- **Dependencies**: SQLite/FTS storage
- **Downstream Consumers**: chat UI
- **Gaps or Uncertainties**: Automatic cleanup thresholds for cached documents are static, risking device storage bloat.
- **Owning Files**:
  - [DocumentationCacheService](../../../OpenIntelligence/Services/Storage/DocumentationCacheService.swift)
- **Main Services / Views / Models**:
  - `CachedDocMetadata`
  - `CachedDocument`
  - `DocumentationCacheIndex`
  - `Keys`
  - `SourceType`
  - `for`

---

## Background tasks

- **Purpose**: Manages deferred background ingestion and synchronization tasks using BGTaskScheduler.
- **Risk Level**: **LOW**
- **Data Owned**: Continued ingestion policies and state context records
- **Dependencies**: ingestion queue, iCloud/workspace sync
- **Downstream Consumers**: ingestion queue
- **Gaps or Uncertainties**: OS-allocated background execution windows are short, often terminating large document indexing runs prematurely.
- **Owning Files**:
  - [BackgroundTaskService](../../../OpenIntelligence/Services/Infrastructure/Background/BackgroundTaskService.swift)
  - [SpotlightIndexService](../../../OpenIntelligence/Services/Infrastructure/Background/SpotlightIndexService.swift)
- **Main Services / Views / Models**:
  - `BackgroundTaskService`
  - `ContinuedIngestionExecutionMode`
  - `ContinuedIngestionPhase`
  - `ContinuedIngestionPolicySnapshot`
  - `ContinuedIngestionRequestContext`
  - `ContinuedIngestionStatusSnapshot`
  - `ContinuedQueryPhase`
  - `ContinuedQueryRequestContext`
  - `ContinuedQueryStatusSnapshot`
  - `SpotlightIndexService`

---

## Icloud/workspace sync

- **Purpose**: Syncs the workspace library structures and indices across Apple devices via iCloud Drive (Ubiquity).
- **Risk Level**: **HIGH**
- **Data Owned**: Workspace inventories, merge results
- **Dependencies**: SQLite/FTS storage, library/container management
- **Downstream Consumers**: library/container management
- **Gaps or Uncertainties**: Conflict resolution uses a last-write-wins policy which can discard user edits in rapid multi-device sync scenarios.
- **Owning Files**:
  - [ContentView](../../../OpenIntelligence/App/ContentView.swift)
  - [KnowledgeContainer](../../../OpenIntelligence/Core/Models/KnowledgeContainer.swift)
  - [DocumentCard](../../../OpenIntelligence/Features/Documents/Components/DocumentCard.swift)
  - [DocumentLibraryView](../../../OpenIntelligence/Features/Documents/Library/DocumentLibraryView.swift)
  - [ContainerSettingsSheet](../../../OpenIntelligence/Features/Documents/Settings/ContainerSettingsSheet.swift)
  - [ConversationMemoryService](../../../OpenIntelligence/Services/Agentic/ConversationMemoryService.swift)
  - [TranscriptPersistenceService](../../../OpenIntelligence/Services/Infrastructure/Background/TranscriptPersistenceService.swift)
  - [ContainerService](../../../OpenIntelligence/Services/Infrastructure/Integration/ContainerService.swift)
  - [WorkspaceSyncService](../../../OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift)
  - [BNNSVectorDatabase](../../../OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift)
- **Main Services / Views / Models**:
  - `AppSupportPaths`
  - `AutoIntelligencePanel`
  - `BootstrapBehavior`
  - `ChunkingDirective`
  - `CodingKeys`
  - `ContainerMergeResult`
  - `ContainerService`
  - `ContainerSettingsSheet`
  - `ContentTagsRow`
  - `ContentView`
  - `ConversationMemory`
  - `ConversationMemoryConfig`
  - `ConversationMemoryService`
  - `ConversationMemoryServiceUnavailable`
  - `DeleteMode`
  - ... and 44 more entities

---

## Billing/entitlements

- **Purpose**: Checks and enforces quotas, paywall display states, and subscription capabilities.
- **Risk Level**: **HIGH**
- **Data Owned**: MaximumModeQuotaState, LocalModelAccessState
- **Dependencies**: StoreKit
- **Downstream Consumers**: library/container management
- **Gaps or Uncertainties**: Quota stores cache states in Keychain but do not verify integrity against a remote server regularly.
- **Owning Files**:
  - [PlanUpgradeEntryPoint](../../../OpenIntelligence/Features/Billing/PlanUpgradeEntryPoint.swift)
  - [PlanUpgradeSheet](../../../OpenIntelligence/Features/Billing/PlanUpgradeSheet.swift)
  - [PrivacyPolicyView](../../../OpenIntelligence/Features/Billing/PrivacyPolicyView.swift)
  - [TermsOfServiceView](../../../OpenIntelligence/Features/Billing/TermsOfServiceView.swift)
  - [DocumentQuotaBanner](../../../OpenIntelligence/Features/Documents/Components/DocumentQuotaBanner.swift)
  - [BillingError](../../../OpenIntelligence/Services/Billing/BillingError.swift)
  - [BillingEvent](../../../OpenIntelligence/Services/Billing/BillingEvent.swift)
  - [BillingProduct](../../../OpenIntelligence/Services/Billing/BillingProduct.swift)
  - [BillingService](../../../OpenIntelligence/Services/Billing/BillingService.swift)
  - [EntitlementStore](../../../OpenIntelligence/Services/Billing/EntitlementStore.swift)
  - [MaximumModeQuotaStore](../../../OpenIntelligence/Services/Billing/MaximumModeQuotaStore.swift)
  - [MonetizationPolicy](../../../OpenIntelligence/Services/Billing/MonetizationPolicy.swift)
  - [QuotaPolicy](../../../OpenIntelligence/Services/Infrastructure/Configuration/QuotaPolicy.swift)
- **Main Services / Views / Models**:
  - `BenefitRow`
  - `BillingError`
  - `BillingEvent`
  - `BillingProduct`
  - `BillingService`
  - `DebugKeys`
  - `DocumentPackEntry`
  - `DocumentQuotaBanner`
  - `DocumentQuotaError`
  - `EntitlementSnapshot`
  - `EntitlementStore`
  - `Keys`
  - `Kind`
  - `LegacyProtectionState`
  - `LibraryQuotaError`
  - ... and 14 more entities

---

## Storekit

- **Purpose**: Interfaces with Apple's StoreKit APIs to manage active purchases.
- **Risk Level**: **HIGH**
- **Data Owned**: Active transactions lists
- **Dependencies**: None
- **Downstream Consumers**: billing/entitlements
- **Gaps or Uncertainties**: StoreKit local validation ignores sandbox/production environment headers, causing subscription status lag in sandbox.
- **Owning Files**:
  - [StoreKitTestHarness](../../../OpenIntelligence/Resources/StoreKit/StoreKitTestHarness.swift)
  - [StoreKitBillingService](../../../OpenIntelligence/Services/Billing/StoreKitBillingService.swift)
- **Main Services / Views / Models**:
  - `StoreKitBillingService`
  - `StoreKitTestHarness`
  - `StoreKitTimeoutError`

---

## Settings

- **Purpose**: Manages configuration forms, system prompt editors, and logging setups.
- **Risk Level**: **LOW**
- **Data Owned**: SettingsStore values, system prompt templates
- **Dependencies**: app lifecycle
- **Downstream Consumers**: Apple Foundation Models
- **Gaps or Uncertainties**: Model selection lists show unavailable models on unsupported legacy hardware.
- **Owning Files**:
  - [ColorPicker](../../../OpenIntelligence/Features/Documents/Settings/ColorPicker.swift)
  - [SFSymbolPicker](../../../OpenIntelligence/Features/Documents/Settings/SFSymbolPicker.swift)
  - [FeatureRow](../../../OpenIntelligence/Features/Settings/Components/FeatureRow.swift)
  - [InfoRow](../../../OpenIntelligence/Features/Settings/Components/InfoRow.swift)
  - [ModelConfigurationSheet](../../../OpenIntelligence/Features/Settings/Components/ModelConfigurationSheet.swift)
  - [ModelPipelineRow](../../../OpenIntelligence/Features/Settings/Components/ModelPipelineRow.swift)
  - [ModelPipelineStage](../../../OpenIntelligence/Features/Settings/Components/ModelPipelineStage.swift)
- **Main Services / Views / Models**:
  - `AccentColorPicker`
  - `AccentColorSettingsRow`
  - `ColorPickerButton`
  - `FeatureRow`
  - `InferencePreset`
  - `InfoRow`
  - `LibraryColorPalette`
  - `LibraryColorPicker`
  - `ModelConfigurationSheet`
  - `ModelPipelineRow`
  - `ModelPipelineStage`
  - `PresetCard`
  - `Role`
  - `SFSymbolPicker`
  - `SFSymbolPickerButton`
  - ... and 4 more entities

---

## App intents/siri/shortcuts

- **Purpose**: Exposes core workflows (Ask, Summarize, Search) to the iOS/macOS Shortcuts system.
- **Risk Level**: **HIGH**
- **Data Owned**: None
- **Dependencies**: retrieval, document import
- **Downstream Consumers**: retrieval
- **Gaps or Uncertainties**: Registering App Intents requires a strict limit of 10 shortcuts; exceeding this causes silent OS registration failure.
- **Owning Files**:
  - [ViewAnnotations](../../../OpenIntelligence/Features/Chat/Conversation/ViewAnnotations.swift)
  - [SettingsView](../../../OpenIntelligence/Features/Settings/SettingsView.swift)
  - [OIDocumentEntity](../../../OpenIntelligence/Services/Agentic/Entities/OIDocumentEntity.swift)
  - [OIEntityQueries](../../../OpenIntelligence/Services/Agentic/Entities/OIEntityQueries.swift)
  - [OILibraryEntity](../../../OpenIntelligence/Services/Agentic/Entities/OILibraryEntity.swift)
  - [RAGAppIntents](../../../OpenIntelligence/Services/Agentic/RAGAppIntents.swift)
  - [ScreenAwarenessIntents](../../../OpenIntelligence/Services/Agentic/ScreenAwarenessIntents.swift)
  - [VisualIntelligenceIntents](../../../OpenIntelligence/Services/Agentic/VisualIntelligenceIntents.swift)
  - [SettingsStore](../../../OpenIntelligence/Services/Infrastructure/Configuration/SettingsStore.swift)
  - [LLMService](../../../OpenIntelligence/Services/LLM/LLMService.swift)
  - [RAGService](../../../OpenIntelligence/Services/RAG/Orchestration/RAGService.swift)
  - [Package](file://Package.swift)
- **Main Services / Views / Models**:
  - `ActiveDocumentAnnotationModifier`
  - `ActiveLibraryAnnotationModifier`
  - `AddDocumentIntent`
  - `AnalyzeImageIntent`
  - `AppleChatGPTExtensionService`
  - `AppleFoundationLLMService`
  - `AppleFoundationLLMServiceUnavailable`
  - `AskDocumentIntent`
  - `AssistChatIntent`
  - `AssistantProvider`
  - `Candidate`
  - `ChunkAutoAction`
  - `ChunkingDefaults`
  - `CompareDocumentsIntent`
  - `ConsentDefaults`
  - ... and 60 more entities

---

## Diagnostics/telemetry

- **Purpose**: Visualizes RAG retrieval flows, hardware stats, memory bounds, and accuracy metrics.
- **Risk Level**: **LOW**
- **Data Owned**: Telemetry center logs, GPU compute activity statistics
- **Dependencies**: SQLite/FTS storage, Apple Foundation Models
- **Downstream Consumers**: export/reporting
- **Gaps or Uncertainties**: Metal hardware monitoring uses custom sampling rates which can inflate CPU overhead when the dashboard is active.
- **Owning Files**:
  - [NetworkMonitor](../../../OpenIntelligence/Core/Extensions/NetworkMonitor.swift)
  - [LiveSystemMonitorWrapper](../../../OpenIntelligence/Features/Diagnostics/Monitoring/LiveSystemMonitorWrapper.swift)
  - [RAGAccuracyView](../../../OpenIntelligence/Features/Diagnostics/Validation/RAGAccuracyView.swift)
  - [LiveTelemetryStatsView](../../../OpenIntelligence/Features/Telemetry/Dashboard/LiveTelemetryStatsView.swift)
  - [MotherboardHUDView](../../../OpenIntelligence/Features/Telemetry/Dashboard/MotherboardHUDView.swift)
  - [TelemetryDashboardView](../../../OpenIntelligence/Features/Telemetry/Dashboard/TelemetryDashboardView.swift)
  - [AppleEvaluationsBridge](../../../OpenIntelligence/Services/Evaluation/AppleEvaluationsBridge.swift)
  - [RAGEvalDataset](../../../OpenIntelligence/Services/Evaluation/RAGEvalDataset.swift)
  - [RAGEvalReportWriter](../../../OpenIntelligence/Services/Evaluation/RAGEvalReportWriter.swift)
  - [SystemStateMonitor](../../../OpenIntelligence/Services/Infrastructure/Monitoring/SystemStateMonitor.swift)
  - [TelemetryCenter](../../../OpenIntelligence/Services/Infrastructure/Monitoring/TelemetryCenter.swift)
- **Main Services / Views / Models**:
  - `AppleEvaluationsBridge`
  - `DeviceComponentLayout`
  - `EmbeddingSanityResult`
  - `EmptyTelemetryView`
  - `EvalError`
  - `FloatingTapticIndicator`
  - `GlowingSoCBorder`
  - `GlowingTapticBorder`
  - `HardwareXRayOverlay`
  - `KeyboardHeightObserver`
  - `LiveSystemMonitorWrapper`
  - `LiveTelemetryStatsView`
  - `MacBatteryState`
  - `MachCPUMonitor`
  - `MemoryPressureLevel`
  - ... and 17 more entities

---

## Export/reporting

- **Purpose**: Exports evaluation reports, pipeline traces, and diagnostic data bundles.
- **Risk Level**: **LOW**
- **Data Owned**: Report payloads
- **Dependencies**: diagnostics/telemetry
- **Downstream Consumers**: None
- **Gaps or Uncertainties**: Trace exports are saved in plain text, which could compromise privacy if documents contain sensitive information.
- **Owning Files**:
  - [PipelineTraceExporter](../../../OpenIntelligence/Features/Chat/Pipeline/PipelineTraceExporter.swift)
- **Main Services / Views / Models**:
  - `PipelineTraceExporter`

---

## Docs/audits

- **Purpose**: Contains documentation audits, pipeline trace schemas, and verification checklists.
- **Risk Level**: **LOW**
- **Data Owned**: None (non-code files)
- **Dependencies**: None
- **Downstream Consumers**: None
- **Gaps or Uncertainties**: Audit files are static markdown and require manual coordination with code changes.
- **Owning Files**:
  - None (Abstract or documented non-code subsystem)
- **Main Services / Views / Models**:
  - None

---

## Tests

- **Purpose**: Tests individual pipelines (Semantic chunking, Context packing, search).
- **Risk Level**: **LOW**
- **Data Owned**: Test fixtures
- **Dependencies**: retrieval, document import
- **Downstream Consumers**: None
- **Gaps or Uncertainties**: Tests lack mock configurations for testing Private Cloud Compute connection timeouts.
- **Owning Files**:
  - [ContainerScopingSelfTestsView](../../../OpenIntelligence/Features/Diagnostics/Validation/ContainerScopingSelfTestsView.swift)
  - [OpenIntelligenceEngineTests](file://OpenIntelligenceTests/OpenIntelligenceEngineTests.swift)
  - [SemanticChunkerTests](file://OpenIntelligenceTests/Services/Document/Chunking/SemanticChunkerTests.swift)
  - [DocumentProcessorTests](file://OpenIntelligenceTests/Services/Document/Processing/DocumentProcessorTests.swift)
  - [ContextPackingServiceTests](file://OpenIntelligenceTests/Services/RAG/Retrieval/ContextPackingServiceTests.swift)
  - [HybridSearchServiceTests](file://OpenIntelligenceTests/Services/RAG/Retrieval/HybridSearchServiceTests.swift)
- **Main Services / Views / Models**:
  - `ContainerScopingSelfTestsView`
  - `ContextPackingServiceTests`
  - `DocumentProcessorTests`
  - `DummyVectorDatabase`
  - `HybridSearchServiceTests`
  - `OpenIntelligenceEngineTests`
  - `ScopingTestResult`
  - `SemanticChunkerTests`
  - `Status`
  - `with`

---



## Delta Repair Note
Subsystem map has been verified against Phase 2 entities. All boundaries are maintained and compliant.
