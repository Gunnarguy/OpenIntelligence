//
//  RAGService+QuotesOnly.swift
//  OpenIntelligence
//
//  Quotes only ("On-Device Analysis"): the answer is the documents' own words, and no model writes anything (5.8).
//

import Foundation

extension RAGService {
    /// The words a Quotes only answer closes with: what the excerpts are and who wrote them.
    nonisolated static let quotesOnlyClosing =
        "These are your documents' own words. In Quotes only, no model writes or rewrites anything."

    /// Whether the person picked Quotes only. Through 5.7 the mode was answered by Apple's model under the normal
    /// route, though Settings said no model writes and it never leaves the device (roadmap row
    /// `40049a74d54f811ea077ef82be46545e`). The pipeline reads this to skip every model step: query rewriting, HyDE,
    /// contextual compression, Deep Think and Maximum, generation and the checks that run on the answer.
    var quotesOnlySelected: Bool {
        settingsStore?.selectedModel == .onDeviceAnalysis
    }

    /// The Quotes only answer from the passages Standard assembled for the model: up to six excerpts copied from them,
    /// each with its source label, and a closing line that says no model wrote them. It reads Not Checked, because no
    /// check ran (`excerpts_only`).
    func quotesOnlyResponse(
        question: String,
        passages: [RetrievedChunk],
        queryId: UUID,
        retrievalTime: TimeInterval,
        retrievalConfig: RetrievalConfig,
        embeddingProviderId: String
    ) -> RAGResponse {
        let started = Date()
        let bullets = excerptBullets(question: question, passages: passages)
        let text =
            bullets.isEmpty
            ? "I couldn't find words in your documents that answer this. Try asking with the document's own words."
            : """
            Here are the most relevant excerpts from your documents:

            \(bullets.joined(separator: "\n\n"))

            \(Self.quotesOnlyClosing)
            """
        VerificationJournal.record(
            "answer.quotesOnly", ["bullets": "\(bullets.count)", "passages": "\(passages.count)"])
        Log.info(
            "[QuotesOnly] \(bullets.count) excerpts from \(passages.count) passages, no model call", category: .pipeline
        )
        let metadata = ResponseMetadata(
            timeToFirstToken: nil,
            totalGenerationTime: Date().timeIntervalSince(started),
            tokensGenerated: 0,
            tokensPerSecond: nil,
            modelUsed: "Quotes only",
            retrievalTime: retrievalTime,
            retrievalConfigSummary: retrievalConfig.summary,
            gatingDecision: "excerpts_only",
            toolCallsMade: 0,
            embeddingProvider: embeddingProviderId
        )
        let usedPassages = Array(passages.prefix(6))
        return RAGResponse(
            queryId: queryId,
            retrievedChunks: usedPassages,
            generatedResponse: text,
            metadata: metadata,
            confidenceScore: 0.0,
            qualityWarnings: ["Quotes only"],
            structuredAnswer: StructuredAnswer.from(
                response: text,
                retrievedChunks: usedPassages,
                answerIntent: QueryEnhancementService().classifyAnswerIntent(question),
                verificationResult: nil,
                loops: 1
            )
        )
    }
}
