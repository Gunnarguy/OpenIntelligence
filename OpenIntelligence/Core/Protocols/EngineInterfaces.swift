import Foundation

/// Stable retrieval request shape for app-facing engine calls.
/// This keeps the public app layer decoupled from the concrete RAGService surface.
struct RetrievalRequest {
    let question: String
    let topK: Int
    let config: InferenceConfig?
    let containerId: UUID?
    let externalEvidence: [EvidenceSource]?

    init(
        question: String,
        topK: Int = 3,
        config: InferenceConfig? = nil,
        containerId: UUID? = nil,
        externalEvidence: [EvidenceSource]? = nil
    ) {
        self.question = question
        self.topK = topK
        self.config = config
        self.containerId = containerId
        self.externalEvidence = externalEvidence
    }
}

/// Public retrieval seam for the app shell.
/// A future private engine can satisfy this without changing feature code.
@MainActor
protocol KnowledgeRetrievalEngine: AnyObject {
    func query(_ request: RetrievalRequest) async throws -> RAGResponse
}

/// Stable chunking override shape for app-facing ingestion calls.
struct DocumentChunkingOverride {
    let strategy: String?
    let targetWordWindow: Int
    let overlapWords: Int

    init(strategy: String? = nil, targetWordWindow: Int, overlapWords: Int) {
        self.strategy = strategy
        self.targetWordWindow = targetWordWindow
        self.overlapWords = overlapWords
    }
}

/// Normalized chunk payload for engine-boundary ingestion results.
struct IngestedChunk {
    let text: String
    let parentText: String?
    let metadata: ChunkMetadata

    init(text: String, parentText: String?, metadata: ChunkMetadata) {
        self.text = text
        self.parentText = parentText
        self.metadata = metadata
    }
}

/// Normalized document ingestion result for future engine extraction.
struct IngestedDocumentPayload {
    let document: Document
    let chunks: [IngestedChunk]

    init(document: Document, chunks: [IngestedChunk]) {
        self.document = document
        self.chunks = chunks
    }
}

/// Public ingestion seam for the app shell.
/// A future private engine can own parsing/chunking while preserving this contract.
@MainActor
protocol DocumentIngestionEngine: AnyObject {
    func ingestDocument(
        at url: URL,
        chunkOverride: DocumentChunkingOverride?,
        containerId: UUID?
    ) async throws -> IngestedDocumentPayload
}
