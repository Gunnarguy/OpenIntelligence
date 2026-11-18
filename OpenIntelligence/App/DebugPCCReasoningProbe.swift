#if DEBUG
    import Foundation

    #if canImport(FoundationModels)
        import FoundationModels
    #endif

    /// `--probe-pcc-reasoning` (5.8, 2026-11-18): asks Private Cloud Compute one fixed question at each reasoning level
    /// and records what Apple reports back, then quits.
    ///
    /// Why it exists: on the owner's iPhone on 2026-11-14 a Deep Think answer sent to Private Cloud Compute at
    /// `.moderate` reported `reasoning=0` tokens, so whether the level the app sends changes anything was unknown. This
    /// measures it on the same path answers use (`streamResponse` with `ContextOptions(reasoningLevel:)`, a fresh session
    /// per call), plus one non-streaming `respond` at moderate, to learn whether streaming hides reasoning tokens.
    ///
    /// It reads no library and touches no stored setting: the context is a fixed paragraph in this file, and it runs from
    /// `App.init` before any service or scene exists, then calls `exit`. It writes `Documents/pcc_reasoning_probe.json`
    /// and one trace line per call. Five calls; the owner's daily Private Cloud Compute quota is shared, so it stops at
    /// the first call that fails rather than spending the rest.
    ///
    /// `--probe-pcc-reasoning-hard` (added the same day, after the first run reported 0 at every level): a harder
    /// question, plan costs across several facts with four traps a careless answer falls into, at no level and deep
    /// through `streamResponse`, then deep set through a session profile (`LanguageModelSession.Profile` with
    /// `.reasoningLevel(.deep)`, the SDK's second way to set it). Three calls; writes
    /// `Documents/pcc_reasoning_probe_hard.json` and records whether each answer is right.
    nonisolated enum DebugPCCReasoningProbe {
        static let flag = "--probe-pcc-reasoning"
        static let hardFlag = "--probe-pcc-reasoning-hard"
        static let resultName = "pcc_reasoning_probe.json"
        static let hardResultName = "pcc_reasoning_probe_hard.json"

        /// How a call reaches the model.
        nonisolated enum API: String, Sendable {
            /// `streamResponse(to:options:contextOptions:)`, the path answers use.
            case stream = "streamResponse"
            /// `respond(to:options:contextOptions:)`.
            case respond = "respond"
            /// `streamResponse(to:options:)` on a session made with `init(profile:)`, the level set on the profile.
            case profileStream = "streamResponse+profile"
        }

        /// One question and how to tell whether its answer is right.
        nonisolated struct Case: Sendable {
            let context: String
            let question: String
            let expected: String
            let isCorrect: @Sendable (String) -> Bool
        }

        /// The deadline for one call. A call that has not finished by then is recorded as timed out.
        static let callTimeout: TimeInterval = 180

        nonisolated struct Row: Codable, Sendable {
            var level: String
            var api: String
            var ok: Bool
            var error: String?
            var reasoningTokens: Int?
            var outputTokens: Int?
            var inputTokens: Int?
            var cachedInputTokens: Int?
            /// Reasoning entries in the session's transcript after the call, and their total characters.
            var transcriptReasoningEntries: Int?
            var transcriptReasoningChars: Int?
            /// To the stream's first snapshot (what the app logs as first token), and to the first snapshot with
            /// answer text. Nil for `respond`, which has no stream.
            var firstSnapshotMs: Int?
            var firstAnswerTextMs: Int?
            var snapshots: Int?
            /// The last stream snapshot's own `usage.output.reasoningTokenCount`, beside the session's.
            var lastSnapshotReasoningTokens: Int?
            var totalMs: Int
            var answerChars: Int
            /// Whether the answer names the right result, by `Case.isCorrect`. Nil when the case has no check.
            var correct: Bool?
            var answer: String
        }

        nonisolated struct Report: Codable, Sendable {
            var startedAt: String
            var finishedAt: String
            var osVersion: String
            var question: String
            var expected: String?
            var contextChars: Int
            var entitled: Bool
            var available: Bool
            var unavailableReason: String?
            var quotaLimitReachedBefore: Bool?
            var quotaLimitReachedAfter: Bool?
            var quotaResetDate: String?
            var rows: [Row]
            var note: String
        }

        /// A fixed passage that needs a few steps to answer: a date calculation with two constraints.
        static let context = """
            Section 14. Ending the lease. Either party may end this lease by written notice. The tenant's notice must be \
            received by the landlord at least 60 days before the move-out date. The move-out date must be the last day \
            of a calendar month. A notice received on a Saturday, Sunday or public holiday counts as received on the \
            next business day. The security deposit of $1,850 is returned within 21 days after move-out, less any \
            unpaid rent.
            """

        static let question = """
            The landlord receives the tenant's written notice on Saturday, March 7, 2026. What is the earliest \
            allowed move-out date, and by what date must the deposit be returned? Answer only from the lease text.
            """

        static let basicCase = Case(
            context: context, question: question, expected: "May 31, 2026; deposit by June 21, 2026",
            isCorrect: { $0.contains("May 31") && $0.contains("June 21") })

        /// Three plans, one usage pattern. The traps: Plan A bills each started GB (3.2 GB over is 4), its discount
        /// covers the monthly fees only, Plan B's activation fee is added once, and Plan C's monthly minimum ($50) is
        /// above what 13.2 GB costs at its rate ($46.20). Totals: A $716.40, B $695.00, C $600.00, so C is cheapest
        /// and $95.00 under B. Missing the minimum gives C $554.40 and a $140.60 gap; missing the activation fee gives
        /// B $660 and a $60 gap; rounding 3.2 GB down to 3 gives A $644.40 and puts it second.
        static let hardContext = """
            Plan A: a monthly fee of $42 that includes 10 GB of data. Data above the allowance costs $6 for each \
            started GB. Paying 12 months upfront takes 15% off the monthly fees; the discount does not apply to data \
            charges. Plan B: a monthly fee of $55 that includes 25 GB of data, extra data at $4 per started GB, and a \
            one-time activation fee of $35. Plan C: no monthly fee; data costs $3.50 per GB, charged on the exact \
            amount used, and a month's bill is never less than $50.
            """

        static let hardQuestion = """
            A customer uses exactly 13.2 GB of data every month for 12 months and would pay Plan A 12 months upfront. \
            What does each plan cost in total over the 12 months? Which plan is cheapest, and how much less does it \
            cost than the second cheapest? Answer only from the plan text.
            """

        static let hardCase = Case(
            context: hardContext, question: hardQuestion,
            expected: "A $716.40, B $695.00, C $600.00; Plan C cheapest, $95.00 less than Plan B",
            isCorrect: { answer in
                let flat = answer.replacingOccurrences(of: ",", with: "")
                return flat.contains("716.4") && flat.contains("695") && flat.contains("600")
                    && flat.range(of: #"(?<![\d.])\$?95(\.00)?(?!\d)"#, options: .regularExpression) != nil
                    && !flat.contains("554.4") && !flat.contains("140.6")
            })

        static let instructions = """
            You answer questions using only the document text provided. Quote the sentence each fact comes from. If \
            the text does not hold the answer, say so.
            """

        /// Called first thing in `App.init`. Returns at once unless the flag is present; otherwise it never returns.
        static func runAndExitIfRequested() {
            let hard = LaunchArguments.has(hardFlag)
            guard hard || LaunchArguments.has(flag) else { return }
            let done = DoneFlag()
            Task.detached(priority: .userInitiated) {
                await run(hard: hard)
                done.set()
            }
            // `App.init` runs on the main thread before the app's run loop starts. Turning the main run loop here lets
            // anything the framework schedules on the main queue run, and keeps every scene and service from starting.
            while !done.isSet {
                _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.25))
            }
            Log.flushTraceLog()
            exit(0)
        }

        private final class DoneFlag: @unchecked Sendable {
            private let lock = NSLock()
            private var value = false
            var isSet: Bool {
                lock.lock()
                defer { lock.unlock() }
                return value
            }
            func set() {
                lock.lock()
                value = true
                lock.unlock()
            }
        }

        private static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

        static func run(hard: Bool) async {
            let started = Date()
            let probeCase = hard ? hardCase : basicCase
            var report = Report(
                startedAt: iso(started), finishedAt: "", osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                question: probeCase.question, expected: probeCase.expected, contextChars: probeCase.context.count,
                entitled: false, available: false, rows: [], note: "")
            defer { write(report, name: hard ? hardResultName : resultName) }

            #if canImport(FoundationModels) && compiler(>=6.4)
                guard #available(iOS 27.0, macOS 27.0, *) else {
                    report.note = "Needs iOS or macOS 27."
                    report.finishedAt = iso(Date())
                    return
                }
                report.entitled = EntitlementChecker.hasEntitlement(EntitlementChecker.privateCloudComputeKey)
                guard report.entitled else {
                    report.note = "This build lacks the Private Cloud Compute entitlement; no call made."
                    report.finishedAt = iso(Date())
                    return
                }
                let model = PrivateCloudComputeLanguageModel()
                report.available = model.isAvailable
                if case .unavailable(let reason) = model.availability { report.unavailableReason = "\(reason)" }
                report.quotaLimitReachedBefore = model.quotaUsage.isLimitReached
                report.quotaResetDate = model.quotaUsage.resetDate.map(iso)
                guard model.isAvailable, !model.quotaUsage.isLimitReached else {
                    report.note = "Private Cloud Compute unavailable or over quota; no call made."
                    report.finishedAt = iso(Date())
                    return
                }

                let plan: [(String, ContextOptions.ReasoningLevel?, API)] =
                    hard
                    ? [("none", nil, .stream), ("deep", .deep, .stream), ("deep", .deep, .profileStream)]
                    : [
                        ("none", nil, .stream),
                        ("light", .light, .stream),
                        ("moderate", .moderate, .stream),
                        ("deep", .deep, .stream),
                        ("moderate", .moderate, .respond),
                    ]
                for (name, level, api) in plan {
                    let row = await probe(model: model, probeCase: probeCase, levelName: name, level: level, api: api)
                    report.rows.append(row)
                    Log.info(
                        "[PCCProbe] level=\(row.level) api=\(row.api) ok=\(row.ok) reasoning=\(row.reasoningTokens.map(String.init) ?? "n/a") "
                            + "out=\(row.outputTokens.map(String.init) ?? "n/a") in=\(row.inputTokens.map(String.init) ?? "n/a") "
                            + "firstSnapshotMs=\(row.firstSnapshotMs.map(String.init) ?? "n/a") "
                            + "firstTextMs=\(row.firstAnswerTextMs.map(String.init) ?? "n/a") totalMs=\(row.totalMs) "
                            + "chars=\(row.answerChars) correct=\(row.correct.map(String.init) ?? "n/a") reasoningEntries=\(row.transcriptReasoningEntries.map(String.init) ?? "n/a")"
                            + (row.error.map { " error=\($0)" } ?? ""),
                        category: .llm)
                    if !row.ok {
                        report.note = "Stopped after a failed call to spare the quota."
                        break
                    }
                }
                report.quotaLimitReachedAfter = model.quotaUsage.isLimitReached
            #else
                report.note = "FoundationModels with the iOS 27 SDK is not in this build."
            #endif
            report.finishedAt = iso(Date())
        }

        #if canImport(FoundationModels) && compiler(>=6.4)
            @available(iOS 27.0, macOS 27.0, *)
            private static func probe(
                model: PrivateCloudComputeLanguageModel, probeCase: Case, levelName: String,
                level: ContextOptions.ReasoningLevel?, api: API
            ) async -> Row {
                let session: LanguageModelSession
                if api == .profileStream {
                    // The level on the session's profile, not on the call (`DynamicProfile.reasoningLevel(_:)`).
                    let profile = LanguageModelSession.Profile { Instructions(instructions) }
                        .model(model)
                        .reasoningLevel(level)
                    session = LanguageModelSession(profile: profile)
                } else {
                    session = LanguageModelSession(model: model, instructions: Instructions(instructions))
                }
                let streaming = api != .respond
                let prompt = "Document text:\n\(probeCase.context)\n\nQuestion: \(probeCase.question)"
                let start = Date()
                var row = Row(
                    level: levelName, api: api.rawValue, ok: false, totalMs: 0, answerChars: 0, answer: "")
                do {
                    let outcome = try await withDeadline(seconds: callTimeout) { () async throws -> Outcome in
                        var outcome = Outcome()
                        if streaming {
                            let stream: LanguageModelSession.ResponseStream<String>
                            if let level, api == .stream {
                                stream = session.streamResponse(
                                    to: prompt, options: GenerationOptions(),
                                    contextOptions: ContextOptions(reasoningLevel: level))
                            } else {
                                stream = session.streamResponse(to: prompt, options: GenerationOptions())
                            }
                            for try await snapshot in stream {
                                outcome.snapshots += 1
                                let elapsed = Int(Date().timeIntervalSince(start) * 1000)
                                if outcome.firstSnapshotMs == nil { outcome.firstSnapshotMs = elapsed }
                                outcome.text = snapshot.content
                                if outcome.firstTextMs == nil, !outcome.text.isEmpty { outcome.firstTextMs = elapsed }
                                outcome.lastSnapshotReasoningTokens = snapshot.usage.output.reasoningTokenCount
                            }
                        } else {
                            let response: LanguageModelSession.Response<String>
                            if let level {
                                response = try await session.respond(
                                    to: prompt, options: GenerationOptions(),
                                    contextOptions: ContextOptions(reasoningLevel: level))
                            } else {
                                response = try await session.respond(to: prompt, options: GenerationOptions())
                            }
                            outcome.text = response.content
                            // The response's own count, which the session's should equal for a one-call session.
                            outcome.responseReasoningTokens = response.usage.output.reasoningTokenCount
                        }
                        return outcome
                    }
                    row.ok = true
                    row.answer = outcome.text
                    if streaming {
                        row.firstSnapshotMs = outcome.firstSnapshotMs
                        row.firstAnswerTextMs = outcome.firstTextMs
                        row.snapshots = outcome.snapshots
                        row.lastSnapshotReasoningTokens = outcome.lastSnapshotReasoningTokens
                    }
                    if let fromResponse = outcome.responseReasoningTokens,
                        fromResponse != session.usage.output.reasoningTokenCount
                    {
                        row.error = "response.usage reasoning=\(fromResponse) differs from session.usage"
                    }
                } catch {
                    row.error = String(describing: error)
                }
                row.totalMs = Int(Date().timeIntervalSince(start) * 1000)
                row.answerChars = row.answer.count
                if row.ok { row.correct = probeCase.isCorrect(row.answer) }
                // One fresh session per call, so its accumulated usage is this call's (as `readUsage` in the app).
                let usage = session.usage
                row.reasoningTokens = usage.output.reasoningTokenCount
                row.outputTokens = usage.output.totalTokenCount
                row.inputTokens = usage.input.totalTokenCount
                row.cachedInputTokens = usage.input.cachedTokenCount
                var entries = 0
                var chars = 0
                for entry in session.transcript {
                    if case .reasoning(let reasoning) = entry {
                        entries += 1
                        chars += reasoning.segments.reduce(0) { $0 + "\($1)".count }
                    }
                }
                row.transcriptReasoningEntries = entries
                row.transcriptReasoningChars = chars
                return row
            }
        #endif

        private struct Outcome: Sendable {
            var firstSnapshotMs: Int?
            var firstTextMs: Int?
            var snapshots = 0
            var text = ""
            var responseReasoningTokens: Int?
            var lastSnapshotReasoningTokens: Int?
        }

        private struct DeadlineExceeded: Error, CustomStringConvertible {
            let seconds: TimeInterval
            var description: String { "timed out after \(Int(seconds)) s" }
        }

        private static func withDeadline<T: Sendable>(
            seconds: TimeInterval, _ body: @escaping @Sendable () async throws -> T
        ) async throws -> T {
            try await withThrowingTaskGroup(of: T?.self) { group in
                group.addTask { try await body() }
                group.addTask {
                    try await Task.sleep(for: .seconds(seconds))
                    throw DeadlineExceeded(seconds: seconds)
                }
                defer { group.cancelAll() }
                guard let first = try await group.next(), let value = first else {
                    throw DeadlineExceeded(seconds: seconds)
                }
                return value
            }
        }

        private static func write(_ report: Report, name: String) {
            guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return
            }
            let url = documents.appendingPathComponent(name)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(report) {
                try? data.write(to: url, options: .atomic)
                print("[PCCProbe] wrote \(url.path)")
            }
        }
    }
#endif
