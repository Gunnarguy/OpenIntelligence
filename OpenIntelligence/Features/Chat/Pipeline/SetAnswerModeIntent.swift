//
//  SetAnswerModeIntent.swift
//  OpenIntelligence
//

import AppIntents
import Foundation

/// Sets the answer mode the chat uses, Standard, Deep Think or Maximum, as the mode menu does (5.7).
///
/// A shortcut can switch to Deep Think before it asks, or a Focus automation can pick a mode. With
/// the app open the chat changes at once; otherwise the mode is saved where the chat reads it at
/// launch (`AnswerModeSetting`). Maximum on the free plan follows the daily limit, as Settings does
/// (`ShortcutsPlanGate.checkMaximumAvailable`). Run from the app, the change can be undone
/// (`UndoableIntent`). An ask action that names its own mode answers in that mode and leaves this
/// setting as it was.
@available(iOS 26.0, macOS 26.0, *)
struct SetAnswerModeIntent: SetValueIntent, UndoableIntent {
    static var title: LocalizedStringResource = "Set Answer Mode"
    static var description: IntentDescription = .init(
        "Chooses the answer mode the chat uses: Standard, Deep Think or Maximum.",
        categoryName: "Ask",
        searchKeywords: ["mode", "deep think", "maximum", "standard", "answer"]
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Answer Mode")
    var value: OIAnswerMode

    static var parameterSummary: some ParameterSummary {
        Summary("Set the answer mode to \(\.$value)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<OIAnswerMode> & ProvidesDialog {
        let wanted = value
        if wanted == .maximum {
            try await MainActor.run { try ShortcutsPlanGate.checkMaximumAvailable() }
        }
        let previous = await MainActor.run { () -> RAGQualityMode in
            let before = AnswerModeSetting.current
            AnswerModeSetting.set(wanted.qualityMode)
            return before
        }
        if previous.canonical != wanted.qualityMode {
            await registerUndo(restoring: previous)
        }
        return .result(value: wanted, dialog: "Questions in the chat use \(wanted.name) now.")
    }

    @MainActor
    private func registerUndo(restoring previous: RAGQualityMode) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: AnswerModeSetting.undoTarget) { _ in
            AnswerModeSetting.set(previous)
        }
        let name: String = "Set Answer Mode"
        undoManager.setActionName(name)
    }
}

/// Where the chat's answer mode lives: the settings the app's screens use when the app is open
/// (`RAGService.registeredSettingsStore`), otherwise the saved value the chat reads at launch, under
/// the key `SettingsStore` writes.
@available(iOS 26.0, macOS 26.0, *)
@MainActor
enum AnswerModeSetting {
    /// What an undo is registered against: the mode is not an object of its own.
    final class UndoTarget {}
    static let undoTarget = UndoTarget()

    static let defaultsKey = "ragQualityMode"

    static var current: RAGQualityMode {
        if let store = RAGService.activePresentedInstance?.registeredSettingsStore {
            return store.ragQualityMode
        }
        return UserDefaults.standard.string(forKey: defaultsKey).flatMap(RAGQualityMode.init(rawValue:)) ?? .standard
    }

    /// Changes the mode as the chat's own menu does, clearing the last Deep Think or Maximum
    /// answer's live figures when the mode changes, so they are not shown under the new mode.
    static func set(_ mode: RAGQualityMode) {
        guard let engine = RAGService.activePresentedInstance, let store = engine.registeredSettingsStore else {
            UserDefaults.standard.set(mode.rawValue, forKey: defaultsKey)
            return
        }
        let changed = store.ragQualityMode.canonical != mode.canonical
        store.ragQualityMode = mode
        if changed { engine.resetDeepThinkLiveMetrics() }
    }
}
