//
//  LibraryIntents.swift
//  OpenIntelligence
//

import AppIntents
import Foundation

/// Creates a library and returns it, so a shortcut can go on to add files to it.
///
/// The plan's library limit applies: `ContainerService.createContainer` throws when the limit is
/// reached, and the action fails with that message.
@available(iOS 26.0, macOS 26.0, *)
struct CreateLibraryIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Library"
    static var description: IntentDescription = .init(
        "Creates a new library in OpenIntelligence.",
        categoryName: "Libraries",
        searchKeywords: ["library", "new", "create", "collection"]
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Name")
    var name: String

    @Parameter(title: "Make Active", description: "Switch to the new library", default: true)
    var makeActive: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Create a library named \(\.$name)") {
            \.$makeActive
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<OILibraryEntity> & ProvidesDialog {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else {
            throw $name.needsValueError("What should the library be called?")
        }

        let activate = makeActive
        let created: KnowledgeContainer
        do {
            created = try await MainActor.run {
                let libraries = IntentSupport.libraries()
                let container = try libraries.createContainer(name: wanted)
                if activate { libraries.setActive(container.id) }
                return container
            }
        } catch {
            throw OIIntentError(error.localizedDescription)
        }

        return .result(
            value: OILibraryEntityQuery.entity(for: created),
            dialog: "Created the library \(created.name).")
    }
}

/// Makes a library the active one, the library questions and imports go to by default.
@available(iOS 26.0, macOS 26.0, *)
struct SetActiveLibraryIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Active Library"
    static var description: IntentDescription = .init(
        "Chooses the library that questions and imports use by default.",
        categoryName: "Libraries",
        searchKeywords: ["library", "switch", "active", "select"]
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Library")
    var library: OILibraryEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Make \(\.$library) the active library")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<OILibraryEntity> & ProvidesDialog {
        let id = library.id
        let found = await MainActor.run { () -> Bool in
            let libraries = IntentSupport.libraries()
            // A library created on another device, or by another action, is on disk before this
            // list has seen it.
            if !libraries.containers.contains(where: { $0.id == id }) {
                libraries.reloadFromDisk()
            }
            guard libraries.containers.contains(where: { $0.id == id }) else { return false }
            libraries.setActive(id)
            return true
        }
        guard found else {
            throw OIIntentError("That library no longer exists.")
        }
        return .result(value: library, dialog: "\(library.name) is now the active library.")
    }
}
