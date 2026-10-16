import Combine
import Foundation
import SwiftUI

/// Asks for an App Store rating at the one moment the app has just proved
/// itself: right after the first answer that came from the person's own files.
///
/// The product page had a single written review on 2026-09-05 and every
/// visitor sees that number before anything else. Apple shows the rating
/// sheet at most three times a year and decides itself whether to show it at
/// all; this decides only when to ask. Never on launch, never after an
/// answer the verifier flagged or the app abstained from, never twice in
/// 120 days, never under tests.
///
/// Until 5.3 the threshold was three answers, and a second, older prompt in
/// `ChatScreen` needed three answers on two separate days. 37% of device-weeks
/// in the App Store data show one session, so most people were never asked.
/// Apple's own budget is three prompts a year; it should be spent on the first
/// success, not saved for a third that rarely comes.
@MainActor
final class ReviewPromptService: ObservableObject {
    static let shared = ReviewPromptService()

    /// Flipped true when the next good moment arrives; ContentView consumes it.
    @Published private(set) var wantsPrompt = false

    private let defaults = UserDefaults.standard
    private let countKey = "reviewPrompt.verifiedAnswers"
    private let lastAskedKey = "reviewPrompt.lastAskedAt"
    nonisolated static let minimumVerifiedAnswers = 1
    private let minimumDaysBetweenAsks = 120.0

    /// Called with the gating decision of every finished answer, how many
    /// sources it cited, and Fact Check's claims.
    func noteAnswer(gatingDecision: String?, retrievedSourceCount: Int, claims: [StructuredAnswer.Claim] = []) {
        guard Self.isVerified(gatingDecision, retrievedSourceCount: retrievedSourceCount, claims: claims) else { return }
        let n = defaults.integer(forKey: countKey) + 1
        defaults.set(n, forKey: countKey)
        guard n >= Self.minimumVerifiedAnswers, !askedRecently, !isTesting else { return }
        wantsPrompt = true
    }

    /// ContentView calls this once it has handed the request to StoreKit.
    func didAsk() {
        defaults.set(Date().timeIntervalSince1970, forKey: lastAskedKey)
        wantsPrompt = false
    }

    private var askedRecently: Bool {
        let t = defaults.double(forKey: lastAskedKey)
        guard t > 0 else { return false }
        return Date().timeIntervalSince1970 - t < minimumDaysBetweenAsks * 86_400
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
