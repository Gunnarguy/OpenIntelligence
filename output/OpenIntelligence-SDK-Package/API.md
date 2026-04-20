# API

## Proposed Public Surface

The first public API should stay intentionally small.

```swift
public enum OIAvailabilityState {
    case available
    case simulatorUnsupported
    case unsupportedDevice
    case appleIntelligenceDisabled
    case modelPreparing
}

public enum OIExecutionContext {
    case automatic
    case onDeviceOnly
    case preferCloud
    case cloudOnly
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

public struct OIIngestResult {
    public var importedDocuments: Int
    public var producedChunks: Int
    public var warnings: [String]
}

public struct OIQueryRequest {
    public var question: String
    public var libraryID: String?
}

public struct OICitation {
    public var source: String
    public var page: Int?
    public var quote: String?
}

public struct OIQueryResult {
    public var answer: String
    public var citations: [OICitation]
    public var confidence: Float
    public var abstained: Bool
    public var warnings: [String]
}

public final class OIEngine {
    public static func availability() -> OIAvailabilityState
    public init(configuration: OIEngineConfiguration) async throws
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

    print("Imported \(ingestResult.importedDocuments) documents")

    let queryResult = try await engine.query(
        OIQueryRequest(question: "What happens if the strap is not removed?", libraryName: "Support Docs")
    )

    print(queryResult.answer)
    print(queryResult.citations)
}
```

## Why This Surface

- It hides the internal pipeline.
- It is small enough to support as a commercial SDK.
- It exposes the two essential workflows: ingest and query.
- It exposes capability state without forcing the client to understand Foundation Models internals.

## Public Behavior Expectations

- `availability()` must fail explicitly on simulator and unsupported hardware.
- `ingest(_:)` must validate readable files and return warnings instead of silent partial success.
- `query(_:)` must prefer supported answers and clearly abstain on weak evidence.

## Current Status

This API is the recommended boundary.
The framework target now exists and builds, but XCFramework packaging and demo validation are still incomplete.

For tomorrow's buyer conversations, this means:

- you can demo the behavior now
- you can show the intended public API now
- you can hand off an evaluation XCFramework now
- you should describe the module-stable binary SDK as in-progress, not finished

For external sharing, include this file in the curated buyer bundle rather than zipping the entire SDK packet folder.
