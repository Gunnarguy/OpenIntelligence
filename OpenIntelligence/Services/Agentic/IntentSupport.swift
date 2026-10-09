//
//  IntentSupport.swift
//  OpenIntelligence
//

import AppIntents
import Foundation

/// An error an action shows to the person and hands to the shortcut as a failure.
///
/// The older actions return a successful result that carries an apology, so the next step of a
/// shortcut receives the apology as if it were the value. An action that throws this stops the
/// shortcut with the message instead.
@available(iOS 16.0, macOS 13.0, *)
struct OIIntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var localizedStringResource: LocalizedStringResource {
        "\(message)"
    }
}

/// What the actions share: the engine to use and where an imported file is stored.
@available(iOS 16.0, macOS 13.0, *)
enum IntentSupport {
    /// The engine the app's screens are using when the app is open, otherwise a new one.
    @MainActor
    static func engine() -> RAGService {
        RAGService.activePresentedInstance ?? RAGService()
    }

    /// The library list the app's screens are using when the app is open, otherwise one read from disk.
    @MainActor
    static func libraries() -> ContainerService {
        RAGService.activePresentedInstance?.containerService ?? ContainerService()
    }

    /// Stores bytes as a new file in the imported-documents folder and returns where it went. The
    /// import queue reads from there, the same place the document picker copies into.
    nonisolated static func store(_ data: Data, preferredFileName: String) throws -> URL {
        let destination = AppSupportPaths.nextAvailableImportedDocumentURL(preferredFileName: preferredFileName)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    /// Copies a file an action was handed into the imported-documents folder. The file an action
    /// receives can be removed when the action ends, so the queue must not be given its address.
    nonisolated static func copyIntoImports(_ source: URL, preferredFileName: String? = nil) throws -> URL {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let destination = AppSupportPaths.nextAvailableImportedDocumentURL(
            preferredFileName: preferredFileName ?? source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: destination)
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: destination.path)
        return destination
    }

    /// A file name for pasted text: its first words, or "Note" with the date.
    nonisolated static func noteFileName(for text: String, name: String?, now: Date = Date()) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        func cleaned(_ value: String) -> String {
            value.components(separatedBy: forbidden).joined(separator: " ")
                .split(separator: " ").joined(separator: " ")
        }
        if let name, !cleaned(name).isEmpty {
            // Saved text is text. A name like "Report.pdf" would send it down the PDF lane.
            let stem = cleaned(name)
            let textExtensions: Set<String> = ["txt", "md", "markdown", "csv", "json", "jsonl", "ndjson"]
            return textExtensions.contains((stem as NSString).pathExtension.lowercased()) ? stem : "\(stem).txt"
        }
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let words = cleaned(firstLine).split(separator: " ").prefix(8).joined(separator: " ")
        if words.count >= 3 {
            return "\(String(words.prefix(60))).txt"
        }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        return "Note \(day.string(from: now)).txt"
    }
}
