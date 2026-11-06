//
//  DocumentPreviewSheet.swift
//  OpenIntelligence
//
//  Moved from DatabaseDashboardView.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import Charts
import SwiftUI

// MARK: - Document Preview Sheet

/// Full preview of a document's FTS5 content and metadata.
///
/// Large documents (947KB+, 28K+ lines) require special handling:
/// - SwiftUI `Text` chokes rendering >100K chars of monospaced text → white canvas
/// - `.filter{}` / `.components(separatedBy:)` on main thread freezes UI
/// Solution: truncate display to 100K chars, pre-compute analysis off main thread,
/// share full content via share sheet.
struct DocumentPreviewSheet: View {
    let documentId: UUID
    let documentName: String
    let characterCount: Int
    let wordCount: Int

    /// Maximum characters to render in the Text view.
    /// 100K chars ≈ 3K lines — plenty for browsing, won't kill SwiftUI layout.
    private static let displayLimit = 100_000

    @State private var fullContent: String = ""
    @State private var fullContentCharacterCount: Int = 0
    @State private var displayContent: String = ""
    @State private var isTruncated = false
    @State private var isLoading = true
    @State private var analysisStats: AnalysisStats?
    @Environment(\.dismiss) private var dismiss

    /// Pre-computed analysis stats (computed off main thread)
    struct AnalysisStats {
        let lines: Int
        let sentences: Int
        let paragraphs: Int
        let uppercaseCount: Int
        let lowercaseCount: Int
        let digitCount: Int
        let whitespaceCount: Int
        let punctuationCount: Int
        let totalChars: Int
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.lg) {
                    // Metadata header
                    VStack(alignment: .leading, spacing: DSSpacing.md) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(Color.accentColor)
                            Text("Document Metadata")
                                .font(.headline)
                            Spacer()
                        }

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.md) {
                            MetadataCard(label: "Document ID", value: documentId.uuidString, isMonospace: true)
                            MetadataCard(label: "Characters", value: characterCount.formatted())
                            MetadataCard(label: "Words", value: wordCount.formatted())
                            MetadataCard(label: "Avg Word Length", value: wordCount > 0 ? String(format: "%.1f", Double(characterCount) / Double(wordCount)) : "—")
                        }
                    }
                    .padding(DSSpacing.lg)
                    .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))

                    // Content preview
                    VStack(alignment: .leading, spacing: DSSpacing.md) {
                        HStack {
                            Image(systemName: "text.alignleft")
                                .foregroundStyle(Color.accentColor)
                            Text("Indexed Content")
                                .font(.headline)
                            Spacer()

                            if !fullContent.isEmpty {
                                ShareLink(item: fullContent) {
                                    Label("Share Full", systemImage: "square.and.arrow.up")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button {
                                    #if canImport(UIKit)
                                    UIPasteboard.general.string = fullContent
                                    #elseif canImport(AppKit)
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(fullContent, forType: .string)
                                    #endif
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }

                        if isLoading {
                            ProgressView("Loading content...")
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(DSSpacing.xxl)
                        } else if displayContent.isEmpty {
                            Text("No content available")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(DSSpacing.lg)
                        } else {
                            if isTruncated {
                                HStack(spacing: DSSpacing.xs) {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundStyle(.orange)
                                    Text("Showing first \(Self.displayLimit.formatted()) of \(fullContentCharacterCount.formatted()) characters. Use Share to export full content.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, DSSpacing.sm)
                                .padding(.vertical, DSSpacing.xs)
                                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
                            }

                            Text(displayContent)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(DSSpacing.lg)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(DSColors.background, in: RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                        }
                    }
                    .padding(DSSpacing.lg)
                    .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))

                    // Analysis — uses pre-computed stats (NOT computed in view body)
                    if let stats = analysisStats {
                        VStack(alignment: .leading, spacing: DSSpacing.md) {
                            HStack {
                                Image(systemName: "chart.bar.fill")
                                    .foregroundStyle(Color.accentColor)
                                Text("Quick Analysis")
                                    .font(.headline)
                                Spacer()
                            }

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.md) {
                                AnalysisCard(label: "Lines", value: "\(stats.lines)", icon: "list.number", color: .accentColor)
                                AnalysisCard(label: "Sentences", value: "\(max(1, stats.sentences))", icon: "text.quote", color: .accentColor)
                                AnalysisCard(label: "Paragraphs", value: "\(stats.paragraphs)", icon: "text.alignleft", color: .accentColor)
                            }

                            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                                Text("Character Breakdown")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                CharacterBreakdownRow(label: "Uppercase", count: stats.uppercaseCount, total: stats.totalChars, color: .accentColor)
                                CharacterBreakdownRow(label: "Lowercase", count: stats.lowercaseCount, total: stats.totalChars, color: .accentColor)
                                CharacterBreakdownRow(label: "Digits", count: stats.digitCount, total: stats.totalChars, color: .accentColor)
                                CharacterBreakdownRow(label: "Whitespace", count: stats.whitespaceCount, total: stats.totalChars, color: .secondary)
                                CharacterBreakdownRow(label: "Punctuation", count: stats.punctuationCount, total: stats.totalChars, color: .accentColor)
                            }
                        }
                        .padding(DSSpacing.lg)
                        .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
                    }
                }
                .padding(DSSpacing.lg)
            }
            .background(DSColors.background.ignoresSafeArea())
            .navigationTitle(documentName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
                #else
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                #endif
            }
        }
        .task {
            isLoading = true
            let docId = documentId
            // Read content off the actor (bypasses serial queue contention) and compute count off main thread
            let (loaded, count) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
                let content = SQLiteFullTextService.readContentDirectly(documentId: docId) ?? ""
                return (content, content.count)
            }.value

            fullContent = loaded
            fullContentCharacterCount = count

            // Truncate for display — SwiftUI Text chokes on >100K monospaced chars
            if count > Self.displayLimit {
                displayContent = String(loaded.prefix(Self.displayLimit))
                isTruncated = true
            } else {
                displayContent = loaded
                isTruncated = false
            }

            isLoading = false

            // Compute analysis stats off main thread AFTER content is visible
            if count > 0 {
                let text = loaded
                let stats = await Task.detached(priority: .utility) {
                    let lines = text.components(separatedBy: .newlines).count
                    let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?")).count - 1
                    let paragraphs = text.components(separatedBy: "\n\n").count
                    var upper = 0, lower = 0, digits = 0, whitespace = 0, punctuation = 0
                    for char in text {
                        if char.isUppercase { upper += 1 }
                        else if char.isLowercase { lower += 1 }
                        if char.isNumber { digits += 1 }
                        if char.isWhitespace { whitespace += 1 }
                        if char.isPunctuation { punctuation += 1 }
                    }
                    return AnalysisStats(
                        lines: lines, sentences: sentences, paragraphs: paragraphs,
                        uppercaseCount: upper, lowercaseCount: lower, digitCount: digits,
                        whitespaceCount: whitespace, punctuationCount: punctuation,
                        totalChars: count
                    )
                }.value
                analysisStats = stats
            }
        }
    }
}

/// Card showing metadata
private struct MetadataCard: View {
    let label: String
    let value: String
    var isMonospace: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(isMonospace ? .system(.caption2, design: .monospaced) : .caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .background(DSColors.background, in: RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
    }
}

/// Card for analysis metrics
private struct AnalysisCard: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: DSSpacing.xs) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.caption)
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
    }
}

/// Row showing character breakdown with progress bar
private struct CharacterBreakdownRow: View {
    let label: String
    let count: Int
    let total: Int
    let color: Color

    var percentage: Double {
        total > 0 ? Double(count) / Double(total) : 0
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .frame(width: 80, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(percentage), height: 8)
                }
            }
            .frame(height: 8)

            Text("\(count)")
                .font(.caption.monospacedDigit())
                .frame(width: 50, alignment: .trailing)

            Text(String(format: "%.1f%%", percentage * 100))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 45, alignment: .trailing)
        }
    }
}
