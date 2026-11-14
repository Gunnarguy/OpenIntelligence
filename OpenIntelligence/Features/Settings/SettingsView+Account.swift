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

    // MARK: - Billing Card

    @ViewBuilder
    var billingCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            // Header with tier badge
            HStack {
                Image(systemName: "creditcard.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text("Subscription")
                        .font(.headline)
                    Text(subscriptionStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                tierBadge
            }

            planPanel

            // Always show a button to access subscription management
            Button {
                planEntryPoint = .settings
                showPlanSheet = true
            } label: {
                HStack {
                    Image(systemName: entitlementStore.effectiveTier == .free ? "arrow.up.circle" : "gearshape")
                    Text(entitlementStore.effectiveTier == .free ? "Upgrade Plan" : "View Plans")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline.weight(.medium))
                .padding(.vertical, DSSpacing.sm)
                .padding(.horizontal, DSSpacing.md)
                .background(entitlementStore.effectiveTier == .free ? Color.accentColor : Color.accentColor.opacity(0.1))
                .foregroundStyle(entitlementStore.effectiveTier == .free ? .white : .accentColor)
                .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
            }
            .buttonStyle(.plain)

            if entitlementStore.activeTier == .free, entitlementStore.isLegacyPaidProtected {
                Text("Previous paid purchases on this Apple ID now unlock Lifetime access on this device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if entitlementStore.effectiveTier == .lifetime {
                lifetimeSupporterBanner
            }
        }
        .padding(DSSpacing.lg)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    /// What the plan allows and how much of it is used, as lit blocks (5.8). The figures are the entitlement
    /// store's and the engine's own counts, the ones the limits are checked against.
    private var planPanel: some View {
        let documents = SettingsStatusPanel.used(ragService.countedDocumentCount, of: entitlementStore.documentLimit)
        let libraries = SettingsStatusPanel.used(containerService.countedLibraryCount, of: entitlementStore.libraryLimit)
        let dailyLimit = QuotaPolicy.freeMaximumModeDailyLimit
        let maximumLeft = entitlementStore.maximumModeRemainingUses
        return SettingsStatusPanel(
            symbol: "creditcard",
            title: "Your plan",
            badge: entitlementStore.effectiveTier.displayName,
            badgeColor: entitlementStore.effectiveTier == .free ? Color.white.opacity(0.7) : .orange,
            blocks: [
                .init(
                    symbol: "doc.text", name: "Documents", color: .blue, figure: documents.figure,
                    share: documents.share, caption: documents.caption),
                .init(
                    symbol: "books.vertical", name: "Libraries", color: .purple, figure: libraries.figure,
                    share: libraries.share, caption: libraries.caption),
                entitlementStore.hasUnlimitedMaximumMode
                    ? .init(
                        symbol: "bolt.fill", name: "Maximum", color: .orange, figure: "No cap", share: nil,
                        caption: "every day")
                    : .init(
                        symbol: "bolt.fill", name: "Maximum", color: .orange,
                        figure: "\(maximumLeft) of \(dailyLimit)",
                        share: Double(maximumLeft) / Double(max(1, dailyLimit)), caption: "left today"),
            ])
    }

    private var subscriptionStatusText: String {
        switch entitlementStore.effectiveTier {
        case .free:
            return "Free tier • Maximum \(QuotaPolicy.freeMaximumModeDailyLimit)/day"
        case .pro:
            return "Pro plan • Unlimited Maximum"
        case .lifetime:
            if entitlementStore.activeTier == .free, entitlementStore.isLegacyPaidProtected {
                return "Lifetime access • Grandfathered from prior purchase"
            }
            return "Lifetime • Everything unlocked"
        }
    }

    @ViewBuilder
    private var tierBadge: some View {
        Text(entitlementStore.effectiveTier.displayName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            .background(tierBadgeColor.opacity(0.15))
            .foregroundStyle(tierBadgeColor)
            .clipShape(Capsule())
    }

    private var tierBadgeColor: Color {
        switch entitlementStore.effectiveTier {
        case .free: return .secondary
        case .pro: return .accentColor
        case .lifetime: return .accentColor
        }
    }

    @ViewBuilder
    private func quotaItem(icon: String, value: String, label: String) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var lifetimeSupporterBanner: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "heart.text.square.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Lifetime")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Forever unlocked")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.xs)
                    .background(Color.accentColor.opacity(0.16))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
            }

            Text("Thanks for backing OpenIntelligence early. Lifetime keeps unlimited documents and 20 libraries unlocked with no recurring subscription.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: DSSpacing.sm) {
                Button {
                    openURL(OpenIntelligenceLinks.feedbackMailtoURL(source: "Settings Screen"))
                } label: {
                    Label("Send Feedback", systemImage: "envelope.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    openURL(OpenIntelligenceLinks.writeReviewURL)
                } label: {
                    Label("Write Review", systemImage: "star.bubble.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(DSSpacing.md)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

}
