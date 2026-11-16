//
//  SettingsView+Account.swift
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
    // MARK: - Hero Card

    @ViewBuilder
    private var heroCard: some View {
        VStack(spacing: DSSpacing.lg) {
            // Animated icon with gradient background
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "brain.head.profile.fill")
                    .scaledFont(size: 36)
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: DSSpacing.xs) {
                Text("OpenIntelligence")
                    .font(.title2.bold())

                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Pipeline status pills
            HStack(spacing: DSSpacing.sm) {
                statusPill(
                    icon: "checkmark.circle.fill",
                    text: "On-Device First",
                    active: deviceCapabilities.supportsFoundationModels
                )
                statusPill(
                    icon: "cloud.fill",
                    text: "PCC Available",
                    active: deviceCapabilities.supportsPrivateCloudCompute && settings.applePCCConsent != .denied
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.xl)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous))
    }

    @ViewBuilder
    func statusPill(icon: String, text: String, active: Bool) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(active ? Color.accentColor : DSColors.secondaryText)
            Text(text)
                .font(.caption2.weight(.medium))
                // Its full height for the width it gets, so at large sizes it wraps instead of ending in "Fir..." (5.7).
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        // The words in the label color when active, the accent in the icon and the tint (5.7, the owner's choice):
        // blue on the blue-tinted pill measured 3.8 to 1.
        .foregroundStyle(active ? DSColors.primaryText : DSColors.secondaryText)
        // A capsule around one line. At accessibility text sizes the words can take two lines, where a capsule's round
        // ends cut into them, so there the pill is a rounded rectangle, and only the background is shaped (5.7).
        .background(
            active ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1),
            in: dynamicTypeSize.isAccessibilitySize
                ? AnyShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)) : AnyShape(Capsule()))
    }

    var statusText: String {
        if deviceCapabilities.supportsFoundationModels {
            return "Apple Intelligence Ready"
        } else {
            // "Preparing AI Models..." was shown for every reason, so it never ended on a device
            // that cannot run Apple Intelligence or has it switched off.
            return AppleIntelligenceCopy.status(for: deviceCapabilities.foundationModelUnavailability)
        }
    }

    // MARK: - Plan usage

    /// What the plans screen's panel shows used, from the counts the limits are checked against (5.8, 2026-11-15).
    /// The Plan & Usage page that showed it was folded into the plans screen, which the Plan & Usage row now opens in
    /// one tap; the page's grandfathered-purchase line went with it, and its Lifetime thanks card, whose Send
    /// Feedback and Write Review buttons are on the Settings list's support card.
    var planUsage: PlanUsage {
        // Conversations are limited in each library, so this is the open library's count.
        PlanUsage(
            documents: ragService.countedDocumentCount,
            libraries: containerService.countedLibraryCount,
            chatsInOpenLibrary: containerService.activeContainer.map { ragService.listThreads(for: $0.id).count } ?? 0)
    }

}
