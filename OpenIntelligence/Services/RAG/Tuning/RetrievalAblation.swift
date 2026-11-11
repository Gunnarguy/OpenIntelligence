//
//  RetrievalAblation.swift
//  OpenIntelligence
//
//  Switches for measuring each retrieval rule on its own (5.8 audit). Development builds only.
//

import Foundation

/// The hand-written rules between the cross-encoder and the prompt that can change which passage leads, each of which
/// a benchmark run can switch off by name: `OI_RETRIEVAL_ABLATE=tocPenalty,specSniper` (in a test run,
/// `TEST_RUNNER_OI_RETRIEVAL_ABLATE`). Several were written for the TinyBERT reranker shipped through 5.7, and none had
/// been measured on its own; the 2026-11-09 audit lists them in `Docs/RETRIEVAL_PIPELINE.md`. A release build reads
/// nothing and every rule runs, so the switches change no shipped behaviour.
nonisolated enum RetrievalAblation {
    enum Rule: String, CaseIterable, Sendable {
        /// `RAGEngine.computeTOCPenalty` after the cross-encoder.
        case tocPenalty
        /// `RAGEngine.computeQuestionBankPenalty`.
        case questionBankPenalty
        /// `RAGEngine.computeBibliographyPenalty`.
        case bibliographyPenalty
        /// `boostContextualDefinitionMatches` (Standard).
        case definitionBoost
        /// The "Spec preservation" rescue of filtered spec passages (Standard).
        case specRescue
        /// `addSummaryDetailHybrid` (Standard).
        case summaryHybrid
        /// `applyFocusedNeighborWindow` (Standard).
        case focusedWindow
        /// `addCrossReferencedPassages` (Standard).
        case crossReferences
        /// `runSpecTableSniper` (Standard). Deep Think's was removed after the 2026-11-10 audit measured it hurting.
        case specSniper
        /// `compressContextCandidates` (Standard).
        case compression
        /// `packContextWithGraph` (Standard).
        case graphPack
        /// `runCorrectiveRetrieval` (Standard).
        case corrective
        /// The keyword priority in `orderContextCandidates`'s extractive branch (Standard); the top passage stays first.
        case extractivePriority
        /// Deep Think's lost-in-the-middle placement in `executeFullRetrievalPipeline`.
        case deepThinkLostInMiddle
        /// Deep Think's multi-query blend of reranker score and reciprocal rank fusion; off, it sorts by reranker score.
        case multiQueryBlend
        /// Reciprocal rank fusion ranks each search's passages by score (5.8); off, by the order the search returned,
        /// which since 5.8 is the lost-in-the-middle order.
        case fusionScoreOrder
    }

    /// The rules switched off for this process, read once.
    static let off: Set<Rule> = {
        #if DEBUG
            let raw = ProcessInfo.processInfo.environment["OI_RETRIEVAL_ABLATE"] ?? ""
            return parse(raw)
        #else
            return []
        #endif
    }()

    /// Set by a benchmark that measures several configurations in one process, between questions, while no search
    /// runs (`EvidenceReachBenchmarkTests`). Development builds only; nil leaves `off` in force.
    #if DEBUG
        nonisolated(unsafe) static var overrideOff: Set<Rule>?
    #endif

    static func isOff(_ rule: Rule) -> Bool {
        #if DEBUG
            if let overrideOff { return overrideOff.contains(rule) }
        #endif
        return off.contains(rule)
    }

    /// The rules named in a comma-separated list; unknown names are ignored. "all" names every rule.
    static func parse(_ raw: String) -> Set<Rule> {
        let names = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if names.contains("all") { return Set(Rule.allCases) }
        return Set(names.compactMap(Rule.init(rawValue:)))
    }
}
