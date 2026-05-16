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

public enum OIQueryQualityMode: String, CaseIterable, Identifiable, Sendable {
    case standard
    case deepThink
    case maximum

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .standard:
            return "Standard"
        case .deepThink:
            return "Deep Think"
        case .maximum:
            return "Maximum"
        }
    }

    public var description: String {
        switch self {
        case .standard:
            return "Fastest grounded pass with verification and citations."
        case .deepThink:
            return "Multi-step reasoning with deeper retrieval before answering."
        case .maximum:
            return "Highest-effort reasoning with the broadest search and strictest verification."
        }
    }

    public var systemImage: String {
        switch self {
        case .standard:
            return "sparkles"
        case .deepThink:
            return "brain.head.profile"
        case .maximum:
            return "flame.fill"
        }
    }
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
    public var qualityMode: OIQueryQualityMode

    nonisolated public init(
        question: String,
        libraryName: String? = nil,
        topK: Int = 6,
        qualityMode: OIQueryQualityMode = .standard
    ) {
        self.question = question
        self.libraryName = libraryName
        self.topK = topK
        self.qualityMode = qualityMode
    }
}

public struct OIQueryStreamEvent: Sendable {
    public let text: String
    public let isFinal: Bool

    nonisolated public init(text: String, isFinal: Bool) {
        self.text = text
        self.isFinal = isFinal
    }
}

public typealias OIQueryStreamHandler = @Sendable (OIQueryStreamEvent) async -> Void

public struct OIQueryProgressEvent: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let phase: String
    public let title: String
    public let detail: String?
    public let systemImage: String
    public let isGenerating: Bool
    public let liveTokenCount: Int
    public let liveStepCount: Int
    public let liveConfidence: Float

    nonisolated public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        phase: String,
        title: String,
        detail: String? = nil,
        systemImage: String,
        isGenerating: Bool = false,
        liveTokenCount: Int = 0,
        liveStepCount: Int = 0,
        liveConfidence: Float = 0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.phase = phase
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.isGenerating = isGenerating
        self.liveTokenCount = liveTokenCount
        self.liveStepCount = liveStepCount
        self.liveConfidence = liveConfidence
    }
}

public typealias OIQueryProgressHandler = @Sendable (OIQueryProgressEvent) async -> Void

public struct OIQueryDiagnostics: Sendable {
    public let retrievedChunkCount: Int
    public let candidateChunkCount: Int?
    public let rerankedChunkCount: Int?
    public let contextChunkCount: Int?
    public let retrievalTime: TimeInterval
    public let generationTime: TimeInterval
    public let timeToFirstToken: TimeInterval?
    public let tokensGenerated: Int
    public let tokensPerSecond: Float?
    public let contextStrategy: String?
    public let featureFlags: [String]

    nonisolated public init(
        retrievedChunkCount: Int,
        candidateChunkCount: Int? = nil,
        rerankedChunkCount: Int? = nil,
        contextChunkCount: Int? = nil,
        retrievalTime: TimeInterval,
        generationTime: TimeInterval,
        timeToFirstToken: TimeInterval? = nil,
        tokensGenerated: Int,
        tokensPerSecond: Float? = nil,
        contextStrategy: String? = nil,
        featureFlags: [String] = []
    ) {
        self.retrievedChunkCount = retrievedChunkCount
        self.candidateChunkCount = candidateChunkCount
        self.rerankedChunkCount = rerankedChunkCount
        self.contextChunkCount = contextChunkCount
        self.retrievalTime = retrievalTime
        self.generationTime = generationTime
        self.timeToFirstToken = timeToFirstToken
        self.tokensGenerated = tokensGenerated
        self.tokensPerSecond = tokensPerSecond
        self.contextStrategy = contextStrategy
        self.featureFlags = featureFlags
    }

    nonisolated public static let empty = OIQueryDiagnostics(
        retrievedChunkCount: 0,
        retrievalTime: 0,
        generationTime: 0,
        tokensGenerated: 0
    )
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
    public let qualityMode: OIQueryQualityMode
    public let reasoningTrace: [String]
    public let diagnostics: OIQueryDiagnostics

    nonisolated public init(
        answer: String,
        citations: [OICitation],
        confidence: Float,
        abstained: Bool,
        warnings: [String],
        modelName: String,
        qualityMode: OIQueryQualityMode = .standard,
        reasoningTrace: [String] = [],
        diagnostics: OIQueryDiagnostics = .empty
    ) {
        self.answer = answer
        self.citations = citations
        self.confidence = confidence
        self.abstained = abstained
        self.warnings = warnings
        self.modelName = modelName
        self.qualityMode = qualityMode
        self.reasoningTrace = reasoningTrace
        self.diagnostics = diagnostics
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

        do {
            let created = try containerService.createContainer(name: trimmedName)
            return Self.makeLibrary(from: created)
        } catch let error as LibraryQuotaError {
            throw OpenIntelligenceEngineError.invalidRequest(error.errorDescription ?? "Library limit reached.")
        }
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

    public func cancelActiveQuery(resetSession: Bool = true) {
        ragService?.cancelActiveGeneration(resetSession: resetSession)
    }

    public func ingest(_ request: OIIngestRequest) async throws -> OIIngestResult {
        guard !request.urls.isEmpty else {
            throw OpenIntelligenceEngineError.invalidRequest("At least one document URL is required.")
        }

        let container = try ensureContainer(named: request.libraryName)
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

    public func query(
        _ request: OIQueryRequest,
        onStreamEvent streamHandler: OIQueryStreamHandler? = nil,
        onProgressEvent progressHandler: OIQueryProgressHandler? = nil
    ) async throws -> OIQueryResult {
        let availability = Self.availability()
        if availability != .available {
            throw OpenIntelligenceEngineError.unavailable(availability)
        }

        let trimmedQuestion = request.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else {
            throw OpenIntelligenceEngineError.invalidRequest("Question must not be empty.")
        }

        let container = try ensureContainer(named: request.libraryName)
        return try await query(
            request,
            in: container.id,
            onStreamEvent: streamHandler,
            onProgressEvent: progressHandler
        )
    }

    public func query(
        _ request: OIQueryRequest,
        in libraryID: UUID,
        onStreamEvent streamHandler: OIQueryStreamHandler? = nil,
        onProgressEvent progressHandler: OIQueryProgressHandler? = nil
    ) async throws -> OIQueryResult {
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

    let qualityMode = Self.mapQualityMode(request.qualityMode)

        var config = InferenceConfig.ragOptimized
        config.executionContext = mapExecutionContext(configuration.executionContext)
        config.allowPrivateCloudCompute = configuration.allowPrivateCloudCompute

        let llmStreamHandler: LLMStreamHandler?
        if let streamHandler {
            llmStreamHandler = { event in
                await streamHandler(OIQueryStreamEvent(text: event.text, isFinal: event.isFinal))
            }
        } else {
            llmStreamHandler = nil
        }

        let ragService = resolvedRAGService()
        let progressTask = makeProgressMonitor(
            for: ragService,
            handler: progressHandler,
            libraryName: container.name
        )
        defer { progressTask?.cancel() }

        let (response, auditSnapshot) = try await ragService.queryWithAudit(
            trimmedQuestion,
            topK: request.topK,
            config: config,
            containerId: container.id,
            qualityModeOverride: qualityMode,
            streamHandler: llmStreamHandler
        )

        let citations = buildCitations(from: response)
        let abstained = response.structuredAnswer?.refuse ?? false
        let warnings = response.qualityWarnings + (response.structuredAnswer?.missing ?? [])
        let resolvedQualityMode = Self.mapQualityModeName(response.metadata.qualityModeName) ?? request.qualityMode
        let diagnostics = OIQueryDiagnostics(
            retrievedChunkCount: response.retrievedChunks.count,
            candidateChunkCount: auditSnapshot?.candidatesCount,
            rerankedChunkCount: auditSnapshot?.rerankedCount,
            contextChunkCount: auditSnapshot?.contextChunksUsed,
            retrievalTime: response.metadata.retrievalTime,
            generationTime: response.metadata.totalGenerationTime,
            timeToFirstToken: response.metadata.timeToFirstToken,
            tokensGenerated: response.metadata.tokensGenerated,
            tokensPerSecond: response.metadata.tokensPerSecond,
            contextStrategy: auditSnapshot?.contextStrategy,
            featureFlags: auditSnapshot?.featureFlags.enabledFeatures ?? []
        )

        if let progressHandler {
            await progressHandler(
                OIQueryProgressEvent(
                    phase: "Query Complete",
                    title: "Retrieved \(diagnostics.retrievedChunkCount) chunks and generated \(diagnostics.tokensGenerated) tokens.",
                    detail: Self.makeCompletionDetail(from: diagnostics),
                    systemImage: "checkmark.seal.fill",
                    isGenerating: false,
                    liveTokenCount: ragService.deepThinkLiveTokens,
                    liveStepCount: ragService.deepThinkLiveSteps,
                    liveConfidence: ragService.deepThinkLiveConfidence
                )
            )
        }

        return OIQueryResult(
            answer: response.generatedResponse,
            citations: citations,
            confidence: response.confidenceScore,
            abstained: abstained,
            warnings: Array(warnings.prefix(6)),
            modelName: response.metadata.modelUsed,
            qualityMode: resolvedQualityMode,
            reasoningTrace: response.metadata.reasoningTrace ?? [],
            diagnostics: diagnostics
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

    private func ensureContainer(named libraryName: String?) throws -> KnowledgeContainer {
        let trimmed = libraryName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            if let activeContainer = containerService.activeContainer {
                return activeContainer
            }

            do {
                return try containerService.createContainer(name: "General")
            } catch let error as LibraryQuotaError {
                throw OpenIntelligenceEngineError.invalidRequest(error.errorDescription ?? "Library limit reached.")
            }
        }

        if let existing = findContainer(named: trimmed) {
            return existing
        }

        do {
            return try containerService.createContainer(name: trimmed)
        } catch let error as LibraryQuotaError {
            throw OpenIntelligenceEngineError.invalidRequest(error.errorDescription ?? "Library limit reached.")
        }
    }

    private static func mapQualityMode(_ qualityMode: OIQueryQualityMode) -> RAGQualityMode {
        switch qualityMode {
        case .standard:
            return .standard
        case .deepThink:
            return .deepThink
        case .maximum:
            return .maximum
        }
    }

    private static func mapQualityModeName(_ qualityModeName: String?) -> OIQueryQualityMode? {
        switch qualityModeName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "standard":
            return .standard
        case "deep think", "deepthink":
            return .deepThink
        case "maximum":
            return .maximum
        default:
            return nil
        }
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

    private func makeProgressMonitor(
        for ragService: RAGService,
        handler: OIQueryProgressHandler?,
        libraryName: String
    ) -> Task<Void, Never>? {
        guard let handler else {
            return nil
        }

        return Task { @MainActor in
            var deliveredEventCount = 0
            var lastGeneratingState = false
            var lastTokenCount = -1
            var lastStepCount = -1
            var lastConfidence = Float.nan
            var hasDeliveredInitialEvent = false

            while !Task.isCancelled {
                if !hasDeliveredInitialEvent {
                    hasDeliveredInitialEvent = true
                    await handler(
                        OIQueryProgressEvent(
                            phase: "Planning",
                            title: "Query submitted",
                            detail: "The SDK handed the question to the retrieval pipeline for \(libraryName).",
                            systemImage: "paperplane.fill"
                        )
                    )
                }

                let thinkingEvents = ragService.thinkingEvents
                let isGenerating = ragService.isLLMResponding
                let liveTokenCount = ragService.deepThinkLiveTokens
                let liveStepCount = ragService.deepThinkLiveSteps
                let liveConfidence = ragService.deepThinkLiveConfidence

                if thinkingEvents.count > deliveredEventCount {
                    for event in thinkingEvents[deliveredEventCount...] {
                        await handler(
                            OIQueryProgressEvent(
                                timestamp: event.timestamp,
                                phase: event.kind.displayName,
                                title: event.title,
                                detail: event.detail,
                                systemImage: event.kind.systemIconName,
                                isGenerating: isGenerating,
                                liveTokenCount: liveTokenCount,
                                liveStepCount: liveStepCount,
                                liveConfidence: liveConfidence
                            )
                        )
                    }
                    deliveredEventCount = thinkingEvents.count
                }

                let confidenceChanged: Bool
                if lastConfidence.isNaN {
                    confidenceChanged = true
                } else {
                    confidenceChanged = abs(lastConfidence - liveConfidence) >= 0.01
                }

                if isGenerating != lastGeneratingState {
                    lastGeneratingState = isGenerating
                    await handler(
                        OIQueryProgressEvent(
                            phase: isGenerating ? "Generation" : "Pipeline",
                            title: isGenerating ? "Model started generating" : "Generation paused",
                            detail: isGenerating
                                ? "The model is now writing the answer text."
                                : "The pipeline is still working, but the model is not actively emitting tokens right now.",
                            systemImage: isGenerating ? "sparkles" : "pause.circle",
                            isGenerating: isGenerating,
                            liveTokenCount: liveTokenCount,
                            liveStepCount: liveStepCount,
                            liveConfidence: liveConfidence
                        )
                    )
                }

                if liveTokenCount != lastTokenCount || liveStepCount != lastStepCount || confidenceChanged {
                    lastTokenCount = liveTokenCount
                    lastStepCount = liveStepCount
                    lastConfidence = liveConfidence

                    guard liveTokenCount > 0 || liveStepCount > 0 || liveConfidence > 0 else {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        continue
                    }

                    await handler(
                        OIQueryProgressEvent(
                            phase: "Live Metrics",
                            title: "Steps \(liveStepCount) · Tokens \(liveTokenCount)",
                            detail: liveConfidence > 0
                                ? "Confidence \(Self.percentString(for: liveConfidence))."
                                : nil,
                            systemImage: "waveform.path.ecg",
                            isGenerating: isGenerating,
                            liveTokenCount: liveTokenCount,
                            liveStepCount: liveStepCount,
                            liveConfidence: liveConfidence
                        )
                    )
                }

                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
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

    private static func makeCompletionDetail(from diagnostics: OIQueryDiagnostics) -> String {
        var parts: [String] = []

        if let candidateChunkCount = diagnostics.candidateChunkCount {
            parts.append("Candidates \(candidateChunkCount)")
        }

        if let rerankedChunkCount = diagnostics.rerankedChunkCount {
            parts.append("Reranked \(rerankedChunkCount)")
        }

        if let contextChunkCount = diagnostics.contextChunkCount {
            parts.append("Context \(contextChunkCount)")
        }

        parts.append("Retrieval \(formattedSeconds(diagnostics.retrievalTime))")
        parts.append("Generation \(formattedSeconds(diagnostics.generationTime))")

        if let timeToFirstToken = diagnostics.timeToFirstToken {
            parts.append("TTFT \(formattedSeconds(timeToFirstToken))")
        }

        if let contextStrategy = diagnostics.contextStrategy, !contextStrategy.isEmpty {
            parts.append(contextStrategy)
        }

        if !diagnostics.featureFlags.isEmpty {
            parts.append(diagnostics.featureFlags.joined(separator: ", "))
        }

        return parts.joined(separator: " · ")
    }

    private static func formattedSeconds(_ value: TimeInterval) -> String {
        String(format: "%.2fs", value)
    }

    private static func percentString(for value: Float) -> String {
        let percentage = Int((value * 100).rounded())
        return "\(percentage)%"
    }
}
