import OpenIntelligenceEngine
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = PitchDemoViewModel()
    @FocusState private var isQuestionFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                DemoBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        heroSection
                        readinessSection
                        demoPackSection
                        librarySection
                        querySection
                        resultSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 44)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Engine Demo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("OpenIntelligence")
                            .font(.custom("AvenirNext-Bold", size: 15))
                            .foregroundStyle(DemoPalette.ink)
                        Text("Pitch Demo")
                            .font(.custom("AvenirNextCondensed-DemiBold", size: 15))
                            .foregroundStyle(DemoPalette.teal)
                    }
                }
            }
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
        .onAppear {
            model.refreshAvailability()
        }
    }

    private var heroSection: some View {
        DemoCard(padding: 24) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("PRIVATE ANSWERS\nFROM PRIVATE DOCS")
                            .font(.custom("AvenirNextCondensed-Bold", size: 38))
                            .foregroundStyle(DemoPalette.ink)
                            .multilineTextAlignment(.leading)

                        Text("Index board packets, diligence memos, contracts, or customer research locally, then answer questions with grounded citations.")
                            .font(.custom("AvenirNext-Regular", size: 16))
                            .foregroundStyle(DemoPalette.ink.opacity(0.84))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    DemoStamp(label: "LIVE SDK", tint: DemoPalette.coral)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        DemoMetric(title: "Library", value: model.libraryHeadline)
                        DemoMetric(title: "Docs", value: "\(model.totalDocuments)")
                        DemoMetric(title: "Chunks", value: model.totalChunksLabel)
                    }

                    VStack(spacing: 10) {
                        DemoMetric(title: "Library", value: model.libraryHeadline)
                        HStack(spacing: 10) {
                            DemoMetric(title: "Docs", value: "\(model.totalDocuments)")
                            DemoMetric(title: "Chunks", value: model.totalChunksLabel)
                        }
                    }
                }

                Text(model.heroMessage)
                    .font(.custom("AvenirNext-DemiBold", size: 15))
                    .foregroundStyle(model.heroTint)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(model.heroTint.opacity(0.12))
                    )
            }
        }
    }

    private var readinessSection: some View {
        DemoCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader(
                    eyebrow: "Room Readiness",
                    title: "Operator status and demo posture"
                )

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        StatusPill(title: "Availability", value: model.availabilityLabel, tint: model.heroTint)
                        StatusPill(title: "Context", value: model.executionContext.rawValue, tint: DemoPalette.teal)
                        StatusPill(
                            title: "Private Cloud",
                            value: model.allowPrivateCloudCompute ? "Allowed" : "Disabled",
                            tint: model.allowPrivateCloudCompute ? DemoPalette.moss : DemoPalette.coral
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        StatusPill(title: "Availability", value: model.availabilityLabel, tint: model.heroTint)
                        HStack(spacing: 10) {
                            StatusPill(title: "Context", value: model.executionContext.rawValue, tint: DemoPalette.teal)
                            StatusPill(
                                title: "Private Cloud",
                                value: model.allowPrivateCloudCompute ? "Allowed" : "Disabled",
                                tint: model.allowPrivateCloudCompute ? DemoPalette.moss : DemoPalette.coral
                            )
                        }
                    }
                }

                Text(model.readinessMessage)
                    .font(.custom("AvenirNext-Regular", size: 15))
                    .foregroundStyle(DemoPalette.ink.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        PromptChip(label: "Choose documents") {
                            model.isDocumentPickerPresented = true
                        }

                        PromptChip(label: "Load sample question") {
                            model.question = model.demoPrompts.first ?? model.question
                            isQuestionFocused = true
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        PromptChip(label: "Choose documents") {
                            model.isDocumentPickerPresented = true
                        }

                        PromptChip(label: "Load sample question") {
                            model.question = model.demoPrompts.first ?? model.question
                            isQuestionFocused = true
                        }
                    }
                }
            }
        }
    }

    private var demoPackSection: some View {
        DemoCard(padding: 22) {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(
                    eyebrow: "Pitch Kit",
                    title: "Use the bundled demo pack"
                )

                Text("These four built-in documents simulate the exact story you want in the room: traction, customer pull, commercial wedge, and the real risks.")
                    .font(.custom("AvenirNext-Regular", size: 15))
                    .foregroundStyle(DemoPalette.ink.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {
                    ForEach(model.demoPackItems) { item in
                        DemoPackRow(item: item)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        DemoActionButton(
                            title: model.demoPackButtonTitle,
                            subtitle: "4 bundled docs, zero file-picking",
                            systemImage: "shippingbox.fill",
                            tint: DemoPalette.teal,
                            isProminent: false
                        ) {
                            model.loadBundledDemoPack()
                        }

                        DemoActionButton(
                            title: "Reset Selection",
                            subtitle: "Clear current library state",
                            systemImage: "arrow.counterclockwise",
                            tint: DemoPalette.ink,
                            isProminent: true,
                            isDisabled: model.selectedDocuments.isEmpty && model.ingestResult == nil && model.queryResult == nil
                        ) {
                            model.resetWorkspace()
                        }
                    }

                    VStack(spacing: 12) {
                        DemoActionButton(
                            title: model.demoPackButtonTitle,
                            subtitle: "4 bundled docs, zero file-picking",
                            systemImage: "shippingbox.fill",
                            tint: DemoPalette.teal,
                            isProminent: false
                        ) {
                            model.loadBundledDemoPack()
                        }

                        DemoActionButton(
                            title: "Reset Selection",
                            subtitle: "Clear current library state",
                            systemImage: "arrow.counterclockwise",
                            tint: DemoPalette.ink,
                            isProminent: true,
                            isDisabled: model.selectedDocuments.isEmpty && model.ingestResult == nil && model.queryResult == nil
                        ) {
                            model.resetWorkspace()
                        }
                    }
                }

                SummaryStrip(
                    title: "Recommended flow",
                    detail: model.demoFlow,
                    tint: DemoPalette.coral
                )
            }
        }
    }

    private var librarySection: some View {
        DemoCard(padding: 22) {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(
                    eyebrow: "Step 1",
                    title: "Stage a private knowledge library"
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Library name")
                        .font(.custom("AvenirNext-DemiBold", size: 14))
                        .foregroundStyle(DemoPalette.ink.opacity(0.76))

                    TextField("Board Briefing", text: $model.libraryName)
                        .textInputAutocapitalization(.words)
                        .font(.custom("AvenirNext-Medium", size: 17))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(DemoPalette.paper)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(DemoPalette.ink.opacity(0.08), lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Selected source documents")
                            .font(.custom("AvenirNext-DemiBold", size: 16))
                            .foregroundStyle(DemoPalette.ink)

                        Spacer()

                        Text("\(model.selectedDocuments.count)")
                            .font(.custom("AvenirNext-Bold", size: 14))
                            .foregroundStyle(DemoPalette.teal)
                    }

                    if model.selectedDocuments.isEmpty {
                        EmptyStateCard(
                            icon: "doc.badge.plus",
                            title: "Bring in PDFs or text files",
                            message: "Use customer calls, investor letters, diligence notes, or any private documents you want the engine to ground against."
                        )
                    } else {
                        VStack(spacing: 10) {
                            ForEach(model.selectedDocuments) { document in
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(DemoPalette.teal.opacity(0.12))
                                            .frame(width: 42, height: 42)
                                        Image(systemName: "doc.text")
                                            .foregroundStyle(DemoPalette.teal)
                                    }

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(document.name)
                                            .font(.custom("AvenirNext-DemiBold", size: 15))
                                            .foregroundStyle(DemoPalette.ink)
                                            .lineLimit(1)
                                        Text(document.url.lastPathComponent)
                                            .font(.custom("AvenirNext-Regular", size: 13))
                                            .foregroundStyle(DemoPalette.ink.opacity(0.58))
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Button {
                                        model.removeDocument(document)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(DemoPalette.ink.opacity(0.35))
                                            .font(.system(size: 18, weight: .bold))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 18)
                                        .fill(Color.white.opacity(0.9))
                                )
                            }
                        }
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        DemoActionButton(
                            title: "Choose Documents",
                            subtitle: "PDF, TXT, RTF",
                            systemImage: "folder.badge.plus",
                            tint: DemoPalette.teal,
                            isProminent: false
                        ) {
                            model.isDocumentPickerPresented = true
                        }

                        DemoActionButton(
                            title: model.isIngesting ? "Indexing..." : "Index Library",
                            subtitle: model.indexButtonSubtitle,
                            systemImage: model.isIngesting ? "hourglass" : "sparkles.rectangle.stack",
                            tint: DemoPalette.coral,
                            isProminent: true,
                            isDisabled: model.selectedDocuments.isEmpty || model.isIngesting
                        ) {
                            Task {
                                await model.ingestSelectedDocuments()
                            }
                        }
                    }

                    VStack(spacing: 12) {
                        DemoActionButton(
                            title: "Choose Documents",
                            subtitle: "PDF, TXT, RTF",
                            systemImage: "folder.badge.plus",
                            tint: DemoPalette.teal,
                            isProminent: false
                        ) {
                            model.isDocumentPickerPresented = true
                        }

                        DemoActionButton(
                            title: model.isIngesting ? "Indexing..." : "Index Library",
                            subtitle: model.indexButtonSubtitle,
                            systemImage: model.isIngesting ? "hourglass" : "sparkles.rectangle.stack",
                            tint: DemoPalette.coral,
                            isProminent: true,
                            isDisabled: model.selectedDocuments.isEmpty || model.isIngesting
                        ) {
                            Task {
                                await model.ingestSelectedDocuments()
                            }
                        }
                    }
                }

                if let summary = model.ingestSummary {
                    SummaryStrip(
                        title: "Indexing result",
                        detail: summary,
                        tint: DemoPalette.moss
                    )
                }
            }
        }
    }

    private var querySection: some View {
        DemoCard(padding: 22) {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(
                    eyebrow: "Step 2",
                    title: "Ask a grounded question"
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(model.demoPrompts, id: \.self) { prompt in
                            PromptChip(label: prompt) {
                                model.question = prompt
                                isQuestionFocused = true
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Question")
                        .font(.custom("AvenirNext-DemiBold", size: 14))
                        .foregroundStyle(DemoPalette.ink.opacity(0.76))

                    TextEditor(text: $model.question)
                        .font(.custom("AvenirNext-Regular", size: 17))
                        .foregroundStyle(DemoPalette.ink)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(minHeight: 128)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(DemoPalette.paper)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(DemoPalette.ink.opacity(0.08), lineWidth: 1)
                        )
                        .focused($isQuestionFocused)
                }

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Execution context")
                                .font(.custom("AvenirNext-DemiBold", size: 14))
                                .foregroundStyle(DemoPalette.ink.opacity(0.75))

                            Picker("Execution Context", selection: $model.executionContext) {
                                ForEach(PitchDemoViewModel.executionContexts, id: \.rawValue) { context in
                                    Text(context.rawValue).tag(context)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Evidence fan-out")
                                    .font(.custom("AvenirNext-DemiBold", size: 14))
                                    .foregroundStyle(DemoPalette.ink.opacity(0.75))
                                Spacer()
                                Text("\(model.topK)")
                                    .font(.custom("AvenirNext-Bold", size: 14))
                                    .foregroundStyle(DemoPalette.teal)
                            }

                            Slider(value: $model.topKValue, in: 3...8, step: 1)
                                .tint(DemoPalette.teal)
                        }

                        Toggle(isOn: $model.allowPrivateCloudCompute) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Allow Private Cloud Compute")
                                    .font(.custom("AvenirNext-DemiBold", size: 14))
                                    .foregroundStyle(DemoPalette.ink)
                                Text("Useful for live demos when richer model capacity is available.")
                                    .font(.custom("AvenirNext-Regular", size: 13))
                                    .foregroundStyle(DemoPalette.ink.opacity(0.6))
                            }
                        }
                        .tint(DemoPalette.coral)
                    }
                    .padding(.top, 14)
                } label: {
                    Text("Operator controls")
                        .font(.custom("AvenirNext-DemiBold", size: 15))
                        .foregroundStyle(DemoPalette.ink)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(0.72))
                )

                DemoActionButton(
                    title: model.isQuerying ? "Generating answer..." : "Run Grounded Query",
                    subtitle: model.queryButtonSubtitle,
                    systemImage: model.isQuerying ? "hourglass" : "arrow.up.right.circle.fill",
                    tint: DemoPalette.ink,
                    isProminent: true,
                    isDisabled: model.isQueryDisabled
                ) {
                    Task {
                        await model.runQuery()
                    }
                }
            }
        }
    }

    private var resultSection: some View {
        DemoCard(padding: 22) {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(
                    eyebrow: "Step 3",
                    title: "Present the answer with evidence"
                )

                if let result = model.queryResult {
                    VStack(alignment: .leading, spacing: 18) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) {
                                StatusPill(title: "Model", value: result.modelName, tint: DemoPalette.teal)
                                StatusPill(
                                    title: "Confidence",
                                    value: "\(Int((result.confidence * 100).rounded()))%",
                                    tint: DemoPalette.moss
                                )
                                if result.abstained {
                                    StatusPill(title: "Posture", value: "Abstained", tint: DemoPalette.coral)
                                }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                StatusPill(title: "Model", value: result.modelName, tint: DemoPalette.teal)
                                HStack(spacing: 10) {
                                    StatusPill(
                                        title: "Confidence",
                                        value: "\(Int((result.confidence * 100).rounded()))%",
                                        tint: DemoPalette.moss
                                    )
                                    if result.abstained {
                                        StatusPill(title: "Posture", value: "Abstained", tint: DemoPalette.coral)
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Answer")
                                .font(.custom("AvenirNextCondensed-DemiBold", size: 22))
                                .foregroundStyle(DemoPalette.ink)
                            Text(result.answer)
                                .font(.custom("AvenirNext-Regular", size: 17))
                                .foregroundStyle(DemoPalette.ink.opacity(0.9))
                                .textSelection(.enabled)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Evidence")
                                .font(.custom("AvenirNextCondensed-DemiBold", size: 22))
                                .foregroundStyle(DemoPalette.ink)

                            if result.citations.isEmpty {
                                EmptyStateCard(
                                    icon: "quote.bubble",
                                    title: "No citations returned",
                                    message: "The engine answered, but this result did not surface explicit citation snippets."
                                )
                            } else {
                                ForEach(Array(result.citations.enumerated()), id: \.offset) { _, citation in
                                    CitationCard(citation: citation)
                                }
                            }
                        }

                        if !result.warnings.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Warnings")
                                    .font(.custom("AvenirNextCondensed-DemiBold", size: 22))
                                    .foregroundStyle(DemoPalette.ink)

                                ForEach(result.warnings, id: \.self) { warning in
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(DemoPalette.coral)
                                        Text(warning)
                                            .font(.custom("AvenirNext-Regular", size: 14))
                                            .foregroundStyle(DemoPalette.ink.opacity(0.82))
                                    }
                                }
                            }
                        }
                    }
                } else {
                    EmptyStateCard(
                        icon: "text.quote",
                        title: "Your answer deck appears here",
                        message: "Index a private document set, ask a question, and the demo will render the answer, confidence signal, and source-backed evidence."
                    )
                }
            }
        }
    }

    private func sectionHeader(eyebrow: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased())
                .font(.custom("AvenirNext-Bold", size: 12))
                .tracking(1.3)
                .foregroundStyle(DemoPalette.coral)
            Text(title)
                .font(.custom("AvenirNextCondensed-DemiBold", size: 28))
                .foregroundStyle(DemoPalette.ink)
        }
    }
}

@MainActor
private final class PitchDemoViewModel: ObservableObject {
    static let executionContexts: [OIExecutionContext] = [.automatic, .onDeviceOnly, .preferCloud, .cloudOnly]

    @Published var libraryName = "OpenIntelligence Board Pack"
    @Published var question = "What are the three biggest risks in this packet, and what evidence supports each one?"
    @Published var selectedDocuments: [DemoDocument] = []
    @Published var ingestResult: OIIngestResult?
    @Published var queryResult: OIQueryResult?
    @Published var availability: OIAvailabilityState = OIEngine.availability()
    @Published var allowPrivateCloudCompute = true
    @Published var executionContext: OIExecutionContext = .automatic
    @Published var topK = 4
    @Published var isDocumentPickerPresented = false
    @Published var isIngesting = false
    @Published var isQuerying = false
    @Published var alert: DemoAlert?

    let demoPrompts = [
        "What are the three biggest risks in this packet, and what evidence supports each one?",
        "Which customer pain points appear most often across the research notes?",
        "What is the commercial wedge, and why would buyers care right now?",
        "Give me a two-minute investor update on traction, risks, and next steps."
    ]

    let demoPackItems = [
        DemoPackItem(
            resourceName: "01_Founder_Briefing",
            title: "Founder Briefing",
            summary: "Traction snapshot, design-partner pipeline, and the board-level narrative."
        ),
        DemoPackItem(
            resourceName: "02_Design_Partner_Research",
            title: "Design Partner Research",
            summary: "Direct buyer pain points, workflow friction, and what makes citations matter."
        ),
        DemoPackItem(
            resourceName: "03_Risk_Register",
            title: "Risk Register",
            summary: "Packaging, reliability, security-review, and adoption risks with mitigations."
        ),
        DemoPackItem(
            resourceName: "04_GTM_Memo",
            title: "Commercial Memo",
            summary: "Pricing, wedge, pilot structure, and the story for a design-partner sale."
        )
    ]

    var totalDocuments: Int {
        ingestResult?.totalLibraryDocuments ?? selectedDocuments.count
    }

    var totalChunksLabel: String {
        guard let chunks = ingestResult?.totalLibraryChunks else { return "--" }
        return chunks.formatted()
    }

    var libraryHeadline: String {
        let trimmed = trimmedLibraryName
        return trimmed.isEmpty ? "General" : trimmed
    }

    var availabilityLabel: String {
        switch availability {
        case .available:
            return "Live"
        case .simulatorUnsupported:
            return "Simulator only"
        case .unsupportedDevice:
            return "Unsupported device"
        case .appleIntelligenceDisabled:
            return "Disabled"
        case .modelPreparing:
            return "Preparing"
        case let .unavailable(message):
            return message
        }
    }

    var heroTint: Color {
        switch availability {
        case .available:
            return DemoPalette.moss
        case .simulatorUnsupported, .modelPreparing:
            return DemoPalette.teal
        case .unsupportedDevice, .appleIntelligenceDisabled, .unavailable:
            return DemoPalette.coral
        }
    }

    var heroMessage: String {
        switch availability {
        case .available:
            return "Ready for a live on-device grounded-answer demo."
        case .simulatorUnsupported:
            return "The UI and import flow work in simulator. Run on your iPhone for live answer generation."
        case .unsupportedDevice:
            return "Connect an Apple Intelligence-capable device for the full demo."
        case .appleIntelligenceDisabled:
            return "Enable Apple Intelligence on this phone before the live answer step."
        case .modelPreparing:
            return "Apple Intelligence is still preparing. Ingest can proceed while the model finishes setup."
        case let .unavailable(message):
            return message
        }
    }

    var readinessMessage: String {
        switch availability {
        case .available:
            return "This device can run the full ingest-plus-query loop. Choose a private document set, index it locally, and answer questions live with source evidence."
        case .simulatorUnsupported:
            return "Use simulator for the visual walkthrough and import UX. Use your connected iPhone for the actual question-answering moment."
        case .unsupportedDevice:
            return "The SDK is staged correctly, but this hardware cannot run the Apple Intelligence query path."
        case .appleIntelligenceDisabled:
            return "The engine is staged and ready. The only blocker is Apple Intelligence being turned off at the OS level."
        case .modelPreparing:
            return "The environment is almost ready. Give the model time to finish preparation, then rerun the live question step."
        case let .unavailable(message):
            return message
        }
    }

    var ingestSummary: String? {
        guard let ingestResult else { return nil }

        var segments = [
            "\(ingestResult.importedDocuments) imported",
            "\(ingestResult.failedDocuments) failed",
            "\(ingestResult.totalLibraryDocuments) total docs",
            "\(ingestResult.totalLibraryChunks.formatted()) chunks"
        ]

        if !ingestResult.warnings.isEmpty {
            segments.append(ingestResult.warnings.joined(separator: " "))
        }

        return segments.joined(separator: " • ")
    }

    var indexButtonSubtitle: String {
        if selectedDocuments.isEmpty {
            return "Select source files first"
        }

        let suffix = selectedDocuments.count == 1 ? "" : "s"
        if isDemoPackLoaded {
            return "Index \(selectedDocuments.count) bundled pitch doc\(suffix)"
        }

        return "Index \(selectedDocuments.count) document\(suffix)"
    }

    var queryButtonSubtitle: String {
        switch availability {
        case .available:
            return "Run grounded answer generation"
        case .simulatorUnsupported:
            return "Use your phone for live questioning"
        default:
            return "Resolve device readiness first"
        }
    }

    var demoFlow: String {
        "1. Load the bundled pack. 2. Index the library. 3. Ask the risk question first. 4. Follow with pain points or commercial wedge. 5. End on the investor-update prompt."
    }

    var demoPackButtonTitle: String {
        isDemoPackLoaded ? "Reload Demo Pack" : "Load Demo Pack"
    }

    var isQueryDisabled: Bool {
        isQuerying || trimmedQuestion.isEmpty || availability != .available
    }

    var isDemoPackLoaded: Bool {
        let demoPackPaths = Set(demoPackItems.compactMap { demoURL(for: $0)?.path })
        let selectedPaths = Set(selectedDocuments.map(\.url.path))
        return !demoPackPaths.isEmpty && selectedPaths == demoPackPaths
    }

    var topKValue: Double {
        get { Double(topK) }
        set { topK = Int(newValue.rounded()) }
    }

    func refreshAvailability() {
        availability = OIEngine.availability()
    }

    func handleDocumentSelection(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            let incoming = urls.map(DemoDocument.init)
            let existingPaths = Set(selectedDocuments.map(\.url.path))
            let deduped = incoming.filter { !existingPaths.contains($0.url.path) }
            selectedDocuments.append(contentsOf: deduped)
            if !deduped.isEmpty {
                ingestResult = nil
                queryResult = nil
            }
        case let .failure(error):
            alert = DemoAlert(title: "Document Import Failed", message: error.localizedDescription)
        }
    }

    func loadBundledDemoPack() {
        let urls = demoPackItems.compactMap { demoURL(for: $0) }
        guard urls.count == demoPackItems.count else {
            alert = DemoAlert(
                title: "Demo Pack Missing",
                message: "The bundled pitch documents were not found in the app bundle. Regenerate the project and rebuild the host app."
            )
            return
        }

        selectedDocuments = urls.map(DemoDocument.init)
        libraryName = "OpenIntelligence Board Pack"
        question = demoPrompts.first ?? question
        ingestResult = nil
        queryResult = nil
    }

    func removeDocument(_ document: DemoDocument) {
        selectedDocuments.removeAll { $0.id == document.id }
        ingestResult = nil
        queryResult = nil
    }

    func resetWorkspace() {
        selectedDocuments = []
        ingestResult = nil
        queryResult = nil
        libraryName = "OpenIntelligence Board Pack"
        question = demoPrompts.first ?? question
    }

    func ingestSelectedDocuments() async {
        guard !selectedDocuments.isEmpty else {
            alert = DemoAlert(title: "No Documents Selected", message: "Choose at least one PDF or text file before indexing the library.")
            return
        }

        isIngesting = true
        defer { isIngesting = false }

        let engine = makeEngine()
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
            let result = try await engine.ingest(
                OIIngestRequest(
                    urls: selectedDocuments.map(\.url),
                    libraryName: trimmedLibraryName.nilIfEmpty
                )
            )

            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                ingestResult = result
            }
        } catch {
            alert = DemoAlert(title: "Indexing Failed", message: error.localizedDescription)
        }
    }

    func runQuery() async {
        refreshAvailability()

        guard availability == .available else {
            alert = DemoAlert(title: "Device Not Ready", message: readinessMessage)
            return
        }

        guard !trimmedQuestion.isEmpty else {
            alert = DemoAlert(title: "No Question Entered", message: "Write a question before running the grounded query.")
            return
        }

        isQuerying = true
        defer { isQuerying = false }

        do {
            let result = try await makeEngine().query(
                OIQueryRequest(
                    question: trimmedQuestion,
                    libraryName: trimmedLibraryName.nilIfEmpty,
                    topK: topK
                )
            )

            withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                queryResult = result
            }
        } catch {
            alert = DemoAlert(title: "Query Failed", message: error.localizedDescription)
        }
    }

    private func makeEngine() -> OIEngine {
        OIEngine(
            configuration: OIEngineConfiguration(
                allowPrivateCloudCompute: allowPrivateCloudCompute,
                executionContext: executionContext
            )
        )
    }

    private var trimmedQuestion: String {
        question.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedLibraryName: String {
        libraryName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func demoURL(for item: DemoPackItem) -> URL? {
        Bundle.main.url(forResource: item.resourceName, withExtension: "txt", subdirectory: "DemoAssets")
    }
}

private struct DemoDocument: Identifiable, Equatable {
    let id = UUID()
    let url: URL

    init(url: URL) {
        self.url = url
    }

    var name: String {
        url.deletingPathExtension().lastPathComponent
    }
}

private struct DemoAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct DemoPackItem: Identifiable {
    let id = UUID()
    let resourceName: String
    let title: String
    let summary: String
}

private struct DemoBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    DemoPalette.shell,
                    DemoPalette.wash,
                    Color.white
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(DemoPalette.coral.opacity(0.12))
                .frame(width: 340, height: 340)
                .blur(radius: 12)
                .offset(x: 130, y: -250)

            Circle()
                .fill(DemoPalette.teal.opacity(0.1))
                .frame(width: 300, height: 300)
                .blur(radius: 18)
                .offset(x: -150, y: 320)
        }
    }
}

private struct DemoCard<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.84))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.9), lineWidth: 1)
        )
        .shadow(color: DemoPalette.ink.opacity(0.06), radius: 20, x: 0, y: 12)
    }
}

private struct DemoMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.custom("AvenirNext-Bold", size: 11))
                .tracking(1.1)
                .foregroundStyle(DemoPalette.ink.opacity(0.45))
            Text(value)
                .font(.custom("AvenirNext-DemiBold", size: 18))
                .foregroundStyle(DemoPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(DemoPalette.paper)
        )
    }
}

private struct DemoStamp: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label)
            .font(.custom("AvenirNextCondensed-Bold", size: 16))
            .tracking(1.2)
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(tint.opacity(0.4), lineWidth: 1.5)
            )
    }
}

private struct StatusPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.custom("AvenirNext-Bold", size: 10))
                .tracking(1.1)
                .foregroundStyle(DemoPalette.ink.opacity(0.42))
            Text(value)
                .font(.custom("AvenirNext-DemiBold", size: 14))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(tint.opacity(0.1))
        )
    }
}

private struct PromptChip: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.custom("AvenirNext-Medium", size: 14))
                .foregroundStyle(DemoPalette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.88))
                )
                .overlay(
                    Capsule()
                        .stroke(DemoPalette.ink.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct DemoActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let isProminent: Bool
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill((isProminent ? Color.white : tint.opacity(0.12)))
                        .frame(width: 42, height: 42)
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isProminent ? tint : tint)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.custom("AvenirNext-DemiBold", size: 16))
                        .foregroundStyle(isProminent ? Color.white : DemoPalette.ink)
                    Text(subtitle)
                        .font(.custom("AvenirNext-Regular", size: 13))
                        .foregroundStyle(isProminent ? Color.white.opacity(0.78) : DemoPalette.ink.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isProminent ? tint : Color.white.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isProminent ? tint.opacity(0.1) : DemoPalette.ink.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
    }
}

private struct EmptyStateCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(DemoPalette.teal)
            Text(title)
                .font(.custom("AvenirNext-DemiBold", size: 16))
                .foregroundStyle(DemoPalette.ink)
            Text(message)
                .font(.custom("AvenirNext-Regular", size: 14))
                .foregroundStyle(DemoPalette.ink.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(DemoPalette.paper)
        )
    }
}

private struct DemoPackRow: View {
    let item: DemoPackItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(DemoPalette.coral.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: "doc.richtext")
                    .foregroundStyle(DemoPalette.coral)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.custom("AvenirNext-DemiBold", size: 15))
                    .foregroundStyle(DemoPalette.ink)
                Text(item.summary)
                    .font(.custom("AvenirNext-Regular", size: 13))
                    .foregroundStyle(DemoPalette.ink.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.9))
        )
    }
}

private struct CitationCard: View {
    let citation: OICitation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(citation.source)
                    .font(.custom("AvenirNext-DemiBold", size: 15))
                    .foregroundStyle(DemoPalette.ink)

                if let page = citation.page {
                    Text("p. \(page)")
                        .font(.custom("AvenirNext-DemiBold", size: 12))
                        .foregroundStyle(DemoPalette.teal)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(DemoPalette.teal.opacity(0.12))
                        )
                }
            }

            if let quote = citation.quote, !quote.isEmpty {
                Text("“\(quote)”")
                    .font(.custom("AvenirNext-Regular", size: 15))
                    .foregroundStyle(DemoPalette.ink.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(DemoPalette.ink.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct SummaryStrip: View {
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.custom("AvenirNext-Bold", size: 11))
                .tracking(1.1)
                .foregroundStyle(tint)
            Text(detail)
                .font(.custom("AvenirNext-Regular", size: 14))
                .foregroundStyle(DemoPalette.ink.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(tint.opacity(0.1))
        )
    }
}

private enum DemoPalette {
    static let shell = Color(red: 0.99, green: 0.96, blue: 0.92)
    static let wash = Color(red: 0.92, green: 0.96, blue: 0.95)
    static let paper = Color(red: 0.98, green: 0.97, blue: 0.95)
    static let ink = Color(red: 0.12, green: 0.16, blue: 0.18)
    static let teal = Color(red: 0.13, green: 0.45, blue: 0.46)
    static let coral = Color(red: 0.87, green: 0.38, blue: 0.24)
    static let moss = Color(red: 0.33, green: 0.52, blue: 0.29)
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
