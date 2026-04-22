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
            // Code
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
        ])
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
                // Start accessing a security-scoped resource
                guard url.startAccessingSecurityScopedResource() else {
                    Log.warning("❌ Failed to access security-scoped resource: \(url.lastPathComponent)", category: .ingestion)
                    continue
                }

                defer { url.stopAccessingSecurityScopedResource() }

                // Copy to app's document directory
                let fileManager = FileManager.default
                let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let destinationURL = documentsPath.appendingPathComponent(url.lastPathComponent)

                do {
                    if fileManager.fileExists(atPath: destinationURL.path) {
                        try fileManager.removeItem(at: destinationURL)
                    }
                    try fileManager.copyItem(at: url, to: destinationURL)
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
    }
}

#endif

#if !canImport(UIKit)
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
