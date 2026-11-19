//
//  EntityBindingEvaluationTests.swift
//  OpenIntelligenceTests
//
//  Twelve entity-attribute questions about the guide "RAG Technical Architecture", whose "Quality modes" list gives
//  each mode's similarity floor, candidates per step, query variants and verification threshold, one mode per list
//  item (5.8, 2026-11-18). On the owner's iPhone "What is the similarity floor in Standard mode?" was answered "0.20
//  [S2]", Maximum's floor two lines further down, and Fact Check marked it Supported: one passage holds all three
//  modes, so the value was in it. Each question has one right value and two wrong ones (the other modes'), which
//  tells a right answer from one that took a value from the wrong list item.
//
//  Each answer is also followed by a probe: Fact Check (`VerificationGateService.claimVerdicts`) on the passages that
//  answer retrieved, for a claim stating each mode's value for the asked mode, so the check is measured whether or not
//  the model got the value wrong.
//
//  The three guides are imported into a library of their own, as the app imports them, and each question is asked
//  through the engine's `query`, as Chat asks it, with the app's own model service. Opt-in: it needs Apple's model
//  and a copy patched by `scripts/sim_model_copy.py` (`OI_ENTITY_EVALS=1`, each setting with the `TEST_RUNNER_`
//  prefix in `xcodebuild`'s environment):
//  - `OI_EVAL_MODE` standard (the default), deepThink or maximum: the mode the questions are asked in.
//  - `OI_ENTITY_RUNS` how many times the twelve are asked in one process (2 by default; retrieval is not deterministic).
//  - `OI_ENTITY_OUT` a folder each answer, its claims and their verdicts, and its passages are written to as JSON lines.
//  `BenchmarkRuns/2026-11-18-entity-binding/run.sh` builds the copy and runs it.
//

import Foundation
import FoundationModels
import Testing

@testable import OpenIntelligence

/// One question: the mode it is about, what it asks, and each mode's value for that attribute.
struct EntityBindingCase: Sendable {
    let id: String
    let entity: String
    let question: String
    /// The values the guide gives the attribute, by mode.
    let values: [String: [String]]
    /// A claim that this mode's attribute is a value, as an answer would state it.
    let statement: @Sendable (String, String) -> String

    var expected: [String] { values[entity] ?? [] }
    var wrong: [String] { values.filter { $0.key != entity }.flatMap(\.value) }

    /// The twelve, from the guide's "Quality modes" list (`SampleDocumentManager`, "RAG Technical Architecture").
    static let all: [EntityBindingCase] = {
        let modes = ["Standard", "Deep Think", "Maximum"]
        let attributes:
            [(id: String, ask: (String) -> String, values: [String: [String]], statement: @Sendable (String, String) -> String)] = [
                ("floor", { "What is the similarity floor in \($0) mode?" },
                 ["Standard": ["0.28"], "Deep Think": ["0.25"], "Maximum": ["0.20"]],
                 { "The similarity floor in \($0) mode is \($1)." }),
                ("candidates", { "How many candidate passages does \($0) mode retrieve per step?" },
                 ["Standard": ["30"], "Deep Think": ["35"], "Maximum": ["50"]],
                 { "\($0) mode retrieves \($1) candidate passages per step." }),
                ("variants", { "How many query variants does \($0) mode use?" },
                 ["Standard": ["no query expansion"], "Deep Think": ["8"], "Maximum": ["12"]],
                 { "\($0) mode uses up to \($1) query variants." }),
                ("threshold", { "What is the verification confidence threshold in \($0) mode?" },
                 ["Standard": ["0.50"], "Deep Think": ["0.60"], "Maximum": ["0.80"]],
                 { "The verification confidence threshold in \($0) mode is \($1)." }),
            ]
        return attributes.flatMap { attribute in
            modes.map { mode in
                EntityBindingCase(
                    id: "\(attribute.id)-\(mode.lowercased().replacingOccurrences(of: " ", with: ""))", entity: mode,
                    question: attribute.ask(mode), values: attribute.values, statement: attribute.statement)
            }
        }
    }()

    /// Whether a text states one of `values`: a number by its value ("0.2" is "0.20"), words as words. "No query
    /// expansion" is also stated as "none", "no variants", "zero" or "0 variants".
    static func states(_ values: [String], in text: String) -> Bool {
        let lower = text.lowercased()
        let pattern = try? NSRegularExpression(pattern: #"(?<![\w.])\d+(?:\.\d+)?(?![\w])"#)
        let whole = NSRange(lower.startIndex..., in: lower)
        let numbers = Set(
            (pattern?.matches(in: lower, range: whole) ?? []).compactMap { match in
                Range(match.range, in: lower).flatMap { Double(lower[$0]) }
            })
        return values.contains { value in
            if let number = Double(value) { return numbers.contains(number) }
            if value == "no query expansion" {
                return lower.contains("no query expansion") || lower.contains("does not expand")
                    || lower.contains("doesn't expand") || lower.contains("no expansion")
                    || lower.contains("no variants") || lower.contains("no query variants")
                    || lower.contains("none") || lower.contains("zero") || numbers.contains(0)
                    || lower.contains("not expand") || lower.contains("without query expansion")
            }
            return lower.contains(value.lowercased())
        }
    }

    /// right: states this mode's value. wrongEntity: states another mode's value and not this one's. miss: neither.
    func grade(_ answer: String) -> String {
        if Self.states(expected, in: answer) { return "right" }
        if Self.states(wrong, in: answer) { return "wrongEntity" }
        return "miss"
    }
}

/// Why a run could not start, said in the test's failure.
private struct EntityBindingSetupError: Error, CustomStringConvertible {
    let description: String
}

@Suite(
    "Entity-attribute questions about the guide's quality modes",
    .enabled(if: ProcessInfo.processInfo.environment["OI_ENTITY_EVALS"] == "1"), .serialized)
struct EntityBindingEvaluationTests {
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    @available(iOS 27.0, macOS 27.0, *)
    @MainActor
    @Test(.timeLimit(.minutes(240)))
    func modesValuesAreBoundToTheirModes() async throws {
        #if os(macOS)
            // Hosted on the Mac this would import into, and change the plan settings of, the owner's own app.
            print("[EntityBinding] skipped: run it in the iOS Simulator (BenchmarkRuns/2026-11-18-entity-binding/run.sh)")
            return
        #endif
        let modeName = Self.environment["OI_EVAL_MODE"] ?? "standard"
        let mode = OIAnswerMode(rawValue: modeName) ?? .standard
        let runs = Int(Self.environment["OI_ENTITY_RUNS"] ?? "") ?? 2
        let out = Self.environment["OI_ENTITY_OUT"].map { URL(fileURLWithPath: $0, isDirectory: true) }

        for _ in 0..<60 where !SystemLanguageModel.default.isAvailable {
            try await Task.sleep(for: .seconds(5))
        }
        let service = AppleFoundationLLMService()
        guard service.isAvailable else {
            throw EntityBindingSetupError(
                description: "the app's own model service is off here: run a copy patched by scripts/sim_model_copy.py")
        }

        // A library of its own, on a plan that allows it, as `AnswerQualityEvaluationTests` makes one.
        let tierKey = "entitlement.activeTier"
        let plan = UserDefaults(suiteName: "EntityBindingEvaluation.plan") ?? .standard
        plan.set(WorkspaceTier.pro.rawValue, forKey: tierKey)
        let store = EntitlementStore(billingService: StoreKitBillingService(), defaults: plan)
        let libraries = IntentSupport.libraries()
        let engine = RAGService(llmService: service, containerService: libraries, entitlementStore: store)
        for _ in 0..<100 where !engine.hasLoadedDocumentsFromDisk {
            try await Task.sleep(for: .milliseconds(100))
        }
        for leftover in libraries.containers where leftover.name.hasPrefix("Entity binding ") {
            for document in engine.documents where document.containerId == leftover.id {
                try? await engine.removeDocument(document)
            }
            libraries.deleteContainer(id: leftover.id)
        }
        let savedTier = UserDefaults.standard.string(forKey: tierKey)
        let savedMaximumCount = UserDefaults.standard.integer(forKey: "entitlement.maximumMode.usedCount")
        UserDefaults.standard.set(WorkspaceTier.pro.rawValue, forKey: tierKey)
        let created = Result { try libraries.createContainer(name: "Entity binding \(UUID().uuidString.prefix(6))") }
        if mode != .maximum {
            if let savedTier { UserDefaults.standard.set(savedTier, forKey: tierKey) } else {
                UserDefaults.standard.removeObject(forKey: tierKey)
            }
        }
        let library = try created.get()

        // The three guides as the app writes them, under the names it gives them.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EntityBindingGuides", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var files: [URL] = []
        for (name, body) in SampleDocumentManager.shared.sampleBodiesByName {
            let url = folder.appendingPathComponent(name.replacingOccurrences(of: " ", with: "-") + ".md")
            try body.write(to: url, atomically: true, encoding: .utf8)
            files.append(url)
        }
        let imported = await engine.ingestDocuments(files, context: .onboarding, containerId: library.id)
        print("[EntityBinding] imported \(imported.successCount) of \(files.count) guides; mode=\(modeName) runs=\(runs)")
        #expect(imported.successCount == 3)

        if let out { try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true) }
        var tally: [String: Int] = [:]
        var falseSupported = 0
        for run in 1...runs {
            var lines: [String] = []
            for evalCase in EntityBindingCase.all {
                if mode == .maximum {
                    UserDefaults.standard.set(WorkspaceTier.pro.rawValue, forKey: tierKey)
                    UserDefaults.standard.set(0, forKey: "entitlement.maximumMode.usedCount")
                }
                let started = Date()
                let record: [String: Any]
                do {
                    let response = try await engine.query(
                        evalCase.question, topK: 3, containerId: library.id, qualityModeOverride: mode.qualityMode)
                    let answer = response.generatedResponse
                    let grade = evalCase.grade(answer)
                    let claims = response.structuredAnswer?.claims ?? []
                    let claimRecords: [[String: Any]] = claims.map { claim in
                        let claimGrade = evalCase.grade(claim.claim)
                        let verdict = claim.verificationVerdict?.rawValue ?? "none"
                        return [
                            "claim": claim.claim, "verdict": verdict, "confidence": claim.confidence,
                            "details": claim.verificationDetails ?? "", "grade": claimGrade,
                        ]
                    }
                    let wrongSupported = claimRecords.filter {
                        ($0["grade"] as? String) == "wrongEntity" && ($0["verdict"] as? String) == "supported"
                    }.count
                    falseSupported += wrongSupported
                    // Fact Check on the passages this answer retrieved, for a claim stating each mode's value for the
                    // asked mode: the right one should hold, the other two should not. This measures the check whatever
                    // the model wrote.
                    var probes: [[String: Any]] = []
                    for (owner, values) in evalCase.values.sorted(by: { $0.key < $1.key }) {
                        guard let value = values.first, Double(value) != nil else { continue }
                        let probe = evalCase.statement(evalCase.entity, value)
                        let verdict = await VerificationGateService().claimVerdicts(
                            for: [probe], response: probe, chunks: response.retrievedChunks, query: evalCase.question
                        ).first
                        probes.append([
                            "claim": probe, "right": owner == evalCase.entity,
                            "verdict": verdict?.verdict.rawValue ?? "none", "details": verdict?.details ?? "",
                        ])
                    }
                    let probeLine = probes.map { "\(($0["right"] as? Bool) == true ? "right" : "wrong"):\($0["verdict"] ?? "")" }
                        .joined(separator: ",")
                    print("[EntityBinding] run=\(run) qid=\(evalCase.id) probes=[\(probeLine)]")
                    tally[grade, default: 0] += 1
                    let verdicts = claimRecords.map { "\($0["verdict"] ?? ""):\($0["grade"] ?? "")" }.joined(separator: ",")
                    print(
                        "[EntityBinding] run=\(run) qid=\(evalCase.id) grade=\(grade) claims=[\(verdicts)] "
                            + "falseSupported=\(wrongSupported) seconds=\(Int(Date().timeIntervalSince(started))) "
                            + "gating=\(response.metadata.gatingDecision ?? "none") "
                            + "answer=\(answer.prefix(240).replacingOccurrences(of: "\n", with: " "))")
                    record = [
                        "run": run, "qid": evalCase.id, "question": evalCase.question, "expected": evalCase.expected,
                        "grade": grade, "answer": answer, "claims": claimRecords, "probes": probes,
                        "confidence": response.confidenceScore, "gating": response.metadata.gatingDecision ?? "",
                        "warnings": response.qualityWarnings,
                        "seconds": Date().timeIntervalSince(started),
                        "passages": response.retrievedChunks.map {
                            ["document": $0.sourceDocument, "score": $0.similarityScore, "text": $0.chunk.contextText]
                        },
                    ]
                } catch {
                    tally["error", default: 0] += 1
                    print("[EntityBinding] run=\(run) qid=\(evalCase.id) grade=error error=\(error)")
                    record = ["run": run, "qid": evalCase.id, "grade": "error", "error": "\(error)"]
                }
                if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
                    let line = String(data: data, encoding: .utf8)
                {
                    lines.append(line)
                }
            }
            if let out {
                try? (lines.joined(separator: "\n") + "\n").write(
                    to: out.appendingPathComponent("\(modeName)-run\(run).jsonl"), atomically: true, encoding: .utf8)
            }
        }
        print(
            "[EntityBinding] total mode=\(modeName) runs=\(runs) right=\(tally["right", default: 0]) "
                + "wrongEntity=\(tally["wrongEntity", default: 0]) miss=\(tally["miss", default: 0]) "
                + "error=\(tally["error", default: 0]) falseSupportedClaims=\(falseSupported)")

        for document in engine.documents where document.containerId == library.id {
            try? await engine.removeDocument(document)
        }
        libraries.deleteContainer(id: library.id)
        if mode == .maximum {
            if let savedTier { UserDefaults.standard.set(savedTier, forKey: tierKey) } else {
                UserDefaults.standard.removeObject(forKey: tierKey)
            }
            UserDefaults.standard.set(savedMaximumCount, forKey: "entitlement.maximumMode.usedCount")
        }
        #expect(tally["error", default: 0] == 0)
    }
}
