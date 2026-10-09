//
//  OpenItemIntents.swift
//  OpenIntelligence
//

import AppIntents
import Foundation

/// Opens the app on a library's documents.
///
/// An item with an open action is one Siri and Spotlight can open by name ("Open Home in
/// OpenIntelligence"). Through 5.6 the app had none, so a library or a document found from outside
/// the app could be listed and not opened.
@available(iOS 26.0, macOS 26.0, *)
struct OpenLibraryIntent: OpenIntent {
    static var title: LocalizedStringResource = "Open Library"
    static var description: IntentDescription = .init(
        "Opens OpenIntelligence on a library's documents and makes it the active library.",
        categoryName: "Libraries",
        searchKeywords: ["open", "show", "library"]
    )

    static var openAppWhenRun: Bool = true

    @Parameter(title: "Library")
    var target: OILibraryEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$target)")
    }

    func perform() async throws -> some IntentResult {
        let id = target.id
        await MainActor.run { AppNavigationRequest.post(.library(id)) }
        return .result()
    }
}

/// Opens the app on the library that holds a document.
///
/// The Documents screen has no single-document view to land on, so this goes to the document's
/// library; it does not scroll to the document.
@available(iOS 26.0, macOS 26.0, *)
struct OpenDocumentIntent: OpenIntent {
    static var title: LocalizedStringResource = "Open Document"
    static var description: IntentDescription = .init(
        "Opens OpenIntelligence on the library that holds a document.",
        categoryName: "Documents",
        searchKeywords: ["open", "show", "document"]
    )

    static var openAppWhenRun: Bool = true

    @Parameter(title: "Document")
    var target: OIDocumentEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$target)")
    }

    func perform() async throws -> some IntentResult {
        let id = target.id
        await MainActor.run { AppNavigationRequest.post(.document(id)) }
        return .result()
    }
}
