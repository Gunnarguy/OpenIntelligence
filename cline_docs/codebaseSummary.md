# Codebase Summary – OpenIntelligence

Last updated: 2025-11-01

## Key Components and Their Interactions
- Views
  - ChatScreen (ChatV2): orchestrates chat flow, streaming, overlays; triggers RAGService.query
  - MessageListView, MessageRowView, MessageBubbleView, SourceChipsView
  - StageProgressBar, PipelineOverlayView, LiveCountersStrip, RetrievalSourcesTray, TokenCadenceView, EventToasts (ToastStackView)
  - SettingsView: model selection, PCC controls, fallbacks, pipeline visualization
  - Diagnostics: CoreValidationView, TelemetryDashboardView for testing and telemetry
- Services
  - RAGService: orchestrates the RAG pipeline (ingestion, retrieval, generation)
  - LLMService implementations:
    - AppleFoundationLLMService (iOS 26+ FoundationModels with PCC)
    - AppleChatGPTExtensionService (iOS 18.1+ AppIntents; entitlement-dependent)
    - OpenAILLMService (direct HTTP API to OpenAI)
    - OnDeviceAnalysisService (extractive QA fallback using NaturalLanguage)
    - CoreMLLLMService (scaffold for custom Core ML LLMs)
    - MLXLocalLLMService (new, macOS-only HTTP bridge to local mlx-lm)
  - Embeddings (new abstraction)
    - EmbeddingService: delegates to EmbeddingProvider
    - EmbeddingProvider protocol: pluggable backends
    - NLEmbeddingProvider: 512-dim word-avg (parity with prior behavior)
    - CoreMLSentenceEmbeddingProvider: scaffold for sentence encoders (384/768)
    - AppleFMEmbeddingProvider: scaffold present (awaiting public embeddings API; currently reports unavailable)
  - RAGEngine: background actor for MMR, context assembly, re-ranking helpers
  - HybridSearchService, VectorDatabase, DocumentProcessor, QueryEnhancementService, SemanticChunker: indexing, retrieval, chunking infrastructure
- Models
  - LLMModelType: enumerates selectable backends (now includes mlxLocal, coreMLLocal)
  - InferenceConfig, RAGQuery, DocumentChunk, RetrievedChunk: data structures for pipeline state

## Data Flow
1. Ingestion
   - DocumentProcessor parses documents (PDFKit, Vision OCR if needed)
   - SemanticChunker creates chunks with metadata
   - EmbeddingService generates embeddings via provider; stored in VectorDatabase
2. Query
   - ChatScreen calls RAGService.query(question, config)
   - Query enhancement (optional), embed query, hybrid search (vector + BM25), re-ranking (RRF/MMR via RAGEngine), context assembly
3. Generation
   - LLMService chosen by user preferences and availability (Apple FM → ChatGPT Ext → OpenAI → OnDeviceAnalysis; now MLX/ Core ML are options)
   - Apple FM may run on-device or via PCC based on complexity; OpenAI uses HTTPS; MLX local calls a local server on macOS
4. Response
   - Telemetry planned for tokens/sec, TTFT, execution location; UI badges to indicate privacy/execution path

## External Dependencies
- Apple frameworks: FoundationModels (iOS 26+), AppIntents, NaturalLanguage, Vision/VisionKit (planned upgrades), CoreML, PDFKit, AVFoundation/Speech (planned), SwiftUI
- OpenAI API (HTTPS) when user-configured
- MLX (macOS): local Python server `mlx_lm.server` exposed with OpenAI-style endpoints

## Recent Significant Changes
- Added EmbeddingProvider abstraction and NLEmbeddingProvider to preserve behavior and enable future sentence encoders
- Refactored EmbeddingService to delegate to provider (no public API break)
- Added CoreMLSentenceEmbeddingProvider scaffold (tokenization/IO TBD)
- Added AppleFMEmbeddingProvider scaffold (awaiting public embeddings API; currently reports unavailable)
- Implemented MLXLocalLLMService (macOS-only local server bridge; OpenAI-compatible request body)
- Extended LLMModelType with `.mlxLocal` and `.coreMLLocal`
- Updated SettingsView to include MLX/Core ML options and corresponding pipeline stages
- ChatV2 UI overhaul:
  - StageProgressBar with per-stage elapsed timers and shimmer
  - PipelineOverlayView behind the message list with animated flow
  - LiveCountersStrip showing TTFT, tokens, tok/s, retrieved chunks
  - RetrievalSourcesTray with live source chips and details sheet
  - TokenCadenceView integrated with streaming row next to TypingIndicator
  - EventToasts (ToastStackView) for stage milestones and TTFT
  - ExecutionBadge indicating On-Device vs PCC via TTFT heuristic
  - Legacy ChatView removed; V2 unified across app (2025-10-29)
  - SemanticChunker: added language detection, lemma-based keyword extraction, and runtime diagnostics; posts Notification.Name.semanticChunkerDiagnosticsUpdated; new NLChunkingDiagnosticsView surfaced in Developer & Diagnostics hub
  - AppleFoundationLLMService: emits TelemetryCenter events on generation start/complete; enforces PCC-block preference by aborting PCC stream and falling back to On‑Device Analysis when user forces on-device/no-PCC

## User Feedback Integration and Impact on Development
- Request: adopt latest Apple 2025 AI stack and avoid deprecated paths; ensure on-device-first, PCC fallback, local open-models (MLX) and Core ML support
- Impact:
  - Provided new model options and routing in Settings
  - Preserved privacy-first design while enabling larger local models (MLX) on macOS
  - Established embeddings abstraction to support better multilingual sentence encoders and future providers

## Notes / Next Steps
- Core ML sentence encoder: implement tokenizer and IO mapping for one known model
- CoreMLLLMService: implement TokenizerAdapter and end-to-end generation for at least one small LLM
- TelemetryCenter: record backendUsed, executionLocation, TTFT, tokens/sec, toolCallsMade
- WritingTools: integrate into composer with fallbacks
- VisionKit scanning and improved OCR settings
- UI: show execution-location badges (📱/☁️/🖥️/🔑) and “why unavailable” diagnostics

---

## Update: 2025-10-31 – Settings Modernization (SurfaceCard + Platform Gating + GGUF iOS)

### Settings Modernization Summary

- Introduced card-based Settings UI using shared primitives:
  - SurfaceCard, SectionHeader, SectionFooter in Shared/DesignSystem/SurfaceCard.swift
- Converted Settings-related screens to the new design system:
  - SettingsView, BackendHealthDiagnosticsView, DeveloperDiagnosticsHubView, DeveloperSettingsView, ContainerScopingSelfTestsView, AboutView
- iOS-first local model path (GGUF via embedded llama.cpp – stubbed):
  - New model option: “GGUF Local (iOS)” in SettingsView
  - File import flow: .fileImporter copies selected .gguf to Documents/Models and persists path/name
  - Runtime wiring: RAGService instantiates LlamaCPPiOSLLMService.fromDefaults() when selected
  - Diagnostics: BackendHealthDiagnosticsView adds “Verify Model File” and “Run Smoke Test” actions (stub backend echoes to confirm wiring)
- Consistency and polish:
  - “Model Flow” visualization converted to a SurfaceCard section
  - iOS pickers standardized to .navigationLink style (Model selection, Fallbacks, OpenAI model)
  - iOS gating: normalizeSelectedModelForPlatform() prevents macOS-only selections on iOS
  - Central “Developer & Diagnostics” tile from Settings routes to the consolidated hub

### Settings Modernization Files Touched

- OpenIntelligence/Views/Settings/SettingsView.swift
- OpenIntelligence/Views/Settings/BackendHealthDiagnosticsView.swift
- OpenIntelligence/Views/Settings/DeveloperDiagnosticsHubView.swift
- OpenIntelligence/Views/Settings/DeveloperSettingsView.swift
- OpenIntelligence/Views/Settings/ContainerScopingSelfTestsView.swift
- OpenIntelligence/Views/Settings/AboutView.swift
- OpenIntelligence/Shared/DesignSystem/SurfaceCard.swift

### iOS GGUF Local Path (current status)

- Service scaffold: OpenIntelligence/Services/LlamaCPPiOSLLMService.swift
- Selection + import: SettingsView.ggufConfigurationSection
- Diagnostics: BackendHealthDiagnosticsView.ggufCard (verify file + smoke test)
- Note: Backend is a stub pending embedded llama.cpp runtime; UI and persistence flows are complete.

### Settings Modernization Pending Tasks

- Visual QA sweep across Settings: spacing, icon weight/size, dark mode, Dynamic Type
- Documentation updates and screenshots once embedded runtime lands
- Optional: message-level badges reflecting backend/execution path and per-message container

---

## Update: 2025-11-01 – Hugging Face Integration for Model Downloads

### Hugging Face Summary

- Added first-class Hugging Face support to the downloader: list repo files (GGUF, optional Core ML), resolve and download with background URLSession, pause/resume, Wi‑Fi‑only, ETA/speed, optional sha256 verification, and ModelRegistry install.

### Hugging Face Key Changes

- Services/ModelDownloadService.swift
  - hf:// scheme parsing (hf://owner/repo[:revision]/path)
  - Resolve via <https://huggingface.co/{owner}/{repo}/resolve/{revision}/{path}?download=true>
  - Repo listing via /api/models/{owner}/{repo}?expand[]=siblings; filter .gguf (+ optional Core ML artifacts)
  - Authorization header when @AppStorage("hfToken") present
  - Error mapping for gated/invalid/rate-limited repos (403/404/429)
  - Reuses background URLSession; telemetry across list/resolve/start/progress/installed/failed
- Views/ModelManagement/ModelManagerView.swift
  - “Add from Hugging Face” sheet: owner/repo(+revision), include Core ML toggle, file list (size + sha256 indicator), Download
- Views/Settings/SettingsView.swift
  - Models & Downloads card: added SecureField for Hugging Face token (hfToken)

### Hugging Face Build Notes

- macOS Debug build succeeded.

---

## Update: 2025-11-01 – Developer Settings Makeover (Native Form)

### Developer Settings Summary

- Simplified DeveloperSettingsView to a native Form with compact Sections; removed custom card chrome to “make it easy.”

### Developer Settings Key Changes

- Views/Settings/DeveloperSettingsView.swift
  - Sections: Console Logging Level (Picker + contextual InfoBox), Logging Categories toggles, Presets (Production/Development/Debug), System Logs note, Current Configuration summary
  - applyLoggingSettings() updates LoggingConfiguration.currentLevel and enabledCategories on changes/presets

### Notes

- Supersedes the earlier “Settings Modernization” note that listed DeveloperSettingsView under card-based screens; this view is now native Form for clarity and minimalism.
- macOS Debug build succeeded; app launches and Developer & Diagnostics hub navigation to Developer Settings remains intact.
