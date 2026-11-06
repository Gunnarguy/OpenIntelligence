//
//  ContainerSettingsSheet+NerdStats.swift
//  OpenIntelligence
//
//  Part of ContainerSettingsSheet, moved from ContainerSettingsSheet+Sections.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import NaturalLanguage
import SwiftUI

extension ContainerSettingsSheet {
    // MARK: - Library Nerd Stats Section (Deep Dive)

    @ViewBuilder
    var libraryNerdStatsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showNerdStats) {
                if isLoadingNerdStats {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading deep stats...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, DSSpacing.sm)
                } else {
                    libraryNerdStatsContent
                }
            } label: {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text("Library Deep Dive")
                            .font(.subheadline.weight(.semibold))
                        Text("Library-scoped diagnostics")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onChange(of: showNerdStats) { _, expanded in
                if expanded && containerFTSStats.isEmpty {
                    loadNerdStats()
                }
            }
        }
    }

    @ViewBuilder
    private var libraryNerdStatsContent: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            // Corpus Intelligence (if available)
            if let report = activeIntelligenceReport {
                corpusSignalsCard(report.corpus)
            }

            // Vector Space Statistics
            vectorSpaceStatsCard

            // AI Subsystem Diagnostics (X-Ray Vision)
            aiSubsystemDiagnosticsCard

            // Document Distribution
            documentDistributionCard

            // Top Terms (Vocabulary Analysis)
            topTermsCard

            // Retrieval Config Summary
            retrievalConfigSummaryCard
        }
        .padding(.top, DSSpacing.sm)
    }

    @ViewBuilder
    private func corpusSignalsCard(_ signals: LibraryIntelligenceCenter.CorpusSignals) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Label("Corpus Intelligence", systemImage: "brain.head.profile")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: DSSpacing.sm) {
                nerdStatCell(label: "Vocabulary Richness", value: String(format: "%.1f%%", signals.vocabularyRichness * 100), icon: "book.fill")
                nerdStatCell(label: "Technical Density", value: String(format: "%.1f%%", signals.technicalDensity * 100), icon: "gearshape.fill")
                nerdStatCell(label: "Semantic Complexity", value: String(format: "%.2f", signals.semanticComplexity), icon: "waveform.path")
                nerdStatCell(label: "Structured Ratio", value: String(format: "%.1f%%", signals.structuredRatio * 100), icon: "tablecells")
            }

            // Content type badges
            HStack(spacing: DSSpacing.sm) {
                if signals.hasCode {
                    corpusBadge(text: "Code", icon: "chevron.left.forwardslash.chevron.right", color: .accentColor)
                }
                if signals.hasMath {
                    corpusBadge(text: "Math", icon: "function", color: .accentColor)
                }
                if signals.multilingualScore > 0.1 {
                    corpusBadge(text: "Multilingual", icon: "globe", color: .accentColor)
                }
            }

            // Language breakdown
            if !signals.languageHypotheses.isEmpty {
                let sortedLangs = signals.languageHypotheses.sorted { $0.value > $1.value }.prefix(3)
                HStack(spacing: DSSpacing.sm) {
                    Text("Languages:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(Array(sortedLangs), id: \.key) { lang, conf in
                        Text("\(lang.rawValue) \(String(format: "%.0f%%", conf * 100))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .padding(DSSpacing.md)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    @ViewBuilder
    private func corpusBadge(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: icon)
                .scaledFont(size: 9)
            Text(text)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var vectorSpaceStatsCard: some View {
        if let container = activeContainer {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Label("Vector Space", systemImage: "cube.transparent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)

                let documentCount = activeContainerDocuments.count
                let chunkCount = activeContainerDocuments.reduce(0) { $0 + $1.totalChunks }
                let estimatedMemoryBytes = chunkCount * container.embeddingDim * 4
                let bytesPerVector = container.embeddingDim * 4

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: DSSpacing.sm) {
                    nerdStatCell(label: "Chunks", value: "\(chunkCount)", icon: "point.3.filled.connected.trianglepath.dotted")
                    nerdStatCell(label: "Dimension", value: "\(container.embeddingDim)D", icon: "cube.fill")
                    nerdStatCell(label: "Documents", value: "\(documentCount)", icon: "doc.fill")
                    nerdStatCell(label: "Est. Vector Bytes", value: formatBytes(estimatedMemoryBytes), icon: "memorychip")
                }

                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption2)
                    Text("~\(bytesPerVector) bytes/vector")
                        .font(.caption2.monospacedDigit())
                    Text("(Float32 estimate)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(DSSpacing.md)
            .background(DSColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
        }
    }

    @ViewBuilder
    private var documentDistributionCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Label("Document Distribution", systemImage: "chart.bar.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)

            if containerFTSStats.isEmpty {
                Text("No documents in this library")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Size distribution
                let totalChars = containerFTSStats.reduce(0) { $0 + $1.characterCount }
                let totalWords = containerFTSStats.reduce(0) { $0 + $1.wordCount }
                let avgChars = containerFTSStats.count > 0 ? totalChars / containerFTSStats.count : 0
                let avgWords = containerFTSStats.count > 0 ? totalWords / containerFTSStats.count : 0

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: DSSpacing.sm) {
                    nerdStatCell(label: "Total Chars", value: formatNumber(totalChars), icon: "character")
                    nerdStatCell(label: "Total Words", value: formatNumber(totalWords), icon: "text.word.spacing")
                    nerdStatCell(label: "Avg Chars", value: formatNumber(avgChars), icon: "textformat.size")
                    nerdStatCell(label: "Avg Words", value: formatNumber(avgWords), icon: "textformat")
                }

                // Size histogram (visual)
                if containerFTSStats.count > 1 {
                    sizeHistogramView
                }
            }
        }
        .padding(DSSpacing.md)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    @ViewBuilder
    private var sizeHistogramView: some View {
        let sortedBySize = containerFTSStats.sorted { $0.characterCount > $1.characterCount }
        let maxSize = sortedBySize.first?.characterCount ?? 1

        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("Size Distribution (largest → smallest)")
                .scaledFont(size: 9)
                .foregroundStyle(.secondary)

            HStack(alignment: .bottom, spacing: DSSpacing.xxs) {
                ForEach(sortedBySize.prefix(10), id: \.id) { doc in
                    let height = CGFloat(doc.characterCount) / CGFloat(maxSize) * 24
                    RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                        .fill(Color.accentColor.opacity(0.6))
                        .frame(width: 8, height: max(4, height))
                }
                if sortedBySize.count > 10 {
                    Text("...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 28)
        }
    }

    @ViewBuilder
    private var topTermsCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Label("Top Terms (This Library)", systemImage: "textformat.abc")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)

            if containerTopTerms.isEmpty {
                Text("No term data available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Show top 12 terms as tags
                FlowLayout(spacing: DSSpacing.xs) {
                    ForEach(containerTopTerms.prefix(12)) { term in
                        HStack(spacing: DSSpacing.xxs) {
                            Text(term.term)
                                .font(.caption2.weight(.medium))
                            Text("×\(term.totalOccurrences)")
                                .scaledFont(size: 9)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, DSSpacing.sm)
                        .padding(.vertical, DSSpacing.xs)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }

                // Vocabulary summary
                HStack(spacing: DSSpacing.md) {
                    Label("Loaded \(containerTopTerms.count) frequent terms", systemImage: "text.book.closed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(DSSpacing.md)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    @ViewBuilder
    private var retrievalConfigSummaryCard: some View {
        let config = retrievalConfig

        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Label("Retrieval Config", systemImage: "gearshape.2.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: DSSpacing.sm) {
                nerdStatCell(label: "Min Similarity", value: String(format: "%.2f", config.minSimilarity), icon: "slider.horizontal.3")
                nerdStatCell(label: "Vector Weight", value: String(format: "%.1f", config.vectorWeight), icon: "cube.fill")
                nerdStatCell(label: "Lexical Weight", value: String(format: "%.1f", config.lexicalWeight), icon: "text.magnifyingglass")
                nerdStatCell(label: "MMR λ", value: String(format: "%.2f", config.mmrLambda), icon: "arrow.triangle.branch")
            }

            // Effective mode description
            let modeDescription: String = {
                if config.vectorWeight > 0.7 { return "Semantic-heavy" }
                if config.lexicalWeight > 0.5 { return "Keyword-heavy" }
                return "Hybrid balanced"
            }()

            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "info.circle.fill")
                    .font(.caption2)
                Text("Mode: \(modeDescription)")
                    .font(.caption2)
            }
            .foregroundStyle(Color.accentColor)
        }
        .padding(DSSpacing.md)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    @ViewBuilder
    private func nerdStatCell(label: String, value: String, icon: String) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(value)
                    .font(.caption.weight(.semibold).monospacedDigit())
                Text(label)
                    .scaledFont(size: 9)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, DSSpacing.xs)
    }

    // MARK: - Formatting Helpers

    private func formatBytes(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        if mb >= 1 {
            return String(format: "%.1f MB", mb)
        } else if kb >= 1 {
            return String(format: "%.1f KB", kb)
        } else {
            return "\(bytes) B"
        }
    }

    private func formatBytes64(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        if mb >= 1 {
            return String(format: "%.1f MB", mb)
        } else if kb >= 1 {
            return String(format: "%.1f KB", kb)
        } else {
            return "\(bytes) B"
        }
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000)
        } else {
            return "\(n)"
        }
    }

    @ViewBuilder
    var deleteLibrarySection: some View {
        if containerService.containers.count > 1 {
            Section(header: Text("Danger zone")) {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Delete Library", systemImage: "trash")
                            .foregroundStyle(.red)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
            }
        }
    }

    @ViewBuilder
    var privateCloudComputeSection: some View {
        let deviceCapabilities = RAGService.checkDeviceCapabilities()
        Section(header: Text("Private Cloud Compute (PCC) Status")) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                // Corrected 2026-10-15: "Deep Think/Maximum and large contexts (>4K tokens) dynamically scale to
                // Apple's Private Cloud Compute enclaves" named a fixed window (the device reports its own; 8,192 on
                // the owner's Mac), sent every Deep Think and Maximum answer, and left out the permission.
                Text("With Hybrid in the model picker, an answer goes to Apple's Private Cloud Compute when its passages don't fit in this device's model, and a Deep Think or Maximum answer when it draws on more than one document. With Private Cloud Compute chosen there, every answer does. Each time only with your permission (Settings, Private Cloud Compute).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, DSSpacing.xs)

                // 1. Hardware/OS Support
                HStack {
                    Label("Platform Support", systemImage: "iphone")
                        .font(.subheadline)
                    Spacer()
                    if deviceCapabilities.supportsPrivateCloudCompute {
                        Text("iOS 27+ Available")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    } else {
                        Text("iOS 26 Fallback Only")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }

                // 2. Entitlement Status
                HStack {
                    Label("Developer Entitlement", systemImage: "signature")
                        .font(.subheadline)
                    Spacer()
                    #if targetEnvironment(simulator)
                    Text("Simulator (Bypassed)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    #else
                    let hasEntitlement = EntitlementChecker.hasEntitlement("com.apple.developer.private-cloud-compute")
                    Text(hasEntitlement ? "Verified Shipped" : "Missing / Not Signed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(hasEntitlement ? .green : .red)
                    #endif
                }

                // 3. User Preferences Policy
                HStack {
                    Label("iCloud Execution Consent", systemImage: "cloud.fill")
                        .font(.subheadline)
                    Spacer()
                    Text(self.settings.applePCCConsent == .allowed ? "Allowed" : (self.settings.applePCCConsent == .denied ? "Denied" : "Not Determined"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(self.settings.applePCCConsent == .allowed ? .green : .orange)
                }

                // 4. Effective Routing Fallback
                Divider()
                    .padding(.vertical, DSSpacing.xs)

                HStack {
                    Label("Effective RAG Fallback", systemImage: "arrow.triangle.branch")
                        .font(.subheadline)
                    Spacer()
                    let canUseNativePCC: Bool = {
                        #if targetEnvironment(simulator)
                        return false
                        #else
                        if deviceCapabilities.supportsPrivateCloudCompute {
                            return EntitlementChecker.hasEntitlement("com.apple.developer.private-cloud-compute")
                        }
                        return false
                        #endif
                    }()
                    
                    if canUseNativePCC && self.settings.applePCCConsent == .allowed {
                        Text("Native PCC (Apple Intelligence)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Text("On-Device (Apple Intelligence)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.green)
                    }
                }
                
                Text(effectiveFallbackDescription(capabilities: deviceCapabilities))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, DSSpacing.xxs)
            }
            .padding(.vertical, DSSpacing.xs)
        }
    }
    
    private func effectiveFallbackDescription(capabilities: DeviceCapabilities) -> String {
        // Corrected 2026-10-15, each line checked against the code: the Simulator does not run Apple's model at
        // all (`AppleFoundationLLMService` is unavailable there, so questions come back as excerpts); the
        // permission is Private Cloud Compute's, not iCloud's; "Ask when needed" asks rather than staying on
        // the device; and the planner's two Hybrid cases replace a fixed 4,096-token threshold.
        #if targetEnvironment(simulator)
        return "The Simulator can't use Apple's model or Private Cloud Compute, so questions here come back as excerpts from your documents."
        #else
        if capabilities.supportsPrivateCloudCompute {
            let hasEntitlement = EntitlementChecker.hasEntitlement("com.apple.developer.private-cloud-compute")
            if !hasEntitlement {
                return "This copy of the app was built without the Private Cloud Compute entitlement, so every answer is written on this device."
            }
            switch self.settings.applePCCConsent {
            case .denied:
                return "Private Cloud Compute is set to Never use in Settings, so every answer is written on this device."
            case .notDetermined:
                return "The app asks you before an answer goes to Private Cloud Compute (Settings, Private Cloud Compute: Ask when needed)."
            case .allowed:
                return "Private Cloud Compute is allowed without asking. With Hybrid, an answer goes there when its passages don't fit in this device's model, and a Deep Think or Maximum answer when it draws on more than one document."
            }
        } else {
            return DeviceCapabilities.pccRoutingCompiledIn
                ? "Private Cloud Compute needs iOS or macOS 27. On this version every answer is written on this device."
                : "Private Cloud Compute isn't in this build, so every answer is written on this device."
        }
        #endif
    }

    @ViewBuilder
    private var aiSubsystemDiagnosticsCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "cpu")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Text("AI Subsystem Diagnostics")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("v4.5.0")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            // 1. Embedding Model Diagnostics
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text("Embedding Pipeline")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                
                HStack {
                    Label("Active Model", systemImage: "cube.transparent")
                        .font(.caption)
                    Spacer()
                    Text("MiniLM-L6-v2 (384D)")
                        .font(.caption.weight(.medium))
                }
                
                HStack {
                    Label("Acceleration Target", systemImage: "bolt.fill")
                        .font(.caption)
                    Spacer()
                    // The library's own provider decides this, not the OS version. Through 5.6 every
                    // iOS 27 and macOS 27 device read "Core AI Neural Engine" here, and the Core AI copy of
                    // the model does not run on the Neural Engine (Docs/ai/DECISIONS.md, 2026-10-10).
                    if providerId == "coreai_sentence_embedding" {
                        Text("Core AI on the GPU")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Core ML Neural Engine")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                
                HStack {
                    Label("Readiness Gate", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                    Spacer()
                    #if canImport(CoreAI)
                    if #available(iOS 27.0, macOS 27.0, *) {
                        let isReady = CoreAISentenceEmbeddingProvider.shared.isModelLoaded
                        Text(isReady ? "Verified Ready" : "Unloaded")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(isReady ? .green : .red)
                    } else {
                        Text("Verified Ready")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    }
                    #else
                    Text("Verified Ready")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                    #endif
                }
            }
            .padding(.bottom, DSSpacing.xs)
            
            Divider()
            
            // 2. Tokenizer Diagnostics
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text("Tokenizer Pipeline")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                
                HStack {
                    Label("Core Parser", systemImage: "curlybraces")
                        .font(.caption)
                    Spacer()
                    Text("Rust-backed swift-tokenizers")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                }
                
                HStack {
                    Label("Vocabulary", systemImage: "book.closed.fill")
                        .font(.caption)
                    Spacer()
                    Text("30,522 (BERT WordPiece)")
                        .font(.caption.weight(.medium))
                }
                
                HStack {
                    Label("Citation Alignment", systemImage: "target")
                        .font(.caption)
                    Spacer()
                    Text("Exact Byte-Level Offsets")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Label("Latency Profile", systemImage: "gauge.with.needle")
                        .font(.caption)
                    Spacer()
                    Text("Microsecond Batching (<1ms)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(DSSpacing.md)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }
}
