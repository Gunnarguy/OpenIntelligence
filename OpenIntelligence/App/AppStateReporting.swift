//
//  AppStateReporting.swift
//  OpenIntelligence
//

import Foundation

#if canImport(StateReporting)
    import StateReporting
#endif

/// What the app is doing, for the system's diagnostics (5.7). From iOS and macOS 27, MetricKit and
/// Instruments show an app's reported state beside its memory, CPU and terminations, so a report
/// from a device says whether an import or a Deep Think answer was running when the app was ended
/// (Apple's "Getting started with StateReporting", read 2026-10-14). Two domains, each with a few
/// fixed labels and no metadata: an import running, and the answer mode of a question running.
/// Nothing of a document or a question is in a label, and the reports stay on the device
/// (`MetricDiagnostics`). Called at the start and end of each, never in a loop, as Apple's rate
/// limit asks.
enum AppStateReporting {
    nonisolated static let importDomain = "com.openintelligence.import"
    nonisolated static let answerDomain = "com.openintelligence.answer"

    static func importBegan() { report(importDomain, "Importing") }
    static func importEnded() { report(importDomain, nil) }

    /// The chat's mode setting, which is the mode its question runs in; the begin call does not
    /// carry it.
    static func answerBegan() {
        report(answerDomain, answerLabel(storedMode: UserDefaults.standard.string(forKey: "ragQualityMode")))
    }

    static func answerEnded() { report(answerDomain, nil) }

    /// "Standard", "Deep Think" or "Maximum"; a legacy stored value maps as the app maps it.
    static func answerLabel(storedMode: String?) -> String {
        RAGQualityMode(rawValue: storedMode ?? "")?.displayName ?? RAGQualityMode.standard.displayName
    }

    private static func report(_ domain: String, _ label: String?) {
        #if canImport(StateReporting)
            if #available(iOS 27.0, macOS 27.0, *) {
                // Always without metadata: a domain asked for again with other metadata types crashes.
                StateReporter<Never, Never>.reporter(for: domain).reportTransition(to: label)
            }
        #endif
    }
}
