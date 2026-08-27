//
//  DocumentPicker.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import SwiftUI
import UniformTypeIdentifiers

/// Copies user-selected files into the app-managed workspace.
///
/// Every import path funnels through here: the iOS document picker, the macOS
/// open panel, and Finder drag-and-drop. Importing by reference instead would
/// leave the library pointing at files outside the workspace, which neither
/// syncs across devices nor survives the original being moved.
enum ImportedFileStaging {
    /// Returns the workspace URLs of everything that copied successfully.
    ///
    /// A failure is logged per file and skipped rather than aborting the batch,
    /// because dropping nine readable files because the tenth was unreadable is
    /// the worse outcome.
    static func copyIntoWorkspace(_ urls: [URL]) -> [URL] {
        guard !urls.isEmpty else { return [] }

        let fileManager = FileManager.default
        var copiedURLs: [URL] = []

        for url in urls {
            // Finder drops and open-panel selections both hand back the original
            // location, unlike the iOS picker's `asCopy: true`, so a sandboxed
            // build needs security-scoped access before reading. The call is
            // harmless when the URL carries no scope.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let destinationURL = AppSupportPaths.nextAvailableImportedDocumentURL(
                preferredFileName: url.lastPathComponent
            )
            do {
                try fileManager.copyItem(at: url, to: destinationURL)
                // Refresh the modification date so the workspace sync sweep does
                // not treat a just-imported file as stale.
                try? fileManager.setAttributes(
                    [.modificationDate: Date()],
                    ofItemAtPath: destinationURL.path
                )
                copiedURLs.append(destinationURL)
                Log.debug("✓ Queued: \(url.lastPathComponent)", category: .ingestion)
            } catch {
                Log.error(
                    "❌ Error copying document \(url.lastPathComponent): \(error)",
                    category: .ingestion
                )
            }
        }

        return copiedURLs
    }
}


#if canImport(UIKit)
struct DocumentPicker: UIViewControllerRepresentable {
    let onDocumentsPicked: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [
            // Documents
            .pdf,
            .plainText,
            .text,
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText,
            .rtf,
            // Office & Productivity
            UTType(filenameExtension: "doc") ?? .data,
            UTType(filenameExtension: "docx") ?? .data,
            UTType(filenameExtension: "xls") ?? .data,
            UTType(filenameExtension: "xlsx") ?? .data,
            UTType(filenameExtension: "ppt") ?? .data,
            UTType(filenameExtension: "pptx") ?? .data,
            UTType(filenameExtension: "pages") ?? .data,
            UTType(filenameExtension: "numbers") ?? .data,
            UTType(filenameExtension: "key") ?? .data,
            .commaSeparatedText,
            // Images and scans
            .image,
            // Structured and web text
            UTType(filenameExtension: "xml") ?? .text,
            UTType(filenameExtension: "yaml") ?? .text,
            UTType(filenameExtension: "yml") ?? .text,
            UTType(filenameExtension: "css") ?? .sourceCode,
            UTType(filenameExtension: "scss") ?? .sourceCode,
            UTType(filenameExtension: "sass") ?? .sourceCode,
            UTType(filenameExtension: "sql") ?? .sourceCode,
            UTType(filenameExtension: "sh") ?? .sourceCode,
            UTType(filenameExtension: "zsh") ?? .sourceCode,
            // Code
            .sourceCode,
            UTType(filenameExtension: "swift") ?? .sourceCode,
            UTType(filenameExtension: "py") ?? .sourceCode,
            UTType(filenameExtension: "js") ?? .sourceCode,
            UTType(filenameExtension: "ts") ?? .sourceCode,
            UTType(filenameExtension: "json") ?? .json,
            UTType(filenameExtension: "html") ?? .html,
            .json,
            // Audio (for transcription)
            .audio,
            .mp3,
            UTType(filenameExtension: "m4a") ?? .audio,
            .wav,
            UTType(filenameExtension: "aiff") ?? .audio,
            UTType(filenameExtension: "caf") ?? .audio,
            // Video (for transcription)
            .movie,
            .mpeg4Movie,
            .quickTimeMovie,
        ], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = true  // Enable multiple file selection
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker

        init(_ parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            // Process ALL selected files
            Log.debug("📚 Processing \(urls.count) selected file(s)...", category: .ingestion)

            let copiedURLs = ImportedFileStaging.copyIntoWorkspace(urls)
            if !copiedURLs.isEmpty {
                parent.onDocumentsPicked(copiedURLs)
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}

#endif

#if !canImport(UIKit) && canImport(AppKit)
import AppKit

/// Native macOS document import.
///
/// This previously rendered "Document picker is unavailable on this platform."
/// Native macOS has no UIKit, so the whole `UIDocumentPickerViewController`
/// path compiled out and Mac users had no way to import anything through this
/// component. AppKit's `NSOpenPanel` is the direct equivalent.
///
/// The panel opens with `beginSheetModal(for:)`, never `runModal()`.
/// `runModal()` starts a nested modal loop, and AppKit refuses to start one
/// from inside a CATransaction commit, which is exactly where SwiftUI runs
/// `onAppear`. A macOS capture on 2026-08-27 recorded the result: three
/// `Suppressing invocation of -[NSApplication runModalForWindow:]` warnings,
/// an `_NSDetectedLayoutRecursion`, 2064 lines of window-chrome relayout, and
/// no panel on screen. `beginSheetModal(for:)` is asynchronous and carries no
/// such restriction.
enum MacDocumentImportPanel {
    /// Presents the open panel and hands back copies inside the workspace.
    ///
    /// `completion` receives an empty array when the user cancels, so callers
    /// can treat cancellation and "nothing usable was selected" identically.
    static func present(
        contentTypes: [UTType] = acceptedContentTypes,
        completion: @escaping ([URL]) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = contentTypes
        panel.message = "Select documents to add to this library"
        panel.prompt = "Import"

        let handle: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, !panel.urls.isEmpty else {
                completion([])
                return
            }
            Log.debug(
                "📚 Processing \(panel.urls.count) selected file(s)...",
                category: .ingestion
            )
            completion(ImportedFileStaging.copyIntoWorkspace(panel.urls))
        }

        // Attaching to the key window makes this a document-modal sheet, which
        // is the native idiom for an import triggered from that window. With no
        // window to attach to there is nothing to sheet onto, so fall back to a
        // free-floating panel rather than dropping the request.
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window) { response in
                MainActor.assumeIsolated { handle(response) }
            }
        } else {
            panel.begin { response in
                MainActor.assumeIsolated { handle(response) }
            }
        }
    }

    /// Kept in sync with the iOS picker's accepted types.
    static let acceptedContentTypes: [UTType] = {
        var types: [UTType] = [
            .pdf, .plainText, .text, .rtf, .commaSeparatedText,
            .image, .sourceCode, .json, .html,
            .audio, .mp3, .wav,
            .movie, .mpeg4Movie, .quickTimeMovie,
        ]
        let byExtension = [
            "md", "markdown",
            "doc", "docx", "xls", "xlsx", "ppt", "pptx",
            "pages", "numbers", "key",
            "xml", "yaml", "yml", "css", "scss", "sass", "sql", "sh", "zsh",
            "swift", "py", "js", "ts",
            "m4a", "aiff", "caf",
        ]
        types.append(contentsOf: byExtension.compactMap { UTType(filenameExtension: $0) })
        return types
    }()
}

/// SwiftUI wrapper kept so shared call sites and `#Preview` still compile on
/// macOS. The library's Add Documents button calls `MacDocumentImportPanel`
/// directly rather than presenting this inside a sheet, because hosting an open
/// panel in a SwiftUI sheet stacks two windows for a single action.
struct DocumentPicker: View {
    let onDocumentsPicked: ([URL]) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.badge.plus")
                .font(.largeTitle)
                .foregroundColor(.accentColor)
            Text("Choose documents to import")
                .font(.headline)
            Text("PDFs, Office files, text, code, images, audio, or video. Export Pages, Numbers "
                     + "and Keynote to PDF first.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Choose Files…") { present() }
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .onAppear { present() }
    }

    private func present() {
        MacDocumentImportPanel.present { urls in
            if !urls.isEmpty {
                onDocumentsPicked(urls)
            }
            dismiss()
        }
    }
}
#endif

#if !canImport(UIKit) && !canImport(AppKit)
struct DocumentPicker: View {
    let onDocumentsPicked: ([URL]) -> Void
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.badge.gearshape")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("Document picker is unavailable on this platform.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
#endif

#Preview {
    DocumentPicker(onDocumentsPicked: { _ in })
}
