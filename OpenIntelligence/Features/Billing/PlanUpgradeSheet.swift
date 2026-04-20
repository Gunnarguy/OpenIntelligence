import StoreKit
import SwiftUI
import UIKit

/// Full-screen paywall surface that highlights plan tiers and billing controls.
struct PlanUpgradeSheet: View {
    let entryPoint: PlanUpgradeEntryPoint

    @EnvironmentObject private var entitlementStore: EntitlementStore
    @Environment(\.dismiss) private var dismiss
    @State private var purchasingProduct: BillingProduct?
    @State private var alertMessage: String?
    @State private var isRefreshingProducts: Bool = false
    @State private var isRestoring = false
    @State private var selectedStoryIndex = 0
    @State private var showingTerms = false
    @State private var showingPrivacy = false

    /// Sorted top-to-bottom by level and billing period to match the release catalog.
    /// The UI intentionally surfaces every SKU so we can spot missing App Store Connect
    /// configuration early (and avoid "only 3 products show up" surprises).
    private let planOptions: [PlanTierOption] = [
        PlanTierOption(
            tier: .pro,
            planName: "Pro (Monthly)",
            product: .proMonthly,
            tagline: "Unlock unlimited Maximum mode with flexible billing",
            badgeText: "Flexible",
            tint: .purple,
            isFeatured: false,
            features: [
                "Unlimited Maximum mode",
                "Up to 1,000 documents",
                "5 libraries",
                "Cancel anytime",
            ]
        ),
        PlanTierOption(
            tier: .pro,
            planName: "Pro (Annual)",
            product: .proAnnual,
            tagline: "Unlimited Maximum mode with the best recurring value",
            badgeText: "Best Value",
            tint: .purple,
            isFeatured: true,
            features: [
                "Unlimited Maximum mode",
                "Up to 1,000 documents",
                "5 libraries",
                "Save 30% vs monthly",
            ]
        ),
        PlanTierOption(
            tier: .lifetime,
            planName: "Lifetime Cohort",
            product: .lifetimeCohort,
            tagline: "Top-tier unlock with no renewal",
            badgeText: "One-Time",
            tint: .orange,
            isFeatured: false,
            features: [
                "Unlimited Maximum mode",
                "Unlimited documents",
                "10 libraries",
                "Everything unlocked",
            ]
        ),
    ]

    private let storySlides: [PlanStorySlide] = [
        PlanStorySlide(
            title: "Maximum without the cap",
            subtitle: "Paid plans remove the daily Maximum limit while keeping Standard and Deep Think available everywhere.",
            icon: "flame.fill",
            tint: .orange
        ),
        PlanStorySlide(
            title: "Privacy guarantee",
            subtitle: "All tiers keep knowledge on-device or Apple PCC—zero third-party AI sharing. Your IP stays yours.",
            icon: "lock.shield.fill",
            tint: .teal
        ),
        PlanStorySlide(
            title: "Lifetime, without renewal",
            subtitle: "Lifetime keeps Maximum unlocked plus unlimited documents and 10 libraries in a single purchase.",
            icon: "arrow.up.right.circle.fill",
            tint: .purple
        ),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heroSection
                    socialProofBanner
                    whyUpgradeNowSection
                    storyCarousel

                    ForEach(planOptions) { option in
                        tierCard(for: option)
                    }

                    if entitlementStore.addOnPacks > 0 {
                        legacyDocumentPackNotice
                    }
                    multiDocumentTip
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
        .sheet(isPresented: $showingTerms) {
            TermsOfServiceView()
        }
        .sheet(isPresented: $showingPrivacy) {
            PrivacyPolicyView()
        }
        .onAppear {
            TelemetryCenter.emitBillingEvent(
                "Paywall viewed",
                metadata: [
                    "entryPoint": entryPoint.analyticsValue,
                    "currentTier": entitlementStore.effectiveTier.rawValue,
                ]
            )
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
            HStack {
                Label("Current plan: \(entitlementStore.currentPlanDisplayName)", systemImage: "creditcard")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Capsule())
                Spacer()
            }
        }
    }

    var socialProofBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.3.fill")
                .foregroundStyle(.purple)
            Text("Upgrade anytime — cancel in App Store settings.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.purple.opacity(0.08))
        )
    }

    var whyUpgradeNowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Why upgrade now?")
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                BenefitRow(icon: "doc.badge.plus", text: "Higher document limits", tint: .orange)
                BenefitRow(icon: "flame.fill", text: "Unlimited Maximum mode", tint: .red)
                BenefitRow(icon: "square.stack.3d.up.fill", text: "More libraries", tint: .blue)
                BenefitRow(icon: "creditcard", text: "One-time lifetime option", tint: .purple)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DSColors.surface.opacity(0.6))
        )
    }

    func tierCard(for option: PlanTierOption) -> some View {
        PlanTierCard(
            option: option,
            price: priceLabel(for: option.product),
            priceSuffix: priceSuffix(for: option.product),
            hasAccess: entitlementStore.effectiveTier.isAtLeast(option.tier),
            // "canPurchase" here means StoreKit metadata has been loaded.
            // We still allow tapping the CTA while loading; the tap will refresh and retry.
            canPurchase: canPurchase(option.product),
            isProcessing: purchasingProduct == option.product || isRefreshingProducts,
            ctaAction: { purchase(option.product) }
        )
    }

    var legacyDocumentPackNotice: some View {
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Legacy Document Packs", systemImage: "shippingbox.fill")
                    .font(.headline)
                Spacer()
                Text("Grandfathered")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Your existing document-pack purchases are still honored, and paid history now receives Lifetime access in-app.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Document packs are no longer sold in-app.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
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

    var multiDocumentTip: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "rectangle.stack.badge.person.crop")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text("Built for personal research")
                    .font(.subheadline.weight(.semibold))
                Text("Standard and Deep Think stay available on every plan. Paid tiers mainly expand capacity and remove the Maximum cap.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
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
                Button("Terms of Use") { showingTerms = true }
                    .font(.caption.weight(.semibold))
                Button("Privacy Policy") { showingPrivacy = true }
                    .font(.caption.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Actions

private extension PlanUpgradeSheet {
    func canPurchase(_ product: BillingProduct) -> Bool {
        entitlementStore.product(for: product) != nil
    }

    func priceLabel(for product: BillingProduct) -> String {
        if let storeProduct = entitlementStore.product(for: product) {
            return storeProduct.displayPrice
        }
        switch product {
        case .proMonthly: return "$5.99"
        case .proAnnual: return "$49.99"
        case .lifetimeCohort: return "$59.99"
        case .documentPackAddOn: return "$2.99"
        }
    }

    func priceSuffix(for product: BillingProduct) -> String? {
        guard product.kind == .subscription else { return nil }

        if let storeProduct = entitlementStore.product(for: product),
           let period = storeProduct.subscription?.subscriptionPeriod
        {
            switch period.unit {
            case .month:
                return " / mo"
            case .year:
                return " / yr"
            case .week:
                return " / wk"
            case .day:
                return " / day"
            @unknown default:
                break
            }
        }

        // Fallback for cases when StoreKit metadata is not loaded yet.
        switch product {
        case .proMonthly:
            return " / mo"
        case .proAnnual:
            return " / yr"
        default:
            return nil
        }
    }

    func purchase(_ product: BillingProduct) {
        // Avoid overlapping purchase flows. StoreKit itself has protection, but keeping the UI
        // single-flight prevents confusing state (multiple spinners/alerts).
        guard purchasingProduct == nil else { return }
        if isRefreshingProducts {
            alertMessage = "Purchases are still loading. Please try again in a moment."
            return
        }

        // This gate does not require StoreKit metadata.
        if product == .documentPackAddOn, !entitlementStore.shouldOfferDocumentPack {
            alertMessage = "Document packs are no longer sold in-app. Existing pack purchases are still honored."
            return
        }

        if product == .documentPackAddOn, entitlementStore.hasReachedDocumentPackCap {
            TelemetryCenter.emitBillingEvent(
                "Paywall CTA blocked",
                severity: .warning,
                metadata: [
                    "product": product.rawValue,
                    "reason": "documentPackCap",
                    "entryPoint": entryPoint.analyticsValue,
                ]
            )
            alertMessage = "You already have the maximum number of document packs active. Remove documents or upgrade your workspace to unlock more capacity."
            return
        }

        if product == .documentPackAddOn, entitlementStore.effectiveTier == .lifetime {
            alertMessage = "Lifetime already unlocks unlimited documents, so document packs are not needed on this account."
            return
        }

        guard canPurchase(product) else {
            #if DEBUG
                if entitlementStore.isDebugBillingSimulationEnabled {
                    // DEBUG fallback: allow local UI validation without StoreKit metadata.
                    entitlementStore.simulateDebugPurchase(product)
                    #if targetEnvironment(simulator)
                        let hint = "You’re running in the iOS Simulator. Real App Store Connect products won’t load here unless you enable a StoreKit Configuration (.storekit) in the scheme."
                    #else
                        let hint = "If you’re testing on a device, ensure you’re signed into a Sandbox account (Settings → App Store → Sandbox Account) and that your IAPs/subscriptions exist and are available in App Store Connect."
                    #endif

                    alertMessage = "StoreKit didn’t return product metadata, so this purchase was simulated (DEBUG-only).\n\n\(hint)"
                    return
                }
            #endif

            // Default behavior (Release + Debug when simulation is disabled): products can take a
            // moment to load on cold start. When the user taps, force a refresh and retry once.
            isRefreshingProducts = true
            purchasingProduct = product

            Task {
                defer {
                    purchasingProduct = nil
                    isRefreshingProducts = false
                }

                await entitlementStore.billingService.refreshProducts()

                do {
                    _ = try await entitlementStore.billingService.purchase(product)
                } catch {
                    let baseMessage = (error as? LocalizedError)?.errorDescription
                        ?? "Purchases aren’t available right now. Please check your internet connection and try again."

                    #if targetEnvironment(simulator)
                        // In the simulator, real App Store Connect products typically won't load unless the
                        // Run scheme has a StoreKit Configuration (.storekit) attached.
                        // Provide a direct, actionable hint to avoid the "worked yesterday" confusion.
                        if entitlementStore.product(for: product) == nil {
                            alertMessage = "\(baseMessage)\n\nYou’re running in the iOS Simulator without a StoreKit Configuration attached.\n\nTo test purchases locally, run the `OpenIntelligence-StoreKitTesting` scheme (or attach `StoreKitConfiguration.storekit` to your Run action)."
                        } else {
                            alertMessage = baseMessage
                        }
                    #else
                        alertMessage = baseMessage
                    #endif

                    TelemetryCenter.emitBillingEvent(
                        "Paywall purchase blocked",
                        severity: .warning,
                        metadata: [
                            "product": product.rawValue,
                            "reason": "productNotLoadedOrPurchaseFailed",
                            "entryPoint": entryPoint.analyticsValue,
                            "error": error.localizedDescription,
                        ]
                    )
                }
            }
            return
        }
        purchasingProduct = product
        TelemetryCenter.emitBillingEvent(
            "Paywall CTA tapped",
            metadata: [
                "product": product.rawValue,
                "entryPoint": entryPoint.analyticsValue,
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
            await entitlementStore.reconcileEntitlementsOnLaunch()
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
    let planName: String
    let product: BillingProduct
    let tagline: String
    let badgeText: String
    let tint: Color
    let isFeatured: Bool
    let features: [String]
}

private struct PlanTierCard: View {
    let option: PlanTierOption
    let price: String
    let priceSuffix: String?
    let hasAccess: Bool
    let canPurchase: Bool
    let isProcessing: Bool
    let ctaAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.planName)
                        .font(.headline)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    Text(option.tagline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                }
                Spacer()
                if option.isFeatured {
                    Text(option.badgeText)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(option.tint.opacity(0.15))
                        .clipShape(Capsule())
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
            }

            Text(price + (priceSuffix ?? ""))
                .font(.title.bold())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(option.features, id: \.self) { feature in
                    Label(feature, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.footnote.weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
            }

            ctaButton(hasAccess: hasAccess, canPurchase: canPurchase, isProcessing: isProcessing)
                // Important: don't disable the CTA when StoreKit metadata hasn't loaded yet.
                // In release builds, tapping triggers a refresh + retry; in DEBUG we may simulate.
                .disabled(hasAccess || isProcessing)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(DSColors.surface)
                .shadow(color: option.isFeatured ? option.tint.opacity(0.2) : .clear, radius: 20, x: 0, y: 10)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(option.planName) plan")
        .accessibilityValue("\(price). \(option.tagline)")
        .accessibilityHint(hasAccess ? "Already unlocked" : "Double tap to purchase")
    }
}

private extension PlanTierCard {
    @ViewBuilder
    func ctaLabel(hasAccess: Bool, canPurchase: Bool, isProcessing: Bool) -> some View {
        if hasAccess {
            Label("Unlocked", systemImage: "checkmark")
                .frame(maxWidth: .infinity)
        } else if isProcessing {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else if !canPurchase {
            Label("Tap to load", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
        } else {
            Label("Choose \(option.planName)", systemImage: "arrow.up.forward.app")
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    func ctaButton(hasAccess: Bool, canPurchase: Bool, isProcessing: Bool) -> some View {
        if option.isFeatured {
            Button(action: ctaAction) {
                ctaLabel(hasAccess: hasAccess, canPurchase: canPurchase, isProcessing: isProcessing)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button(action: ctaAction) {
                ctaLabel(hasAccess: hasAccess, canPurchase: canPurchase, isProcessing: isProcessing)
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

private struct BenefitRow: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

#Preview {
    PlanUpgradeSheet(entryPoint: .settings)
        .environmentObject(EntitlementStore(billingService: StoreKitBillingService()))
}
