//
//  RAGService+BackgroundModelCalls.swift
//  OpenIntelligence
//
//  Deep Think starts no model call on the device while the app is in the background (5.8).
//

import Foundation

extension RAGService {
    /// Set by Chat around its query (5.8). An answer asked through Siri or Shortcuts runs while the app is in the
    /// background by design, so it is never held for the app to come forward.
    @TaskLocal static var answerAskedInChat = false

    /// Waits, before a Deep Think or Maximum model call, while the app is in the background, for an answer asked in
    /// Chat that this call runs on the device. iOS rate-limits the on-device model for an app in the background: on the
    /// owner's iPhone on 2026-11-05 synthesis started two seconds after he left the app, Apple's model answered
    /// `rateLimited` twice, and the answer was lost when iOS later ended the app (roadmap row
    /// `40f49a74d54f812dbdd8fd628b622299`). Until then the wait ran only after a refusal. `onDevice` is true for a call
    /// pinned to the device (the reasoning sessions pass `forceOnDevice: true`); otherwise the route preference decides,
    /// and an answer that may use Private Cloud Compute asks iOS for background time
    /// (`OpenIntelligenceApp.configureQueryRuntimeBridge`) and is not held.
    func waitBeforeModelCallWhileInBackground(_ step: String, onDevice: Bool = false) async {
        guard Self.answerAskedInChat else { return }
        let held: Bool = await MainActor.run {
            if onDevice { return true }
            switch settingsStore?.fmPreference.canonical {
            case .core3B?, .advanced20B?: return true
            default: return false
            }
        }
        guard held else { return }
        let waited = await Self.waitWhileAppIsInBackground()
        if waited > 0.5 {
            await MainActor.run {
                VerificationJournal.record(
                    "answer.waitedForForeground", ["step": step, "seconds": String(format: "%.1f", waited)])
            }
            Log.info("[Background] Waited \(String(format: "%.1f", waited)) s for the app before \(step)", category: .llm)
        }
    }
}
