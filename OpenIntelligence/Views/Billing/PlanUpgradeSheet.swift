import SwiftUI
import StoreKit
import UIKit

/// Full-screen paywall surface that highlights plan tiers, add-ons, and billing controls.
struct PlanUpgradeSheet: View {
    let entryPoint: PlanUpgradeEntryPoint

    @EnvironmentObject private var entitlementStore: EntitlementStore
    @Environment(\.dismiss) private var dismiss
    @State private var purchasingProduct: BillingProduct?
    @State private var alertMessage: String?
    @State private var isRestoring = false
    @State private var selectedStoryIndex = 0

    private let tierOptions: [PlanTierOption] = [
        PlanTierOption(
            tier: .starter,
            product: .starterMonthly,
            tagline: "Personal workspace",
            badgeText: "Best for pilots",
            tint: .blue,
            isFeatured: false,
            alternateBillingProduct: .starterAnnual,
            alternatePriceSuffix: "/ yr · save ~30%",
            features: [
                "40 documents & 3 libraries",
                "Weekly rerank refresh",
                "Telemetry dashboard access"
            ]
        ),
        PlanTierOption(
            tier: .pro,
            product: .proMonthly,
            tagline: "Full research scale",
            badgeText: "Most popular",
            tint: .purple,
            isFeatured: true,
            alternateBillingProduct: .proAnnual,
            alternatePriceSuffix: "/ yr · 2 months free",
            features: [
                "Unlimited documents",
                "Up to 10 libraries",
                "Automation + tool calling"
            ]
        )
    ]

    private let storySlides: [PlanStorySlide] = [
        PlanStorySlide(
            title: "Stay fast",
            subtitle: "Starter bumps ingestion priority so new PDFs process in seconds, not minutes.",
            icon: "bolt.fill",
            tint: .orange
        ),
        PlanStorySlide(
            title: "Keep it private",
            subtitle: "All plans keep knowledge on-device or Apple PCC – never OpenAI unless reviewer mode.",
            icon: "lock.shield",
            tint: .teal
        ),
        PlanStorySlide(
            title: "Scale together",
            subtitle: "Pro unlocks automation hooks, tool calling, and up to 10 libraries for teams.",
            icon: "person.3.sequence",
            tint: .purple
        )
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heroSection
                    storyCarousel
                    if shouldShowRefillQuickAction {
                        refillQuickAction
                    }

                    ForEach(tierOptions) { option in
                        tierCard(for: option)
                    }

                    addOnCard
                    managementControls
                    complianceFooter
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(
                LinearGradient(
                    colors: [DSColors.background, DSColors.surface.opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Workspace Plans")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .alert(alertMessage ?? "", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            if let alertMessage {
                Text(alertMessage)
            }
        }
    }
}

// MARK: - Sections

private extension PlanUpgradeSheet {
    var heroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(entryPoint.headline)
                .font(.title2.weight(.semibold))
            Text(entryPoint.subheadline)
                .font(.body)
                .foregroundStyle(.secondary)
            Label("Current plan: \(entitlementStore.activeTier.displayName)", systemImage: "creditcard")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(Capsule())
        }
    }

    func tierCard(for option: PlanTierOption) -> some View {
        PlanTierCard(
            option: option,
            price: priceLabel(for: option.product),
            alternatePriceDescription: alternatePriceDescription(for: option),
            hasAccess: entitlementStore.activeTier.isAtLeast(option.tier),
            isProcessing: purchasingProduct == option.product,
            ctaAction: { purchase(option.product) }
        )
    }

    var addOnCard: some View {
        let activePacks = entitlementStore.addOnPacks
        let packCap = entitlementStore.documentPackCap
        let remainingPacks = entitlementStore.remainingDocumentPackCapacity
        let isCapped = entitlementStore.hasReachedDocumentPackCap
        let bonusDocuments = activePacks * QuotaPolicy.addOnDocumentIncrement

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Document Pack", systemImage: "plus.rectangle.on.rectangle")
                    .font(.headline)
                Spacer()
                Text(QuotaPolicy.addOnDocumentIncrement.description + " docs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Need a quick burst of capacity? Add \(QuotaPolicy.addOnDocumentIncrement) extra document slots. Up to \(packCap) packs can be active at once.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(
                    value: Double(activePacks),
                    total: Double(packCap)
                )
                .tint(isCapped ? .orange : .accentColor)

                if activePacks > 0 {
                    Text("Active packs: \(activePacks)/\(packCap) (\(bonusDocuments) extra docs)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Text("No add-on packs active yet.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if isCapped {
                    Label("Maximum pack cap reached. Remove documents or upgrade to unlock more space.", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else if remainingPacks > 0 {
                    Text("You can add \(remainingPacks) more pack\(remainingPacks == 1 ? "" : "s") (\(remainingPacks * QuotaPolicy.addOnDocumentIncrement) docs) before hitting the cap.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                purchase(.documentPackAddOn)
            } label: {
                Label(
                    isCapped ? "Pack Limit Reached" : "Buy Document Pack – \(priceLabel(for: .documentPackAddOn))",
                    systemImage: isCapped ? "lock.fill" : "cart.badge.plus"
                )
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCapped || purchasingProduct == .documentPackAddOn)
        }
        .padding()
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    var storyCarousel: some View {
        TabView(selection: $selectedStoryIndex) {
            ForEach(storySlides.indices, id: \.self) { index in
                let slide = storySlides[index]
                storySlideView(slide)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(slide.tint.opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(slide.tint.opacity(0.2), lineWidth: 1)
                    )
                    .tag(index)
            }
        }
        .frame(height: 170)
        .tabViewStyle(.page(indexDisplayMode: .always))
        .accessibilityLabel("Plan value stories")
    }

    func storySlideView(_ slide: PlanStorySlide) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(slide.tint.opacity(0.2))
                    .frame(width: 48, height: 48)
                Image(systemName: slide.icon)
                    .foregroundStyle(slide.tint)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(slide.title)
                    .font(.headline)
                Text(slide.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    var shouldShowRefillQuickAction: Bool {
        !entitlementStore.hasReachedDocumentPackCap
    }

    var refillQuickAction: some View {
        let remaining = entitlementStore.remainingDocumentPackCapacity
        let docsPerPack = QuotaPolicy.addOnDocumentIncrement
        return VStack(alignment: .leading, spacing: 10) {
            Label("Need documents today?", systemImage: "sparkles.rectangle.stack")
                .font(.headline)
            Text("Refill instantly with a document pack. Each pack adds \(docsPerPack) slots without changing your plan.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if remaining > 0 {
                Text("You can add \(remaining) more pack\(remaining == 1 ? "" : "s") before reaching the cap.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                purchase(.documentPackAddOn)
            } label: {
                Label("Refill documents – \(priceLabel(for: .documentPackAddOn))", systemImage: "tray.and.arrow.down.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(purchasingProduct == .documentPackAddOn)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DSColors.surface)
        )
    }

    var managementControls: some View {
        VStack(spacing: 12) {
            Button(action: manageSubscriptions) {
                Label("Manage Subscription", systemImage: "person.crop.circle.badge.checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(action: restorePurchases) {
                if isRestoring {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Restore Purchases", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .disabled(isRestoring)
        }
    }

    var complianceFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Subscriptions renew automatically until cancelled. Payments are charged to your Apple ID account.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Link("Terms of Use", destination: URL(string: "https://openintelligence.ai/terms")!)
                    .font(.caption.weight(.semibold))
                Link("Privacy Policy", destination: URL(string: "https://openintelligence.ai/privacy")!)
                    .font(.caption.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Actions

private extension PlanUpgradeSheet {
    func priceLabel(for product: BillingProduct) -> String {
        if let storeProduct = entitlementStore.product(for: product) {
            return storeProduct.displayPrice
        }
        switch product {
        case .starterMonthly: return "$2.99"
        case .starterAnnual: return "$24.99"
        case .proMonthly: return "$8.99"
        case .proAnnual: return "$82.99"
        case .lifetimeCohort: return "$249.00"
        case .documentPackAddOn: return "$1.99"
        }
    }

    func alternatePriceDescription(for option: PlanTierOption) -> String? {
        guard let altProduct = option.alternateBillingProduct else { return nil }
        let altPrice = priceLabel(for: altProduct)
        if let suffix = option.alternatePriceSuffix {
            return "Or \(altPrice) \(suffix)"
        }
        return "Or \(altPrice)"
    }

    func purchase(_ product: BillingProduct) {
        guard purchasingProduct != product else { return }
        if product == .documentPackAddOn && entitlementStore.hasReachedDocumentPackCap {
            TelemetryCenter.emitBillingEvent(
                "Paywall CTA blocked",
                severity: .warning,
                metadata: [
                    "product": product.rawValue,
                    "reason": "documentPackCap",
                    "entryPoint": entryPoint.analyticsValue
                ]
            )
            alertMessage = "You already have the maximum number of document packs active. Remove documents or upgrade your workspace to unlock more capacity."
            return
        }
        purchasingProduct = product
        TelemetryCenter.emitBillingEvent(
            "Paywall CTA tapped",
            metadata: [
                "product": product.rawValue,
                "entryPoint": entryPoint.analyticsValue
            ]
        )
        Task {
            defer { purchasingProduct = nil }
            do {
                _ = try await entitlementStore.billingService.purchase(product)
            } catch {
                alertMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func restorePurchases() {
        guard !isRestoring else { return }
        isRestoring = true
        Task {
            defer { isRestoring = false }
            await entitlementStore.billingService.restorePurchases()
        }
    }

    func manageSubscriptions() {
        Task {
            do {
                let scene = await MainActor.run {
                    UIApplication.shared.connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                        .first { $0.activationState == .foregroundActive }
                }

                guard let windowScene = scene else {
                    alertMessage = "Unable to locate an active window scene."
                    return
                }

                try await AppStore.showManageSubscriptions(in: windowScene)
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Supporting Models

private struct PlanTierOption: Identifiable {
    let id = UUID()
    let tier: WorkspaceTier
    let product: BillingProduct
    let tagline: String
    let badgeText: String
    let tint: Color
    let isFeatured: Bool
    let alternateBillingProduct: BillingProduct?
    let alternatePriceSuffix: String?
    let features: [String]
}

private struct PlanTierCard: View {
    let option: PlanTierOption
    let price: String
    let alternatePriceDescription: String?
    let hasAccess: Bool
    let isProcessing: Bool
    let ctaAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.tier.displayName)
                        .font(.headline)
                    Text(option.tagline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if option.isFeatured {
                    Text(option.badgeText)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(option.tint.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            Text(price + (option.product.kind == .subscription ? " / mo" : ""))
                .font(.title.bold())

            if let alternatePriceDescription {
                Text(alternatePriceDescription)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(option.features, id: \.self) { feature in
                    Label(feature, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.footnote.weight(.semibold))
                }
            }

            ctaButton(hasAccess: hasAccess, isProcessing: isProcessing)
                .disabled(hasAccess || isProcessing)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(DSColors.surface)
                .shadow(color: option.isFeatured ? option.tint.opacity(0.2) : .clear, radius: 20, x: 0, y: 10)
        )
    }
}

private extension PlanTierCard {
    @ViewBuilder
    func ctaLabel(hasAccess: Bool, isProcessing: Bool) -> some View {
        if hasAccess {
            Label("Current Plan", systemImage: "checkmark")
                .frame(maxWidth: .infinity)
        } else if isProcessing {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else {
            Label("Upgrade to \(option.tier.displayName)", systemImage: "arrow.up.forward.app")
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    func ctaButton(hasAccess: Bool, isProcessing: Bool) -> some View {
        if option.isFeatured {
            Button(action: ctaAction) {
                ctaLabel(hasAccess: hasAccess, isProcessing: isProcessing)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button(action: ctaAction) {
                ctaLabel(hasAccess: hasAccess, isProcessing: isProcessing)
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct PlanStorySlide: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
}
