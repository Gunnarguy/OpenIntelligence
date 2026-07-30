//
//  DocumentPicker.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import SwiftUI
import UniformTypeIdentifiers

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

            var copiedURLs: [URL] = []
            for url in urls {
                // The URL is already a copy in the app's temp directory because of `asCopy: true`.
                // Copy into the app-managed workspace so the same source file can sync across devices.
                let fileManager = FileManager.default
                let destinationURL = AppSupportPaths.nextAvailableImportedDocumentURL(preferredFileName: url.lastPathComponent)

                do {
                    try fileManager.copyItem(at: url, to: destinationURL)
                    try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: destinationURL.path)
                    copiedURLs.append(destinationURL)
                    Log.debug("✓ Queued: \(url.lastPathComponent)", category: .ingestion)
                } catch {
                    Log.error("❌ Error copying document \(url.lastPathComponent): \(error)", category: .ingestion)
                }
            }
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
/// — native macOS has no UIKit, so the whole `UIDocumentPickerViewController`
/// path compiled out and Mac users had no way to import anything through this
/// component. AppKit's `NSOpenPanel` is the direct equivalent.
///
/// Behavior deliberately matches the iOS path: the same accepted types,
/// multiple selection, and a copy into the app-managed workspace via
/// `AppSupportPaths.nextAvailableImportedDocumentURL` so imported files sync
/// across devices rather than being referenced in place.
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
            Text("PDFs, Office and iWork files, text, code, images, audio, or video.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Choose Files…") { presentPanel() }
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .onAppear { presentPanel() }
    }

    private func presentPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = DocumentPicker.acceptedContentTypes
        panel.message = "Select documents to add to this library"
        panel.prompt = "Import"

        guard panel.runModal() == .OK, !panel.urls.isEmpty else {
            dismiss()
            return
        }

        Log.debug("📚 Processing \(panel.urls.count) selected file(s)...", category: .ingestion)

        var copiedURLs: [URL] = []
        let fileManager = FileManager.default

        for url in panel.urls {
            // NSOpenPanel hands back the original location (unlike iOS's
            // asCopy:true), so security-scoped access is required before reading
            // it in a sandboxed build.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let destinationURL = AppSupportPaths.nextAvailableImportedDocumentURL(
                preferredFileName: url.lastPathComponent
            )
            do {
                try fileManager.copyItem(at: url, to: destinationURL)
                // Match iOS: refresh the modification date so the workspace
                // sync sweep does not treat a just-imported file as stale.
                try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: destinationURL.path)
                copiedURLs.append(destinationURL)
                Log.debug("✓ Queued: \(url.lastPathComponent)", category: .ingestion)
            } catch {
                Log.error("❌ Error copying document \(url.lastPathComponent): \(error)", category: .ingestion)
            }
        }

        if !copiedURLs.isEmpty {
            onDocumentsPicked(copiedURLs)
        }
        dismiss()
    }

    /// Kept in sync with the iOS picker's accepted types.
    private static let acceptedContentTypes: [UTType] = {
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
