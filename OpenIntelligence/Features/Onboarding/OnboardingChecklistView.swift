import SwiftUI

// MARK: - Display Helpers

private func fmtNumber(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1000 { return String(format: "%.1fK", Double(n) / 1000) }
    return "\(n)"
}

private func fmtMs(_ ms: Int) -> String {
    if ms >= 60000 { return String(format: "%.1fm", Double(ms) / 60000) }
    if ms >= 1000 { return String(format: "%.1fs", Double(ms) / 1000) }
    return "\(ms)ms"
}

// MARK: - Pipeline Log Entry

private struct PipelineLogEntry: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let icon: String
    let color: Color
    let text: String
}

// MARK: - OnboardingChecklistView

/// Full-screen onboarding: 2-page flow.
/// Page 1 - Welcome with real-world use cases.
/// Page 2 - Live pipeline theater: compact metrics dashboard + streaming log.
struct OnboardingChecklistView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStateStore
    @ObservedObject var ragService: RAGService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onOpenSettings: () -> Void
    let onOpenChat: () -> Void

    @State private var currentPage = 0
    private let totalPages = 2

    // Staggered entrance animation
    @State private var showHeadline = false
    @State private var showSubtitle = false
    @State private var cardsRevealed = 0

    // Processing state
    @State private var hasSentImportRequest = false
    @State private var isProcessing = false
    @State private var processingStatus = "Preparing sample workspace..."
    @State private var processingComplete = false
    @State private var processingFailed = false
    @State private var pulsePhase = 0.0

    // Streaming log
    @State private var logEntries: [PipelineLogEntry] = []
    @State private var lastSnapshotPerItem: [UUID: MetricsSnapshot] = [:]

    var body: some View {
        ZStack {
            SplashBackdrop()

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    Button {
                        DSHaptics.light()
                        onboardingStore.skipPermanently()
                        onOpenChat()
                    } label: {
                        Text("Skip")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Skip onboarding")
                }
                .padding(.top, 16)
                .padding(.trailing, 8)

                // Page content
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    pipelineTheaterPage.tag(1)
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
                #endif
                .animation(.easeInOut(duration: 0.4), value: currentPage)

                // Bottom navigation
                bottomNavigation
            }
        }
        .onAppear { animateEntrance() }
        .onChange(of: ragService.ingestionItems) { _, newItems in
            diffAndEmitLogEntries(newItems)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Bottom Navigation

    private var bottomNavigation: some View {
        VStack(spacing: 20) {
            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { index in
                    Capsule()
                        .fill(index == currentPage ? Color.white : Color.white.opacity(0.3))
                        .frame(width: index == currentPage ? 24 : 8, height: 8)
                        .animation(.spring(response: 0.3), value: currentPage)
                }
            }
            .opacity(isProcessing && !processingComplete ? 0 : 1)

            if currentPage == 0 {
                Button {
                    DSHaptics.medium()
                    withAnimation(.easeInOut(duration: 0.4)) { currentPage = 1 }
                    startWithSamples()
                } label: {
                    HStack(spacing: 8) {
                        Text("See It in Action").font(.headline)
                        Image(systemName: "play.fill").font(.system(size: 13))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)

                Button {
                    DSHaptics.light()
                    onboardingStore.skipPermanently()
                    onOpenChat()
                } label: {
                    Text("I'll add my own documents")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            } else if processingComplete {
                Button {
                    DSHaptics.medium()
                    onboardingStore.markOnboardingCompleted()
                    onOpenChat()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.text.bubble.right.fill").font(.system(size: 14))
                        Text("Start Asking").font(.headline)
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if processingFailed {
                Button {
                    DSHaptics.medium()
                    processingFailed = false
                    startWithSamples()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 13))
                        Text("Retry").font(.headline)
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
            } else {
                Color.clear.frame(height: 52)
            }
        }
        .padding(.bottom, 48)
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("Built for Your Files")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                )
                .padding(.bottom, 18)
                .opacity(showHeadline ? 1 : 0)
                .offset(y: showHeadline ? 0 : 8)

            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color.accentColor.opacity(0.3), Color.purple.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 100, height: 100)
                    .blur(radius: 20)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.8)], startPoint: .top, endPoint: .bottom))
            }
            .padding(.bottom, 16)
            .opacity(showHeadline ? 1 : 0)
            .offset(y: showHeadline ? 0 : 10)

            VStack(spacing: 10) {
                Text("Your documents.\nClear answers.")
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .opacity(showHeadline ? 1 : 0)
                    .offset(y: showHeadline ? 0 : 15)

                Text("Import PDFs, Office files, scans, images, code, and transcripts. Every answer stays tied to the source.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                    .opacity(showSubtitle ? 1 : 0)
                    .offset(y: showSubtitle ? 0 : 10)
            }

            Spacer().frame(height: 32)

            VStack(spacing: 12) {
                UseCaseCard(icon: "tag.fill", iconColor: .blue, docType: "Product Guide", exampleQuestion: "What file types does OpenIntelligence handle best?")
                    .opacity(cardsRevealed > 0 ? 1 : 0).offset(y: cardsRevealed > 0 ? 0 : 20)
                UseCaseCard(icon: "cpu.fill", iconColor: .orange, docType: "RAG Architecture", exampleQuestion: "How does OpenIntelligence work around the 4,096-token limit?")
                    .opacity(cardsRevealed > 1 ? 1 : 0).offset(y: cardsRevealed > 1 ? 0 : 20)
                UseCaseCard(icon: "lock.shield.fill", iconColor: .purple, docType: "Apple Intelligence & PCC", exampleQuestion: "When does processing stay on-device, and when does Apple Private Cloud Compute step in?")
                    .opacity(cardsRevealed > 2 ? 1 : 0).offset(y: cardsRevealed > 2 ? 0 : 20)
            }
            .padding(.horizontal, 28)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Page 2: Pipeline Theater

    private var pipelineTheaterPage: some View {
        VStack(spacing: 0) {
            // Compact header
            VStack(spacing: 4) {
                Text("Watch your library come online")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(stageExplainer)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut(duration: 0.3), value: stageExplainer)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            // Compact pipeline capsules
            pipelineProgressStrip
                .padding(.horizontal, 20)
                .padding(.top, 10)

            // Live metrics
            if isProcessing || processingComplete {
                liveMetricsDashboard
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Active documents — simple text lines
            if !ragService.ingestionItems.isEmpty {
                activeDocsTicker
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
            } else if isProcessing {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.6).tint(.white)
                    Text(processingStatus).font(.caption).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }

            // Streaming log ticker (fixed-height, last few entries)
            if !logEntries.isEmpty && !processingComplete {
                logTickerView
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }

            Spacer(minLength: 8)

            // Completion
            if processingComplete {
                completionView
                    .padding(.horizontal, 20)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Live Metrics Dashboard

    private var liveMetricsDashboard: some View {
        let items = ragService.ingestionItems
        let words = items.reduce(0) { $0 + $1.metrics.totalWords }
        let chunks = items.reduce(0) { $0 + $1.metrics.chunkCount }
        let vectors = items.reduce(0) { $0 + $1.metrics.embeddingsGenerated }
        let timeMs = items.reduce(0) { $0 + $1.metrics.totalTimeMs }

        return HStack(spacing: 0) {
            dashCounter(value: fmtNumber(words), label: "Words", icon: "textformat", color: .orange)
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 28)
            dashCounter(value: fmtNumber(chunks), label: "Chunks", icon: "square.split.2x2", color: .purple)
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 28)
            dashCounter(value: fmtNumber(vectors), label: "Vectors", icon: "brain.head.profile", color: .green)
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 28)
            dashCounter(value: timeMs > 0 ? fmtMs(timeMs) : "\u{2014}", label: "Time", icon: "clock", color: .cyan)
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func dashCounter(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                    .foregroundStyle(color)
                    .symbolEffect(.pulse, options: .repeating, value: isProcessing && !processingComplete)
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Compact Pipeline Strip

    private var pipelineProgressStrip: some View {
        HStack(spacing: 3) {
            pipelineCapsule("Extract", icon: "doc.text", phase: .extract)
            chevronDot
            pipelineCapsule("Chunk", icon: "rectangle.split.3x1", phase: .chunk)
            chevronDot
            pipelineCapsule("Embed", icon: "brain.head.profile", phase: .embed)
            chevronDot
            pipelineCapsule("Index", icon: "magnifyingglass", phase: .index)
        }
    }

    @ViewBuilder
    private func pipelineCapsule(_ label: String, icon: String, phase: PipelinePhase) -> some View {
        let isActive = currentPipelinePhase == phase
        let isComplete = isPipelinePhaseComplete(phase)
        let pulse = isActive && !reduceMotion
        
        HStack(spacing: 3) {
            Image(systemName: isComplete ? "checkmark" : icon)
                .font(.system(size: 7, weight: .bold))
                .symbolEffect(.bounce, value: isComplete)
            Text(label)
                .font(.system(size: 9, weight: isActive ? .bold : .medium))
        }
        .foregroundStyle(isComplete ? .white : (isActive ? .white : .white.opacity(0.4)))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            ZStack {
                Capsule().fill(
                    isComplete ? Color.green.opacity(0.5) :
                        (isActive ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.06))
                )
                
                if pulse {
                    Capsule()
                        .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
                        .scaleEffect(1.0 + CGFloat(sin(pulsePhase)) * 0.1)
                        .opacity(0.5 - sin(pulsePhase) * 0.5)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isActive)
        .animation(.easeInOut(duration: 0.3), value: isComplete)
    }

    private var chevronDot: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 6, weight: .bold))
            .foregroundStyle(.white.opacity(0.2))
    }

    // MARK: - Active Documents Ticker

    private var activeDocsTicker: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(ragService.ingestionItems) { item in
                HStack(spacing: 6) {
                    Image(systemName: item.stage == .complete ? "checkmark.circle.fill" : (item.stage == .failed ? "xmark.circle.fill" : "circle.fill"))
                        .font(.system(size: 7))
                        .foregroundStyle(item.stage == .complete ? .green : (item.stage == .failed ? .red : .accentColor))
                        .frame(width: 10)
                    Text(item.filename)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(item.stage.isTerminal ? 0.5 : 0.9))
                        .lineLimit(1)
                    if !item.stage.isTerminal {
                        Text("\u{2014} \(item.stage.displayName)")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                        if let detail = compactDetail(for: item) {
                            Text("\u{00b7} \(detail)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func compactDetail(for item: IngestionItem) -> String? {
        let m = item.metrics
        switch item.stage {
        case .extracting: return m.totalWords > 0 ? "\(fmtNumber(m.totalWords))w" : nil
        case .chunking: return m.chunkCount > 0 ? "\(m.chunkCount) chunks" : nil
        case .embedding: return m.embeddingsGenerated > 0 ? "\(m.embeddingsGenerated)/\(m.chunkCount)" : nil
        default: return nil
        }
    }

    // MARK: - Log Ticker (Fixed Height)

    private var logTickerView: some View {
        let visible = Array(logEntries.suffix(6))

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "terminal")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                Text("PIPELINE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                Spacer()
                Text("\(logEntries.count)")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
            }
            .padding(.bottom, 3)

            ZStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(visible) { entry in
                        PipelineLogRow(entry: entry)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }

                if logEntries.count > 6 {
                    LinearGradient(
                        colors: [Color(red: 0.04, green: 0.07, blue: 0.15).opacity(0.95), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 14)
                    .allowsHitTesting(false)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .animation(.easeOut(duration: 0.2), value: logEntries.count)
    }

    // MARK: - Completion View

    private var completionView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.green.opacity(0.15)).frame(width: 64, height: 64)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(LinearGradient(colors: [.green, .green.opacity(0.8)], startPoint: .top, endPoint: .bottom))
            }

            VStack(spacing: 6) {
                Text("Your documents are ready")
                    .font(.title3.bold()).foregroundStyle(.white)

                let items = ragService.ingestionItems
                let totalChunks = items.reduce(0) { $0 + $1.metrics.chunkCount }
                let totalWords = items.reduce(0) { $0 + $1.metrics.totalWords }
                if totalChunks > 0 {
                    Text("\(items.count) docs \u{00b7} \(totalWords.formatted()) words \u{00b7} \(totalChunks) chunks")
                        .font(.caption).foregroundStyle(.white.opacity(0.5))
                }
            }

            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.horizontal, 16)

            VStack(spacing: 10) {
                Text("Try asking something like:")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.6))
                VStack(spacing: 6) {
                    ExampleQuestionPill(text: "How does OpenIntelligence work around the 4,096-token limit?", icon: "cpu.fill", color: .orange)
                    ExampleQuestionPill(text: "What file types does OpenIntelligence handle best?", icon: "tag.fill", color: .blue)
                    ExampleQuestionPill(text: "When does processing stay on-device, and when does Apple Private Cloud Compute step in?", icon: "lock.shield.fill", color: .purple)
                }
            }
        }
    }

    // MARK: - Log Diffing Engine

    private struct MetricsSnapshot: Equatable {
        let stage: IngestionStage
        let words: Int
        let chunks: Int
        let vectors: Int
        let tables: Int
        let lists: Int
        let headers: Int
        let entities: Int
        let pages: Int
        let ocrPages: Int
        let domain: String
        let sections: Int
        let topics: Int
        let embBoundaries: Int
        let vision: Bool
        let totalTime: Int

        init(from item: IngestionItem) {
            stage = item.stage
            words = item.metrics.totalWords
            chunks = item.metrics.chunkCount
            vectors = item.metrics.embeddingsGenerated
            tables = item.metrics.tablesExtracted
            lists = item.metrics.listsExtracted
            headers = item.metrics.titlesDetected
            entities = item.metrics.entitiesExtracted
            pages = item.metrics.pageCount
            ocrPages = item.metrics.ocrPagesCount
            domain = item.metrics.documentDomain
            sections = item.metrics.sectionsDetected
            topics = item.metrics.topicBoundaries
            embBoundaries = item.metrics.embeddingBoundaries
            vision = item.metrics.usedStructuredParsing
            totalTime = item.metrics.totalTimeMs
        }
    }

    private func diffAndEmitLogEntries(_ items: [IngestionItem]) {
        var newEntries: [PipelineLogEntry] = []

        for item in items {
            let current = MetricsSnapshot(from: item)
            let previous = lastSnapshotPerItem[item.id]

            // Stage change
            if previous == nil || previous?.stage != current.stage {
                if let entry = logEntryForStageChange(item: item) {
                    newEntries.append(entry)
                }
            }

            // Vision detected (one-shot)
            if current.vision && previous?.vision != true {
                var parts = ["RecognizeDocuments"]
                if current.pages > 0 { parts.append("\(current.pages) pg") }
                newEntries.append(PipelineLogEntry(icon: "eye.fill", color: .green, text: "[\(item.filename)] Vision \u{00b7} " + parts.joined(separator: " \u{00b7} ")))
            }

            // Tables/Lists/Headers
            if current.tables > 0 && current.tables != previous?.tables {
                var parts: [String] = []
                parts.append("\(current.tables) table\(current.tables > 1 ? "s" : "")")
                if current.lists > 0 { parts.append("\(current.lists) list\(current.lists > 1 ? "s" : "")") }
                if current.headers > 0 { parts.append("\(current.headers) header\(current.headers > 1 ? "s" : "")") }
                newEntries.append(PipelineLogEntry(icon: "tablecells", color: .cyan, text: "[\(item.filename)] Layout \u{00b7} " + parts.joined(separator: " \u{00b7} ")))
            }

            // Words extracted
            if current.words > 0 && current.words != previous?.words && current.stage == .extracting {
                var parts = ["\(current.words.formatted()) words"]
                if current.pages > 0 { parts.append("\(current.pages) pg") }
                if current.ocrPages > 0 { parts.append("\(current.ocrPages) OCR") }
                newEntries.append(PipelineLogEntry(icon: "doc.text.magnifyingglass", color: .blue, text: "[\(item.filename)] Extract \u{00b7} " + parts.joined(separator: " \u{00b7} ")))
            }

            // Chunks created
            if current.chunks > 0 && current.chunks != previous?.chunks {
                var parts = ["\(current.chunks) chunks"]
                let avg = item.metrics.avgChunkWords
                if avg > 0 { parts.append("\(avg)w avg") }
                if current.sections > 0 { parts.append("\(current.sections) sec") }
                if current.topics > 0 { parts.append("\(current.topics) topics") }
                if current.embBoundaries > 0 { parts.append("\(current.embBoundaries) \u{2207}sim") }
                newEntries.append(PipelineLogEntry(icon: "square.split.2x2", color: .purple, text: "[\(item.filename)] Chunk \u{00b7} " + parts.joined(separator: " \u{00b7} ")))
            }

            // Entities extracted
            if current.entities > 0 && current.entities != previous?.entities {
                var parts = ["\(current.entities) entities"]
                let top = item.metrics.topEntities.prefix(3)
                if !top.isEmpty { parts.append(top.joined(separator: ", ")) }
                newEntries.append(PipelineLogEntry(icon: "tag", color: .mint, text: "[\(item.filename)] NER \u{00b7} " + parts.joined(separator: " \u{00b7} ")))
            }

            // Domain classified
            if !current.domain.isEmpty && current.domain != previous?.domain {
                newEntries.append(PipelineLogEntry(icon: "brain", color: .indigo, text: "[\(item.filename)] Classified \u{2192} \(current.domain)"))
            }

            // Embeddings generated
            if current.vectors > 0 && current.vectors != previous?.vectors {
                var parts = ["\(current.vectors) \u{2192} \(item.metrics.embeddingDimension)D"]
                let provider = item.metrics.embeddingProvider
                if !provider.isEmpty { parts.append(provider) }
                newEntries.append(PipelineLogEntry(icon: "brain.head.profile", color: .green, text: "[\(item.filename)] Embed \u{00b7} " + parts.joined(separator: " \u{00b7} ")))
            }

            // Done
            if current.stage == .complete && previous?.stage != .complete {
                let time = current.totalTime > 0 ? " \u{00b7} \(fmtMs(current.totalTime))" : ""
                newEntries.append(PipelineLogEntry(icon: "checkmark.circle.fill", color: .green, text: "[\(item.filename)] Done\(time)"))
            }

            lastSnapshotPerItem[item.id] = current
        }

        if !newEntries.isEmpty {
            withAnimation(.easeOut(duration: 0.2)) {
                logEntries.append(contentsOf: newEntries)
                if logEntries.count > 100 {
                    logEntries.removeFirst(logEntries.count - 100)
                }
            }
        }
    }

    private func logEntryForStageChange(item: IngestionItem) -> PipelineLogEntry? {
        let fn = item.filename
        switch item.stage {
        case .queued: return PipelineLogEntry(icon: "clock", color: .white.opacity(0.5), text: "[\(fn)] Queued")
        case .loading: return PipelineLogEntry(icon: "arrow.down.circle", color: .white.opacity(0.6), text: "[\(fn)] Loading file...")
        case .transcribing: return PipelineLogEntry(icon: "waveform", color: .orange, text: "[\(fn)] Transcribing audio...")
        case .extracting: return PipelineLogEntry(icon: "doc.text.magnifyingglass", color: .blue, text: "[\(fn)] Extracting text...")
        case .chunking: return PipelineLogEntry(icon: "rectangle.split.3x1", color: .purple, text: "[\(fn)] Semantic chunking...")
        case .analyzing: return PipelineLogEntry(icon: "brain", color: .indigo, text: "[\(fn)] Corpus intelligence analysis...")
        case .adapting: return PipelineLogEntry(icon: "gearshape.2", color: .yellow, text: "[\(fn)] Adapting config...")
        case .reindexing: return PipelineLogEntry(icon: "arrow.triangle.2.circlepath", color: .orange, text: "[\(fn)] Re-indexing with adapted config...")
        case .embedding: return PipelineLogEntry(icon: "point.3.connected.trianglepath.dotted", color: .green, text: "[\(fn)] Generating embeddings...")
        case .indexing: return PipelineLogEntry(icon: "magnifyingglass", color: .teal, text: "[\(fn)] BM25 + HNSW indexing...")
        case .storing: return PipelineLogEntry(icon: "externaldrive", color: .gray, text: "[\(fn)] Persisting to vector store...")
        case .complete: return nil
        case .cancelled: return PipelineLogEntry(icon: "slash.circle.fill", color: .orange, text: "[\(fn)] Cancelled")
        case .failed:
            let err = item.errorMessage ?? "Unknown error"
            return PipelineLogEntry(icon: "xmark.circle.fill", color: .red, text: "[\(fn)] Failed: \(err)")
        }
    }

    // MARK: - Stage Explainer

    private var stageExplainer: String {
        if !ragService.ingestionItems.isEmpty {
            let active = ragService.ingestionItems.filter { !$0.stage.isTerminal }
            if let first = active.first {
                return "Currently \(first.stage.displayName.lowercased()) '\(first.filename)'..."
            }
        }
        
        switch currentPipelinePhase {
        case .extract: return "Reading every word from your documents..."
        case .chunk: return "Breaking content into searchable pieces..."
        case .embed: return "Converting text to AI-readable vectors..."
        case .index: return "Building your personal search index..."
        case .none: return isProcessing ? "Preparing the pipeline..." : "Ready to process"
        }
    }

    // MARK: - Animations

    private func animateEntrance() {
        if reduceMotion {
            showHeadline = true; showSubtitle = true; cardsRevealed = 3
            return
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.2)) { showHeadline = true }
        withAnimation(.easeOut(duration: 0.5).delay(0.5)) { showSubtitle = true }
        withAnimation(.easeOut(duration: 0.5).delay(0.7)) { cardsRevealed = 1 }
        withAnimation(.easeOut(duration: 0.5).delay(0.9)) { cardsRevealed = 2 }
        withAnimation(.easeOut(duration: 0.5).delay(1.1)) { cardsRevealed = 3 }
    }

    // MARK: - Computed Properties

    private enum PipelinePhase: Int, Comparable {
        case none = 0, extract = 1, chunk = 2, embed = 3, index = 4
        static func < (lhs: PipelinePhase, rhs: PipelinePhase) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private var currentPipelinePhase: PipelinePhase {
        let items = ragService.ingestionItems
        guard !items.isEmpty else { return .none }
        for item in items where !item.stage.isTerminal {
            switch item.stage {
            case .queued, .loading, .transcribing, .extracting: return .extract
            case .chunking, .analyzing, .adapting, .reindexing: return .chunk
            case .embedding: return .embed
            case .indexing, .storing: return .index
            default: continue
            }
        }
        return .none
    }

    private func isPipelinePhaseComplete(_ phase: PipelinePhase) -> Bool {
        let items = ragService.ingestionItems
        guard !items.isEmpty else { return false }
        if items.allSatisfy({ $0.stage.isTerminal }) { return true }
        return currentPipelinePhase > phase
    }

    // MARK: - Actions

    private func startWithSamples() {
        guard !hasSentImportRequest else { return }
        hasSentImportRequest = true
        processingFailed = false
        withAnimation(.easeInOut(duration: 0.3)) { 
            isProcessing = true
            logEntries.append(PipelineLogEntry(icon: "bolt.fill", color: .yellow, text: "Initializing RAG pipeline..."))
            logEntries.append(PipelineLogEntry(icon: "doc.fill", color: .blue, text: "Scanning 3 curated sample documents..."))
            logEntries.append(PipelineLogEntry(icon: "cpu", color: .purple, text: "Waking Neural Engine..."))
        }
        
        withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
            pulsePhase = .pi * 2
        }

        Task { @MainActor in
            do {
                try await SampleDocumentManager.shared.importSamples(into: ragService) { current, total, filename in
                    Task { @MainActor in
                        processingStatus = "Processing \(filename)..."
                    }
                }

                DSHaptics.success()
                withAnimation(.easeInOut(duration: 0.5)) { processingComplete = true }
                ragService.resetLLMSession()

            } catch {
                Log.error("Sample import failed: \(error)", category: .initialization)
                processingStatus = "Import failed \u{2014} tap Retry"
                DSHaptics.error()
                withAnimation(.easeInOut(duration: 0.3)) {
                    isProcessing = false
                    processingFailed = true
                }
                hasSentImportRequest = false
            }
        }
    }
}

// MARK: - Pipeline Log Row

private struct PipelineLogRow: View {
    let entry: PipelineLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: entry.icon)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(entry.color)
                .frame(width: 12, alignment: .center)

            Text(entry.text)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Text(timestampString(entry.timestamp))
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.2))
        }
        .padding(.vertical, 2)
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "ss.SSS"
        return f
    }()

    private func timestampString(_ date: Date) -> String {
        Self.timestampFormatter.string(from: date)
    }
}

// MARK: - Use Case Card

private struct UseCaseCard: View {
    let icon: String
    let iconColor: Color
    let docType: String
    let exampleQuestion: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(iconColor.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(iconColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(docType).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text("\"\(exampleQuestion)\"").font(.caption).foregroundStyle(.white.opacity(0.6)).italic().lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        )
    }
}

// MARK: - Example Question Pill

private struct ExampleQuestionPill: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(color)
            Text(text).font(.subheadline).foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(color.opacity(0.2), lineWidth: 1))
        )
    }
}

// MARK: - Splash Backdrop

private struct SplashBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.05, blue: 0.12), Color(red: 0.05, green: 0.11, blue: 0.22), Color(red: 0.08, green: 0.16, blue: 0.31)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).ignoresSafeArea()
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.35)).frame(width: 320, height: 320).blur(radius: 140).offset(x: -140, y: -200)
                Circle().fill(Color.purple.opacity(0.25)).frame(width: 260, height: 260).blur(radius: 120).offset(x: 140, y: 160)
                Circle().fill(Color.orange.opacity(0.18)).frame(width: 200, height: 200).blur(radius: 100).offset(x: -80, y: 260)
            }
            .compositingGroup()
            .ignoresSafeArea()
            Color.black.opacity(0.35).ignoresSafeArea()
        }
    }
}

#Preview {
    OnboardingChecklistView(
        ragService: RAGService(),
        onOpenSettings: {},
        onOpenChat: {}
    )
    .environmentObject(OnboardingStateStore())
}
