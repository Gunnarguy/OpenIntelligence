import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

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

    nonisolated public init(
        storageURL: URL? = nil,
        allowPrivateCloudCompute: Bool = true,
        executionContext: OIExecutionContext = .automatic
    ) {
        self.storageURL = storageURL
        self.allowPrivateCloudCompute = allowPrivateCloudCompute
        self.executionContext = executionContext
    }
}

public struct OILibrary: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let documentCount: Int
    public let chunkCount: Int

    nonisolated public init(
        id: UUID,
        name: String,
        documentCount: Int,
        chunkCount: Int
    ) {
        self.id = id
        self.name = name
        self.documentCount = documentCount
        self.chunkCount = chunkCount
    }
}

public struct OIDocument: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let filename: String
    public let addedAt: Date
    public let chunkCount: Int
    public let libraryID: UUID?
    public let contentType: String

    nonisolated public init(
        id: UUID,
        filename: String,
        addedAt: Date,
        chunkCount: Int,
        libraryID: UUID?,
        contentType: String
    ) {
        self.id = id
        self.filename = filename
        self.addedAt = addedAt
        self.chunkCount = chunkCount
        self.libraryID = libraryID
        self.contentType = contentType
    }
}

public struct OIIngestRequest: Sendable {
    public var urls: [URL]
    public var libraryName: String?

    nonisolated public init(urls: [URL], libraryName: String? = nil) {
        self.urls = urls
        self.libraryName = libraryName
    }
}

public struct OIIngestResult: Sendable {
    public let importedDocuments: Int
    public let failedDocuments: Int
    public let totalDocuments: Int
    public let totalLibraryDocuments: Int
    public let totalLibraryChunks: Int
    public let warnings: [String]

    nonisolated public init(
        importedDocuments: Int,
        failedDocuments: Int,
        totalDocuments: Int,
        totalLibraryDocuments: Int,
        totalLibraryChunks: Int,
        warnings: [String]
    ) {
        self.importedDocuments = importedDocuments
        self.failedDocuments = failedDocuments
        self.totalDocuments = totalDocuments
        self.totalLibraryDocuments = totalLibraryDocuments
        self.totalLibraryChunks = totalLibraryChunks
        self.warnings = warnings
    }
}

public struct OIQueryRequest: Sendable {
    public var question: String
    public var libraryName: String?
    public var topK: Int

    nonisolated public init(
        question: String,
        libraryName: String? = nil,
        topK: Int = 6
    ) {
        self.question = question
        self.libraryName = libraryName
        self.topK = topK
    }
}

public struct OICitation: Sendable {
    public let source: String
    public let page: Int?
    public let quote: String?

    nonisolated public init(source: String, page: Int?, quote: String?) {
        self.source = source
        self.page = page
        self.quote = quote
    }
}

public struct OIQueryResult: Sendable {
    public let answer: String
    public let citations: [OICitation]
    public let confidence: Float
    public let abstained: Bool
    public let warnings: [String]
    public let modelName: String

    nonisolated public init(
        answer: String,
        citations: [OICitation],
        confidence: Float,
        abstained: Bool,
        warnings: [String],
        modelName: String
    ) {
        self.answer = answer
        self.citations = citations
        self.confidence = confidence
        self.abstained = abstained
        self.warnings = warnings
        self.modelName = modelName
    }
}

public enum OpenIntelligenceEngineError: LocalizedError, Sendable {
    case unavailable(OIAvailabilityState)
    case invalidRequest(String)

    public var errorDescription: String? {
        switch self {
        case let .unavailable(state):
            switch state {
            case .available:
                return nil
            case .simulatorUnsupported:
                return "Apple Intelligence is not available in the iOS Simulator."
            case .unsupportedDevice:
                return "This device does not support Apple Intelligence."
            case .appleIntelligenceDisabled:
                return "Apple Intelligence is disabled on this device."
            case .modelPreparing:
                return "Apple Intelligence is still preparing on this device."
            case let .unavailable(message):
                return message
            }
        case let .invalidRequest(message):
            return message
        }
    }
}

@MainActor
public final class OIEngine {
    private let configuration: OIEngineConfiguration
    private let containerService: ContainerService
    private var ragService: RAGService?

    public static func availability() -> OIAvailabilityState {
        #if targetEnvironment(simulator)
        return .simulatorUnsupported
        #else
        guard DeviceCapabilityService.shared.supportsAppleIntelligence else {
            return .unsupportedDevice
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case let .unavailable(reason):
                switch reason {
                case .deviceNotEligible:
                    return .unsupportedDevice
                case .appleIntelligenceNotEnabled:
                    return .appleIntelligenceDisabled
                case .modelNotReady:
                    return .modelPreparing
                @unknown default:
                    return .unavailable("Apple Intelligence is unavailable for an unknown reason.")
                }
            }
        }
        #endif

        return .available
        #endif
    }

    public init(configuration: OIEngineConfiguration = OIEngineConfiguration()) {
        self.configuration = configuration
        AppSupportPaths.configureBaseDir(configuration.storageURL)
        containerService = ContainerService()
    }

    public func listLibraries() -> [OILibrary] {
        containerService.containers.map(Self.makeLibrary)
    }

    @discardableResult
    public func createLibrary(name: String) throws -> OILibrary {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw OpenIntelligenceEngineError.invalidRequest("Library name must not be empty.")
        }

        if let existing = findContainer(named: trimmedName) {
            return Self.makeLibrary(from: existing)
        }

        let created = containerService.createContainer(name: trimmedName)
        return Self.makeLibrary(from: created)
    }

    public func deleteLibrary(id: UUID) throws {
        guard findContainer(id: id) != nil else {
            throw OpenIntelligenceEngineError.invalidRequest("Library not found.")
        }

        guard containerService.containers.count > 1 else {
            throw OpenIntelligenceEngineError.invalidRequest("At least one library must remain.")
        }

        containerService.deleteContainer(id: id)
    }

    public func listDocuments(in libraryID: UUID) throws -> [OIDocument] {
        guard let container = findContainer(id: libraryID) else {
            throw OpenIntelligenceEngineError.invalidRequest("Library not found.")
        }

        return resolvedRAGService()
            .documents
            .filter { $0.containerId == container.id }
            .sorted { lhs, rhs in
                if lhs.addedAt == rhs.addedAt {
                    return lhs.filename.localizedCaseInsensitiveCompare(rhs.filename) == .orderedAscending
                }
                return lhs.addedAt > rhs.addedAt
            }
            .map(Self.makeDocument)
    }

    public func removeDocument(id: UUID, from libraryID: UUID) async throws {
        guard findContainer(id: libraryID) != nil else {
            throw OpenIntelligenceEngineError.invalidRequest("Library not found.")
        }

        let ragService = resolvedRAGService()
        guard let document = ragService.documents.first(where: { $0.id == id && $0.containerId == libraryID }) else {
            throw OpenIntelligenceEngineError.invalidRequest("Document not found in the specified library.")
        }

        containerService.setActive(libraryID)
        try await ragService.removeDocument(document)
    }

    public func clearLibrary(id: UUID) async throws {
        guard let container = findContainer(id: id) else {
            throw OpenIntelligenceEngineError.invalidRequest("Library not found.")
        }

        containerService.setActive(container.id)
        try await resolvedRAGService().clearAllDocuments()
    }

    public func ingest(_ request: OIIngestRequest) async throws -> OIIngestResult {
        guard !request.urls.isEmpty else {
            throw OpenIntelligenceEngineError.invalidRequest("At least one document URL is required.")
        }

        let container = ensureContainer(named: request.libraryName)
        return try await ingest(request, into: container.id)
    }

    public func ingest(_ request: OIIngestRequest, into libraryID: UUID) async throws -> OIIngestResult {
        guard !request.urls.isEmpty else {
            throw OpenIntelligenceEngineError.invalidRequest("At least one document URL is required.")
        }

        guard let container = findContainer(id: libraryID) else {
            throw OpenIntelligenceEngineError.invalidRequest("Library not found.")
        }

        containerService.setActive(container.id)

        let result = await resolvedRAGService().ingestDocuments(request.urls, context: .userInitiated)
        let warnings: [String]
        if result.failureCount > 0 {
            warnings = ["\(result.failureCount) document(s) failed during ingestion."]
        } else {
            warnings = []
        }

        return OIIngestResult(
            importedDocuments: result.successCount,
            failedDocuments: result.failureCount,
            totalDocuments: result.totalCount,
            totalLibraryDocuments: containerService.documentCount(for: container.id),
            totalLibraryChunks: containerService.chunkCount(for: container.id),
            warnings: warnings
        )
    }

    public func query(_ request: OIQueryRequest) async throws -> OIQueryResult {
        let availability = Self.availability()
        if availability != .available {
            throw OpenIntelligenceEngineError.unavailable(availability)
        }

        let trimmedQuestion = request.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else {
            throw OpenIntelligenceEngineError.invalidRequest("Question must not be empty.")
        }

        let container = ensureContainer(named: request.libraryName)
        return try await query(request, in: container.id)
    }

    public func query(_ request: OIQueryRequest, in libraryID: UUID) async throws -> OIQueryResult {
        let availability = Self.availability()
        if availability != .available {
            throw OpenIntelligenceEngineError.unavailable(availability)
        }

        let trimmedQuestion = request.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else {
            throw OpenIntelligenceEngineError.invalidRequest("Question must not be empty.")
        }

        guard let container = findContainer(id: libraryID) else {
            throw OpenIntelligenceEngineError.invalidRequest("Library not found.")
        }

        containerService.setActive(container.id)

        var config = InferenceConfig.ragOptimized
        config.executionContext = mapExecutionContext(configuration.executionContext)
        config.allowPrivateCloudCompute = configuration.allowPrivateCloudCompute

        let response = try await resolvedRAGService().query(
            trimmedQuestion,
            topK: request.topK,
            config: config,
            containerId: container.id,
            streamHandler: nil
        )

        let citations = buildCitations(from: response)
        let abstained = response.structuredAnswer?.refuse ?? false
        let warnings = response.qualityWarnings + (response.structuredAnswer?.missing ?? [])

        return OIQueryResult(
            answer: response.generatedResponse,
            citations: citations,
            confidence: response.confidenceScore,
            abstained: abstained,
            warnings: Array(warnings.prefix(6)),
            modelName: response.metadata.modelUsed
        )
    }

    private func findContainer(id: UUID) -> KnowledgeContainer? {
        containerService.containers.first(where: { $0.id == id })
    }

    private func findContainer(named libraryName: String) -> KnowledgeContainer? {
        containerService.containers.first(where: {
            $0.name.compare(libraryName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        })
    }

    private func ensureContainer(named libraryName: String?) -> KnowledgeContainer {
        let trimmed = libraryName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return containerService.activeContainer ?? containerService.createContainer(name: "General")
        }

        if let existing = findContainer(named: trimmed) {
            return existing
        }

        return containerService.createContainer(name: trimmed)
    }

    private static func makeLibrary(from container: KnowledgeContainer) -> OILibrary {
        OILibrary(
            id: container.id,
            name: container.name,
            documentCount: container.totalDocuments,
            chunkCount: container.totalChunks
        )
    }

    private static func makeDocument(from document: Document) -> OIDocument {
        OIDocument(
            id: document.id,
            filename: document.filename,
            addedAt: document.addedAt,
            chunkCount: document.totalChunks,
            libraryID: document.containerId,
            contentType: document.contentType.rawValue.uppercased()
        )
    }

    private func resolvedRAGService() -> RAGService {
        if let ragService {
            return ragService
        }

        let ragService = RAGService(containerService: containerService)
        self.ragService = ragService
        return ragService
    }

    private func mapExecutionContext(_ value: OIExecutionContext) -> ExecutionContext {
        switch value {
        case .automatic:
            return .automatic
        case .onDeviceOnly:
            return .onDeviceOnly
        case .preferCloud:
            return .preferCloud
        case .cloudOnly:
            return .cloudOnly
        }
    }

    private func buildCitations(from response: RAGResponse) -> [OICitation] {
        if let structured = response.structuredAnswer, !structured.evidence.isEmpty {
            return structured.evidence.map {
                OICitation(
                    source: $0.documentName ?? "Unknown",
                    page: $0.page,
                    quote: $0.quote
                )
            }
        }

        return response.retrievedChunks.prefix(6).map {
            let quote = $0.chunk.parentContent ?? $0.chunk.content
            return OICitation(
                source: $0.sourceDocument,
                page: $0.pageNumber,
                quote: String(quote.prefix(240))
            )
        }
    }
}
