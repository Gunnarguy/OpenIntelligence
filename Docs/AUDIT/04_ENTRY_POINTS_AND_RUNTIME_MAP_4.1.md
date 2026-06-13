# Phase 4: Runtime Entry Points Mapping - OpenIntelligence v4.1

This document maps all application launch, UI navigation, background, deep link, and pipeline execution entry points. Verified for OpenIntelligence v4.1.

## 1. Primary Entry Points

| Entry Point | File | User-facing? | Target / Config | Description |
|---|---|---|---|---|
| **App Launch (`@main`)** | `OpenIntelligence/App/OpenIntelligenceApp.swift` | Yes | `OpenIntelligence` | Performs startup checks (debug harnesses, TipKit, background task registration), and sets `ContentView()` as the root scene. |
| **Live Activities (`@main`)** | `OpenIntelligenceLiveActivities/OpenIntelligenceLiveActivitiesBundle.swift` | Yes (Widget) | `OpenIntelligenceLiveActivities` | Root of the widget extension displaying live activities for ingestion status in iOS 17+. |
| **Root UI (`ContentView`)** | `OpenIntelligence/App/ContentView.swift` | Yes | `OpenIntelligence` | App container featuring 5 tabs, iCloud sync hooks, deep-linking URL routing, and TipKit settings. |
| **Chat Tab** | `OpenIntelligence/Features/Chat/Conversation/ChatScreen.swift` | Yes | `OpenIntelligence` | Tab 1: Handles chat interactions, messaging inputs, suggested questions, and reasoning streams. |
| **Documents Tab** | `OpenIntelligence/Features/Documents/Library/DocumentLibraryView.swift` | Yes | `OpenIntelligence` | Tab 2: Document manager showing workspaces, document ingestion list, quota usage, and detail views. |
| **Atlas Tab** | `OpenIntelligence/Features/Telemetry/Visualizations/AdaptiveVisualizationsView.swift` | Yes | `OpenIntelligence` | Tab 3: Interactive 2D/3D visualizations of document projections and chunks in vector space. |
| **Database Tab** | `OpenIntelligence/Features/Database/DatabaseDashboardView.swift` | Yes | `OpenIntelligence` | Tab 4: Admin HUD displaying SQLite FTS tables, vector database statistics, and raw index entries. |
| **Settings Tab** | `OpenIntelligence/Features/Settings/SettingsView.swift` | Yes | `OpenIntelligence` | Tab 5: Configuration settings for local model paths, Private Cloud Compute consents, billing options, and themes. |
| **Spotlight Integration** | `OpenIntelligence/Services/Infrastructure/Background/SpotlightIndexService.swift` | Yes | `OpenIntelligence` & `OpenIntelligenceEngine` | Indexes document files at the passage level so search results appear in system Spotlight. Tap on a Spotlight result enters via `onContinueUserActivity` in `ContentView` and routes to documents. |
| **Deep Link Handler** | `OpenIntelligence/App/ContentView.swift` (line 351) | Yes (Implicit) | `OpenIntelligence` | Listens to custom deep link URLs (e.g. `openintelligence://documents/ingestion` or `openintelligence://chat`) and switches tabs. |
| **Debug Validation Harness** | `OpenIntelligence/App/DebugRAGValidationHarness.swift` | No (Dev/Debug) | `OpenIntelligence` | Compiles in Debug mode only; triggers automated execution of RAG verification cases on launch. |
| **AppIntents Integration** | `OpenIntelligence/Services/Agentic/RAGAppIntents.swift` | Yes (Voice/Siri) | `OpenIntelligence` | Registers intents (`QueryKnowledgeIntent`, etc.) making libraries queryable via Siri and Shortcuts. |

## 2. Ingestion Pipeline Runtime Flow
```
[User Selects File]
      ↓
[DocumentLibraryView / DocumentPicker]
      ↓ (triggers)
[DocumentProcessor.shared.ingest()]
      ↓
[PageComplexityAnalyzer] (Skips OCR for digital text pages / Scales OCR dynamically)
      ↓
[VisionOCRProcessor / Text Extraction]
      ↓
[SemanticChunker] (Chunking based on natural sentences & structural headers)
      ↓
[EmbeddingService / CoreAISentenceEmbeddingProvider] (Metal/GPU GPU-driven vector generation)
      ↓ (Batch cosine calculations)
[VecturaVectorDatabase / SQLiteFullTextService] (Atomic storage writes)
      ↓ (Triggers background re-indexing)
[SpotlightIndexService] (Register document in system index)
```

## 3. Query Execution Runtime Flow
```
[User submits Query in ChatComposer]
      ↓
[ChatScreen / RAGService]
      ↓
[QueryComplexityAnalyzer] (Evaluate prompt length and difficulty)
      ↓
[FoundationModelRoutePolicy] (Standard -> Local 4K model vs. Deep Think -> PCC 32K model)
      ↓
[QueryRewriter / HyDEService] (Perform query enhancement in memory)
      ↓
[HybridSearchService] (Runs Cosine Similarity vector search & SQLite FTS keywords)
      ↓
[ContextPackingService] (Consolidate overlapping chunks & parent expansions)
      ↓
[VerificationGateService] (Groundedness, contradiction, and numeric consistency gates)
      ↓
[LLMService / PCC Execution] (Structured JSON answer synthesis)
      ↓
[GroundedAnswerView] (Fades in cited answer card, unified metrics, and source chips)
```

## 4. Background Task Registrations
The app registers the following background tasks in `OpenIntelligenceApp.swift` (under iOS 26+):
- `"com.openintelligence.continued-ingestion"`: Continued processing of files when the app backgrounds.
- `"com.openintelligence.continued-query"`: Allows query and answer generation to complete in the background.
- `"com.openintelligence.index-maintenance"`: Periodic background compaction of the vector database and database defragmentation.
- `"com.openintelligence.spotlight-reindex"`: Synchronizes local documents index with system search database.
- `"com.openintelligence.app-refresh"`: Background cache warming and local model pre-check.
