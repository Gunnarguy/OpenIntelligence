import SwiftUI

enum OpenIntelligenceLinks {
    static let appStoreID = "6756559175"
    static let githubURL = URL(string: "https://github.com/Gunnarguy/OpenIntelligence")!
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id\(appStoreID)")!
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

    /// Single source of truth for hardware identity. `deviceCapabilities` is still used
    /// for the OS version and the Apple Intelligence availability rows, both of which it
    /// gets from live system APIs rather than from its own chip table.
    private let deviceService = DeviceCapabilityService.shared

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
                        // Rendered from `WhatsNewStore.releases`, the same source as the
                        // sheet shown after an update. These three highlights used to be
                        // hardcoded here and had gone stale: they described an older
                        // release ("Quality modes are easier to scan") while the app was
                        // on 4.8. Two places holding release copy is two places to drift,
                        // and this one already had. It also gives the update sheet a
                        // permanent home, so dismissing it does not lose the content.
                        // Three highlights, not the whole release.
                        //
                        // This rendered every item in the release, which for 5.0 is
                        // nineteen — the same content Version History already shows in
                        // full, one screen away. Two surfaces printing the same changelog
                        // at the same length is not two views of it, it is the same wall
                        // twice. About is now the teaser and Version History the record.
                        VStack(alignment: .leading, spacing: 10) {
                            if let release = WhatsNewStore().releaseForCurrentVersion() {
                                ForEach(release.items.prefix(3)) { item in
                                    releaseHighlight(
                                        icon: item.symbol,
                                        tint: .accentColor,
                                        title: item.title,
                                        detail: item.detail
                                    )
                                }

                                if release.items.count > 3 {
                                    NavigationLink {
                                        VersionHistoryView()
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text("See all \(release.items.count) changes in \(release.version)")
                                                .font(.footnote.weight(.medium))
                                            Image(systemName: "arrow.forward")
                                                .font(.system(size: 10, weight: .semibold))
                                        }
                                        .foregroundStyle(Color.accentColor)
                                        .padding(.top, 2)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } else {
                                Text("Release notes for this version aren't available in the app. The App Store listing has the full list.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Your Device
                    SurfaceCard {
                        SectionHeader(icon: "cpu", title: "Your Device")
                        VStack(alignment: .leading, spacing: 8) {
                            // Read the chip from DeviceCapabilityService, not from
                            // `deviceCapabilities.deviceChip`.
                            //
                            // `RAGService.detectDeviceChip()` switches on the iPhone
                            // identifier family and stops at "iPhone17" (the iPhone 16
                            // line), so every iPhone 17 and newer fell to `default:
                            // return .older` — whose rawValue is the literal string
                            // "A12 or Older", with performanceRating "Limited". Those
                            // two strings were rendered right here, so the newest iPhone
                            // Apple sells reported itself as a 2018 chip, directly above
                            // an "Apple Intelligence ✓" row that reads the live
                            // availability API and was therefore correct.
                            //
                            // DeviceCapabilityService keys iPhones off the major version
                            // number and Macs off the CPU brand string, so it already
                            // resolves A19/A20 and M5 and does not need a new table for
                            // hardware that has not shipped yet.
                            LabeledContent("Device Chip", value: deviceService.chipName)
                            LabeledContent("iOS Version", value: deviceCapabilities.iOSVersion)
                            LabeledContent("Neural Engine", value: "\(deviceService.npuTops) TOPS")
                            LabeledContent("Memory", value: String(format: "%.0f GB", deviceService.memoryGB))
                            LabeledContent("AI Tier", value: deviceService.tier.displayName)
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
                        SectionHeader(icon: "bubble.left.and.exclamationmark.bubble.right.fill", title: "Feature Requests")
                        VStack(alignment: .leading, spacing: 10) {
                            externalLinkRow(
                                title: "Send a Feature Request",
                                subtitle: "Email feature ideas and product requests directly from the app",
                                icon: "sparkles.rectangle.stack.fill",
                                tint: .orange
                            ) {
                                openFeatureRequestEmail()
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
                                subtitle: "Feature ideas, bugs, and product feedback land in the product inbox",
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
                                title: "Notion Roadmap",
                                subtitle: "Track the features, tasks, and future technical roadmap milestones",
                                icon: "map.fill",
                                tint: .primary
                            ) {
                                openURL(OpenIntelligenceLinks.notionRoadmapURL)
                            }
                            externalLinkRow(
                                title: "Write an App Store Review",
                                subtitle: "Open the App Store review form directly when you want to leave feedback",
                                icon: "star.bubble.fill",
                                tint: .orange
                            ) {
                                openURL(OpenIntelligenceLinks.writeReviewURL)
                            }
                            externalLinkRow(
                                title: "App Store Listing",
                                subtitle: "Browse the public listing, screenshots, and release notes",
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

    private func openFeatureRequestEmail() {
        openURL(OpenIntelligenceLinks.feedbackMailtoURL(source: "About Screen Feature Request"))
    }
}

#Preview {
    AboutView()
        .environmentObject(SettingsStore(ragService: RAGService()))
}
