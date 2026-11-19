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
        /// Deep Think's final step reads the passages its passes cited beside their notes (`ChainSynthesisEvidence`,
        /// 5.8); off, it reads the notes alone, cut at 3,000 characters, the path before it.
        case chainSourcePassages
        /// A streamed Standard answer with no `[S#]` label gets labels from its context (`CitationAttribution`, 5.8);
        /// off, it is kept without, the path before it.
        case citationAttribution
        /// Deep Think's final step opens with one sentence that answers the question, the value and its label, and
        /// does not call a value missing that a passage gives (5.8, 2026-11-13); off, the comprehensive-essay prompt
        /// alone, the path before it. On 53 table questions its answers ran a median 2,231 characters and 19 said a
        /// value was absent or not stated, some of them while giving it.
        case answerFirst
        /// Maximum's final step reads the top retrieved passages in the documents' own words, labelled as the answer's
        /// source list labels them, beside its claim bank (5.8, 2026-11-13); off, the claim bank alone, the path before
        /// it. On 2026-11-13 Maximum gave "$1.2 billion" for a document's "$1,577 million" and the battery limit "45 C"
        /// for a payload: every value went through the sessions' notes first.
        case maximumSourcePassages
        /// The source-only check flags an answer Needs Verification on its drafting model's "abstain" only when one of
        /// the answer's claims failed its check (5.8, 2026-11-13); off, the drafter's "abstain" alone flags it, the path
        /// before it.
        case draftAbstainNeedsFailedClaim
        /// Deep Think's final step reads as much evidence as the window leaves (5,986 tokens of an 8,192 window, 1,890 of
        /// 4,096) (5.8, 2026-11-18); off, it is held to `SessionEvidencePlan.readingCeilingTokens` (3,200), the path
        /// before it. Measured 2026-11-17 as `synthesisReadingCeiling` (the opposite sense): 49 against 47 of 53 table
        /// questions right at an 8,192 window (`BenchmarkRuns/2026-11-17-synthesis-ceiling`).
        case synthesisFullWindow
        /// A sentence that sentence extraction cuts from a list item or a labelled line carries the item's lead ("Standard
        /// > 30 candidate passages, a similarity floor of 0.28") (5.8, 2026-11-18); off, it is packed without it, the path
        /// before it, where "What is the similarity floor in Standard mode?" was answered with Maximum's 0.20 on the
        /// owner's iPhone (`BenchmarkRuns/2026-11-18-entity-binding`).
        case itemLeadInSentences
        /// Fact Check counts a "no" against a claim only when what it denies is named in the claim (5.8, 2026-11-18,
        /// `ClaimCheck.resolvingNo`); off, every "no" counts, the path before it, where the guide's "no query expansion"
        /// marked the right "The similarity floor in Standard mode is 0.28." as "says the opposite".
        case noNamedOnly
        /// Fact Check marks a claim Unsupported when the passages give its value for another list item, labelled line
        /// or section than the one it names (5.8, 2026-11-18, `EntityBinding.misplacedValues` in
        /// `VerificationGateService.markingValuesFromOtherRows`); off, that check is skipped, the path before it.
        case entityBindingGate
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
