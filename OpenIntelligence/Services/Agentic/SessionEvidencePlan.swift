//
//  SessionEvidencePlan.swift
//  OpenIntelligence
//

import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// How much evidence one Deep Think chain session reads, in tokens, from the window the device
/// reports.
///
/// Through 5.5 a session's evidence was sized in characters (3,500, cut to 2,200 once there were
/// earlier findings) and first went through sentence extraction, which keeps a sentence only when
/// it, its heading or the line before it matches a keyword of the question. A passage that answers
/// the question in other words could be left out before the model read anything. Those character
/// constants assume 1.4 characters a token. That ratio fits dense numeric tables and is about three
/// times too cautious for prose, so a session carried roughly 500 tokens of an on-device window of
/// 4,096 or 8,192.
///
/// Here the budget is counted in tokens, and a session reads its chunks whole when they fit. The
/// reading ceiling is below a full window on purpose. One run on one Mac on 2026-10-07, 15 questions
/// a size, suggested why: asked directly, the on-device model wrongly answered that the excerpts did
/// not hold a passage 3 or 4 times with 800 to 4,000 tokens of evidence and 7 times with 6,600, when
/// the question shared few words with it, and time to first token grew from 2.3 s at 2,574 input
/// tokens to 10.7 s at 7,608 (the owner's local `BenchmarkRuns/2026-10-07-context-window-probe`).
/// That is not a measurement of this app's loop.
nonisolated enum SessionEvidencePlan {
    /// The most evidence a session reads, whatever the window.
    static let readingCeilingTokens = 3_200
    /// The prompt's fixed wording and its system prompt. The longest of the three session prompts is
    /// about 710 characters with its system prompt.
    static let promptReserveTokens = 400
    static let safetyReserveTokens = 256
    /// What joining one more block adds beyond the block's own count.
    static let joinOverheadTokens = 4
    /// A window at least this large is the larger on-device model's (8,192 measured).
    static let largeWindowThreshold = 8_000
    /// The question, the earlier findings and the objective lines are not counted exactly, because
    /// windows are planned before any session has written them. Prose measured 4.2 to 5.5 characters
    /// a token and a dense numeric table 1.38. 2.5 sits between; a session that overflows anyway is
    /// retried from sentence extraction (`executeReasoningChain`, context overflow).
    static let carriedCharsPerToken = 2.5
    /// The PRIOR FINDINGS cap in `buildChainPrompt`.
    static let priorFindingsChars = 1_200
    /// The session objective and the STILL UNANSWERED line, which later sessions carry.
    static let objectiveChars = 400
    /// Chunks counted for a plan. Eight sessions of seven chunks is the most a chain can read.
    static let maxPlannedChunks = 56

    /// The text a session's prompt carries besides its evidence and its fixed wording. The first
    /// session states the question once and carries no findings; later sessions state it twice.
    static func carriedChars(questionLength: Int, isFirstSession: Bool) -> Int {
        let question = max(0, questionLength)
        return isFirstSession ? question : priorFindingsChars + 2 * question + objectiveChars
    }

    /// Tokens of evidence a session may carry.
    static func evidenceTokenBudget(contextSize: Int, outputReserve: Int, carriedChars: Int) -> Int {
        let carried = Int((Double(max(0, carriedChars)) / carriedCharsPerToken).rounded(.up))
        let available = contextSize - max(0, outputReserve) - carried - promptReserveTokens - safetyReserveTokens
        return max(0, min(readingCeilingTokens, available))
    }

    /// The most chunks one chain session reads whole. A 4,096 window keeps the count it had. The
    /// larger window reads up to seven, but never so many that a pool the old path split into two
    /// sessions becomes one: a single session's notes skip the synthesis pass and would be shown as
    /// the answer.
    static func chainChunkCap(contextSize: Int, poolSize: Int, legacyCount: Int) -> Int {
        let legacy = max(1, legacyCount)
        guard contextSize >= largeWindowThreshold else { return legacy }
        let half = Int((Double(max(0, poolSize)) / 2).rounded(.up))
        return min(7, max(legacy, half))
    }

    struct Window: Equatable, Sendable {
        /// One past the last chunk index in the window.
        let end: Int
        /// True when every chunk in the window fits whole. False means: size this window the old
        /// way (`legacyCount` chunks through sentence extraction).
        let wholeChunks: Bool
        /// Evidence tokens of a whole-chunk window. Zero otherwise.
        let tokens: Int
    }

    /// The window that starts at `start`. `tokenCounts` are the counts of each chunk's block
    /// (`block(for:label:)`). Takes chunks in order while they fit `budget`, up to `cap`. If fewer
    /// fit than the old path would have read (`legacyCount`), the window is not a whole-chunk one,
    /// so the chain never plans more windows than it did.
    static func window(start: Int, tokenCounts: [Int], budget: Int, cap: Int, legacyCount: Int) -> Window {
        let remaining = max(0, tokenCounts.count - start)
        let legacy = min(max(1, legacyCount), remaining)
        guard remaining > 0 else { return Window(end: start, wholeChunks: false, tokens: 0) }

        var taken = 0
        var total = 0
        while taken < min(max(1, cap), remaining) {
            let next = tokenCounts[start + taken] + joinOverheadTokens
            guard total + next <= budget else { break }
            total += next
            taken += 1
        }
        guard taken >= legacy else { return Window(end: start + legacy, wholeChunks: false, tokens: 0) }
        return Window(end: start + taken, wholeChunks: true, tokens: total)
    }

    /// One chunk as a session reads it, in the form the chain's raw-chunk fallback already uses: a
    /// `[S#]` label with the source name, then the chunk's text. `label` is one-based and global,
    /// the chunk's position among the routed chunks.
    static func block(for chunk: RetrievedChunk, label: Int) -> String {
        "[S\(label)] (\(chunk.sourceDocument))\n" + text(of: chunk) + "\n\n---\n"
    }

    /// The text of a whole-chunk window. `firstLabel` is one-based.
    static func wholeChunkContext(_ chunks: [RetrievedChunk], firstLabel: Int) -> String {
        chunks.enumerated().map { block(for: $0.element, label: firstLabel + $0.offset) }.joined()
    }

    /// The text a session reads for a chunk: its parent passage when it has one, as sentence
    /// extraction reads. Neighbouring chunks' parent passages can overlap; whole chunks keep that
    /// repeat, where extraction removed duplicate sentences.
    static func text(of chunk: RetrievedChunk) -> String {
        chunk.chunk.parentContent ?? chunk.chunk.content
    }
}

/// Exact token counts from the SDK, one call a text.
///
/// `FoundationModelTokenBudget.snapshot` counts instructions and tools as well, three calls a text.
/// On a Mac under load on 2026-10-07, 20 chunks counted that way took 4.9 s in parallel. A plan
/// needs the evidence count alone.
nonisolated enum SessionEvidenceTokenCounter {
    /// One count per text, or nil when the SDK cannot count exactly on this OS or a count fails.
    /// Nil means: keep the character-sized path.
    static func counts(for texts: [String]) async -> [Int]? {
        #if canImport(FoundationModels)
            guard !texts.isEmpty else { return [] }
            guard #available(iOS 26.4, macOS 26.4, *) else { return nil }
            return await withTaskGroup(of: (Int, Int?).self) { group -> [Int]? in
                for (index, text) in texts.enumerated() {
                    group.addTask {
                        (index, try? await SystemLanguageModel.default.tokenCount(for: Prompt(text)))
                    }
                }
                var counts = [Int](repeating: 0, count: texts.count)
                for await (index, count) in group {
                    guard let count else {
                        group.cancelAll()
                        return nil
                    }
                    counts[index] = count
                }
                return counts
            }
        #else
            return nil
        #endif
    }
}
