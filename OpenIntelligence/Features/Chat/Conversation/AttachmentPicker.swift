//
//  AttachmentPicker.swift
//  OpenIntelligence
//
//  Unified attachment picker supporting documents, photos, and camera capture
//

#if os(iOS)
import PhotosUI
import UIKit
#else
import AppKit
typealias UIImage = NSImage
#endif

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Attachment Result

/// Represents an attachment ready for ingestion
struct ChatAttachment: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let type: AttachmentType
    let thumbnail: UIImage?

    enum AttachmentType: String, Sendable {
        case document
        case photo
        case camera

        var icon: String {
            switch self {
            case .document: return "doc.fill"
            case .photo: return "photo.fill"
            case .camera: return "camera.fill"
            }
        }
    }
}

// MARK: - Photo Picker

#if os(iOS)
struct PhotoPicker: UIViewControllerRepresentable {
    let onImagesPicked: ([URL]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 10 // Allow multiple images
        config.filter = .images
        config.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: PHPickerViewController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker

        init(_ parent: PhotoPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard !results.isEmpty else { return }

            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let attachmentsDir = documentsPath.appendingPathComponent("ChatAttachments", isDirectory: true)
            try? FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)

            var savedURLs: [URL] = []
            let group = DispatchGroup()

            for result in results {
                group.enter()

                let itemProvider = result.itemProvider

                // Try to get the image data
                if itemProvider.canLoadObject(ofClass: UIImage.self) {
                    itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                        defer { group.leave() }

                        guard let image = object as? UIImage else {
                            Log.error("[PhotoPicker] Failed to load image: \(error?.localizedDescription ?? "unknown")", category: .ingestion)
                            return
                        }

                        // Save as JPEG for consistent processing
                        let filename = "photo_\(UUID().uuidString).jpg"
                        let fileURL = attachmentsDir.appendingPathComponent(filename)

                        if let data = image.jpegData(compressionQuality: 0.9) {
                            do {
                                try data.write(to: fileURL)
                                savedURLs.append(fileURL)
                                Log.debug("[PhotoPicker] Saved image: \(filename)", category: .ingestion)
                            } catch {
                                Log.error("[PhotoPicker] Failed to save image: \(error)", category: .ingestion)
                            }
                        }
                    }
                } else {
                    group.leave()
                }
            }

            group.notify(queue: .main) { [weak self] in
                self?.parent.onImagesPicked(savedURLs)
            }
        }
    }
}
#else
/// Runs an `NSOpenPanel` without starting a nested modal loop.
///
/// SwiftUI fires `onAppear` inside a CATransaction commit, and AppKit refuses
/// to start a modal loop there: it logs `Suppressing invocation of
/// -[NSApplication runModalForWindow:]` and the panel never appears. A macOS
/// capture on 2026-08-27 recorded exactly that for both pickers in this file,
/// and because each one renders `Color.clear`, the user was left looking at an
/// empty sheet with no way forward. `beginSheetModal(for:)` is asynchronous and
/// is safe to call from anywhere.
enum MacAttachmentPanel {
    /// Calls `completion` with the chosen URLs, or an empty array on cancel.
    static func present(
        contentTypes: [UTType],
        completion: @escaping ([URL]) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = contentTypes

        let handle: (NSApplication.ModalResponse) -> Void = { response in
            completion(response == .OK ? panel.urls : [])
        }

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
}

struct PhotoPicker: View {
    let onImagesPicked: ([URL]) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Color.clear
            .onAppear {
                MacAttachmentPanel.present(contentTypes: [.image]) { urls in
                    if !urls.isEmpty {
                        onImagesPicked(urls)
                    }
                    dismiss()
                }
            }
    }
}
#endif

// MARK: - Camera Capture

#if os(iOS)
struct CameraPicker: UIViewControllerRepresentable {
    let onImageCaptured: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)

            guard let image = info[.originalImage] as? UIImage else {
                parent.onImageCaptured(nil)
                return
            }

            // Save captured image
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let attachmentsDir = documentsPath.appendingPathComponent("ChatAttachments", isDirectory: true)
            try? FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)

            let filename = "capture_\(UUID().uuidString).jpg"
            let fileURL = attachmentsDir.appendingPathComponent(filename)

            if let data = image.jpegData(compressionQuality: 0.9) {
                do {
                    try data.write(to: fileURL)
                    Log.debug("[CameraPicker] Captured and saved: \(filename)", category: .ingestion)
                    parent.onImageCaptured(fileURL)
                } catch {
                    Log.error("[CameraPicker] Failed to save capture: \(error)", category: .ingestion)
                    parent.onImageCaptured(nil)
                }
            } else {
                parent.onImageCaptured(nil)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            parent.onImageCaptured(nil)
        }
    }
}
#else
struct CameraPicker: View {
    let onImageCaptured: (URL?) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Color.clear
            .onAppear {
                onImageCaptured(nil)
                dismiss()
            }
    }
}
#endif

// MARK: - Attachment Preview Chip

struct AttachmentPreviewChip: View {
    let attachment: ChatAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            // Thumbnail or icon
            #if os(iOS)
            if let thumbnail = attachment.thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: attachment.type.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DSColors.accent)
                    .frame(width: 28, height: 28)
                    .background(DSColors.accent.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            #else
            if let thumbnail = attachment.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: attachment.type.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DSColors.accent)
                    .frame(width: 28, height: 28)
                    .background(DSColors.accent.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            #endif

            // Filename
            Text(attachment.url.lastPathComponent)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}

// MARK: - Attachment Menu

struct AttachmentMenuButton: View {
    let onSelectDocument: () -> Void
    let onSelectPhoto: () -> Void
    let onTakePhoto: () -> Void
    var onVisionCapture: (() -> Void)? = nil  // Enhanced Vision capture (optional)
    let isCameraAvailable: Bool

    var body: some View {
        Menu {
            Button(action: onSelectDocument) {
                Label("Choose File", systemImage: "doc.fill")
            }

            Button(action: onSelectPhoto) {
                Label("Photo Library", systemImage: "photo.on.rectangle.angled")
            }

            if isCameraAvailable {
                Button(action: onTakePhoto) {
                    Label("Take Photo", systemImage: "camera.fill")
                }

                // Vision Capture - Advanced camera with live OCR and document detection
                if let onVisionCapture = onVisionCapture {
                    Divider()

                    Button(action: onVisionCapture) {
                        Label("Scan Document", systemImage: "doc.viewfinder")
                    }
                }
            }
        } label: {
            Image(systemName: "paperclip")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(DSColors.accent)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Extended Document Picker (includes images)

#if os(iOS)
struct ExtendedDocumentPicker: UIViewControllerRepresentable {
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
            // Images
            .image,
            .jpeg,
            .png,
            .heic,
            .tiff,
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
            // Video (for transcription)
            .movie,
            .mpeg4Movie,
            .quickTimeMovie,
        ], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = true
        return picker
    }

    func updateUIViewController(_: UIDocumentPickerViewController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: ExtendedDocumentPicker

        init(_ parent: ExtendedDocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {

            let fileManager = FileManager.default
            let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let attachmentsDir = documentsPath.appendingPathComponent("ChatAttachments", isDirectory: true)
            try? fileManager.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)

            var copiedURLs: [URL] = []

            for url in urls {
                // The URL is already a copy in the app's temp directory because of `asCopy: true`.

                // Use unique filename to avoid conflicts
                let uniqueName = "\(UUID().uuidString)_\(url.lastPathComponent)"
                let destinationURL = attachmentsDir.appendingPathComponent(uniqueName)

                do {
                    if fileManager.fileExists(atPath: destinationURL.path) {
                        try fileManager.removeItem(at: destinationURL)
                    }
                    try fileManager.copyItem(at: url, to: destinationURL)
                    copiedURLs.append(destinationURL)
                    Log.debug("[ExtendedDocumentPicker] Copied: \(url.lastPathComponent)", category: .ingestion)
                } catch {
                    Log.error("[ExtendedDocumentPicker] Copy failed: \(error)", category: .ingestion)
                }
            }

            parent.onDocumentsPicked(copiedURLs)
        }

        func documentPickerWasCancelled(_: UIDocumentPickerViewController) {}
    }
}
#else
struct ExtendedDocumentPicker: View {
    let onDocumentsPicked: ([URL]) -> Void
    @Environment(\.dismiss) var dismiss

    /// Kept in sync with the iOS `ExtendedDocumentPicker` accepted types.
    private static let acceptedContentTypes: [UTType] = {
        var types: [UTType] = [
            .pdf, .plainText, .text, .rtf, .commaSeparatedText,
            .image, .jpeg, .png, .heic, .tiff,
            .json, .html,
            .audio, .mp3, .wav,
            .movie, .mpeg4Movie, .quickTimeMovie,
        ]
        let byExtension = [
            "md",
            "doc", "docx", "xls", "xlsx", "ppt", "pptx",
            "pages", "numbers", "key",
            "swift", "py", "js", "ts",
            "m4a",
        ]
        types.append(contentsOf: byExtension.compactMap { UTType(filenameExtension: $0) })
        return types
    }()

    var body: some View {
        Color.clear
            .onAppear {
                MacAttachmentPanel.present(contentTypes: Self.acceptedContentTypes) { urls in
                    if !urls.isEmpty {
                        onDocumentsPicked(Self.copyIntoAttachments(urls))
                    }
                    dismiss()
                }
            }
    }

    /// Chat attachments live beside the conversation rather than in the document
    /// workspace, so this keeps its own destination instead of reusing
    /// `ImportedFileStaging`.
    private static func copyIntoAttachments(_ urls: [URL]) -> [URL] {
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let attachmentsDir = documentsPath.appendingPathComponent("ChatAttachments", isDirectory: true)
        try? fileManager.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)

        var copiedURLs: [URL] = []
        for url in urls {
            // The panel hands back the original location, so a sandboxed build
            // needs security-scoped access before reading it.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            // Use unique filename to avoid conflicts
            let uniqueName = "\(UUID().uuidString)_\(url.lastPathComponent)"
            let destinationURL = attachmentsDir.appendingPathComponent(uniqueName)
            do {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: url, to: destinationURL)
                copiedURLs.append(destinationURL)
                Log.debug("[ExtendedDocumentPicker] Copied: \(url.lastPathComponent)", category: .ingestion)
            } catch {
                Log.error("[ExtendedDocumentPicker] Copy failed: \(error)", category: .ingestion)
            }
        }
        return copiedURLs
    }
}
#endif

// MARK: - Thumbnail Generator

#if os(macOS)
@MainActor
func generateThumbnail(for url: URL) -> NSImage? {
    let ext = url.pathExtension.lowercased()

    // For images, load and resize
    if ["jpg", "jpeg", "png", "heic", "tiff", "gif"].contains(ext) {
        if let data = try? Data(contentsOf: url),
           let image = NSImage(data: data)
        {
            let size = NSSize(width: 60, height: 60)
            let destImage = NSImage(size: size)
            destImage.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            NSColor.white.setFill()
            NSRect(origin: .zero, size: size).fill()
            image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1.0)
            destImage.unlockFocus()
            return destImage
        }
    }
    return nil
}
#else
@MainActor
func generateThumbnail(for url: URL) -> UIImage? {
    let ext = url.pathExtension.lowercased()

    // For images, load and resize
    if ["jpg", "jpeg", "png", "heic", "tiff", "gif"].contains(ext) {
        if let data = try? Data(contentsOf: url),
           let image = UIImage(data: data)
        {
            let size = CGSize(width: 60, height: 60)
            // Use opaque context - thumbnails have white background
            UIGraphicsBeginImageContextWithOptions(size, true, 0)
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
            let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return thumbnail
        }
    }

    // For PDFs, render first page
    if ext == "pdf" {
        // Return nil; we'll use an icon instead
        return nil
    }

    return nil
}
#endif

#Preview {
    AttachmentMenuButton(
        onSelectDocument: {},
        onSelectPhoto: {},
        onTakePhoto: {},
        isCameraAvailable: true
    )
}
