import Foundation
import OpenIntelligenceEngine
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = SourceSDKDemoViewModel()
    @FocusState private var isQuestionFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    heroSection
                    runtimeSection
                    librarySection
                    documentsSection
                    querySection
                    resultSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .background(demoBackground)
            .navigationTitle("Source SDK Host")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if let operationState = model.operationState {
                    DemoOperationDock(state: operationState)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .task {
            guard !SourceSDKHostRuntime.shouldSkipInteractiveBootstrap else { return }
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

    private var demoBackground: some View {
        LinearGradient(
            colors: [
                Color(uiColor: .systemGroupedBackground),
                Color.teal.opacity(0.08),
                Color.indigo.opacity(0.09)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var heroSection: some View {
        DemoCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("OpenIntelligence Source SDK", systemImage: "square.stack.3d.up.fill")
                        .font(.title2.weight(.bold))

                    Text("This sample should make one thing obvious: a separate iPhone app can load private docs, index them, and answer grounded questions with citations.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        DemoMetricPill(
                            label: "Bundled demo pack",
                            value: "\(model.bundledDemoPack.count) docs",
                            tint: .teal
                        )
                        DemoMetricPill(
                            label: "Selected right now",
                            value: "\(model.selectedDocuments.count) docs",
                            tint: .indigo
                        )
                        DemoMetricPill(
                            label: "Queryable",
                            value: model.hasQueryableContent ? "Ready" : "Not yet",
                            tint: model.hasQueryableContent ? .green : .orange
                        )
                    }
                }

                if !model.bundledDemoPack.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Bundled samples")
                            .font(.subheadline.weight(.semibold))

                        ForEach(model.bundledDemoPack.prefix(2)) { document in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "doc.richtext.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.teal)
                                    .frame(width: 24, height: 24)
                                    .background(Color.teal.opacity(0.14), in: Circle())

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(document.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text(document.preview)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }

                                Spacer(minLength: 0)

                                Text(document.source.label)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.teal)
                            }
                        }
                    }
                }

                if let lastAction = model.lastAction {
                    DemoInfoBanner(
                        title: "Latest event",
                        message: lastAction,
                        systemImage: "sparkles",
                        tint: .indigo
                    )
                }
            }
        }
    }

    private var runtimeSection: some View {
        DemoCard {
            DemoSectionHeader(
                step: "Runtime",
                title: "Can this device actually run the sample?",
                caption: "These values explain the current execution lane."
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                DemoMetricTile(
                    title: "Availability",
                    value: model.availabilityLabel,
                    detail: model.availabilityDetail,
                    systemImage: model.availabilitySystemImage,
                    tint: model.availabilityTint
                )

                DemoMetricTile(
                    title: "Execution",
                    value: model.executionContext.rawValue,
                    detail: "The sample asks the SDK to choose the best supported path.",
                    systemImage: "cpu",
                    tint: .indigo
                )

                DemoMetricTile(
                    title: "Private Cloud Compute",
                    value: model.allowPrivateCloudCompute ? "Allowed" : "Disabled",
                    detail: model.allowPrivateCloudCompute
                        ? "The SDK may use Apple’s private path when supported."
                        : "Only local execution is allowed.",
                    systemImage: model.allowPrivateCloudCompute ? "lock.shield.fill" : "lock.fill",
                    tint: model.allowPrivateCloudCompute ? .green : .orange
                )

                DemoMetricTile(
                    title: "Active library",
                    value: model.activeLibrary?.name ?? "None",
                    detail: model.activeLibraryMetrics,
                    systemImage: "books.vertical.fill",
                    tint: .teal
                )
            }
        }
    }

    private var librarySection: some View {
        DemoCard {
            DemoSectionHeader(
                step: "1",
                title: "Choose the library that will hold indexed chunks",
                caption: "If the library already exists, the sample will reuse it instead of creating a duplicate."
            )

            TextField("Library name", text: $model.libraryName)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    libraryActionButton
                    activeLibrarySummary
                }

                VStack(alignment: .leading, spacing: 12) {
                    libraryActionButton
                    activeLibrarySummary
                }
            }

            if !model.libraries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Known libraries")
                        .font(.subheadline.weight(.semibold))

                    ForEach(model.libraries, id: \.id) { library in
                        Button {
                            model.selectLibrary(library)
                        } label: {
                            DemoLibraryRow(
                                library: library,
                                isSelected: library.id == model.activeLibrary?.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var libraryActionButton: some View {
        Button {
            model.ensureLibrary()
        } label: {
            Label("Create / Select Library", systemImage: "books.vertical")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.isWorking)
    }

    @ViewBuilder
    private var activeLibrarySummary: some View {
        if let activeLibrary = model.activeLibrary {
            VStack(alignment: .leading, spacing: 5) {
                Text(activeLibrary.name)
                    .font(.subheadline.weight(.semibold))
                Text("\(activeLibrary.documentCount) indexed docs · \(activeLibrary.chunkCount) chunks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var documentsSection: some View {
        DemoCard {
            DemoSectionHeader(
                step: "2",
                title: "Pick the docs you want indexed",
                caption: "The bundled demo pack is preloaded so you can see what the sample is about before importing your own files."
            )

            DemoInfoBanner(
                title: "What these docs are",
                message: model.documentReadinessMessage,
                systemImage: "doc.text.magnifyingglass",
                tint: .teal
            )

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    bundledPackButton
                    chooseFilesButton
                    indexButton
                }

                VStack(spacing: 10) {
                    bundledPackButton
                    chooseFilesButton
                    indexButton
                }
            }

            if model.selectedDocuments.isEmpty {
                DemoEmptyState(
                    title: "No documents selected yet",
                    message: "Use the bundled demo pack or choose files from the picker."
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Selected for next ingest")
                        .font(.subheadline.weight(.semibold))

                    ForEach(model.selectedDocuments) { document in
                        DemoDocumentCard(document: document)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Indexed in active library")
                    .font(.subheadline.weight(.semibold))

                if let activeLibrary = model.activeLibrary {
                    if model.indexedDocuments.isEmpty {
                        DemoEmptyState(
                            title: "No indexed docs in \(activeLibrary.name)",
                            message: "Once you index files, they will show up here so you can remove them and reingest without deleting the app."
                        )
                    } else {
                        Text("\(activeLibrary.name) currently has \(model.indexedDocuments.count) indexed doc\(model.indexedDocuments.count == 1 ? "" : "s").")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(model.indexedDocuments) { document in
                            DemoIndexedDocumentCard(document: document) {
                                Task { await model.removeIndexedDocument(document) }
                            }
                        }
                    }
                } else {
                    DemoEmptyState(
                        title: "No active library selected",
                        message: "Create or select a library first, then index documents into it."
                    )
                }
            }

            if let ingestSummary = model.ingestSummary {
                DemoInfoBanner(
                    title: "Latest ingest",
                    message: ingestSummary,
                    systemImage: "checkmark.circle.fill",
                    tint: .green
                )
            }

            if !model.ingestWarnings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ingest warnings")
                        .font(.subheadline.weight(.semibold))

                    ForEach(model.ingestWarnings, id: \.self) { warning in
                        DemoInfoBanner(
                            title: "Warning",
                            message: warning,
                            systemImage: "exclamationmark.triangle.fill",
                            tint: .orange
                        )
                    }
                }
            }
        }
    }

    private var bundledPackButton: some View {
        Button {
            model.loadBundledDemoPack()
        } label: {
            Label("Use Bundled Demo Pack", systemImage: "shippingbox.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.isWorking)
    }

    private var chooseFilesButton: some View {
        Button {
            model.isDocumentPickerPresented = true
        } label: {
            Label("Choose Files", systemImage: "folder.badge.plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(model.isWorking)
    }

    private var indexButton: some View {
        Button {
            Task { await model.ingestSelectedDocuments() }
        } label: {
            Label("Index Selected Docs", systemImage: "text.magnifyingglass")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(!model.canIndexSelectedDocuments)
    }

    private var querySection: some View {
        DemoCard {
            DemoSectionHeader(
                step: "3",
                title: "Ask a grounded question",
                caption: "If the current library has chunks, the answer should come back with source citations."
            )

            DemoInfoBanner(
                title: model.hasQueryableContent ? "Ready to query" : "Not ready yet",
                message: model.queryReadinessMessage,
                systemImage: model.hasQueryableContent ? "checkmark.seal.fill" : "hourglass",
                tint: model.hasQueryableContent ? .green : .orange
            )

            ZStack(alignment: .topLeading) {
                if model.questionTrimmed.isEmpty {
                    Text("Ask what the documents actually say, for example: What is the fastest path to a real no-guidance SDK?")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                }

                TextEditor(text: $model.question)
                    .focused($isQuestionFocused)
                    .frame(minHeight: 140)
                    .padding(10)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(model.demoPrompts, id: \.self) { prompt in
                        Button(prompt) {
                            model.question = prompt
                            isQuestionFocused = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            Button {
                Task { await model.runQuery() }
            } label: {
                Label("Ask Grounded Question", systemImage: "bubble.left.and.text.bubble.right.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canRunQuery)
        }
    }

    private var resultSection: some View {
        DemoCard {
            DemoSectionHeader(
                step: "4",
                title: "Read the answer and verify the citations",
                caption: "This section should make it obvious whether the app is actually working."
            )

            if let queryResult = model.queryResult {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: queryResult.abstained ? "hand.raised.fill" : "text.quote")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(queryResult.abstained ? .orange : .teal)
                                .frame(width: 34, height: 34)
                                .background(
                                    (queryResult.abstained ? Color.orange : Color.teal)
                                        .opacity(0.14),
                                    in: Circle()
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(queryResult.abstained ? "The model abstained" : "Grounded answer")
                                    .font(.headline)
                                Text("The text below is the response generated from the active library.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(queryResult.answer)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            DemoMetricPill(
                                label: "Confidence",
                                value: model.confidenceSummary,
                                tint: model.confidenceTint
                            )
                            DemoMetricPill(
                                label: "Citations",
                                value: "\(queryResult.citations.count)",
                                tint: .purple
                            )
                            DemoMetricPill(
                                label: "Model",
                                value: queryResult.modelName,
                                tint: .indigo
                            )
                        }
                    }

                    if !queryResult.warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Query warnings")
                                .font(.subheadline.weight(.semibold))

                            ForEach(queryResult.warnings, id: \.self) { warning in
                                DemoInfoBanner(
                                    title: "Warning",
                                    message: warning,
                                    systemImage: "exclamationmark.triangle.fill",
                                    tint: .orange
                                )
                            }
                        }
                    }

                    if queryResult.citations.isEmpty {
                        DemoEmptyState(
                            title: "No citations returned",
                            message: "The query finished, but the model did not return source snippets for this answer."
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Citations")
                                .font(.subheadline.weight(.semibold))

                            ForEach(Array(queryResult.citations.enumerated()), id: \.offset) { index, citation in
                                DemoCitationCard(
                                    index: index + 1,
                                    citation: citation
                                )
                            }
                        }
                    }
                }
            } else {
                DemoEmptyState(
                    title: "No answer yet",
                    message: "Index the selected docs, then ask one of the prompts above to see an answer with citations."
                )
            }
        }
    }
}

@MainActor
final class SourceSDKDemoViewModel: ObservableObject {
    enum DemoDocumentSource: String {
        case bundled
        case imported

        var label: String {
            switch self {
            case .bundled:
                return "Bundled sample"
            case .imported:
                return "Imported file"
            }
        }
    }

    struct DemoDocument: Identifiable {
        let id: String
        let url: URL
        let name: String
        let source: DemoDocumentSource
        let preview: String
        let fileType: String
        let fileSizeDescription: String
    }

    struct DemoOperationState {
        enum Kind {
            case loading
            case indexing
            case querying

            var systemImage: String {
                switch self {
                case .loading:
                    return "shippingbox.fill"
                case .indexing:
                    return "text.magnifyingglass"
                case .querying:
                    return "bubble.left.and.text.bubble.right.fill"
                }
            }

            var tint: Color {
                switch self {
                case .loading:
                    return .teal
                case .indexing:
                    return .indigo
                case .querying:
                    return .purple
                }
            }
        }

        let kind: Kind
        let title: String
        let detail: String
        let nextStep: String
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
    @Published private(set) var bundledDemoPack: [DemoDocument] = []
    @Published var selectedDocuments: [DemoDocument] = []
    @Published var indexedDocuments: [OIDocument] = []
    @Published var queryResult: OIQueryResult?
    @Published var ingestSummary: String?
    @Published var ingestWarnings: [String] = []
    @Published var alert: DemoAlert?
    @Published var isDocumentPickerPresented = false
    @Published var operationState: DemoOperationState?
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

    var availabilityDetail: String {
        switch OIEngine.availability() {
        case .available:
            return "The SDK can run on this device right now."
        case .simulatorUnsupported:
            return "The simulator cannot run Apple Intelligence features."
        case .unsupportedDevice:
            return "This device does not support the required Apple Intelligence features."
        case .appleIntelligenceDisabled:
            return "Enable Apple Intelligence on the device to use the runtime."
        case .modelPreparing:
            return "Apple models are still preparing on this device."
        case let .unavailable(message):
            return message
        }
    }

    var availabilitySystemImage: String {
        switch OIEngine.availability() {
        case .available:
            return "checkmark.seal.fill"
        case .modelPreparing:
            return "hourglass"
        default:
            return "exclamationmark.triangle.fill"
        }
    }

    var availabilityTint: Color {
        switch OIEngine.availability() {
        case .available:
            return .green
        case .modelPreparing:
            return .orange
        default:
            return .red
        }
    }

    var isWorking: Bool {
        operationState != nil
    }

    var questionTrimmed: String {
        question.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasQueryableContent: Bool {
        (activeLibrary?.chunkCount ?? 0) > 0
    }

    var canIndexSelectedDocuments: Bool {
        !selectedDocuments.isEmpty && !isWorking
    }

    var canRunQuery: Bool {
        hasQueryableContent && !questionTrimmed.isEmpty && !isWorking
    }

    var activeLibraryMetrics: String {
        guard let activeLibrary else {
            return "No active library selected."
        }

        return "\(activeLibrary.documentCount) docs · \(activeLibrary.chunkCount) chunks"
    }

    var documentReadinessMessage: String {
        if selectedDocuments.isEmpty {
            return "Use the bundled demo pack to see two tiny sample docs: a board briefing and a risk memo."
        }

        let bundledCount = selectedDocuments.filter { $0.source == .bundled }.count
        let importedCount = selectedDocuments.count - bundledCount
        var parts: [String] = ["\(selectedDocuments.count) document\(selectedDocuments.count == 1 ? "" : "s") selected"]

        if bundledCount > 0 {
            parts.append("\(bundledCount) bundled")
        }

        if importedCount > 0 {
            parts.append("\(importedCount) imported")
        }

        return parts.joined(separator: " · ") + ". Tap Index Selected Docs to build searchable chunks in the active library."
    }

    var queryReadinessMessage: String {
        guard activeLibrary != nil else {
            return "Create or select a library first so the SDK has somewhere to store indexed content."
        }

        guard hasQueryableContent else {
            return "The current library has no searchable chunks yet. Index the selected documents first, then ask a question."
        }

        guard !questionTrimmed.isEmpty else {
            return "Pick one of the suggested prompts or type your own question about the indexed documents."
        }

        return "Ready. The query will run against the active library and should return citations if the answer is grounded."
    }

    var confidenceSummary: String {
        guard let queryResult else {
            return "—"
        }

        let percentage = Int((queryResult.confidence * 100).rounded())
        switch queryResult.confidence {
        case 0.85...:
            return "High (\(percentage)%)"
        case 0.60..<0.85:
            return "Medium (\(percentage)%)"
        default:
            return "Low (\(percentage)%)"
        }
    }

    var confidenceTint: Color {
        guard let queryResult else {
            return .gray
        }

        switch queryResult.confidence {
        case 0.85...:
            return .green
        case 0.60..<0.85:
            return .orange
        default:
            return .red
        }
    }

    func bootstrapIfNeeded() {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        guard !SourceSDKHostRuntime.shouldSkipInteractiveBootstrap else {
            lastAction = "Skipping interactive bootstrap for automated smoke execution."
            return
        }

        bundledDemoPack = discoverBundledDemoPack()
        if selectedDocuments.isEmpty {
            selectedDocuments = bundledDemoPack
        }

        refreshLibraries()
        ensureLibrary()
        lastAction = hasQueryableContent
            ? "Source SDK host initialized with a queryable library."
            : "Source SDK host initialized. The bundled demo pack is ready to index."
    }

    func ensureLibrary() {
        libraryName = libraryName.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing = libraries.first(where: {
            $0.name.caseInsensitiveCompare(libraryName) == .orderedSame
        }) {
            activeLibrary = existing
            libraryName = existing.name
            lastAction = "Selected existing library: \(existing.name)."
            return
        }

        do {
            let library = try engine.createLibrary(name: libraryName)
            refreshLibraries(activeID: library.id)
            lastAction = "Active library: \(library.name)."
        } catch {
            alert = DemoAlert(title: "Library Error", message: error.localizedDescription)
        }
    }

    func selectLibrary(_ library: OILibrary) {
        refreshLibraries(activeID: library.id)
        libraryName = library.name
        lastAction = "Switched to library: \(library.name)."
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

        refreshIndexedDocuments()
    }

    func refreshIndexedDocuments() {
        guard let activeLibrary else {
            indexedDocuments = []
            return
        }

        do {
            indexedDocuments = try engine.listDocuments(in: activeLibrary.id)
        } catch {
            indexedDocuments = []
        }
    }

    func loadBundledDemoPack() {
        if bundledDemoPack.isEmpty {
            bundledDemoPack = discoverBundledDemoPack()
        }

        guard !bundledDemoPack.isEmpty else {
            alert = DemoAlert(
                title: "Demo Pack Missing",
                message: "The bundled sample documents could not be found in the app bundle."
            )
            return
        }

        selectedDocuments = bundledDemoPack
        ingestSummary = nil
        ingestWarnings = []
        queryResult = nil
        operationState = nil
        lastAction = "Loaded bundled demo pack (\(selectedDocuments.count) docs)."
    }

    func handleDocumentSelection(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            selectedDocuments = urls
                .sorted {
                    $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
                }
                .map { makeDemoDocument(url: $0, source: .imported) }
            ingestSummary = nil
            ingestWarnings = []
            queryResult = nil
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

        if activeLibrary == nil {
            ensureLibrary()
        }

        guard let activeLibrary else {
            return
        }

        var securedURLs: [URL] = []
        for document in selectedDocuments where document.url.startAccessingSecurityScopedResource() {
            securedURLs.append(document.url)
        }

        defer {
            for url in securedURLs {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            operationState = DemoOperationState(
                kind: .indexing,
                title: "Indexing \(selectedDocuments.count) document\(selectedDocuments.count == 1 ? "" : "s")",
                detail: "Adding content into \(activeLibrary.name) and building searchable chunks.",
                nextStep: "Next: ask a grounded question and inspect the citations below."
            )
            queryResult = nil
            ingestSummary = nil
            ingestWarnings = []

            let result = try await engine.ingest(
                OIIngestRequest(urls: selectedDocuments.map(\.url)),
                into: activeLibrary.id
            )

            ingestSummary = "Imported \(result.importedDocuments) of \(result.totalDocuments) docs into \(activeLibrary.name). Library now has \(result.totalLibraryDocuments) docs and \(result.totalLibraryChunks) chunks."
            ingestWarnings = result.warnings
            refreshLibraries(activeID: activeLibrary.id)
            lastAction = "Index complete for \(activeLibrary.name)."
        } catch {
            alert = DemoAlert(title: "Ingest Error", message: error.localizedDescription)
        }

        operationState = nil
    }

    func removeIndexedDocument(_ document: OIDocument) async {
        guard let activeLibrary else {
            alert = DemoAlert(title: "No Library", message: "Create or select a library first.")
            return
        }

        operationState = DemoOperationState(
            kind: .loading,
            title: "Removing \(document.filename)",
            detail: "Deleting the indexed document from \(activeLibrary.name).",
            nextStep: "Next: re-index the file again if you changed its contents."
        )

        defer { operationState = nil }

        do {
            try await engine.removeDocument(id: document.id, from: activeLibrary.id)
            queryResult = nil
            ingestWarnings = []
            ingestSummary = nil
            refreshLibraries(activeID: activeLibrary.id)
            lastAction = "Removed \(document.filename) from \(activeLibrary.name)."
        } catch {
            alert = DemoAlert(title: "Remove Error", message: error.localizedDescription)
        }
    }

    func runQuery() async {
        guard let activeLibrary else {
            alert = DemoAlert(title: "No Library", message: "Create or select a library first.")
            return
        }

        guard activeLibrary.chunkCount > 0 else {
            alert = DemoAlert(
                title: "Nothing Indexed Yet",
                message: "Index the selected documents before asking a grounded question."
            )
            return
        }

        guard !questionTrimmed.isEmpty else {
            alert = DemoAlert(
                title: "No Question",
                message: "Type a question or tap one of the suggested prompts first."
            )
            return
        }

        do {
            operationState = DemoOperationState(
                kind: .querying,
                title: "Searching \(activeLibrary.name)",
                detail: "Retrieving evidence for “\(questionTrimmed)”.",
                nextStep: "Next: the answer card will show supporting citations."
            )
            queryResult = try await engine.query(
                OIQueryRequest(question: questionTrimmed),
                in: activeLibrary.id
            )
            lastAction = "Query completed for \(activeLibrary.name)."
            refreshLibraries(activeID: activeLibrary.id)
        } catch {
            alert = DemoAlert(title: "Query Error", message: error.localizedDescription)
        }

        operationState = nil
    }

    private func discoverBundledDemoPack() -> [DemoDocument] {
        let urls = Bundle.main.urls(forResourcesWithExtension: "txt", subdirectory: "DemoAssets") ?? []
        return urls
            .sorted {
                $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
            }
            .map { makeDemoDocument(url: $0, source: .bundled) }
    }

    private func makeDemoDocument(url: URL, source: DemoDocumentSource) -> DemoDocument {
        let normalizedText = loadNormalizedText(at: url)
        let lines = normalizedText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let fallbackName = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        let name = lines.first ?? fallbackName

        let preview = lines
            .dropFirst()
            .prefix(2)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safePreview = preview.isEmpty
            ? (source == .bundled ? "Bundled sample document included with the app." : "Imported from Files.")
            : preview

        let fileType = url.pathExtension.isEmpty ? "FILE" : url.pathExtension.uppercased()
        let fileSizeDescription = documentSizeDescription(for: url)

        return DemoDocument(
            id: "\(source.rawValue)-\(url.standardizedFileURL.path)",
            url: url,
            name: name,
            source: source,
            preview: safePreview,
            fileType: fileType,
            fileSizeDescription: fileSizeDescription
        )
    }

    private func loadNormalizedText(at url: URL) -> String {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }

        return raw.replacingOccurrences(of: "\\n", with: "\n")
    }

    private func documentSizeDescription(for url: URL) -> String {
        guard
            let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
            let fileSize = values.fileSize
        else {
            return "Unknown size"
        }

        return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }
}

private struct DemoCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 8)
        )
    }
}

private struct DemoSectionHeader: View {
    let step: String
    let title: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(step.hasPrefix("Step") ? step : "Step \(step)")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DemoMetricTile: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.subheadline.weight(.semibold))

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DemoMetricPill: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct DemoInfoBanner: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DemoLibraryRow: View {
    let library: OILibrary
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(library.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(library.documentCount) docs · \(library.chunkCount) chunks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if isSelected {
                Label("Active", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
        .padding(14)
        .background(
            isSelected
                ? Color.green.opacity(0.12)
                : Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? Color.green.opacity(0.35) : Color.clear, lineWidth: 1)
        )
    }
}

private struct DemoDocumentCard: View {
    let document: SourceSDKDemoViewModel.DemoDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: document.source == .bundled ? "shippingbox.fill" : "folder.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(document.source == .bundled ? .teal : .indigo)
                    .frame(width: 30, height: 30)
                    .background(
                        (document.source == .bundled ? Color.teal : Color.indigo)
                            .opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(document.name)
                        .font(.subheadline.weight(.semibold))
                    Text(document.preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                DemoMiniBadge(text: document.source.label, tint: document.source == .bundled ? .teal : .indigo)
                DemoMiniBadge(text: document.fileType, tint: .gray)
                DemoMiniBadge(text: document.fileSizeDescription, tint: .gray)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DemoIndexedDocumentCard: View {
    let document: OIDocument
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(width: 30, height: 30)
                    .background(Color.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(document.filename)
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 8) {
                        DemoMiniBadge(text: "\(document.chunkCount) chunks", tint: .green)
                        DemoMiniBadge(text: document.contentType, tint: .gray)
                    }

                    Text(document.addedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DemoMiniBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct DemoEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DemoCitationCard: View {
    let index: Int
    let citation: OICitation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text("#\(index)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.purple.opacity(0.14), in: Capsule())

                VStack(alignment: .leading, spacing: 2) {
                    Text(citation.source)
                        .font(.subheadline.weight(.semibold))
                    if let page = citation.page {
                        Text("Page \(page)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }

            if let quote = citation.quote, !quote.isEmpty {
                Text("“\(quote)”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No inline quote returned for this citation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DemoOperationDock: View {
    let state: SourceSDKDemoViewModel.DemoOperationState

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ProgressView()
                .tint(state.kind.tint)
                .scaleEffect(1.1)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Label(state.title, systemImage: state.kind.systemImage)
                    .font(.subheadline.weight(.semibold))

                Text(state.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(state.nextStep)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(state.kind.tint.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 6)
    }
}
