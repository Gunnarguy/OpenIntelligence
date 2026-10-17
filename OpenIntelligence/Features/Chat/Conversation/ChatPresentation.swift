//
//  ChatPresentation.swift
//  OpenIntelligence
//
//  How much of its machinery the chat shows (5.7).
//

import SwiftUI

private struct ShowsTechnicalDetailsKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether the chat shows its technical view: the stats bar, the step console and the technical badges
    /// (`SettingsStore.showTechnicalDetails`, set by the chat screen). True outside the chat, where nothing reads it.
    var showsTechnicalDetails: Bool {
        get { self[ShowsTechnicalDetailsKey.self] }
        set { self[ShowsTechnicalDetailsKey.self] = newValue }
    }
}

/// What the chat says it is doing while an answer is on its way, in plain words, when the technical view is off
/// (5.7). The technical view names each step ("RRF fusion", "BM25 search"); a person who has not built a search
/// engine wants to know that their documents are being searched and an answer written.
enum ChatProgress {
    static func phrase(for kind: ThinkingEvent.Kind?, thinksInSteps: Bool) -> String {
        guard let kind else { return "Reading your question…" }
        switch kind {
        case .planning, .intentRoute, .queryRewrite, .hyde, .embedding:
            return "Reading your question…"
        case .retrieval, .vectorSearch, .bm25, .rrf, .rerank, .mmr, .parentDoc, .iterative, .graphPack:
            return "Searching your documents…"
        case .context, .compression, .lostInMiddle, .extractive, .factBank:
            return "Reading what it found…"
        case .generation:
            return "Writing the answer…"
        // Deep Think's and Maximum's tools look things up in the library.
        case .toolCall:
            return "Looking through your documents…"
        // The gate that decides whether the passages found are good enough to answer from; it runs before the answer
        // is written.
        case .gating:
            return "Checking what it found…"
        case .grounding, .verification, .selfRag, .confidence:
            return "Checking against your documents…"
        case .agentic, .reasoning:
            return thinksInSteps ? "Thinking it through…" : "Working on it…"
        case .imagePlayground:
            return "Getting the picture ready…"
        default:
            return "Working on it…"
        }
    }
}
