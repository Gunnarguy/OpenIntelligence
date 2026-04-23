import SwiftUI

enum OpenIntelligenceLinks {
    static let roadmapURL = URL(string: "https://gunzino.notion.site/98fb2f9dc3294cb5a283fabfaf7aee0a?v=33b49a74d54f81c5a6f2000c94fb8c3b&pvs=25")!
    static let feedbackBoardURL = URL(string: "https://gunzino.notion.site/483120d0efa34513816f9fa43764ee2e?v=97202e3dfa49450b93f0159beb0978c9&pvs=25")!
    static let githubURL = URL(string: "https://github.com/Gunnarguy/OpenIntelligence")!
    static let appStoreURL = URL(string: "https://apps.apple.com/us/app/openintelligence/id6756559175")!
    static let feedbackEmailAddress = "Gunnarguy@me.com"

    static func feedbackMailtoURL(source: String) -> URL {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackEmailAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: "[OpenIntelligence App Feedback] \(source) | v\(version) (\(build))"),
            URLQueryItem(name: "body", value: "Source: \(source)\nApp Version: \(version) (\(build))\n\nTopic:\n\nDetails:\n")
        ]
        return components.url ?? URL(string: "mailto:\(feedbackEmailAddress)")!
    }
}

/// Presents product metadata and device-specific capability information.
struct AboutView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.openURL) private var openURL
    @State private var deviceCapabilities = DeviceCapabilities()

    /// Human-readable name for the active embedding provider
    private var embeddingDisplayName: String {
        switch settings.defaultEmbeddingProvider {
        case "nl_contextual_embedding":
            return "NLContextual (512D)"
        case "nl_embedding":
            return "NLEmbedding (512D)"
        case "coreml_sentence_embedding":
            return "MiniLM-L6-v2 (384D)"
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
                VStack(spacing: 16) {
                    // App Info
                    SurfaceCard {
                        SectionHeader(icon: "info.circle", title: "About OpenIntelligence")
                        VStack(alignment: .leading, spacing: 8) {
                            Text("OpenIntelligence")
                                .font(.title.bold())
                            Text("Privacy-First RAG Application")
                                .foregroundColor(.secondary)
                            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0") (Build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "19"))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }

                    SurfaceCard {
                        SectionHeader(icon: "sparkles.rectangle.stack", title: "Latest Update")
                        VStack(alignment: .leading, spacing: 10) {
                            releaseHighlight(
                                icon: "bolt.fill",
                                tint: .orange,
                                title: "Quality modes are easier to scan",
                                detail: "Standard, Deep Think, and Maximum now have clearer labels and stronger visual separation in chat."
                            )
                            releaseHighlight(
                                icon: "paintbrush.pointed.fill",
                                tint: .purple,
                                title: "Settings and About are cleaner",
                                detail: "Plan messaging, update summaries, and key product links now read more clearly inside the app."
                            )
                            releaseHighlight(
                                icon: "list.bullet.rectangle.portrait.fill",
                                tint: .blue,
                                title: "Feedback is easier to send",
                                detail: "The app keeps direct paths to feedback, support, the App Store, and the public codebase without the broken update pages."
                            )
                        }
                    }

                    // Your Device
                    SurfaceCard {
                        SectionHeader(icon: "cpu", title: "Your Device")
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Device Chip", value: deviceCapabilities.deviceChip.rawValue)
                            LabeledContent("iOS Version", value: deviceCapabilities.iOSVersion)
                            LabeledContent("Performance", value: deviceCapabilities.deviceChip.performanceRating)
                            LabeledContent("AI Tier", value: deviceCapabilities.deviceTier.description)
                        }
                    }

                    // AI Capabilities
                    SurfaceCard {
                        SectionHeader(icon: "brain.head.profile", title: "AI Capabilities")
                        VStack(alignment: .leading, spacing: 8) {
                            capabilityRow(title: "Apple Intelligence", condition: deviceCapabilities.supportsAppleIntelligence)
                            capabilityRow(title: "Foundation Models", condition: deviceCapabilities.supportsFoundationModels)
                            capabilityRow(title: "Private Cloud Compute", condition: deviceCapabilities.supportsPrivateCloudCompute)
                            capabilityRow(title: "Writing Tools", condition: deviceCapabilities.supportsWritingTools)
                        }
                    }

                    // Features
                    SurfaceCard {
                        SectionHeader(icon: "star.circle.fill", title: "Features")
                        VStack(alignment: .leading, spacing: 8) {
                            FeatureRow(icon: "doc.text.fill", title: "Document Processing", description: "Import PDFs, text files, and more")
                            FeatureRow(icon: "cpu", title: "On-Device Processing", description: "OCR, chunking, and embeddings run locally")
                            FeatureRow(icon: "brain", title: "Multiple AI Pathways", description: "Apple Foundation Models or extractive QA")
                            FeatureRow(icon: "lock.shield.fill", title: "Privacy First", description: "Your data stays on your device by default")
                        }
                    }

                    // Technology
                    SurfaceCard {
                        SectionHeader(icon: "gearshape.2.fill", title: "Technology")
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("RAG Pipeline", value: "Hybrid (Vector + BM25 → RRF)")
                            LabeledContent("Embeddings", value: embeddingDisplayName)
                            LabeledContent("Vector Store", value: "Persistent JSON (exact k-NN)")
                            LabeledContent("Minimum iOS", value: "18.0")
                            LabeledContent("Optimized for", value: "iOS 26.0+")
                        }
                    }

                    SurfaceCard {
                        SectionHeader(icon: "map", title: "Roadmap & Feedback")
                        VStack(alignment: .leading, spacing: 10) {
                            externalLinkRow(
                                title: "Roadmap",
                                subtitle: "See what shipped, what is active, and what is next",
                                icon: "map.fill",
                                tint: .teal
                            ) {
                                openURL(OpenIntelligenceLinks.roadmapURL)
                            }
                            externalLinkRow(
                                title: "Feature Requests & Feedback",
                                subtitle: "Vote on ideas and add bugs or product requests",
                                icon: "bubble.left.and.exclamationmark.bubble.right.fill",
                                tint: .orange
                            ) {
                                openURL(OpenIntelligenceLinks.feedbackBoardURL)
                            }
                        }
                    }

                    // Contact & Support
                    SurfaceCard {
                        SectionHeader(icon: "envelope.fill", title: "Contact & Support")
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Need help or have feedback? Get in touch:")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            externalLinkRow(
                                title: OpenIntelligenceLinks.feedbackEmailAddress,
                                subtitle: "Feature ideas, bugs, and roadmap feedback land in the product inbox",
                                icon: "envelope.fill",
                                tint: .accentColor
                            ) {
                                openEmail()
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
                                title: "App Store Listing",
                                subtitle: "Share the live app and current pricing page",
                                icon: "apple.logo",
                                tint: .blue
                            ) {
                                openURL(OpenIntelligenceLinks.appStoreURL)
                            }
                        }
                    }
                }
                .padding(16)
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
    }

    private func capabilityRow(title: String, condition: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: condition ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(condition ? .green : .secondary)
        }
    }

    private func releaseHighlight(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 18, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
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
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 2) {
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
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private func openEmail() {
        openURL(OpenIntelligenceLinks.feedbackMailtoURL(source: "About Screen"))
    }
}

#Preview {
    AboutView()
        .environmentObject(SettingsStore(ragService: RAGService()))
}
