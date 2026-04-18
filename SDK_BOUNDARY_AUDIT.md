# SDK Boundary Audit

This document defines the smallest credible boundary for turning the current app into a closed-source Apple SDK.
It is written for internal productization work, not for buyers.

## Executive Verdict

The codebase contains a real sellable engine, but it is not yet packaged as a sellable SDK.

The fastest credible SDK boundary is:

- document ingestion
- chunking and indexing
- retrieval and reranking
- grounded answer generation
- source-only verification
- capability checks for Apple Intelligence availability

The wrong first SDK boundary is:

- the full app
- billing
- chat UI
- onboarding
- diagnostics UI
- telemetry dashboards
- StoreKit
- Tips
- Spotlight/background app shell behavior

## Current Project Shape

Current state observed from the workspace:

- two native Xcode targets:
  - `OpenIntelligence`
  - `OpenIntelligenceEngine`
- one filesystem-synchronized source root: `OpenIntelligence/`
- one local Swift package dependency tree: `OpenIntelligence/swift-transformers`
- bundled model resources under `OpenIntelligence/Resources/MLModels`
- dedicated framework target exists for `OpenIntelligenceEngine`
- framework target build validated for `generic/platform=iOS Simulator`
- no existing XCFramework output

This means the engine boundary now compiles as a framework target, but the binary packaging step is still incomplete.

## Navigation Map

If you are trying to understand the SDK path quickly, start here:

- public SDK entry point:
  - `OpenIntelligence/SDK/OpenIntelligenceEngine.swift`
- framework-safe runtime path and bundle lookup:
  - `OpenIntelligence/Core/Support/OpenIntelligenceRuntimePaths.swift`
- current framework target definition:
  - `OpenIntelligence.xcodeproj/project.pbxproj`
- packaging scripts:
  - `scripts/build_engine_xcframework.sh`
  - `scripts/validate_sdk_package.sh`
- deliverable docs:
  - `output/OpenIntelligence-SDK-Package/README.md`
  - `output/OpenIntelligence-SDK-Package/BUILD_NOTES.md`
  - `output/OpenIntelligence-SDK-Package/PACKAGE_SUMMARY.md`

## Recommended SDK Boundary

### Include In SDK

Core engine surface:

- `OpenIntelligence/Core/Protocols/EngineInterfaces.swift`
- `OpenIntelligence/Core/Models/DocumentChunk.swift`
- `OpenIntelligence/Core/Models/RAGQuery.swift`
- `OpenIntelligence/Core/Models/StructuredAnswer.swift`
- `OpenIntelligence/Core/Models/RAGStructuredResponse.swift`
- `OpenIntelligence/Core/Models/RAGQualityMode.swift`
- request/response types derived from `LLMModel.swift` inference config concepts

Document ingestion and parsing:

- `OpenIntelligence/Services/Document/Processing/*`
- `OpenIntelligence/Services/Document/Chunking/*`
- `OpenIntelligence/Services/Document/Analysis/DocumentSummaryService.swift`
- `OpenIntelligence/Services/Document/Analysis/EntityIndexService.swift`
- `OpenIntelligence/Services/Document/Analysis/SpatialDocumentAnalyzer.swift`
- `OpenIntelligence/Services/Document/Analysis/SpecificationDetector.swift`

Embeddings and retrieval:

- `OpenIntelligence/Services/Embedding/*`
- `OpenIntelligence/Services/Storage/SQLiteFullTextService.swift`
- `OpenIntelligence/Services/Storage/FullTextStorageService.swift`
- `OpenIntelligence/Services/VectorStore/*`
- `OpenIntelligence/Services/RAG/Retrieval/*`
- `OpenIntelligence/Services/RAG/Extraction/*`
- `OpenIntelligence/Services/RAG/Orchestration/RAGEngine.swift`
- `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift`
- `OpenIntelligence/Services/RAG/Orchestration/RAGService+KnowledgeRetrievalEngine.swift`

Answer policy and safety:

- `OpenIntelligence/Services/Query/Analysis/GroundedAnswerPolicy.swift`
- `OpenIntelligence/Services/Query/Analysis/QueryComplexityAnalyzer.swift`
- `OpenIntelligence/Services/Query/Analysis/SpecificationExtractor.swift`
- `OpenIntelligence/Services/Query/Rewriting/*`
- `OpenIntelligence/Services/Query/Routing/*`
- `OpenIntelligence/Services/RAG/Safety/*`

Foundation Models integration:

- `OpenIntelligence/Services/LLM/LLMService.swift`
- selected support types from `OpenIntelligence/Core/Models/LLMModel.swift`

Capability/runtime checks:

- `OpenIntelligence/Services/Infrastructure/Monitoring/DeviceCapabilityService.swift`
- a narrowed availability facade derived from `SystemStateMonitor` rules where needed

### Keep Out Of SDK

App shell:

- `OpenIntelligence/App/*`
- `OpenIntelligence/Features/*`
- `OpenIntelligence/UI/*`

Commercialization and app-only services:

- `OpenIntelligence/Services/Billing/*`
- `OpenIntelligence/Services/Infrastructure/Tips/*`
- `OpenIntelligence/Services/Infrastructure/Background/*`
- `OpenIntelligence/Services/Infrastructure/Presentation/*`
- `OpenIntelligence/Services/Infrastructure/Integration/ImagePlaygroundService.swift`
- `OpenIntelligence/Services/Agentic/RAGAppIntents.swift`
- `OpenIntelligence/Services/Agentic/VisualIntelligenceIntents.swift`
- `OpenIntelligence/Services/Agentic/WritingToolsService.swift`

Internal-only operational tooling:

- diagnostics views
- telemetry dashboards
- fastlane metadata
- release copy files

## Required SDK Resources

These resources are required by the current engine implementation:

- `OpenIntelligence/Resources/MLModels/EmbeddingModel.mlpackage`
- `OpenIntelligence/Resources/MLModels/ReRankerModel.mlpackage`
- `OpenIntelligence/Resources/MLModels/embedding_vocab.json`
- `OpenIntelligence/Resources/MLModels/reranker_vocab.json`
- privacy manifest handling derived from `OpenIntelligence/Resources/PrivacyInfo.xcprivacy`

Potential future optional resources:

- `ExtractiveQAModel.mlmodelc` if the extractive path is reinstated as a real shipped dependency
- additional Core ML classification assets if image/document classification remains inside the SDK scope

## External Dependencies

Local package products currently linked by the app target:

- `Hub`
- `Tokenizers`
- `Transformers`

Apple frameworks directly used across the engine:

- `FoundationModels`
- `NaturalLanguage`
- `CoreML`
- `PDFKit`
- `Vision`
- `SQLite3`
- `Metal`
- `Accelerate`
- `Compression`
- `UniformTypeIdentifiers`

## Main Blockers To A Closed Binary SDK

### 1. Target Membership Cleanup

The framework target exists, but it was created from the same filesystem-synchronized source root as the app.
That makes the target boundary viable for compilation, but still too broad for commercial packaging.

Before sending this to startups, tighten target membership so the shipping framework does not accidentally include:

- `App/*`
- `Features/*`
- `UI/*`
- billing / diagnostics / onboarding-only surfaces

### 2. App-Owned Storage Assumptions

Storage services write into app support paths under the current app identity.
A framework needs either:

- caller-provided container URLs, or
- a clearly documented default storage contract

### 3. Shared Singleton Concentration

Many services use `static let shared`.
That increases coupling and makes multi-instance SDK use harder.

Most important examples:

- `SQLiteFullTextService`
- `RAGEngine`
- `VerificationGateService`
- `SourceOnlyAnswerService`
- `DeviceCapabilityService`

### 4. Main-Actor And UI-Telemetry Coupling

The engine still references:

- `@MainActor`
- telemetry reporters
- system monitors
- app-facing observable state

That is workable inside an app and noisy inside an SDK.

### 5. Public Type Surface Is Too App-Shaped

Current engine protocols are promising, but the concrete models are still app-oriented and too broad.

The SDK should expose a smaller public surface:

- `configure`
- `capabilities`
- `ingest`
- `query`

### 6. Artifact Validation Is Not Finished

The framework target builds, but the commercial packaging path is still incomplete:

- device and simulator archives have not both been validated
- final `OpenIntelligenceEngine.xcframework` is not yet in the deliverable folder
- sample binary integration has not yet been proven in a separate demo app

## Smallest Viable Public API

The first sellable API should look roughly like:

```swift
public enum OIAvailabilityState {
    case available
    case simulatorUnsupported
    case unsupportedDevice
    case appleIntelligenceDisabled
    case modelPreparing
}

public struct OIEngineConfiguration {
    public var storageURL: URL
    public var allowPrivateCloudCompute: Bool
    public var executionContext: OIExecutionContext
}

public struct OIIngestRequest {
    public var urls: [URL]
    public var libraryID: String?
}

public struct OIQueryRequest {
    public var question: String
    public var libraryID: String?
}

public final class OIEngine {
    public static func availability() -> OIAvailabilityState
    public init(configuration: OIEngineConfiguration) async throws
    public func ingest(_ request: OIIngestRequest) async throws -> OIIngestResult
    public func query(_ request: OIQueryRequest) async throws -> OIQueryResult
}
```

That is enough to sell and integrate.

## Honest Timeline Read

### Could Be Ready In A Few Focused Days If Scope Stays Narrow

- create framework target
- move resource loading off `Bundle.main`
- define public API wrapper
- exclude UI/app-only services
- produce XCFramework
- build tiny demo app

### Not Ready In A Few Days If Scope Expands To "The Whole App Brain"

- full agentic layer
- all diagnostics
- all telemetry
- all image and multimodal extras
- all app conveniences and system integrations

## Final Boundary Recommendation

Package a first SDK around:

- private document ingestion
- grounded QA over ingested libraries
- Apple Intelligence availability handling
- source-backed answer payloads

Do not package:

- app UI
- billing
- onboarding
- diagnostics UX
- app-specific telemetry and background services

## Current Readiness

Current repo status for a sealed SDK:

- engine logic exists: yes
- coherent extraction boundary exists: yes
- public API exists: partially
- framework target exists: no
- XCFramework build path exists: no
- demo app using packaged binary exists: no
- buyer-ready binary deliverable exists: no

Verdict:

- conceptually productizable: yes
- actually ready to send as a closed-source SDK today: no
