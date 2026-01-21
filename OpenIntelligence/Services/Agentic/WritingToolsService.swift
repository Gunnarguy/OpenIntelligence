//
//  WritingToolsService.swift
//  OpenIntelligence
//
//  Apple Writing Tools API integration for proofreading, rewriting, and summarization
//  Available on iOS 18.1+ with Apple Intelligence
//
//  Created by GitHub Copilot on 10/15/25.
//

import Foundation
import SwiftUI

#if canImport(WritingTools)
import WritingTools

/// Service for integrating Apple's Writing Tools into RAG workflows
/// Provides system-level text enhancement capabilities
@available(iOS 18.1, *)
class WritingToolsService {
    
    /// Check if Writing Tools are available on this device
    var isAvailable: Bool {
        // Writing Tools requires Apple Intelligence to be enabled
        // Available on iPhone 15 Pro/Pro Max+, iPad with M1+, Mac with M1+
        return WritingTools.isAvailable
    }
    
    // MARK: - Text Enhancement
    
    /// Proofread text for grammar and spelling errors
    func proofread(_ text: String) async throws -> String {
        guard isAvailable else {
            throw WritingToolsError.notAvailable
        }

        Log.debug("[Writing Tools] Proofreading text (chars=\(text.count))", category: .pipeline)
        
        let request = WritingToolsRequest(
            text: text,
            tool: .proofread
        )
        
        let result = try await WritingTools.process(request)

        Log.debug("[Writing Tools] Proofreading complete (changes=\(result.changeCount))", category: .pipeline)
        
        return result.text
    }
    
    /// Rewrite text in different tones/styles
    func rewrite(_ text: String, tone: RewriteTone) async throws -> [String] {
        guard isAvailable else {
            throw WritingToolsError.notAvailable
        }

        Log.debug("[Writing Tools] Rewriting text (chars=\(text.count), tone=\(tone.rawValue))", category: .pipeline)
        
        let request = WritingToolsRequest(
            text: text,
            tool: .rewrite(tone: tone.systemTone)
        )
        
        let result = try await WritingTools.process(request)

        Log.debug("[Writing Tools] Rewrite complete (alternatives=\(result.alternatives.count))", category: .pipeline)
        
        return result.alternatives
    }
    
    /// Summarize text into key points
    func summarize(_ text: String, style: SummaryStyle) async throws -> String {
        guard isAvailable else {
            throw WritingToolsError.notAvailable
        }

        Log.debug("[Writing Tools] Summarizing text (chars=\(text.count), style=\(style.rawValue))", category: .pipeline)
        
        let request = WritingToolsRequest(
            text: text,
            tool: .summarize(style: style.systemStyle)
        )
        
        let result = try await WritingTools.process(request)

        let compression = text.isEmpty ? 0.0 : (Double(result.text.count) / Double(text.count) * 100)
        Log.debug("[Writing Tools] Summary complete (originalChars=\(text.count), summaryChars=\(result.text.count), compression=\(String(format: "%.1f", compression))%)", category: .pipeline)
        
        return result.text
    }
    
    /// Make text more concise
    func makeConcise(_ text: String) async throws -> String {
        guard isAvailable else {
            throw WritingToolsError.notAvailable
        }

        Log.debug("[Writing Tools] Making text concise (chars=\(text.count))", category: .pipeline)
        
        let request = WritingToolsRequest(
            text: text,
            tool: .makeConcise
        )
        
        let result = try await WritingTools.process(request)

        Log.debug("[Writing Tools] Concise version ready (originalChars=\(text.count), conciseChars=\(result.text.count))", category: .pipeline)
        
        return result.text
    }
    
    // MARK: - RAG-Specific Enhancements
    
    /// Summarize retrieved chunks before passing to LLM (reduces token usage)
    func summarizeContext(_ chunks: [RetrievedChunk]) async throws -> String {
        guard isAvailable else {
            // Fallback: Return raw chunks concatenated
            return chunks.map { $0.chunk.content }.joined(separator: "\n\n")
        }

        Log.debug("[Writing Tools] Summarizing context (chunks=\(chunks.count))", category: .pipeline)
        
        let rawContext = chunks.map { chunk in
            """
            [Relevance: \(String(format: "%.2f", chunk.similarityScore))]
            \(chunk.chunk.content)
            """
        }.joined(separator: "\n\n---\n\n")
        
        // Use "key points" style for factual document content
        let summary = try await summarize(rawContext, style: .keyPoints)

        let savings = rawContext.count - summary.count
        let pct = rawContext.isEmpty ? 0.0 : ((1.0 - Double(summary.count) / Double(rawContext.count)) * 100)
        Log.debug("[Writing Tools] Context summarized (originalChars=\(rawContext.count), summaryChars=\(summary.count), savingsChars=\(savings), savingsPct=\(String(format: "%.1f", pct))%)", category: .pipeline)
        
        return summary
    }
    
    /// Improve user query clarity before RAG processing
    func clarifyQuery(_ query: String) async throws -> String {
        guard isAvailable else {
            return query
        }

        Log.debug("[Writing Tools] Clarifying user query (chars=\(query.count))", category: .pipeline)
        
        // Use proofread to fix typos and grammar
        let clarified = try await proofread(query)

        if clarified != query {
            Log.debug("[Writing Tools] Query clarified (charsBefore=\(query.count), charsAfter=\(clarified.count))", category: .pipeline)
        } else {
            Log.verbose("[Writing Tools] Query already clear", category: .pipeline)
        }
        
        return clarified
    }
}

// MARK: - Supporting Types

@available(iOS 18.1, *)
enum RewriteTone: String, CaseIterable {
    case professional = "Professional"
    case friendly = "Friendly"
    case concise = "Concise"
    case casual = "Casual"
    
    var systemTone: WritingTools.Tone {
        switch self {
        case .professional: return .professional
        case .friendly: return .friendly
        case .concise: return .concise
        case .casual: return .casual
        }
    }
}

@available(iOS 18.1, *)
enum SummaryStyle: String, CaseIterable {
    case keyPoints = "Key Points"
    case paragraph = "Paragraph"
    case list = "List"
    
    var systemStyle: WritingTools.SummaryStyle {
        switch self {
        case .keyPoints: return .keyPoints
        case .paragraph: return .paragraph
        case .list: return .list
        }
    }
}

enum WritingToolsError: LocalizedError {
    case notAvailable
    case processingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Writing Tools require Apple Intelligence (iOS 18.1+, A17 Pro+ or M1+)"
        case .processingFailed(let message):
            return "Writing Tools processing failed: \(message)"
        }
    }
}

#else
// Stub for platforms without Writing Tools
class WritingToolsService {
    var isAvailable: Bool { false }
    
    func proofread(_ text: String) async throws -> String {
        throw WritingToolsError.notAvailable
    }
    
    func rewrite(_ text: String, tone: RewriteTone) async throws -> [String] {
        throw WritingToolsError.notAvailable
    }
    
    func summarize(_ text: String, style: SummaryStyle) async throws -> String {
        throw WritingToolsError.notAvailable
    }
    
    func makeConcise(_ text: String) async throws -> String {
        throw WritingToolsError.notAvailable
    }
    
    func summarizeContext(_ chunks: [RetrievedChunk]) async throws -> String {
        return chunks.map { $0.chunk.content }.joined(separator: "\n\n")
    }
    
    func clarifyQuery(_ query: String) async throws -> String {
        return query
    }
}

enum RewriteTone: String, CaseIterable {
    case professional = "Professional"
    case friendly = "Friendly"
    case concise = "Concise"
    case casual = "Casual"
}

enum SummaryStyle: String, CaseIterable {
    case keyPoints = "Key Points"
    case paragraph = "Paragraph"
    case list = "List"
}

enum WritingToolsError: LocalizedError {
    case notAvailable
    
    var errorDescription: String? {
        "Writing Tools not available on this platform"
    }
}
#endif
