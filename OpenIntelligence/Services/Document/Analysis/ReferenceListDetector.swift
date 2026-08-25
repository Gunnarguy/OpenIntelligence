//
//  ReferenceListDetector.swift
//  OpenIntelligence
//
//  Recognises the shape of a bibliography, which prose does not produce.
//

import Foundation

/// Whether a piece of text looks like a reference list.
///
/// Two subsystems need this and they needed it for opposite reasons, which is why it lives in one
/// place rather than being written twice:
///
/// - `RAGEngine` demotes reference chunks during reranking. A page of citations about dopamine
///   contains "dopamine" many times and states no fact about it, so it is simultaneously the worst
///   possible evidence and one of the best keyword matches.
/// - `ContentTaggingService` samples a document's first, middle and last chunk to generate tags. On
///   a journal article the last chunk **is** the bibliography, so a third of the tag model's input
///   was author surnames. Observed on device 2026-08-25: the same paper produced `analysis,
///   depression, dopamine, motivation, serotonin` on one ingest and `check, cho, informative,
///   merten, pychatry, updates, zeng` on another — `Cho`, `Merten` and `Zeng` being cited authors
///   and `pychatry` a mangled `PCNPsychiatry` running header.
///
/// Duplicating the three regexes across both call sites would have been the fourth instance this
/// week of a rule applied to a subset of the places that need it.
enum ReferenceListDetector {

    /// `Surname AB,` — a family name followed by run-together initials. Two or more of these in one
    /// chunk is an author list.
    private static let authorInitialsRegex = try? Regex(#"\b[A-Z][a-z]{2,}\s+[A-Z]{1,3}[,\.]"#)
    /// `2013; 500: 575-579` — the year/volume/pages tail of a journal citation.
    private static let citationTailRegex = try? Regex(#"\b(?:19|20)\d{2};\s*\d+\s*:\s*\d+"#)
    /// `58. Menegas` — a numbered entry opening on a capitalised surname.
    private static let numberedEntryRegex = try? Regex(#"(?:^|\s)\d{1,3}\.\s+[A-Z][a-z]{2,}"#)

    struct Signals: Sendable {
        /// How many of the three independent shapes are present.
        let signalsPresent: Int
        /// Markers per word. Distinguishes a 400-word methods paragraph citing four papers from a
        /// 60-word chunk that is nothing but citations.
        let markerDensity: Float

        /// Requires two of three. Each signal alone has a false positive — a methods section cites
        /// authors, a results table carries year/volume figures, a numbered procedure opens on
        /// digits — and requiring agreement is what keeps prose that merely *mentions* a reference
        /// from being treated as one.
        var looksLikeReferenceList: Bool { signalsPresent >= 2 }
    }

    static func analyse(_ content: String) -> Signals {
        let wordCount = content.split(separator: " ").count
        guard wordCount > 12 else { return Signals(signalsPresent: 0, markerDensity: 0) }

        let authorHits = authorInitialsRegex.map { content.matches(of: $0).count } ?? 0
        let citationHits = citationTailRegex.map { content.matches(of: $0).count } ?? 0
        let numberedHits = numberedEntryRegex.map { content.matches(of: $0).count } ?? 0

        let signalsPresent = [authorHits >= 2, citationHits >= 1, numberedHits >= 2]
            .filter { $0 }
            .count

        return Signals(
            signalsPresent: signalsPresent,
            markerDensity: Float(authorHits + citationHits + numberedHits) / Float(wordCount)
        )
    }
}
