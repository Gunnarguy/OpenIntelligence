# How Another App Uses The Engine

## First: This Is Not A Hosted API

There is no hosted web API in this packet.

This file is about the small set of engine entry points another Apple app would use if it embedded the engine locally.

In plain English, another app would:

1. check whether the engine is available on the device
2. create the engine
3. create or select a library
4. import files into it
5. ask a question
6. get back an answer with citations

## Current Engine Entry Points

The staged engine entry points in `OpenIntelligence/SDK/OpenIntelligenceEngine.swift` are intentionally small.

This is the current evaluation boundary, not proof of a finished enterprise SDK contract.

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

public struct OILibrary: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let documentCount: Int
    public let chunkCount: Int
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
    public func listLibraries() -> [OILibrary]
    public func createLibrary(name: String) throws -> OILibrary
    public func deleteLibrary(id: UUID) throws
    public func ingest(_ request: OIIngestRequest) async throws -> OIIngestResult
    public func ingest(_ request: OIIngestRequest, into libraryID: UUID) async throws -> OIIngestResult
    public func query(_ request: OIQueryRequest) async throws -> OIQueryResult
    public func query(_ request: OIQueryRequest, in libraryID: UUID) async throws -> OIQueryResult
}
```

## Example Of How A Buyer App Would Use It

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

    let library = try engine.createLibrary(name: "Support Docs")

    let ingestResult = try await engine.ingest(OIIngestRequest(urls: documentURLs), into: library.id)

    let queryResult = try await engine.query(OIQueryRequest(question: "What happens if the strap is not removed?", topK: 6), in: library.id)

    print(ingestResult.importedDocuments)
    print(queryResult.answer)
    print(queryResult.citations)
}
```

## Minimum Integration Contract

Today, the practical source-SDK integration contract is:

- add the repo root as a Swift package dependency
- link the `OpenIntelligenceEngine` product into your app target
- call the public engine facade from a `@MainActor` context
- create or select a library explicitly
- ingest document URLs explicitly
- query a specific library explicitly when you want predictable isolation

If you want a concrete reference implementation, use `Samples/SourceSDKHost/` in the private engine repo.

For simulator-safe contract checks that do not depend on live Apple Intelligence generation, use `Samples/SourceSDKHost/run_smoke_tests.sh`.

## Current Caveats

- The source SDK now has a root `Package.swift` and a consumer sample under `Samples/SourceSDKHost/`, but that is still productization progress rather than finished no-guidance completion.
- `storageURL` lets the caller redirect the base storage location, but the current facade still wraps app-era internals.
- `allowPrivateCloudCompute` is a permission/control flag, not proof of direct server-model access or larger public context windows.
- `availability()` should be treated as a practical runtime check, not a full packaging-readiness statement.
- This boundary is good enough for evaluation. It is not yet the final long-term SDK contract.
