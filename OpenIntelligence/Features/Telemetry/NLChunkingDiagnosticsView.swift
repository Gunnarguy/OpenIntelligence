//
//  NLChunkingDiagnosticsView.swift
//  OpenIntelligence
//
//  Shows NaturalLanguage-based chunking diagnostics emitted by SemanticChunker
//

import SwiftUI
import NaturalLanguage

struct NLChunkingDiagnosticsView: View {
    @State private var diagnostics: SemanticChunker.ChunkingDiagnostics?
    @State private var lastUpdated: Date?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [DSColors.background, DSColors.surface.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    SurfaceCard {
                        SectionHeader(icon: "text.magnifyingglass", title: "NL Chunking Diagnostics")

                        if let d = diagnostics {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    LabeledContent("Dominant Language", value: languageString(d.language))
                                    Spacer()
                                    if let lastUpdated {
                                        Text("Updated \(relativeDate(lastUpdated))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                if !d.languageHypotheses.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Language Hypotheses")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        ForEach(sortedHypotheses(d.languageHypotheses), id: \.0) { lang, prob in
                                            HStack {
                                                Text(languageCodeToName(lang.rawValue))
                                                Spacer()
                                                Text(String(format: "%.1f%%", prob * 100))
                                                    .foregroundColor(.secondary)
                                            }
                                            .font(.footnote)
                                        }
                                    }
                                }

                                Divider().padding(.vertical, 4)

                                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                                    GridRow {
                                        metric("Sections", value: "\(d.sectionCount)")
                                        metric("Topic Boundaries", value: "\(d.topicBoundaryCount)")
                                        metric("Total Sentences", value: "\(d.totalSentences)")
                                    }
                                    GridRow {
                                        metric("Avg Sentence Length", value: String(format: "%.1f words", d.averageSentenceLengthWords))
                                        metric("Avg Words/Chunk", value: String(format: "%.1f", d.averageWordsPerChunk))
                                        metric("Overlap", value: "\(d.overlapWords) words")
                                    }
                                }

                                if !d.warnings.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Label("Warnings", systemImage: "exclamationmark.triangle.fill")
                                            .foregroundColor(.yellow)
                                        ForEach(d.warnings, id: \.self) { w in
                                            Text("• \(w)")
                                                .font(.footnote)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }

                                SectionFooter("Stats reflect the most recent document processed by the SemanticChunker. Trigger ingestion or re-index to refresh.")
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("No diagnostics yet")
                                    .font(.headline)
                                Text("""
                                     Waiting for SemanticChunker to emit diagnostics. To populate:
                                     1) Add or re-index a document in Document Library
                                     2) Chunking runs during ingestion
                                     3) This view updates automatically
                                     """)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                HStack(spacing: 8) {
                                    ProgressView().scaleEffect(0.8)
                                    Text("Listening for diagnostics...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                SectionFooter("The chunker posts Notification.Name.semanticChunkerDiagnosticsUpdated when diagnostics are available.")
                            }
                        }
                    }

                    SurfaceCard {
                        SectionHeader(icon: "info.circle", title: "About")
                        Text("""
                             • Language is detected using NLLanguageRecognizer
                             • Keywords use lemma/POS-filtered counts (nouns/verbs/adjectives)
                             • Overlap indicates words re-used at chunk boundaries
                             • Average sentence length can guide targetSize tuning
                             """)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("NL Diagnostics")
        .onReceive(NotificationCenter.default.publisher(for: .semanticChunkerDiagnosticsUpdated)) { note in
            if let obj = note.object as? SemanticChunker.ChunkingDiagnostics {
                diagnostics = obj
                lastUpdated = Date()
                TelemetryCenter.emit(
                    .system,
                    title: "NL Diagnostics Updated",
                    metadata: [
                        "lang": languageString(obj.language),
                        "sections": "\(obj.sectionCount)",
                        "boundaries": "\(obj.topicBoundaryCount)"
                    ]
                )
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
        }
    }

    private func languageString(_ lang: NLLanguage?) -> String {
        guard let lang else { return "Unknown" }
        return languageCodeToName(lang.rawValue)
    }

    private func sortedHypotheses(_ dict: [NLLanguage: Double]) -> [(NLLanguage, Double)] {
        dict.sorted { $0.value > $1.value }
    }

    private func languageCodeToName(_ code: String) -> String {
        let locale = Locale.current
        return locale.localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    private func relativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    NavigationView {
        NLChunkingDiagnosticsView()
    }
    #if os(iOS)
    .navigationViewStyle(.stack)
    #endif
}
