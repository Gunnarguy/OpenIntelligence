//
//  DocumentCard.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import SwiftUI

struct ModernDocumentCard: View {
    let document: Document
    @ObservedObject var ragService: RAGService
    @EnvironmentObject private var workspaceSyncService: WorkspaceSyncService
    @State private var showingDeleteAlert = false
    @State private var deleteMode: DeleteMode = .local

    enum DeleteMode {
        case local
        case everywhere
    }

    private var documentSyncMode: LibrarySyncMode {
        ragService.syncMode(for: document)
    }

    private var isSharedICloudDocument: Bool {
        documentSyncMode == .iCloudShared
    }

    /// Display up to 3 tags to keep the card compact
    private var displayTags: [String] {
        guard let tags = document.contentTags, !tags.isEmpty else { return [] }
        return Array(tags.prefix(3))
    }

    var body: some View {
        HStack(spacing: 16) {
            // Icon with liquid gradient background
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.4), Color.accentColor.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                    .glassCircleEffectHelper()

                Image(systemName: DocumentRow.iconName(for: document.contentType))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(document.filename)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "cube.box.fill")
                        Text("\(document.totalChunks)")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(document.addedAt, style: .relative)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    
                    if isSharedICloudDocument {
                        HStack(spacing: 4) {
                            Image(systemName: "icloud.fill")
                            Text("Synced")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.blue.opacity(0.8))
                    }
                }

                // Content tags row (iOS 26+)
                if !displayTags.isEmpty {
                    ContentTagsRow(tags: displayTags, hasMoreTags: (document.contentTags?.count ?? 0) > 3)
                        .padding(.top, 2)
                }
            }

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        .contextMenu {
            Button(role: .destructive) {
                deleteMode = .local
                showingDeleteAlert = true
            } label: {
                Label(isSharedICloudDocument ? "Remove Local Copy" : "Delete", systemImage: "trash")
            }

            if isSharedICloudDocument {
                Button(role: .destructive) {
                    deleteMode = .everywhere
                    showingDeleteAlert = true
                } label: {
                    Label("Delete Everywhere", systemImage: "cloud.moon.fill")
                }
            }
        }
        .alert(alertTitle, isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button(confirmButtonTitle, role: .destructive) {
                Task {
                    if deleteMode == .everywhere {
                        try? await workspaceSyncService.deleteDocumentFromICloud(document)
                    }
                    try? await ragService.removeDocument(document)
                }
            }
        } message: {
            Text(alertMessage)
        }
    }

    // Both modes delete the document everywhere, so neither is labelled as if it were local.
    //
    // `.local` runs `removeDocument` alone; `.everywhere` runs
    // `deleteDocumentFromICloud` first and then `removeDocument`. The difference is that
    // `.everywhere` removes the shared file immediately while `.local` leaves the tombstone to
    // do it on the next sync pass. That is a timing difference, not a scope one, and calling
    // the first "Remove Local Copy" told users the opposite.
    private var alertTitle: String {
        switch deleteMode {
        case .local:
            return "Delete Document?"
        case .everywhere:
            return "Delete from iCloud?"
        }
    }

    private var confirmButtonTitle: String {
        switch deleteMode {
        case .local:
            return "Delete"
        case .everywhere:
            return "Delete Everywhere"
        }
    }

    private var alertMessage: String {
        switch deleteMode {
        case .local:
            if isSharedICloudDocument {
                // Was "If the document still exists in iCloud, Sync Now can bring it back."
                // It cannot. `removeDocument` calls `registerDeletedDocuments` before it does
                // anything else, and that tombstone is unioned into both workspace roots and
                // then used to filter the shared inventory, so the next sync pass removes the
                // document from iCloud and from every other device. Promising recovery on a
                // path that writes a permanent tombstone is the worst kind of wrong copy,
                // because it is read at the moment someone decides whether to tap Delete.
                return "This deletes \"\(document.filename)\" here and in iCloud, on every device signed in to this library. This cannot be undone."
            } else {
                return "This will remove \"\(document.filename)\" and all its chunks from your knowledge base on this device."
            }
        case .everywhere:
            return "This will permanently delete \"\(document.filename)\" from iCloud Sync and remove it from every device using this shared library. This cannot be undone."
        }
    }
}

// MARK: - Content Tags Row

/// Displays document content tags as compact pills
struct ContentTagsRow: View {
    let tags: [String]
    var hasMoreTags: Bool = false

    /// Gradient colors for tag backgrounds based on index
    private func tagColor(for index: Int) -> Color {
        let colors: [Color] = [
            .blue.opacity(0.15),
            .purple.opacity(0.15),
            .green.opacity(0.15),
            .orange.opacity(0.15),
            .pink.opacity(0.15),
        ]
        return colors[index % colors.count]
    }

    private func tagTextColor(for index: Int) -> Color {
        let colors: [Color] = [
            .blue,
            .purple,
            .green,
            .orange,
            .pink,
        ]
        return colors[index % colors.count]
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                Text(tag)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(tagTextColor(for: index).opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(tagColor(for: index).opacity(0.5))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(tagTextColor(for: index).opacity(0.15), lineWidth: 0.5)
                    )
            }

            if hasMoreTags {
                Image(systemName: "ellipsis")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.leading, 2)
            }
        }
    }
}

#Preview {
    ModernDocumentCard(
        document: Document(
            filename: "Annual Report.pdf",
            fileURL: URL(fileURLWithPath: "/tmp/report.pdf"),
            contentType: .pdf,
            totalChunks: 42
        ),
        ragService: RAGService()
    )
    .padding()
}
