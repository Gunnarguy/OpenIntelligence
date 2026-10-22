import SwiftUI

struct SemanticSearchView: View {
    @ObservedObject var ragService: RAGService
    @ObservedObject var containerService: ContainerService

    /// Text to search for as the screen opens: a search Siri handed over (5.7).
    var initialQuery: String = ""

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var results: [RetrievedChunk] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var topK: Double = 6
    @State private var minSimilarity: Double = 0.35
    @State private var enforceThreshold = true
    @FocusState private var isQueryFocused: Bool

    var body: some View {
        NavigationStack {
            content
                .onAppear {
                    let handedOver = initialQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !handedOver.isEmpty, query.isEmpty else { return }
                    query = handedOver
                    performSearch()
                }
                // Another search from Siri while this screen is open runs here.
                .onChange(of: initialQuery) { _, newQuery in
                    let handedOver = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !handedOver.isEmpty else { return }
                    query = handedOver
                    performSearch()
                }
                .navigationTitle("Semantic Search")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: DSSpacing.lg) {
                ContainerPickerStrip(containerService: containerService)

                querySection
                tuningSection
                statusSection
                resultsSection
            }
            .padding(DSSpacing.lg)
        }
        .background(DSColors.background.ignoresSafeArea())
    }

    private var querySection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Label("Search Query", systemImage: "magnifyingglass")
                .font(.headline)
            TextField("Ask about your documents", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isQueryFocused)
                .submitLabel(.search)
                .onSubmit { performSearch() }
            Button(action: performSearch) {
                HStack {
                    if isSearching {
                        ProgressView().progressViewStyle(.circular)
                    }
                    Text(isSearching ? "Searching" : "Run Search")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSearching)
        }
        .padding(DSSpacing.lg)
        .background(cardBackground)
    }

    private var tuningSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text("Tuning")
                .font(.headline)
            Stepper(value: $topK, in: 1 ... 12, step: 1) {
                Text("Top results: \(Int(topK))")
                    .monospacedDigit()
            }
            Toggle("Apply minimum similarity", isOn: $enforceThreshold)
            if enforceThreshold {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Slider(value: $minSimilarity, in: 0.2 ... 0.8, step: 0.05)
                    Text("Threshold: \(similarityLabel(minSimilarity))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(DSSpacing.lg)
        .background(cardBackground)
    }

    private var statusSection: some View {
        Group {
            // Show active embedding provider
            if let container = containerService.activeContainer {
                // A Core AI library is MiniLM too (5.7). It fell to the last branch and read "NLEmbedding (512D)",
                // the label of a different model with a different vector size, on every Mac with macOS 27, where
                // Core AI is the default. The Core ML badge read "ANE": Core ML picks the chip, and runs on the CPU
                // in the Simulator and in a background import without the GPU.
                let isCoreML = container.embeddingProviderId == "coreml_sentence_embedding"
                let isCoreAI = container.embeddingProviderId == "coreai_sentence_embedding"
                let isMiniLM = isCoreML || isCoreAI
                let isContextual = container.embeddingProviderId == "nl_contextual_embedding"
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: isMiniLM ? "cpu.fill" : (isContextual ? "sparkles" : "brain.head.profile"))
                        .foregroundStyle(Color.accentColor)
                    Text(isMiniLM ? "MiniLM-L6-v2 (384D)" : (isContextual ? "Contextual (512D)" : "NLEmbedding (512D)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isMiniLM {
                        Text(isCoreAI ? "Core AI" : "Core ML")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, DSSpacing.xs)
                            .padding(.vertical, DSSpacing.xxs)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    } else if isContextual {
                        Text("Contextual")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, DSSpacing.xs)
                            .padding(.vertical, DSSpacing.xxs)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    }
                }
                .padding(.horizontal, DSSpacing.lg)
            }

            if isSearching {
                StatusBanner(
                    icon: "hourglass", color: Color.secondary,
                    message: "Running hybrid search (vector + BM25) across \(scopedDocuments.count) document(s)..."
                )
            } else if let message = errorMessage {
                StatusBanner(
                    icon: "exclamationmark.triangle.fill", color: .orange,
                    message: message
                )
            } else if results.isEmpty {
                let hint = scopedDocuments.isEmpty
                    ? "Add documents to \(activeContainerName) before running semantic search."
                    : "Enter a question or keywords to retrieve the most relevant passages."
                StatusBanner(icon: "lightbulb.fill", color: .accentColor, message: hint)
            }
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            if !results.isEmpty {
                Text("Results")
                    .font(.title3)
                LazyVStack(spacing: DSSpacing.md) {
                    ForEach(Array(results.enumerated()), id: \.element.chunk.id) { index, chunk in
                        SemanticResultCard(
                            chunk: chunk,
                            position: index + 1
                        )
                    }
                }
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
            .fill(DSColors.surface)
            .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
    }

    private var scopedDocuments: [Document] {
        let activeId = containerService.activeContainerId
        let defaultId = containerService.containers.first?.id
        return ragService.documents.filter { doc in
            if let cid = doc.containerId {
                return cid == activeId
            } else {
                return activeId == defaultId
            }
        }
    }

    private var activeContainerName: String {
        containerService.containers.first(where: { $0.id == containerService.activeContainerId })?.name ?? "Current Library"
    }

    private func similarityLabel(_ value: Double) -> String {
        let percent = Int((value * 100).rounded())
        return "\(percent)%"
    }

    private func performSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter a query before searching."
            return
        }
        guard !scopedDocuments.isEmpty else {
            errorMessage = "Add documents to the active library before searching."
            return
        }

        isSearching = true
        errorMessage = nil
        isQueryFocused = false

        let selectedTopK = max(1, Int(topK))
        let threshold = enforceThreshold ? Float(minSimilarity) : nil

        Task {
            do {
                let chunks = try await ragService.semanticSearch(
                    query: trimmed,
                    topK: selectedTopK,
                    minSimilarity: threshold
                )
                await MainActor.run {
                    self.results = chunks
                    self.isSearching = false
                    if chunks.isEmpty {
                        self.errorMessage = "No relevant passages found. Try different keywords."
                    }
                }
            } catch {
                await MainActor.run {
                    self.results = []
                    self.isSearching = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct SemanticResultCard: View {
    let chunk: RetrievedChunk
    let position: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            header
            snippet
            metadata
        }
        .padding(DSSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.surfaceElevated)
        )
    }

    private var header: some View {
        HStack {
            Text("#\(position)")
                .font(.caption)
                .padding(.horizontal, DSSpacing.sm)
                .padding(.vertical, DSSpacing.xs)
                .background(Capsule().fill(DSColors.accent.opacity(0.15)))
                .foregroundStyle(DSColors.accent)
            Spacer()
            Text(similarityText)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }

    private var snippet: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(chunk.sourceDocument)
                .font(.subheadline)
                .fontWeight(.semibold)
            if let page = chunk.pageNumber {
                Text("Page \(page)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(chunk.chunk.content.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(6)
        }
    }

    private var metadata: some View {
        HStack(spacing: DSSpacing.md) {
            Label("Chunk \(chunk.chunk.metadata.chunkIndex + 1)", systemImage: "number")
                .font(.caption)
                .foregroundStyle(.secondary)
            Label(similarityText, systemImage: "circle.grid.cross")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var similarityText: String {
        let percent = Int((chunk.similarityScore * 100).rounded())
        return "\(percent)% match"
    }
}

private struct StatusBanner: View {
    let icon: String
    let color: Color
    let message: String

    var body: some View {
        HStack(alignment: .center, spacing: DSSpacing.md) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DSSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.surface)
        )
    }
}

#Preview {
    SemanticSearchView(
        ragService: RAGService(),
        containerService: ContainerService()
    )
}
