import os

WORKSPACE_DIR = "/Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public"
OUTPUT_PATH = os.path.join(WORKSPACE_DIR, "Docs/AUDIT/05_COMPONENT_REALITY_MAP_4.1.md")

def main():
    content = """# Phase 5: Component-by-Component Reality Map - OpenIntelligence v4.1

This document provides a component-by-component reality audit of the OpenIntelligence v4.1 application, mapping claimed capabilities in documentation and marketing against actual code implementations.

---

## 1. App identity and platform support
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Runs natively on Apple Silicon devices (iOS 26.0+, macOS 16.0+/26.0+, visionOS 26.0+).
- **Technical summary:** Xcode project defines targets for iOS, macOS, and visionOS with deployment target set to `26.0`.
- **Evidence:** `project.pbxproj` (lines 675-697).
- **Not shipped / caveats:** Mac Catalyst is explicitly disabled (`SUPPORTS_MACCATALYST = NO`).
- **Docs impact:** None.
- **Public-safe wording:** "Built natively for Apple Silicon (Mac, iPad, iPhone, and Apple Vision Pro)."
- **Public-unsafe wording:** "Supports macOS versions older than Golden Gate (26.0)."

---

## 2. App launch and navigation
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Launch app to root layout with 5 tabs: Chat, Documents, Atlas (Visualizations), Database, and Settings.
- **Technical summary:** SwiftUI navigation container using TabView with 5 navigation stacks.
- **Evidence:** `OpenIntelligence/App/ContentView.swift` (lines 197-250).
- **Not shipped / caveats:** Deep links only support routing to Chat or Documents tabs.
- **Docs impact:** None.
- **Public-safe wording:** "Simple tabbed interface to manage documents, search the database, and chat."

---

## 3. Document library
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Manage lists of documents inside workspaces.
- **Technical summary:** Implemented via `DocumentLibraryView` backed by `ContainerService` which scans directories.
- **Evidence:** `OpenIntelligence/Features/Documents/Library/DocumentLibraryView.swift`.
- **Not shipped / caveats:** Deletion is not fully integrated with cloud-sync storage paths in the free tier.
- **Public-safe wording:** "Organize your PDFs and notes into workspaces."

---

## 4. Library/workspace/container model
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Workspaces isolate documents from each other.
- **Technical summary:** `KnowledgeContainer` struct models isolated document silos.
- **Evidence:** `OpenIntelligence/Core/Models/KnowledgeContainer.swift`.
- **Not shipped / caveats:** Workspaces do not support cross-workspace queries in standard mode.
- **Public-safe wording:** "Containers isolate knowledge domains."

---

## 5. Document import
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Import PDFs, notes, and text files.
- **Technical summary:** Triggers `DocumentProcessor.shared.ingest` to run parsing pipeline.
- **Evidence:** `OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift`.
- **Not shipped / caveats:** Large files (>10MB) can cause high memory usage on devices with 8GB RAM.
- **Public-safe wording:** "Import PDF, TXT, and Markdown files."

---

## 6. Supported file types
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** PDF, Markdown, and TXT files.
- **Technical summary:** Layout extraction checks file extensions and processes text or runs OCR on PDFs/images.
- **Evidence:** `OpenIntelligence/Services/Document/Processing/IntelligentDocumentProcessor.swift`.
- **Not shipped / caveats:** Claimed support for Office/iWork docs, CSV, or audio/video files is mostly stubbed/scaffolded.
- **Public-safe wording:** "Fully supports PDF, Markdown, and text files."
- **Public-unsafe wording:** "Fully supports spreadsheets, slideshows, and audio/video files."

---

## 7. PDF processing
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Extract text page-by-page from PDFs.
- **Technical summary:** PDFKit-based document parsing for digital text extraction.
- **Evidence:** `OpenIntelligence/Services/Document/Processing/LayoutAwareExtractor.swift`.
- **Not shipped / caveats:** Highly complex layout structures (multi-column tables) can lose context.
- **Public-safe wording:** "Fast, private PDF text extraction."

---

## 8. Page complexity analysis
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Skips OCR scanning for clean digital text files, saving processing time.
- **Technical summary:** `PageComplexityAnalyzer` counts digital characters vs. images on a page to decide whether to trigger OCR.
- **Evidence:** `OpenIntelligence/Services/Document/Chunking/PageComplexityAnalyzer.swift`.
- **Not shipped / caveats:** Pages with mixed content might still run full OCR scan.
- **Public-safe wording:** "Automatically detects digital text to bypass OCR and speed up document import."

---

## 9. Vision OCR
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Extracts text from scanned documents or pictures using device camera.
- **Technical summary:** Uses Apple's Vision framework `VNRecognizeTextRequest` on images and scanned pages.
- **Evidence:** `OpenIntelligence/Services/Document/Processing/StructuredDocumentParser.swift`.
- **Not shipped / caveats:** Performance on hand-written notes is limited by Apple Vision engine capabilities.
- **Public-safe wording:** "Built-in Apple Vision OCR for scanned files and images."

---

## 10. Structured PDF parsing
- **Status:** `SHIPPED_INTERNAL`
- **User-facing summary:** Preserves document hierarchy during import.
- **Technical summary:** Text blocks are grouped based on layout bounding boxes.
- **Evidence:** `OpenIntelligence/Services/Document/Processing/LayoutAwareExtractor.swift`.
- **Not shipped / caveats:** Multi-page spans can have extraction borders.
- **Public-safe wording:** "Layout-aware parsing."

---

## 11. Table extraction
- **Status:** `SCAFFOLDED`
- **User-facing summary:** Parse structural tables from documents.
- **Technical summary:** `SpatialDocumentAnalyzer` defines structs for table cells but doesn't implement reconstruction of complex data.
- **Evidence:** `OpenIntelligence/Services/Document/Analysis/SpatialDocumentAnalyzer.swift`.
- **Not shipped / caveats:** Table layout reconstruction is scaffolded and does not output formatted tables to the LLM context.
- **Public-safe wording:** "Scaffolded table detection."
- **Public-unsafe wording:** "Full automatic table extraction and semantic cell mapping."

---

## 12. List extraction
- **Status:** `SCAFFOLDED`
- **User-facing summary:** Parse lists.
- **Technical summary:** Layout parser reads list bullets but treats them as normal text blocks.
- **Evidence:** `OpenIntelligence/Services/Document/Processing/LayoutAwareExtractor.swift`.
- **Not shipped / caveats:** Treating list bullets as normal text blocks without bullet hierarchical understanding.
- **Public-safe wording:** "Basic bullet list text parsing."

---

## 13. Image/visual evidence extraction
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Select images for text extraction.
- **Technical summary:** Passes UI images directly to the Vision text request.
- **Evidence:** `OpenIntelligence/Features/Camera/DocumentCaptureView.swift`.
- **Not shipped / caveats:** Vision does not output semantic bounding boxes to user in a visual overlay for answers.
- **Public-safe wording:** "Import images and screenshots."

---

## 14. Audio/video transcription
- **Status:** `SCAFFOLDED`
- **User-facing summary:** Transcribe voice notes or video.
- **Technical summary:** `AudioTranscriptionService` defines stubs returning static empty text or error.
- **Evidence:** `OpenIntelligence/Services/Document/Extraction/AudioTranscriptionService.swift`.
- **Not shipped / caveats:** Audio and video processing is not implemented in the production build.
- **Public-safe wording:** "Audio transcription is scaffolded for future releases."
- **Public-unsafe wording:** "Transcribe audio and video on-device."

---

## 15. XML / large-file streaming
- **Status:** `SHIPPED_INTERNAL`
- **User-facing summary:** Stream large XML schemas.
- **Technical summary:** XML parser streams tags progressively.
- **Evidence:** `OpenIntelligence/Services/Document/Processing/StreamingXMLProcessor.swift`.
- **Not shipped / caveats:** Restricted to XML schemas, not general TXT files.
- **Public-safe wording:** "Streams XML files."

---

## 16. Text normalization / OCR cleanup
- **Status:** `SHIPPED_INTERNAL`
- **User-facing summary:** Clean up weird characters in OCR text.
- **Technical summary:** String extension removes double spaces, normalizes punctuation.
- **Evidence:** `OpenIntelligence/Services/Document/Extraction/LanguageDetectionService.swift`.
- **Not shipped / caveats:** Cannot fix OCR spelling errors.
- **Public-safe wording:** "Normalizes extracted text punctuation."

---

## 17. Dynamic OCR vocabulary
- **Status:** `SCAFFOLDED`
- **User-facing summary:** Custom OCR lexicon.
- **Technical summary:** Option exists in configuration but isn't passed to the Vision API text request.
- **Evidence:** `OpenIntelligence/Services/Document/Config/OCRConfiguration.swift`.
- **Not shipped / caveats:** Custom dictionary does not affect OCR extraction accuracy.
- **Public-safe wording:** "Planned dynamic vocabulary."

---

## 18. Semantic chunking
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Splits text into chunks by sentences.
- **Technical summary:** `SemanticChunker` groups text into overlapping sentence windows.
- **Evidence:** `OpenIntelligence/Services/Document/Chunking/SemanticChunker.swift`.
- **Not shipped / caveats:** Does not dynamically evaluate sentence embedding similarity to split.
- **Public-safe wording:** "Sentence-level text chunking with overlap."

---

## 19. Structure-aware chunking
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Respects headers and paragraphs.
- **Technical summary:** Sentence chunker avoids merging across major markdown headings.
- **Evidence:** `OpenIntelligence/Services/Document/Chunking/SemanticChunker.swift`.
- **Not shipped / caveats:** Restricted to Markdown files; PDF header boundaries are heuristic-based.
- **Public-safe wording:** "Header-boundary aware chunking."

---

## 20. Token-limit enforcement
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Prevent model crashes from long prompts.
- **Technical summary:** `FoundationModelTokenBudget` limits prompt assembly to target sizes.
- **Evidence:** `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelTokenBudget.swift`.
- **Not shipped / caveats:** Basic word/token estimator.
- **Public-safe wording:** "Context window token budgeting."

---

## 21. Full-text storage / SQLite FTS
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Fast keyword search.
- **Technical summary:** SQLite database using FTS5 virtual tables.
- **Evidence:** `OpenIntelligence/Services/Storage/SQLiteFullTextService.swift`.
- **Not shipped / caveats:** DB connection must be closed during backgrounding.
- **Public-safe wording:** "SQLite-backed keyword search (FTS5)."

---

## 22. Vector storage
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Local vector database.
- **Technical summary:** Implemented via `BNNSVectorDatabase` storing vectors in a flat JSON structure.
- **Evidence:** `OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift`.
- **Not shipped / caveats:** Vectura (HNSW ANN) vector storage is scaffolded / stubbed.
- **Public-safe wording:** "BNNS-accelerated persistent vector database."

---

## 23. Embedding generation
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Vector embeddings computed locally on device.
- **Technical summary:** CoreML model for text embedding generation.
- **Evidence:** `OpenIntelligence/Services/Embedding/Providers/CoreMLSentenceEmbeddingProvider.swift`.
- **Not shipped / caveats:** CoreAI embedding generation is scaffolded.
- **Public-safe wording:** "CoreML-backed local text embeddings."

---

## 24. Metal / GPU acceleration paths
- **Status:** `SHIPPED_INTERNAL`
- **User-facing summary:** Metal GPU-accelerated calculations.
- **Technical summary:** Metal compute shaders used in similarity checking.
- **Evidence:** `OpenIntelligence/Services/Infrastructure/Compute/GPUComputeService.swift`.
- **Not shipped / caveats:** Benchmarks showing exact "4x speedup" are development-specific.
- **Public-safe wording:** "Metal-backed similarity acceleration."
- **Public-unsafe wording:** "Brings 4x battery improvements for all query lookups."

---

## 25. Retrieval pipeline
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Pulls relevant document passages to answer questions.
- **Technical summary:** Hybrid search matches keyword + vector ranks, followed by reranking.
- **Evidence:** `OpenIntelligence/Services/RAG/Orchestration/RAGService+KnowledgeRetrievalEngine.swift`.
- **Not shipped / caveats:** None.
- **Public-safe wording:** "Hybrid retrieval system."

---

## 26. Hybrid search
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Combines keyword search and semantic matching.
- **Technical summary:** Re-ranks combined FTS5 + cosine similarity results.
- **Evidence:** `OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift`.
- **Not shipped / caveats:** None.
- **Public-safe wording:** "Combined vector and keyword search."

---

## 27. Parent/sibling/chunk expansion
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Retrieval pulls surrounding context.
- **Technical summary:** `ParentDocumentService` retrieves full paragraph context for a chunk.
- **Evidence:** `OpenIntelligence/Services/RAG/Retrieval/ParentDocumentService.swift`.
- **Not shipped / caveats:** None.
- **Public-safe wording:** "Parent context expansion."

---

## 28. Context packing
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Bundles retrieved paragraphs into LLM prompt.
- **Technical summary:** De-duplicates overlapping paragraphs and packs up to token budget.
- **Evidence:** `OpenIntelligence/Services/RAG/Retrieval/ContextPackingService.swift`.
- **Not shipped / caveats:** None.
- **Public-safe wording:** "Intelligent context packing."

---

## 29. Query analysis / rewriting / HyDE
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Enhances user questions for better matching.
- **Technical summary:** Generates synthetic answers in memory (HyDE) before running vector searches.
- **Evidence:** `OpenIntelligence/Services/Query/Rewriting/HyDEService.swift`.
- **Not shipped / caveats:** HyDE is bypassed for simple lookup queries.
- **Public-safe wording:** "On-device query enhancement."

---

## 30. Standard query mode
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Fast local Q&A.
- **Technical summary:** Uses on-device 4K context LLM session.
- **Evidence:** `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelRoutePolicy.swift`.
- **Not shipped / caveats:** Uses 4K token context ceiling.
- **Public-safe wording:** "Fast, local standard search queries."

---

## 31. Deep Think mode
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Thinks longer before responding, routing to Private Cloud Compute if consented.
- **Technical summary:** Policy sets route to PCC with moderate reasoning level.
- **Evidence:** `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelRoutePolicy.swift`.
- **Not shipped / caveats:** Requires active Apple PCC availability and user consent.
- **Public-safe wording:** "Deep Think routing option."

---

## 32. Maximum mode
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Maximum reasoning level, subject to daily usage caps for free tiers.
- **Technical summary:** Routes to PCC with deep reasoning level and checks billing quotas.
- **Evidence:** `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelRoutePolicy.swift`.
- **Not shipped / caveats:** Gated by free daily cap of 3 queries.
- **Public-safe wording:** "Maximum reasoning mode."

---

## 33. Agentic orchestration
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Multi-step tool execution.
- **Technical summary:** Implemented via `AgenticOrchestrator` which manages model tool-calling loops.
- **Evidence:** `OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift`.
- **Not shipped / caveats:** None.
- **Public-safe wording:** "Tool-calling agentic RAG orchestration."

---

## 34. Apple Foundation Models integration
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Native Apple Intelligence integrations on supported operating systems.
- **Technical summary:** Compiles with `FoundationModels` framework when available.
- **Evidence:** `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelSessionFactory.swift`.
- **Not shipped / caveats:** Dependent on iOS 26+ and macOS 16+ support.
- **Public-safe wording:** "Integrates natively with Apple's Foundation Models on supported systems."

---

## 35. On-device route
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Runs standard inquiries on your device.
- **Technical summary:** Routes session to `SystemLanguageModel.default`.
- **Evidence:** `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelSessionFactory.swift` (line 45).
- **Not shipped / caveats:** Bypassed when local model is updating.
- **Public-safe wording:** "Default on-device reasoning path."

---

## 36. PCC route
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Scales complex tasks to Apple's Private Cloud Compute.
- **Technical summary:** Session is routed to `PrivateCloudComputeLanguageModel()`.
- **Evidence:** `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelSessionFactory.swift` (line 55).
- **Not shipped / caveats:** Bypassed if PCC is unavailable.
- **Public-safe wording:** "Supports secure Private Cloud Compute scaling."

---

## 37. FoundationModelSessionFactory
- **Status:** `SHIPPED_INTERNAL`
- **User-facing summary:** Allocates AI sessions.
- **Technical summary:** Creates `LanguageModelSession` with specified route and tools.
- **Evidence:** `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelSessionFactory.swift`.
- **Not shipped / caveats:** None.
- **Public-safe wording:** "Dynamic session factory."

---

## 38. FoundationModelRoutePolicy
- **Status:** `SHIPPED_INTERNAL`
- **User-facing summary:** Selects optimal execution model.
- **Technical summary:** Evaluates query type and estimated context size to determine route.
- **Evidence:** `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelRoutePolicy.swift`.
- **Not shipped / caveats:** None.
- **Public-safe wording:** "Execution routing controller."

---

## 39. FoundationModelStructuredGenerator
- **Status:** `SHIPPED_INTERNAL`
- **User-facing summary:** Structural response format.
- **Technical summary:** Forces structured schema generation via the model.
- **Evidence:** `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelStructuredGenerator.swift`.
- **Not shipped / caveats:** Uses word-based schema stubs when models fail.
- **Public-safe wording:** "Structured response generation."

---

## 40. FoundationModelToolRegistry
- **Status:** `SHIPPED_INTERNAL`
- **User-facing summary:** Available tools for AI to retrieve documents.
- **Technical summary:** Exposes search functions as registered tool parameters.
- **Evidence:** `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelToolRegistry.swift`.
- **Not shipped / caveats:** None.
- **Public-safe wording:** "Tool definition registry."

---

## 41. FoundationModelPromptCompiler
- **Status:** `SHIPPED_INTERNAL`
- **User-facing summary:** Prompt templates builder.
- **Technical summary:** Assembles prompts and system instructions for the LLM.
- **Evidence:** `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelPromptCompiler.swift`.
- **Not shipped / caveats:** None.
- **Public-safe wording:** "System prompt compiler."

---

## 42. FoundationModelErrorMapper
- **Status:** `SHIPPED_INTERNAL`
- **User-facing summary:** Translates system model errors to readable texts.
- **Technical summary:** Maps SDK errors into friendly user-facing messages.
- **Evidence:** `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelErrorMapper.swift`.
- **Not shipped / caveats:** None.
- **Public-safe wording:** "System error mapping."

---

## 43. Transcript/history handling
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Keeps conversation flow.
- **Technical summary:** Saves conversation transcripts to disk on app background.
- **Evidence:** `OpenIntelligence/Services/Infrastructure/Background/TranscriptPersistenceService.swift`.
- **Not shipped / caveats:** Bypassed if user disables chat history.
- **Public-safe wording:** "Auto-persisted chat history."

---

## 44. Verification gates
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Double checks answers for correctness.
- **Technical summary:** RAG pipeline runs validation checks on output citations.
- **Evidence:** `OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift`.
- **Not shipped / caveats:** Adds latency to the total query time.
- **Public-safe wording:** "Citation verification gates."

---

## 45. Confidence calibration
- **Status:** `SHIPPED_INTERNAL`
- **User-facing summary:** Calibrates confidence score.
- **Technical summary:** `ConfidenceCalibrationService` grades response grounding.
- **Evidence:** `OpenIntelligence/Services/RAG/Safety/ConfidenceCalibrationService.swift`.
- **Not shipped / caveats:** Static heuristic grading.
- **Public-safe wording:** "Answer confidence rating."

---

## 46. Numeric sanity checks
- **Status:** `SHIPPED_INTERNAL`
- **User-facing summary:** Verifies numbers in answers.
- **Technical summary:** Checks if numbers in generated response match source text.
- **Evidence:** `OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift`.
- **Not shipped / caveats:** Heuristics based, not mathematical proofing.
- **Public-safe wording:** "Numeric consistency checks."

---

## 47. Contradiction checks
- **Status:** `SHIPPED_INTERNAL`
- **User-facing summary:** Detects conflicting info in answers.
- **Technical summary:** Scans context for contradiction triggers.
- **Evidence:** `OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift`.
- **Not shipped / caveats:** Limited to simple negation detection.
- **Public-safe wording:** "Basic contradiction scanning."

---

## 48. Semantic grounding
- **Status:** `SHIPPED_INTERNAL`
- **User-facing summary:** Ensures answers match source content.
- **Technical summary:** Verifies response chunks align semantically with text database.
- **Evidence:** `OpenIntelligence/Services/RAG/Safety/SourceOnlyAnswerService.swift`.
- **Not shipped / caveats:** None.
- **Public-safe wording:** "Semantic grounding validation."

---

## 49. Abstention behavior
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** AI declines to answer when info is missing.
- **Technical summary:** Abstained queries output a predefined "I do not know" response instead of hallucinating.
- **Evidence:** `OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift`.
- **Not shipped / caveats:** None.
- **Public-safe wording:** "Automatic abstention policy when context is insufficient."

---

## 50. Answer rendering
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Beautiful answers in chat bubbles.
- **Technical summary:** Rendered via SwiftUI Markdown Views.
- **Evidence:** `OpenIntelligence/Features/Chat/Response/GroundedAnswerView.swift`.
- **Not shipped / caveats:** None.
- **Public-safe wording:** "Rich text Markdown answer rendering."

---

## 51. Citations/source cards
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Interactive source cards under the answer.
- **Technical summary:** SwiftUI components linking to citation positions.
- **Evidence:** `OpenIntelligence/Features/Chat/Response/SourceChipsView.swift`.
- **Not shipped / caveats:** None.
- **Public-safe wording:** "Interactive source citation chips."

---

## 52. Grounded answer UI
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Highlights source page and lines.
- **Technical summary:** Opens document page matching the citation ID.
- **Evidence:** `OpenIntelligence/Features/Chat/Response/GroundedAnswerView.swift`.
- **Not shipped / caveats:** Mixed pages might not align perfectly on some complex PDF layouts.
- **Public-safe wording:** "Visual grounding highlights."

---

## 53. Visual evidence cards
- **Status:** `SCAFFOLDED`
- **User-facing summary:** Display images of the source page.
- **Technical summary:** View exists but displays a generic document placeholder.
- **Evidence:** `OpenIntelligence/Features/Chat/Response/VisualEvidenceCard.swift`.
- **Not shipped / caveats:** Visual page crop rendering is scaffolded.
- **Public-safe wording:** "Scaffolded visual evidence previews."
- **Public-unsafe wording:** "Shows pictures of the exact paragraphs from the original page."

---

## 54. Unified Metrics Bar
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Performance metrics bar at bottom of chat.
- **Technical summary:** Displays execution speed, model routing state, and token counts.
- **Evidence:** `OpenIntelligence/Features/Chat/Response/UnifiedMetricsBar.swift`.
- **Not shipped / caveats:** Speed telemetry might have minor estimation variance.
- **Public-safe wording:** "Real-time performance telemetry."

---

## 55. Thinking stream / reasoning telemetry
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Displays reasoning steps while AI compiles answers.
- **Technical summary:** Stream updates UI based on `ThinkingEvent` changes.
- **Evidence:** `OpenIntelligence/Features/Chat/Response/ThinkingStreamView.swift`.
- **Not shipped / caveats:** None.
- **Public-safe wording:** "Live reasoning step telemetry."

---

## 56. Hardware telemetry / motherboard/HUD
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** HUD showing CPU/GPU and hardware diagnostics.
- **Technical summary:** Renders memory usage and device metrics.
- **Evidence:** `OpenIntelligence/Features/Telemetry/Dashboard/MotherboardHUDView.swift`.
- **Not shipped / caveats:** Requires diagnostic privileges to access raw thermal indexes.
- **Public-safe wording:** "Hardware HUD metrics."

---

## 57. Liquid Glass UI helpers
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Frosted glass effect UI.
- **Technical summary:** Custom modifier applying `.glassEffect` styling.
- **Evidence:** `OpenIntelligence/UI/DesignSystem/SurfaceCard.swift`.
- **Not shipped / caveats:** Standard iOS/macOS system glass.
- **Public-safe wording:** " Frosted glass design styling."

---

## 58. Suggested questions
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Proposes grammatically clean follow-up questions.
- **Technical summary:** Suggestion generator filters out grammatical noise.
- **Evidence:** `OpenIntelligence/Services/Query/UX/SuggestedQuestionsService.swift`.
- **Not shipped / caveats:** Bypassed when offline suggestions are disabled.
- **Public-safe wording:** "Smart suggested follow-up questions."

---

## 59. NLTagger / NaturalLanguage usage
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Clean grammatical suggestions.
- **Technical summary:** Uses `NLTagger` to analyze part-of-speech structure.
- **Evidence:** `OpenIntelligence/Services/Query/UX/SuggestedQuestionsService.swift`.
- **Not shipped / caveats:** Bypassed on unsupported languages.
- **Public-safe wording:** "Local part-of-speech language filtering."

---

## 60. Settings
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Configure options.
- **Technical summary:** System settings view editing `SettingsStore`.
- **Evidence:** `OpenIntelligence/Features/Settings/SettingsView.swift`.
- **Not shipped / caveats:** None.
- **Public-safe wording:** "Advanced settings panel."

---

## 61. Model selector
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Choose the default on-device model.
- **Technical summary:** UI picker modifying configuration parameters.
- **Evidence:** `OpenIntelligence/Features/Settings/Components/ModelSelectorSheet.swift`.
- **Not shipped / caveats:** Only displays available system models.
- **Public-safe wording:** "Flexible local model selection."

---

## 62. PCC consent / privacy settings
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Control when queries scale to Private Cloud Compute.
- **Technical summary:** Consent toggle stored in `SettingsStore`.
- **Evidence:** `OpenIntelligence/Features/Settings/Components/ModelConfigurationSheet.swift`.
- **Not shipped / caveats:** Bypassing consent falls back to local execution.
- **Public-safe wording:** "Private Cloud Compute toggle control."

---

## 63. Billing products
- **Status:** `RESOURCE_ONLY`
- **User-facing summary:** Purchase options in the StoreKit setup.
- **Technical summary:** Product configurations registered in `StoreKitConfiguration.storekit`.
- **Evidence:** `OpenIntelligence/Resources/StoreKit/StoreKitConfiguration.storekit`.
- **Not shipped / caveats:** Standard StoreKit sandbox.
- **Public-safe wording:** "StoreKit purchases integration."

---

## 64. StoreKit 2 purchase flow
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Standard payment sheet to upgrade.
- **Technical summary:** Implemented via `StoreKitBillingService` using the StoreKit 2 API.
- **Evidence:** `OpenIntelligence/Services/Billing/StoreKitBillingService.swift`.
- **Not shipped / caveats:** None.
- **Public-safe wording:** "Secure App Store checkout."

---

## 65. Entitlement store
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Tracks active upgrades.
- **Technical summary:** Manages user purchase states in Keychain.
- **Evidence:** `OpenIntelligence/Services/Billing/EntitlementStore.swift`.
- **Not shipped / caveats:** Reconciled on launch.
- **Public-safe wording:** "Local entitlements cache."

---

## 66. Quota policy
- **Status:** `SHIPPED_INTERNAL`
- **User-facing summary:** Gates access to free tier limits.
- **Technical summary:** Validates file counts against `QuotaPolicy`.
- **Evidence:** `OpenIntelligence/Services/Infrastructure/Configuration/QuotaPolicy.swift`.
- **Not shipped / caveats:** None.
- **Public-safe wording:** "Workspace quota policy."

---

## 67. Free/Pro/Lifetime tiers
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Free plan (5 docs), Pro ($9.99/mo, 1000 docs), Lifetime ($49.99, unlimited docs).
- **Technical summary:** Tiers mapped and validated in `EntitlementStore` and `QuotaPolicy`.
- **Evidence:** `OpenIntelligence/Services/Billing/WorkspaceTier.swift`.
- **Not shipped / caveats:** Pro cap is exactly 1000 documents.
- **Public-safe wording:** "Three transparent subscription plans."
- **Public-unsafe wording:** "Pro gives unlimited documents."

---

## 68. Document pack add-on
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Consumable pack to add 10 more documents.
- **Technical summary:** Increments allowed count by 10 per pack.
- **Evidence:** `OpenIntelligence/Services/Infrastructure/Configuration/QuotaPolicy.swift` (line 18).
- **Not shipped / caveats:** None.
- **Public-safe wording:** "+10 document expansion packs."

---

## 69. Legacy paid protection
- **Status:** `SCAFFOLDED`
- **User-facing summary:** Protects older purchases.
- **Technical summary:** Mapped in configuration but not checked during StoreKit verification.
- **Evidence:** `OpenIntelligence/Services/Billing/MonetizationPolicy.swift`.
- **Not shipped / caveats:** Legacy protection is scaffolded.
- **Public-safe wording:** "Scaffolded purchase protection."

---

## 70. iCloud/sync/storage
- **Status:** `SCAFFOLDED`
- **User-facing summary:** Sync workspaces across devices.
- **Technical summary:** `WorkspaceSyncService` contains stubs for file replication.
- **Evidence:** `OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift`.
- **Not shipped / caveats:** Actual iCloud sync is not implemented.
- **Public-safe wording:** "iCloud sync is planned for future updates."
- **Public-unsafe wording:** "Instantly sync documents across iPhone, iPad, and Mac."

---

## 71. Core Spotlight indexing
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Find documents through system Spotlight.
- **Technical summary:** Indexes chunks using `CSSearchableIndex`.
- **Evidence:** `OpenIntelligence/Services/Infrastructure/Background/SpotlightIndexService.swift`.
- **Not shipped / caveats:** Bypassed if system search is turned off.
- **Public-safe wording:** "Spotlight system integration."

---

## 72. AppEntity / AppIntents
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Shortcuts and Siri integrations.
- **Technical summary:** Mapped to App Entities and Siri query handlers.
- **Evidence:** `OpenIntelligence/Services/Agentic/RAGAppIntents.swift`.
- **Not shipped / caveats:** Bypassed on older operating systems.
- **Public-safe wording:** "App Intents shortcuts support."

---

## 73. Siri integration status
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Siri can query libraries.
- **Technical summary:** Leverages App Intents to answer voice requests.
- **Evidence:** `OpenIntelligence/Services/Agentic/RAGAppIntents.swift`.
- **Not shipped / caveats:** Bypassed if voice permissions are off.
- **Public-safe wording:** "Siri shortcuts query support."

---

## 74. Core AI registry/backend status
- **Status:** `SCAFFOLDED`
- **User-facing summary:** Direct silicon compilation layer.
- **Technical summary:** Defined registry but inference is stubbed.
- **Evidence:** `OpenIntelligence/Services/AIPlatform/CoreAI/CoreAIModelRegistry.swift`.
- **Not shipped / caveats:** CoreAI engine transition is scaffolded.
- **Public-safe wording:** "Planned Core AI registry."
- **Public-unsafe wording:** "Custom compiled silicon execution engine."

---

## 75. RAG evaluation framework
- **Status:** `SHIPPED_USER_FACING`
- **User-facing summary:** Local evaluation runner to test RAG quality.
- **Technical summary:** Implemented via `RAGEvalRunner` matching local targets.
- **Evidence:** `OpenIntelligence/Services/Evaluation/RAGEvalRunner.swift`.
- **Not shipped / caveats:** None.
- **Public-safe wording:** "Built-in evaluations engine."

---

## 76. Debug validation harnesses
- **Status:** `DEBUG_ONLY`
- **User-facing summary:** None.
- **Technical summary:** Compiles only in debug to run synthetic cases.
- **Evidence:** `OpenIntelligence/App/DebugRAGValidationHarness.swift`.
- **Not shipped / caveats:** Excluded from App Store build.
- **Public-safe wording:** "Developer validation tooling."

---

## 77. Scripts
- **Status:** `SCRIPT_ONLY`
- **User-facing summary:** None.
- **Technical summary:** Python scripts in `scripts/` folder.
- **Evidence:** `scripts/run_rag_benchmarks.py`.
- **Not shipped / caveats:** None.
- **Public-safe wording:** "Development automation scripts."

---

## 78. Fastlane metadata
- **Status:** `RESOURCE_ONLY`
- **User-facing summary:** App Store page content.
- **Technical summary:** Fastlane configuration and text files.
- **Evidence:** `fastlane/metadata/en-US/release_notes.txt`.
- **Not shipped / caveats:** None.
- **Public-safe wording:** "Fastlane configurations."

---

## 79. StoreKit testing resources
- **Status:** `RESOURCE_ONLY`
- **User-facing summary:** Sandbox checkout testing.
- **Technical summary:** StoreKit config and testing harnesses.
- **Evidence:** `OpenIntelligence/Resources/StoreKit/StoreKitConfiguration.storekit`.
- **Not shipped / caveats:** None.
- **Public-safe wording:** "StoreKit sandbox test files."

---

## 80. App icons/assets
- **Status:** `RESOURCE_ONLY`
- **User-facing summary:** App design elements.
- **Technical summary:** Asset catalogs inside target resources.
- **Evidence:** `OpenIntelligence/Resources/Assets/Assets.xcassets`.
- **Not shipped / caveats:** None.
- **Public-safe wording:** "Standard design assets."

---

## 81. Entitlements/sandbox/network/privacy plist keys
- **Status:** `RESOURCE_ONLY`
- **User-facing summary:** Sandbox security profiles.
- **Technical summary:** Entitlements and plist definitions.
- **Evidence:** `OpenIntelligence/OpenIntelligence.entitlements`.
- **Not shipped / caveats:** None.
- **Public-safe wording:** "Standard App Store entitlements."

---

## 82. Known placeholders/stubs
- **Status:** `SCAFFOLDED`
- **User-facing summary:** Planned features.
- **Technical summary:** CoreAI execution layer and iCloud sync stubs.
- **Evidence:** `OpenIntelligence/Services/AIPlatform/CoreAI/CoreAIExecutionBackend.swift`.
- **Not shipped / caveats:** None.
- **Public-safe wording:** "Identified experimental modules."

---

## 83. Known deprecated/historical paths
- **Status:** `DEPRECATED`
- **User-facing summary:** Old features.
- **Technical summary:** Files with historical logs.
- **Evidence:** `Docs/USER_CHANGELOG.md`.
- **Not shipped / caveats:** None.
- **Public-safe wording:** "Archived log references."

---

## 84. Known unused candidates
- **Status:** `UNUSED_CANDIDATE`
- **User-facing summary:** None.
- **Technical summary:** Unused files like `test_extension.swift` not in Xcode compilation.
- **Evidence:** `test_extension.swift`.
- **Not shipped / caveats:** None.
- **Public-safe wording:** "Unused testing stubs."
"""
    with open(OUTPUT_PATH, 'w', encoding='utf-8') as f:
        f.write(content)
        
    print(f"Successfully wrote Component Reality Map to {OUTPUT_PATH}")

if __name__ == "__main__":
    main()
