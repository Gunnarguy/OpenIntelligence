//
//  DeleteIntents.swift
//  OpenIntelligence
//

import AppIntents
import Foundation

/// Deletes documents from a shortcut or from Siri, after asking (5.7). Through 5.6 a document could
/// be deleted only in the app.
///
/// The app's own engine does the deleting when the app is open, and one made for the action does
/// it otherwise (`IntentSupport.engine`). `RAGService.removeDocument` works from the engine's own
/// record of a document (its library, its file, its passage count), and an engine made for the
/// action reads its list from disk a moment after it is made, so nothing is deleted until that list
/// holds every document asked for, and a document no longer there stops the action before anything
/// is deleted. A save leaves out a document recorded as deleted, so another engine that read the
/// list earlier does not write it back (`RAGService.saveDocumentsToDisk`).
@available(iOS 26.0, macOS 26.0, *)
struct DeleteDocumentsIntent: DeleteIntent {
    static var title: LocalizedStringResource = "Delete Documents"
    static var description: IntentDescription = .init(
        "Deletes documents from your libraries, with their passages and their Spotlight entries, after asking.",
        categoryName: "Documents",
        searchKeywords: ["delete", "remove", "document"]
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Documents")
    var entities: [OIDocumentEntity]

    static var parameterSummary: some ParameterSummary {
        Summary("Delete \(\.$entities)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard !entities.isEmpty else {
            throw $entities.needsValueError("Which documents should be deleted?")
        }
        try await requestConfirmation(
            actionName: .continue,
            dialog: IntentDialog(stringLiteral: DocumentDeletion.question(for: entities.map(\.filename))))

        let wanted = Set(entities.map(\.id))
        let engine = await MainActor.run { IntentSupport.engine() }
        let documents = try await DocumentDeletion.documents(wanted, in: engine)
        for document in documents {
            do {
                try await engine.removeDocument(document)
            } catch {
                Log.error("[Shortcuts] Delete failed: \(error.localizedDescription)", category: .pipeline)
                throw OIIntentError("\(document.filename) could not be deleted. \(error.localizedDescription)")
            }
        }
        Log.info("[Shortcuts] Deleted \(documents.count) document(s)", category: .pipeline)
        return .result(dialog: IntentDialog(stringLiteral: DocumentDeletion.done(count: documents.count)))
    }
}

@available(iOS 26.0, macOS 26.0, *)
enum DocumentDeletion {
    /// The engine's records for these documents, once its list holds every one of them: at most
    /// `attempts` tries a tenth of a second apart, for an engine made for the action whose list is
    /// still being read. A document missing after that is no longer in the libraries.
    @MainActor
    static func documents(_ wanted: Set<UUID>, in engine: RAGService, attempts: Int = 30) async throws -> [Document] {
        for attempt in 0..<max(attempts, 1) {
            let found = engine.documents.filter { wanted.contains($0.id) }
            if Set(found.map(\.id)) == wanted { return found }
            if attempt < attempts - 1 { try await Task.sleep(for: .milliseconds(100)) }
        }
        throw OIIntentError(
            wanted.count == 1
                ? "That document is no longer in your libraries."
                : "One of those documents is no longer in your libraries. Nothing was deleted.",
            kind: .itemNotFound)
    }

    /// The confirmation: the names, up to three, and what goes with them.
    nonisolated static func question(for names: [String]) -> String {
        switch names.count {
        case 0:
            return "Delete nothing?"
        case 1:
            return "Delete “\(names[0])”? Its passages and its Spotlight entries go with it."
        default:
            let shown = names.prefix(3).map { "“\($0)”" }
            let rest = names.count - shown.count
            let list =
                rest > 0
                ? shown.joined(separator: ", ") + " and \(rest) more"
                : shown.dropLast().joined(separator: ", ") + " and " + shown.last!
            return "Delete \(names.count) documents, \(list)? Their passages and Spotlight entries go with them."
        }
    }

    nonisolated static func done(count: Int) -> String {
        count == 1 ? "Deleted the document." : "Deleted \(count) documents."
    }
}
