//
//  SettingsView+AppearanceAndSupport.swift
//  OpenIntelligence
//
//  Part of SettingsView, moved from SettingsView.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import AppIntents
import SwiftUI
import TipKit

#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(AppKit)
import AppKit
#endif

extension SettingsView {
    // MARK: - General

    /// The General page (2026-11-16): Appearance and Notifications, which were two pages of three rows and one row.
    /// Each card is a `SurfaceCard` with a `SectionHeader`, its rows the same size; every setting keeps its key.
    @ViewBuilder
    var generalPage: some View {
        appearanceCard
        CompletionNotificationSettingsCard()
    }

    @ViewBuilder
    var appearanceCard: some View {
        SurfaceCard {
            SectionHeader(icon: "paintpalette", title: "Appearance")

            AccentColorSettingsRow(accentColorHex: $settings.appAccentColorHex)

            Divider()

            // The one technical switch (2026-11-16). Plain English had its own, stored apart
            // (`glossary.showsTechnicalDetail`), which `SettingsStore` removes; this one keeps its value.
            generalToggleRow(
                title: "Technical Details",
                subtitle: "In the chat: the live stats, each step as it runs, and the answer mode, reasoning and confidence under an answer. In Settings: the techniques behind each mode. In Plain English: the technical version of every word.",
                isOn: $settings.showTechnicalDetails
            )
            .onChange(of: settings.showTechnicalDetails) { _, _ in
                Tour.used(.technicalDetails)
                DSHaptics.toggle()
            }
            .tour(.technicalDetails, in: Tour.settings)

            Divider()

            // Was "Real-time model routing and token telemetry"; the X-Ray shows neither (5.7).
            generalToggleRow(
                title: "Telemetry HUD",
                subtitle: "A floating map of the chip: this app's CPU use, the work it sends to the Neural Engine and GPU, and free memory",
                isOn: $settings.showSiliconHUD
            )
            .onChange(of: settings.showSiliconHUD) { _, _ in
                Tour.used(.xray)
                DSHaptics.toggle()
            }
            .tour(.xray, in: Tour.settings)

            // HUD Customization (only show when HUD is enabled)
            if settings.showSiliconHUD {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    // Glow Intensity Slider
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        HStack {
                            Text("Glow Intensity")
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(settings.hudGlowIntensity * 100))%")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(DSColors.secondaryText)
                        }
                        Slider(value: $settings.hudGlowIntensity, in: 0.1...1.0, step: 0.1)
                            .tint(.accentColor)
                            // Its name and the number shown beside it, for VoiceOver (5.7).
                            .accessibilityLabel("Glow Intensity")
                            .accessibilityValue("\(Int(settings.hudGlowIntensity * 100))%")
                            .onChange(of: settings.hudGlowIntensity) { _, _ in
                                DSHaptics.tick()
                            }
                    }

                    // Was "Show ops count and latency"; with it on the legend shows each chip's activity and free
                    // memory, and with it off "idle" (`HardwareTelemetryState.componentActivities`) (5.7).
                    generalToggleRow(
                        title: "Live Metrics", subtitle: "Show each chip's activity and free memory in the legend",
                        isOn: $settings.hudShowMetrics
                    )
                    .onChange(of: settings.hudShowMetrics) { _, _ in DSHaptics.toggle() }

                    generalToggleRow(
                        title: "Taptic Engine", subtitle: "Show haptic motor activity on HUD",
                        isOn: $settings.hudShowTaptic
                    )
                    .onChange(of: settings.hudShowTaptic) { _, _ in DSHaptics.toggle() }

                    // X-Ray labels (5.8): the chip's name and "Taptic Engine" in the outlines' corners.
                    generalToggleRow(
                        title: "Labels", subtitle: "Name what is working on the X-Ray", isOn: $settings.hudShowLabels
                    )
                    .onChange(of: settings.hudShowLabels) { _, _ in DSHaptics.toggle() }
                }
                .padding(.leading, DSSpacing.lg)
            }

            #if os(macOS)
                Divider()

                // The menu bar item (5.7), on until it is turned off here.
                generalToggleRow(
                    title: "Menu Bar", subtitle: "Ask, add documents or search from the menu bar",
                    isOn: $showsMenuBarItem
                )
                .tour(.menuBar, in: Tour.settings)
                .onChange(of: showsMenuBarItem) { _, _ in Tour.used(.menuBar) }
            #endif
        }
    }

    /// One row of the General page: name, a line under it, and the switch.
    private func generalToggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: DSSpacing.md) {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(DSColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DSSpacing.sm)
            // The title is the switch's name for VoiceOver; `labelsHidden()` keeps it off the screen (5.7).
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .tint(.accentColor)
        }
    }

    // `developerCard` and `aboutCard` were removed with the Settings restructure.
    // Both were NavigationLink-in-a-card wrappers; the same destinations are now
    // reached from `SettingsEntry.all` like every other screen.

    // MARK: - Support Card

    @ViewBuilder
    var supportCard: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: DSSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "heart.fill")
                        .scaledFont(size: 14)
                        .foregroundStyle(Color.accentColor)
                }

                Text("Support & Feedback")
                    .font(.headline)

                Spacer()
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.top, DSSpacing.lg)
            .padding(.bottom, DSSpacing.sm)

            Divider()
                .padding(.horizontal, DSSpacing.lg)

            // Rate App Row
            Button {
                openURL(OpenIntelligenceLinks.writeReviewURL)
            } label: {
                HStack(spacing: DSSpacing.md) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(Color.accentColor)
                        .scaledFont(size: 16)
                        .frame(width: 24, alignment: .center)
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text("Rate on the App Store")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DSColors.primaryText)
                        Text("A rating or review helps other people find the app")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, DSSpacing.lg)
                .padding(.vertical, DSSpacing.md)
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.horizontal, DSSpacing.lg)

            // Feedback Row
            Button {
                openURL(OpenIntelligenceLinks.feedbackMailtoURL(source: "Settings Screen"))
            } label: {
                HStack(spacing: DSSpacing.md) {
                    Image(systemName: "envelope.fill")
                        .foregroundStyle(Color.accentColor)
                        .scaledFont(size: 16)
                        .frame(width: 24, alignment: .center)
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text("Send Feedback")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DSColors.primaryText)
                        Text("Provide feedback to improve the experience")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, DSSpacing.lg)
                .padding(.vertical, DSSpacing.md)
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.horizontal, DSSpacing.lg)

            // Share App Row
            Button {
                shareApp()
            } label: {
                HStack(spacing: DSSpacing.md) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(Color.accentColor)
                        .scaledFont(size: 16)
                        .frame(width: 24, alignment: .center)
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text("Share with Friends")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DSColors.primaryText)
                        Text("Recommend OpenIntelligence to others")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, DSSpacing.lg)
                .padding(.vertical, DSSpacing.md)
            }
            .buttonStyle(.plain)
        }
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    var speechAnalysisSubtitle: String {
        settings.showTechnicalDetails ? "Audio transcription & voice input" : "Transcribes audio files and what you say"
    }

    private func shareApp() {
        let items: [Any] = [
            "I'm using OpenIntelligence for private, on-device AI and RAG search. Check it out on the App Store!",
            OpenIntelligenceLinks.sharedAppStoreURL
        ]
        
        #if canImport(UIKit)
        // The sheet's header shows the app's name and icon rather than the bare address (5.7).
        let activityVC = UIActivityViewController(
            activityItems: PreviewedShareItem.items(items, preview: .app), applicationActivities: nil)
        
        // Setup popover for iPad support
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            
            // For iPad compatibility
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = rootVC.view
                popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            rootVC.present(activityVC, animated: true)
        }
        #elseif os(macOS)
        let preview = ShareSheetPreview.app
        let picker = NSSharingServicePicker(items: [
            items[0],
            NSPreviewRepresentingActivityItem(
                item: OpenIntelligenceLinks.sharedAppStoreURL, title: preview.title, image: nil,
                icon: ShareSheetPreview.appIcon),
        ])
        if let window = NSApplication.shared.windows.first(where: { $0.isKeyWindow }),
           let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
        #endif
    }

    // MARK: - Helpers

    func updatePipelineStages() {
        pipelineStages = [
            ModelPipelineStage(
                name: "Embedding",
                role: .primary,
                detail: "Native FoundationModels Embeddings",
                status: .active,
                icon: "rectangle.3.group"
            ),
            ModelPipelineStage(
                name: "Retrieval",
                role: .primary,
                detail: "Hybrid Vector + BM25",
                status: .active,
                icon: "magnifyingglass"
            ),
            ModelPipelineStage(
                    name: "Generation",
                    role: .primary,
                    detail: settings.selectedModel.displayName,
                    status: deviceCapabilities.supportsFoundationModels ? .active : .unavailable(reason: "Not available"),
                    icon: "text.bubble"
                )
        ]
    }
}
