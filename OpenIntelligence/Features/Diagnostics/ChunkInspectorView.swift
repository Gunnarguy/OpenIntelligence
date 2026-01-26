//
//  ChunkInspectorView.swift
//  OpenIntelligence
//
//  God-mode chunk inspection for debugging extraction quality.
//

import SwiftUI

struct ChunkInspectorView: View {
    @ObservedObject var ragService: RAGService
    @EnvironmentObject private var containerService: ContainerService

    @State private var searchQuery: String = ""
    @State private var inspectionResults: [ChunkInspectionResult] = []
    @State private var isSearching: Bool = false
    @State private var selectedChunk: ChunkInspectionResult?
    @State private var corpusVerification: CorpusVerificationResult?
    @State private var inspectionMode: InspectionMode = .semantic
    @State private var allDocumentChunks: [ChunkInspectionResult] = []
    @State private var selectedDocument: Document?
    @State private var sortOrder: ChunkSortOrder = .chunkIndex
    @State private var filterStructureType: String? = nil

    enum InspectionMode: String, CaseIterable {
        case semantic = "Semantic Search"
        case exactMatch = "Exact Match (FTS5)"
        case browseAll = "Browse All Chunks"
    }

    enum ChunkSortOrder: String, CaseIterable {
        case relevance = "Relevance"
        case pageNumber = "Page Number"
        case chunkIndex = "Chunk Order"
        case wordCount = "Word Count"
        case structureType = "Structure Type"
    }

    var body: some View {
        VStack(spacing: 0) {
            inspectionHeader
            Divider()
            if inspectionMode == .browseAll {
                documentBrowser
            } else {
                searchInterface
            }
            Divider()
            resultsList
        }
        .navigationTitle("Chunk Inspector")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedChunk) { chunk in
            ChunkDetailSheet(chunk: chunk)
        }
    }

    private var inspectionHeader: some View {
        VStack(spacing: 12) {
            Picker("Mode", selection: $inspectionMode) {
                ForEach(InspectionMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            HStack(spacing: 16) {
                statPill(icon: "doc.text", value: "\(ragService.documents.count)", label: "Docs")
                if let container = containerService.activeContainer {
                    statPill(icon: "cube.box", value: container.name, label: "Container")
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .background(Color(.systemGroupedBackground))
    }

    private func statPill(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(Capsule())
    }

    private var searchInterface: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: inspectionMode == .exactMatch ? "textformat.abc" : "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(inspectionMode == .exactMatch ? "Exact phrase..." : "Semantic query...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .submitLabel(.search)
                    .onSubmit { performSearch() }
                if isSearching {
                    ProgressView().scaleEffect(0.8)
                } else if !searchQuery.isEmpty {
                    Button { searchQuery = ""; inspectionResults = []; corpusVerification = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)

            if searchQuery.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        quickSearchChip("SAE 0W-20")
                        quickSearchChip("SAE 5W-30")
                        quickSearchChip("engine oil")
                        quickSearchChip("viscosity")
                        quickSearchChip("2.0L")
                    }
                    .padding(.horizontal)
                }
            }

            if let v = corpusVerification {
                corpusVerificationBadge(v)
            }
        }
        .padding(.vertical, 12)
    }

    private func quickSearchChip(_ text: String) -> some View {
        Button {
            searchQuery = text
            performSearch()
        } label: {
            Text(text).font(.caption).padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.15)).foregroundStyle(Color.accentColor).clipShape(Capsule())
        }
    }

    private func corpusVerificationBadge(_ v: CorpusVerificationResult) -> some View {
        HStack(spacing: 8) {
            Image(systemName: v.found ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(v.found ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(v.found ? "Found in corpus" : "NOT found").font(.caption.bold()).foregroundStyle(v.found ? .green : .red)
                Text("\(v.occurrences) occurrences in \(v.documentCount) docs").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(v.found ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
    }

    private var documentBrowser: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ragService.documents) { doc in
                        Button {
                            selectedDocument = doc
                            loadChunksForDocument(doc)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: DocumentRow.iconName(for: doc.contentType)).font(.caption)
                                Text(doc.filename).font(.caption).lineLimit(1)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(selectedDocument?.id == doc.id ? Color.accentColor : Color(.secondarySystemGroupedBackground))
                            .foregroundStyle(selectedDocument?.id == doc.id ? .white : .primary)
                            .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal)
            }

            HStack {
                Picker("Sort", selection: $sortOrder) {
                    ForEach(ChunkSortOrder.allCases, id: \.self) { o in Text(o.rawValue).tag(o) }
                }.pickerStyle(.menu)
                Spacer()
                Menu {
                    Button("All Types") { filterStructureType = nil }
                    Button("Tables") { filterStructureType = "table" }
                    Button("Lists") { filterStructureType = "list" }
                    Button("Paragraphs") { filterStructureType = "paragraph" }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text(filterStructureType ?? "Filter").font(.caption)
                    }
                }
            }
            .padding(.horizontal)

            if let doc = selectedDocument {
                Text("\(filteredAndSortedChunks.count) chunks from \(doc.filename)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
    }

    private var filteredAndSortedChunks: [ChunkInspectionResult] {
        var chunks = allDocumentChunks
        if let f = filterStructureType { chunks = chunks.filter { $0.structureType == f } }
        switch sortOrder {
        case .relevance: chunks.sort { ($0.similarity ?? 0) > ($1.similarity ?? 0) }
        case .pageNumber: chunks.sort { ($0.pageNumber ?? 0) < ($1.pageNumber ?? 0) }
        case .chunkIndex: chunks.sort { $0.chunkIndex < $1.chunkIndex }
        case .wordCount: chunks.sort { $0.wordCount > $1.wordCount }
        case .structureType: chunks.sort { ($0.structureType ?? "") < ($1.structureType ?? "") }
        }
        return chunks
    }

    private var resultsList: some View {
        Group {
            if inspectionResults.isEmpty && allDocumentChunks.isEmpty && !isSearching {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass").font(.system(size: 48)).foregroundStyle(.secondary)
                    Text(inspectionMode == .browseAll ? "Select a document" : "Enter a search query").font(.headline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let chunks = inspectionMode == .browseAll ? filteredAndSortedChunks : inspectionResults
                List {
                    ForEach(chunks) { chunk in
                        ChunkRowView(chunk: chunk)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedChunk = chunk }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func performSearch() {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        inspectionResults = []
        corpusVerification = nil

        Task {
            if inspectionMode == .exactMatch {
                await performExactSearch()
            } else {
                await performSemanticSearch()
            }
            await MainActor.run { isSearching = false }
        }
    }

    private func performSemanticSearch() async {
        do {
            let retrieved = try await ragService.searchDocumentsRaw(query: searchQuery, topK: 50, minSimilarity: 0.1)
            let results = retrieved.map { r in
                ChunkInspectionResult(
                    id: r.chunk.id,
                    chunkIndex: r.chunk.metadata.chunkIndex,
                    content: r.chunk.content,
                    snippet: String(r.chunk.content.prefix(300)),
                    pageNumber: r.chunk.metadata.pageNumber,
                    sectionTitle: r.chunk.metadata.sectionTitle,
                    structureType: r.chunk.metadata.structureType,
                    wordCount: r.chunk.metadata.wordCount,
                    similarity: Double(r.similarityScore),
                    bm25Score: nil,
                    entities: r.chunk.metadata.entities,
                    keywords: r.chunk.metadata.keywords,
                    sectionPath: r.chunk.metadata.sectionPath,
                    documentName: r.sourceDocument,
                    contextualPrefix: r.chunk.contextualPrefix
                )
            }
            await MainActor.run { inspectionResults = results }
        } catch {
            Log.error("[ChunkInspector] Search failed: \(error)", category: .pipeline)
        }
    }

    private func performExactSearch() async {
        let cid = containerService.activeContainerId
        let counts = await SQLiteFullTextService.shared.countPatternInCorpus(pattern: searchQuery, containerId: cid)
        let v = CorpusVerificationResult(
            pattern: searchQuery,
            found: !counts.isEmpty,
            occurrences: counts.values.reduce(0, +),
            documentCount: counts.count
        )
        let fts = await SQLiteFullTextService.shared.search(query: searchQuery, containerId: cid, limit: 50)
        let results = fts.map { f in
            ChunkInspectionResult(
                id: f.documentId,
                chunkIndex: 0,
                content: f.content,
                snippet: f.snippet,
                pageNumber: nil,
                sectionTitle: nil,
                structureType: nil,
                wordCount: f.content.split(separator: " ").count,
                similarity: Double(-f.bm25Score),
                bm25Score: -f.bm25Score,
                entities: [],
                keywords: [],
                sectionPath: nil,
                documentName: nil,
                contextualPrefix: nil
            )
        }
        await MainActor.run { corpusVerification = v; inspectionResults = results }
    }

    private func loadChunksForDocument(_ doc: Document) {
        Task {
            do {
                let all = try await ragService.searchDocumentsRaw(query: doc.filename, topK: 500, minSimilarity: 0.0)
                let docChunks = all.filter { $0.chunk.documentId == doc.id }
                let results = docChunks.map { r in
                    ChunkInspectionResult(
                        id: r.chunk.id,
                        chunkIndex: r.chunk.metadata.chunkIndex,
                        content: r.chunk.content,
                        snippet: String(r.chunk.content.prefix(300)),
                        pageNumber: r.chunk.metadata.pageNumber,
                        sectionTitle: r.chunk.metadata.sectionTitle,
                        structureType: r.chunk.metadata.structureType,
                        wordCount: r.chunk.metadata.wordCount,
                        similarity: nil,
                        bm25Score: nil,
                        entities: r.chunk.metadata.entities,
                        keywords: r.chunk.metadata.keywords,
                        sectionPath: r.chunk.metadata.sectionPath,
                        documentName: doc.filename,
                        contextualPrefix: r.chunk.contextualPrefix
                    )
                }.sorted { $0.chunkIndex < $1.chunkIndex }
                await MainActor.run { allDocumentChunks = results }
            } catch {
                Log.error("[ChunkInspector] Load failed: \(error)", category: .pipeline)
            }
        }
    }
}

// MARK: - Chunk Row View

struct ChunkRowView: View {
    let chunk: ChunkInspectionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let st = chunk.structureType {
                    structureBadge(st)
                }
                if let p = chunk.pageNumber {
                    Text("p.\(p)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(Capsule())
                }
                Text("#\(chunk.chunkIndex)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                Spacer()
                if let sim = chunk.similarity {
                    HStack(spacing: 2) {
                        Image(systemName: "target").font(.caption2)
                        Text(String(format: "%.1f%%", sim * 100)).font(.caption2.bold())
                    }
                    .foregroundStyle(sim >= 0.6 ? .green : sim >= 0.4 ? .orange : .red)
                }
                Text("\(chunk.wordCount)w")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let path = chunk.sectionPath, !path.isEmpty {
                Text(path.joined(separator: " › "))
                    .font(.caption2)
                    .foregroundStyle(.blue)
                    .lineLimit(1)
            }
            Text(chunk.snippet ?? chunk.content)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(4)
        }
        .padding(.vertical, 8)
    }

    private func structureBadge(_ type: String) -> some View {
        let (icon, color): (String, Color) = {
            switch type.lowercased() {
            case "table": return ("tablecells", .cyan)
            case "list": return ("list.bullet", .green)
            case "title", "header": return ("textformat", .purple)
            default: return ("text.alignleft", .gray)
            }
        }()
        return HStack(spacing: 2) {
            Image(systemName: icon)
            Text(type.capitalized)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }
}

// MARK: - Chunk Detail Sheet

struct ChunkDetailSheet: View {
    let chunk: ChunkInspectionResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    metadataCard
                    contentCard
                    if let prefix = chunk.contextualPrefix, !prefix.isEmpty {
                        prefixCard(prefix)
                    }
                    if let path = chunk.sectionPath, !path.isEmpty {
                        sectionPathCard(path)
                    }
                    if !chunk.entities.isEmpty {
                        entitiesCard
                    }
                    if !chunk.keywords.isEmpty {
                        keywordsCard
                    }
                    technicalCard
                }
                .padding()
            }
            .navigationTitle("Chunk Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        UIPasteboard.general.string = chunk.content
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }
        }
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Metadata").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metadataItem("Chunk", value: "#\(chunk.chunkIndex)")
                metadataItem("Page", value: chunk.pageNumber.map { "Page \($0)" } ?? "N/A")
                metadataItem("Structure", value: chunk.structureType?.capitalized ?? "Text")
                metadataItem("Words", value: "\(chunk.wordCount)")
                metadataItem("Similarity", value: chunk.similarity.map { String(format: "%.2f", $0) } ?? "N/A")
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func metadataItem(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.bold())
        }
    }

    private var contentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Full Content").font(.headline)
                Spacer()
                Text("\(chunk.content.count) chars").font(.caption).foregroundStyle(.secondary)
            }
            Text(chunk.content)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func prefixCard(_ prefix: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Contextual Prefix").font(.headline)
            Text(prefix)
                .font(.caption)
                .foregroundStyle(.blue)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func sectionPathCard(_ path: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Section Hierarchy").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(Array(path.enumerated()), id: \.offset) { i, s in
                        if i > 0 {
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        Text(s)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var entitiesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Named Entities").font(.headline)
            FlowLayout(spacing: 6) {
                ForEach(chunk.entities, id: \.self) { e in
                    Text(e)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.15))
                        .foregroundStyle(.purple)
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var keywordsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keywords").font(.headline)
            FlowLayout(spacing: 6) {
                ForEach(chunk.keywords, id: \.self) { k in
                    Text(k)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var technicalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Technical Info").font(.headline)
            Text("ID: \(chunk.id.uuidString)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            if let n = chunk.documentName {
                Text("Document: \(n)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Supporting Types

struct ChunkInspectionResult: Identifiable {
    let id: UUID
    let chunkIndex: Int
    let content: String
    let snippet: String?
    let pageNumber: Int?
    let sectionTitle: String?
    let structureType: String?
    let wordCount: Int
    let similarity: Double?
    let bm25Score: Double?
    let entities: [String]
    let keywords: [String]
    let sectionPath: [String]?
    let documentName: String?
    let contextualPrefix: String?
}

struct CorpusVerificationResult {
    let pattern: String
    let found: Bool
    let occurrences: Int
    let documentCount: Int
}

#Preview {
    NavigationView {
        ChunkInspectorView(ragService: RAGService())
            .environmentObject(ContainerService())
    }
}
