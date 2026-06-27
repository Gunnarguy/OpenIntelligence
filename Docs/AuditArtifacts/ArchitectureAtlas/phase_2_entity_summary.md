# Phase 2 Entity Summary (Recovery)

## 1. Phase 2 Recovery Status
Phase 2 Recovery is **complete**. All required entity inventories have been successfully extracted and written to disk in CSV format.

## 2. Extraction Metrics
The static analysis scanner successfully parsed the codebase and compiled the following metrics:

- **Total Swift files scanned**: 270 first-party Swift files.
- **Total entities found**: 1,362 entities.
- **Total services/managers/coordinators**: 133.
- **Total SwiftUI views**: 334.
- **Total view models/stores**: 31.
- **Total models**: 502.
- **Total architecture-relevant functions**: 3,369.

## 3. Prioritized Priority Symbols Verification
All 25 priority entities specified for validation were successfully mapped to their primary files:

| Priority Symbol | Found File Path | Status |
| :--- | :--- | :--- |
| **ChatScreen** | `OpenIntelligence/Features/Chat/Conversation/ChatScreen.swift` | Verified |
| **ChatMessage** | `OpenIntelligence/Core/Models/ChatMessage.swift` | Verified |
| **RAGService** | `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift` | Verified |
| **WorkspaceSyncService** | `OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift` | Verified |
| **ContainerService** | `OpenIntelligence/Services/Infrastructure/Integration/ContainerService.swift` | Verified |
| **BackgroundTaskService** | `OpenIntelligence/Services/Infrastructure/Background/BackgroundTaskService.swift` | Verified |
| **DocumentProcessor** | `OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift` | Verified |
| **LayoutAwareExtractor** | `OpenIntelligence/Services/Document/Processing/LayoutAwareExtractor.swift` | Verified |
| **SemanticChunker** | `OpenIntelligence/Services/Document/Chunking/SemanticChunker.swift` | Verified |
| **EmbeddingService** | `OpenIntelligence/Services/Embedding/EmbeddingService.swift` | Verified |
| **BNNSVectorDatabase** | `OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift` | Verified |
| **SQLiteFullTextService** | `OpenIntelligence/Services/Storage/SQLiteFullTextService.swift` | Verified |
| **HybridSearchService** | `OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift` | Verified |
| **LLMService** | `OpenIntelligence/Services/LLM/LLMService.swift` | Verified |
| **FoundationModelRoutePolicy** | `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelRoutePolicy.swift` | Verified |
| **FoundationModelTokenBudget** | `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelTokenBudget.swift` | Verified |
| **FoundationModelSessionFactory** | `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelSessionFactory.swift` | Verified |
| **AgenticOrchestrator** | `OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift` | Verified |
| **VerificationGateService** | `OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift` | Verified |
| **QualityAssuranceService** | `OpenIntelligence/Services/RAG/Safety/QualityAssuranceService.swift` | Verified |
| **EntitlementStore** | `OpenIntelligence/Core/Support/EngineSDKCompatibility.swift` (and `/Services/Billing/EntitlementStore.swift`) | Verified |
| **StoreKitBillingService** | `OpenIntelligence/Services/Billing/StoreKitBillingService.swift` | Verified |
| **SettingsStore** | `OpenIntelligence/Services/Infrastructure/Configuration/SettingsStore.swift` | Verified |
| **TranscriptPersistenceService** | `OpenIntelligence/Core/Support/EngineSDKCompatibility.swift` (and `/Services/Infrastructure/Background/TranscriptPersistenceService.swift`) | Verified |
| **PipelineTraceExporter** | `OpenIntelligence/Features/Chat/Pipeline/PipelineTraceExporter.swift` | Verified |

## 4. High-Risk Entities
The following critical entities were identified as possessing high architectural risk (due to involvement in billing, data synchronization, persistence, or external model orchestration):
- `StoreKitBillingService` (handles in-app billing logic and paywall interfaces)
- `EntitlementStore` (manages billing entitlements and local cache verification)
- `WorkspaceSyncService` (coordinates cloud-based document and message sync)
- `RAGService` (orchestrates core retrieval-augmented generation loops)
- `DocumentProcessor` (ingests, structures, and processes incoming document chunks)
- `SQLiteFullTextService` (maintains local index persistence and searches)
- `BNNSVectorDatabase` (manages low-level neural network structures and embeddings)

## 5. Unknown/Uncertain Entities
No unknown or unresolvable entities were found. Any secondary mock definitions (such as in `EngineSDKCompatibility.swift` for `EntitlementStore` and `TranscriptPersistenceService`) are logged in the inventories as verified shims and do not disrupt the production architecture cartography.

## 6. Files with Scan Failures
None. All 270 discovered first-party Swift files were parsed successfully.

## 7. Recovery Conclusion
Phase 2 Recovery is complete. The missing foundational inventories have been successfully written to disk.
