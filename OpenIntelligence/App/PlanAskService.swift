//
//  PlanAskService.swift
//  OpenIntelligence
//
//  One unprompted look at the plans screen, at the moment the app has just proved itself.
//
//  WHY THIS EXISTS
//
//  Ninety days of App Store Connect data (2026-09-18): the people who buy decide within two days
//  of download, and the plans screen was reachable only by going looking for it. So the one
//  moment the app is allowed to open that screen on its own is right after a verified answer, the
//  same trigger `ReviewPromptService` uses for the rating request, because that is the moment the
//  product has just done the thing it is for.
//
//  WHAT KEEPS THIS FROM BEING A NAG
//
//  It fires once, ever, per install. It fires only for the free tier. It fires on the verified
//  answer AFTER the one that requested a rating, so the two sheets never compete for the same
//  moment. It is a sheet the user closes; nothing is pre-selected, nothing counts down. The
//  decision is a pure function so every one of those properties is pinned by a test.
//

import Combine
import Foundation

@MainActor
final class PlanAskService: ObservableObject {
    static let shared = PlanAskService()

    @Published private(set) var wantsAsk = false

    private let defaults = UserDefaults.standard
    private let shownKey = "planAsk.shownAt"
    private let verifiedCountKey = "reviewPrompt.verifiedAnswers"   // shared with ReviewPromptService, read only

    /// The review prompt asks at `ReviewPromptService.minimumVerifiedAnswers` (3); this asks one
    /// verified answer later, so the sheets are never stacked on one answer.
    nonisolated static let minimumVerifiedAnswers = 4

    /// Pure. `verifiedAnswers` is the count including the answer that just landed.
    nonisolated static func shouldAsk(verifiedAnswers: Int, isFreeTier: Bool, alreadyShown: Bool, isTesting: Bool) -> Bool {
        !alreadyShown && isFreeTier && !isTesting && verifiedAnswers >= minimumVerifiedAnswers
    }

    /// Call after `ReviewPromptService.shared.noteAnswer`, which is what increments the count.
    func noteAnswer(gatingDecision: String?, isFreeTier: Bool) {
        guard ReviewPromptService.isVerified(gatingDecision) else { return }
        let n = defaults.integer(forKey: verifiedCountKey)
        guard Self.shouldAsk(verifiedAnswers: n, isFreeTier: isFreeTier, alreadyShown: defaults.double(forKey: shownKey) > 0, isTesting: isTesting) else { return }
        wantsAsk = true
    }

    func didAsk() {
        defaults.set(Date().timeIntervalSince1970, forKey: shownKey)
        wantsAsk = false
    }

    private var isTesting: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains("-uiTesting")
    }
}
