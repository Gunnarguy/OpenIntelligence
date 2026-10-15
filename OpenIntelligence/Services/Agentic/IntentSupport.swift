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
nonisolated struct OIIntentError: Error, CustomLocalizedStringResourceConvertible {
    /// What kind of failure it is, which the system reads from iOS and macOS 27
    /// (`CustomAppIntentErrorConvertible`). The message is what the person sees either way.
    nonisolated enum Kind: Sendable {
        /// Something went wrong; the message says what.
        case general
        /// A document, library or conversation the action was given no longer exists.
        case itemNotFound
        /// Some of the work was done and some was not, and the message lists both.
        case partial
    }

    let message: String
    let kind: Kind

    init(_ message: String, kind: Kind = .general) {
        self.message = message
        self.kind = kind
    }

    var localizedStringResource: LocalizedStringResource {
        "\(message)"
    }
}

/// From iOS and macOS 27 an action's failure also tells the system what kind it is (5.7): an item
/// that is gone is Apple's "entity not found", work done in part is "partial failure", anything
/// else is the message alone. Measured on macOS 27 on 2026-10-14: the text the system shows for
/// each is the message unchanged. Before 27 the system gets the message only. Apple's "feature
/// currently restricted" is not used for the free plan's limits: its own text names Screen Time and
/// device management.
@available(iOS 27.0, macOS 27.0, *)
extension OIIntentError: CustomAppIntentErrorConvertible {
    nonisolated var appIntentError: AppIntentError {
        let shown: LocalizedStringResource = "\(message)"
        switch kind {
        case .general:
            return AppIntentError(description: shown)
        case .itemNotFound:
            return AppIntentError(predefinedError: .Unrecoverable.entityNotFound, description: shown)
        case .partial:
            return AppIntentError(predefinedError: .Unrecoverable.partialFailure, description: shown)
        }
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
