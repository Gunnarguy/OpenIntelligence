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
            tagline: "Maximum mode every day, month to month",
            badgeText: "Flexible",
            tint: .purple,
            isFeatured: false,
            features: [
                "Maximum mode with no daily cap",
                "Up to 1,000 documents",
                "10 libraries",
                "Cancel anytime",
            ]
        ),
        PlanTierOption(
            tier: .pro,
            planName: "Pro (Annual)",
            product: .proAnnual,
            tagline: "Maximum mode every day, one payment a year",
            badgeText: "Best Value",
            tint: .purple,
            isFeatured: true,
            features: [
                "Maximum mode with no daily cap",
                "Up to 1,000 documents",
                "10 libraries",
                "Save 58% vs monthly",
            ]
        ),
        PlanTierOption(
            tier: .lifetime,
            planName: "Lifetime Cohort",
            product: .lifetimeCohort,
            tagline: "Everything, once, for good",
            badgeText: "One-Time",
            tint: .orange,
            isFeatured: false,
            features: [
                "Maximum mode with no daily cap",
                "Unlimited documents",
                "20 libraries",
                "One payment, no renewal",
            ]
        ),
    ]

    private let storySlides: [PlanStorySlide] = [
        PlanStorySlide(
            title: "The same model in every plan",
            subtitle: "Apple Intelligence on your device, Deep Think, and Private Cloud Compute after you approve what is sent: all of it is free. Pro and Lifetime remove the limits.",
            icon: "bolt.fill",
            tint: .orange
        ),
        PlanStorySlide(
            title: "Privacy guarantee",
            subtitle:
                "Reading, searching and citing happen on your device in every plan. Nothing ever goes to a third-party AI provider.",
            icon: "lock.shield.fill",
            tint: .teal
        ),
        PlanStorySlide(
            title: "Maximum, every day",
            subtitle:
                "Maximum is the highest-effort mode, three runs a day on the free plan. Pro lifts the cap; Lifetime does too, with unlimited documents, for one payment.",
            icon: "arrow.up.right.circle.fill",
            tint: .purple
        ),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heroSection
                    launchSaleBanner
                    socialProofBanner
                    whyUpgradeNowSection
                    storyCarousel

                    ForEach(planOptions) { option in
                        tierCard(for: option)
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
        .alert(
            alertMessage ?? "",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
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
        .task {
            // Re-read prices every time the paywall opens.
            //
            // `EntitlementStore` loads its products once at init, and this app can stay running
            // for weeks on a Mac. Without this, a price change that ended or was cancelled
            // mid-session would leave a stale cheaper price cached, and the sale banner would
            // keep advertising a discount the customer would not actually be charged. Refreshing
            // here keeps what the banner claims and what checkout charges the same number.
            await entitlementStore.billingService.refreshProducts()
        }
    }
}

// MARK: - Sections

extension PlanUpgradeSheet {
    fileprivate var heroSection: some View {
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

    fileprivate var socialProofBanner: some View {
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

    /// The launch-sale strip, shown only when Lifetime has a confirmed discount.
    ///
    /// Names the plan and its own real percentage rather than a headline figure, so the strip
    /// cannot promise more than the card below it delivers. Only Lifetime is ever discounted;
    /// `LaunchSale` explains why the subscriptions are left alone.
    @ViewBuilder
    fileprivate var launchSaleBanner: some View {
        if let offer = saleOffer(for: .lifetimeCohort) {
            HStack(spacing: 10) {
                Image(systemName: "tag.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch sale: Lifetime is \(offer.percentOff)% off")
                        .font(.subheadline.weight(.bold))
                    Text("Ends \(LaunchSale.deadlineText(for: offer.endDate)). One payment, no renewal.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.green.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.green.opacity(0.35), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
        }
    }

    fileprivate var whyUpgradeNowSection: some View {
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

    fileprivate func tierCard(for option: PlanTierOption) -> some View {
        PlanTierCard(
            option: option,
            price: priceLabel(for: option.product),
            priceSuffix: priceSuffix(for: option.product),
            saleOffer: saleOffer(for: option.product),
            hasAccess: entitlementStore.activeTier.isAtLeast(option.tier),
            // "canPurchase" here means StoreKit metadata has been loaded.
            // We still allow tapping the CTA while loading; the tap will refresh and retry.
            canPurchase: canPurchase(option.product),
            isProcessing: purchasingProduct == option.product || isRefreshingProducts,
            ctaAction: { purchase(option.product) }
        )
    }

    fileprivate var storyCarousel: some View {
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

    fileprivate func storySlideView(_ slide: PlanStorySlide) -> some View {
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

    fileprivate var multiDocumentTip: some View {
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

    fileprivate var managementControls: some View {
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

    fileprivate var complianceFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                "Subscriptions automatically renew at the price and duration selected above unless cancelled at least 24 hours before the end of the current period. Payments are charged to your App Store account. You can manage your subscriptions and turn off auto-renewal in your App Store Account Settings after purchase."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Link(
                    "Terms of Use (EULA)",
                    destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
                )
                .font(.caption.weight(.semibold))
                Link("Privacy Policy", destination: URL(string: "https://gunzino.me/openintelligence/privacy")!)
                    .font(.caption.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Actions

extension PlanUpgradeSheet {
    fileprivate func canPurchase(_ product: BillingProduct) -> Bool {
        entitlementStore.product(for: product) != nil
    }

    fileprivate func priceLabel(for product: BillingProduct) -> String {
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

    /// The discount to advertise for this product, or `nil` to say nothing.
    ///
    /// Delegates every judgement to `LaunchSale`, which refuses to return an offer unless
    /// StoreKit's live price is genuinely below the recorded regular price in the customer's
    /// own currency. When StoreKit metadata has not loaded there is no live price to compare,
    /// so no claim is made.
    fileprivate func saleOffer(for product: BillingProduct) -> LaunchSaleOffer? {
        guard let storeProduct = entitlementStore.product(for: product) else { return nil }
        return LaunchSale.offer(for: product, storeProduct: storeProduct)
    }

    fileprivate func priceSuffix(for product: BillingProduct) -> String? {
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

    fileprivate func purchase(_ product: BillingProduct) {
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
            alertMessage =
                "You already have the maximum number of document packs active. Remove documents or upgrade your workspace to unlock more capacity."
            return
        }

        guard canPurchase(product) else {
            #if DEBUG
                if entitlementStore.isDebugBillingSimulationEnabled {
                    // DEBUG fallback: allow local UI validation without StoreKit metadata.
                    entitlementStore.simulateDebugPurchase(product)
                    #if targetEnvironment(simulator)
                        let hint =
                            "You’re running in the iOS Simulator. Real App Store Connect products won’t load here unless you enable a StoreKit Configuration (.storekit) in the scheme."
                    #else
                        let hint =
                            "If you’re testing on a device, ensure you’re signed into a Sandbox account (Settings → App Store → Sandbox Account) and that your IAPs/subscriptions exist and are available in App Store Connect."
                    #endif

                    alertMessage =
                        "StoreKit didn’t return product metadata, so this purchase was simulated (DEBUG-only).\n\n\(hint)"
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
                    let baseMessage =
                        (error as? LocalizedError)?.errorDescription
                        ?? "Purchases aren’t available right now. Please check your internet connection and try again."

                    #if targetEnvironment(simulator)
                        // In the simulator, real App Store Connect products typically won't load unless the
                        // Run scheme has a StoreKit Configuration (.storekit) attached.
                        // Provide a direct, actionable hint to avoid the "worked yesterday" confusion.
                        if entitlementStore.product(for: product) == nil {
                            alertMessage =
                                "\(baseMessage)\n\nYou’re running in the iOS Simulator without a StoreKit Configuration attached.\n\nTo test purchases locally, run the `OpenIntelligence-StoreKitTesting` scheme (or attach `StoreKitConfiguration.storekit` to your Run action)."
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

    fileprivate func restorePurchases() {
        guard !isRestoring else { return }
        isRestoring = true
        Task {
            defer { isRestoring = false }
            await entitlementStore.billingService.restorePurchases()
        }
    }

    fileprivate func manageSubscriptions() {
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
    /// Non-nil only when `LaunchSale` has confirmed the live price is genuinely below the
    /// regular one in this customer's currency. See `LaunchSale` for why that is guarded.
    let saleOffer: LaunchSaleOffer?
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

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(price + (priceSuffix ?? ""))
                        .font(.title.bold())
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)

                    if let saleOffer {
                        Text(saleOffer.regularDisplayPrice)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .strikethrough(true, color: .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility1)

                        Text("\(saleOffer.percentOff)% off")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.green))
                            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    }
                }

                if let saleOffer {
                    Text("Launch price until \(LaunchSale.deadlineText(for: saleOffer.endDate))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
            }
            // Deliberately no accessibility modifiers here. The whole card is a single element
            // (see the bottom of this view), and a label applied inside it would be discarded.
            // The sale is spoken through `accessibilityValueText` instead.

            if option.product.kind == .subscription {
                Text(
                    option.product == .proMonthly
                        ? "1-Month Auto-Renewing Subscription" : "1-Year Auto-Renewing Subscription"
                )
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
        .accessibilityValue(accessibilityValueText)
        .accessibilityHint(hasAccess ? "Already unlocked" : "Double tap to purchase")
    }

    /// What VoiceOver reads for the card, including the sale when one is running.
    ///
    /// The card is a single accessibility element, so this is the only place the discount can
    /// be spoken. A label applied to the price row inside would be discarded.
    private var accessibilityValueText: String {
        guard let saleOffer else { return "\(price). \(option.tagline)" }
        return "\(price), reduced from \(saleOffer.regularDisplayPrice), "
            + "\(saleOffer.percentOff) percent off until "
            + "\(LaunchSale.deadlineText(for: saleOffer.endDate)). \(option.tagline)"
    }
}

extension PlanTierCard {
    @ViewBuilder
    fileprivate func ctaLabel(hasAccess: Bool, canPurchase: Bool, isProcessing: Bool) -> some View {
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
    fileprivate func ctaButton(hasAccess: Bool, canPurchase: Bool, isProcessing: Bool) -> some View {
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
