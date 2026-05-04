//
//  EvidenceScoringPolicyService.swift
//  OpenIntelligence
//
//  Centralized evidence scoring rules for extractive retrieval, sentence
//  selection, and precision-lock decisions.
//

import Foundation

enum EvidenceScoringPolicyService {
    nonisolated private static func isSentenceStopWord(_ token: String) -> Bool {
        switch token {
        case "a", "an", "the", "is", "are", "was", "were", "be", "been", "being",
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
             "he", "him", "his", "she", "her", "hers", "they", "them", "their":
            return true
        default:
            return false
        }
    }

    nonisolated private static let crossReferenceIndicators = [
        "given in", "refer to", "see page", "found in", "listed in", "shown in",
        "specified in", "provided in"
    ]

    nonisolated private static let stateIndicatorTerms = [
        "light", "lights", "indicator", "indicators", "led", "status", "signal"
    ]

    nonisolated private static let stateTerms = [
        "solid", "flashing", "flash", "blink", "blinking", "steady", "pulsing", "rapid", "slow"
    ]

    nonisolated private static let stateColors = [
        "red", "green", "blue", "yellow", "amber", "orange", "purple", "white", "cyan", "magenta"
    ]

    nonisolated static func precisionLockThreshold(forceExtractiveAttempt: Bool) -> Float {
        forceExtractiveAttempt ? 0.90 : 0.82
    }

    nonisolated static func isStateLookupQuery(_ query: String) -> Bool {
        let lower = query.lowercased()
        let hasIndicatorTerm = stateIndicatorTerms.contains { lower.contains($0) }
        let hasStateTerm = stateTerms.contains { lower.contains($0) }
        let hasColor = stateColors.contains { color in
            lower.range(of: #"\b\#(color)\b"#, options: .regularExpression) != nil
        }

        return hasIndicatorTerm && (hasStateTerm || hasColor)
    }

    nonisolated static func stateLookupAnchors(from query: String) -> (colors: [String], states: [String]) {
        let lower = query.lowercased()
        let colors = stateColors.filter { color in
            lower.range(of: #"\b\#(color)\b"#, options: .regularExpression) != nil
        }
        let states = stateTerms.filter { lower.contains($0) }
        return (colors, states)
    }

    nonisolated static func satisfiesStateLookupAnchors(query: String, content: String) -> Bool {
        let anchors = stateLookupAnchors(from: query)
        let lowerContent = content.lowercased()

        if !anchors.colors.isEmpty && !anchors.colors.contains(where: { lowerContent.contains($0) }) {
            return false
        }

        if !anchors.states.isEmpty && !anchors.states.contains(where: { lowerContent.contains($0) }) {
            return false
        }

        return true
    }

    nonisolated static func stateLookupAnchorAdjustment(
        query: String,
        content: String,
        structureType: String?
    ) -> Float {
        guard isStateLookupQuery(query) else { return 0 }

        let anchors = stateLookupAnchors(from: query)
        let lowerContent = content.lowercased()
        var adjustment: Float = 0

        if !anchors.colors.isEmpty {
            if anchors.colors.contains(where: { lowerContent.contains($0) }) {
                adjustment += 0.16
            } else {
                adjustment -= 0.18
            }
        }

        if !anchors.states.isEmpty {
            if anchors.states.contains(where: { lowerContent.contains($0) }) {
                adjustment += 0.08
            } else {
                adjustment -= 0.08
            }
        }

        if isStructuredEvidence(text: content, structureType: structureType) {
            adjustment += 0.05
        }

        if stateIndicatorTerms.contains(where: { lowerContent.contains($0) }) {
            adjustment += 0.03
        }

        return adjustment
    }

    nonisolated static func hasQuantitativeSignal(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        let numberPattern = #"\b\d+(?:\.\d+)?\b"#
        guard normalized.range(of: numberPattern, options: .regularExpression) != nil else {
            return false
        }

        let unitPattern = #"\b(?:gal(?:lon)?s?|l(?:iter)?s?|ml|kg|g|lb?s?|oz|mm|cm|m|km|mi|mph|km/h|psi|kpa|bar|v|a|w|kw|hz|mhz|ghz|°c|°f|%)\b"#
        if normalized.lowercased().range(of: unitPattern, options: .regularExpression) != nil {
            return true
        }

        let specCodePattern = #"\b[A-Z]{1,6}[\s-]?\d+(?:\.\d+)?\b|\b\d+(?:\.\d+)?[A-Z]{1,4}\b"#
        return normalized.range(of: specCodePattern, options: .regularExpression) != nil
    }

    nonisolated static func specPatternCount(in content: String) -> Int {
        var score = 0

        let gradePattern = #"[A-Z0-9]+[-][A-Z0-9]+"#
        if let regex = try? NSRegularExpression(pattern: gradePattern, options: []) {
            score += regex.numberOfMatches(in: content, options: [], range: NSRange(content.startIndex..., in: content)) * 2
        }

        let measurementPattern = #"\d+(?:\.\d+)?\s*(?:L|ml|mm|cm|m|kg|g|psi|kPa|°[CF]|ft|in|lbs?)\b"#
        if let regex = try? NSRegularExpression(pattern: measurementPattern, options: .caseInsensitive) {
            score += regex.numberOfMatches(in: content, options: [], range: NSRange(content.startIndex..., in: content)) * 2
        }

        if content.contains(":") && content.rangeOfCharacter(from: .decimalDigits) != nil {
            score += 2
        }

        let specCodePattern = #"\b(?:API|ISO|IEEE|ANSI|ASTM|IEC|SAE|ACEA)\s*[A-Z0-9-]+"#
        if let regex = try? NSRegularExpression(pattern: specCodePattern, options: []) {
            score += regex.numberOfMatches(in: content, options: [], range: NSRange(content.startIndex..., in: content)) * 3
        }

        let numberPattern = #"\b\d+(?:\.\d+)?\b"#
        if let regex = try? NSRegularExpression(pattern: numberPattern, options: []) {
            score += min(5, regex.numberOfMatches(in: content, options: [], range: NSRange(content.startIndex..., in: content)))
        }

        return score
    }

    nonisolated static func isStructuredEvidence(text: String, structureType: String?) -> Bool {
        if structureType == "table" {
            return true
        }

        if text.contains("|") && text.components(separatedBy: "|").count >= 4 {
            return true
        }

        if text.contains("\t") {
            return true
        }

        let lines = text.split(separator: "\n").prefix(6)
        let structuredLines = lines.filter { line in
            let lineText = String(line)
            let hasNumbers = lineText.rangeOfCharacter(from: .decimalDigits) != nil
            let hasColumns = lineText.contains(":") || lineText.contains("  ") || lineText.contains("\t")
            return hasNumbers && hasColumns
        }

        return structuredLines.count >= 2
    }

    nonisolated static func correctiveRetrievalScore(
        content: String,
        queryTerms: [String],
        structureType: String?,
        baseScore: Float
    ) -> Float {
        let lowercased = content.lowercased()
        let matchingTerms = queryTerms.filter { lowercased.contains($0) }
        guard !matchingTerms.isEmpty else { return 0 }

        var score = baseScore
        let coverage = Float(matchingTerms.count) / Float(max(1, queryTerms.count))
        score += min(0.20, coverage * 0.20)
        score += min(0.12, Float(specPatternCount(in: content)) * 0.015)

        if isStructuredEvidence(text: content, structureType: structureType) {
            score += 0.08
        }
        if content.rangeOfCharacter(from: .decimalDigits) != nil {
            score += 0.05
        }
        if matchingTerms.count >= min(2, queryTerms.count) {
            score += 0.04
        }

        return min(score, 0.93)
    }

    nonisolated static func crossReferenceScoreFloor(isSpecificationHeavy: Bool) -> Float {
        isSpecificationHeavy ? 0.60 : 0.55
    }

    nonisolated static func crossReferenceSectionScore(
        content: String,
        structureType: String?,
        hasNumericData: Bool,
        isSpecificationHeavy: Bool,
        matchesFullSection: Bool,
        matchingWordCount: Int,
        totalSectionWordCount: Int
    ) -> Float? {
        if matchesFullSection {
            return 0.70
        }

        guard matchingWordCount >= max(2, totalSectionWordCount * 2 / 3) else {
            return nil
        }

        let hasTableIndicator = structureType == "table"
            || (content.contains("|") && content.components(separatedBy: "|").count >= 4)
        let rawScore: Float = (hasTableIndicator && hasNumericData) ? 0.65 : 0.55
        return max(rawScore, crossReferenceScoreFloor(isSpecificationHeavy: isSpecificationHeavy))
    }

    nonisolated static func crossReferencePageScore(
        content: String,
        structureType: String?,
        hasNumericData: Bool,
        isSpecificationHeavy: Bool,
        queryWordOverlap: Int
    ) -> Float {
        var score: Float = max(0.60, crossReferenceScoreFloor(isSpecificationHeavy: isSpecificationHeavy))

        if structureType == "table" {
            score += 0.15
        }
        if content.contains("|") && content.components(separatedBy: "|").count >= 4 {
            score += 0.10
        }
        if hasNumericData {
            score += 0.05
        }
        if queryWordOverlap > 0 {
            score += Float(queryWordOverlap) * 0.05
        }

        return score
    }

    nonisolated static func specSniperScore(
        content: String,
        structureType: String?,
        queryConceptAliases: [[String]]
    ) -> (score: Float, matchCount: Int)? {
        guard !queryConceptAliases.isEmpty else { return nil }

        let contentLower = content.lowercased()
        let matchingConceptCount = queryConceptAliases.filter { aliases in
            aliases.contains { alias in
                guard alias.count > 1 else { return false }
                return contentLower.contains(alias)
            }
        }.count

        let minRequired = min(2, queryConceptAliases.count)
        guard matchingConceptCount >= minRequired else { return nil }
        guard content.rangeOfCharacter(from: .decimalDigits) != nil else { return nil }

        var score: Float = 0.60
        let coverage = Float(matchingConceptCount) / Float(max(1, queryConceptAliases.count))
        score += coverage * 0.15

        if structureType == "table" {
            score += 0.10
        }
        if content.contains("|") && content.components(separatedBy: "|").count >= 4 {
            score += 0.08
        }

        let measurementPattern = #"\d+(?:\.\d+)?\s*(?:L|qt|gal|ml|mL|mg|g|kg|lb|oz|psi|kPa|bar|mm|cm|km|in|ft|yd|V|A|W|kW|mA|Ah|kWh|Hz|MHz|GHz|%|cc|cu)\b"#
        let hasMeasurement = content.range(
            of: measurementPattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        if hasMeasurement {
            score += 0.08
        }

        let lines = content.components(separatedBy: "\n")
        let kvLines = lines.filter { line in
            (line.contains(":") || line.contains("\t"))
                && line.rangeOfCharacter(from: .decimalDigits) != nil
        }
        if kvLines.count >= 2 {
            score += 0.05
        }

        let hasCrossRef = crossReferenceIndicators.contains { contentLower.contains($0) }
        if hasCrossRef && contentLower.contains("page") {
            score -= 0.20
        }

        return (score, matchingConceptCount)
    }

    nonisolated static func extractivePriorityScore(
        content: String,
        queryKeywords: [String],
        structureType: String?
    ) -> Float {
        let lowercased = content.lowercased()
        let specScore = Float(specPatternCount(in: content))
        let structuredBonus: Float = isStructuredEvidence(text: content, structureType: structureType) ? 10 : 0
        let keywordHits = Float(queryKeywords.filter { lowercased.contains($0) }.count)
        let keywordBonus = keywordHits * 5
        return specScore + structuredBonus + keywordBonus
    }

    nonisolated static func sentenceScore(
        line: String,
        headingContext: String,
        queryKeywords: [String],
        chunkIndex: Int,
        isExtractiveFirst: Bool
    ) -> Double? {
        let lineLower = line.lowercased()
        let headingLower = headingContext.lowercased()
        let lineWords = Set(lineLower
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !Self.isSentenceStopWord($0) })
        let queryWords = Set(queryKeywords)

        if !lineWords.isEmpty && !queryWords.isEmpty {
            let overlap = lineWords.intersection(queryWords).count
            let lineUnique = lineWords.subtracting(queryWords).count
            if overlap >= queryWords.count && lineUnique <= 1 {
                return nil
            }
        }

        var directHits = 0
        for keyword in queryKeywords where lineLower.contains(keyword) {
            directHits += 1
        }

        var headingHits = 0
        for keyword in queryKeywords where headingLower.contains(keyword) {
            headingHits += 1
        }

        let totalKeywordHits = directHits + headingHits
        guard totalKeywordHits > 0 else { return nil }

        let specBoostMultiplier: Double = isExtractiveFirst ? 2.5 : 1.0
        let hasNumbers = line.rangeOfCharacter(from: .decimalDigits) != nil
        let numberBonus: Double = hasNumbers ? 2.0 : 0.0

        let unitPattern = #"\d+(?:\.\d+)?\s*(?:qt|quart|gal|gallon|L|liter|litre|ml|oz|fl|kg|g|lb|lbs|mg|mcg|ug|mm|cm|m|km|in|ft|yd|mi|psi|kPa|MPa|bar|atm|rpm|hp|kW|MW|GW|Hz|kHz|MHz|GHz|TB|GB|MB|KB|V|mV|A|mA|W|kWh|MWh|Ah|mAh|cal|kcal|kJ|MJ|BTU|dB|dBm|lux|lm|cd|mol|IU|%)\b"#
        let unitHits = (try? NSRegularExpression(pattern: unitPattern, options: .caseInsensitive))?
            .numberOfMatches(in: line, range: NSRange(line.startIndex..., in: line)) ?? 0
        let unitBonus = Double(min(unitHits, 3)) * 1.5 * specBoostMultiplier

        let specCodePattern = #"\b(?:API|ISO|SAE|ACEA|ASTM|IEEE|ANSI|IEC|NIST|OSHA|EPA|FDA|WHO|USP|NF|BP|JP|MIL-|SPEC-|UL|CE|FCC|RoHS|REACH|GMP|HACCP|NFPA|ASHRAE|ACI|AISI|AISC|AWS|ASME|DOT|FMVSS|ECE|JIS|DIN|EN|BS|AS|NZS|CSA|CAN|GB|GB/T)\s*[A-Z0-9./-]+"#
        let specHits = (try? NSRegularExpression(pattern: specCodePattern))?
            .numberOfMatches(in: line, range: NSRange(line.startIndex..., in: line)) ?? 0
        let specBonus = Double(min(specHits, 3)) * 2.0 * specBoostMultiplier

        let keyValueBonus: Double = (line.contains(":") && hasNumbers) ? 1.5 * specBoostMultiplier : 0.0

        let structuredCodePattern = #"\b[A-Z0-9]{1,6}[-./][A-Z0-9]{1,6}(?:[-./][A-Z0-9]{1,6})?\b"#
        let codeHits = (try? NSRegularExpression(pattern: structuredCodePattern))?
            .numberOfMatches(in: line, range: NSRange(line.startIndex..., in: line)) ?? 0
        let codeBonus = Double(min(codeHits, 3)) * 1.5 * specBoostMultiplier

        let rankBonus = max(0.0, 1.0 - Double(chunkIndex) * 0.05)
        let keywordScore = Double(directHits) * 3.0 + Double(headingHits) * 2.0
        let coverageFraction = Double(totalKeywordHits) / Double(max(1, queryKeywords.count))
        let coveragePenalty: Double = (queryKeywords.count >= 2 && coverageFraction < 0.5) ? 0.4 : 1.0

        return (keywordScore + numberBonus + unitBonus + specBonus + keyValueBonus + codeBonus + rankBonus)
            * coveragePenalty
    }
}
