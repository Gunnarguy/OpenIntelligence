import SwiftUI

enum OpenIntelligenceLinks {
    nonisolated static let appStoreID = "6756559175"
    static let githubURL = URL(string: "https://github.com/Gunnarguy/OpenIntelligence")!
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id\(appStoreID)")!
    /// Campaign tag on every App Store link the app hands to someone else (Share the App, a shared
    /// answer, an exported conversation). One tag for all of them: App Store Connect shows a tag
    /// only after first-time downloads from five people, so splitting it would hide the number.
    nonisolated static let shareCampaignTag = "In_App_Share"
    /// The App Store link for sharing. `pt` is the provider token, the same public value as in the
    /// repository README's link; `ct` is the campaign tag App Store Connect reports under Acquisition.
    nonisolated static let sharedAppStoreURL = URL(
        string: "https://apps.apple.com/app/apple-store/id\(appStoreID)?pt=127101782&ct=\(shareCampaignTag)&mt=8")!
    static let writeReviewURL = URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")!
    static let feedbackEmailAddress = "gunnarguy@me.com"
    static let notionRoadmapURL = URL(string: "https://app.notion.com/p/gunzino/37f49a74d54f81b79424dae1288c0043")!

    static func feedbackMailtoURL(source: String) -> URL {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackEmailAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: "[OpenIntelligence App Feedback] \(source) | v\(version) (\(build))"),
            URLQueryItem(
                name: "body", value: "Source: \(source)\nApp Version: \(version) (\(build))\n\nTopic:\n\nDetails:\n"),
        ]
        return components.url ?? URL(string: "mailto:\(feedbackEmailAddress)")!
    }
}

/// Presents product metadata and device-specific capability information.
struct AboutView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.openURL) private var openURL
    @State private var deviceCapabilities = DeviceCapabilities()
    /// The privacy policy in the app (`PrivacyPolicyView`, 5.7). Its only way in, a button on the Plans
    /// screen, became a link to the website on 2026-05-28, and nothing opened it after that.
    @State private var showingPrivacyPolicy = false
    /// Whether Private Cloud Compute is available, from the same live snapshot the Private Cloud Compute page reads
    /// (5.8). Nil until it loads, when the compile-time check stands in, as on that page.
    @State private var pccAvailable: Bool?

    /// Single source of truth for hardware identity. `deviceCapabilities` is still used
    /// for the OS version and the Apple Intelligence availability rows, both of which it
    /// gets from live system APIs rather than from its own chip table.
    private let deviceService = DeviceCapabilityService.shared

    /// The system's name for the version line: "iOS 27.0.0", "iPadOS ...", "macOS ...".
    private var systemName: String {
        #if os(macOS)
            return "macOS"
        #else
            if ProcessInfo.processInfo.isiOSAppOnMac { return "macOS" }
            return deviceService.isIPad ? "iPadOS" : "iOS"
        #endif
    }

    /// Human-readable name for the active embedding provider
    private var embeddingDisplayName: String {
        switch settings.defaultEmbeddingProvider {
        case "nl_contextual_embedding":
            return "NLContextual (512D)"
        case "nl_embedding":
            return "NLEmbedding (512D)"
        case "coreml_sentence_embedding":
            return "Granite small english r2 (384D, Core ML)"
        // Showed the raw id on a Mac with macOS 27, where Core AI is the default (5.7).
        case "coreai_sentence_embedding":
            return "Core AI (retired in 5.8)"
        case "apple_fm_embed":
            return "Apple FM (1024D)"
        default:
            return settings.defaultEmbeddingProvider
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [DSColors.background, DSColors.surface.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: DSSpacing.lg) {
                    // App Info
                    SurfaceCard {
                        SectionHeader(icon: "info.circle", title: "About OpenIntelligence")
                        VStack(alignment: .leading, spacing: DSSpacing.sm) {
                            Text("OpenIntelligence")
                                .font(.title.bold())
                            Text("Privacy-First RAG Application")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(
                                "Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0") (Build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "19"))"
                            )
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            Text("On \(deviceService.modelName ?? deviceService.chipDisplayName), \(systemName) \(deviceCapabilities.iOSVersion)")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, DSSpacing.xxs)
                    }

                    // "Latest Update" and "Your Device" were cards here until 2026-11-16. The first showed three items of
                    // the release Version History shows whole, one row away in Settings; the second the model, chip,
                    // Neural Engine figure and memory that Device & Performance shows with their sources. The system
                    // version, which only that card showed, is a line in the card above.

                    // AI Capabilities
                    SurfaceCard {
                        SectionHeader(icon: "brain.head.profile", title: "AI Capabilities")
                        VStack(alignment: .leading, spacing: DSSpacing.sm) {
                            capabilityRow(
                                title: "Apple Intelligence", condition: deviceCapabilities.supportsAppleIntelligence)
                            capabilityRow(
                                title: "Foundation Models", condition: deviceCapabilities.supportsFoundationModels)
                            capabilityRow(
                                title: "Private Cloud Compute",
                                condition: pccAvailable ?? deviceCapabilities.supportsPrivateCloudCompute)
                            capabilityRow(title: "Writing Tools", condition: deviceCapabilities.supportsWritingTools)
                        }
                    }

                    // Features
                    SurfaceCard {
                        SectionHeader(icon: "star.circle.fill", title: "Features")
                        VStack(alignment: .leading, spacing: DSSpacing.sm) {
                            FeatureRow(
                                icon: "doc.text.fill", title: "Document Processing",
                                description: "Import PDFs, text files, and more")
                            FeatureRow(
                                icon: "cpu", title: "On-Device Processing",
                                description: "OCR, chunking, and embeddings run locally")
                            FeatureRow(
                                icon: "brain", title: "Multiple AI Pathways",
                                description: "Apple Foundation Models or extractive QA")
                            FeatureRow(
                                icon: "lock.shield.fill", title: "Privacy First",
                                description: "Your data stays on your device by default")
                        }
                    }

                    // Technology
                    SurfaceCard {
                        SectionHeader(icon: "gearshape.2.fill", title: "Technology")
                        VStack(alignment: .leading, spacing: DSSpacing.sm) {
                            LabeledContent("RAG Pipeline", value: "Hybrid (Vector + BM25 → RRF)")
                            LabeledContent("Embeddings", value: embeddingDisplayName)
                            // Corrected 2026-11-15 against the code: the store is `BNNSVectorDatabase`, raw vectors in
                            // a memory-mapped file searched exhaustively on the GPU or CPU (not JSON); the app's
                            // deployment target is iOS 26.0 and macOS 26.0 (was "18.0"); Private Cloud Compute needs 27.
                            LabeledContent("Vector Store", value: "Memory-mapped file (exact search)")
                            LabeledContent("Requires", value: "iOS 26 or macOS 26")
                                .monospacedDigit()
                            LabeledContent("Private Cloud Compute", value: "iOS 27 or macOS 27")
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                    }

                    // Feedback, feature requests and the App Store review are the Support & Feedback card at the end of the
                    // Settings list (2026-11-16): the feedback address was offered three times between the two, and the
                    // review link twice. A crash report and the links only About has stay here.
                    if let crashReport = CrashReports.all().first {
                        SurfaceCard {
                            SectionHeader(icon: "exclamationmark.triangle", title: "Last Crash Report")
                            VStack(alignment: .leading, spacing: DSSpacing.md) {
                                // The newest crash report, when there is one (`CrashReports`, 5.7).
                                externalLinkRow(
                                    title: "Email the Last Crash Report",
                                    subtitle: "A summary of where the app stopped, sent from your mail app",
                                    icon: "exclamationmark.triangle.fill",
                                    tint: .red
                                ) {
                                    openURL(
                                        CrashReports.mailURL(
                                            for: crashReport, to: OpenIntelligenceLinks.feedbackEmailAddress))
                                }
                                ShareLink(item: crashReport) {
                                    linkRowLabel(
                                        title: "Share the Last Crash Report",
                                        subtitle: "The whole report as a file. It has none of your documents or chats",
                                        icon: "square.and.arrow.up",
                                        tint: .red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    SurfaceCard {
                        SectionHeader(icon: "link", title: "Privacy and Links")
                        VStack(alignment: .leading, spacing: DSSpacing.md) {
                            externalLinkRow(
                                title: "Privacy Policy",
                                subtitle: "What stays on your device, and what can leave it",
                                icon: "hand.raised.fill",
                                tint: .accentColor
                            ) {
                                showingPrivacyPolicy = true
                            }
                            externalLinkRow(
                                title: "GitHub Repository",
                                subtitle: "Browse the codebase, releases, and implementation details",
                                icon: "chevron.left.forwardslash.chevron.right",
                                tint: .secondary
                            ) {
                                openURL(OpenIntelligenceLinks.githubURL)
                            }
                            externalLinkRow(
                                title: "Notion Roadmap",
                                subtitle: "Track the features, tasks, and future technical roadmap milestones",
                                icon: "map.fill",
                                tint: .secondary
                            ) {
                                openURL(OpenIntelligenceLinks.notionRoadmapURL)
                            }
                            externalLinkRow(
                                title: "App Store Listing",
                                subtitle: "Browse the public listing, screenshots, and release notes",
                                icon: "apple.logo",
                                tint: .accentColor
                            ) {
                                openURL(OpenIntelligenceLinks.appStoreURL)
                            }
                        }
                    }
                }
                .padding(DSSpacing.lg)
            }
        }
        .navigationTitle("About")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            DispatchQueue.main.async {
                deviceCapabilities = RAGService.checkDeviceCapabilities()
            }
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            PrivacyPolicyView()
        }
        .task {
            #if canImport(FoundationModels)
                if #available(iOS 26.0, macOS 26.0, *) {
                    pccAvailable = await LiveFoundationModelCapabilityProvider().snapshot().pccAvailable
                }
            #endif
        }
    }

    private func capabilityRow(title: String, condition: Bool) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Image(systemName: condition ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(condition ? .green : .secondary)
        }
    }

    private func releaseHighlight(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 18, alignment: .center)

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func externalLinkRow(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            linkRowLabel(title: title, subtitle: subtitle, icon: icon, tint: tint)
        }
        .buttonStyle(.plain)
    }

    /// The look of every row on this screen, for a button or a share link.
    private func linkRowLabel(title: String, subtitle: String, icon: String, tint: Color) -> some View {
        HStack(spacing: DSSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DSColors.primaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "arrow.up.forward")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, DSSpacing.xxs)
        .frame(minHeight: DSSpacing.tapTarget)
    }

}

#Preview {
    AboutView()
        .environmentObject(SettingsStore(ragService: RAGService()))
}
