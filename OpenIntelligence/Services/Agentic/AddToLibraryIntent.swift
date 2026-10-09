//
//  AddToLibraryIntent.swift
//  OpenIntelligence
//

import AppIntents
import Foundation

/// One action that adds a file, a web page or plain text to a library.
///
/// Before this, a file had its own action, a link had one that downloaded nothing, and text had
/// none. Whatever is given is stored in the imported-documents folder first and then queued, the
/// way the document picker does it, and the action returns the names of the files it queued. When
/// one of several things cannot be stored, the rest are still queued and the action fails with a
/// message naming both. The import itself runs after the action returns, so a plan's document
/// limit or an unreadable file is reported in the app, not to the shortcut.
@available(iOS 26.0, macOS 26.0, *)
struct AddToLibraryIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to Library"
    static var description: IntentDescription = .init(
        "Adds a file, a web page or text to a library in OpenIntelligence.",
        categoryName: "Ingestion",
        searchKeywords: ["add", "import", "save", "ingest", "file", "link", "text", "note"]
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "File")
    var file: IntentFile?

    @Parameter(title: "Link", description: "A web address to download and save")
    var link: URL?

    @Parameter(title: "Text", description: "Text to save as a note")
    var text: String?

    @Parameter(title: "Name", description: "A name for the saved text")
    var name: String?

    @Parameter(title: "Library", description: "Leave empty to use the active library")
    var library: OILibraryEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$file) to \(\.$library)") {
            \.$link
            \.$text
            \.$name
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog {
        let note = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard file != nil || link != nil || !note.isEmpty else {
            throw $file.needsValueError("What should I add? Give a file, a link or some text.")
        }

        var stored: [URL] = []
        var failures: [String] = []

        if let file {
            do {
                if let source = file.fileURL {
                    stored.append(try IntentSupport.copyIntoImports(source, preferredFileName: file.filename))
                } else {
                    stored.append(try IntentSupport.store(file.data, preferredFileName: file.filename))
                }
            } catch {
                failures.append("\(file.filename): \(error.localizedDescription)")
            }
        }

        if let link {
            do {
                let fetched = try await WebPageFetchService.fetch(link)
                stored.append(try IntentSupport.store(fetched.data, preferredFileName: fetched.fileName))
            } catch {
                failures.append("\(link.host ?? link.absoluteString): \(error.localizedDescription)")
            }
        }

        if !note.isEmpty {
            do {
                let fileName = IntentSupport.noteFileName(for: note, name: name)
                stored.append(try IntentSupport.store(Data(note.utf8), preferredFileName: fileName))
            } catch {
                failures.append("Text: \(error.localizedDescription)")
            }
        }

        if !failures.isEmpty {
            Log.warning(
                "[Shortcuts] Add to Library: \(failures.count) item(s) could not be stored, \(stored.count) stored",
                category: .ingestion)
        }
        guard !stored.isEmpty else {
            throw OIIntentError("Nothing was added. \(failures.joined(separator: " "))")
        }

        let containerId = library?.id
        let queued = stored
        await MainActor.run {
            _ = IntentSupport.engine().enqueueDocuments(queued, containerId: containerId)
        }

        let names = stored.map(\.lastPathComponent)
        let target = library?.name ?? "your active library"
        Log.info(
            "[Shortcuts] Add to Library queued \(names.count) item(s), \(failures.count) failed", category: .ingestion)

        // What could be stored is queued either way. When something could not be, the action fails
        // with both lists, so a shortcut does not run on as if everything went in.
        guard failures.isEmpty else {
            throw OIIntentError(
                "Added \(names.joined(separator: ", ")) to \(target). Not added: \(failures.joined(separator: " "))")
        }
        let message =
            "Added \(names.count) item\(names.count == 1 ? "" : "s") to \(target). Importing continues in OpenIntelligence."
        return .result(value: names, dialog: IntentDialog(stringLiteral: message))
    }
}
