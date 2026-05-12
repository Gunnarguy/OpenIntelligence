//
//  PipelineTraceExporter.swift
//  OpenIntelligence
//
//  Builds a comprehensive pipeline trace from a ChatMessage and exports it as a
//  shareable text file. Captures: query, response, metadata, retrieved chunks,
//  reasoning trace, thinking events, and timing — everything needed for debugging
//  without copy-pasting from the Xcode console.
//

import Foundation

enum PipelineTraceExporter {

    /// Build a complete pipeline trace string from a ChatMessage and optional thinking events.
    /// The output is a human-readable text file with all debugging information.
    static func buildTrace(
        message: ChatMessage,
        userQuery: String? = nil,
        thinkingEvents: [ThinkingEvent] = [],
        pipelineTrace: [String] = []
    ) -> String {
        var lines: [String] = []
        let divider = String(repeating: "═", count: 72)
        let thinDivider = String(repeating: "─", count: 72)
        let exportedThinkingEvents = thinkingEvents.isEmpty ? (message.thinkingEvents ?? []) : thinkingEvents
        let exportedPipelineTrace = pipelineTrace.isEmpty ? (message.pipelineTrace ?? []) : pipelineTrace

        // Header
        lines.append(divider)
        lines.append("  OPENINTELLIGENCE PIPELINE TRACE")
        lines.append("  Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("  Message ID: \(message.id.uuidString)")
        if let containerId = message.containerId {
            lines.append("  Container: \(containerId.uuidString)")
        }
        lines.append(divider)

        // Query
        lines.append("")
        lines.append("▶ QUERY")
        lines.append(thinDivider)
        if let q = userQuery ?? message.traceQuery ?? message.metadata?.originalQuery {
            lines.append(q)
        } else {
            lines.append("(not captured)")
        }

        // Response
        lines.append("")
        lines.append("▶ RESPONSE (\(message.content.count) chars)")
        lines.append(thinDivider)
        lines.append(message.content)

        // Metadata
        if let meta = message.metadata {
            lines.append("")
            lines.append("▶ METADATA")
            lines.append(thinDivider)
            lines.append("  Model:            \(meta.modelUsed)")
            lines.append("  Quality Mode:     \(meta.qualityModeName ?? "Standard")")
            lines.append("  Agentic:          \(meta.usedAgenticMode ? "YES" : "NO")")
            lines.append("  Retrieval Config: \(meta.retrievalConfigSummary)")
            lines.append("  Retrieval Time:   \(String(format: "%.0fms", meta.retrievalTime * 1000))")
            lines.append("  Total Gen Time:   \(String(format: "%.1fs", meta.totalGenerationTime))")
            if let ttft = meta.timeToFirstToken {
                lines.append("  TTFT:             \(String(format: "%.0fms", ttft * 1000))")
            }
            lines.append("  Tokens Generated: \(meta.tokensGenerated)")
            if let tps = meta.tokensPerSecond {
                lines.append("  Tokens/sec:       \(String(format: "%.1f", tps))")
            }
            if let gating = meta.gatingDecision {
                lines.append("  Gating:           \(gating)")
            }
            if let tools = meta.toolCallsMade, tools > 0 {
                lines.append("  Tool Calls:       \(tools)")
            }
            if let embedding = meta.embeddingProvider {
                lines.append("  Embedding:        \(embedding)")
            }
        }

        // Thinking Events (real-time pipeline steps)
        let formattedThinkingLines: [String]
        if !exportedThinkingEvents.isEmpty {
            lines.append("")
            lines.append("▶ THINKING EVENTS (\(exportedThinkingEvents.count) events)")
            lines.append(thinDivider)
            let sorted = exportedThinkingEvents.sorted { $0.timestamp < $1.timestamp }
            let baseTime = sorted.first?.timestamp ?? Date()
            formattedThinkingLines = sorted.map { event in
                let elapsed = event.timestamp.timeIntervalSince(baseTime)
                let time = String(format: "+%06.0fms", elapsed * 1000)
                let detail = event.detail.map { " │ \($0)" } ?? ""
                return "  \(time) [\(event.kind.displayName)] \(event.title)\(detail)"
            }
            for line in formattedThinkingLines {
                lines.append(line)
            }
        } else {
            formattedThinkingLines = []
        }

        // Pipeline Trace (captured log lines)
        if !exportedPipelineTrace.isEmpty && exportedPipelineTrace != formattedThinkingLines.map({ String($0.dropFirst(2)) }) {
            lines.append("")
            lines.append("▶ PIPELINE LOG (\(exportedPipelineTrace.count) entries)")
            lines.append(thinDivider)
            for entry in exportedPipelineTrace {
                lines.append("  \(entry)")
            }
        }

        // Reasoning Trace (agentic session chain)
        if let trace = message.metadata?.reasoningTrace, !trace.isEmpty {
            lines.append("")
            lines.append("▶ REASONING TRACE (\(trace.count) sessions)")
            lines.append(thinDivider)
            for (i, step) in trace.enumerated() {
                lines.append("  Session \(i + 1): \(step)")
            }
        }

        // Retrieved Chunks
        if let chunks = message.retrievedChunks, !chunks.isEmpty {
            lines.append("")
            lines.append("▶ RETRIEVED CHUNKS (\(chunks.count) chunks)")
            lines.append(thinDivider)
            for (i, chunk) in chunks.enumerated() {
                lines.append("")
                lines.append("  ── Chunk \(i + 1) ──")
                lines.append("  Source:     \(chunk.sourceDocument)")
                lines.append("  Rank:       \(chunk.rank)")
                lines.append("  Similarity: \(String(format: "%.4f", chunk.similarityScore))")
                if let page = chunk.pageNumber {
                    lines.append("  Page:       \(page)")
                }
                let sectionTitle = trustedLegacySectionLabel(chunk.chunk.metadata.sectionTitle) ?? ""
                let sectionPath = (trustedLegacySectionPath(chunk.chunk.metadata.sectionPath) ?? []).joined(separator: " > ")
                let structureType = chunk.chunk.metadata.structureType ?? ""
                if !sectionTitle.isEmpty {
                    lines.append("  Section:    \(sectionTitle)")
                }
                if !sectionPath.isEmpty {
                    lines.append("  Path:       \(sectionPath)")
                }
                if !structureType.isEmpty {
                    lines.append("  Structure:  \(structureType)")
                }
                // Show first 300 chars of content
                let preview = String(
                    sanitizedPreviewContent(
                        chunk.chunk.text,
                        cleanedSectionPath: trustedLegacySectionPath(chunk.chunk.metadata.sectionPath)
                    ).prefix(300)
                )
                    .replacingOccurrences(of: "\n", with: " ")
                lines.append("  Content:    \(preview)\(chunk.chunk.text.count > 300 ? "..." : "")")
            }
        }

        // Footer
        lines.append("")
        lines.append(divider)
        lines.append("  END OF TRACE")
        lines.append(divider)
        lines.append("")

        return lines.joined(separator: "\n")
    }

    /// Write trace to a temporary file and return the URL for sharing
    static func exportToFile(
        message: ChatMessage,
        userQuery: String? = nil,
        thinkingEvents: [ThinkingEvent] = [],
        pipelineTrace: [String] = []
    ) -> URL? {
        let trace = buildTrace(
            message: message,
            userQuery: userQuery,
            thinkingEvents: thinkingEvents,
            pipelineTrace: pipelineTrace
        )

        let timestamp = DateFormatter.traceFileFormatter.string(from: message.timestamp)
        let filename = "pipeline_trace_\(timestamp).txt"
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)

        do {
            try trace.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            Log.error("Failed to write pipeline trace: \(error)", category: .pipeline)
            return nil
        }
    }

    private nonisolated static func trustedLegacySectionPath(_ rawPath: [String]?) -> [String]? {
        let cleaned = (rawPath ?? []).compactMap(trustedLegacySectionLabel)
        guard !cleaned.isEmpty else { return nil }

        return cleaned.reduce(into: [String]()) { result, component in
            if result.last?.caseInsensitiveCompare(component) != .orderedSame {
                result.append(component)
            }
        }
    }

    private nonisolated static func trustedLegacySectionLabel(_ raw: String?) -> String? {
        guard let raw else { return nil }

        let normalized = OCRConfiguration.normalizeExtractedText(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        guard !normalized.contains("_"), !normalized.contains("|") else { return nil }

        let scalars = normalized.unicodeScalars
        let letterCount = scalars.filter { CharacterSet.letters.contains($0) }.count
        let alnumCount = scalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        let latinCount = scalars.filter { scalar in
            (0x0041...0x005A).contains(scalar.value) || (0x0061...0x007A).contains(scalar.value)
        }.count
        let cyrillicCount = scalars.filter { scalar in
            (0x0400...0x04FF).contains(scalar.value) || (0x0500...0x052F).contains(scalar.value)
        }.count

        guard letterCount >= 2 else { return nil }
        if scalars.count >= 8, Double(alnumCount) / Double(max(1, scalars.count)) < 0.55 {
            return nil
        }
        if latinCount > 0, cyrillicCount > 0 {
            return nil
        }

        return normalized
    }

    private nonisolated static func sanitizedPreviewContent(_ text: String, cleanedSectionPath: [String]?) -> String {
        let lines = text.components(separatedBy: .newlines)
        guard let firstLine = lines.first else { return text }
        guard firstLine.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Section Path:") else { return text }

        var updatedLines = lines
        if let cleanedSectionPath, !cleanedSectionPath.isEmpty {
            updatedLines[0] = "Section Path: \(cleanedSectionPath.joined(separator: " > "))"
        } else {
            updatedLines.removeFirst()
            while updatedLines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                updatedLines.removeFirst()
            }
        }

        return updatedLines.joined(separator: "\n")
    }
}

// MARK: - Date Formatter

private extension DateFormatter {
    static let traceFileFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f
    }()
}
