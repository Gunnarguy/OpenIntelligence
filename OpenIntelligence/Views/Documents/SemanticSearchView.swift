import SwiftUI

struct SemanticSearchView: View {
    @ObservedObject var ragService: RAGService
    @ObservedObject var containerService: ContainerService

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
        NavigationView {
            content
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
            VStack(spacing: 16) {
                ContainerPickerStrip(containerService: containerService)

                querySection
                tuningSection
                statusSection
                resultsSection
            }
            .padding()
        }
        .background(DSColors.background.ignoresSafeArea())
    }

    private var querySection: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        .padding()
        .background(cardBackground)
    }

    private var tuningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tuning")
                .font(.headline)
            Stepper(value: $topK, in: 1...12, step: 1) {
                Text("Top results: \(Int(topK))")
            }
            Toggle("Apply minimum similarity", isOn: $enforceThreshold)
            if enforceThreshold {
                VStack(alignment: .leading, spacing: 6) {
                    Slider(value: $minSimilarity, in: 0.2...0.8, step: 0.05)
                    Text("Threshold: \(similarityLabel(minSimilarity))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(cardBackground)
    }

    private var statusSection: some View {
        Group {
            if isSearching {
                StatusBanner(
                    icon: "hourglass", color: Color.secondary,
                    message: "Running cosine search across \(scopedDocuments.count) document(s)..."
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
                StatusBanner(icon: "lightbulb.fill", color: .blue, message: hint)
            }
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !results.isEmpty {
                Text("Results")
                    .font(.title3)
                    .fontWeight(.semibold)
                LazyVStack(spacing: 12) {
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
        RoundedRectangle(cornerRadius: 18)
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
        VStack(alignment: .leading, spacing: 10) {
            header
            snippet
            metadata
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DSColors.surfaceElevated)
        )
    }

    private var header: some View {
        HStack {
            Text("#\(position)")
                .font(.caption)
                .fontWeight(.bold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(DSColors.accent.opacity(0.15)))
                .foregroundColor(DSColors.accent)
            Spacer()
            Text(similarityText)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
    }

    private var snippet: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(chunk.sourceDocument)
                .font(.subheadline)
                .fontWeight(.semibold)
            if let page = chunk.pageNumber {
                Text("Page \(page)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(chunk.chunk.content.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(6)
        }
    }

    private var metadata: some View {
        HStack(spacing: 12) {
            Label("Chunk \(chunk.chunk.metadata.chunkIndex + 1)", systemImage: "number")
                .font(.caption)
                .foregroundColor(.secondary)
            Label(similarityText, systemImage: "circle.grid.cross")
                .font(.caption)
                .foregroundColor(.secondary)
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
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
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
