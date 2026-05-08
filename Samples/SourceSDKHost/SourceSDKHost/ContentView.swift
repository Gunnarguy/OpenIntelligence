import OpenIntelligenceEngine
import SwiftUI
import UniformTypeIdentifiers

private enum SourceSDKHostRuntime {
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}

struct ContentView: View {
    @StateObject private var model = SourceSDKDemoViewModel()
    @FocusState private var isQuestionFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    statusSection
                    librarySection
                    documentsSection
                    querySection
                    resultSection
                }
                .padding(20)
            }
            .navigationTitle("Source SDK Host")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            guard !SourceSDKHostRuntime.isRunningTests else { return }
            model.bootstrapIfNeeded()
        }
        .fileImporter(
            isPresented: $model.isDocumentPickerPresented,
            allowedContentTypes: [.pdf, .plainText, .text, .rtf],
            allowsMultipleSelection: true,
            onCompletion: model.handleDocumentSelection
        )
        .alert(item: $model.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OpenIntelligence Source SDK")
                .font(.title.bold())
            Text("This sample consumes the root Swift package directly and exercises the public SDK surface without the XCFramework evaluation path.")
                .foregroundStyle(.secondary)
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Runtime Status")
                .font(.headline)

            LabeledContent("Availability", value: model.availabilityLabel)
            LabeledContent("Execution Context", value: model.executionContext.rawValue)
            LabeledContent("Private Cloud Compute", value: model.allowPrivateCloudCompute ? "Allowed" : "Disabled")

            if let lastAction = model.lastAction {
                Text(lastAction)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step 1 · Library")
                .font(.headline)

            TextField("Library name", text: $model.libraryName)
                .textInputAutocapitalization(.words)
                .padding(12)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 12) {
                Button("Create / Select Library") {
                    model.ensureLibrary()
                }
                .buttonStyle(.borderedProminent)

                if let activeLibrary = model.activeLibrary {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(activeLibrary.name)
                            .font(.subheadline.bold())
                        Text("\(activeLibrary.documentCount) docs · \(activeLibrary.chunkCount) chunks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !model.libraries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Known libraries")
                        .font(.subheadline.weight(.semibold))
                    ForEach(model.libraries, id: \.id) { library in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(library.name)
                                Text("\(library.documentCount) docs · \(library.chunkCount) chunks")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if library.id == model.activeLibrary?.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step 2 · Documents")
                .font(.headline)

            HStack(spacing: 12) {
                Button("Load Bundled Demo Pack") {
                    model.loadBundledDemoPack()
                }
                .buttonStyle(.borderedProminent)

                Button("Choose Files") {
                    model.isDocumentPickerPresented = true
                }
                .buttonStyle(.bordered)

                Button("Index Documents") {
                    Task { await model.ingestSelectedDocuments() }
                }
                .buttonStyle(.bordered)
                .disabled(model.selectedDocuments.isEmpty || model.isWorking)
            }

            if model.selectedDocuments.isEmpty {
                Text("No documents selected yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.selectedDocuments) { document in
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.teal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(document.name)
                            Text(document.url.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let ingestSummary = model.ingestSummary {
                Text(ingestSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var querySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step 3 · Query")
                .font(.headline)

            TextEditor(text: $model.question)
                .focused($isQuestionFocused)
                .frame(minHeight: 120)
                .padding(8)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 12) {
                Button("Ask") {
                    Task { await model.runQuery() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isWorking)

                Menu("Prompt") {
                    ForEach(model.demoPrompts, id: \.self) { prompt in
                        Button(prompt) {
                            model.question = prompt
                            isQuestionFocused = true
                        }
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step 4 · Result")
                .font(.headline)

            if model.isWorking {
                ProgressView(model.progressLabel)
            }

            if let queryResult = model.queryResult {
                Text(queryResult.answer)
                    .font(.body)

                Text("Confidence: \(String(format: "%.2f", queryResult.confidence)) · Model: \(queryResult.modelName)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if !queryResult.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Warnings")
                            .font(.subheadline.weight(.semibold))
                        ForEach(queryResult.warnings, id: \.self) { warning in
                            Text("• \(warning)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !queryResult.citations.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Citations")
                            .font(.subheadline.weight(.semibold))
                        ForEach(Array(queryResult.citations.enumerated()), id: \.offset) { _, citation in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(citation.source)
                                    .font(.subheadline.bold())
                                if let page = citation.page {
                                    Text("Page \(page)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let quote = citation.quote, !quote.isEmpty {
                                    Text("“\(quote)”")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            } else {
                Text("No query result yet.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

@MainActor
final class SourceSDKDemoViewModel: ObservableObject {
    struct DemoDocument: Identifiable {
        let id = UUID()
        let url: URL
        let name: String
    }

    struct DemoAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @Published var libraryName = "Board Briefing"
    @Published var question = "What is the fastest path to a real no-guidance SDK?"
    @Published var libraries: [OILibrary] = []
    @Published var activeLibrary: OILibrary?
    @Published var selectedDocuments: [DemoDocument] = []
    @Published var queryResult: OIQueryResult?
    @Published var ingestSummary: String?
    @Published var alert: DemoAlert?
    @Published var isDocumentPickerPresented = false
    @Published var isWorking = false
    @Published var progressLabel = "Working…"
    @Published var lastAction: String?

    let demoPrompts: [String] = [
        "What is the fastest path to a real no-guidance SDK?",
        "What are the biggest remaining risks before a no-guidance SDK claim?",
        "What progress has already been made toward a source-distributed SDK?"
    ]

    let executionContext: OIExecutionContext = .automatic
    let allowPrivateCloudCompute = true

    private lazy var engine = OIEngine(
        configuration: OIEngineConfiguration(
            allowPrivateCloudCompute: true,
            executionContext: .automatic
        )
    )
    private var hasBootstrapped = false

    var availabilityLabel: String {
        switch OIEngine.availability() {
        case .available: return "Available"
        case .simulatorUnsupported: return "Simulator Unsupported"
        case .unsupportedDevice: return "Unsupported Device"
        case .appleIntelligenceDisabled: return "Apple Intelligence Disabled"
        case .modelPreparing: return "Model Preparing"
        case let .unavailable(message): return message
        }
    }

    func bootstrapIfNeeded() {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        guard !SourceSDKHostRuntime.isRunningTests else {
            lastAction = "Running under XCTest smoke tests."
            return
        }

        refreshLibraries()
        ensureLibrary()
        lastAction = "Source SDK host initialized."
    }

    func ensureLibrary() {
        do {
            let library = try engine.createLibrary(name: libraryName)
            refreshLibraries(activeID: library.id)
            lastAction = "Active library: \(library.name)"
        } catch {
            alert = DemoAlert(title: "Library Error", message: error.localizedDescription)
        }
    }

    func refreshLibraries(activeID: UUID? = nil) {
        libraries = engine.listLibraries()
        if let activeID {
            activeLibrary = libraries.first(where: { $0.id == activeID })
        } else if let existing = activeLibrary {
            activeLibrary = libraries.first(where: { $0.id == existing.id }) ?? libraries.first
        } else {
            activeLibrary = libraries.first
        }
    }

    func loadBundledDemoPack() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "txt", subdirectory: "DemoAssets") ?? []
        selectedDocuments = urls
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { DemoDocument(url: $0, name: $0.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ").capitalized) }
        ingestSummary = nil
        queryResult = nil
        lastAction = "Loaded bundled demo pack (\(selectedDocuments.count) docs)."
    }

    func handleDocumentSelection(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            selectedDocuments = urls.map { DemoDocument(url: $0, name: $0.lastPathComponent) }
            lastAction = "Selected \(urls.count) file(s)."
        case let .failure(error):
            alert = DemoAlert(title: "Import Error", message: error.localizedDescription)
        }
    }

    func ingestSelectedDocuments() async {
        guard !selectedDocuments.isEmpty else {
            alert = DemoAlert(title: "No Documents", message: "Choose files or load the bundled demo pack first.")
            return
        }

        do {
            isWorking = true
            progressLabel = "Indexing documents…"
            let library = try engine.createLibrary(name: libraryName)
            activeLibrary = library

            let result = try await engine.ingest(
                OIIngestRequest(urls: selectedDocuments.map(\.url)),
                into: library.id
            )

            ingestSummary = "Imported \(result.importedDocuments)/\(result.totalDocuments) docs · \(result.totalLibraryChunks) chunks"
            refreshLibraries(activeID: library.id)
            lastAction = "Index complete for \(library.name)."
        } catch {
            alert = DemoAlert(title: "Ingest Error", message: error.localizedDescription)
        }
        isWorking = false
    }

    func runQuery() async {
        guard let activeLibrary else {
            alert = DemoAlert(title: "No Library", message: "Create or select a library first.")
            return
        }

        do {
            isWorking = true
            progressLabel = "Running query…"
            queryResult = try await engine.query(
                OIQueryRequest(question: question),
                in: activeLibrary.id
            )
            lastAction = "Query completed for \(activeLibrary.name)."
            refreshLibraries(activeID: activeLibrary.id)
        } catch {
            alert = DemoAlert(title: "Query Error", message: error.localizedDescription)
        }
        isWorking = false
    }
}
