//
//  RAGService+SentenceExtraction.swift
//  OpenIntelligence
//
//  Part of RAGService, moved unchanged from RAGService.swift on 2026-11-05 (5.8 split).
//

import Combine
import CryptoKit
import Foundation
import NaturalLanguage
import PDFKit

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    // For `NSApplication.isActive`, the AppKit equivalent of the foreground check that gates
    // Private Cloud Compute. Without it the macOS branch had no foreground check at all.
    import AppKit
#endif

#if canImport(FoundationModels)
    import FoundationModels
#endif

extension RAGService {
    // MARK: - Sentence-Level Extraction for Lookup Queries

    /// Result from sentence-level extraction
    struct SentenceExtractionResult: Sendable {
        let context: String
        let sourcesUsed: Int
        let sentencesIncluded: Int

        /// Indices into the `candidates` array whose sentences actually reached the context.
        ///
        /// Needed because a caller that labels these sources `[Sn]` must also be able to attach the
        /// same chunks to the response. Returning only a count let the needle-rescue path put
        /// sentences from dropped chunks into the prompt while the response carried none of them,
        /// so any citation the model made against those sentences resolved to nothing.
        let usedSourceIndices: [Int]

        nonisolated static let empty = SentenceExtractionResult(
            context: "", sourcesUsed: 0, sentencesIncluded: 0, usedSourceIndices: []
        )
    }

    /// Extracts query-relevant sentences from ALL candidate chunks and packs them
    /// into the context budget.  Instead of fitting 3 whole chunks (and hoping
    /// the answer is in one of them), this fits targeted lines from 10-15+ chunks.
    ///
    /// Universal across all domains — works for any document type.  Uses simple
    /// keyword + spec-pattern matching to score individual sentences.
    /// - Parameter leadingCandidateWhole: put the first candidate in whole, as `[S1]`, before any
    ///   chosen sentence (see `extractRelevantSentencesOffMain`).
    func extractRelevantSentences(
        from candidates: [RetrievedChunk],
        query: String,
        maxChars: Int,
        compact: Bool,
        isExtractiveFirst: Bool = false,
        labelOffset: Int = 0,
        leadingCandidateWhole: Bool = false,
        numberByUse: Bool = false
    ) async -> SentenceExtractionResult {
        let extractionTask = Task.detached(priority: .utility) {
            Self.extractRelevantSentencesOffMain(
                from: candidates,
                query: query,
                maxChars: maxChars,
                compact: compact,
                isExtractiveFirst: isExtractiveFirst,
                labelOffset: labelOffset,
                leadingCandidateWhole: leadingCandidateWhole,
                numberByUse: numberByUse
            )
        }

        return await withTaskCancellationHandler {
            await extractionTask.value
        } onCancel: {
            extractionTask.cancel()
        }
    }

    /// How many tokens of passages graph packing gathers for an investigate, compare or findings question (5.7).
    ///
    /// It was 6,000 on every device. Graph packing returns its passages in document order, with the context passages
    /// it adds scored 0.3, and `assembleContext` then fills the window in that order (after the lost-in-the-middle
    /// reorder, which assumes relevance order). On a device whose window is 4,096 tokens, about 3,190 tokens (4,470
    /// characters) are left for passages, measured on the owner's iPhone 16 Pro Max (`Context budget: base=4096 ...
    /// available=3190`, 2026-10-16), so roughly half of a 6,000-token pack was cut by position rather than relevance.
    /// Three quarters of the window fits what is left after the instructions and the question; at 8,192 or more the
    /// budget stays 6,000, as before. A device that reports no window counts as 4,096.
    nonisolated static func graphPackingTokenBudget(windowTokens: Int) -> Int {
        let window = windowTokens > 0 ? windowTokens : FoundationModelTokenBudget.baseContextLength
        return min(6000, max(1500, window * 3 / 4))
    }

    /// The candidates with the passage retrieval ranked first in front, the rest in the order given
    /// (5.7). The extractive ordering sorts by the question's words, and must not move retrieval's
    /// best passage out of the context: see `extractRelevantSentencesOffMain`.
    nonisolated static func leadingWithTopRanked(_ top: RetrievedChunk?, then ordered: [RetrievedChunk])
        -> [RetrievedChunk]
    {
        guard let top else { return ordered }
        return [top] + ordered.filter { $0.chunk.id != top.chunk.id }
    }

    private nonisolated static func extractRelevantSentencesOffMain(
        from candidates: [RetrievedChunk],
        query: String,
        maxChars: Int,
        compact: Bool,
        isExtractiveFirst: Bool,
        labelOffset: Int = 0,
        leadingCandidateWhole: Bool = false,
        numberByUse: Bool = false
    ) -> SentenceExtractionResult {
        if Task.isCancelled {
            return .empty
        }

        // The passage retrieval ranked first goes in whole, ahead of every chosen sentence (5.7).
        // Sentences are chosen by the question's words, and a passage can answer a question without
        // repeating them. On 2026-10-15 "What happened on September 30" had the September 30 section
        // of a monthly log ranked first; its lines name people and events, not "happened", and the
        // date is in its heading, so the sentences chosen came from September 24 and 25 and the model
        // was told nothing about the 30th. It takes at most three fifths of the budget, cut at a line
        // or a sentence end; chosen sentences from the other passages fill the rest.
        let leadEntry: (label: String, body: String)? = {
            guard leadingCandidateWhole, let lead = candidates.first else { return nil }
            let sectionTag: String
            if let section = lead.chunk.metadata.sectionTitle, !section.isEmpty {
                sectionTag = " \(section) —"
            } else {
                sectionTag = ""
            }
            let label: String
            if compact {
                let filename = URL(fileURLWithPath: lead.sourceDocument).lastPathComponent
                label = "[S\(1 + labelOffset)]\(sectionTag) (\(filename))"
            } else {
                let page = lead.pageNumber.map { " p.\($0)" } ?? ""
                label = "[S\(1 + labelOffset)]\(sectionTag) \(lead.sourceDocument)\(page)"
            }
            var body = lead.chunk.contextText.trimmingCharacters(in: .whitespacesAndNewlines)
            let room = maxChars * 3 / 5 - label.count - 1
            if body.count > room {
                let head = room > 0 ? String(body.prefix(room)) : ""
                if let lineEnd = head.lastIndex(of: "\n") {
                    body = String(head[..<lineEnd])
                } else if let stop = head.lastIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) {
                    body = String(head[...stop])
                } else {
                    body = head
                }
            }
            return body.isEmpty ? nil : (label, body)
        }()
        let leadBodyLower = leadEntry?.body.lowercased() ?? ""

        // Keep sentence-scoring resources local to this detached task.
        // Shared static Set/regex storage has proven crash-prone on the utility queue.
        let lexicalStopWords: Set<String> = [
            "a", "an", "the", "is", "are", "was", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did", "will", "would", "could", "should",
            "may", "might", "must", "shall", "can", "need", "dare", "ought", "used",
            "to", "of", "in", "for", "on", "with", "at", "by", "from", "as", "into",
            "through", "during", "before", "after", "above", "below", "between",
            "under", "again", "further", "then", "once", "here", "there", "when",
            "where", "why", "how", "all", "each", "few", "more", "most", "other",
            "some", "such", "no", "nor", "not", "only", "own", "same", "so", "than",
            "too", "very", "just", "also", "now", "what", "which", "who", "whom",
            "this", "that", "these", "those", "am", "it", "its", "i", "me", "my",
            "myself", "we", "our", "ours", "ourselves", "you", "your", "yours",
            "he", "him", "his", "she", "her", "hers", "they", "them", "their",
        ]
        let sentenceUnitRegex = try? NSRegularExpression(
            pattern:
                #"\d+(?:\.\d+)?\s*(?:qt|quart|gal|gallon|L|liter|litre|ml|oz|fl|kg|g|lb|lbs|mg|mcg|ug|mm|cm|m|km|in|ft|yd|mi|psi|kPa|MPa|bar|atm|rpm|hp|kW|MW|GW|Hz|kHz|MHz|GHz|TB|GB|MB|KB|V|mV|A|mA|W|kWh|MWh|Ah|mAh|cal|kcal|kJ|MJ|BTU|dB|dBm|lux|lm|cd|mol|IU|%)\b"#,
            options: .caseInsensitive
        )
        let sentenceSpecCodeRegex = try? NSRegularExpression(
            pattern:
                #"\b(?:API|ISO|SAE|ACEA|ASTM|IEEE|ANSI|IEC|NIST|OSHA|EPA|FDA|WHO|USP|NF|BP|JP|MIL-|SPEC-|UL|CE|FCC|RoHS|REACH|GMP|HACCP|NFPA|ASHRAE|ACI|AISI|AISC|AWS|ASME|DOT|FMVSS|ECE|JIS|DIN|EN|BS|AS|NZS|CSA|CAN|GB|GB/T)\s*[A-Z0-9./-]+"#
        )
        let sentenceStructuredCodeRegex = try? NSRegularExpression(
            pattern: #"\b[A-Z0-9]{1,6}[-./][A-Z0-9]{1,6}(?:[-./][A-Z0-9]{1,6})?\b"#
        )

        func meaningfulSentenceTokens(from lowercasedText: String) -> Set<String> {
            var tokens = Set<String>()
            tokens.reserveCapacity(16)

            for rawToken in lowercasedText.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                guard Self.isEvidenceKeyword(rawToken) else { continue }

                let token = String(rawToken)
                guard !lexicalStopWords.contains(token) else { continue }
                tokens.insert(token)
            }

            return tokens
        }

        /// Crude suffix stripper, applied identically to both sides of every comparison.
        ///
        /// This is not linguistics, it is agreement. FTS5 indexes with `porter unicode61`, so
        /// retrieval matches "reprocessed" and "reprocess" to a query saying "reprocessing".
        /// Sentence selection below then compared raw substrings, so it discarded the very
        /// sentences retrieval had just found and kept only lines containing the literal query
        /// token. On a numbered technical manual the only such line is the section heading, which
        /// is how an eight-session Deep Think chain came to reason over a table of contents.
        ///
        /// Symmetry is what matters here, not correctness: over-stemming "series" to "seri" costs
        /// nothing as long as the query side is stemmed the same way. The 4-character floor stops
        /// short words collapsing into each other.
        func lexicalStem(_ token: String) -> String {
            var stem = token
            // Longest first, so "ing" cannot pre-empt "ingly" and "s" cannot pre-empt "ies".
            for suffix in ["ingly", "edly", "ings", "ing", "ies", "ied", "ed", "es", "s"] {
                if stem.count - suffix.count >= 4, stem.hasSuffix(suffix) {
                    stem.removeLast(suffix.count)
                    break
                }
            }
            return stem
        }

        // Extract discriminative query keywords
        let queryLower = query.lowercased()
        let queryKeywords =
            queryLower
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { Self.isEvidenceKeyword($0) && !lexicalStopWords.contains($0) }

        guard !queryKeywords.isEmpty else {
            // Fallback: no usable keywords, return empty
            return .empty
        }
        let queryWordSet = Set(queryKeywords)
        // Parallel to `queryKeywords` by index, so a keyword can hit on either form.
        let queryStems = queryKeywords.map(lexicalStem)

        func sentenceScore(
            line: String,
            headingContext: String,
            chunkIndex: Int,
            isExtractiveFirst: Bool
        ) -> Double? {
            let lineLower = line.lowercased()
            let headingLower = headingContext.lowercased()
            let lineWords = meaningfulSentenceTokens(from: lineLower)

            if !lineWords.isEmpty && !queryWordSet.isEmpty {
                let overlap = lineWords.intersection(queryWordSet).count
                let lineUnique = lineWords.subtracting(queryWordSet).count
                if overlap >= queryWordSet.count && lineUnique <= 1 {
                    return nil
                }
            }

            // A keyword hits on the raw substring, which is what this always did, or on a stem
            // match, which is new. Additive on purpose: every line that scored before still
            // scores, and lines that previously failed only on inflection now score too. That
            // asymmetry between a stemmed index and an unstemmed filter is what emptied the
            // reasoning context on device.
            let lineStems = Set(lineWords.map(lexicalStem))
            let headingStems = Set(meaningfulSentenceTokens(from: headingLower).map(lexicalStem))

            var directHits = 0
            var headingHits = 0
            for (index, keyword) in queryKeywords.enumerated() {
                let stem = queryStems[index]
                if lineLower.contains(keyword) || lineStems.contains(stem) {
                    directHits += 1
                }
                if headingLower.contains(keyword) || headingStems.contains(stem) {
                    headingHits += 1
                }
            }

            let totalKeywordHits = directHits + headingHits
            guard totalKeywordHits > 0 else { return nil }

            let specBoostMultiplier: Double = isExtractiveFirst ? 2.5 : 1.0
            let hasNumbers = line.rangeOfCharacter(from: .decimalDigits) != nil
            let numberBonus: Double = hasNumbers ? 2.0 : 0.0

            let unitHits =
                sentenceUnitRegex?
                .numberOfMatches(in: line, range: NSRange(line.startIndex..., in: line)) ?? 0
            let unitBonus = Double(min(unitHits, 3)) * 1.5 * specBoostMultiplier

            let specHits =
                sentenceSpecCodeRegex?
                .numberOfMatches(in: line, range: NSRange(line.startIndex..., in: line)) ?? 0
            let specBonus = Double(min(specHits, 3)) * 2.0 * specBoostMultiplier

            let keyValueBonus: Double = (line.contains(":") && hasNumbers) ? 1.5 * specBoostMultiplier : 0.0

            let codeHits =
                sentenceStructuredCodeRegex?
                .numberOfMatches(in: line, range: NSRange(line.startIndex..., in: line)) ?? 0
            let codeBonus = Double(min(codeHits, 3)) * 1.5 * specBoostMultiplier

            let rankBonus = max(0.0, 1.0 - Double(chunkIndex) * 0.05)
            let keywordScore = Double(directHits) * 3.0 + Double(headingHits) * 2.0
            let coverageFraction = Double(totalKeywordHits) / Double(max(1, queryKeywords.count))
            let coveragePenalty: Double = (queryKeywords.count >= 2 && coverageFraction < 0.5) ? 0.4 : 1.0

            return (keywordScore + numberBonus + unitBonus + specBonus + keyValueBonus + codeBonus + rankBonus)
                * coveragePenalty
        }

        // Score every sentence across all candidates
        struct ScoredSentence {
            let text: String  // The sentence/line itself
            let headingContext: String  // The heading above this line (if any)
            let score: Double
            let sourceIndex: Int  // which chunk it came from
            let sourceDoc: String
            let pageNumber: Int?
        }

        var scoredSentences: [ScoredSentence] = []

        for (chunkIdx, candidate) in candidates.enumerated() {
            if Task.isCancelled {
                return .empty
            }
            // The leading passage is in already, whole.
            if leadEntry != nil && chunkIdx == 0 { continue }

            let content = candidate.chunk.contextText
            let source = candidate.sourceDocument
            let page = candidate.pageNumber

            // Split into individual lines first (preserve line order for heading tracking). A
            // sentence wrapped over two lines is joined back so it is scored and kept whole.
            let rawLines = EvidenceLineSplitter.lines(in: content)

            // Track the most recent heading-like line for context inheritance.
            // A "heading" is a short line (≤80 chars) without numbers that acts
            // as a section label in spec tables.  Universal across all documents.
            // Seed from the section the chunker already resolved, rather than starting blank and
            // hoping a text heuristic rediscovers it. `sectionTitle` is the same field FTS5 ranks
            // at a bm25 weight of 10.0, so it is already trusted elsewhere in the pipeline; this
            // function was the one place re-deriving it from raw text. The heuristic below still
            // runs, and still wins for chunks whose own section is absent or that span sections.
            var currentHeading =
                candidate.chunk.metadata.sectionTitle?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            for (lineIdx, rawLine) in rawLines.enumerated() {
                // Detect heading lines: short labels, not data rows.
                //
                // The digit test is applied to the line with any leading section number removed.
                // Applying it to the whole line rejected every heading in a numbered technical
                // document: "4 Reprocessing" and "4.5.1 Overview" both contain digits, so neither
                // became `currentHeading`, and no sentence beneath them could inherit the section's
                // keywords. That is half of why a query whose answer sat under "4 Reprocessing"
                // retrieved the section and then passed only its title downstream.
                let headingBody = rawLine.replacingOccurrences(
                    of: #"^\d+(?:\.\d+)*[.)]?\s+"#,
                    with: "",
                    options: .regularExpression
                )
                let isHeading =
                    rawLine.count <= 80
                    && !headingBody.isEmpty
                    && headingBody.rangeOfCharacter(from: .decimalDigits) == nil
                    && !rawLine.contains("|")
                    && !rawLine.hasSuffix(".")

                if isHeading {
                    currentHeading = rawLine
                }

                // Split line into sub-sentences if it's prose (not table/spec data). Table rows stay
                // whole, and a sentence is never cut inside "p.m." or an amount.
                let subLines = EvidenceLineSplitter.units(in: rawLine)

                for subLine in subLines {
                    if Task.isCancelled {
                        return .empty
                    }

                    guard subLine.count > 5 else { continue }
                    // A line the leading passage already gives, from a neighbouring passage.
                    if !leadBodyLower.isEmpty, leadBodyLower.contains(subLine.lowercased()) { continue }
                    var headingContext = ""
                    if !isHeading {
                        headingContext = currentHeading
                        if headingContext.isEmpty && lineIdx > 0 {
                            headingContext = rawLines[lineIdx - 1]
                        }
                    }

                    guard
                        let totalScore = sentenceScore(
                            line: subLine,
                            headingContext: headingContext,
                            chunkIndex: chunkIdx,
                            isExtractiveFirst: isExtractiveFirst
                        )
                    else { continue }

                    let subLineLower = subLine.lowercased()
                    let headingLower = headingContext.lowercased()
                    let directHits = queryKeywords.reduce(0) { partialResult, keyword in
                        partialResult + (subLineLower.contains(keyword) ? 1 : 0)
                    }
                    let headingHits = queryKeywords.reduce(0) { partialResult, keyword in
                        partialResult + (headingLower.contains(keyword) ? 1 : 0)
                    }

                    // Determine heading context to include when packing
                    let effectiveHeading: String
                    if directHits == 0 && headingHits > 0 && !currentHeading.isEmpty {
                        // Line only matches via heading — include heading for context
                        effectiveHeading = currentHeading
                    } else {
                        effectiveHeading = ""
                    }

                    scoredSentences.append(
                        ScoredSentence(
                            text: subLine,
                            headingContext: effectiveHeading,
                            score: totalScore,
                            sourceIndex: chunkIdx,
                            sourceDoc: source,
                            pageNumber: page
                        ))
                }
            }
        }

        // Sort by score descending
        scoredSentences.sort { $0.score > $1.score }

        // Deduplicate: remove near-identical sentences (same text, different chunks)
        // Phase 1: Exact-match dedup (fast, O(n))
        var seen: Set<String> = []
        scoredSentences = scoredSentences.filter { s in
            let key = s.text.lowercased().filter { $0.isLetter || $0.isNumber }
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }

        // Phase 2: Fuzzy dedup using Jaccard word-set similarity
        // Catches near-duplicate sentences like "activated when the driver presses the Mode button"
        // vs "activated by pressing the Mode button" that share >70% of meaningful words.
        // O(n*m) where n=candidates, m=kept — acceptable since n is typically <100 after Phase 1.
        do {
            var keptSentences: [ScoredSentence] = []
            // Pre-compute word sets for kept sentences to avoid recomputation
            var keptWordSets: [Set<String>] = []

            for sentence in scoredSentences {
                if Task.isCancelled {
                    return .empty
                }

                let words = Set(
                    sentence.text.lowercased()
                        .components(separatedBy: CharacterSet.alphanumerics.inverted)
                        .filter { $0.count > 2 && !lexicalStopWords.contains($0) }
                )
                // Very short sentences: skip fuzzy dedup (not enough signal)
                guard words.count >= 3 else {
                    keptSentences.append(sentence)
                    keptWordSets.append(words)
                    continue
                }

                var isDuplicate = false
                for (idx, keptWords) in keptWordSets.enumerated() {
                    guard keptWords.count >= 3 else { continue }
                    let intersection = words.intersection(keptWords).count
                    let union = words.union(keptWords).count
                    let jaccard = Double(intersection) / Double(max(1, union))
                    if jaccard > 0.70 {
                        if Self.shouldKeepBothExactSentences(sentence.text, keptSentences[idx].text) {
                            continue
                        }
                        // Keep the higher-scoring one
                        if sentence.score > keptSentences[idx].score {
                            keptSentences[idx] = sentence
                            keptWordSets[idx] = words
                        }
                        isDuplicate = true
                        break
                    }
                }
                if !isDuplicate {
                    keptSentences.append(sentence)
                    keptWordSets.append(words)
                }
            }
            scoredSentences = keptSentences
        }

        // Pack into context budget
        var builder = String()
        builder.reserveCapacity(min(maxChars, 5000))
        var sourcesUsed: Set<Int> = []
        // The sources in the order their blocks are written, which is the order `numberByUse` numbers them.
        var packedOrder: [Int] = []
        var sentenceCount = 0
        let headerOverhead = compact ? 30 : 80
        let separatorSize = compact ? 5 : 7

        if let leadEntry {
            builder += leadEntry.label + "\n" + leadEntry.body + "\n"
            sourcesUsed.insert(0)
            packedOrder.append(0)
            sentenceCount += EvidenceLineSplitter.lines(in: leadEntry.body).count
        }

        // Group sentences by source into prose paragraphs (not one-per-line lists).
        // When each sentence is its own line, the FM regurgitates them as bullet lists.
        // Joining them with ". " creates natural paragraphs the FM will synthesize from.
        // Track per-source sentence buffers so same-source sentences merge into one block.
        var sourceBuffers: [Int: [String]] = [:]  // sourceIndex → [sentences]
        var sourceOrder: [Int] = []  // Track order of first appearance
        var sourceLabels: [Int: String] = [:]  // sourceIndex → label

        for sentence in scoredSentences {
            if Task.isCancelled {
                return .empty
            }

            let displayText =
                sentence.headingContext.isEmpty
                ? sentence.text
                : "\(sentence.headingContext) > \(sentence.text)"

            if sourceBuffers[sentence.sourceIndex] == nil {
                sourceOrder.append(sentence.sourceIndex)
                // Build source label — include section title so the LLM knows
                // what topic/metric each source covers. Critical for health data
                // and structured documents where compression strips headers,
                // leaving decontextualized data lines like "2024: 1,821 records,
                // avg 71.6 ms" with no indication of which metric they belong to.
                let sectionTag: String
                if sentence.sourceIndex < candidates.count,
                    let section = candidates[sentence.sourceIndex].chunk.metadata.sectionTitle,
                    !section.isEmpty
                {
                    sectionTag = " \(section) —"
                } else {
                    sectionTag = ""
                }
                // With `numberByUse` the number is filled in after packing (`numberedLabels`), once it is known which
                // sources made it: each is numbered by its place among the sources used, in the order
                // `usedSourceIndices` returns, for a caller that keeps only those (the Standard path and its needle
                // rescue). Without it the number is the candidate's place plus `labelOffset`, for a caller that keeps
                // every candidate (Deep Think's windows, numbered over all routed passages).
                let number =
                    numberByUse
                    ? labelPlaceholder(sentence.sourceIndex) : "\(sentence.sourceIndex + 1 + labelOffset)"
                if compact {
                    let filename = URL(fileURLWithPath: sentence.sourceDoc).lastPathComponent
                    sourceLabels[sentence.sourceIndex] = "[S\(number)]\(sectionTag) (\(filename))"
                } else {
                    let page = sentence.pageNumber.map { " p.\($0)" } ?? ""
                    sourceLabels[sentence.sourceIndex] = "[S\(number)]\(sectionTag) \(sentence.sourceDoc)\(page)"
                }
            }
            sourceBuffers[sentence.sourceIndex, default: []].append(displayText)
        }

        // Pack source paragraphs into budget
        for srcIdx in sourceOrder {
            if Task.isCancelled {
                return .empty
            }

            guard let sentences = sourceBuffers[srcIdx],
                let label = sourceLabels[srcIdx]
            else { continue }

            // Join sentences into a prose paragraph
            let paragraph = sentences.map { sent in
                // Ensure sentence ends with period for natural flow
                let trimmed = sent.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") || trimmed.hasSuffix(":")
                {
                    return trimmed
                }
                return trimmed + "."
            }.joined(separator: " ")

            let entry = label + "\n" + paragraph + "\n"
            let overhead = headerOverhead + separatorSize

            if builder.count + entry.count + overhead <= maxChars {
                if !sourcesUsed.isEmpty {
                    builder += compact ? "\n---\n" : "\n\n---\n\n"
                }
                builder += entry
                if sourcesUsed.insert(srcIdx).inserted { packedOrder.append(srcIdx) }
                sentenceCount += sentences.count
            } else {
                // Try fitting partial sentences from this source
                let remaining = maxChars - builder.count - overhead - label.count - 2
                if remaining > 50 && sourcesUsed.isEmpty || remaining > 100 {
                    var partial: [String] = []
                    var partialLen = 0
                    for sent in sentences {
                        if partialLen + sent.count + 2 > remaining { break }
                        partial.append(sent)
                        partialLen += sent.count + 2
                    }
                    if !partial.isEmpty {
                        let partialParagraph = partial.joined(separator: " ")
                        if !sourcesUsed.isEmpty {
                            builder += compact ? "\n---\n" : "\n\n---\n\n"
                        }
                        builder += label + "\n" + partialParagraph + "\n"
                        if sourcesUsed.insert(srcIdx).inserted { packedOrder.append(srcIdx) }
                        sentenceCount += partial.count
                    }
                }
                break
            }
        }

        // With `numberByUse` the sources are numbered in the order the context reads them ([S1], [S2], [S3] down the
        // page) and returned in that order, the order the caller keeps them in. The blocks are written by relevance
        // (each source's best sentence first), so numbered in candidate order the labels read [S1], [S8], [S9], [S6]
        // down the page (5.7; Docs/ai/DECISIONS.md, 2026-10-20). Without `numberByUse` a label is the candidate's
        // place, so the order stays the candidates' (Deep Think's windows).
        let usedSourceIndices = numberByUse ? packedOrder : sourcesUsed.sorted()
        return SentenceExtractionResult(
            context: numberByUse
                ? numberedLabels(in: builder, usedSourceIndices: usedSourceIndices, labelOffset: labelOffset) : builder,
            sourcesUsed: sourcesUsed.count,
            sentencesIncluded: sentenceCount,
            // The caller's passages, in the order the labels number them.
            usedSourceIndices: usedSourceIndices
        )
    }

    /// `context` with its "Cite only ..." line (written by `RAGEngine` after the packed sources) removed and restated at
    /// the end for `sources` sources (5.8): sources rescued after the packed block are numbered past its bound.
    nonisolated static func withCitationBound(_ context: String, sources: Int) -> String {
        let stripped = context.replacingOccurrences(
            of: #"\n\nCite only (source S1|sources S1 to S\d+)\."#, with: "", options: .regularExpression)
        guard sources > 0 else { return stripped }
        return stripped + (sources == 1 ? "\n\nCite only source S1." : "\n\nCite only sources S1 to S\(sources).")
    }

    /// The candidates the whole-chunk assembler did not reach, which is what the needle rescue reads. It packs in
    /// rank order, skipping near-duplicates, and stops at the first passage that does not fit, so these are the ones
    /// after where it stopped: the ones the budget cut, and any near-duplicates skipped after the last one packed. A
    /// later copy of a packed passage is not where it stopped and is not read again. `dropFirst(assembled.used)`
    /// counted the skipped near-duplicates as packed, so it handed the rescue passages already in the prompt, and
    /// while the assembler reordered every candidate before the cut (to 2026-10-20) it also left out the second-best
    /// passage, which the reordering had put last.
    nonisolated static func candidatesPastThePacked(
        _ candidates: [RetrievedChunk], packed: [RetrievedChunk]
    ) -> [RetrievedChunk] {
        let packedIDs = Set(packed.map(\.chunk.id))
        let stop = packed.compactMap { kept in candidates.firstIndex { $0.chunk.id == kept.chunk.id } }.max() ?? -1
        return candidates[(stop + 1)...].filter { !packedIDs.contains($0.chunk.id) }
    }

    /// Each passage's place among the candidates, from 1, in the order given (5.7). The trace line that uses it shows
    /// which candidates a whole-passage context kept and where it put them: "candidates [1, 3, 4, 2]" is the first
    /// four, placed best first and second best last.
    nonisolated static func candidatePlaces(of passages: [RetrievedChunk], in candidates: [RetrievedChunk]) -> [Int] {
        passages.compactMap { passage in candidates.firstIndex { $0.chunk.id == passage.chunk.id }.map { $0 + 1 } }
    }

    /// The passages a cloud envelope carries, in its order, which is the order its [S1], [S2] ... labels number them
    /// (`renderCloudEvidenceEnvelope`); a passage it left out is dropped (5.7). The envelope orders its evidence by
    /// rank, so the local order filtered by the envelope could put a different passage at a label's place.
    nonisolated static func passages(
        _ chunks: [RetrievedChunk], inTheOrderOf envelope: CloudEvidenceEnvelope
    ) -> [RetrievedChunk] {
        var byID: [String: RetrievedChunk] = [:]
        for chunk in chunks where byID[chunk.chunk.id.uuidString] == nil {
            byID[chunk.chunk.id.uuidString] = chunk
        }
        return envelope.evidence.compactMap { byID[$0.sourceID] }
    }

    /// A label number not yet known: the candidate's index between two private-use characters.
    private nonisolated static func labelPlaceholder(_ sourceIndex: Int) -> String {
        "\u{E000}\(sourceIndex)\u{E001}"
    }

    /// The context with each source's label numbered by its place in `usedSourceIndices` (5.7), for a caller that
    /// keeps only those sources, in that order. The Standard path numbered by candidate while keeping only the used sources, numbered from
    /// one: on 2026-10-20 a pet-deposit question drew sentences from candidates 1, 5 and 6, the model was shown [S1],
    /// [S5] and [S6], cited all three correctly, and the answer's passages numbered 1 to 3 opened [S1] only. The
    /// needle rescue's labels, which start at `labelOffset`, skipped numbers the same way.
    nonisolated static func numberedLabels(in context: String, usedSourceIndices: [Int], labelOffset: Int) -> String {
        var numbered = context
        for (place, sourceIndex) in usedSourceIndices.enumerated() {
            numbered = numbered.replacingOccurrences(
                of: labelPlaceholder(sourceIndex), with: "\(place + 1 + labelOffset)")
        }
        return numbered
    }

    private nonisolated static func exactSentenceAnchorTokens(from text: String) -> Set<String> {
        let lower = text.lowercased()
        var tokens = Set<String>()
        let pattern =
            #"\b(?:\d+(?:[.,]\d+)?(?:\s*[-~/]\s*\d+(?:[.,]\d+)?)?(?:\s*(?:us\s*)?(?:gal(?:lon)?s?|l(?:iter)?s?|qt|quarts?|ml|kg|g|lb?s?|oz|mm|cm|m|km|mi|mph|km/h|psi|kpa|bar|°c|°f|%))?|[0o]w-\d{2}|75w/\d{2}|level\s*[123]|full open|user height setting|auto open|api\s+[a-z0-9 +/\-]+|ilsac\s+[a-z0-9\-]+|dot-4|gl-5)\b"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
            for match in regex.matches(in: lower, options: [], range: range) {
                guard let tokenRange = Range(match.range, in: lower) else { continue }
                tokens.insert(String(lower[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return tokens
    }

    private nonisolated static func shouldKeepBothExactSentences(_ lhs: String, _ rhs: String) -> Bool {
        let lhsTokens = exactSentenceAnchorTokens(from: lhs)
        let rhsTokens = exactSentenceAnchorTokens(from: rhs)

        guard !lhsTokens.isEmpty || !rhsTokens.isEmpty else { return false }
        return lhsTokens != rhsTokens
    }

}
