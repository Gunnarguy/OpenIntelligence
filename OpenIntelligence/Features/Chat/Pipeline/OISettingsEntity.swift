//
//  OISettingsEntity.swift
//  OpenIntelligence
//

import AppIntents
import Foundation

/// OpenIntelligence's settings as one item a shortcut can read (5.7, `UniqueAppEntity`): the answer
/// mode the chat uses, the active library and how many libraries there are. With "Set Answer Mode"
/// and "Set Active Library" a shortcut can note them, change them for a task and put them back.
/// There is only ever one, so Shortcuts never asks which (`UniqueAppEntityProvider`).
@available(iOS 26.0, macOS 26.0, *)
struct OISettingsEntity: UniqueAppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "OpenIntelligence Settings")
    static var defaultQuery = UniqueAppEntityProvider { await OISettingsEntity.current() }

    var id: String { "OpenIntelligence.settings" }

    @Property(title: "Answer Mode")
    var answerMode: OIAnswerMode

    @Property(title: "Active Library")
    var activeLibrary: OILibraryEntity?

    @Property(title: "Libraries")
    var libraryCount: Int

    init(answerMode: OIAnswerMode, activeLibrary: OILibraryEntity?, libraryCount: Int) {
        self.answerMode = answerMode
        self.activeLibrary = activeLibrary
        self.libraryCount = libraryCount
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "OpenIntelligence Settings",
            subtitle: "\(answerMode.name), \(activeLibrary?.name ?? "no active library")")
    }

    /// The settings as the app holds them now: the open chat's when the app is up, the saved ones
    /// otherwise (`AnswerModeSetting`, `IntentSupport.libraries`).
    @MainActor
    static func current() -> OISettingsEntity {
        let libraries = IntentSupport.libraries()
        return OISettingsEntity(
            answerMode: OIAnswerMode(AnswerModeSetting.current),
            activeLibrary: libraries.activeContainer.map(OILibraryEntityQuery.entity(for:)),
            libraryCount: libraries.containers.count)
    }
}

/// Hands a shortcut OpenIntelligence's settings (5.7).
@available(iOS 26.0, macOS 26.0, *)
struct GetSettingsIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Settings"
    static var description: IntentDescription = .init(
        "Gets OpenIntelligence's answer mode and active library, so a shortcut can read them or put them back later.",
        categoryName: "Ask",
        searchKeywords: ["settings", "mode", "library", "active"]
    )

    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<OISettingsEntity> {
        .result(value: await OISettingsEntity.current())
    }
}
