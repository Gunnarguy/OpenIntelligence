import Foundation

enum IngestionStage: String, CaseIterable, Codable, Sendable {
    case queued
    case loading
    case transcribing // Audio/video transcription via Speech.framework
    case extracting
    case chunking
    case analyzing // Corpus intelligence analysis
    case adapting // Adjusting chunking/embedding config
    case reindexing // Re-chunking with new parameters
    case embedding
    case indexing // BM25 + vector index building
    case storing
    case complete
    case cancelled
    case failed

        nonisolated static let pipelineStages: [IngestionStage] = [
        .loading,
        .transcribing,
        .extracting,
        .chunking,
        .analyzing,
        .adapting,
        .reindexing,
        .embedding,
        .indexing,
        .storing,
    ]

    nonisolated private static let pipelineStageWeights: [IngestionStage: Double] = [
        .loading: 0.05,
        .transcribing: 0.03,
        .extracting: 0.52,
        .chunking: 0.08,
        .analyzing: 0.08,
        .adapting: 0.04,
        .reindexing: 0.04,
        .embedding: 0.10,
        .indexing: 0.04,
        .storing: 0.02,
    ]

    nonisolated private static let pipelineTotalWeight: Double = pipelineStages.reduce(0) {
        $0 + (pipelineStageWeights[$1] ?? 0)
    }

    var displayName: String {
        switch self {
        case .queued: return "Queued"
        case .loading: return "Loading"
        case .transcribing: return "Transcribing"
        case .extracting: return "Extracting"
        case .chunking: return "Chunking"
        case .analyzing: return "Analyzing"
        case .adapting: return "Adapting"
        case .reindexing: return "Re-indexing"
        case .embedding: return "Embedding"
        case .indexing: return "Indexing"
        case .storing: return "Storing"
        case .complete: return "Complete"
        case .cancelled: return "Cancelled"
        case .failed: return "Failed"
        }
    }

    nonisolated var pipelineIndex: Int? {
        IngestionStage.pipelineStages.firstIndex(of: self)
    }

    nonisolated var pipelineBaseFraction: Double? {
        guard pipelineIndex != nil, Self.pipelineTotalWeight > 0 else { return nil }

        var accumulatedWeight = 0.0
        for stage in Self.pipelineStages {
            if stage == self {
                return accumulatedWeight / Self.pipelineTotalWeight
            }
            accumulatedWeight += Self.pipelineStageWeights[stage] ?? 0
        }

        return nil
    }

    nonisolated var pipelineWeightFraction: Double? {
        guard pipelineIndex != nil, Self.pipelineTotalWeight > 0 else { return nil }
        return (Self.pipelineStageWeights[self] ?? 0) / Self.pipelineTotalWeight
    }

    nonisolated var isTerminal: Bool {
        self == .complete || self == .cancelled || self == .failed
    }
}

/// Granular event representing a discrete step in the ingestion pipeline
struct IngestionEvent: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let timestamp: Date
    let stage: IngestionStage
    let title: String
    let detail: String?

    init(id: UUID = UUID(), timestamp: Date = Date(), stage: IngestionStage, title: String, detail: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.stage = stage
        self.title = title
        self.detail = detail
    }
}

/// Rich pipeline metrics for real-time transparency
struct PipelineMetrics: Codable, Sendable, Equatable {
    nonisolated init() {}

    // Document stats
    var fileSizeMB: Double = 0
    var totalCharacters: Int = 0
    var totalWords: Int = 0
    var pageCount: Int = 0
    var ocrPagesCount: Int = 0

    // === STRUCTURED DOCUMENT PARSING (Vision iOS 26+) ===
    var usedStructuredParsing: Bool = false
    var structuredParsingQuality: Double = 0  // 0.0-1.0 quality score
    var tablesExtracted: Int = 0
    var tableRowsTotal: Int = 0
    var tableColumnsMax: Int = 0
    var listsExtracted: Int = 0
    var listItemsTotal: Int = 0
    var titlesDetected: Int = 0
    var figureReferences: Int = 0
    var visionEntitiesDetected: Int = 0  // Emails, phones, dates, URLs from Vision
    var sectionPathDepth: Int = 0  // Deepest hierarchy level detected
    var structuredParsingTimeMs: Int = 0

    // Chunking stats
    var chunkCount: Int = 0
    var avgChunkWords: Int = 0
    var minChunkWords: Int = 0
    var maxChunkWords: Int = 0
    var chunkingStrategy: String = ""
    var targetWordWindow: Int = 0
    var overlapWords: Int = 0
    var sectionsDetected: Int = 0
    var topicBoundaries: Int = 0
    var embeddingBoundaries: Int = 0
    var atomicTableChunks: Int = 0  // Tables kept as single chunks
    var atomicListChunks: Int = 0   // Lists kept as single chunks

    // Entity extraction
    var entitiesExtracted: Int = 0
    var topEntities: [String] = []

    // Embedding stats
    var embeddingDimension: Int = 0
    var embeddingProvider: String = ""
    var embeddingsGenerated: Int = 0
    var embeddingBatchProgress: Double = 0

    // Analysis results (when auto-adaptive)
    var vocabularyRichness: Double = 0
    var technicalDensity: Double = 0
    var semanticComplexity: Double = 0
    var multilingualScore: Double = 0
    var detectedLanguages: [String] = []
    var hasCode: Bool = false
    var hasMath: Bool = false

    // Document content profile (displayed in UI)
    var documentDomain: String = ""          // e.g. "Vehicle Manual", "Technical Report", "Legal"
    var contentDescriptor: String = ""       // e.g. "Automotive maintenance & specifications"
    var extractionCoverage: Double = 0       // 0.0-1.0 ratio of pages with extracted text
    var documentLanguage: String = ""        // Primary detected language name
    var contentCategories: [String] = []     // e.g. ["Safety", "Maintenance", "Specifications"]

    // Timing
    var extractionTimeMs: Int = 0
    var chunkingTimeMs: Int = 0
    var analysisTimeMs: Int = 0
    var embeddingTimeMs: Int = 0
    var totalTimeMs: Int = 0

    // Flags
    var isAutoAdaptive: Bool = false
    var configWasAdapted: Bool = false
    var adaptationReason: String = ""
    var isRebuild: Bool = false
    var rebuildReason: String = ""
}

struct IngestionItem: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    private let legacyURL: URL?
    let storageRelativePath: String?
    let containerId: UUID?
    var documentHash: String?
    var leaseOwnerDeviceId: String?
    var leaseExpiresAt: Date?
    var lastLeaseHeartbeatAt: Date?
    var stage: IngestionStage
    var detail: String
    var progress: Double?
    var startedAt: Date?
    var finishedAt: Date?
    var errorMessage: String?
    var metrics: PipelineMetrics = .init()
    var events: [IngestionEvent] = []

    nonisolated var url: URL {
        if let storageRelativePath {
            return AppSupportPaths.documentURL(forRelativePath: storageRelativePath)
        }

        if let legacyURL {
            return legacyURL
        }

        return AppSupportPaths.importedDocumentsDirectoryURL().appendingPathComponent(id.uuidString)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case url
        case storageRelativePath
        case containerId
        case documentHash
        case leaseOwnerDeviceId
        case leaseExpiresAt
        case lastLeaseHeartbeatAt
        case stage
        case detail
        case progress
        case startedAt
        case finishedAt
        case errorMessage
        case metrics
        case events
    }

    nonisolated init(
        id: UUID = UUID(),
        url: URL,
        storageRelativePath: String? = nil,
        containerId: UUID? = nil,
        documentHash: String? = nil,
        leaseOwnerDeviceId: String? = nil,
        leaseExpiresAt: Date? = nil,
        lastLeaseHeartbeatAt: Date? = nil,
        stage: IngestionStage = .queued,
        detail: String = "Queued",
        progress: Double? = nil,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        errorMessage: String? = nil,
        metrics: PipelineMetrics = PipelineMetrics(),
        events: [IngestionEvent] = []
    ) {
        let resolvedRelativePath = storageRelativePath ?? AppSupportPaths.relativePath(for: url)

        self.id = id
        self.legacyURL = resolvedRelativePath == nil ? url : nil
        self.storageRelativePath = resolvedRelativePath
        self.containerId = containerId
        self.documentHash = documentHash
        self.leaseOwnerDeviceId = leaseOwnerDeviceId
        self.leaseExpiresAt = leaseExpiresAt
        self.lastLeaseHeartbeatAt = lastLeaseHeartbeatAt
        self.stage = stage
        self.detail = detail
        self.progress = progress
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.errorMessage = errorMessage
        self.metrics = metrics
        self.events = events
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let decodedLegacyURL = try container.decodeIfPresent(URL.self, forKey: .url)
        let decodedRelativePath = try container.decodeIfPresent(String.self, forKey: .storageRelativePath)
        let resolvedRelativePath = decodedRelativePath ?? decodedLegacyURL.flatMap { AppSupportPaths.relativePath(for: $0) }
        legacyURL = resolvedRelativePath == nil ? decodedLegacyURL : nil
        storageRelativePath = resolvedRelativePath
        containerId = try container.decodeIfPresent(UUID.self, forKey: .containerId)
        documentHash = try container.decodeIfPresent(String.self, forKey: .documentHash)
        leaseOwnerDeviceId = try container.decodeIfPresent(String.self, forKey: .leaseOwnerDeviceId)
        leaseExpiresAt = try container.decodeIfPresent(Date.self, forKey: .leaseExpiresAt)
        lastLeaseHeartbeatAt = try container.decodeIfPresent(Date.self, forKey: .lastLeaseHeartbeatAt)
        stage = try container.decode(IngestionStage.self, forKey: .stage)
        detail = try container.decode(String.self, forKey: .detail)
        progress = try container.decodeIfPresent(Double.self, forKey: .progress)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        metrics = try container.decodeIfPresent(PipelineMetrics.self, forKey: .metrics) ?? .init()
        events = try container.decodeIfPresent([IngestionEvent].self, forKey: .events) ?? []
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(legacyURL, forKey: .url)
        try container.encodeIfPresent(storageRelativePath, forKey: .storageRelativePath)
        try container.encodeIfPresent(containerId, forKey: .containerId)
        try container.encodeIfPresent(documentHash, forKey: .documentHash)
        try container.encodeIfPresent(leaseOwnerDeviceId, forKey: .leaseOwnerDeviceId)
        try container.encodeIfPresent(leaseExpiresAt, forKey: .leaseExpiresAt)
        try container.encodeIfPresent(lastLeaseHeartbeatAt, forKey: .lastLeaseHeartbeatAt)
        try container.encode(stage, forKey: .stage)
        try container.encode(detail, forKey: .detail)
        try container.encodeIfPresent(progress, forKey: .progress)
        try container.encodeIfPresent(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(finishedAt, forKey: .finishedAt)
        try container.encodeIfPresent(errorMessage, forKey: .errorMessage)
        try container.encode(metrics, forKey: .metrics)
        try container.encode(events, forKey: .events)
    }

    nonisolated var filename: String {
        url.lastPathComponent
    }

    nonisolated func hasActiveLease(at date: Date = Date()) -> Bool {
        guard let leaseOwnerDeviceId, !leaseOwnerDeviceId.isEmpty,
              let leaseExpiresAt else {
            return false
        }
        return leaseExpiresAt > date
    }

    nonisolated func isLeased(to deviceId: String, at date: Date = Date()) -> Bool {
        hasActiveLease(at: date) && leaseOwnerDeviceId == deviceId
    }

    mutating func claimLease(ownerDeviceId: String, duration: TimeInterval, now: Date = Date()) {
        leaseOwnerDeviceId = ownerDeviceId
        lastLeaseHeartbeatAt = now
        leaseExpiresAt = now.addingTimeInterval(duration)
    }

    mutating func clearLease() {
        leaseOwnerDeviceId = nil
        leaseExpiresAt = nil
        lastLeaseHeartbeatAt = nil
    }
}

struct IngestionBatchResult: Sendable {
    let successCount: Int
    let failureCount: Int
    let totalCount: Int
    let completedIds: [UUID]
}
