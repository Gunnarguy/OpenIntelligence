import SwiftUI

/// Full-screen onboarding splash shown on first launch.
/// Clean, benefit-focused design that guides users to value quickly.
/// Sample documents import in background after dismissal - no blocking UI.
struct OnboardingChecklistView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStateStore
    @EnvironmentObject private var entitlementStore: EntitlementStore
    @ObservedObject var ragService: RAGService
    let onOpenSettings: () -> Void
    let onOpenChat: () -> Void

    @State private var currentPage = 0

    private let totalPages = 3

    var body: some View {
        ZStack {
            SplashBackdrop()

            VStack(spacing: 0) {
                // Skip button - permanent skip on final page
                HStack {
                    Spacer()
                    Button {
                        if currentPage == totalPages - 1 {
                            // On final page, skip permanently
                            DSHaptics.light()
                            onboardingStore.skipPermanently()
                            onOpenChat()
                        } else {
                            DSHaptics.soft()
                            onboardingStore.dismissChecklist()
                        }
                    } label: {
                        Text("Skip")
                            .font(.body.weight(.medium))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .opacity(isProcessing ? 0 : 1)
                    .disabled(isProcessing)
                }
                .padding(.top, 16)
                .padding(.trailing, 8)

                Spacer()

                // Page content
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    featuresPage.tag(1)
                    getStartedPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentPage)
                .opacity(isProcessing ? 0.3 : 1)
                .blur(radius: isProcessing ? 8 : 0)

                Spacer()

                // Page indicator and navigation
                VStack(spacing: 24) {
                    // Custom page dots
                    HStack(spacing: 8) {
                        ForEach(0 ..< totalPages, id: \.self) { index in
                            Circle()
                                .fill(index == currentPage ? Color.white : Color.white.opacity(0.3))
                                .frame(width: 8, height: 8)
                                .scaleEffect(index == currentPage ? 1.2 : 1.0)
                                .animation(.spring(response: 0.3), value: currentPage)
                        }
                    }
                    .opacity(isProcessing ? 0 : 1)

                    // Navigation buttons
                    if currentPage < totalPages - 1 {
                        Button {
                            DSHaptics.selection()
                            withAnimation { currentPage += 1 }
                        } label: {
                            Text("Continue")
                                .font(.headline)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 32)
                    } else {
                        // Final page - primary CTA
                        Button {
                            DSHaptics.medium()
                            startWithSamples()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.right.circle.fill")
                                Text("Get Started")
                                    .font(.headline)
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 32)
                        .disabled(isProcessing)
                        .opacity(isProcessing ? 0 : 1)

                        Button {
                            DSHaptics.light()
                            onboardingStore.skipPermanently()
                            onOpenChat()
                        } label: {
                            Text("I'll add my own documents")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                        .disabled(isProcessing)
                        .opacity(isProcessing ? 0 : 1)
                    }
                }
                .padding(.bottom, 48)
            }

            // Processing overlay
            if isProcessing {
                processingOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Processing Overlay

    private var processingOverlay: some View {
        VStack(spacing: 20) {
            // Header with pulsing icon
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.2))
                        .frame(width: 48, height: 48)
                        .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulseAnimation)

                    Image(systemName: "cpu")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.accentColor, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("RAG Pipeline Active")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text(overallStatus)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("RAG Pipeline: \(overallStatus)")

                Spacer()
            }
            .padding(.horizontal, 4)

            // Pipeline legend - shows which phase is active
            HStack(spacing: 12) {
                PipelineStageBadge(
                    label: "Extract",
                    icon: "doc.text",
                    isActive: currentPipelinePhase == .extract
                )

                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.3))

                PipelineStageBadge(
                    label: "Chunk",
                    icon: "rectangle.split.3x1",
                    isActive: currentPipelinePhase == .chunk
                )

                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.3))

                PipelineStageBadge(
                    label: "Embed",
                    icon: "point.3.connected.trianglepath.dotted",
                    isActive: currentPipelinePhase == .embed
                )

                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.3))

                PipelineStageBadge(
                    label: "Index",
                    icon: "magnifyingglass",
                    isActive: currentPipelinePhase == .index
                )
            }
            .padding(.horizontal, 8)

            // Real-time ingestion queue
            if !ragService.ingestionItems.isEmpty {
                VStack(spacing: 8) {
                    ForEach(ragService.ingestionItems.prefix(5)) { item in
                        OnboardingIngestionRow(item: item)
                    }

                    if ragService.ingestionItems.count > 5 {
                        Text("+\(ragService.ingestionItems.count - 5) more...")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            } else {
                // Fallback when queue is empty but still processing
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)

                    Text(processingStatus)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))

                    Spacer()
                }
                .padding(.vertical, 8)
            }

            // Overall progress bar
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 8)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.accentColor, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, geo.size.width * overallProgress), height: 8)
                            .animation(.easeInOut(duration: 0.3), value: overallProgress)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("\(completedItemsCount)/\(totalItemsCount) documents")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))

                    Spacer()

                    Text("\(Int(overallProgress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 400)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .padding(.horizontal, 24)
        .onAppear { pulseAnimation = true }
    }

    // MARK: - Ingestion Computed Properties

    @State private var pulseAnimation = false

    private var totalItemsCount: Int {
        max(ragService.ingestionItems.count, 1)
    }

    private var completedItemsCount: Int {
        ragService.ingestionItems.filter { $0.stage == .complete }.count
    }

    /// Check if any active item is in one of the specified stages
    private func hasActiveStage(_ stages: [IngestionStage]) -> Bool {
        ragService.ingestionItems.contains { stages.contains($0.stage) }
    }

    /// Simplified pipeline phase for UI display
    private enum PipelinePhase {
        case none, extract, chunk, embed, index
    }

    /// Current pipeline phase based on active ingestion items
    private var currentPipelinePhase: PipelinePhase {
        let items = ragService.ingestionItems
        guard !items.isEmpty else { return .none }

        // Find the first non-terminal item's stage
        for item in items where !item.stage.isTerminal {
            switch item.stage {
            case .queued, .loading, .transcribing, .extracting:
                return .extract
            case .chunking, .analyzing, .adapting, .reindexing:
                return .chunk
            case .embedding:
                return .embed
            case .indexing, .storing:
                return .index
            default:
                continue
            }
        }
        return .none
    }

    private var overallProgress: Double {
        let items = ragService.ingestionItems
        guard !items.isEmpty else { return processingProgress }

        let totalProgress = items.reduce(0.0) { sum, item in
            sum + (item.progress ?? (item.stage == .complete ? 1.0 : 0.0))
        }
        return totalProgress / Double(items.count)
    }

    private var overallStatus: String {
        let items = ragService.ingestionItems
        let active = items.filter { !$0.stage.isTerminal }
        let completed = items.filter { $0.stage == .complete }
        let failed = items.filter { $0.stage == .failed }

        if failed.count > 0 {
            return "\(completed.count) done, \(failed.count) failed"
        } else if active.isEmpty && !items.isEmpty {
            return "All documents processed!"
        } else if let current = active.first {
            return current.stage.displayName
        }
        return processingStatus
    }

    // MARK: - Welcome Page

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            // App icon or logo
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.3), Color.purple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
.frame(width: 100, height: 100)
    .blur(radius: 20)

                Image(systemName: "brain.head.profile")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
.padding(.bottom, 8)

            VStack(spacing: 12) {
                Text("Welcome to OpenIntelligence")
                    .font(.title.bold())
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("Your private AI assistant that actually understands your documents.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
            Spacer()
        }
    }

    // MARK: - Features Page

    private var featuresPage: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("Built for Privacy")
                .font(.title2.bold())
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 20) {
                OnboardingFeatureRow(
                    icon: "lock.shield.fill",
                    iconColor: .green,
                    title: "100% Private",
                    description: "Everything stays on your device or Apple's secure cloud"
                )

                OnboardingFeatureRow(
                    icon: "brain.head.profile",
                    iconColor: .purple,
                    title: "Auto Intelligence",
                    description: "Automatically learns your documents to give better answers"
                )

                OnboardingFeatureRow(
                    icon: "doc.text.magnifyingglass",
                    iconColor: .blue,
                    title: "Smart Search",
                    description: "Ask questions and get answers from your own documents"
                )

                OnboardingFeatureRow(
                    icon: "airplane",
                    iconColor: .orange,
                    title: "Works in Airplane Mode",
                    description: "Search and get answers even without internet"
                )
            }
.padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Get Started Page

    private var getStartedPage: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "sparkles")
                    .font(.system(size: 36))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 12) {
                Text("Ready to Try It?")
                    .font(.title2.bold())
                    .foregroundColor(.white)

                Text("We'll add some sample documents so you can see how it works. You can remove them anytime.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Quick preview of what's included
            VStack(alignment: .leading, spacing: 12) {
                Text("Sample documents include:")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white.opacity(0.7))

                HStack(spacing: 8) {
                    SampleDocChip(title: "Pricing Guide", icon: "dollarsign.circle")
                    SampleDocChip(title: "RAG Tech Guide", icon: "cpu")
                }

                HStack(spacing: 8) {
                    SampleDocChip(title: "Private Cloud Compute", icon: "cloud.fill")
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Actions

    /// Track whether we've already triggered sample import to prevent duplicates
    @State private var hasSentImportRequest = false

    /// Show loading overlay while processing documents
    @State private var isProcessing = false

    /// Current processing status message
    @State private var processingStatus = "Preparing documents..."

    /// Processing progress (0.0 to 1.0)
    @State private var processingProgress: Double = 0.0

    private func startWithSamples() {
        guard !hasSentImportRequest else { return }
        hasSentImportRequest = true

        // Show processing overlay
        withAnimation(.easeInOut(duration: 0.3)) {
            isProcessing = true
        }

        // Import samples and wait for completion before navigating
        Task { @MainActor in
            do {
                try await SampleDocumentManager.shared.importSamples(into: ragService) { current, total, filename in
                    // Update progress on main thread
                    Task { @MainActor in
                        processingStatus = "Processing \(filename)..."
                        processingProgress = Double(current) / Double(total)
                    }
                }

                // Brief pause to show completion
                processingStatus = "Ready!"
                processingProgress = 1.0
                DSHaptics.success()
                try? await Task.sleep(for: .milliseconds(400))

                // Reset LLM session to ensure fresh context budget for first queries
                // This prevents transcript tokens from eating into context window
                ragService.resetLLMSession()

                // Mark onboarding properly completed (not skipped) for analytics
                onboardingStore.markOnboardingCompleted()
                onOpenChat()

            } catch {
                Log.error("Sample import failed: \(error)", category: .initialization)
                processingStatus = "Import failed — please try again"
                processingProgress = 0.0
                DSHaptics.error()

                // Reset so the user can try again — do NOT complete onboarding
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.easeInOut(duration: 0.3)) {
                    isProcessing = false
                }
                hasSentImportRequest = false
            }
        }
    }
}

// MARK: - Supporting Views

private struct OnboardingFeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct SampleDocChip: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(title)
                .font(.caption.weight(.medium))
        }
        .foregroundColor(.white.opacity(0.8))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.1), in: Capsule())
    }
}

private struct SplashBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.05, blue: 0.12),
                    Color(red: 0.05, green: 0.11, blue: 0.22),
                    Color(red: 0.08, green: 0.16, blue: 0.31)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(width: 320, height: 320)
                    .blur(radius: 140)
                    .offset(x: -140, y: -200)
                Circle()
                    .fill(Color.purple.opacity(0.25))
                    .frame(width: 260, height: 260)
                    .blur(radius: 120)
                    .offset(x: 140, y: 160)
                Circle()
                    .fill(Color.orange.opacity(0.18))
                    .frame(width: 200, height: 200)
                    .blur(radius: 100)
                    .offset(x: -80, y: 260)
            }
            .ignoresSafeArea()

            Color.black.opacity(0.35).ignoresSafeArea()
        }
    }
}

// MARK: - Onboarding Ingestion Row

/// Transparent, nerdy row for showing document processing pipeline during onboarding
/// Gives users a taste of the app's detailed transparency philosophy
private struct OnboardingIngestionRow: View {
    let item: IngestionItem

    private var stageIcon: String {
        switch item.stage {
        case .queued: return "clock"
        case .loading: return "arrow.down.circle"
        case .transcribing: return "waveform"
        case .extracting: return "doc.text.magnifyingglass"
        case .chunking: return "rectangle.split.3x1"
        case .analyzing: return "brain"
        case .embedding: return "point.3.connected.trianglepath.dotted"
        case .storing: return "externaldrive"
        case .adapting: return "gearshape.2"
        case .reindexing: return "arrow.triangle.2.circlepath"
        case .indexing: return "magnifyingglass"
        case .complete: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private var stageColor: Color {
        switch item.stage {
        case .complete: return .green
        case .failed: return .red
        case .queued: return .white.opacity(0.5)
        default: return .accentColor
        }
    }

    /// Real-time metrics string based on current stage
    private var metricsDetail: String? {
        let m = item.metrics

        switch item.stage {
        case .extracting:
            if m.totalWords > 0 {
                return "\(m.totalWords.formatted()) words"
            }
        case .chunking:
            if m.chunkCount > 0 {
                return "\(m.chunkCount) chunks @ ~\(m.avgChunkWords)w"
            }
        case .embedding:
            if m.embeddingsGenerated > 0 {
                return "\(m.embeddingsGenerated)/\(m.chunkCount) → 384d"
            } else if m.chunkCount > 0 {
                return "0/\(m.chunkCount) → 384d vectors"
            }
        case .indexing:
            return "BM25 + HNSW"
        case .complete:
            // Show final stats
            let timeStr = m.totalTimeMs > 0 ? "\(m.totalTimeMs)ms" : ""
            if m.chunkCount > 0 && !timeStr.isEmpty {
                return "\(m.chunkCount) chunks in \(timeStr)"
            } else if m.chunkCount > 0 {
                return "\(m.chunkCount) chunks indexed"
            }
        default:
            break
        }
        return nil
    }

    /// Pipeline progress (which stage out of total)
    private var pipelineProgress: (current: Int, total: Int)? {
        guard let idx = item.stage.pipelineIndex else { return nil }
        return (idx + 1, IngestionStage.pipelineStages.count)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Stage icon with pulse animation for active stages
            ZStack {
                if !item.stage.isTerminal {
                    Circle()
                        .fill(stageColor.opacity(0.2))
                        .frame(width: 28, height: 28)
                        .scaleEffect(1.2)
                        .opacity(0.5)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: item.stage)
                }

                Image(systemName: stageIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(stageColor)
                    .frame(width: 28, height: 28)
            }

            VStack(alignment: .leading, spacing: 2) {
                // Filename
                Text(item.filename)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)

                // Stage name + pipeline position
                HStack(spacing: 4) {
                    Text(item.stage.displayName)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(stageColor)

                    if let (current, total) = pipelineProgress {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.3))
                        Text("\(current)/\(total)")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.white.opacity(0.4))
                    }
                }

                // Metrics detail (nerdy stats)
                if let detail = metricsDetail {
                    Text(detail)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            Spacer()

            // Status indicator
            VStack(alignment: .trailing, spacing: 2) {
                if item.stage == .complete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.green)
                } else if item.stage == .failed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                } else if let progress = item.progress {
                    Text("\(Int(progress * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.white.opacity(0.6))
                } else {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.white.opacity(0.6))
                }

                // Elapsed time for active items
                if let started = item.startedAt, !item.stage.isTerminal {
                    Text(elapsedString(from: started))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.filename), \(item.stage.displayName)")
        .accessibilityValue(metricsDetail ?? "")
    }

    private func elapsedString(from start: Date) -> String {
        let elapsed = Date().timeIntervalSince(start)
        if elapsed < 1 {
            return "<1s"
        } else if elapsed < 60 {
            return String(format: "%.1fs", elapsed)
        } else {
            return String(format: "%.0fm", elapsed / 60)
        }
    }
}

// MARK: - Pipeline Stage Badge

/// Visual indicator for pipeline stages during onboarding
private struct PipelineStageBadge: View {
    let label: String
    let icon: String
    let isActive: Bool

    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Outer pulse ring for active state
                if isActive {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.4), lineWidth: 2)
                        .frame(width: 36, height: 36)
                        .scaleEffect(isPulsing ? 1.3 : 1.0)
                        .opacity(isPulsing ? 0 : 0.8)
                        .animation(.easeOut(duration: 1.0).repeatForever(autoreverses: false), value: isPulsing)
                }

                Circle()
                    .fill(isActive ? Color.accentColor : Color.white.opacity(0.1))
                    .frame(width: 32, height: 32)

                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isActive ? .white : .white.opacity(0.4))
            }
            .scaleEffect(isActive ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isActive)

            Text(label)
                .font(.system(size: 9, weight: isActive ? .bold : .medium))
                .foregroundColor(isActive ? .white : .white.opacity(0.4))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) stage")
        .accessibilityValue(isActive ? "Active" : "Inactive")
        .onAppear {
            if isActive { isPulsing = true }
        }
        .onChange(of: isActive) { _, newValue in
            isPulsing = newValue
        }
    }
}
