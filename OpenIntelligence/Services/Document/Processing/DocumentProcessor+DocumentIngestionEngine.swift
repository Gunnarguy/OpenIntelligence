import Foundation

extension DocumentProcessor: DocumentIngestionEngine {
    func ingestDocument(
        at url: URL,
        chunkOverride: DocumentChunkingOverride? = nil,
        containerId: UUID? = nil
    ) async throws -> IngestedDocumentPayload {
        let resolvedOverride = chunkOverride.map {
            ChunkingOverride(
                strategy: nil,
                targetWordWindow: $0.targetWordWindow,
                overlapWords: $0.overlapWords
            )
        }

        let (document, chunks) = try await processDocument(
            at: url,
            chunkOverride: resolvedOverride,
            containerId: containerId
        )

        return IngestedDocumentPayload(
            document: document,
            chunks: chunks.map {
                IngestedChunk(
                    text: $0.text,
                    parentText: $0.parentText,
                    metadata: $0.metadata
                )
            }
        )
    }
}
