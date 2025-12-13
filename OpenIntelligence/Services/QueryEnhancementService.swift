//
//  QueryEnhancementService.swift
//  OpenIntelligence
//
//  Query expansion and light reformulation to improve hybrid retrieval.
//

import Foundation
import NaturalLanguage

/// Enhances user queries before retrieval.
///
/// This service must be silent-by-default: do not use direct `print()`.
/// Route diagnostic output through `Log.*` so verbosity is gated.
final class QueryEnhancementService {

    /// Produces a small set of query variants for keyword-heavy retrieval (BM25).
    /// - Note: The first element is always the original query (trimmed).
    func expandQuery(_ query: String) -> [String] {
        let original = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return [] }

        Log.debug("[QueryEnhancement] Expanding query", category: .retrieval)

        var variations: [String] = [original]

        // 1) Extract key terms for synonym lookup.
        let keyTerms = extractKeyTerms(original)
        if !keyTerms.isEmpty {
            Log.debug("[QueryEnhancement] Key terms: \(keyTerms.joined(separator: ", "))", category: .retrieval)
        }

        // 2) Handle trivial/underspecified queries (helps BM25 avoid empty-ish inputs).
        let tokenCount = original.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let lower = original.lowercased()
        let trivialSet: Set<String> = [
            "test", "help", "hello", "hi", "hey", "ok", "okay", "thanks", "thank you",
        ]
        if tokenCount <= 1 || keyTerms.isEmpty || trivialSet.contains(lower) {
            variations.append("\(original) overview")
            variations.append("\(original) summary")
            variations.append("\(original) introduction")
            variations.append("overview")
            variations.append("summary")
            Log.debug("[QueryEnhancement] Trivial input detected; added generic boost terms", category: .retrieval)
            return uniquePreservingOrder(variations, max: 8)
        }

        // 3) Synonym-based expansions.
        let synonyms = generateSynonyms(for: keyTerms)
        if !synonyms.isEmpty {
            Log.debug("[QueryEnhancement] Synonym groups: \(synonyms.count)", category: .retrieval)

            // Replace key terms with synonyms (limited to keep the query compact).
            for (term, syns) in synonyms {
                for syn in syns.prefix(2) {
                    let expanded = original.replacingOccurrences(of: term, with: syn, options: .caseInsensitive)
                    if expanded != original {
                        variations.append(expanded)
                    }
                }
            }

            // Append a few synonyms (bag-of-words style).
            let allSynonyms = synonyms.values.flatMap { $0 }.prefix(3)
            if !allSynonyms.isEmpty {
                variations.append("\(original) \(allSynonyms.joined(separator: " "))")
            }
        }

        // 4) Simple question reformulations.
        if original.contains("?") {
            variations.append(contentsOf: reformulateQuestion(original))
        }

        let result = uniquePreservingOrder(variations, max: 12)
        Log.debug("[QueryEnhancement] Produced \(result.count) variations", category: .retrieval)
        return result
    }

    /// Extracts key terms (nouns/verbs/adjectives) using `NaturalLanguage`.
    private func extractKeyTerms(_ query: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType])
        tagger.string = query

        var terms: [String] = []
        var seen = Set<String>()

        tagger.enumerateTags(
            in: query.startIndex..<query.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            // NOTE: NLTagger.Options no longer includes `.omitStopWords` on newer SDKs.
            // We already filter by lexical class (noun/verb/adjective), which naturally
            // excludes most stop words.
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, range in
            guard let tag else { return true }
            guard tag == .noun || tag == .verb || tag == .adjective else { return true }

            let token = String(query[range])
            guard token.count > 2 else { return true }

            let key = token.lowercased()
            if seen.insert(key).inserted {
                terms.append(token)
            }
            return true
        }

        return terms
    }

    /// Very small, domain-oriented synonym map.
    ///
    /// This is intentionally conservative (no heavy NLP / embeddings) to keep expansion cheap.
    private func generateSynonyms(for terms: [String]) -> [String: [String]] {
        var result: [String: [String]] = [:]

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
            "warning": ["caution", "alert", "notice", "advisory"],
        ]

        for term in terms {
            let lower = term.lowercased()
            if let syns = synonymDict[lower], !syns.isEmpty {
                result[term] = syns
            }
        }

        return result
    }

    /// Reformulates common question patterns into statement/keyword forms.
    private func reformulateQuestion(_ query: String) -> [String] {
        var reformulations: [String] = []

        let patterns: [(pattern: String, replacement: String)] = [
            ("^How do I ", "instructions for "),
            ("^How to ", "procedure for "),
            ("^What is ", "information about "),
            ("^What are ", "details on "),
            ("^When should ", "timing for "),
            ("^Why ", "reason for "),
            ("^Can I ", "possibility of "),
            ("^Where ", "location of "),
        ]

        for (pattern, replacement) in patterns {
            if let range = query.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                var s = query
                s.replaceSubrange(range, with: replacement)
                s = s.replacingOccurrences(of: "?", with: "")
                reformulations.append(s)
            }
        }

        return reformulations
    }

    /// De-duplicates case-insensitively while preserving order.
    private func uniquePreservingOrder(_ strings: [String], max: Int) -> [String] {
        var seen = Set<String>()
        var out: [String] = []

        for s in strings {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                out.append(trimmed)
                if out.count >= max {
                    break
                }
            }
        }
        return out
    }
}
