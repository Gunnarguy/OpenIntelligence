import SwiftUI

/// Full-screen onboarding splash shown on first launch.
/// Clean, benefit-focused design that guides users to value quickly.
struct OnboardingChecklistView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStateStore
    @EnvironmentObject private var entitlementStore: EntitlementStore
    @ObservedObject var ragService: RAGService
    let onOpenSettings: () -> Void
    let onOpenChat: () -> Void

    @State private var isImportingSamples = false
    @State private var errorMessage: String?
    @State private var currentPage = 0

    private let totalPages = 3

    var body: some View {
        ZStack {
            SplashBackdrop()

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    Button {
                        onboardingStore.dismissChecklist()
                    } label: {
                        Text("Skip")
                            .font(.body.weight(.medium))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
.buttonStyle(.plain)
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

                    // Navigation buttons
                    if currentPage < totalPages - 1 {
                        Button {
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
                            startWithSamples()
                        } label: {
                            HStack(spacing: 8) {
                                if isImportingSamples {
                                    ProgressView()
                                        .tint(.black)
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.right.circle.fill")
                                }
                                Text(isImportingSamples ? "Setting up..." : "Get Started")
                                    .font(.headline)
                            }
.foregroundColor(.black)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 16)
    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
.buttonStyle(.plain)
    .disabled(isImportingSamples)
    .padding(.horizontal, 32)

Button {
    onboardingStore.dismissChecklist()
                            onOpenChat()
                        } label: { 
                            Text("I'll add my own documents")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)
.padding(.top, 4)
                    }
                }
.padding(.bottom, 48)
            }
        }
        .accessibilityElement(children: .contain)
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
                    icon: "doc.text.magnifyingglass",
                    iconColor: .blue,
                    title: "Smart Search",
                    description: "Ask questions and get answers from your own documents"
                )

                OnboardingFeatureRow(
                    icon: "bolt.fill",
                    iconColor: .orange,
                    title: "Instant Answers",
                    description: "No waiting—responses start in under a second"
                )

                OnboardingFeatureRow(
                    icon: "iphone",
                    iconColor: .purple,
                    title: "Works Offline",
                    description: "Search and basic answers work without internet"
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
                    SampleDocChip(title: "Pricing Brief", icon: "doc.text")
                    SampleDocChip(title: "Architecture", icon: "building.2")
                }

                HStack(spacing: 8) {
                    SampleDocChip(title: "User Guide", icon: "book")
                    SampleDocChip(title: "FAQ", icon: "questionmark.circle")
                }
            }
.padding(.horizontal, 32)
    .padding(.top, 8)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 32)
            }

            Spacer()
            Spacer()
        }
    }

    // MARK: - Actions

    private func startWithSamples() { 
        guard !isImportingSamples else { return }
        isImportingSamples = true
        errorMessage = nil

        Task {
            defer { isImportingSamples = false }
            do {
                try await SampleDocumentManager.shared.importSamples(into: ragService)
                onboardingStore.markSamplesImported()
                onboardingStore.dismissChecklist()
                onOpenChat()
            } catch {
                errorMessage = "Couldn't set up samples. Tap to try again."
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
