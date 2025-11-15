import SwiftUI

/// Full-screen onboarding splash shown on first launch.
/// Redesigned to avoid cramped overlaps on smaller devices while keeping the checklist actionable.
struct OnboardingChecklistView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStateStore
    @ObservedObject var ragService: RAGService
    let onOpenSettings: () -> Void
    let onOpenChat: () -> Void

    @State private var isImportingSamples = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            SplashBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    heroSection
                    progressCard

                    VStack(spacing: 18) {
                        ForEach(steps) { step in
                            stepCard(for: step)
                        }
                    }

                    if let errorMessage {
                        errorBanner(errorMessage)
                    }

                    actionButtons
                }
                .padding(24)
                .frame(maxWidth: 520)
                .background(
                    .ultraThinMaterial.opacity(0.95),
                    in: RoundedRectangle(cornerRadius: 32, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, 24)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Title + tagline with a quick-close affordance.
    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Private RAG workspace", systemImage: "lock.shield")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.12), in: Capsule())
                        .foregroundColor(.white)
                    Text("Welcome to OpenIntelligence")
                        .font(.title2.bold())
                        .foregroundStyle(Color.white)
                    Text("Take two minutes to prime the retrieval engine so the very first chat already knows your docs.")
                        .font(.callout)
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                Spacer(minLength: 0)
                Button {
                    onboardingStore.dismissChecklist()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.semibold))
                        .padding(10)
                        .background(Color.white.opacity(0.12), in: Circle())
                        .foregroundColor(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
            }

            Divider()
                .background(Color.white.opacity(0.2))
        }
    }

    /// Progress summary with contextual copy.
    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(.yellow)
                Text("Setup progress")
                    .font(.headline)
                    .foregroundStyle(Color.white)
                Spacer()
                Text("\(completedStepCount)/\(steps.count) complete")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
            }
            ProgressView(value: progressFraction)
                .tint(.accentColor)
                .background(
                    Capsule().fill(Color.white.opacity(0.12))
                )
            Text("Finish the checklist to import curated knowledge, pick your go-to model, and land your first answer with confidence.")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.8))
        }
        .padding(20)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    /// Renders the individual checklist cards.
    private func stepCard(for step: ChecklistStep) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(step.title, systemImage: step.systemImage)
                    .font(.headline)
                    .foregroundStyle(Color.white)
                Spacer()
                statusChip(for: step)
            }

            Text(step.caption)
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.8))

            if step.kind == .importSamples && isImportingSamples {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)
                    Text("Importing sample workspace…")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                }
            } else if let actionTitle = step.actionTitle, !step.isComplete {
                Button(action: step.action) {
                    Label(actionTitle, systemImage: step.buttonIcon)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(StepActionButtonStyle())
                .disabled(isImportingSamples && step.kind != .importSamples)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(step.isComplete ? 0.16 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    /// Primary + secondary CTAs.
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(primaryButtonTitle) {
                onboardingStore.dismissChecklist()
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .controlSize(.large)
            .disabled(isImportingSamples)

            Button("I'll finish these later", role: .cancel) {
                onboardingStore.dismissChecklist()
            }
            .buttonStyle(.bordered)
            .tint(Color.white.opacity(0.85))
            .disabled(isImportingSamples)
        }
    }

    /// Surfaces the latest error inline with the checklist.
    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Color.white)
        }
        .padding(14)
        .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Builds the view model for each checklist step so layout remains declarative.
    private var steps: [ChecklistStep] {
        [
            ChecklistStep(
                kind: .importSamples,
                title: "Prime your workspace",
                caption: "Import the curated sample set or add your own docs so retrieval has real context.",
                systemImage: "tray.and.arrow.down.fill",
                isComplete: onboardingStore.hasImportedSamples,
                actionTitle: onboardingStore.hasImportedSamples ? nil : "Import sample set",
                buttonIcon: "arrow.down.circle.fill",
                action: importSamples
            ),
            ChecklistStep(
                kind: .pickModel,
                title: "Pick your default model",
                caption: "Visit Settings → Models so routing knows whether to stay on-device or use Apple PCC.",
                systemImage: "slider.horizontal.3",
                isComplete: onboardingStore.hasAcknowledgedModelSelection,
                actionTitle: onboardingStore.hasAcknowledgedModelSelection ? nil : "Open Settings",
                buttonIcon: "gearshape.fill",
                action: openSettingsAndTrack
            ),
            ChecklistStep(
                kind: .firstQuestion,
                title: "Ask your first question",
                caption: "Jump into chat and ask about the imported docs to unlock smart suggestions.",
                systemImage: "bubble.left.and.bubble.right.fill",
                isComplete: onboardingStore.hasAskedFirstQuery,
                actionTitle: onboardingStore.hasAskedFirstQuery ? nil : "Go to Chat",
                buttonIcon: "paperplane.fill",
                action: openChatAndTrack
            )
        ]
    }

    private var completedStepCount: Int {
        steps.filter { $0.isComplete }.count
    }

    private var progressFraction: Double {
        guard !steps.isEmpty else { return 0 }
        return Double(completedStepCount) / Double(steps.count)
    }

    private var primaryButtonTitle: String {
        onboardingStore.hasCompletedOnboarding ? "Launch workspace" : "Dive in anyway"
    }

    private func statusChip(for step: ChecklistStep) -> some View {
        Text(step.isComplete ? "Done" : "Pending")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(step.isComplete ? Color.green.opacity(0.2) : Color.white.opacity(0.1))
            )
            .foregroundColor(step.isComplete ? Color.green : Color.white.opacity(0.85))
    }

    /// Opens the settings tab and records completion for the model-selection step.
    private func openSettingsAndTrack() {
        onOpenSettings()
        onboardingStore.markModelSelectionAcknowledged()
    }

    /// Switches to chat and marks the "first query" step as complete.
    private func openChatAndTrack() {
        onOpenChat()
        onboardingStore.markAskedFirstQuery()
    }

    /// Writes curated sample docs to disk, ingests them, and updates onboarding progress.
    private func importSamples() {
        guard !isImportingSamples else { return }
        isImportingSamples = true
        errorMessage = nil

        Task {
            defer { isImportingSamples = false }
            do {
                try await SampleDocumentManager.shared.importSamples(into: ragService)
                onboardingStore.markSamplesImported()
            } catch {
                errorMessage = "Could not import samples. Please try again."
            }
        }
    }
}

// MARK: - Models & Styles

private struct ChecklistStep: Identifiable {
    enum Kind { case importSamples, pickModel, firstQuestion }
    let id = UUID()
    let kind: Kind
    let title: String
    let caption: String
    let systemImage: String
    let isComplete: Bool
    let actionTitle: String?
    let buttonIcon: String
    let action: () -> Void
}

private struct StepActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.24 : 0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .foregroundColor(.white)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
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
