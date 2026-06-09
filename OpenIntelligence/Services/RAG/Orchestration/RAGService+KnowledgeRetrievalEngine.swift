import Foundation

extension RAGService: KnowledgeRetrievalEngine {
    func query(_ request: RetrievalRequest) async throws -> RAGResponse {
        try await query(
            request.question,
            topK: request.topK,
            config: request.config,
            containerId: request.containerId,
            externalEvidence: request.externalEvidence,
            streamHandler: nil
        )
    }
}
