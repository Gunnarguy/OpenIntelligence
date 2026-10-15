//
//  OpenedFilesSheet.swift
//  OpenIntelligence
//

import QuickLook
import SwiftUI

/// Files another app handed over ("Open in OpenIntelligence" from Files, Mail or AirDrop, or a file
/// opened with the app on the Mac), shown before anything is added (5.7). Each file opens in Quick
/// Look, read-only, and nothing joins a library until Add to Library; Don't Add, or closing the
/// sheet, removes the app's copies. Through the first 5.7 builds a file handed over was imported at
/// once. The system's document browser (`DocumentGroup`) was not used: it would make a document
/// window part of the app's launch, for a file the person may not keep.
struct OpenedFilesSheet: View {
    let files: [URL]
    let libraryName: String
    let onAdd: () -> Void
    let onDiscard: () -> Void

    @State private var previewing: URL?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(files, id: \.self) { file in
                        Button {
                            previewing = file
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: Self.symbol(for: file))
                                    .font(.title3)
                                    .foregroundStyle(DSColors.accent)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.lastPathComponent)
                                        .foregroundStyle(DSColors.primaryText)
                                        .lineLimit(2)
                                    Text(Self.detail(of: file))
                                        .font(.caption)
                                        .foregroundStyle(DSColors.secondaryText)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "eye")
                                    .foregroundStyle(DSColors.secondaryText)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows the file without adding it")
                    }
                } footer: {
                    Text("Tap a file to look at it. Nothing is added until you add it.")
                }
            }
            .navigationTitle(files.count == 1 ? "Opened File" : "\(files.count) Opened Files")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Don't Add", role: .cancel, action: onDiscard)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add to \(libraryName)", action: onAdd)
                        .fontWeight(.semibold)
                }
            }
        }
        .quickLookPreview($previewing, in: files)
    }

    /// The file's kind and size, read from the copy: "PDF, 2.4 MB".
    nonisolated static func detail(of file: URL) -> String {
        let values = try? file.resourceValues(forKeys: [.localizedTypeDescriptionKey, .fileSizeKey])
        let kind = values?.localizedTypeDescription ?? file.pathExtension.uppercased()
        guard let size = values?.fileSize else { return kind }
        return "\(kind), \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))"
    }

    nonisolated static func symbol(for file: URL) -> String {
        switch file.pathExtension.lowercased() {
        case "pdf": return "doc.richtext"
        case "png", "jpg", "jpeg", "heic", "gif", "tiff": return "photo"
        case "mp3", "m4a", "wav", "caf", "aiff": return "waveform"
        case "mp4", "mov", "m4v": return "film"
        case "csv", "xlsx", "numbers": return "tablecells"
        case "json", "jsonl", "ndjson": return "curlybraces"
        default: return "doc.text"
        }
    }
}
