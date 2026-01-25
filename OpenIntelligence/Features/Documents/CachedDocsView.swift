//
//  CachedDocsView.swift
//  OpenIntelligence
//
//  Created by Copilot on 2025
//  Browser for cached documentation with RAG ingestion support
//

import SwiftUI

// Note: CachedDocMetadata is now a top-level type in DocumentationCacheService.swift

/// View for browsing, searching, and ingesting cached documentation
struct CachedDocsView: View {
    let ragService: RAGService

    @Environment(\.dismiss) private var dismiss
    @State private var cachedDocs: [CachedDocMetadata] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var selectedDoc: CachedDocMetadata?
    @State private var selectedFullDoc: CachedDocument?
    @State private var showingDeleteConfirmation = false
    @State private var docToDelete: CachedDocMetadata?
    @State private var ingestingDocId: UUID?
    @State private var showingPreview = false
    @State private var errorMessage: String?

    private var filteredDocs: [CachedDocMetadata] {
        if searchText.isEmpty {
            return cachedDocs
        }
        let lowercasedSearch = searchText.lowercased()
        return cachedDocs.filter { doc in
            doc.title.lowercased().contains(lowercasedSearch) ||
            doc.url.absoluteString.lowercased().contains(lowercasedSearch)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if cachedDocs.isEmpty {
                    emptyStateView
                } else {
                    docListView
                }
            }
            .navigationTitle("Cached Docs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(role: .destructive) {
                            Task { await pruneExpired() }
                        } label: {
                            Label("Prune Expired", systemImage: "trash.slash")
                        }

                        Button(role: .destructive) {
                            Task { await clearAllCache() }
                        } label: {
                            Label("Clear All Cache", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search cached docs...")
            .sheet(isPresented: $showingPreview) {
                if let doc = selectedFullDoc {
                    DocPreviewSheet(document: doc)
                }
            }
            .alert("Delete Cached Document?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    docToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let doc = docToDelete {
                        Task { await deleteDoc(doc) }
                    }
                }
            } message: {
                if let doc = docToDelete {
                    Text("This will remove \"\(doc.title)\" from the cache. The original source remains available online.")
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let msg = errorMessage {
                    Text(msg)
                }
            }
        }
        .task {
            await loadCachedDocs()
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading cached docs...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Cached Docs", systemImage: "doc.on.doc")
        } description: {
            Text("Documentation you fetch from the web will be cached here for offline access and easy ingestion.")
        }
    }

    private var docListView: some View {
        List {
            Section {
                ForEach(filteredDocs) { doc in
                    CachedDocRow(
                        document: doc,
                        isIngesting: ingestingDocId == doc.id,
                        onPreview: {
                            Task { await showPreview(for: doc) }
                        },
                        onIngest: {
                            Task { await ingestDoc(doc) }
                        },
                        onDelete: {
                            docToDelete = doc
                            showingDeleteConfirmation = true
                        }
                    )
                }
            } header: {
                Text("\(filteredDocs.count) cached document\(filteredDocs.count == 1 ? "" : "s")")
            } footer: {
                if let oldest = cachedDocs.min(by: { $0.fetchDate < $1.fetchDate }) {
                    Text("Oldest: \(oldest.fetchDate.formatted(date: .abbreviated, time: .shortened))")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Actions

    private func loadCachedDocs() async {
        isLoading = true
        defer { isLoading = false }

        cachedDocs = await DocumentationCacheService.shared.listCached()
            .sorted { $0.fetchDate > $1.fetchDate }
    }

    private func showPreview(for doc: CachedDocMetadata) async {
        if let fullDoc = await DocumentationCacheService.shared.get(id: doc.id) {
            selectedFullDoc = fullDoc
            showingPreview = true
        }
    }

    private func ingestDoc(_ doc: CachedDocMetadata) async {
        ingestingDocId = doc.id
        defer { ingestingDocId = nil }

        do {
            // Export cached doc for RAG ingestion
            guard let url = try await DocumentationCacheService.shared.exportForIngestion(id: doc.id) else {
                errorMessage = "Failed to prepare document for ingestion"
                return
            }

            // Ingest into RAG
            await MainActor.run {
                _ = ragService.enqueueDocuments([url])
            }
        } catch {
            errorMessage = "Failed to export document: \(error.localizedDescription)"
        }
    }

    private func deleteDoc(_ doc: CachedDocMetadata) async {
        do {
            try await DocumentationCacheService.shared.delete(id: doc.id)
        } catch {
            errorMessage = "Failed to delete: \(error.localizedDescription)"
        }
        await loadCachedDocs()
        docToDelete = nil
    }

    private func pruneExpired() async {
        do {
            let count = try await DocumentationCacheService.shared.pruneExpired()
            await loadCachedDocs()
            if count > 0 {
                errorMessage = "Removed \(count) expired document\(count == 1 ? "" : "s")"
            }
        } catch {
            errorMessage = "Prune failed: \(error.localizedDescription)"
        }
    }

    private func clearAllCache() async {
        do {
            try await DocumentationCacheService.shared.clearAll()
        } catch {
            errorMessage = "Clear failed: \(error.localizedDescription)"
        }
        await loadCachedDocs()
    }
}

// MARK: - Row View

private struct CachedDocRow: View {
    let document: CachedDocMetadata
    let isIngesting: Bool
    let onPreview: () -> Void
    let onIngest: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(document.title)
                        .font(.headline)
                        .lineLimit(2)

                    Text(document.url.host ?? document.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(document.fetchDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Text("\(document.wordCount) words")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Action buttons
            HStack(spacing: 12) {
                Button(action: onPreview) {
                    Label("Preview", systemImage: "eye")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: onIngest) {
                    if isIngesting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Ingest", systemImage: "arrow.down.doc")
                            .font(.caption)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isIngesting)

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview Sheet

private struct DocPreviewSheet: View {
    let document: CachedDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Metadata header
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Source") {
                                Link(destination: document.url) {
                                    Text(document.url.host ?? "Link")
                                        .lineLimit(1)
                                }
                            }

                            LabeledContent("Fetched") {
                                Text(document.fetchDate.formatted(date: .long, time: .shortened))
                            }

                            LabeledContent("Size") {
                                Text("\(document.wordCount) words")
                            }

                            LabeledContent("Type") {
                                Text(document.sourceType.rawValue)
                            }
                        }
                        .font(.subheadline)
                    }

                    Divider()

                    // Content preview
                    Text(document.content)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                .padding()
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    ShareLink(
                        item: document.content,
                        subject: Text(document.title),
                        message: Text("From: \(document.url.absoluteString)")
                    )
                }
            }
        }
    }
}

#Preview {
    CachedDocsView(ragService: RAGService())
}
