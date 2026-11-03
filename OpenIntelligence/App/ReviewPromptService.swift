import Combine
import Foundation
import SwiftUI

/// Asks for an App Store rating with Apple's own sheet, the only way the app asks: stars and an optional written
/// review, sent without leaving the app.
///
/// When: on the first answer that came from the person's own files and was verified, or on the third finished answer
/// of any kind, whichever comes first. Once per app version, as Apple's sample does, and never within 14 days of the
/// last ask (Human Interface Guidelines, Ratings and reviews: "a week or two between requests"). Never on launch,
/// never from a button, never under tests.
///
/// Apple shows the sheet at most three times in 365 days on a device, and decides itself whether to show it at all;
/// this decides only when to ask (`RequestReviewAction`, read 2026-11-03).
///
/// Until 5.8 it asked only on a verified answer and then waited 120 days, so a person whose answers never earned the
/// badge was never asked, and one asked in 5.6 was not asked again for four releases. A custom "Enjoying
/// OpenIntelligence?" alert after a thumbs-up also existed; it was removed in 5.8, because App Review Guideline 5.6.1
/// disallows custom review prompts and its "I love it" button called the sheet from a tap, which Apple says may show
/// nothing. On 2026-11-03 the US store had 4 ratings and 2 written reviews, and the other 11 storefronts checked had
/// none.
@MainActor
final class ReviewPromptService: ObservableObject {
    static let shared = ReviewPromptService()

    /// Flipped true when the next good moment arrives; ContentView consumes it.
    @Published private(set) var wantsPrompt = false

    private let defaults = UserDefaults.standard
    private let countKey = "reviewPrompt.verifiedAnswers"
    private let finishedKey = "reviewPrompt.finishedAnswers"
    private let lastAskedKey = "reviewPrompt.lastAskedAt"
    private let lastAskedVersionKey = "reviewPrompt.lastAskedVersion"
    nonisolated static let minimumVerifiedAnswers = 1
    nonisolated static let minimumFinishedAnswers = 3
    nonisolated static let minimumDaysBetweenAsks = 14.0

    /// Called with the gating decision of every finished answer, how many
    /// sources it cited, and Fact Check's claims.
    func noteAnswer(gatingDecision: String?, retrievedSourceCount: Int, claims: [StructuredAnswer.Claim] = []) {
        let verified = Self.isVerified(gatingDecision, retrievedSourceCount: retrievedSourceCount, claims: claims)
        let finished = defaults.integer(forKey: finishedKey) + 1
        defaults.set(finished, forKey: finishedKey)
        var verifiedCount = defaults.integer(forKey: countKey)
        if verified {
            verifiedCount += 1
            defaults.set(verifiedCount, forKey: countKey)
        }
        let lastAsked = defaults.double(forKey: lastAskedKey)
        guard
            Self.shouldAsk(
                thisAnswerIsVerified: verified, verifiedAnswers: verifiedCount, finishedAnswers: finished,
                lastAskedVersion: defaults.string(forKey: lastAskedVersionKey), currentVersion: Self.currentVersion,
                daysSinceLastAsk: lastAsked > 0 ? (Date().timeIntervalSince1970 - lastAsked) / 86_400 : nil,
                isTesting: isTesting)
        else { return }
        wantsPrompt = true
    }

    /// ContentView calls this once it has handed the request to StoreKit.
    func didAsk() {
        defaults.set(Date().timeIntervalSince1970, forKey: lastAskedKey)
        defaults.set(Self.currentVersion, forKey: lastAskedVersionKey)
        wantsPrompt = false
    }

    /// Pure, so every rule above is pinned by a test. Counts include the answer that just finished.
    nonisolated static func shouldAsk(
        thisAnswerIsVerified: Bool, verifiedAnswers: Int, finishedAnswers: Int, lastAskedVersion: String?,
        currentVersion: String, daysSinceLastAsk: Double?, isTesting: Bool
    ) -> Bool {
        guard !isTesting, !currentVersion.isEmpty, lastAskedVersion != currentVersion else { return false }
        if let days = daysSinceLastAsk, days < minimumDaysBetweenAsks { return false }
        return (thisAnswerIsVerified && verifiedAnswers >= minimumVerifiedAnswers)
            || finishedAnswers >= minimumFinishedAnswers
    }

    private static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private var isTesting: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains("-uiTesting")
    }

    /// The reading the message bubble uses for its Verified badge (`VerificationOutcome.from(gatingDecision:claims:)`):
    /// an answer counts only when its badge says Verified. Until 5.7 this kept its own list of failure words, which
    /// missed the `unverified:<gates>` a failed check writes, so an answer under a red Unverified badge counted.
    ///
    /// Deep Think and Maximum answers leave the gating string nil unless the
    /// source-only refinement ran, so a nil string is read by what it cited:
    /// sources present counts, none does not. Before this, no agentic answer
    /// ever counted, which excluded the most engaged users from ever being asked.
    nonisolated static func isVerified(
        _ gatingDecision: String?, retrievedSourceCount: Int, claims: [StructuredAnswer.Claim] = []
    ) -> Bool {
        guard let decision = gatingDecision, !decision.isEmpty else { return retrievedSourceCount > 0 }
        return VerificationOutcome.from(gatingDecision: decision, claims: claims) == .supported
    }
}
