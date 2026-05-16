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
    @State private var showingDeleteAlert = false

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
            // Icon with gradient background
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.6), Color.accentColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)

                Image(systemName: DocumentRow.iconName(for: document.contentType))
                    .font(.system(size: 24))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(document.filename)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    Label("\(document.totalChunks)", systemImage: "cube.box.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(document.addedAt, style: .relative)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                // Content tags row (iOS 26+)
                if !displayTags.isEmpty {
                    ContentTagsRow(tags: displayTags, hasMoreTags: (document.contentTags?.count ?? 0) > 3)
                }
            }

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DSColors.surface)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
        .contextMenu {
            Button(role: .destructive) {
                showingDeleteAlert = true
            } label: {
                Label(isSharedICloudDocument ? "Remove Local Copy" : "Delete", systemImage: "trash")
            }
        }
        .alert(isSharedICloudDocument ? "Remove Local Document?" : "Delete Document?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button(isSharedICloudDocument ? "Remove Local Copy" : "Delete", role: .destructive) {
                Task {
                    try? await ragService.removeDocument(document)
                }
            }
        } message: {
            if isSharedICloudDocument {
                Text("This removes \"\(document.filename)\" from this device's current copy of the shared iCloud library. If the document still exists in iCloud, Sync Now can bring it back.")
            } else {
                Text("This will remove \"\(document.filename)\" and all its chunks from your knowledge base on this device.")
            }
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
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(tagTextColor(for: index))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(tagColor(for: index))
                    )
            }

            if hasMoreTags {
                Text("...")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
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
