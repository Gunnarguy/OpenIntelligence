//
//  LibraryFocusFilterIntent.swift
//  OpenIntelligence
//

import AppIntents
import Foundation

/// A Focus filter (Settings, Focus, a Focus, Add Filter, OpenIntelligence): while that Focus is on,
/// the app lists only the chosen libraries and opens the first of them (5.7). A Work Focus can
/// keep a work library in front, a Personal one the rest.
///
/// The system runs `perform()` with the chosen libraries when the Focus turns on, and with the
/// parameter's empty value when it turns off. `ContainerService.applyFocusFilter` does the rest.
@available(iOS 26.0, macOS 26.0, *)
struct LibraryFocusFilterIntent: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Set Libraries"
    static var description: IntentDescription = .init(
        "Shows only the chosen libraries while this Focus is on, and opens the first of them.",
        categoryName: "Libraries",
        searchKeywords: ["focus", "filter", "library"]
    )

    @Parameter(title: "Libraries")
    var libraries: [OILibraryEntity]?

    var displayRepresentation: DisplayRepresentation {
        let names = (libraries ?? []).map(\.name)
        guard !names.isEmpty else { return DisplayRepresentation(title: "All libraries") }
        return DisplayRepresentation(
            title: "\(names.joined(separator: ", "))",
            subtitle: names.count == 1 ? "1 library" : "\(names.count) libraries")
    }

    func perform() async throws -> some IntentResult {
        let ids = libraries?.map(\.id)
        await MainActor.run {
            IntentSupport.libraries().applyFocusFilter(ids)
        }
        return .result()
    }

    /// The filter in force now, applied at launch in case a Focus changed while the app was not
    /// running and the system did not start it.
    @MainActor
    static func applyCurrent(to libraries: ContainerService) async {
        guard let current = try? await LibraryFocusFilterIntent.current else { return }
        libraries.applyFocusFilter(current.libraries?.map(\.id))
    }
}
