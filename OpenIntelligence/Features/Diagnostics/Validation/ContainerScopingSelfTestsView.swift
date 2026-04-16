//
//  ContainerScopingSelfTestsView.swift
//  OpenIntelligence
//
//  Verifies that retrieval and agentic tool calls are strictly scoped
//  to the selected KnowledgeContainer (pinned or per-message override).
//

import SwiftUI

struct ContainerScopingSelfTestsView: View {
    @ObservedObject var ragService: RAGService

    @State private var isRunning: Bool = false
    @State private var results: [ScopingTestResult] = []

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
                    // About
                    SurfaceCard {
                        SectionHeader(icon: "info.circle", title: "About")
                        VStack(alignment: .leading, spacing: 8) {
                            Text("These diagnostics validate that:")
                                .font(.subheadline)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("• Document listings reflect the selected library.")
                                Text("• A one-off per-message override confines retrieval to the override library.")
                                Text("• Agentic tool calls (search/list/summary) obey the in-flight query container context.")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }

                    // Actions
                    SurfaceCard {
                        SectionHeader(icon: "play.circle.fill", title: "Actions")
                        Button {
                            Task { await runAllTests() }
                        } label: {
                            Label(isRunning ? "Running..." : "Run Scoping Tests", systemImage: isRunning ? "hourglass" : "play.circle.fill")
                        }
                        .disabled(isRunning)
                    }

                    // Results
                    if !results.isEmpty {
                        SurfaceCard {
                            SectionHeader(icon: "list.bullet", title: "Results")
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(results) { r in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: r.icon)
                                            .foregroundColor(r.tint)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(r.name)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                            if let details = r.details, !details.isEmpty {
                                                Text(details)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .textSelection(.enabled)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Container Scoping Tests")
    }

    // MARK: - Runner

    private func runAllTests() async {
        await MainActor.run {
            isRunning = true
            results.removeAll()
        }

        var newResults: [ScopingTestResult] = []

        if let r1 = await scopedListingDiffersAcrossContainers() {
            newResults.append(r1)
        }
        if let r2 = await oneOffOverrideRetrievalIsScoped() {
            newResults.append(r2)
        }
        if let r3 = await agenticToolCallsObeyQueryContext() {
            newResults.append(r3)
        }

        await MainActor.run {
            results = newResults
            isRunning = false
        }
    }

    // MARK: - Tests

    // Test 1:
    // Listing documents under different containers should produce container-scoped differences.
    private func scopedListingDiffersAcrossContainers() async -> ScopingTestResult? {
        let containers = await MainActor.run { ragService.containerService.containers }
        guard containers.count >= 2 else {
            return ScopingTestResult(name: "Document listing differs across containers",
                              status: .skip,
                              details: "Requires at least 2 containers.")
        }
        let a = containers[0]
        let b = containers[1]

        do {
            let listA = try await ragService.withQueryContainerContext(containerId: a.id) {
                try await ragService.listDocuments()
            }
            let listB = try await ragService.withQueryContainerContext(containerId: b.id) {
                try await ragService.listDocuments()
            }

            // If both empty messages, skip
            let emptyMsg = "No documents available in the selected library."
            let aEmpty = listA.trimmingCharacters(in: .whitespacesAndNewlines) == emptyMsg
            let bEmpty = listB.trimmingCharacters(in: .whitespacesAndNewlines) == emptyMsg

            if aEmpty && bEmpty {
                return ScopingTestResult(name: "Document listing differs across containers",
                                  status: .skip,
                                  details: "Both libraries have no documents indexed; listing comparison skipped.")
            }

            if listA != listB {
                return ScopingTestResult(name: "Document listing differs across containers",
                                  status: .pass,
                                  details: "Listings for '\(a.name)' and '\(b.name)' are distinct as expected.")
            } else {
                return ScopingTestResult(name: "Document listing differs across containers",
                                  status: .fail,
                                  details: "Listings for '\(a.name)' and '\(b.name)' are identical. Expected container-scoped differences.")
            }
        } catch {
            return ScopingTestResult(name: "Document listing differs across containers",
                              status: .fail,
                              details: "Error: \(error.localizedDescription)")
        }
    }

    // Test 2:
    // When a per-message override is provided to RAGService.query, retrieved chunks should only come
    // from documents in that override container (or legacy default parity).
    private func oneOffOverrideRetrievalIsScoped() async -> ScopingTestResult? {
        let containers = await MainActor.run { ragService.containerService.containers }
        let activeId: UUID? = await MainActor.run { ragService.containerService.activeContainerId }
        guard let activeId = activeId,
              let override = containers.first(where: { $0.id != activeId })
        else {
            return ScopingTestResult(name: "Per-message override retrieval is scoped",
                              status: .skip,
                              details: "No secondary container available to test override scoping.")
        }

        // Conservative generation config
        let cfg = InferenceConfig(maxTokens: 64, temperature: 0.0, topP: 0.9, topK: 40, useKVCache: true)

        do {
            let response = try await ragService.query(
                "diagnostic retrieval probe",
                topK: 3,
                config: cfg,
                containerId: override.id
            )

            let chunks = response.retrievedChunks
            if chunks.isEmpty {
                return ScopingTestResult(name: "Per-message override retrieval is scoped",
                                  status: .skip,
                                  details: "No retrieved chunks (library '\(override.name)' likely empty or dimension mismatch); retrieval scoping check skipped.")
            }

            // Build lookup for document container ownership
            let docs = await MainActor.run { ragService.documents }
            let defaultId = await MainActor.run { ragService.containerService.containers.first?.id }

            var offenders: [String] = []
            for r in chunks {
                if let doc = docs.first(where: { $0.id == r.chunk.documentId }) {
                    // Legacy docs (nil container) belong to default only
                    let belongsToOverride =
                        (doc.containerId == override.id) ||
                        (doc.containerId == nil && override.id == defaultId)

                    if !belongsToOverride {
                        offenders.append(doc.filename)
                    }
                } else {
                    offenders.append("Unknown document for id \(r.chunk.documentId)")
                }
            }

            if offenders.isEmpty {
                return ScopingTestResult(name: "Per-message override retrieval is scoped",
                                  status: .pass,
                                  details: "All \(chunks.count) retrieved chunks belonged to '\(override.name)'.")
            } else {
                return ScopingTestResult(name: "Per-message override retrieval is scoped",
                                  status: .fail,
                                  details: "Retrieved chunks included documents outside '\(override.name)': \(offenders.joined(separator: ", "))")
            }
        } catch {
            return ScopingTestResult(name: "Per-message override retrieval is scoped",
                              status: .fail,
                              details: "Error: \(error.localizedDescription)")
        }
    }

    // Test 3:
    // Agentic tool calls under a temporary query context must obey that container.
    private func agenticToolCallsObeyQueryContext() async -> ScopingTestResult? {
        let containers = await MainActor.run { ragService.containerService.containers }
        guard let target = containers.first else {
            return ScopingTestResult(name: "Agentic tool calls obey query container context",
                              status: .skip,
                              details: "No containers available.")
        }

        do {
            let output = try await ragService.withQueryContainerContext(containerId: target.id) {
                try await ragService.searchDocuments(query: "the", topK: 3, minSimilarity: nil)
            }

            if output.contains("No relevant information found") {
                return ScopingTestResult(name: "Agentic tool calls obey query container context",
                                  status: .skip,
                                  details: "No search results in '\(target.name)'; cannot verify scoping from content.")
            }

            // Parse document names from tool output lines:
            // Format: "[1] From Filename (Page X) (Relevance: 92.1%):"
            let names = parseDocNames(from: output)

            if names.isEmpty {
                return ScopingTestResult(name: "Agentic tool calls obey query container context",
                                  status: .skip,
                                  details: "Could not extract document names from tool output.")
            }

            let docs = await MainActor.run { ragService.documents }
            let defaultId = await MainActor.run { ragService.containerService.containers.first?.id }

            var offenders: [String] = []
            for name in names {
                if let doc = docs.first(where: { $0.filename == name }) {
                    let ok = (doc.containerId == target.id) || (doc.containerId == nil && target.id == defaultId)
                    if !ok {
                        offenders.append(name)
                    }
                } else {
                    // If we cannot resolve, flag as offender for visibility
                    offenders.append("\(name) (unresolved)")
                }
            }

            if offenders.isEmpty {
                return ScopingTestResult(name: "Agentic tool calls obey query container context",
                                  status: .pass,
                                  details: "All agentic search results mapped to '\(target.name)'.")
            } else {
                return ScopingTestResult(name: "Agentic tool calls obey query container context",
                                  status: .fail,
                                  details: "Results included documents outside '\(target.name)': \(offenders.joined(separator: ", ")).\nRaw:\n\(output)")
            }
        } catch {
            return ScopingTestResult(name: "Agentic tool calls obey query container context",
                              status: .fail,
                              details: "Error: \(error.localizedDescription)")
        }
    }

    // MARK: - Parsing

    private func parseDocNames(from output: String) -> [String] {
        var names: [String] = []
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("[") && trimmed.contains("From ") else { continue }
            if let range = trimmed.range(of: "From ") {
                let after = trimmed[range.upperBound...]
                // Stop at first "(" if present; otherwise take entire remainder
                let end = after.firstIndex(of: "(") ?? after.endIndex
                let name = after[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    names.append(String(name))
                }
            }
        }
        return names
    }
}

// MARK: - Result Model

private struct ScopingTestResult: Identifiable {
    enum Status {
        case pass, fail, skip
    }

    let id = UUID()
    let name: String
    let status: Status
    let details: String?

    var icon: String {
        switch status {
        case .pass: return "checkmark.circle.fill"
        case .fail: return "xmark.octagon.fill"
        case .skip: return "minus.circle.fill"
        }
    }

    var tint: Color {
        switch status {
        case .pass: return .green
        case .fail: return .red
        case .skip: return .orange
        }
    }
}

#Preview {
    NavigationView {
        ContainerScopingSelfTestsView(ragService: RAGService())
    }
}
