//
//  AnswerIntelligenceView.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 2025.
//
//  Displays explainability information showing WHY an answer is accurate.
//  Shows verification gates, citation checks, confidence breakdown, and reasoning sessions.
//

import SwiftUI

// MARK: - Answer Intelligence Model

/// Represents the intelligence/explainability data for an answer
struct AnswerIntelligence: Identifiable, Sendable {
    let id: UUID
    let generatedAt: Date

    // Verification Gates (from VerificationGateService)
    let gatesPassed: Int
    let gatesTotalCount: Int
    let gateDetails: [GateDetail]

    // Citation Verification
    let citationCount: Int
    let verifiedCitations: Int
    let sourcesUsed: [SourceInfo]

    // Confidence Breakdown
    let overallConfidence: Double
    let retrievalConfidence: Double
    let evidenceCoverage: Double
    let semanticRelevance: Double

    // Reasoning Sessions (if agentic)
    let reasoningSessionCount: Int
    let reasoningMode: String  // "Standard", "Deep Think", "Maximum"
    let factBankEntries: Int

    // Context Usage
    let contextCharsUsed: Int
    let contextCharsMax: Int
    let chunksRetrieved: Int
    let uniqueDocuments: Int

    /// Individual gate detail for display
    struct GateDetail: Identifiable, Sendable {
        let id: UUID
        let name: String
        let passed: Bool
        let confidence: Double
        let description: String
        let icon: String
    }

    /// Source document info
    struct SourceInfo: Identifiable, Sendable {
        let id: UUID
        let documentName: String
        let relevanceScore: Double
        let chunkCount: Int
    }

    // MARK: - Computed Properties

    var allGatesPassed: Bool {
        gatesPassed == gatesTotalCount
    }

    var confidenceLevel: ConfidenceLevel {
        switch overallConfidence {
        case 0.85...1.0: return .high
        case 0.65..<0.85: return .medium
        case 0.40..<0.65: return .low
        default: return .veryLow
        }
    }

    var citationVerificationRate: Double {
        guard citationCount > 0 else { return 1.0 }
        return Double(verifiedCitations) / Double(citationCount)
    }

    var contextUtilization: Double {
        guard contextCharsMax > 0 else { return 0 }
        return Double(contextCharsUsed) / Double(contextCharsMax)
    }

    enum ConfidenceLevel: String {
        case high = "High"
        case medium = "Medium"
        case low = "Low"
        case veryLow = "Very Low"

        var color: Color {
            switch self {
            case .high: return .green
            case .medium: return .yellow
            case .low: return .orange
            case .veryLow: return .red
            }
        }

        var icon: String {
            switch self {
            case .high: return "checkmark.shield.fill"
            case .medium: return "checkmark.shield"
            case .low: return "exclamationmark.shield"
            case .veryLow: return "xmark.shield"
            }
        }
    }
}

// MARK: - Answer Intelligence View

/// Expandable panel showing why an answer is trustworthy
struct AnswerIntelligenceView: View {
    let intelligence: AnswerIntelligence
    @State private var isExpanded: Bool = false
    @State private var selectedSection: Section = .overview

    enum Section: String, CaseIterable {
        case overview = "Overview"
        case gates = "Verification"
        case sources = "Sources"
        case reasoning = "Reasoning"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsed header - always visible
            headerButton

            // Expanded content
            if isExpanded {
                expandedContent
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
    }

    // MARK: - Header

    private var headerButton: some View {
        Button {
            withAnimation {
                isExpanded.toggle()
                if isExpanded {
                    DSHaptics.expand()
                } else {
                    DSHaptics.collapse()
                }
            }
        } label: {
            HStack(spacing: DSSpacing.sm) {
                // Confidence indicator
                Image(systemName: intelligence.confidenceLevel.icon)
                    .foregroundStyle(intelligence.confidenceLevel.color)
                    .font(.system(size: 18, weight: .semibold))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Answer Intelligence")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.secondaryText)

                    HStack(spacing: DSSpacing.xs) {
                        Text("\(intelligence.confidenceLevel.rawValue) Confidence")
                            .font(DSTypography.body.weight(.medium))
                            .foregroundStyle(intelligence.confidenceLevel.color)

                        Text("•")
                            .foregroundStyle(DSColors.secondaryText)

                        Text("\(intelligence.gatesPassed)/\(intelligence.gatesTotalCount) Checks")
                            .font(DSTypography.body)
                            .foregroundStyle(intelligence.allGatesPassed ? DSColors.secondaryText : .orange)
                    }
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundStyle(DSColors.secondaryText)
                    .font(.system(size: 14, weight: .medium))
            }
            .padding(DSSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var borderColor: Color {
        if intelligence.allGatesPassed {
            return intelligence.confidenceLevel.color.opacity(0.3)
        } else {
            return Color.orange.opacity(0.3)
        }
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()

            // Section picker
            sectionPicker
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)

            Divider()

            // Section content
            Group {
                switch selectedSection {
                case .overview:
                    overviewSection
                case .gates:
                    gatesSection
                case .sources:
                    sourcesSection
                case .reasoning:
                    reasoningSection
                }
            }
            .padding(DSSpacing.md)
        }
    }

    private var sectionPicker: some View {
        HStack(spacing: DSSpacing.xs) {
            ForEach(Section.allCases, id: \.self) { section in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedSection = section
                    }
                } label: {
                    Text(section.rawValue)
                        .font(DSTypography.caption)
                        .foregroundStyle(selectedSection == section ? DSColors.accent : DSColors.secondaryText)
                        .padding(.horizontal, DSSpacing.sm)
                        .padding(.vertical, DSSpacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous)
                                .fill(selectedSection == section ? DSColors.accent.opacity(0.15) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Overview Section

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            // Source Fidelity Status Card
            SourceFidelityStatus(
                fidelityScore: Float(intelligence.overallConfidence),
                shouldAbstain: !intelligence.allGatesPassed && intelligence.gatesPassed == 0
            )

            // Confidence bar
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                HStack {
                    Text("Overall Confidence")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.secondaryText)
                    Spacer()
                    Text("\(Int(intelligence.overallConfidence * 100))%")
                        .font(DSTypography.body.weight(.medium))
                        .foregroundStyle(intelligence.confidenceLevel.color)
                }

                ProgressView(value: intelligence.overallConfidence)
                    .tint(intelligence.confidenceLevel.color)
            }

            // Key metrics grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: DSSpacing.sm) {
                metricCard(
                    icon: "checkmark.shield",
                    title: "Verification Gates",
                    value: "\(intelligence.gatesPassed)/\(intelligence.gatesTotalCount)",
                    color: intelligence.allGatesPassed ? .green : .orange
                )

                metricCard(
                    icon: "quote.bubble",
                    title: "Citations Verified",
                    value: "\(intelligence.verifiedCitations)/\(intelligence.citationCount)",
                    color: intelligence.citationVerificationRate >= 0.8 ? .green : .orange
                )

                metricCard(
                    icon: "doc.text",
                    title: "Sources Used",
                    value: "\(intelligence.uniqueDocuments) docs",
                    color: .blue
                )

                metricCard(
                    icon: "brain",
                    title: "Reasoning Depth",
                    value: intelligence.reasoningMode,
                    color: .purple
                )
            }
        }
    }

    private func metricCard(icon: String, title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 12))
                Text(title)
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.secondaryText)
            }
            Text(value)
                .font(DSTypography.body.weight(.medium))
                .foregroundStyle(DSColors.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous)
                .fill(DSColors.surface)
        )
    }

    // MARK: - Gates Section

    private var gatesSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("Verification gates ensure the answer is grounded in your documents.")
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.secondaryText)
                .padding(.bottom, DSSpacing.xs)

            ForEach(intelligence.gateDetails) { gate in
                gateRow(gate)
            }
        }
    }

    private func gateRow(_ gate: AnswerIntelligence.GateDetail) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: gate.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(gate.passed ? .green : .red)
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(gate.name)
                        .font(DSTypography.body.weight(.medium))
                        .foregroundStyle(DSColors.primaryText)

                    Spacer()

                    Text("\(Int(gate.confidence * 100))%")
                        .font(DSTypography.caption)
                        .foregroundStyle(gate.passed ? DSColors.secondaryText : .red)
                }

                Text(gate.description)
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.secondaryText)
                    .lineLimit(2)
            }
        }
        .padding(DSSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous)
                .fill(gate.passed ? DSColors.surface : Color.red.opacity(0.05))
        )
    }

    // MARK: - Sources Section

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            // Context utilization
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                HStack {
                    Text("Context Utilization")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.secondaryText)
                    Spacer()
                    Text("\(intelligence.contextCharsUsed.formatted()) / \(intelligence.contextCharsMax.formatted()) chars")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.secondaryText)
                }
                ProgressView(value: intelligence.contextUtilization)
                    .tint(.blue)
            }
            .padding(.bottom, DSSpacing.xs)

            Text("\(intelligence.chunksRetrieved) chunks from \(intelligence.uniqueDocuments) documents")
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.secondaryText)

            // Source list
            ForEach(intelligence.sourcesUsed) { source in
                sourceRow(source)
            }
        }
    }

    private func sourceRow(_ source: AnswerIntelligence.SourceInfo) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: "doc.text.fill")
                .foregroundStyle(.blue)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 2) {
                Text(source.documentName)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.primaryText)
                    .lineLimit(1)

                HStack(spacing: DSSpacing.sm) {
                    Text("\(source.chunkCount) chunks")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.secondaryText)

                    Text("•")
                        .foregroundStyle(DSColors.secondaryText)

                    Text("Relevance: \(Int(source.relevanceScore * 100))%")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.secondaryText)
                }
            }

            Spacer()
        }
        .padding(DSSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous)
                .fill(DSColors.surface)
        )
    }

    // MARK: - Reasoning Section

    private var reasoningSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            // Reasoning mode indicator
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: reasoningModeIcon)
                    .foregroundStyle(reasoningModeColor)
                    .font(.system(size: 18))

                VStack(alignment: .leading, spacing: 2) {
                    Text(intelligence.reasoningMode)
                        .font(DSTypography.body.weight(.medium))
                        .foregroundStyle(DSColors.primaryText)

                    Text(reasoningModeDescription)
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.secondaryText)
                }
            }
            .padding(DSSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous)
                    .fill(reasoningModeColor.opacity(0.1))
            )

            // Session stats
            if intelligence.reasoningSessionCount > 1 {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text("Multi-Session Synthesis")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.secondaryText)

                    HStack(spacing: DSSpacing.lg) {
                        VStack(alignment: .leading) {
                            Text("\(intelligence.reasoningSessionCount)")
                                .font(DSTypography.title)
                                .foregroundStyle(DSColors.primaryText)
                            Text("Sessions")
                                .font(DSTypography.caption)
                                .foregroundStyle(DSColors.secondaryText)
                        }

                        VStack(alignment: .leading) {
                            Text("\(intelligence.factBankEntries)")
                                .font(DSTypography.title)
                                .foregroundStyle(DSColors.primaryText)
                            Text("Facts Collected")
                                .font(DSTypography.caption)
                                .foregroundStyle(DSColors.secondaryText)
                        }
                    }
                }
            }

            // Explanation
            Text("OpenIntelligence synthesizes information across multiple reasoning sessions, collecting verified facts and cross-referencing sources to minimize hallucination.")
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.secondaryText)
                .padding(.top, DSSpacing.xs)
        }
    }

    private var reasoningModeIcon: String {
        switch intelligence.reasoningMode {
        case "Deep Think": return "brain.head.profile"
        case "Maximum": return "sparkles"
        default: return "brain"
        }
    }

    private var reasoningModeColor: Color {
        switch intelligence.reasoningMode {
        case "Deep Think": return .orange
        case "Maximum": return .purple
        default: return .blue
        }
    }

    private var reasoningModeDescription: String {
        switch intelligence.reasoningMode {
        case "Deep Think":
            return "\(intelligence.reasoningSessionCount) reasoning sessions with iterative verification"
        case "Maximum":
            return "\(intelligence.reasoningSessionCount) parallel chains with cluster synthesis"
        default:
            return "Standard single-pass reasoning"
        }
    }
}

// MARK: - Compact Badge Version

/// A compact badge that shows confidence at a glance
struct AnswerIntelligenceBadge: View {
    let intelligence: AnswerIntelligence
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: intelligence.confidenceLevel.icon)
                    .font(.system(size: 10))

                Text("\(Int(intelligence.overallConfidence * 100))%")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(intelligence.confidenceLevel.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(intelligence.confidenceLevel.color.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Factory

extension AnswerIntelligence {
    /// Create from RAG audit data and verification results
    static func from(
        verificationResult: RAGVerificationResult,
        auditSnapshot: RAGAuditSnapshot,
        retrievedChunks: [RetrievedChunk]
    ) -> AnswerIntelligence {
        // Convert gate results
        let gateDetails = verificationResult.gateResults.map { result in
            GateDetail(
                id: UUID(),
                name: gateName(for: result.gate),
                passed: result.passed,
                confidence: Double(result.confidence),
                description: result.details,
                icon: gateIcon(for: result.gate)
            )
        }

        // Build source info from chunks
        var sourcesByDoc: [String: (relevance: Double, count: Int)] = [:]
        for chunk in retrievedChunks {
            let docName = chunk.sourceDocument.isEmpty ? "Unknown" : chunk.sourceDocument
            let existing = sourcesByDoc[docName] ?? (relevance: 0, count: 0)
            sourcesByDoc[docName] = (
                relevance: max(existing.relevance, Double(chunk.similarityScore)),
                count: existing.count + 1
            )
        }

        let sources = sourcesByDoc.map { name, data in
            SourceInfo(
                id: UUID(),
                documentName: name,
                relevanceScore: data.relevance,
                chunkCount: data.count
            )
        }.sorted { $0.relevanceScore > $1.relevanceScore }

        // Determine reasoning mode
        let reasoningMode: String
        let sessionCount: Int
        if auditSnapshot.isRecursiveRAG {
            if auditSnapshot.llmCallCount >= 8 {
                reasoningMode = "Maximum"
                sessionCount = auditSnapshot.llmCallCount
            } else if auditSnapshot.llmCallCount >= 4 {
                reasoningMode = "Deep Think"
                sessionCount = auditSnapshot.llmCallCount
            } else {
                reasoningMode = "Standard"
                sessionCount = auditSnapshot.llmCallCount
            }
        } else {
            reasoningMode = "Standard"
            sessionCount = 1
        }

        return AnswerIntelligence(
            id: UUID(),
            generatedAt: Date(),
            gatesPassed: verificationResult.gateResults.filter { $0.passed }.count,
            gatesTotalCount: verificationResult.gateResults.count,
            gateDetails: gateDetails,
            citationCount: retrievedChunks.count,  // Approximate
            verifiedCitations: retrievedChunks.filter { $0.similarityScore >= 0.4 }.count,
            sourcesUsed: sources,
            overallConfidence: Double(verificationResult.overallConfidence),
            retrievalConfidence: Double(auditSnapshot.topSim),
            evidenceCoverage: verificationResult.gateResults
                .first { $0.gate == .evidenceCoverage }
                .map { Double($0.confidence) } ?? 0.5,
            semanticRelevance: Double(auditSnapshot.avgTop5),
            reasoningSessionCount: sessionCount,
            reasoningMode: reasoningMode,
            factBankEntries: auditSnapshot.isRecursiveRAG ? auditSnapshot.llmCallCount * 3 : 0,  // Estimate
            contextCharsUsed: auditSnapshot.contextChars,
            contextCharsMax: auditSnapshot.maxContextChars,
            chunksRetrieved: auditSnapshot.mmrSelectedCount,
            uniqueDocuments: auditSnapshot.uniqueDocCount
        )
    }

    private static func gateName(for gate: VerificationGate) -> String {
        switch gate {
        case .retrievalConfidence: return "Retrieval Confidence"
        case .evidenceCoverage: return "Evidence Coverage"
        case .numericSanity: return "Numeric Accuracy"
        case .contradictionSweep: return "Contradiction Check"
        case .semanticGrounding: return "Semantic Grounding"
        case .quoteFaithfulness: return "Quote Faithfulness"
        case .generationQuality: return "Generation Quality"
        case .answerCompleteness: return "Answer Completeness"
        case .domainIsolation: return "Domain Isolation"
        }
    }

    private static func gateIcon(for gate: VerificationGate) -> String {
        switch gate {
        case .retrievalConfidence: return "magnifyingglass"
        case .evidenceCoverage: return "text.quote"
        case .numericSanity: return "number"
        case .contradictionSweep: return "arrow.triangle.branch"
        case .semanticGrounding: return "brain.head.profile"
        case .quoteFaithfulness: return "quote.bubble"
        case .generationQuality: return "waveform.path.ecg"
        case .answerCompleteness: return "checklist"
        case .domainIsolation: return "square.3.layers.3d.slash"
        }
    }
}

// MARK: - Preview

#Preview {
    let mockIntelligence = AnswerIntelligence(
        id: UUID(),
        generatedAt: Date(),
        gatesPassed: 3,
        gatesTotalCount: 4,
        gateDetails: [
            .init(id: UUID(), name: "Retrieval Confidence", passed: true, confidence: 0.85, description: "Top result score exceeds threshold", icon: "magnifyingglass"),
            .init(id: UUID(), name: "Evidence Coverage", passed: true, confidence: 0.92, description: "All claims cite evidence", icon: "text.quote"),
            .init(id: UUID(), name: "Numeric Accuracy", passed: false, confidence: 0.65, description: "1 number could not be verified", icon: "number"),
            .init(id: UUID(), name: "Contradiction Check", passed: true, confidence: 1.0, description: "No contradictions detected", icon: "arrow.triangle.branch")
        ],
        citationCount: 5,
        verifiedCitations: 4,
        sourcesUsed: [
            .init(id: UUID(), documentName: "Aurora_EV7_Owners_Manual.md", relevanceScore: 0.89, chunkCount: 3),
            .init(id: UUID(), documentName: "Technical_Specifications.pdf", relevanceScore: 0.72, chunkCount: 2)
        ],
        overallConfidence: 0.82,
        retrievalConfidence: 0.89,
        evidenceCoverage: 0.92,
        semanticRelevance: 0.85,
        reasoningSessionCount: 4,
        reasoningMode: "Deep Think",
        factBankEntries: 12,
        contextCharsUsed: 4200,
        contextCharsMax: 5500,
        chunksRetrieved: 8,
        uniqueDocuments: 2
    )

    return VStack {
        AnswerIntelligenceView(intelligence: mockIntelligence)
            .padding()

        AnswerIntelligenceBadge(intelligence: mockIntelligence) {
            print("Tapped")
        }
        .padding()
    }
    .background(DSColors.background)
}
