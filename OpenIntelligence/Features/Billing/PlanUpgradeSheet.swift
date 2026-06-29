import StoreKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Full-screen paywall surface that highlights plan tiers, add-ons, and billing controls.
struct PlanUpgradeSheet: View {
    let entryPoint: PlanUpgradeEntryPoint

    @EnvironmentObject private var entitlementStore: EntitlementStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
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
            tagline: "Expand your workspace with no long-term commitment",
            badgeText: "Flexible",
            tint: .purple,
            isFeatured: false,
            features: [
                "Up to 1,000 documents",
                "10 libraries",
                "Expanded workspace limits",
                "Cancel anytime",
            ]
        ),
        PlanTierOption(
            tier: .pro,
            planName: "Pro (Annual)",
            product: .proAnnual,
            tagline: "7-day free trial, then $29.99/yr",
            badgeText: "Best Value",
            tint: .purple,
            isFeatured: true,
            features: [
                "7-day free trial included",
                "Up to 1,000 documents",
                "10 libraries",
                "Save 58% vs monthly",
            ]
        ),
        PlanTierOption(
            tier: .lifetime,
            planName: "Lifetime Cohort",
            product: .lifetimeCohort,
            tagline: "One-time unlock with no renewal",
            badgeText: "One-Time",
            tint: .orange,
            isFeatured: false,
            features: [
                "Unlimited documents",
                "20 libraries",
                "Everything in Pro",
                "No renewal — one-time purchase",
            ]
        ),
    ]

    private let storySlides: [PlanStorySlide] = [
        PlanStorySlide(
            title: "Unlock more capacity",
            subtitle: "Pro expands your workspace from the free tier to up to 1,000 documents and 10 libraries.",
            icon: "bolt.fill",
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
            subtitle: "Lifetime keeps Pro-level access unlocked with unlimited documents and up to 20 libraries in a single purchase.",
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
                    if shouldShowRefillQuickAction {
                        refillQuickAction
                    }

                    ForEach(planOptions) { option in
                        tierCard(for: option)
                    }

                    if entitlementStore.shouldOfferDocumentPack {
                        addOnCard
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
                    "currentTier": entitlementStore.activeTier.rawValue,
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
                Label("Current plan: \(entitlementStore.activeTier.displayName)", systemImage: "creditcard")
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
            hasAccess: entitlementStore.activeTier.isAtLeast(option.tier),
            // "canPurchase" here means StoreKit metadata has been loaded.
            // We still allow tapping the CTA while loading; the tap will refresh and retry.
            canPurchase: canPurchase(option.product),
            isProcessing: purchasingProduct == option.product || isRefreshingProducts,
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
            .disabled(isCapped || isRefreshingProducts || purchasingProduct != nil)
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
        #if os(iOS)
        .tabViewStyle(.page(indexDisplayMode: .always))
        #endif
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
        entitlementStore.shouldOfferDocumentPack && !entitlementStore.hasReachedDocumentPackCap
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
            .disabled(purchasingProduct != nil || isRefreshingProducts)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DSColors.surface)
        )
    }

    var multiDocumentTip: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "rectangle.stack.badge.person.crop")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text("Built for personal research")
                    .font(.subheadline.weight(.semibold))
                Text("Spin up as many document chats as you need while keeping each workspace organized.")
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Subscriptions automatically renew at the price and duration selected above unless cancelled at least 24 hours before the end of the current period. Payments are charged to your App Store account. You can manage your subscriptions and turn off auto-renewal in your App Store Account Settings after purchase.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Link("Terms of Use (EULA)", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    .font(.caption.weight(.semibold))
                Link("Privacy Policy", destination: URL(string: "https://gunzino.me/openintelligence/privacy")!)
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
        case .proAnnual: return "$29.99"
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
        }
    }

    func manageSubscriptions() {
        Task {
            do {
#if canImport(UIKit) && !targetEnvironment(macCatalyst)
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
#elseif os(macOS) || targetEnvironment(macCatalyst)
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    openURL(url)
                }
#else
                alertMessage = "Subscription management is unavailable on this platform."
#endif
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

            if option.product.kind == .subscription {
                Text(option.product == .proMonthly ? "1-Month Auto-Renewing Subscription" : "1-Year Auto-Renewing Subscription")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, -8)
            }

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
