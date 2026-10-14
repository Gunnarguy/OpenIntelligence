//
//  AppleIntelligenceAvailability.swift
//  OpenIntelligence
//

import Foundation

/// Why Apple's on-device model cannot be used, as `SystemLanguageModel.availability` reports it.
///
/// The app kept this reason only as a sentence for the Settings model card. Every other surface
/// asked one question, "is it available", and answered a no the same way: chat said "Apple
/// Intelligence isn't available. Enable it in Settings." on a device that can never enable it, and
/// Settings said "Preparing AI Models..." without end.
nonisolated enum AppleIntelligenceUnavailability: String, Sendable, Equatable {
    /// The hardware cannot run Apple Intelligence. Nothing the person does changes this.
    case deviceNotEligible
    /// The hardware can run it and it is switched off in Settings.
    case notEnabled
    /// It is switched on and the model is still downloading or starting.
    case modelNotReady
    /// The system gave a reason this build does not know.
    case unknown
}

/// The words each surface uses for an unavailable model. One place, so the chat error, the Settings
/// status and the notice on an empty chat never disagree.
nonisolated enum AppleIntelligenceCopy {
    /// The hardware Apple lists for Apple Intelligence (support.apple.com/en-us/121115, read
    /// 2026-10-06), in the short form the store description uses.
    static let supportedDevices =
        "an iPhone 15 Pro, any iPhone 16 or later, an iPad mini with A17 Pro, or an iPad or Mac with an M1 chip or later"

    /// A few words for a status chip or a Settings row.
    static func status(for reason: AppleIntelligenceUnavailability?) -> String {
        switch reason {
        case .deviceNotEligible: return "Not supported on this device"
        case .notEnabled: return "Apple Intelligence is turned off"
        case .modelNotReady: return "Apple Intelligence is downloading"
        case .unknown, nil: return "Apple Intelligence unavailable"
        }
    }

    /// What chat says when a question could not be answered because the model is unavailable.
    static func chatMessage(for reason: AppleIntelligenceUnavailability?) -> String {
        switch reason {
        case .deviceNotEligible:
            return
                "This device can't run Apple Intelligence, so OpenIntelligence can't write answers on it. It needs \(supportedDevices)."
        case .notEnabled:
            return
                "Apple Intelligence is turned off. Turn it on in Settings > Apple Intelligence & Siri, then ask again."
        case .modelNotReady:
            return
                "Apple Intelligence is still downloading its model. Give it a few minutes, then ask again."
        case .unknown, nil:
            return "Apple Intelligence isn't available right now. Try again in a moment."
        }
    }

    /// The last line of an answer made of excerpts because no answer was written (5.7). Through 5.6
    /// it said "the model may be temporarily rate-limited" whatever the cause, which on a device
    /// that cannot run the model is not the reason (backlog row 3e449a74d54f8170a3cbfb570a41d0a5).
    static func excerptClosing(for reason: AppleIntelligenceUnavailability?, isAvailable: Bool) -> String {
        guard !isAvailable else { return "The model didn't write an answer this time. Try asking again in a moment." }
        switch reason {
        case .deviceNotEligible:
            return "These are excerpts, not a written answer: this device can't run Apple Intelligence."
        case .notEnabled:
            return
                "These are excerpts, not a written answer: Apple Intelligence is turned off. Turn it on in Settings > Apple Intelligence & Siri for written answers."
        case .modelNotReady:
            return "These are excerpts, not a written answer: Apple Intelligence is still downloading its model."
        case .unknown, nil:
            return "These are excerpts, not a written answer: Apple Intelligence isn't available right now."
        }
    }

    /// The notice an empty chat shows before the first question, or nil when the model is available.
    /// It says what still works: documents are read, indexed and searched without the model, and a
    /// Standard question comes back as excerpts from them.
    static func notice(for reason: AppleIntelligenceUnavailability?, isAvailable: Bool) -> String? {
        guard !isAvailable else { return nil }
        let stillWorks =
            "OpenIntelligence can still read, index and search your documents, and Standard questions come back as excerpts from them instead of written answers."
        switch reason {
        case .deviceNotEligible:
            return "This device can't run Apple Intelligence. \(stillWorks) Written answers need \(supportedDevices)."
        case .notEnabled:
            return
                "Apple Intelligence is turned off. \(stillWorks) Turn it on in Settings > Apple Intelligence & Siri for written answers."
        case .modelNotReady:
            return
                "Apple Intelligence is still downloading its model. Until it finishes, Standard questions come back as excerpts from your documents instead of written answers."
        case .unknown, nil:
            return "Apple Intelligence isn't available right now. \(stillWorks)"
        }
    }
}
