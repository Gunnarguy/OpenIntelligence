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
/// window part of the app's launch, for a file the person may not keep. The library the files go to
/// is chosen here, with the same chips the Documents screen uses, and starts on the open library.
struct OpenedFilesSheet: View {
    let files: [URL]
    let libraries: [KnowledgeContainer]
    let documentCount: (UUID) -> Int
    let onAdd: (UUID?) -> Void
    let onDiscard: () -> Void

    @State private var previewing: URL?
    @State private var libraryId: UUID?

    init(
        files: [URL], libraries: [KnowledgeContainer], initialLibraryId: UUID?,
        documentCount: @escaping (UUID) -> Int, onAdd: @escaping (UUID?) -> Void, onDiscard: @escaping () -> Void
    ) {
        self.files = files
        self.libraries = libraries
        self.documentCount = documentCount
        self.onAdd = onAdd
        self.onDiscard = onDiscard
        _libraryId = State(initialValue: initialLibraryId)
    }

    private var libraryName: String {
        libraries.first { $0.id == libraryId }?.name ?? "Library"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(files, id: \.self) { file in
                        Button {
                            previewing = file
                        } label: {
                            HStack(spacing: DSSpacing.md) {
                                Image(systemName: Self.symbol(for: file))
                                    .font(.title3)
                                    .foregroundStyle(DSColors.accent)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                                    Text(file.lastPathComponent)
                                        .font(.subheadline)
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

                if libraries.count > 1 {
                    Section("Add to") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DSSpacing.sm) {
                                ForEach(libraries) { library in
                                    let count = documentCount(library.id)
                                    ContainerPill(
                                        container: library,
                                        isSelected: library.id == libraryId,
                                        canDelete: false,
                                        badgeText: count > 0 ? "\(count)" : nil,
                                        badgeStyle: .count,
                                        onSelect: { libraryId = library.id }
                                    )
                                }
                            }
                            .padding(.vertical, DSSpacing.xs)
                        }
                    }
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
                    Button("Add to \(libraryName)") { onAdd(libraryId) }
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
