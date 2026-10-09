//
//  RAGQueryScope.swift
//  OpenIntelligence
//

import Foundation

/// Limits one question to passages from named documents.
///
/// Shortcuts' "Ask About a Document" wrote the file name into the question and searched the whole
/// library, so the answer could come from any document (roadmap row 3f449a74d54f81c0963bc125ccabbb33).
/// A caller sets the scope around one `RAGService.query` call:
///
///     try await RAGQueryScope.$documentIds.withValue([document.id]) {
///         try await engine.query(question)
///     }
///
/// It is a task-local value, like the stream handler in `LLMStreamingContext`, so it reaches every
/// stage of that one question and no other question running at the same time.
nonisolated enum RAGQueryScope {
    @TaskLocal static var documentIds: Set<UUID>?

    /// The passages that belong to the scope. Without a scope the list comes back unchanged.
    static func apply(to chunks: [RetrievedChunk]) -> [RetrievedChunk] {
        guard let scope = documentIds, !scope.isEmpty else { return chunks }
        return chunks.filter { scope.contains($0.chunk.documentId) }
    }

    /// The candidate passages that belong to the scope. Without a scope the list comes back unchanged.
    static func apply(to chunks: [DocumentChunk]) -> [DocumentChunk] {
        guard let scope = documentIds, !scope.isEmpty else { return chunks }
        return chunks.filter { scope.contains($0.documentId) }
    }
}

/// A question limited to named documents found none of their passages. It is an error and not an
/// answer: without it the engine's general fallback would reply from the model alone, with no
/// sources, to a question that named a document.
nonisolated struct RAGQueryScopeEmptyError: LocalizedError {
    var errorDescription: String? {
        "Nothing in the chosen document matched the question."
    }
}
