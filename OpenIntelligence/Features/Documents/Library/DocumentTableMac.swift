//
//  DocumentTableMac.swift
//  OpenIntelligence
//
//  The Mac's document list (5.8 Mac redesign): a table of the open library's documents with sortable columns, several
//  rows selected at once, Delete to remove them and the selected document's details in the window's inspector
//  (`DocumentLibraryView`). It replaces the iPhone's tall cards, each a link to a pushed page, which on a Mac showed
//  three documents to a screen. The iPhone and iPad keep the cards.
//

#if os(macOS)
    import SwiftUI

    struct DocumentTableMac: View {
        let documents: [Document]
        @ObservedObject var ragService: RAGService
        @Binding var selection: Set<Document.ID>
        /// Double-click, or Show Details in the menu: the details in the inspector.
        let onShowDetails: (Document.ID) -> Void

        @Environment(\.undoManager) private var undoManager
        @Environment(\.macAreaIsActive) private var macAreaIsActive
        @State private var sortOrder = [KeyPathComparator(\Document.addedAt, order: .reverse)]
        /// Documents in an iCloud library ask before they go, as the card's Delete does.
        @State private var pendingICloudDeletion: [Document] = []

        private var rows: [Document] {
            documents.sorted(using: sortOrder)
        }

        var body: some View {
            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.filename) { document in
                    Label {
                        Text(document.filename)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } icon: {
                        Image(systemName: DocumentRow.iconName(for: document.contentType))
                            .foregroundStyle(DSColors.accent)
                    }
                    .help(document.filename)
                }
                .width(min: 220, ideal: 380)

                TableColumn("Kind", value: \.contentType.rawValue) { document in
                    Text(document.contentType.rawValue.uppercased())
                        .foregroundStyle(.secondary)
                }
                .width(min: 50, ideal: 70, max: 110)

                TableColumn("Passages", value: \.totalChunks) { document in
                    Text(document.totalChunks.formatted())
                        .monospacedDigit()
                }
                .width(min: 60, ideal: 76, max: 110)

                TableColumn("Words", value: \.macWordCount) { document in
                    Text(document.macWordCount > 0 ? document.macWordCount.formatted() : "\u{2014}")
                        .monospacedDigit()
                        .foregroundStyle(document.macWordCount > 0 ? .primary : .secondary)
                }
                .width(min: 60, ideal: 80, max: 120)

                TableColumn("Pages", value: \.macPageCount) { document in
                    Text(document.macPageCount > 0 ? document.macPageCount.formatted() : "\u{2014}")
                        .monospacedDigit()
                        .foregroundStyle(document.macPageCount > 0 ? .primary : .secondary)
                }
                .width(min: 46, ideal: 60, max: 90)

                TableColumn("Size", value: \.macFileSizeMB) { document in
                    Text(document.macFileSizeMB > 0 ? Self.sizeText(document.macFileSizeMB) : "\u{2014}")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 60, ideal: 76, max: 110)

                TableColumn("Added", value: \.addedAt) { document in
                    Text(document.addedAt, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                        .foregroundStyle(.secondary)
                }
                .width(min: 150, ideal: 180)
            }
            .contextMenu(forSelectionType: Document.ID.self) { ids in
                if ids.count == 1, let id = ids.first {
                    Button("Show Details") { onShowDetails(id) }
                    Button("Copy Link") {
                        SystemClipboard.copy(AppLink.webURL(for: .document(id)).absoluteString)
                    }
                }
                let deletable = deletableDocuments(ids)
                if !deletable.isEmpty {
                    Divider()
                    Button(deletable.count == 1 ? "Delete Document" : "Delete \(deletable.count) Documents", role: .destructive) {
                        delete(deletable)
                    }
                }
            } primaryAction: { ids in
                if let id = ids.first { onShowDetails(id) }
            }
            .onDeleteCommand {
                guard macAreaIsActive else { return }
                let deletable = deletableDocuments(selection)
                if !deletable.isEmpty { delete(deletable) }
            }
            .alert(
                pendingICloudDeletion.count == 1 ? "Delete Document?" : "Delete \(pendingICloudDeletion.count) Documents?",
                isPresented: Binding(
                    get: { !pendingICloudDeletion.isEmpty },
                    set: { if !$0 { pendingICloudDeletion = [] } })
            ) {
                Button("Cancel", role: .cancel) { pendingICloudDeletion = [] }
                Button("Delete", role: .destructive) {
                    ragService.scheduleRemoval(of: pendingICloudDeletion, undoManager: undoManager)
                    pendingICloudDeletion = []
                }
            } message: {
                if pendingICloudDeletion.count == 1, let document = pendingICloudDeletion.first {
                    Text(ModernDocumentCard.sharedDeleteMessage(for: document.filename))
                } else {
                    Text("These documents are in an iCloud library, so they are deleted on every device signed in to it.")
                }
            }
        }

        /// The selected documents that may be deleted: the guide library's come with the app and stay.
        private func deletableDocuments(_ ids: Set<Document.ID>) -> [Document] {
            documents.filter { ids.contains($0.id) && !ragService.isProtectedGuideDocument($0) }
        }

        /// As a swipe deletes on the iPhone (`swipeDelete`): at once, undoable for a few seconds, unless a document is in
        /// an iCloud library, which asks first.
        private func delete(_ documents: [Document]) {
            if documents.contains(where: { ragService.syncMode(for: $0) == .iCloudShared }) {
                pendingICloudDeletion = documents
            } else {
                ragService.scheduleRemoval(of: documents, undoManager: undoManager)
                selection.subtract(documents.map(\.id))
            }
        }

        private static func sizeText(_ megabytes: Double) -> String {
            ByteCountFormatter.string(fromByteCount: Int64(megabytes * 1_048_576), countStyle: .file)
        }
    }

    extension Document {
        /// Words, pages and size as the import measured them, or zero where the document carries no measurements.
        var macWordCount: Int { processingMetadata?.totalWords ?? 0 }
        var macPageCount: Int { processingMetadata?.pagesProcessed ?? 0 }
        var macFileSizeMB: Double { processingMetadata?.fileSizeMB ?? 0 }
    }
#endif
