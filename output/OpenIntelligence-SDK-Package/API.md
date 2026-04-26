# API

## Current Public Facade

The staged public facade in `OpenIntelligence/SDK/OpenIntelligenceEngine.swift` is intentionally small.

It is the current evaluation boundary, not proof of a finished enterprise SDK contract.

```swift
public enum OIAvailabilityState: Equatable, Sendable {
    case available
    case simulatorUnsupported
    case unsupportedDevice
    case appleIntelligenceDisabled
    case modelPreparing
    case unavailable(String)
}

public enum OIExecutionContext: String, Sendable {
    case automatic
    case onDeviceOnly
    case preferCloud
    case cloudOnly
}

public struct OIEngineConfiguration: Sendable {
    public var storageURL: URL?
    public var allowPrivateCloudCompute: Bool
    public var executionContext: OIExecutionContext
}

public struct OIIngestRequest: Sendable {
    public var urls: [URL]
    public var libraryName: String?
}

public struct OIIngestResult: Sendable {
    public let importedDocuments: Int
    public let failedDocuments: Int
    public let totalDocuments: Int
    public let totalLibraryDocuments: Int
    public let totalLibraryChunks: Int
    public let warnings: [String]
}

public struct OIQueryRequest: Sendable {
    public var question: String
    public var libraryName: String?
    public var topK: Int
}

public struct OICitation: Sendable {
    public let source: String
    public let page: Int?
    public let quote: String?
}

public struct OIQueryResult: Sendable {
    public let answer: String
    public let citations: [OICitation]
    public let confidence: Float
    public let abstained: Bool
    public let warnings: [String]
    public let modelName: String
}

@MainActor
public final class OIEngine {
    public static func availability() -> OIAvailabilityState
    public init(configuration: OIEngineConfiguration = OIEngineConfiguration())
    public func ingest(_ request: OIIngestRequest) async throws -> OIIngestResult
    public func query(_ request: OIQueryRequest) async throws -> OIQueryResult
}
```

## Example Integration

```swift
import OpenIntelligenceEngine

@MainActor
func runDemo(documentURLs: [URL]) async throws {
    let engine = OIEngine(
        configuration: OIEngineConfiguration(
            storageURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            allowPrivateCloudCompute: true,
            executionContext: .automatic
        )
    )

    let ingestResult = try await engine.ingest(
        OIIngestRequest(urls: documentURLs, libraryName: "Support Docs")
    )

    let queryResult = try await engine.query(
        OIQueryRequest(question: "What happens if the strap is not removed?", libraryName: "Support Docs", topK: 6)
    )

    print(ingestResult.importedDocuments)
    print(queryResult.answer)
    print(queryResult.citations)
}
```

## Current Caveats

- `storageURL` lets the caller redirect the base storage location, but the current facade still wraps app-era internals.
- `allowPrivateCloudCompute` is a permission/control flag, not proof of direct server-model access or larger public context windows.
- `availability()` should be treated as a practical runtime check, not a full packaging-readiness statement.
- This boundary is good enough for evaluation. It is not yet the final long-term SDK contract.
