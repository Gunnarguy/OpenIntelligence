//
//  DocumentDetailsView.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import SwiftUI

struct DocumentDetailsView: View {
    let document: Document
    let embeddingProviderId: String?

    /// Human-readable name for the embedding provider
    private var embeddingProviderDisplayName: String {
        switch embeddingProviderId {
        case "nl_contextual_embedding":
            return "Contextual Embedding"
        case "nl_embedding", nil:
            return "NLEmbedding"
        case "coreml_sentence_embedding":
            return "CoreML Sentence"
        case "apple_fm_embed":
            return "Apple FM"
        default:
            return embeddingProviderId ?? "NLEmbedding"
        }
    }

    /// Description for the embedding provider
    private var embeddingProviderDescription: String {
        switch embeddingProviderId {
        case "nl_contextual_embedding":
            return "BERT-based, high-accuracy semantic search"
        case "nl_embedding", nil:
            return "Word2Vec-based, 512 dimensions"
        case "coreml_sentence_embedding":
            return "Sentence-level, cross-lingual"
        case "apple_fm_embed":
            return "Foundation Model embeddings"
        default:
            return "512 dimensions"
        }
    }

    /// Whether this is a high-accuracy provider
    private var isHighAccuracyProvider: Bool {
        embeddingProviderId == "nl_contextual_embedding"
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18, pinnedViews: []) {
                documentHeaderCard

                // Content tags card (iOS 26+ feature)
                if let tags = document.contentTags, !tags.isEmpty {
                    contentTagsCard(tags: tags)
                }

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

    // MARK: - Content Tags Card (iOS 26+)

    @ViewBuilder
    private func contentTagsCard(tags: [String]) -> some View {
        DocumentDetailCardView(icon: "tag.fill", title: "Content Tags", caption: "Auto-generated by Apple Intelligence") {
            VStack(alignment: .leading, spacing: 12) {
                // Info text
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.purple)
                        .font(.caption)
                    Text("Topics, actions, and themes identified in this document")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Tags flow layout
                FlowLayout(spacing: 8) {
                    ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                        ContentTagPill(tag: tag, colorIndex: index)
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
                    icon: isHighAccuracyProvider ? "sparkles" : "brain.head.profile",
                    label: "Embedding Model",
                    value: embeddingProviderDisplayName,
                    detail: embeddingProviderDescription,
                    valueColor: isHighAccuracyProvider ? .purple : .primary
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
        DocumentDetailCardView(icon: "scissors", title: "Chunking Strategy", caption: "Semantic boundary detection") { 
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

                // Silicon-Native info
                HStack(spacing: 8) {
                    Image(systemName: "bolt.horizontal.fill")
                        .foregroundColor(.cyan)
                        .font(.caption)
                    Text("Semantic boundaries detected via embedding similarity • vDSP accelerated")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text("280-400 word target with ~17% overlap for optimal retrieval")
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
        DocumentDetailCardView(icon: "speedometer", title: "Performance Metrics", caption: "Silicon-native pipeline timing") { 
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
                    detail: "\(document.totalChunks) chunks via embeddings"
                )

                PerformanceRow(
                    icon: "brain.head.profile",
                    iconColor: .purple,
                    label: "Vector Embedding",
                    time: metadata.embeddingTimeSeconds,
                    detail: String(format: "%.0f ms/chunk (Neural Engine)", (metadata.embeddingTimeSeconds / Double(document.totalChunks)) * 1000)
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

                HStack(spacing: 8) {
                    Image(systemName: "bolt.horizontal.fill")
                        .foregroundColor(.cyan)
                        .font(.caption)
                    Text("Accelerate vDSP • Device-optimized batch sizes")
                        .font(.caption2)
                        .foregroundColor(.cyan)
                }
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

// MARK: - Content Tag Pill

private struct ContentTagPill: View {
    let tag: String
    let colorIndex: Int

    /// Gradient colors for tag backgrounds based on index
    private var tagBackgroundColor: Color {
        let colors: [Color] = [
            .blue.opacity(0.15),
            .purple.opacity(0.15),
            .green.opacity(0.15),
            .orange.opacity(0.15),
            .pink.opacity(0.15),
            .teal.opacity(0.15),
            .indigo.opacity(0.15),
            .mint.opacity(0.15),
        ]
        return colors[colorIndex % colors.count]
    }

    private var tagTextColor: Color {
        let colors: [Color] = [
            .blue,
            .purple,
            .green,
            .orange,
            .pink,
            .teal,
            .indigo,
            .mint,
        ]
        return colors[colorIndex % colors.count]
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "tag.fill")
                .font(.system(size: 10))
            Text(tag)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(tagTextColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(tagBackgroundColor)
        )
    }
}

// MARK: - Flow Layout (wrapping horizontal layout)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = flowLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = flowLayout(proposal: proposal, subviews: subviews)
        for (index, placement) in result.placements.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + placement.x, y: bounds.minY + placement.y),
                proposal: ProposedViewSize(placement.size)
            )
        }
    }

    private struct Placement {
        let x: CGFloat
        let y: CGFloat
        let size: CGSize
    }

    private struct FlowResult {
        let size: CGSize
        let placements: [Placement]
    }

    private func flowLayout(proposal: ProposedViewSize, subviews: Subviews) -> FlowResult {
        let maxWidth = proposal.width ?? .infinity
        var placements: [Placement] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            // Check if we need to wrap to next line
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            placements.append(Placement(x: currentX, y: currentY, size: size))

            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, currentX + size.width)
            currentX += size.width + spacing
        }

        totalHeight = currentY + rowHeight

        return FlowResult(
            size: CGSize(width: totalWidth, height: totalHeight),
            placements: placements
        )
    }
}
