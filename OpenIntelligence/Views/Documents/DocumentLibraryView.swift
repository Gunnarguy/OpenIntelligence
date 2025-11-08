//
//  DocumentLibraryView.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct DocumentLibraryView: View {
    @ObservedObject var ragService: RAGService
    @ObservedObject var containerService: ContainerService
    @State private var showingFilePicker = false
    @State private var showingProcessingSummary = false
    @State private var lastProcessedSummary: ProcessingSummary?
    @State private var showingContainerSettings = false
    @State private var showingSemanticSearch = false
    let onViewVisualizations: (() -> Void)?

    init(ragService: RAGService, containerService: ContainerService, onViewVisualizations: (() -> Void)? = nil) {
        self._ragService = ObservedObject(wrappedValue: ragService)
        self._containerService = ObservedObject(wrappedValue: containerService)
        self.onViewVisualizations = onViewVisualizations
    }
    
    private var filteredDocuments: [Document] {
        let activeId = containerService.activeContainerId
        let defaultId = containerService.containers.first?.id
        return ragService.documents.filter { doc in
            if let cid = doc.containerId {
                return cid == activeId
            } else {
                // Legacy docs without containerId appear only in the default container
                return activeId == defaultId
            }
        }
    }
    
    private var filteredTotalChunks: Int {
        filteredDocuments.reduce(0) { $0 + $1.totalChunks }
    }
    
    var body: some View {
        ZStack {
            // Modern gradient background
            LinearGradient(
                colors: [
                    DSColors.background,
                    DSColors.surface.opacity(0.3)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            if filteredDocuments.isEmpty {
                // Modern empty state
                VStack(spacing: 12) {
                    ContainerPickerStrip(containerService: containerService)
                        .padding(.horizontal)
                    EmptyDocumentsView()
                }
            } else {
                VStack(spacing: 12) {
                    ContainerPickerStrip(containerService: containerService)
                        .padding(.horizontal)
                    // Document list with modern styling
                    ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredDocuments) { document in
                            NavigationLink(destination: DocumentDetailsView(document: document)) {
                                ModernDocumentCard(document: document, ragService: ragService)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    
                    // Stats footer
                    StatsFooter(totalChunks: filteredTotalChunks)
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                }
                }
            }
        }
        .navigationTitle("Documents")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { showingFilePicker = true }) {
                    Label("Add Document", systemImage: "plus")
                }
                .disabled(ragService.isProcessing)
            }
            
            ToolbarItem(placement: .automatic) {
                Button {
                    showingContainerSettings = true
                } label: {
                    Label("Manage Library", systemImage: "gearshape")
                }
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    showingSemanticSearch = true
                } label: {
                    Label("Semantic Search", systemImage: "text.magnifyingglass")
                }
                .disabled(ragService.documents.isEmpty)
            }
            
            if filteredDocuments.count > 0 {
                ToolbarItem(placement: .automatic) {
                    Button {
                        onViewVisualizations?()
                    } label: {
                        Label("Visualize", systemImage: "cube.transparent")
                    }
                }
            }
            
            if !ragService.documents.isEmpty {
                ToolbarItem(placement: .automatic) {
                    Button(role: .destructive) {
                        Task {
                            try? await ragService.clearAllDocuments()
                        }
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                }
            }
        }
        .sheet(isPresented: $showingFilePicker) {
            DocumentPicker { url in
                Task {
                    try? await ragService.addDocument(at: url)
                }
            }
        }
        .alert("Error Processing Document", isPresented: .constant(ragService.lastError != nil)) {
            Button("OK", role: .cancel) {
                ragService.lastError = nil
            }
        } message: {
            if let error = ragService.lastError {
                Text(error)
            }
        }
        .overlay {
            if ragService.isProcessing {
                ProcessingOverlay(status: ragService.processingStatus)
            }
        }
        .sheet(isPresented: $showingContainerSettings) {
            ContainerSettingsSheet(containerService: containerService)
        }
        .sheet(isPresented: Binding(
            get: { ragService.lastProcessingSummary != nil },
            set: { if !$0 { ragService.lastProcessingSummary = nil } }
        )) {
            if let summary = ragService.lastProcessingSummary {
                ProcessingSummaryView(summary: summary)
            }
        }
        .sheet(isPresented: $showingSemanticSearch) {
            SemanticSearchView(
                ragService: ragService,
                containerService: containerService
            )
        }
    }
}

// MARK: - Modern Document Card

struct ModernDocumentCard: View {
    let document: Document
    @ObservedObject var ragService: RAGService
    @State private var showingDeleteAlert = false
    
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
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Delete Document?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    try? await ragService.removeDocument(document)
                }
            }
        } message: {
            Text("This will remove \"\(document.filename)\" and all its chunks from your knowledge base.")
        }
    }
}

struct DocumentRow: View {
    let document: Document
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: iconName(for: document.contentType))
                    .foregroundColor(.accentColor)
                Text(document.filename)
                    .font(.headline)
            }
            
            HStack {
                Text("\(document.totalChunks) chunks")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(document.addedAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func iconName(for type: DocumentType) -> String {
        DocumentRow.iconName(for: type)
    }
}

// MARK: - Empty State

struct EmptyDocumentsView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Hero icon with gradient
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.1),
                                Color.accentColor.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("No Documents Yet")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Build your knowledge base by adding documents")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Features
            VStack(alignment: .leading, spacing: 12) {
                DocumentFeatureRow(
                    icon: "doc.fill",
                    title: "Multiple Formats",
                    description: "PDF, Text, Markdown, and more"
                )
                
                DocumentFeatureRow(
                    icon: "bolt.fill",
                    title: "Fast Processing",
                    description: "Automatic chunking and embedding"
                )
                
                DocumentFeatureRow(
                    icon: "cylinder.fill",
                    title: "Persistent Storage",
                    description: "Saved locally on your device"
                )
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DocumentFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct ContainerPickerStrip: View {
    @ObservedObject var containerService: ContainerService
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(containerService.containers, id: \.id) { c in
                    let isActive = c.id == containerService.activeContainerId
                    Button(action: { containerService.setActive(c.id) }) {
                        HStack(spacing: 6) {
                            Image(systemName: c.icon)
                            Text(c.name)
                                .lineLimit(1)
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isActive ? Color.accentColor.opacity(0.2) : DSColors.surface)
                        .foregroundColor(isActive ? .accentColor : .primary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                
                Button {
                    let new = containerService.createContainer(name: "Library \(containerService.containers.count + 1)")
                    containerService.setActive(new.id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("New Library")
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DSColors.surface)
                    .foregroundColor(.primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
        }
    }
}

struct ContainerSettingsSheet: View {
    @ObservedObject var containerService: ContainerService
    @Environment(\.dismiss) var dismiss
    @State private var name: String = ""
    @State private var icon: String = "folder.fill"
    @State private var colorHex: String = "#4F46E5"
    @State private var providerId: String = "nl_embedding"
    @State private var dim: Int = 512
    @State private var dbKind: VectorDBKind = .persistentJSON
    @State private var strictMode: Bool = true
    
    private var activeContainer: KnowledgeContainer? {
        containerService.containers.first(where: { $0.id == containerService.activeContainerId })
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Library")) {
                    TextField("Name", text: $name)
                    TextField("Icon (SF Symbol)", text: $icon)
                    TextField("Color Hex", text: $colorHex)
                    HStack {
                        Toggle("Strict Mode (medical-grade)", isOn: $strictMode)
                        InfoButtonView(
                            title: "Strict Mode",
                            explanation: "When enabled, this library requires a higher standard of evidence before answering.\n\n• Similarity Threshold: Retrieved chunks must be at least 52% similar to your query.\n\n• Supporting Chunks: At least 3 high-confidence chunks are required.\n\nIf these conditions aren't met, the model will state that it cannot answer reliably, preventing responses based on low-quality or insufficient information. Ideal for medical or technical libraries where accuracy is critical."
                        )
                    }
                }
                
                Section(header: Text("Embeddings")) {
                    TextField("Provider ID", text: $providerId)
                    Picker("Dimensions", selection: $dim) {
                        Text("384").tag(384)
                        Text("512").tag(512)
                        Text("768").tag(768)
                        Text("1024").tag(1024)
                    }
                    Text("Changing dimensions requires re-embedding.").font(.caption).foregroundColor(.secondary)
                }
                
                Section(header: Text("Vector Database")) {
                    Picker("Engine", selection: $dbKind) {
                        ForEach(VectorDBKind.allCases, id: \.self) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    Text("Vectura HNSW requires VecturaKit at build time; otherwise falls back to JSON.").font(.caption).foregroundColor(.secondary)
                }
            }
            .navigationTitle("Library Settings")
            .iOSNavigationBarInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if var c = activeContainer {
                            c.name = name
                            c.icon = icon
                            c.colorHex = colorHex
                            let prevDim = c.embeddingDim
                            let prevDB = c.vectorDBKind
                            c.embeddingProviderId = providerId
                            c.embeddingDim = dim
                            c.vectorDBKind = dbKind
                            c.strictMode = strictMode
                            containerService.updateContainer(c)
                            // If engine changed, router will re-create lazily next access.
                            // If dimension changed, a re-embed workflow should be offered.
                            // For now, show a console hint.
                            if prevDim != dim {
                                print("ℹ️ Container \(c.name) embedding dimension changed from \(prevDim) to \(dim). Re-embedding required for best results.")
                            }
                            if prevDB != dbKind {
                                print("ℹ️ Container \(c.name) vector DB changed to \(dbKind). New index will be used on next retrieval.")
                            }
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let c = activeContainer {
                    name = c.name
                    icon = c.icon
                    colorHex = c.colorHex
                    providerId = c.embeddingProviderId
                    dim = c.embeddingDim
                    dbKind = c.vectorDBKind
                    strictMode = c.strictMode
                }
            }
        }
    }
}

// MARK: - Stats Footer

struct StatsFooter: View {
    let totalChunks: Int
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\(totalChunks) chunks stored")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("Saved to disk • Ready for queries")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green.opacity(0.1))
        )
    }
}

extension DocumentRow {
    static func iconName(for type: DocumentType) -> String {
        switch type {
        // Documents
        case .pdf:
            return "doc.fill"
        case .text:
            return "doc.text.fill"
        case .markdown:
            return "doc.richtext.fill"
        case .rtf:
            return "doc.richtext.fill"
            
        // Images
        case .png, .jpeg, .heic, .tiff, .gif, .image:
            return "photo.fill"
            
        // Code files
        case .swift:
            return "swift"
        case .python:
            return "chevron.left.forwardslash.chevron.right"
        case .javascript, .typescript:
            return "curlybraces"
        case .java, .cpp, .c, .objc, .go, .rust, .ruby, .php:
            return "chevron.left.forwardslash.chevron.right"
        case .html, .css, .xml:
            return "chevron.left.forwardslash.chevron.right"
        case .json, .yaml:
            return "curlybraces.square.fill"
        case .sql:
            return "cylinder.fill"
        case .shell, .code:
            return "terminal.fill"
            
        // Office documents
        case .word:
            return "doc.text.fill"
        case .excel, .csv:
            return "tablecells.fill"
        case .powerpoint:
            return "rectangle.3.group.fill"
        case .pages:
            return "doc.richtext.fill"
        case .numbers:
            return "tablecells.fill"
        case .keynote:
            return "rectangle.3.group.fill"
            
        case .unknown:
            return "doc.questionmark"
        }
    }
}

struct ProcessingOverlay: View {
    let status: String
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Animated progress indicator
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 4)
                        .frame(width: 60, height: 60)
                    
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                }
                
                VStack(spacing: 8) {
                    // Main status message
                    if !status.isEmpty {
                        let components = status.split(separator: "•", maxSplits: 1)
                        
                        if components.count >= 2 {
                            // Show filename
                            Text(String(components[0]).trimmingCharacters(in: .whitespaces))
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            
                            // Show detailed progress
                            HStack(spacing: 6) {
                                Image(systemName: progressIcon(for: String(components[1])))
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                
                                Text(String(components[1]).trimmingCharacters(in: .whitespaces))
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.15))
                            )
                        } else {
                            Text(status)
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                    }
                    
                    // Subtle hint text
                    Text("Processing document...")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            )
        }
    }
    
    private func progressIcon(for status: String) -> String {
        let lowerStatus = status.lowercased()
        
        if lowerStatus.contains("loading") {
            return "arrow.down.circle.fill"
        } else if lowerStatus.contains("extracting") || lowerStatus.contains("page") {
            return "doc.text.magnifyingglass"
        } else if lowerStatus.contains("ocr") {
            return "text.viewfinder"
        } else if lowerStatus.contains("chunking") {
            return "scissors"
        } else if lowerStatus.contains("embedding") {
            return "brain.head.profile"
        } else if lowerStatus.contains("storing") {
            return "cylinder.fill"
        } else {
            return "sparkles"
        }
    }
}

// MARK: - Document Picker

#if canImport(UIKit)
struct DocumentPicker: UIViewControllerRepresentable {
    let onDocumentPicked: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [
            .pdf,
            .plainText,
            .text,
            UTType(filenameExtension: "md") ?? .plainText,
            .rtf
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
            print("📚 Processing \(urls.count) selected file(s)...")
            
            for url in urls {
                // Start accessing a security-scoped resource
                guard url.startAccessingSecurityScopedResource() else {
                    print("❌ Failed to access security-scoped resource: \(url.lastPathComponent)")
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
                    parent.onDocumentPicked(destinationURL)
                    print("✓ Queued: \(url.lastPathComponent)")
                } catch {
                    print("❌ Error copying document \(url.lastPathComponent): \(error)")
                }
            }
        }
    }
}

#endif

#if !canImport(UIKit)
struct DocumentPicker: View {
    let onDocumentPicked: (URL) -> Void
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

// MARK: - Processing Summary View

struct ProcessingSummaryView: View {
    let summary: ProcessingSummary
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Success header
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        
                        Text("Document Processed!")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(summary.filename)
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)
                    
                    // File Info Section
                    InfoSection(title: "File Information", icon: "doc.fill", color: .blue) {
                        DetailInfoRow(label: "File Size", value: summary.fileSize)
                        DetailInfoRow(label: "Type", value: summary.documentType.rawValue.capitalized)
                        if let pageCount = summary.pageCount {
                            DetailInfoRow(label: "Pages", value: "\(pageCount)")
                        }
                        if let ocrPages = summary.ocrPagesUsed {
                            DetailInfoRow(label: "OCR Used", value: "\(ocrPages) pages")
                        }
                    }
                    
                    // Content Statistics Section
                    InfoSection(title: "Content Statistics", icon: "text.alignleft", color: .green) {
                        DetailInfoRow(label: "Characters", value: String(format: "%,d", summary.totalChars))
                        DetailInfoRow(label: "Words", value: String(format: "%,d", summary.totalWords))
                        DetailInfoRow(label: "Chunks Created", value: "\(summary.chunksCreated)")
                        DetailInfoRow(label: "Avg Chunk Size", value: "\(summary.chunkStats.avgChars) chars")
                        DetailInfoRow(label: "Size Range", value: "\(summary.chunkStats.minChars) - \(summary.chunkStats.maxChars) chars")
                    }
                    
                    // Performance Section
                    InfoSection(title: "Performance Metrics", icon: "speedometer", color: .orange) {
                        DetailInfoRow(label: "Extraction Time", value: String(format: "%.2f s", summary.extractionTime))
                        DetailInfoRow(label: "Chunking Time", value: String(format: "%.3f s", summary.chunkingTime))
                        DetailInfoRow(label: "Embedding Time", value: String(format: "%.2f s", summary.embeddingTime))
                        DetailInfoRow(label: "Avg per Chunk", value: String(format: "%.0f ms", (summary.embeddingTime / Double(summary.chunksCreated)) * 1000))
                        Divider()
                        DetailInfoRow(label: "Total Time", value: String(format: "%.2f s", summary.totalTime), highlight: true)
                    }
                }
                .padding()
            }
            .navigationTitle("Processing Complete")
            .iOSNavigationBarInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

extension View {
    @ViewBuilder func iOSNavigationBarInline() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

struct InfoSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
            }
            
            VStack(spacing: 8) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(DSColors.surface)
        .cornerRadius(12)
    }
}

// MARK: - Simple Info Row for Document Details

struct DetailInfoRow: View {
    let label: String
    let value: String
    var highlight: Bool = false
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(highlight ? .bold : .regular)
                .foregroundColor(highlight ? .primary : .primary)
        }
        .font(highlight ? .body : .subheadline)
    }
}

// MARK: - Document Details View

struct DocumentDetailsView: View {
    let document: Document
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18, pinnedViews: []) {
                documentHeaderCard
                vectorStorageCard
                
                if let metadata = document.processingMetadata {
                    contentAnalysisCard(metadata)
                    chunkingStrategyCard(metadata)
                    performanceMetricsCard(metadata)
                    
                    if metadata.ocrPagesCount ?? 0 > 0 {
                        ocrDetailsCard(metadata)
                    }
                }
                
                technicalDetailsCard
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 18)
        }
            .background(DSColors.background.ignoresSafeArea())
            .navigationTitle("Document Intelligence")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
    }
    
    // MARK: - Document Header Card
    
    @ViewBuilder
    private var documentHeaderCard: some View {
        DocumentDetailCardView(icon: iconName(for: document.contentType), title: document.filename, caption: "Document Overview") {
            VStack(alignment: .leading, spacing: 12) {
                // Type badge
                HStack {
                    Text(document.contentType.rawValue.uppercased())
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.2), Color.accentColor.opacity(0.1)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.accentColor)
                        .cornerRadius(8)
                    
                    Spacer()
                    
                    Text(document.addedAt, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Quick stats
                HStack(spacing: 20) {
                    QuickStatView(
                        icon: "cube.box.fill",
                        value: "\(document.totalChunks)",
                        label: "Chunks",
                        color: .blue
                    )
                    
                    if let metadata = document.processingMetadata {
                        QuickStatView(
                            icon: "doc.text",
                            value: formatNumber(metadata.totalCharacters),
                            label: "Characters",
                            color: .green
                        )
                        
                        QuickStatView(
                            icon: "text.word.spacing",
                            value: formatNumber(metadata.totalWords),
                            label: "Words",
                            color: .orange
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Vector Storage Card
    
    @ViewBuilder
    private var vectorStorageCard: some View {
        DocumentDetailCardView(icon: "cylinder.fill", title: "Vector Storage", caption: "Embedding metrics") {
            VStack(spacing: 8) {
                VectorMetricRow(
                    icon: "brain.head.profile",
                    label: "Embedding Model",
                    value: "NLEmbedding",
                    detail: "Word2Vec-based, 512 dimensions"
                )
                
                VectorMetricRow(
                    icon: "square.stack.3d.up.fill",
                    label: "Vector Dimensions",
                    value: "512-dim",
                    detail: "Cosine similarity search"
                )
                
                VectorMetricRow(
                    icon: "memorychip",
                    label: "Memory Footprint",
                    value: estimatedMemoryUsage,
                    detail: "Vectors + metadata"
                )
                
                VectorMetricRow(
                    icon: "externaldrive.fill",
                    label: "Storage Status",
                    value: "Persisted",
                    detail: "Auto-saved to disk",
                    valueColor: .green
                )
            }
        }
    }
    
    // MARK: - Content Analysis Card
    
    @ViewBuilder
    private func contentAnalysisCard(_ metadata: ProcessingMetadata) -> some View {
        DocumentDetailCardView(icon: "text.magnifyingglass", title: "Content Analysis", caption: "Document structure breakdown") {
            VStack(spacing: 8) {
                ContentMetricRow(
                    icon: "doc.on.doc",
                    iconColor: .blue,
                    label: "File Size",
                    value: String(format: "%.2f MB", metadata.fileSizeMB),
                    detail: formatBytes(Int(metadata.fileSizeMB * 1024 * 1024))
                )
                
                if let pages = metadata.pagesProcessed {
                    ContentMetricRow(
                        icon: "doc.plaintext",
                        iconColor: .purple,
                        label: "Pages Processed",
                        value: "\(pages)",
                        detail: pages > 1 ? "Multi-page document" : "Single page"
                    )
                }
                
                ContentMetricRow(
                    icon: "character.book.closed",
                    iconColor: .green,
                    label: "Total Characters",
                    value: formatNumber(metadata.totalCharacters),
                    detail: "\(formatNumber(metadata.totalWords)) words"
                )
                
                ContentMetricRow(
                    icon: "chart.line.uptrend.xyaxis",
                    iconColor: .orange,
                    label: "Content Density",
                    value: String(format: "%.1f", contentDensity(metadata)),
                    detail: "Words per 100 characters"
                )
            }
        }
    }
    
    // MARK: - Chunking Strategy Card
    
    @ViewBuilder
    private func chunkingStrategyCard(_ metadata: ProcessingMetadata) -> some View {
        DocumentDetailCardView(icon: "scissors", title: "Chunking Strategy", caption: "Semantic paragraph-based splitting") {
            VStack(spacing: 8) {
                ChunkMetricRow(
                    icon: "cube.box",
                    label: "Total Chunks",
                    value: "\(document.totalChunks)",
                    badge: "Optimal"
                )
                
                ChunkMetricRow(
                    icon: "ruler",
                    label: "Average Size",
                    value: "\(metadata.chunkStats.averageChars) chars",
                    badge: "\(averageWords(metadata)) words"
                )
                
                ChunkMetricRow(
                    icon: "arrow.up.arrow.down",
                    label: "Size Range",
                    value: "\(metadata.chunkStats.minChars) - \(metadata.chunkStats.maxChars)",
                    badge: "Chars"
                )
                
                Divider()
                
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text("400-word target with 50-word overlap for context preservation")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    
    // MARK: - Performance Metrics Card
    
    @ViewBuilder
    private func performanceMetricsCard(_ metadata: ProcessingMetadata) -> some View {
        DocumentDetailCardView(icon: "speedometer", title: "Performance Metrics", caption: "Processing pipeline timing") {
            VStack(spacing: 8) {
                PerformanceRow(
                    icon: "doc.text.magnifyingglass",
                    iconColor: .blue,
                    label: "Text Extraction",
                    time: metadata.extractionTimeSeconds,
                    detail: extractionMethod(metadata)
                )
                
                PerformanceRow(
                    icon: "scissors",
                    iconColor: .orange,
                    label: "Semantic Chunking",
                    time: metadata.chunkingTimeSeconds,
                    detail: "\(document.totalChunks) chunks created"
                )
                
                PerformanceRow(
                    icon: "brain.head.profile",
                    iconColor: .purple,
                    label: "Vector Embedding",
                    time: metadata.embeddingTimeSeconds,
                    detail: String(format: "%.0f ms/chunk avg", (metadata.embeddingTimeSeconds / Double(document.totalChunks)) * 1000)
                )
                
                Divider()
                
                PerformanceRow(
                    icon: "clock.fill",
                    iconColor: .green,
                    label: "Total Pipeline Time",
                    time: metadata.totalProcessingTimeSeconds,
                    detail: throughputRate(metadata),
                    highlight: true
                )
            }
        }
    }
    
    // MARK: - OCR Details Card
    
    @ViewBuilder
    private func ocrDetailsCard(_ metadata: ProcessingMetadata) -> some View {
        if let ocrPages = metadata.ocrPagesCount, ocrPages > 0 {
            DocumentDetailCardView(icon: "text.viewfinder", title: "OCR Processing", caption: "Vision framework text recognition") {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "eye.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                            .frame(width: 32)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Optical Character Recognition")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            Text("\(ocrPages) page\(ocrPages == 1 ? "" : "s") processed with Vision framework")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    Divider()
                    
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text("OCR was used for scanned pages or images without embedded text")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
    
    // MARK: - Technical Details Card
    
    @ViewBuilder
    private var technicalDetailsCard: some View {
        DocumentDetailCardView(icon: "info.circle", title: "Technical Details", caption: "System information") {
            VStack(spacing: 8) {
                TechnicalRow(label: "Document ID", value: document.id.uuidString.prefix(8) + "...")
                TechnicalRow(label: "Added", value: document.addedAt.formatted(date: .abbreviated, time: .standard))
                TechnicalRow(label: "File Type", value: document.contentType.rawValue)
                TechnicalRow(label: "Vector Database", value: "In-Memory (Persistent)")
                TechnicalRow(label: "Search Algorithm", value: "Cosine Similarity (k-NN)")
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private var estimatedMemoryUsage: String {
        let bytesPerChunk = (512 * 4) + 500
        let totalBytes = bytesPerChunk * document.totalChunks
        return formatBytes(totalBytes)
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.2f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }
    
    private func formatNumber(_ number: Int) -> String {
        if number < 1000 {
            return "\(number)"
        } else if number < 1_000_000 {
            return String(format: "%.1fK", Double(number) / 1000.0)
        } else {
            return String(format: "%.2fM", Double(number) / 1_000_000.0)
        }
    }
    
    private func contentDensity(_ metadata: ProcessingMetadata) -> Double {
        guard metadata.totalCharacters > 0 else { return 0 }
        return Double(metadata.totalWords) / Double(metadata.totalCharacters) * 100
    }
    
    private func averageWords(_ metadata: ProcessingMetadata) -> Int {
        return metadata.chunkStats.averageChars / 5 // Rough estimate: 5 chars per word
    }
    
    private func extractionMethod(_ metadata: ProcessingMetadata) -> String {
        if let ocrPages = metadata.ocrPagesCount, ocrPages > 0 {
            return "PDFKit + Vision OCR"
        } else {
            return "PDFKit native"
        }
    }
    
    private func throughputRate(_ metadata: ProcessingMetadata) -> String {
        let chunksPerSecond = Double(document.totalChunks) / metadata.totalProcessingTimeSeconds
        return String(format: "%.1f chunks/sec", chunksPerSecond)
    }
    
    private func iconName(for type: DocumentType) -> String {
        switch type {
        case .pdf: return "doc.fill"
        case .text: return "doc.text.fill"
        case .markdown: return "doc.richtext.fill"
        case .rtf: return "doc.richtext.fill"
        case .png, .jpeg, .heic, .tiff, .gif, .image: return "photo.fill"
        case .swift: return "swift"
        case .python: return "chevron.left.forwardslash.chevron.right"
        case .javascript, .typescript: return "curlybraces"
        case .java, .cpp, .c, .objc, .go, .rust, .ruby, .php: return "chevron.left.forwardslash.chevron.right"
        case .html, .css, .xml: return "chevron.left.forwardslash.chevron.right"
        case .json, .yaml: return "curlybraces.square.fill"
        case .sql: return "cylinder.fill"
        case .shell, .code: return "terminal.fill"
        case .word: return "doc.text.fill"
        case .excel: return "tablecells.fill"
        case .powerpoint: return "rectangle.3.group.fill"
        case .pages: return "doc.text.fill"
        case .numbers: return "tablecells.fill"
        case .keynote: return "rectangle.3.group.fill"
        case .csv: return "tablecells.fill"
        case .unknown: return "doc.questionmark"
        }
    }
}

struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    var highlight: Bool = false
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.accentColor)
            
            Text(label)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .fontWeight(highlight ? .semibold : .regular)
                .foregroundColor(highlight ? .accentColor : .primary)
        }
        .font(.subheadline)
    }
}

// MARK: - Document Detail Card Components

private struct DocumentDetailCardView<Content: View>: View {
    let icon: String?
    let title: String
    let caption: String?
    let content: Content
    
    init(icon: String? = nil, title: String, caption: String? = nil, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.caption = caption
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if icon != nil || !title.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .frame(width: 20)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .textCase(.uppercase)
                            .tracking(0.8)
                        if let caption, !caption.isEmpty {
                            Text(caption)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            content
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DSColors.surface)
                .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
        )
    }
}

private struct QuickStatView: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct VectorMetricRow: View {
    let icon: String
    let label: String
    let value: String
    let detail: String
    var valueColor: Color = .primary
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.subheadline)
                Text(value)
                    .font(.headline)
                    .foregroundColor(valueColor)
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct ContentMetricRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    let detail: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.subheadline)
                Text(value)
                    .font(.headline)
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct ChunkMetricRow: View {
    let icon: String
    let label: String
    let value: String
    let badge: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .font(.title3)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                Text(value)
                    .font(.headline)
            }
            
            Spacer()
            
            Text(badge)
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.15))
                .foregroundColor(.accentColor)
                .cornerRadius(6)
        }
        .padding(.vertical, 4)
    }
}

private struct PerformanceRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    let time: TimeInterval
    let detail: String
    var highlight: Bool = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(highlight ? .semibold : .regular)
                Text(String(format: "%.3f s", time))
                    .font(highlight ? .title3 : .headline)
                    .fontWeight(highlight ? .bold : .regular)
                    .foregroundColor(highlight ? .green : .primary)
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct TechnicalRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    DocumentLibraryView(ragService: RAGService(), containerService: ContainerService())
}
