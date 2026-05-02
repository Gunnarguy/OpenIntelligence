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
    case failed

    static let pipelineStages: [IngestionStage] = [
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
        case .failed: return "Failed"
        }
    }

    var pipelineIndex: Int? {
        IngestionStage.pipelineStages.firstIndex(of: self)
    }

    var isTerminal: Bool {
        self == .complete || self == .failed
    }
}

/// Rich pipeline metrics for real-time transparency
struct PipelineMetrics: Codable, Sendable, Equatable {
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
    let url: URL
    var stage: IngestionStage
    var detail: String
    var progress: Double?
    var startedAt: Date?
    var finishedAt: Date?
    var errorMessage: String?
    var metrics: PipelineMetrics = .init()

    init(
        id: UUID = UUID(),
        url: URL,
        stage: IngestionStage = .queued,
        detail: String = "Queued",
        progress: Double? = nil,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        errorMessage: String? = nil,
        metrics: PipelineMetrics = PipelineMetrics()
    ) {
        self.id = id
        self.url = url
        self.stage = stage
        self.detail = detail
        self.progress = progress
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.errorMessage = errorMessage
        self.metrics = metrics
    }

    var filename: String {
        url.lastPathComponent
    }
}

struct IngestionBatchResult: Sendable {
    let successCount: Int
    let failureCount: Int
    let totalCount: Int
    let completedIds: [UUID]
}
