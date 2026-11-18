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
        chunk.chunk.contextText
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

/// What Deep Think's final step reads (5.8): the passages its reading passes cited, in their own words, beside the
/// passes' notes, sized in tokens against the live window.
///
/// Through 5.8's first builds the final step read the notes alone: free-text paraphrases each pass wrote, joined in
/// order until 3,000 characters and cut there, with no passage text and no log line for what was cut
/// (`executeReasoningChain`, "Deep Think synthesis"). 3,000 characters assumed 1.4 characters a token; prose measures
/// about 4.4, so that was about 700 tokens of a 4,096 window, the same on an 8,192 one, and the later passes, which look
/// for what the first ones missed, were the ones cut. A number reached the answer only as a pass had restated it.
///
/// The model is not asked to quote: a small model paraphrases even when told not to. The passes already cite each fact
/// with the `[S#]` label of the passage it came from, and those labels are global positions among the routed chunks, so
/// the code reads which passages were cited and puts their text in front of the final step.
nonisolated enum ChainSynthesisEvidence {
    /// The final step's response limit (`maxTokens` at both synthesis calls).
    static let outputReserveTokens = 1_500
    /// The prompt's fixed wording, the question twice and the system prompt, before they are counted exactly.
    static let promptReserveTokens = 450
    /// The most of the evidence budget the notes may take; the passages get the rest first.
    static let notesShareOfBudget = 0.35
    /// Passages counted for the choice, in rank order: every passage a chain can read (eight sessions of seven).
    static let maxCandidates = SessionEvidencePlan.maxPlannedChunks

    /// Tokens the passages and the notes may take together: the window less the answer, the prompt and the safety
    /// margin. On a 4,096 window that is 1,890; on an 8,192 window 5,986. Until 2026-11-18 it was also held to what a
    /// session reads (`SessionEvidencePlan.readingCeilingTokens`, 3,200), from a 2026-10-07 probe on the 20B model.
    /// Lifting that ceiling at an 8,192 window answered 49 of 53 table questions right against 47 (2 better, 0 worse;
    /// `BenchmarkRuns/2026-11-17-synthesis-ceiling`, iOS 27.0 Simulator with the Mac's model), so the window decides.
    static func evidenceTokenBudget(contextSize: Int) -> Int {
        let free = contextSize - outputReserveTokens - promptReserveTokens - SessionEvidencePlan.safetyReserveTokens
        // Switched off, the old ceiling comes back, to measure against it (`RetrievalAblation.synthesisFullWindow`).
        if RetrievalAblation.isOff(.synthesisFullWindow) {
            return max(0, min(SessionEvidencePlan.readingCeilingTokens, free))
        }
        return max(0, free)
    }

    /// The `[S#]` labels a text cites, one-based, in order of first appearance. Reads "[S3]", "[S3, S5]" and
    /// "[S3][S5]".
    static func citedLabels(in text: String) -> [Int] {
        var seen = Set<Int>()
        var labels: [Int] = []
        let groups = text.matches(of: /\[(S\d+(?:\s*,\s*S?\d+)*)\]/)
        for group in groups {
            for part in group.output.1.split(separator: ",") {
                let digits = part.trimmingCharacters(in: .whitespaces).drop { $0 == "S" }
                if let label = Int(digits), label > 0, seen.insert(label).inserted { labels.append(label) }
            }
        }
        return labels
    }

    /// Zero-based positions among the routed chunks, best first: those the notes cite, most-cited first (ties: the
    /// earlier first citation, then the earlier position), then every other passage a pass read, in retrieval order.
    /// Only positions a pass read count; a label naming anything else is ignored.
    static func rankedPositions(notes: [String], readPositions: [Int]) -> [Int] {
        let read = Set(readPositions)
        var citations: [Int: Int] = [:]
        var firstCited: [Int: Int] = [:]
        var order = 0
        for note in notes {
            for label in citedLabels(in: note) {
                let position = label - 1
                guard read.contains(position) else { continue }
                citations[position, default: 0] += 1
                if firstCited[position] == nil {
                    firstCited[position] = order
                    order += 1
                }
            }
        }
        let cited = citations.keys.sorted {
            let (a, b) = (citations[$0]!, citations[$1]!)
            if a != b { return a > b }
            if firstCited[$0]! != firstCited[$1]! { return firstCited[$0]! < firstCited[$1]! }
            return $0 < $1
        }
        var seen = Set(cited)
        var ranked = cited
        for position in readPositions.sorted() where seen.insert(position).inserted { ranked.append(position) }
        return ranked
    }

    /// Passages taken in rank order while they fit `budget`; one that does not fit is skipped and the next tried, so a
    /// long passage cannot shut out shorter ones behind it. `counts[i]` is the token count of `ranked[i]`'s block.
    static func choose(ranked: [Int], counts: [Int], budget: Int) -> [Int] {
        var total = 0
        var chosen: [Int] = []
        for (position, count) in zip(ranked, counts) {
            let next = count + SessionEvidencePlan.joinOverheadTokens
            guard total + next <= budget else { continue }
            total += next
            chosen.append(position)
        }
        return chosen
    }

    /// The notes fitted to `limit` characters without dropping a later note: sentences an earlier note already holds
    /// are removed first, and if that is not enough every note is cut at a sentence boundary to an equal share. Notes
    /// under 20 characters and "no new information" notes are left out, as before.
    static func fittedNotes(_ notes: [String], limit: Int) -> [String] {
        let kept = notes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 20 && !$0.lowercased().contains("no new information") }
        var seen = Set<String>()
        let deduplicated = kept.map { note -> String in
            sentences(of: note).filter { sentence in
                let key = sentence.lowercased().filter { $0.isLetter || $0.isNumber }
                return key.count < 12 || seen.insert(key).inserted
            }.joined(separator: " ")
        }.filter { $0.count >= 20 }
        guard deduplicated.reduce(0, { $0 + $1.count }) > limit, !deduplicated.isEmpty else { return deduplicated }
        let share = max(80, limit / deduplicated.count)
        return deduplicated.map { cut($0, at: share) }
    }

    /// The text cut at the last sentence end within `limit` characters, or at the limit when no sentence ends there. A
    /// sentence ends at ".", "!" or "?" followed by a space, so "12.5" is never cut to "12.".
    static func cut(_ text: String, at limit: Int) -> String {
        guard text.count > limit else { return text }
        let characters = Array(text)
        var end: Int?
        for index in stride(from: min(limit, characters.count - 1) - 1, through: limit / 3, by: -1)
        where ".!?".contains(characters[index]) && characters[index + 1].isWhitespace {
            end = index
            break
        }
        return end.map { String(characters[...$0]) } ?? String(characters.prefix(limit))
    }

    private static func sentences(of text: String) -> [String] {
        var result: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, _ in
            if let sentence {
                let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { result.append(trimmed) }
            }
        }
        return result.isEmpty ? [text] : result
    }
}
