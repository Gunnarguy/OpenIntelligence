import Foundation

enum IngestionStage: String, CaseIterable, Sendable {
    case queued
    case loading
    case extracting
    case chunking
    case analyzing
    case embedding
    case storing
    case complete
    case failed

    static let pipelineStages: [IngestionStage] = [
        .loading,
        .extracting,
        .chunking,
        .analyzing,
        .embedding,
        .storing,
    ]

    var displayName: String {
        switch self {
        case .queued: return "Queued"
        case .loading: return "Loading"
        case .extracting: return "Extracting"
        case .chunking: return "Chunking"
        case .analyzing: return "Analyzing"
        case .embedding: return "Embedding"
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

struct IngestionItem: Identifiable, Sendable, Equatable {
    let id: UUID
    let url: URL
    var stage: IngestionStage
    var detail: String
    var progress: Double?
    var startedAt: Date?
    var finishedAt: Date?
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        url: URL,
        stage: IngestionStage = .queued,
        detail: String = "Queued",
        progress: Double? = nil,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.url = url
        self.stage = stage
        self.detail = detail
        self.progress = progress
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.errorMessage = errorMessage
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
