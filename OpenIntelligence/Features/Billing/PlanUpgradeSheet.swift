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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var purchasingProduct: BillingProduct?
    @State private var alertMessage: String?
    @State private var isRefreshingProducts: Bool = false
    @State private var isRestoring = false
    @State private var showingRedeemCode = false
    @State private var selectedStoryIndex = 0
    @State private var showingTerms = false
    @State private var showingPrivacy = false
    /// The storefront's country, for a sale's regular price (5.7).
    @ObservedObject private var storefront = StorefrontTerritory.shared

    /// Sorted top-to-bottom by level and billing period to match the release catalog.
    /// The UI intentionally surfaces every SKU so we can spot missing App Store Connect
    /// configuration early (and avoid "only 3 products show up" surprises).
    ///
    /// No saving is written here as fixed text. Until 5.5 the Annual card carried a hardcoded
    /// "Save 58% vs monthly" bullet, true only where both prices moved together; the savings now
    /// come from `dealBadge(for:)`, per storefront, from StoreKit's live prices.
    private let planOptions: [PlanTierOption] = [
        PlanTierOption(
            tier: .pro,
            planName: "Pro (Monthly)",
            product: .proMonthly,
            tagline: "Maximum mode every day, billed monthly",
            badgeText: "Month to month",
            tint: .accentColor,
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
            badgeText: nil,
            tint: .accentColor,
            isFeatured: true,
            features: [
                "Maximum mode with no daily cap",
                "Up to 1,000 documents",
                "10 libraries",
                "Cancel anytime",
            ]
        ),
        PlanTierOption(
            tier: .lifetime,
            planName: "Lifetime",
            product: .lifetimeCohort,
            tagline: "Everything, once, for good",
            badgeText: "Pay once",
            tint: .orange,
            isFeatured: false,
            features: [
                "Maximum mode with no daily cap",
                "Unlimited documents",
                "20 libraries",
                "Never expires",
            ]
        ),
    ]

    private let storySlides: [PlanStorySlide] = [
        PlanStorySlide(
            title: "The same model in every plan",
            subtitle: "Apple Intelligence on your device, Deep Think, and Private Cloud Compute after you approve what is sent: all of it is free. Pro and Lifetime remove the limits.",
            icon: "bolt.fill",
            tint: .accentColor
        ),
        PlanStorySlide(
            title: "Privacy guarantee",
            subtitle:
                "Reading, searching and citing happen on your device in every plan. Nothing ever goes to a third-party AI provider.",
            icon: "lock.shield.fill",
            tint: .accentColor
        ),
        PlanStorySlide(
            title: "Maximum, every day",
            subtitle:
                "Maximum is the highest-effort mode, three runs a day on the free plan. Pro lifts the cap; Lifetime does too, with unlimited documents, for one payment.",
            icon: "arrow.up.right.circle.fill",
            tint: .orange
        ),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.xl) {
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
                .padding(.horizontal, DSSpacing.lg)
                .padding(.vertical, DSSpacing.xl)
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
            #if os(iOS)
            // Inline at accessibility text sizes, where the large title was cut to "Workspace..." (5.7).
            .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .large)
            #endif
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
        .task { await AppStoreRatingService.refreshIfStale() }
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
            await storefront.refresh()
        }
    }
}

// MARK: - Sections

extension PlanUpgradeSheet {
    fileprivate var heroSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text(entryPoint.headline)
                .font(.title2.weight(.semibold))
            Text(entryPoint.subheadline)
                .font(.body)
                .foregroundStyle(DSColors.secondaryText)
            HStack {
                Label("Current plan: \(entitlementStore.activeTier.displayName)", systemImage: "creditcard")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.xs)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Capsule())
                Spacer()
            }
        }
    }

    /// Two things a buyer can check on the product page, and nothing else. The rating line
    /// appears only once the store count is large enough to mean something; see
    /// `AppStoreRatingSnapshot.minimumRatingCount`. Until 5.4 this banner said "Upgrade anytime,
    /// cancel in App Store settings", which is a footer, not proof.
    fileprivate var socialProofBanner: some View {
        // The words in the label color and the color in the icons (5.7): gray words on the tint measured 3.34
        // to 1.
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Label {
                Text("App Store privacy label: Data Not Collected")
            } icon: {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(DSColors.readable(.accentColor))
            }
            if let rating = AppStoreRatingService.cached(), rating.isWorthShowing {
                Label {
                    Text(rating.line)
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "star.fill")
                        .foregroundStyle(DSColors.readable(.accentColor))
                }
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(DSColors.primaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
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
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "tag.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text("Launch sale: Lifetime is \(offer.percentOff)% off")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                    Text("Ends \(LaunchSale.deadlineText(for: offer.endDate)). One payment, no renewal.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.vertical, DSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .fill(Color.green.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .strokeBorder(Color.green.opacity(0.35), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
        }
    }

    fileprivate var whyUpgradeNowSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text("Why upgrade now?")
                .font(.headline)
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                BenefitRow(icon: "doc.badge.plus", text: "Higher document limits", tint: .accentColor)
                BenefitRow(icon: "square.stack.3d.up.fill", text: "More libraries", tint: .accentColor)
                BenefitRow(icon: "creditcard", text: "One-time lifetime option", tint: .accentColor)
            }
        }
        .padding(DSSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.surface.opacity(0.6))
        )
    }

    fileprivate func tierCard(for option: PlanTierOption) -> some View {
        PlanTierCard(
            option: option,
            price: priceLabel(for: option.product),
            priceSuffix: priceSuffix(for: option.product),
            saleOffer: saleOffer(for: option.product),
            dealBadge: dealBadge(for: option.product),
            comparisons: comparisons(for: option.product),
            hasAccess: entitlementStore.activeTier.isAtLeast(option.tier),
            // "canPurchase" here means StoreKit metadata has been loaded.
            // We still allow tapping the CTA while loading; the tap will refresh and retry.
            canPurchase: canPurchase(option.product),
            isProcessing: purchasingProduct == option.product || isRefreshingProducts,
            ctaAction: { purchase(option.product) }
        )
    }

    /// As tall as its tallest page plus the page dots (5.7), measured from a hidden copy of the pages behind it. At a
    /// fixed 170 points the first page's last line ran under the dots at the default text size, and larger text was
    /// cut.
    fileprivate var storyCarousel: some View {
        ZStack {
            ForEach(storySlides.indices, id: \.self) { index in
                storySlideView(storySlides[index])
                    .padding(DSSpacing.lg)
            }
        }
        .padding(.bottom, DSSpacing.xxl)
        .hidden()
        .accessibilityHidden(true)
        .overlay {
            TabView(selection: $selectedStoryIndex) {
                ForEach(storySlides.indices, id: \.self) { index in
                    let slide = storySlides[index]
                    storySlideView(slide)
                        .padding(DSSpacing.lg)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .background(
                            RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous)
                                .fill(slide.tint.opacity(0.15))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous)
                                .stroke(slide.tint.opacity(0.2), lineWidth: 1)
                        )
                        .padding(.bottom, DSSpacing.xxl)
                        .tag(index)
                }
            }
            #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .always))
            #endif
            .accessibilityLabel("Plan value stories")
        }
    }

    fileprivate func storySlideView(_ slide: PlanStorySlide) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.lg) {
            ZStack {
                Circle()
                    .fill(slide.tint.opacity(0.2))
                    .frame(width: 48, height: 48)
                Image(systemName: slide.icon)
                    .foregroundStyle(slide.tint)
            }
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(slide.title)
                    .font(.headline)
                // The label color on the slide's tint, where gray measured 4.53 to 1 on the orange one (5.7).
                Text(slide.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(DSColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    fileprivate var multiDocumentTip: some View {
        HStack(alignment: .top, spacing: DSSpacing.md) {
            Image(systemName: "rectangle.stack.badge.person.crop")
                .font(.title3)
                .foregroundStyle(DSColors.accent)
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text("Built for personal research")
                    .font(.subheadline.weight(.medium))
                Text("Spin up as many document chats as you need while keeping each workspace organized.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(DSSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
    }

    fileprivate var managementControls: some View {
        VStack(spacing: DSSpacing.md) {
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

            // Apple's own sheet for an offer code made in App Store Connect. Apple's rule is that a
            // code is redeemed through that sheet and not through a field of the app's own.
            Button {
                showingRedeemCode = true
            } label: {
                Label("Redeem a Code", systemImage: "giftcard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .redeemCodeSheet(isPresented: $showingRedeemCode) { outcome in
                if let message = outcome.message { alertMessage = message }
                guard outcome.readsEntitlementsAgain else { return }
                // Reads the App Store's current entitlements again; nothing is asked of the person.
                // After a pause, so the listener that applies the redeemed transaction goes first
                // and this read cannot overwrite it with an older state.
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    await entitlementStore.reconcileEntitlementsOnLaunch()
                }
            }
        }
    }

    fileprivate var complianceFooter: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(
                "Subscriptions automatically renew at the price and duration selected above unless cancelled at least 24 hours before the end of the current period. Payments are charged to your App Store account. You can manage your subscriptions and turn off auto-renewal in your App Store Account Settings after purchase."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DSSpacing.lg) {
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

    /// StoreKit's price for this storefront, or a US fallback until StoreKit answers.
    ///
    /// The fallbacks are the US prices from 2026-10-01 (Lifetime from 2026-09-30). They only
    /// fill the card while products load, and nothing is computed from them: every badge and
    /// caption below waits for the live price.
    fileprivate func priceLabel(for product: BillingProduct) -> String {
        if let storeProduct = entitlementStore.product(for: product) {
            return storeProduct.displayPrice
        }
        switch product {
        case .proMonthly: return "$4.99"
        case .proAnnual: return "$24.99"
        case .lifetimeCohort: return "$49.99"
        case .documentPackAddOn: return "$2.99"
        }
    }

    /// Two live StoreKit products priced in the same currency, or nil. Every comparison on a card
    /// needs both sides from the customer's own storefront; a US fallback on either side would
    /// make it a guess.
    fileprivate func livePrices(_ first: BillingProduct, _ second: BillingProduct) -> (Product, Product)? {
        guard let a = entitlementStore.product(for: first),
            let b = entitlementStore.product(for: second),
            a.priceFormatStyle.currencyCode == b.priceFormatStyle.currencyCode
        else { return nil }
        return (a, b)
    }

    /// The saving against another plan, drawn as a small capsule under the price, or nil when
    /// there is nothing true to say: Annual against twelve months of Monthly, and Lifetime when
    /// it costs less than a year of Monthly. Monthly is what the others are measured against, so
    /// it has none.
    fileprivate func dealBadge(for product: BillingProduct) -> String? {
        switch product {
        case .proAnnual:
            guard let pair = livePrices(.proMonthly, .proAnnual),
                let percent = PlanPriceComparison.annualSavingsPercent(
                    monthlyPrice: pair.0.price, annualPrice: pair.1.price)
            else { return nil }
            return "Save \(percent)% vs Monthly"
        case .lifetimeCohort:
            guard let pair = livePrices(.proMonthly, .lifetimeCohort),
                PlanPriceComparison.lifetimeCostsLessThanAYearOfMonthly(
                    lifetimePrice: pair.1.price, monthlyPrice: pair.0.price)
            else { return nil }
            return "Less than a year of Monthly"
        case .proMonthly, .documentPackAddOn:
            return nil
        }
    }

    /// The caption lines under a card's price, live prices only, like `dealBadge(for:)`.
    fileprivate func comparisons(for product: BillingProduct) -> [String] {
        switch product {
        case .proAnnual:
            guard let annual = entitlementStore.product(for: .proAnnual),
                let perMonth = PlanPriceComparison.perMonthText(
                    annualPrice: annual.price, style: annual.priceFormatStyle)
            else { return [] }
            return ["\(perMonth) a month, billed yearly"]
        case .lifetimeCohort:
            guard let months = monthsOfAnnualForLifetime else { return [] }
            return ["Pays for itself against Pro Annual in \(months) months"]
        case .proMonthly, .documentPackAddOn:
            return []
        }
    }

    /// Lifetime's price in months of Pro Annual, from StoreKit's live prices for this storefront,
    /// or nil until both have loaded. Never from the hardcoded fallbacks: those are US numbers.
    fileprivate var monthsOfAnnualForLifetime: Int? {
        guard let pair = livePrices(.lifetimeCohort, .proAnnual) else { return nil }
        return LaunchSale.monthsOfAnnual(lifetimePrice: pair.0.price, annualPricePerYear: pair.1.price)
    }

    /// The discount to advertise for this product, or `nil` to say nothing.
    ///
    /// Delegates every judgement to `LaunchSale`, which refuses to return an offer unless
    /// StoreKit's live price is genuinely below the recorded regular price in the customer's
    /// own currency. When StoreKit metadata has not loaded there is no live price to compare,
    /// so no claim is made.
    fileprivate func saleOffer(for product: BillingProduct) -> LaunchSaleOffer? {
        guard let storeProduct = entitlementStore.product(for: product) else { return nil }
        return LaunchSale.offer(for: product, storeProduct: storeProduct, territory: storefront.code)
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
    /// A plain label beside the plan's name ("Month to month", "Pay once"), or nil. Never a
    /// saving: savings are computed per storefront and drawn under the price.
    let badgeText: String?
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
    /// The saving against another plan, live prices only; nil when there is none to state.
    let dealBadge: String?
    /// Caption lines under the price, live prices only.
    let comparisons: [String]
    let hasAccess: Bool
    let canPurchase: Bool
    let isProcessing: Bool
    let ctaAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            HStack {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(option.planName)
                        .font(.headline)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    Text(option.tagline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                }
                Spacer()
                // Until 5.5 only the featured card drew its label, so "Flexible" and "One-Time"
                // were written for Monthly and Lifetime and never shown.
                if let badgeText = option.badgeText {
                    Text(badgeText)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, DSSpacing.sm)
                        .padding(.vertical, DSSpacing.xs)
                        .background(option.tint.opacity(0.15))
                        .clipShape(Capsule())
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
            }

            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: DSSpacing.sm) {
                    Text(price + (priceSuffix ?? ""))
                        .font(.title.bold())
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)

                    if let saleOffer {
                        Text(saleOffer.regularDisplayPrice)
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .strikethrough(true, color: .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility1)

                        Text("\(saleOffer.percentOff)% off")
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, DSSpacing.sm)
                            .padding(.vertical, DSSpacing.xxs)
                            .background(Capsule().fill(Color.green))
                            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    }
                }

                PlanPriceCaptions(saleOffer: saleOffer, dealBadge: dealBadge, lines: comparisons)
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
                .padding(.top, -DSSpacing.sm)
            }

            VStack(alignment: .leading, spacing: DSSpacing.sm) {
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
        .padding(DSSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous)
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
        var parts: [String] = []
        if let saleOffer {
            parts.append(
                "\(price), reduced from \(saleOffer.regularDisplayPrice), "
                    + "\(saleOffer.percentOff) percent off until "
                    + "\(LaunchSale.deadlineText(for: saleOffer.endDate))"
            )
        } else {
            parts.append(price)
        }
        if let dealBadge { parts.append(dealBadge) }
        parts += comparisons
        if let badgeText = option.badgeText { parts.append(badgeText) }
        parts.append(option.tagline)
        return parts.joined(separator: ". ")
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

/// Everything under a card's price: the sale's last day, the saving against another plan as a
/// small capsule, and the arithmetic lines. All of it sits below the price and is smaller than
/// it, because Apple requires the billed amount to be the most prominent pricing element and a
/// per-month figure or a saving to be "displayed in a subordinate position and size" (see
/// `PlanPriceComparison`). A separate view because the card body is already at the edge of what
/// the type checker will accept in one expression.
private struct PlanPriceCaptions: View {
    let saleOffer: LaunchSaleOffer?
    let dealBadge: String?
    let lines: [String]

    var body: some View {
        if let saleOffer {
            Text("Launch price until \(LaunchSale.deadlineText(for: saleOffer.endDate))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        if let dealBadge {
            Text(dealBadge)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .padding(.horizontal, DSSpacing.sm)
                .padding(.vertical, DSSpacing.xxs)
                .background(Capsule().fill(Color.green.opacity(0.18)))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        ForEach(lines, id: \.self) { line in
            Text(line)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
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
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: DSSpacing.xl)
            Text(text)
                .font(.subheadline)
        }
    }
}

#Preview {
    PlanUpgradeSheet(entryPoint: .settings)
        .environmentObject(EntitlementStore(billingService: StoreKitBillingService()))
}
