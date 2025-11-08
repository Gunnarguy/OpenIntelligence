//
//  QueryEnhancementService.swift
//  OpenIntelligence
//
//  Query expansion, reformulation, and result re-ranking
//

import Foundation
import NaturalLanguage

/// Enhances queries and re-ranks results for better retrieval accuracy
class QueryEnhancementService {
    
    /// Expand query with synonyms and related terms
    func expandQuery(_ query: String) -> [String] {
        print("\n🔍 [QueryEnhancement] Expanding query...")
        print("   📝 Original: \"\(query)\"")
        
        var expandedQueries: [String] = [query]  // Always include original
        
        // 1. Extract key terms
        let keyTerms = extractKeyTerms(query)
        print("   🎯 Key terms: \(keyTerms.joined(separator: ", "))")
        
        // 2. Generate synonyms using NaturalLanguage
        let synonyms = generateSynonyms(for: keyTerms)
        print("   📚 Synonyms found: \(synonyms.count)")
        
        // 2.5 Handle trivial/underspecified queries to help BM25
        let tokenCount = query.split(separator: " ").count
        let trimmedLower = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let trivialSet: Set<String> = ["test","help","hello","hi","hey","ok","okay","thanks","thank you"]
        if tokenCount <= 1 || keyTerms.isEmpty || trivialSet.contains(trimmedLower) {
            expandedQueries.append("\(query) overview")
            expandedQueries.append("\(query) summary")
            expandedQueries.append("\(query) introduction")
            expandedQueries.append("overview")
            expandedQueries.append("summary")
            print("   🔧 Trivial input detected; added generic boost terms for BM25")
            print("   ✅ Generated \(expandedQueries.count) query variations")
            return Array(Set(expandedQueries))
        }
        
        // 3. Create expanded query versions
        if !synonyms.isEmpty {
            // Version 1: Replace key terms with synonyms
            for (term, syns) in synonyms {
                for syn in syns.prefix(2) {  // Top 2 synonyms only
                    let expanded = query.replacingOccurrences(of: term, with: syn, options: .caseInsensitive)
                    if expanded != query {
                        expandedQueries.append(expanded)
                    }
                }
            }
            
            // Version 2: Append synonyms
            let allSynonyms = synonyms.values.flatMap { $0 }.prefix(3).joined(separator: " ")
            if !allSynonyms.isEmpty {
                expandedQueries.append("\(query) \(allSynonyms)")
            }
        }
        
        // 4. Question reformulation
        if query.contains("?") {
            expandedQueries.append(contentsOf: reformulateQuestion(query))
        }
        
        print("   ✅ Generated \(expandedQueries.count) query variations")
        for (i, q) in expandedQueries.enumerated() where i > 0 {
            print("      [\(i)] \(q)")
        }
        
        return Array(Set(expandedQueries))  // Remove duplicates
    }
    
    /// Extract key terms (nouns, verbs, proper nouns)
    private func extractKeyTerms(_ query: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType])
        tagger.string = query
        
        var keyTerms: [String] = []
        
        tagger.enumerateTags(in: query.startIndex..<query.endIndex, unit: .word,
                            scheme: .lexicalClass, options: [.omitWhitespace, .omitPunctuation]) { tag, range in
            if tag == .noun || tag == .verb || tag == .adjective {
                let term = String(query[range])
                if term.count > 2 {  // Filter very short words
                    keyTerms.append(term)
                }
            }
            return true
        }
        
        return keyTerms
    }
    
    /// Generate synonyms for terms
    private func generateSynonyms(for terms: [String]) -> [String: [String]] {
        var synonyms: [String: [String]] = [:]
        
        // Common domain-specific synonyms (can be expanded)
        let synonymDict: [String: [String]] = [
            "clean": ["sanitize", "disinfect", "sterilize", "wash"],
            "use": ["operate", "utilize", "employ", "apply"],
            "device": ["instrument", "equipment", "apparatus", "tool"],
            "procedure": ["process", "method", "protocol", "technique"],
            "patient": ["individual", "subject", "person"],
            "doctor": ["physician", "surgeon", "clinician", "practitioner"],
            "remove": ["detach", "disconnect", "separate", "extract"],
            "install": ["attach", "connect", "mount", "affix"],
            "check": ["verify", "inspect", "examine", "test"],
            "warning": ["caution", "alert", "notice", "advisory"]
        ]
        
        for term in terms {
            let lowercased = term.lowercased()
            if let syns = synonymDict[lowercased] {
                synonyms[term] = syns
            }
        }
        
        return synonyms
    }
    
    /// Reformulate questions into statement form
    private func reformulateQuestion(_ query: String) -> [String] {
        var reformulations: [String] = []
        
        // Common question patterns
        let patterns: [(pattern: String, replacement: String)] = [
            ("^How do I ", "Instructions for "),
            ("^How to ", "Procedure for "),
            ("^What is ", "Information about "),
            ("^What are ", "Details on "),
            ("^When should ", "Timing for "),
            ("^Why ", "Reason for "),
            ("^Can I ", "Possibility of "),
            ("^Where ", "Location of ")
        ]
        
        for (pattern, replacement) in patterns {
            if let range = query.range(of: pattern, options: .regularExpression) {
                var reformulated = query
                reformulated.replaceSubrange(range, with: replacement)
                reformulated = reformulated.replacingOccurrences(of: "?", with: "")
                reformulations.append(reformulated)
            }
        }
        
        return reformulations
    }
    
    /// Re-rank results using multiple signals
    func rerank(
        chunks: [RetrievedChunk],
        query: String,
        topK: Int
    ) -> [RetrievedChunk] {
        print("\n🔄 [QueryEnhancement] Re-ranking \(chunks.count) results...")
        
        // Create mutable array with metadata dictionary
        var scoredChunks: [(chunk: RetrievedChunk, metadata: [String: Any])] = chunks.map {
            ($0, [:])
        }
        
        // Score each chunk with multiple signals
        for i in 0..<scoredChunks.count {
            var score = scoredChunks[i].chunk.similarityScore  // Base semantic similarity
            
            // Signal 1: Exact keyword matches
            let keywordBoost = calculateKeywordMatch(query: query, content: scoredChunks[i].chunk.chunk.content)
            score += keywordBoost * 0.2
            scoredChunks[i].metadata["keyword_boost"] = keywordBoost
            
            // Signal 2: Term proximity (how close query terms are in document)
            let proximityBoost = calculateTermProximity(query: query, content: scoredChunks[i].chunk.chunk.content)
            score += proximityBoost * 0.15
            scoredChunks[i].metadata["proximity_boost"] = proximityBoost
            
            // Signal 3: Position/recency (first chunks often more important)
            let chunkIndex = scoredChunks[i].chunk.chunk.metadata.chunkIndex
            let positionScore = 1.0 / Float(chunkIndex + 10)  // Slight boost for earlier chunks
            score += positionScore * 0.05
            
            // Note: Enhanced metadata from SemanticChunker (hasNumericData, hasListStructure)
            // will be available once DocumentProcessor integration is complete
            
            // Store final score
            scoredChunks[i].metadata["rerank_score"] = score
        }
        
        // Sort by re-ranked score
        scoredChunks.sort { item1, item2 in
            let score1 = item1.metadata["rerank_score"] as? Float ?? item1.chunk.similarityScore
            let score2 = item2.metadata["rerank_score"] as? Float ?? item2.chunk.similarityScore
            return score1 > score2
        }
        
        let topResults = Array(scoredChunks.prefix(topK))
        
        if let firstScore = topResults.first?.metadata["rerank_score"] as? Float {
            print("   ✅ Re-ranking complete. Top score: \(String(format: "%.4f", firstScore))")
            print("   📊 Score breakdown:")
            print("      - Semantic: \(String(format: "%.3f", topResults.first?.chunk.similarityScore ?? 0))")
            print("      - Keywords: \(String(format: "%.3f", topResults.first?.metadata["keyword_boost"] as? Float ?? 0))")
            print("      - Proximity: \(String(format: "%.3f", topResults.first?.metadata["proximity_boost"] as? Float ?? 0))")
        }
        
        // Return just the chunks (metadata is in print output only for now)
        return topResults.map { $0.chunk }
    }
    
    /// Calculate keyword match score
    private func calculateKeywordMatch(query: String, content: String) -> Float {
        let queryTerms = Set(query.lowercased().split(separator: " ").map { String($0) }.filter { $0.count > 2 })
        let contentTerms = Set(content.lowercased().split(separator: " ").map { String($0) })
        
        let matches = queryTerms.intersection(contentTerms)
        return Float(matches.count) / Float(max(queryTerms.count, 1))
    }
    
    /// Calculate term proximity (how close query terms appear in content)
    private func calculateTermProximity(query: String, content: String) -> Float {
        let queryTerms = query.lowercased().split(separator: " ").map { String($0) }.filter { $0.count > 2 }
        let contentWords = content.lowercased().split(separator: " ").map { String($0) }
        
        guard queryTerms.count > 1 else { return 0 }
        
        // Find positions of each query term
        var positions: [[Int]] = []
        for term in queryTerms {
            let pos = contentWords.enumerated().compactMap { $0.element.contains(term) ? $0.offset : nil }
            positions.append(pos)
        }
        
        // Calculate minimum distance between terms
        var minDistance = Int.max
        if positions.allSatisfy({ !$0.isEmpty }) {
            for i in 0..<positions[0].count {
                for j in 0..<positions[1].count {
                    let distance = abs(positions[0][i] - positions[1][j])
                    minDistance = min(minDistance, distance)
                }
            }
        }
        
        // Closer terms = higher score
        return minDistance == Int.max ? 0 : 1.0 / Float(minDistance + 1)
    }
    
    private func queryHasNumbers(_ query: String) -> Bool {
        return query.rangeOfCharacter(from: .decimalDigits) != nil
    }
    
    private func querySeeksSteps(_ query: String) -> Bool {
        let stepKeywords = ["how", "step", "procedure", "process", "instructions"]
        return stepKeywords.contains { query.lowercased().contains($0) }
    }
}
