//
//  AttachmentPicker.swift
//  OpenIntelligence
//
//  Unified attachment picker supporting documents, photos, and camera capture
//

import PhotosUI
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

// MARK: - Camera Capture

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

// MARK: - Attachment Preview Chip

struct AttachmentPreviewChip: View {
    let attachment: ChatAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            // Thumbnail or icon
            if let thumbnail = attachment.thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: attachment.type.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DSColors.accent)
                    .frame(width: 28, height: 28)
                    .background(DSColors.accent.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

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
            .json,
            // Spreadsheets
            .commaSeparatedText,
            // Audio (for transcription)
            .audio,
            .mp3,
            UTType(filenameExtension: "m4a") ?? .audio,
            .wav,
                // Video (for transcription)
                .movie,
            .mpeg4Movie,
            .quickTimeMovie,
        ])
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
                guard url.startAccessingSecurityScopedResource() else {
                    Log.error("[ExtendedDocumentPicker] Failed to access: \(url.lastPathComponent)", category: .ingestion)
                    continue
                }
                defer { url.stopAccessingSecurityScopedResource() }

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

        func documentPickerWasCancelled(_: UIDocumentPickerViewController) {
            // No action needed
        }
    }
}

// MARK: - Thumbnail Generator

@MainActor
func generateThumbnail(for url: URL) -> UIImage? {
    let ext = url.pathExtension.lowercased()

    // For images, load and resize
    if ["jpg", "jpeg", "png", "heic", "tiff", "gif"].contains(ext) {
        if let data = try? Data(contentsOf: url),
           let image = UIImage(data: data)
        {
            let size = CGSize(width: 60, height: 60)
            UIGraphicsBeginImageContextWithOptions(size, false, 0)
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
