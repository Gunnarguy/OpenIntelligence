//
//  CheckClaimIntent.swift
//  OpenIntelligence
//

import AppIntents
import Foundation

/// Checks a sentence against the active library without writing an answer (5.7). The six passages
/// that match it best are found as "Find Passages" finds them, by the sentence's embedding and its
/// keywords, and the claim check a Standard answer goes through judges whether they hold it up
/// (`ClaimCheck.check`). That check compares the sentence's key words, which Apple's noun tagger
/// picks, its figures and the passages' retrieval scores. No language model judges the sentence.
@available(iOS 26.0, macOS 26.0, *)
struct CheckClaimIntent: AppIntent {
    static var title: LocalizedStringResource = "Check a Claim"
    static var description: IntentDescription = .init(
        "Checks whether the words and figures in your active library hold up a sentence, and names the passage it was checked against.",
        categoryName: "Documents",
        searchKeywords: ["check", "verify", "fact", "claim", "support", "source"]
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Claim", description: "The sentence to check")
    var claim: String

    static var parameterSummary: some ParameterSummary {
        Summary("Check \(\.$claim) against my documents")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let wanted = claim.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else {
            throw $claim.needsValueError("What should I check?")
        }
        Log.info("[Shortcuts] Check a Claim invoked (claimChars=\(wanted.count))", category: .pipeline)

        let engine = await MainActor.run { IntentSupport.engine() }
        let chunks: [RetrievedChunk]
        do {
            chunks = Array(try await engine.searchDocumentsRaw(query: wanted, topK: 6).prefix(6))
        } catch {
            throw OIIntentError("The search did not finish: \(error.localizedDescription)")
        }
        let outcome = await ClaimCheck.check(wanted, against: chunks)
        Log.info(
            "[Shortcuts] Check a Claim: \(outcome.verdict.label) from \(chunks.count) passage(s)\(outcome.numberMismatch ? ", a number did not match" : "")\(outcome.negationDiffers ? ", a negation differs" : "")",
            category: .pipeline)
        return .result(
            value: outcome.verdict.label,
            dialog: IntentDialog(stringLiteral: ClaimCheck.sentence(outcome)))
    }
}

/// What "Check a Claim" decides, says and returns.
nonisolated enum ClaimCheck {
    enum Verdict: Equatable {
        case supported, partial, unsupported, notFound

        /// The value the action returns, which a shortcut can test.
        var label: String {
            switch self {
            case .supported: return "Supported"
            case .partial: return "Partly supported"
            case .unsupported: return "Not supported"
            case .notFound: return "Not found"
            }
        }
    }

    struct Outcome {
        let verdict: Verdict
        /// "Lease.pdf, page 3": the passage the verdict rests on, or the closest one.
        let source: String?
        let numberMismatch: Bool
        let negationDiffers: Bool
    }

    /// The claim check on these passages, with the sentence as its one claim. The query is left
    /// empty: the check counts a word found in the question as covered, and here the question would
    /// be the sentence itself, which would cover every word of it. Word overlap cannot tell "pets are
    /// allowed" from "pets are not allowed", so a supported sentence whose matching sentence in the
    /// passage disagrees with it about a negation is only partly supported. Only that one sentence
    /// is compared: a "not" in the sentence after it says nothing about this one.
    static func check(_ claim: String, against chunks: [RetrievedChunk]) async -> Outcome {
        guard !chunks.isEmpty else {
            return Outcome(verdict: .notFound, source: nil, numberMismatch: false, negationDiffers: false)
        }
        let result = await VerificationGateService.shared.verify(
            response: claim,
            query: "",
            retrievedChunks: chunks,
            topScores: chunks.map(\.similarityScore),
            structuredClaims: [StructuredRAGClaim(claim: claim, citations: [], isExtracted: false)]
        )
        let claimResult = result.claimResults.first
        var verdict = Self.verdict(claimResult?.verdict)
        // The gate takes a sentence's key words from Apple's noun tagger and counts a sentence it
        // finds no nouns in as covered, which is every sentence where the tagger has no model (the
        // iOS Simulator, and a language it does not tag). So a partial verdict also needs half the
        // sentence's content words in the passages.
        if verdict == .partial, Self.contentWordCoverage(claim, in: chunks) < 0.5 { verdict = .unsupported }
        // The passage the gate's evidence starts with, which its confidence was taken from.
        let resolved = (claimResult?.resolvedEvidenceIds ?? []).lazy
            .compactMap { id in chunks.first { $0.chunk.id.uuidString == id } }.first
        let passage = resolved ?? chunks.first
        var negationDiffers = false
        if let passage, verdict != .unsupported,
            let sentence = Self.matchingSentence(for: claim, in: passage.chunk.contextText)
        {
            negationDiffers = Self.negationDiffers(claim, sentence)
            if negationDiffers, verdict == .supported { verdict = .partial }
        }
        let numberMismatch = result.gateResults.contains { $0.gate == .numericSanity && !$0.passed }
        let source = passage.map { chunk -> String in
            let name = chunk.sourceDocument.isEmpty ? "a document" : chunk.sourceDocument
            guard let page = chunk.pageNumber ?? chunk.chunk.metadata.pageNumber else { return name }
            return "\(name), page \(page)"
        }
        return Outcome(verdict: verdict, source: source, numberMismatch: numberMismatch, negationDiffers: negationDiffers)
    }

    /// The share of the claim's content words that the passages hold, as whole words.
    static func contentWordCoverage(_ claim: String, in chunks: [RetrievedChunk]) -> Double {
        let wanted = contentWords(claim)
        guard !wanted.isEmpty else { return 1 }
        let held = chunks.reduce(into: Set<String>()) { held, chunk in
            held.formUnion(contentWords(chunk.chunk.contextText))
        }
        return Double(wanted.intersection(held).count) / Double(wanted.count)
    }

    /// Words of three letters or more and numbers, without the commonest English words: the rule an
    /// answer's quote is picked by (`StructuredAnswer.quote`).
    static func contentWords(_ text: String) -> Set<String> {
        let common: Set<String> = [
            "the", "and", "for", "with", "that", "this", "from", "are", "was", "were", "has", "have",
            "not", "but", "you", "your", "its", "their", "they", "will", "can", "may", "which", "what",
            "when", "there", "been", "also", "into", "than", "then", "each", "any", "all", "per",
        ]
        let tokens = text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return Set(tokens.filter { !common.contains($0) && ($0.count >= 3 || $0.allSatisfy(\.isNumber)) })
    }

    /// The sentence of a passage that shares the most content words with the claim, the first of
    /// them on a tie, or nil when none shares one. A table row counts as one sentence.
    static func matchingSentence(for claim: String, in text: String) -> String? {
        let wanted = contentWords(claim)
        guard !wanted.isEmpty else { return nil }
        var best: String?
        var bestShared = 0
        for sentence in EvidenceLineSplitter.lines(in: text).flatMap(EvidenceLineSplitter.units(in:)) {
            let shared = contentWords(sentence).intersection(wanted).count
            if shared > bestShared {
                best = sentence
                bestShared = shared
            }
        }
        return best
    }

    static func verdict(_ gateVerdict: RAGVerificationResult.ClaimResult.Verdict?) -> Verdict {
        switch gateVerdict {
        case .supported?: return .supported
        case .partial?: return .partial
        case .unsupported?, nil: return .unsupported
        }
    }

    /// Whether one of the two is negative (`hasNegation(_:against:)`) and the other isn't.
    static func negationDiffers(_ claim: String, _ sentence: String) -> Bool {
        hasNegation(claim, against: sentence) != hasNegation(sentence, against: claim)
    }

    /// `hasNegation`, counting "without" only when what it is without is named in `other` (5.7). The handbook's
    /// "your child may return after being fever-free for 24 hours without fever-reducing medicine" denies nothing in
    /// the claim "The child must also be kept home with fever ≥100.4°F, vomiting/diarrhea, or pink eye until
    /// cleared.", and Fact Check marked that claim "The passage it rests on says the opposite" (demo copy of 1c913bf
    /// in the iOS 27 Simulator, 2026-10-20). "The landlord may enter without notice" against a passage that requires
    /// notice still reads as the opposite, because notice is named in both. What follows "without" is read up to the
    /// end of its clause or a joining word, leaving out a leading article, and its last word is the one looked for.
    static func hasNegation(_ text: String, against other: String) -> Bool {
        let lowered = text.lowercased()
        guard lowered.contains("without"),
            let without = try? NSRegularExpression(pattern: #"\bwithout\b([^.,;:!?()\n]*)"#)
        else { return hasNegation(text) }
        let named = Set(other.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        let leading: Set<String> = ["a", "an", "the", "any", "your", "their", "his", "her", "its", "our", "my"]
        let joining: Set<String> = [
            "for", "and", "or", "but", "in", "on", "at", "to", "until", "unless", "if", "before", "after", "while",
            "when", "from", "by", "of", "with",
        ]
        let source = lowered as NSString
        var kept = lowered as NSString
        for match in without.matches(in: lowered, range: NSRange(location: 0, length: source.length)) {
            var object: [String] = []
            let words = source.substring(with: match.range(at: 1)).split { !$0.isLetter && !$0.isNumber }
            for word in words.map(String.init) {
                if joining.contains(word) { break }
                if object.isEmpty, leading.contains(word) { continue }
                object.append(word)
                if object.count == 4 { break }
            }
            let isNamed = object.last.map { head in
                named.contains(head) || named.contains(head + "s")
                    || (head.hasSuffix("s") && named.contains(String(head.dropLast())))
            } ?? false
            // The same length, so the ranges of the matches after this one still hold.
            if !isNamed {
                kept = kept.replacingCharacters(in: NSRange(location: match.range.location, length: 7), with: "with   ") as NSString
            }
        }
        return hasNegation(kept as String)
    }

    /// Whether the text says "not", "no", "never", "none", "nobody", "nothing", "neither", "nor",
    /// "cannot" or "without", a word ending in "n't", a word starting with "non" ("non-refundable",
    /// "nonpayment"), or a form of "prohibit" or "forbid". The phrases in `denyingNothing` are taken
    /// out first.
    static func hasNegation(_ text: String) -> Bool {
        var text = text.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        for phrase in denyingNothing {
            text = text.replacingOccurrences(of: phrase, with: " ", options: .regularExpression)
        }
        let negations: Set<String> = [
            "not", "no", "never", "none", "nobody", "nothing", "neither", "nor", "cannot", "without",
        ]
        let notNegations: Set<String> = ["nonetheless", "nonsense", "nonce"]
        return text.split { !$0.isLetter && $0 != "'" }.contains { word in
            negations.contains(String(word)) || word.hasSuffix("n't")
                || (word.hasPrefix("non") && !notNegations.contains(String(word)))
                || word.hasPrefix("prohibit") || word.hasPrefix("forbid") || word == "forbade"
        }
    }

    /// Phrases with "no", "not" or "without" in them that deny nothing: a bound ("no later than the
    /// 5th", "not less than 30 days", "not to exceed $500"), "not only", "whether or not", the
    /// abbreviation in "Unit No. 4" and "No. of guests", and the legal "without limitation" and
    /// "without prejudice".
    private static let denyingNothing = [
        #"\bno(t)?\s+(later|earlier|sooner|more|less|fewer|greater)\s+than\b"#,
        #"\bnot\s+to\s+exceed\b"#,
        #"\bnot\s+only\b"#,
        #"\bwhether\s+or\s+not\b"#,
        #"\bno\.\s*(\d|of\b)"#,
        #"\bwithout\s+(limitation|prejudice)\b"#,
    ]

    /// The spoken line: the verdict, the passage, and a figure or a negation that differs.
    static func sentence(_ outcome: Outcome) -> String {
        var text: String
        switch outcome.verdict {
        case .supported: text = "Your documents hold it up"
        case .partial: text = "Your documents partly hold it up"
        case .unsupported: text = "Your documents don't hold it up"
        case .notFound: return "Nothing in the active library matches it."
        }
        if let source = outcome.source {
            text += outcome.verdict == .unsupported ? ". The closest passage is in \(source)" : ", in \(source)"
        }
        text += "."
        if outcome.negationDiffers { text += " One of them says no where the other says yes, so read the passage." }
        if outcome.numberMismatch { text += " A number in it doesn't match what the documents say." }
        return text
    }
}
