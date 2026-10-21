//
//  RetrievalStyle.swift
//  OpenIntelligence
//
//  The search styles Library Settings offers (5.7), and the rules that decide when the person's
//  values hold: tuning after an import leaves them alone, and the passages-needed rule acts.
//

import Foundation

/// A library's search settings as Library Settings names them.
///
/// Whether the person chose the values is kept in `RetrievalConfig.requireExplicitCitations`. That field
/// no longer changes how an answer cites: every mode asks for citations (`RAGQualityMode.requiresCitations`),
/// so the generation path reads it and gets the same answer either way. The two places that do act on it
/// already read it as "the person's values": the filter keeps the person's bar as given rather than the
/// lower of it and the mode's (`RetrievalPolicyService.baseMinSimilarity`), and tuning after an import
/// leaves the library alone (`RetrievalConfig.autoTuned`). Reusing it keeps the library's saved form and
/// its iCloud copy unchanged.
enum RetrievalStyle: String, CaseIterable, Identifiable, Sendable {
    /// The app picks the values from the library's documents after each import.
    case automatic
    case balanced
    case precise
    case technical
    case exploratory

    var id: String { rawValue }

    /// The values a chosen style sets. Automatic has none of its own.
    var preset: RetrievalConfig? {
        switch self {
        case .automatic: nil
        case .balanced: .default
        case .precise: .highAccuracy
        case .technical: .technicalManual
        case .exploratory: .exploratory
        }
    }
}

extension RetrievalConfig {
    /// True when the person chose these values in Library Settings; see `RetrievalStyle`.
    var isChosenByPerson: Bool {
        get { requireExplicitCitations }
        set { requireExplicitCitations = newValue }
    }

    /// The values `style` sets, marked as the person's. Automatic gives what the app would pick for
    /// `documentTypes` and leaves later imports free to change it.
    static func chosen(_ style: RetrievalStyle, documentTypes: [DocumentType]) -> RetrievalConfig {
        guard var config = style.preset else {
            var automatic = RetrievalConfig.recommended(forDocumentTypes: documentTypes)
            automatic.isChosenByPerson = false
            return automatic
        }
        config.isChosenByPerson = true
        return config
    }

    /// The style these values are: automatic while tuning after an import may still change them, else the preset
    /// they equal, or nil for values set by hand. A bar of 0.5 or more nobody chose (an older strict library) is
    /// never changed by tuning (`autoTuned`), so it is not automatic either. Equal means within 0.001, so a slider
    /// moved away and back still reads as its preset, and anything else reads as Custom.
    var style: RetrievalStyle? {
        guard isChosenByPerson || minSimilarity >= 0.5 else { return .automatic }
        return RetrievalStyle.allCases.first { style in
            guard let preset = style.preset else { return false }
            return matches(preset)
        }
    }

    /// The same values as `other`, within 0.001, with the same number of passages needed.
    func matches(_ other: RetrievalConfig) -> Bool {
        abs(minSimilarity - other.minSimilarity) < 0.001
            && abs(vectorWeight - other.vectorWeight) < 0.001
            && abs(lexicalWeight - other.lexicalWeight) < 0.001
            && abs(mmrLambda - other.mmrLambda) < 0.001
            && minConfidentChunks == other.minConfidentChunks
    }

    /// What tuning after an import writes, or nil to leave the library as it is: the values the app
    /// recommends for its documents, unless the person chose the library's values or they already match.
    /// A bar of 0.5 or more is left alone too, as it was before the person's choice was recorded.
    static func autoTuned(current: RetrievalConfig, recommended: RetrievalConfig) -> RetrievalConfig? {
        if current.isChosenByPerson || current.minSimilarity >= 0.5 { return nil }
        let differs =
            recommended.vectorWeight != current.vectorWeight
            || recommended.lexicalWeight != current.lexicalWeight
            || abs(recommended.minSimilarity - current.minSimilarity) > 0.05
        guard differs else { return nil }
        var tuned = recommended
        tuned.isChosenByPerson = false
        return tuned
    }
}
