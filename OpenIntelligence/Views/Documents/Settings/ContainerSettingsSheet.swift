//
//  ContainerSettingsSheet.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import Foundation
import NaturalLanguage
import SwiftUI

struct ContainerSettingsSheet: View {
    @ObservedObject var containerService: ContainerService
    @ObservedObject var ragService: RAGService
    @Environment(\.dismiss) var dismiss
    @State private var name: String = ""
    @State private var icon: String = "folder.fill"
    @State private var colorHex: String = "#4F46E5"
    @State private var providerId: String = "nl_embedding"
    @State private var dim: Int = 512
    @State private var dbKind: VectorDBKind = .persistentJSON
    @State private var strictMode: Bool = true
    @State private var autoAdaptDimension: Bool = false
    @State private var pendingReembedContext: ReembedContext?
    @State private var showingReembedConfirmation = false
    @State private var isReembedding = false
    @State private var reembedProgress: ReembedProgress?
    @State private var reembedError: String?

    private var activeContainer: KnowledgeContainer? {
        containerService.containers.first(where: { $0.id == containerService.activeContainerId })
    }

    private var activeIntelligenceReport: LibraryIntelligenceCenter.IntelligenceReport? {
        ragService.intelligenceReport(for: activeContainer?.id)
    }

    private var lastSelfTuneSummary: String? {
        guard let stamp = activeContainer?.lastSelfTuneAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: stamp, relativeTo: Date())
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Library identity & guardrails")) {
                    Text("Give this workspace a clear name, friendly icon, and color so you always know which knowledge base you're editing.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("Name", text: $name)
                    TextField("Icon (SF Symbol)", text: $icon)
                    Text("Examples: book.closed, doc.text, sparkles, folder.badge.gear. Open the SF Symbols app to browse icons that match your library's vibe.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 2)
                    TextField("Color Hex", text: $colorHex)
                    Text("Use #RRGGBB values (e.g., #3366FF). This tints cards and pickers so it's obvious which library is active.")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Toggle("Strict Mode (medical-grade)", isOn: $strictMode)

                    SettingHelpCallout(
                        icon: "shield.checkered",
                        title: "What Strict Mode enforces",
                        description: "Keeps the assistant cautious when evidence is weak—perfect for compliance, medical, or legal sets.",
                        bullets: [
                            "Requires similarities ≥52% before a chunk can answer",
                            "Needs at least 3 confident chunks before drafting a reply",
                            "Falls back to 'I don't have enough data' instead of hallucinating",
                        ]
                    )
                }

                if let report = activeIntelligenceReport {
                    Section(header: Text("Auto Intelligence snapshot")) {
                        AutoIntelligencePanel(
                            report: report,
                            isAutoEnabled: autoAdaptDimension,
                            onToggleAuto: {
                                autoAdaptDimension.toggle()
                            }
                        )
                    }
                } else if autoAdaptDimension {
                    Section(header: Text("Auto Intelligence snapshot")) {
                        SettingHelpCallout(
                            icon: "sparkles",
                            title: "Awaiting first ingest",
                            description: "Drop a few documents into this library and the dynamic engine will profile everything, set chunking windows, and be ready to re-index the rest whenever the strategy shifts.",
                            bullets: [
                                "We’ll automatically re-chunk + re-embed when new docs change the optimal strategy",
                                "You’ll get recommendations before anything hits the cloud (and only with your consent)",
                                "Pause auto mode anytime to freeze the current profile",
                            ],
                            accent: .accentColor
                        )
                    }
                }

                Section(header: Text("Embedding model — how text becomes numbers")) {
                    Text("Pick the translator that turns sentences into vectors. Each option stays on-device unless noted.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(embeddingProviderOptions) { option in
                        SelectableOptionCard(
                            icon: option.icon,
                            title: option.title,
                            subtitle: option.tagline,
                            detail: option.detail,
                            isActive: providerId == option.id,
                            badgeText: option.badgeText,
                            isDisabled: !option.isSelectable,
                            metrics: option.metrics
                        ) {
                            guard option.isSelectable else { return }
                            providerId = option.id
                            normalizeProviderAndDimension()
                        }
                    }

                    if !providerAlerts.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(providerAlerts) { alert in
                                SettingHelpCallout(
                                    icon: alert.icon,
                                    title: alert.title,
                                    description: alert.description,
                                    bullets: alert.bullets,
                                    accent: alert.accent
                                )
                            }
                        }
                        .padding(.top, 6)
                    }
                }

                Section(header: Text("Embedding resolution")) {
                    Text("Higher dimensions capture more nuance but increase storage and indexing time.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Dimension", selection: $dim) {
                        ForEach(availableDimensionValues, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .pickerStyle(.menu)

                    Toggle(isOn: $autoAdaptDimension) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dynamic self-tuning library")
                            if autoAdaptDimension, let directive = activeContainer?.chunkingDirective {
                                Text("Chunking locked on \(directive.strategy.capitalized) • \(directive.targetWordWindow)w / \(directive.overlapWords) overlap from the last run.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if autoAdaptDimension {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("OpenIntelligence watches the entire corpus. When a fresh upload shifts the optimal chunking windows or embedding space, we’ll automatically re-chunk and re-embed the whole library for you.")
                            if let summary = lastSelfTuneSummary {
                                Text("Last tune \(summary). Next one kicks in as soon as the intelligence profile drifts again.")
                            } else {
                                Text("First tune will kick off as soon as enough signal lands to profile your stack.")
                            }
                        }
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                        .padding(.top, 4)
                    } else {
                        Text("Leave this off to keep manual control—recommendations still show up, but nothing will re-index or re-chunk without you pressing the button.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }

                    if let selectedOption = dimensionOptions.first(where: { $0.value == dim }) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: selectedOption.icon)
                                    .foregroundColor(.accentColor)
                                Text(selectedOption.title)
                                    .font(.subheadline.weight(.semibold))
                            }
                            Text(selectedOption.detail)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if !selectedOption.metrics.isEmpty {
                                HStack(spacing: 12) {
                                    ForEach(selectedOption.metrics) { metric in
                                        HStack(spacing: 4) {
                                            Image(systemName: metric.icon)
                                                .font(.caption2)
                                            Text(metric.text)
                                                .font(.caption2)
                                        }
                                        .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .background(Color.accentColor.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    if activeContainer?.embeddingDim != dim {
                        SettingHelpCallout(
                            icon: "arrow.triangle.2.circlepath",
                            title: "Re-embed required",
                            description: "Changing dimensions reshapes every vector. Reprocess your documents so searches stay accurate.",
                            bullets: [
                                "Export/backup if you need a snapshot",
                                "Re-run ingestion to rebuild embeddings",
                                "Old indexes are discarded once new vectors exist",
                            ],
                            accent: .orange
                        )
                    }

                    if isReembedding, let progress = reembedProgress {
                        ReembedStatusBanner(progress: progress)
                    }
                }

                Section(header: Text("Vector database — where embeddings live")) {
                    Text("Choose how search indexes are stored. Durable engines persist on disk; volatile ones reset when you relaunch.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(vectorDBOptions) { option in
                        SelectableOptionCard(
                            icon: option.icon,
                            title: option.title,
                            subtitle: option.caption,
                            detail: option.detail,
                            isActive: dbKind == option.kind
                        ) {
                            dbKind = option.kind
                        }
                    }
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
                        handleSave()
                    }
                    .disabled(isReembedding)
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
                    autoAdaptDimension = c.autoAdaptDimension
                }
                normalizeProviderAndDimension()
                if let containerId = activeContainer?.id {
                    ragService.refreshIntelligence(for: containerId)
                } else {
                    ragService.refreshIntelligence(for: nil)
                }
            }
            .onChange(of: providerId) { _, _ in
                normalizeProviderAndDimension()
            }
            .onChange(of: containerService.activeContainerId) { _, newValue in
                ragService.refreshIntelligence(for: newValue)
            }
            .confirmationDialog(
                "Rebuild embeddings now?",
                isPresented: $showingReembedConfirmation,
                presenting: pendingReembedContext
            ) { context in
                Button("Rebuild now (\(context.documentCount) docs)") {
                    startReembedding(context)
                }
                Button("Later", role: .cancel) {
                    pendingReembedContext = nil
                    showingReembedConfirmation = false
                    dismiss()
                }
            } message: { context in
                Text("You changed the \(context.reason). We'll refresh \(context.documentCount) document\(context.documentCount == 1 ? "" : "s") so search quality stays sharp.")
            }
            .alert("Re-embed failed", isPresented: Binding(
                get: { reembedError != nil },
                set: { if !$0 { reembedError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                if let message = reembedError {
                    Text(message)
                }
            }
        }
    }

    private var embeddingProviderOptions: [EmbeddingProviderOption] {
        [
            EmbeddingProviderOption(
                id: "nl_embedding",
                icon: "bolt.badge.a",
                title: "Apple Natural Language",
                tagline: "Fast, private default",
                detail: "Runs 100% on-device with low battery impact. Great for mixed-format libraries and everyday Q&A.",
                isSelectable: true,
                badgeText: nil,
                supportedDimensions: [512],
                metrics: [
                    OptionMetric(icon: "speedometer", text: "~2.1 ms/chunk", tint: .accentColor),
                    OptionMetric(icon: "battery.100", text: "Low battery impact"),
                    OptionMetric(icon: "lock.shield", text: "Private by default"),
                ],
                alert: nil
            ),
            EmbeddingProviderOption(
                id: "nl_contextual_embedding",
                icon: "sparkles",
                title: "Contextual Embeddings",
                tagline: "High-accuracy semantic search",
                detail: "BERT-like contextual understanding. 'Bank' near 'river' differs from 'bank' near 'money'. 15-25% accuracy boost for complex queries.",
                isSelectable: true,
                badgeText: "⚡ Recommended",
                supportedDimensions: [512],
                metrics: [
                    OptionMetric(icon: "brain.head.profile", text: "Context-aware", tint: .purple),
                    OptionMetric(icon: "chart.line.uptrend.xyaxis", text: "+15-25% accuracy", tint: .green),
                    OptionMetric(icon: "lock.shield", text: "100% on-device"),
                ],
                alert: ProviderAvailabilityAlert(
                    id: "nl_contextual",
                    icon: "arrow.down.circle",
                    title: "One-time model download",
                    description: "First use downloads ~50MB language model. After that, everything runs on-device.",
                    bullets: [
                        "Supports 27+ languages automatically",
                        "Best for research, medical, legal documents",
                        "No cloud calls—ever",
                    ],
                    accent: .purple
                )
            ),
            EmbeddingProviderOption(
                id: "coreml_sentence_embedding",
                icon: "text.book.closed.fill",
                title: "Core ML Sentence",
                tagline: "Question-focused",
                detail: "Load your own Core ML sentence encoders for multilingual or domain-specific embeddings.",
                isSelectable: true,
                badgeText: nil,
                supportedDimensions: [384, 768],
                metrics: [
                    OptionMetric(icon: "globe", text: "Multilingual ready"),
                    OptionMetric(icon: "externaldrive", text: "Bring-your-own model"),
                    OptionMetric(icon: "icloud.and.arrow.down", text: "Side-load requirement"),
                ],
                alert: ProviderAvailabilityAlert(
                    id: "coreml",
                    icon: "tray.and.arrow.down.fill",
                    title: "Install Core ML bundle",
                    description: "Import a compatible `.mlpackage` via Files to enable Core ML sentence embeddings.",
                    bullets: [
                        "Supports e5-small, MiniLM, and multilingual encoders",
                        "Place the package under On-Device Models",
                        "Restart the app after sideloading to refresh",
                    ],
                    accent: .orange
                )
            ),
            EmbeddingProviderOption(
                id: "apple_fm_embed",
                icon: "sparkles.rectangle.stack",
                title: "Apple Foundation Model",
                tagline: "Cloud-consent powerhouse",
                detail: "Uses Apple's embedding endpoint with 1024-dim research-grade vectors.",
                isSelectable: true,
                badgeText: nil,
                supportedDimensions: [1024],
                metrics: [
                    OptionMetric(icon: "wifi", text: "Calls Apple PCC"),
                    OptionMetric(icon: "shield.lefthalf.fill", text: "Consent logged"),
                    OptionMetric(icon: "dial.max.fill", text: "1024 dimensions"),
                ],
                alert: ProviderAvailabilityAlert(
                    id: "apple_fm",
                    icon: "lock.shield",
                    title: "Apple FM needs consent",
                    description: "This endpoint calls Private Cloud Compute with full privacy protection.",
                    bullets: [
                        "Requires iOS 26+ and Apple ID opt-in",
                        "All transmissions logged in Telemetry",
                        "1024-dimension vectors for maximum fidelity",
                    ],
                    accent: .purple
                )
            ),
        ]
    }

    private var dimensionOptions: [DimensionOption] {
        [
            DimensionOption(
                value: 384,
                icon: "speedometer",
                title: "384 • Compact",
                caption: "Tiny index",
                detail: "Best for <50 documents or lightweight notes. Re-embeds quickly and minimizes storage.",
                metrics: [
                    OptionMetric(icon: "externaldrive", text: "~0.55 MB / 100 docs"),
                    OptionMetric(icon: "person.3.sequence", text: "Rapid retraining", tint: .green),
                ]
            ),
            DimensionOption(
                value: 512,
                icon: "dial.medium.fill",
                title: "512 • Balanced",
                caption: "Recommended",
                detail: "Default sweet spot for mobile. Captures nuance without ballooning storage.",
                metrics: [
                    OptionMetric(icon: "speedometer", text: "~2.1 ms/chunk", tint: .accentColor),
                    OptionMetric(icon: "externaldrive", text: "~0.78 MB / 100 docs"),
                    OptionMetric(icon: "cube.box", text: "1K chunks comfy"),
                ]
            ),
            DimensionOption(
                value: 768,
                icon: "dial.high.fill",
                title: "768 • High resolution",
                caption: "Richer context",
                detail: "Great for technical manuals or multilingual sets. Larger index (~1.5× 512).",
                metrics: [
                    OptionMetric(icon: "speedometer", text: "~3.4 ms/chunk"),
                    OptionMetric(icon: "externaldrive", text: "~1.1 MB / 100 docs"),
                    OptionMetric(icon: "globe", text: "Better multilingual fidelity"),
                ]
            ),
            DimensionOption(
                value: 1024,
                icon: "dial.max.fill",
                title: "1024 • Ultra",
                caption: "Research grade",
                detail: "Maximum fidelity for giant libraries. Expect longer ingestion and biggest storage footprint.",
                metrics: [
                    OptionMetric(icon: "speedometer", text: "~4.8 ms/chunk"),
                    OptionMetric(icon: "externaldrive", text: "~1.5 MB / 100 docs"),
                    OptionMetric(icon: "building.columns", text: ">10K chunk atlas"),
                ]
            ),
        ]
    }

    private var availableDimensionOptions: [DimensionOption] {
        guard let option = embeddingProviderOptions.first(where: { $0.id == providerId && $0.isSelectable }) else {
            return []
        }
        return dimensionOptions.filter { option.supportedDimensions.contains($0.value) }
    }

    private var availableDimensionValues: [Int] {
        guard let option = embeddingProviderOptions.first(where: { $0.id == providerId && $0.isSelectable }) else {
            return [512]
        }
        return option.supportedDimensions.sorted()
    }

    private var providerAlerts: [ProviderAvailabilityAlert] {
        embeddingProviderOptions.compactMap { $0.alert }
    }

    private var vectorDBOptions: [VectorDBOptionDescriptor] {
        [
            VectorDBOptionDescriptor(
                kind: .persistentJSON,
                icon: "externaldrive.badge.checkmark",
                title: "Persistent JSON",
                caption: "Simple & durable",
                detail: "Plain files stored with your documents. Perfect for under 1K docs and effortless backups."
            ),
            VectorDBOptionDescriptor(
                kind: .vecturaHNSW,
                icon: "chart.xyaxis.line",
                title: "Vectura HNSW",
                caption: "Fastest searches",
                detail: "Graph index built for >1K documents. Millisecond lookups even with millions of chunks."
            ),
            VectorDBOptionDescriptor(
                kind: .inMemory,
                icon: "bolt.slash",
                title: "In-Memory",
                caption: "Scratchpad",
                detail: "Lives in RAM only. Clears on relaunch—use for demos or temporary experiments."
            ),
        ]
    }

    private func normalizeProviderAndDimension() {
        guard let option = embeddingProviderOptions.first(where: { $0.id == providerId }) else {
            if let fallback = embeddingProviderOptions.first(where: { $0.isSelectable }) {
                providerId = fallback.id
                dim = fallback.supportedDimensions.first ?? dim
            }
            return
        }

        guard option.isSelectable else {
            if let fallback = embeddingProviderOptions.first(where: { $0.isSelectable }) {
                if providerId != fallback.id {
                    providerId = fallback.id
                }
                dim = fallback.supportedDimensions.first ?? dim
            }
            return
        }

        if !option.supportedDimensions.contains(dim) {
            dim = option.supportedDimensions.first ?? dim
        }
    }

    private var activeContainerDocuments: [Document] {
        guard let containerId = activeContainer?.id else { return [] }
        return documents(for: containerId)
    }

    private func documents(for containerId: UUID) -> [Document] {
        let defaultContainerId = containerService.containers.first?.id
        return ragService.documents.filter { document in
            if let docContainer = document.containerId {
                return docContainer == containerId
            } else {
                return containerId == defaultContainerId
            }
        }
    }

    private func handleSave() {
        guard var container = activeContainer else { return }
        let previousProvider = container.embeddingProviderId
        let previousDim = container.embeddingDim
        let previousDB = container.vectorDBKind
        let previousAutoAdapt = container.autoAdaptDimension

        container.name = name
        container.icon = icon
        container.colorHex = colorHex
        container.embeddingProviderId = providerId
        container.embeddingDim = dim
        container.vectorDBKind = dbKind
        container.strictMode = strictMode
        container.autoAdaptDimension = autoAdaptDimension

        containerService.updateContainer(container)

        if autoAdaptDimension, !previousAutoAdapt {
            ragService.refreshIntelligence(for: container.id, force: true)
        }

        if previousDim != dim {
            print("ℹ️ Container \(container.name) embedding dimension changed from \(previousDim) to \(dim). Re-embedding required for best results.")
        }
        if previousDB != dbKind {
            print("ℹ️ Container \(container.name) vector DB changed to \(dbKind). New index will be used on next retrieval.")
        }

        let providerChanged = previousProvider != providerId
        let dimensionChanged = previousDim != dim
        let needsReembed = (providerChanged || dimensionChanged) && !activeContainerDocuments.isEmpty

        if needsReembed {
            pendingReembedContext = ReembedContext(
                containerId: container.id,
                reason: reembedReason(providerChanged: providerChanged, dimensionChanged: dimensionChanged),
                documentCount: activeContainerDocuments.count
            )
            showingReembedConfirmation = true
        } else {
            dismiss()
        }
    }

    private func reembedReason(providerChanged: Bool, dimensionChanged: Bool) -> String {
        switch (providerChanged, dimensionChanged) {
        case (true, true):
            return "provider & resolution"
        case (true, false):
            return "embedding provider"
        case (false, true):
            return "vector resolution"
        default:
            return "configuration"
        }
    }

    private func startReembedding(_ context: ReembedContext) {
        pendingReembedContext = nil
        showingReembedConfirmation = false
        isReembedding = true
        reembedProgress = ReembedProgress(completed: 0, total: context.documentCount, currentFilename: "")

        Task {
            do {
                try await ragService.reembedDocuments(in: context.containerId) { progress in
                    reembedProgress = progress
                }
                await MainActor.run {
                    isReembedding = false
                    dismiss()
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    reembedError = error.localizedDescription
                    isReembedding = false
                }
            }
        }
    }
}

// MARK: - Settings Helpers

private struct EmbeddingProviderOption: Identifiable {
    let id: String
    let icon: String
    let title: String
    let tagline: String
    let detail: String
    let isSelectable: Bool
    let badgeText: String?
    let supportedDimensions: [Int]
    let metrics: [OptionMetric]
    let alert: ProviderAvailabilityAlert?
}

private struct DimensionOption: Identifiable {
    let value: Int
    let icon: String
    let title: String
    let caption: String
    let detail: String
    let metrics: [OptionMetric]

    var id: Int { value }
}

private struct VectorDBOptionDescriptor: Identifiable {
    let kind: VectorDBKind
    let icon: String
    let title: String
    let caption: String
    let detail: String

    var id: VectorDBKind { kind }
}

private struct ProviderAvailabilityAlert: Identifiable {
    let id: String
    let icon: String
    let title: String
    let description: String
    let bullets: [String]
    let accent: Color
}

private struct LibraryThemePreset: Identifiable {
    let id: String
    let title: String
    let icon: String
    let colorHex: String
    let description: String
    let strictModeDefault: Bool?

    var subtitle: String {
        strictModeDefault == true ? "Strict guardrails" : "Flexible responses"
    }
}

private struct ReembedContext: Identifiable {
    let containerId: UUID
    let reason: String
    let documentCount: Int

    var id: UUID { containerId }
}

private struct SelectableOptionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let detail: String
    let isActive: Bool
    var badgeText: String? = nil
    var isDisabled: Bool = false
    var metrics: [OptionMetric] = []
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(iconColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .foregroundColor(primaryTextColor)

                        if isActive {
                            Pill(text: "ACTIVE", color: .accentColor)
                        } else if let badge = badgeText {
                            Pill(text: badge, color: .orange)
                        }
                    }

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(secondaryTextColor)

                    Text(detail)
                        .font(.caption2)
                        .foregroundColor(secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)

                    if !metrics.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(metrics) { metric in
                                HStack(spacing: 6) {
                                    Image(systemName: metric.icon)
                                        .font(.caption2)
                                        .foregroundColor(metric.tint)
                                    Text(metric.text)
                                        .font(.caption2)
                                        .foregroundColor(metric.tint)
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                }

                Spacer()

                Image(systemName: isActive ? "checkmark.circle.fill" : (isDisabled ? "lock.circle" : "circle"))
                    .foregroundColor(trailingIconColor)
                    .imageScale(.large)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) embedding provider. \(subtitle)")
        .accessibilityValue(isActive ? "Currently active" : (isDisabled ? "Unavailable" : "Available"))
        .accessibilityHint(isDisabled ? "This provider is not available on your device" : "Double tap to select this embedding provider")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private var iconColor: Color {
        if isDisabled { return .secondary.opacity(0.4) }
        return isActive ? .accentColor : .secondary
    }

    private var primaryTextColor: Color {
        isDisabled ? .secondary.opacity(0.7) : .primary
    }

    private var secondaryTextColor: Color {
        isDisabled ? .secondary.opacity(0.6) : .secondary
    }

    private var trailingIconColor: Color {
        if isDisabled { return .secondary.opacity(0.6) }
        return isActive ? .accentColor : .secondary
    }

    private var backgroundColor: Color {
        if isActive { return Color.accentColor.opacity(0.08) }
        if isDisabled { return DSColors.surface.opacity(0.7) }
        return DSColors.surface
    }

    private var borderColor: Color {
        if isActive { return Color.accentColor.opacity(0.6) }
        if isDisabled { return Color.gray.opacity(0.2) }
        return Color.gray.opacity(0.15)
    }

    private struct Pill: View {
        let text: String
        let color: Color

        var body: some View {
            Text(text.uppercased())
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.12))
                .clipShape(Capsule())
        }
    }
}

private struct OptionMetric: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    var tint: Color = .secondary
}

private struct SettingHelpCallout: View {
    let icon: String
    let title: String
    let description: String
    let bullets: [String]
    var accent: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(accent)
                Text(title)
                    .font(.headline)
            }

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(accent)
                            .padding(.top, 1)
                        Text(bullet)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent.opacity(0.08))
        )
    }
}

private struct AutoIntelligencePanel: View {
    let report: LibraryIntelligenceCenter.IntelligenceReport
    let isAutoEnabled: Bool
    var onToggleAuto: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        isAutoEnabled ? "Auto Intelligence is orchestrating" : "Latest intelligence snapshot",
                        systemImage: "wand.and.stars"
                    )
                    .font(.subheadline.weight(.semibold))

                    Text(headline)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(relationshipSummary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let onToggleAuto {
                    Button(isAutoEnabled ? "Switch to manual" : "Use Auto Intelligence", action: onToggleAuto)
                        .buttonStyle(.borderedProminent)
                        .font(.caption)
                        .tint(isAutoEnabled ? .gray : .accentColor)
                }
            }

            Divider()

            InsightLine(
                icon: "square.stack.3d.down.right",
                title: "Chunking",
                value: "\(report.chunking.strategy.displayName) • \(report.chunking.targetWordWindow)w window / \(report.chunking.overlapWords) overlap",
                detail: report.chunking.rationales.joined(separator: " · ")
            )

            InsightLine(
                icon: "dot.vector",
                title: "Embeddings",
                value: "\(friendlyProviderName(report.embedding.providerId)) • \(report.embedding.dimension)D",
                detail: report.embedding.rationale
            )

            InsightLine(
                icon: "line.3.horizontal.decrease.circle",
                title: "Retrieval",
                value: "\(report.retrieval.fusionStyle.displayName) • vector \(percentage(report.retrieval.vectorWeight)) / lexical \(percentage(report.retrieval.lexicalWeight))",
                detail: retrievalDetails
            )

            if let languageDetail = dominantLanguageDetail {
                InsightLine(
                    icon: "globe",
                    title: "Languages",
                    value: languageDetail,
                    detail: report.corpus.multilingualScore > 0.5
                        ? "We’re mapping cross-language references automatically."
                        : "Single-language focus detected, optimizing for nuance."
                )
            }

            if !report.documents.isEmpty {
                Divider()
                DocumentContextSummary(documents: report.documents)
            }

            if !report.alerts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(report.alerts, id: \.self) { alert in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text(alert)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.08)))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
    }

    private var headline: String {
        let corpus = report.corpus
        guard corpus.documentCount > 0 else {
            return "No documents yet—ready to profile whatever you drop in."
        }
        if corpus.hasMath && corpus.technicalDensity > 0.55 {
            return "Treating this as a precision research stack with deep technical context."
        }
        if corpus.hasCode {
            return "Profiling the library as an engineering playbook that mixes prose and code."
        }
        if corpus.multilingualScore > 0.6 {
            return "Detected a multilingual knowledge base and widened the semantic space."
        }
        if corpus.documentCount >= 5 && corpus.vocabularyRichness < 0.35 {
            return "Blending diverse topics into a general knowledge base while tracking overlaps."
        }
        return "Dialed in as a focused library built around your recent uploads."
    }

    private var relationshipSummary: String {
        let corpus = report.corpus
        if corpus.documentCount == 0 {
            return "Auto Intelligence will relate documents as soon as the first batch lands."
        }
        let docWord = corpus.documentCount == 1 ? "document" : "documents"
        let chunkWord = corpus.chunkCount == 1 ? "chunk" : "chunks"
        var fragments = ["\(corpus.documentCount) \(docWord)", "\(corpus.chunkCount) \(chunkWord)"]
        if corpus.structuredRatio > 0.3 {
            fragments.append("structure-rich sections detected")
        }
        if corpus.hasMath {
            fragments.append("math-heavy passages linked")
        }
        if corpus.hasCode {
            fragments.append("code + prose blended")
        }
        return "Currently orchestrating " + fragments.joined(separator: " • ") + ". We'll keep rebalancing windows and embeddings as you add new domains."
    }

    private var retrievalDetails: String {
        var parts = report.retrieval.notes
        parts.append("MMR λ=\(String(format: "%.2f", report.retrieval.mmrLambda))")
        parts.append("Reranker: \(report.retrieval.reranker.displayName)")
        return parts.joined(separator: " · ")
    }

    private var dominantLanguageDetail: String? {
        guard let dominant = report.corpus.languageHypotheses.max(by: { $0.value < $1.value }) else {
            return nil
        }
        let code = dominant.key.rawValue
        let readable = Locale.current.localizedString(forLanguageCode: code) ?? code
        let extra = report.corpus.languageHypotheses.count > 1
            ? " + \(report.corpus.languageHypotheses.count - 1) others"
            : ""
        return "\(readable)\(extra) (\(percentage(dominant.value)))"
    }

    private func friendlyProviderName(_ providerId: String) -> String {
        switch providerId {
        case "coreml_sentence_embedding":
            return "Core ML Sentence"
        case "apple_fm_embed":
            return "Apple Foundation Model"
        default:
            return "Apple Natural Language"
        }
    }

    private func percentage(_ value: Double) -> String {
        let clamped = max(0, min(value, 1))
        return String(format: "%.0f%%", clamped * 100)
    }
}

private struct InsightLine: View {
    let icon: String
    let title: String
    let value: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }

            Text(value)
                .font(.callout)
                .foregroundColor(.primary)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct DocumentContextSummary: View {
    let documents: [LibraryIntelligenceCenter.DocumentProfile]

    private var featuredDocuments: [LibraryIntelligenceCenter.DocumentProfile] {
        Array(documents.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Document context", systemImage: "books.vertical")
                .font(.subheadline.weight(.semibold))

            ForEach(featuredDocuments) { profile in
                DocumentProfileRow(profile: profile)
                if profile.id != featuredDocuments.last?.id {
                    Divider()
                }
            }

            if documents.count > featuredDocuments.count {
                Text("+\(documents.count - featuredDocuments.count) more captured in this library")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct DocumentProfileRow: View {
    let profile: LibraryIntelligenceCenter.DocumentProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(profile.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
            }

            Text(profile.descriptor)
                .font(.caption)
                .foregroundColor(.secondary)

            if !profile.keyTopics.isEmpty {
                HStack(spacing: 6) {
                    ForEach(profile.keyTopics.prefix(3), id: \.self) { topic in
                        TopicChip(text: topic)
                    }
                }
            }

            if !profile.preview.isEmpty {
                Text(profile.preview)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct TopicChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(0.15))
            )
            .foregroundColor(.accentColor)
    }
}

private extension LibraryIntelligenceCenter.ChunkingPlan.Strategy {
    var displayName: String {
        switch self {
        case .balanced: return "Balanced"
        case .densePrecision: return "Precision"
        case .elastic: return "Elastic"
        }
    }
}

private extension LibraryIntelligenceCenter.RetrievalPlan.FusionStyle {
    var displayName: String {
        switch self {
        case .hybrid: return "Hybrid"
        case .vectorOnly: return "Vector-first"
        case .lexicalBoosted: return "Lexical boosted"
        }
    }
}

private extension LibraryIntelligenceCenter.RetrievalPlan.RerankerStrategy {
    var displayName: String {
        switch self {
        case .none: return "None"
        case .semantic: return "Semantic"
        case .structural: return "Structural"
        }
    }
}

private struct ReembedStatusBanner: View {
    let progress: ReembedProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Rebuilding embeddings", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if progress.total > 0 {
                    Text("\(progress.completed)/\(progress.total)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            ProgressView(value: progress.percentage)
                .tint(.orange)

            if !progress.currentFilename.isEmpty {
                Text(progress.currentFilename)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Text("We’ll refresh embeddings so retrieval quality matches your new configuration.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
    }
}
