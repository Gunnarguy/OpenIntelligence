//
//  RAPTORSummaryRouter.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import Foundation

/// Routes overview queries to summary-level index chunks (RAPTOR-lite L1).
final class RAPTORSummaryRouter: Sendable {
    
    /// Filter database chunks to only include summary-level (L1+) chunks.
    static func filterSummaryChunks(_ chunks: [DocumentChunk]) -> [DocumentChunk] {
        return chunks.filter { $0.metadata.abstractionLevel.isSummary }
    }
    
    /// Filter retrieved chunks to only include summary-level (L1+) chunks.
    static func filterSummaryRetrievedChunks(_ chunks: [RetrievedChunk]) -> [RetrievedChunk] {
        return chunks.filter { $0.chunk.metadata.abstractionLevel.isSummary }
    }
}
