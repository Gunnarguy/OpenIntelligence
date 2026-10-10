//
//  PastedContentStaging.swift
//  OpenIntelligence
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// Works out what was pasted into a library and stores it where the import queue reads.
///
/// Through 5.6 a document came in through the picker, a drop, or another app. From 5.7 the Documents
/// screen has a Paste control: a copied file is copied in, a web address is downloaded the way "Save
/// a Web Page" does it, and text is saved as a note. Everything ends as a file in the
/// imported-documents folder, so it takes the same plan check and import review as a picked file.
nonisolated enum PastedContentStaging {
    enum Item: Equatable, Sendable {
        /// A file on disk, still where the other app left it.
        case file(URL)
        /// A web address to download.
        case link(URL)
        /// Text to keep as a note.
        case text(String)
    }

    struct Outcome: Sendable {
        /// Files now in the imported-documents folder.
        var staged: [URL] = []
        /// One line per item that could not be stored.
        var failures: [String] = []
    }

    /// Data types that are stored as the file they are, with the extension to give each. A copied
    /// PDF or picture arrives as its data, not as a file address.
    private static let dataTypes: [(type: UTType, fallbackExtension: String)] = [(.pdf, "pdf"), (.image, "png")]

    // MARK: - Reading what was pasted

    static func item(for url: URL) -> Item? {
        if url.isFileURL { return .file(url) }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = url.host, !host.isEmpty
        else { return nil }
        return .link(url)
    }

    /// A string that is one web address and nothing else is a link. Anything else with content is
    /// text, a sentence that mentions an address included.
    static func item(for string: String) -> Item? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains(where: \.isWhitespace), let url = URL(string: trimmed),
            case .link(let link)? = item(for: url)
        {
            return .link(link)
        }
        return .text(trimmed)
    }

    /// A browser puts a copied link on the pasteboard as an address and as its text. One is kept.
    static func deduplicated(_ items: [Item]) -> [Item] {
        var seen: [Item] = []
        for item in items where !seen.contains(item) {
            seen.append(item)
        }
        return seen
    }

    // MARK: - Storing

    static func storeText(_ text: String, now: Date = Date()) throws -> URL {
        let fileName = IntentSupport.noteFileName(for: text, name: nil, now: now)
        return try IntentSupport.store(Data(text.utf8), preferredFileName: fileName)
    }

    /// Stores everything the providers carry. A failure on one item is reported and the rest go on.
    /// On the concurrent pool: it copies files, and a large one copied on the main actor would hold
    /// the screen for as long as the copy takes.
    @concurrent
    static func stage(_ providers: [NSItemProvider]) async -> Outcome {
        var outcome = Outcome()
        var items: [Item] = []

        for provider in providers {
            // A copied PDF or picture: its data, written straight into the imports folder.
            if let stored = await storeDataFile(from: provider) {
                switch stored {
                case .success(let url): outcome.staged.append(url)
                case .failure(let error): outcome.failures.append(error.localizedDescription)
                }
                continue
            }
            if provider.canLoadObject(ofClass: URL.self), let url = await loadURL(from: provider),
                let item = item(for: url)
            {
                items.append(item)
            } else if provider.canLoadObject(ofClass: String.self), let text = await loadString(from: provider),
                let item = item(for: text)
            {
                items.append(item)
            }
        }

        for item in deduplicated(items) {
            do {
                switch item {
                case .file(let url):
                    outcome.staged.append(try IntentSupport.copyIntoImports(url))
                case .link(let url):
                    let fetched = try await WebPageFetchService.fetch(url)
                    outcome.staged.append(try IntentSupport.store(fetched.data, preferredFileName: fetched.fileName))
                case .text(let text):
                    outcome.staged.append(try storeText(text))
                }
            } catch {
                outcome.failures.append("\(label(for: item)): \(error.localizedDescription)")
            }
        }
        return outcome
    }

    /// The stored name of a pasted PDF or picture. The extension is added unless the suggested name
    /// already ends in it: "Screenshot 2026-10-09 at 10.31.22" has no extension, whatever
    /// `pathExtension` makes of its last dot.
    static func fileName(stem: String, extension ext: String) -> String {
        stem.lowercased().hasSuffix(".\(ext.lowercased())") ? stem : "\(stem).\(ext)"
    }

    static func label(for item: Item) -> String {
        switch item {
        case .file(let url): return url.lastPathComponent
        case .link(let url): return url.host ?? url.absoluteString
        case .text: return "Text"
        }
    }

    // MARK: - The clipboard

    /// What is on the clipboard now, as the providers `stage` reads. On iOS reading it is what
    /// makes the system ask "Allow Paste" for content copied in another app.
    @MainActor
    static func clipboardProviders() -> [NSItemProvider] {
        #if canImport(UIKit)
            return UIPasteboard.general.itemProviders
        #elseif canImport(AppKit)
            let pasteboard = NSPasteboard.general
            let fileURLs =
                pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
                ?? []
            if !fileURLs.isEmpty {
                // As the address, so `stage` copies the file itself and keeps its name and type.
                return fileURLs.map { NSItemProvider(object: $0 as NSURL) }
            }
            // Text before picture data: a Mac app that copies text often adds a picture of it.
            if let text = pasteboard.string(forType: .string), !text.isEmpty {
                return [NSItemProvider(object: text as NSString)]
            }
            let dataTypes: [(NSPasteboard.PasteboardType, UTType)] = [(.pdf, .pdf), (.png, .png), (.tiff, .tiff)]
            for (pasteboardType, type) in dataTypes {
                if let data = pasteboard.data(forType: pasteboardType) {
                    return [NSItemProvider(item: data as NSData, typeIdentifier: type.identifier)]
                }
            }
            return []
        #else
            return []
        #endif
    }

    // MARK: - Providers

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
        }
    }

    private static func loadString(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { text, _ in continuation.resume(returning: text) }
        }
    }

    /// nil when the provider carries no PDF or picture data. The file the system hands over exists
    /// only inside the callback, so it is copied there.
    private static func storeDataFile(from provider: NSItemProvider) async -> Result<URL, Error>? {
        // A file address wins: it keeps the file's own name and type.
        guard !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return nil }
        guard let match = dataTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0.type.identifier) })
        else { return nil }

        let stem = provider.suggestedName ?? "Pasted"
        return await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: match.type.identifier) { url, error in
                guard let url else {
                    continuation.resume(returning: .failure(error ?? CocoaError(.fileReadUnknown)))
                    return
                }
                let ext = url.pathExtension.isEmpty ? match.fallbackExtension : url.pathExtension
                let name = Self.fileName(stem: stem, extension: ext)
                continuation.resume(returning: Result { try IntentSupport.copyIntoImports(url, preferredFileName: name) })
            }
        }
    }
}

/// The Paste control on the Documents screen. It owns the wait and the failure message, and hands
/// the stored files to the screen, which runs the plan check and the import review on them.
///
/// The screen passes in the label, which is its own action chip, so this control looks like the
/// ones beside it. The first build of 5.7 used the system's `PasteButton` here, which draws itself
/// and cannot take the chip's look. What that gave up: the system button reads the clipboard
/// without asking, and a button of the app's own makes iOS ask "Allow Paste" when the copied
/// content came from another app (unless the person has set Paste from Other Apps to Allow).
struct LibraryPasteButton<ChipLabel: View>: View {
    let onStaged: ([URL]) -> Void
    @ViewBuilder let label: (_ isWorking: Bool) -> ChipLabel

    @State private var isWorking = false
    @State private var message: PasteMessage?
    /// Files stored by a paste that also had failures. They are handed over when the alert is
    /// closed, because the screen answers them with a sheet and only one can be up at a time.
    @State private var stagedBehindMessage: [URL] = []

    private struct PasteMessage {
        let title: String
        let detail: String
    }

    var body: some View {
        Button {
            paste()
        } label: {
            label(isWorking)
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .accessibilityLabel("Paste into Library")
        .help("Paste a file, a web address or text into this library")
        .alert(
            message?.title ?? "",
            isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
        ) {
            Button("OK", role: .cancel) {
                let staged = stagedBehindMessage
                stagedBehindMessage = []
                guard !staged.isEmpty else { return }
                DispatchQueue.main.async { onStaged(staged) }
            }
        } message: {
            Text(message?.detail ?? "")
        }
    }

    private func paste() {
        let providers = PastedContentStaging.clipboardProviders()
        guard !providers.isEmpty else {
            message = PasteMessage(
                title: "Nothing to Paste",
                detail: "Copy a file, a web address or some text first, then tap Paste.")
            return
        }
        isWorking = true
        Task { @MainActor in
            let outcome = await PastedContentStaging.stage(providers)
            isWorking = false
            if !outcome.failures.isEmpty {
                stagedBehindMessage = outcome.staged
                message = PasteMessage(
                    title: outcome.staged.isEmpty
                        ? "What You Pasted Was Not Added" : "Some of What You Pasted Was Not Added",
                    detail: outcome.failures.joined(separator: "\n"))
            } else if outcome.staged.isEmpty {
                message = PasteMessage(title: "Nothing to Paste", detail: Self.nothingUsableDetail)
            } else {
                onStaged(outcome.staged)
            }
        }
    }

    /// Shown when the clipboard had something and none of it could be read. On iPhone and iPad
    /// that is also what a declined "Allow Paste" looks like from here.
    private static var nothingUsableDetail: String {
        let base = "The clipboard holds nothing OpenIntelligence can add. Copy a file, a web address or some text."
        #if canImport(UIKit)
            return base + " If iOS asked whether to allow the paste, choose Allow Paste."
        #else
            return base
        #endif
    }
}
