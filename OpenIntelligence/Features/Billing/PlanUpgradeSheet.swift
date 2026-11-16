import StoreKit
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

/// What the person has used of their plan, counted by the presenter (5.8, 2026-11-15). Settings passes it, so the
/// plans screen opens with the figures the Plan & Usage page showed before that page was folded into it. The sheet
/// can't count them itself: it is presented from places whose environment holds no `RAGService`.
struct PlanUsage {
    let documents: Int
    let libraries: Int
    /// Conversations in the open library, where the conversation limit is checked.
    let chatsInOpenLibrary: Int
}

/// The plans screen: the person's plan and usage, the three plans with their live prices, the side-by-side table,
/// and the store's links (5.8, 2026-11-15). The owner found it "too many taps deep" and not clean; it lost its hero,
/// its banners, a "What you get" list the table repeated, a three-slide carousel and a tip, and follows the type and
/// card rule on `DSTypography`.
struct PlanUpgradeSheet: View {
    let entryPoint: PlanUpgradeEntryPoint
    /// Nil from presenters that can't count usage; the panel then states the plan's limits.
    var usage: PlanUsage? = nil

    @EnvironmentObject private var entitlementStore: EntitlementStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var purchasingProduct: BillingProduct?
    @State private var alertMessage: String?
    @State private var isRefreshingProducts: Bool = false
    @State private var isRestoring = false
    @State private var showingRedeemCode = false
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
            features: PlanBenefits.pro
        ),
        PlanTierOption(
            tier: .pro,
            planName: "Pro (Annual)",
            product: .proAnnual,
            tagline: "Maximum mode every day, one payment a year",
            badgeText: nil,
            tint: .accentColor,
            isFeatured: true,
            features: PlanBenefits.pro
        ),
        PlanTierOption(
            tier: .lifetime,
            planName: "Lifetime",
            product: .lifetimeCohort,
            tagline: "Everything, once, for good",
            badgeText: "Pay once",
            tint: .orange,
            isFeatured: false,
            features: PlanBenefits.lifetime
        ),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.lg) {
                    usageSection

                    ForEach(planOptions) { option in
                        tierCard(for: option)
                    }

                    planComparisonSection
                    storeLinks
                }
                .padding(DSSpacing.lg)
                // The Settings pages' column, centred, on a Mac and an iPad.
                .frame(maxWidth: SettingsView.detailColumnWidth)
                .frame(maxWidth: .infinity)
            }
            .background(DSColors.background.ignoresSafeArea())
            .navigationTitle("Plans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        #if os(macOS)
            // A Mac sheet with no size takes its content's narrowest width (see `ContainerSettingsSheet`).
            .frame(minWidth: 560, idealWidth: 640, maxWidth: 760, minHeight: 560, idealHeight: 720)
        #endif
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
        .task { await AppStoreRatingService.refreshIfStale() }
        .onAppear {
            TelemetryCenter.emitBillingEvent(
                "Paywall viewed",
                metadata: [
                    "entryPoint": entryPoint.analyticsValue,
                    "currentTier": entitlementStore.effectiveTier.rawValue,
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
    /// Why the screen opened, when something asked for it (a limit, Maximum running out, a watched folder), then the
    /// plan the person has and what they have used of it, in the dark panel the Settings pages open with. Opened from
    /// Settings it is the panel alone: the reason there was "Manage your workspace plan".
    fileprivate var usageSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            if entryPoint != .settings {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(entryPoint.headline)
                        .font(DSTypography.title)
                    Text(entryPoint.subheadline)
                        .font(DSTypography.body)
                        .foregroundStyle(DSColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // The tier the person has, with a purchase from before 5.5 counted (5.8): `activeTier` is only what the
            // store sells now, and the sheet said "Free" to the owner, whose Plan & Usage said Lifetime (2026-11-04).
            SettingsStatusPanel(
                symbol: "creditcard",
                title: "Your plan",
                badge: entitlementStore.effectiveTier.displayName,
                badgeColor: entitlementStore.effectiveTier == .free ? Color.white.opacity(0.7) : .orange,
                blocks: usageBlocks)
            if entitlementStore.activeTier == .free, entitlementStore.isLegacyPaidProtected {
                Text("Previous paid purchases on this Apple ID now unlock Lifetime access on this device.")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.secondaryText)
            }
            launchSaleLine
        }
    }

    /// The figures are the entitlement store's limits and the presenter's counts, the ones the limits are checked
    /// against. Without counts each block states its limit.
    private var usageBlocks: [SettingsStatusPanel.Block] {
        let documentLimit = entitlementStore.documentLimit
        let libraryLimit = entitlementStore.libraryLimit
        let chatLimit = QuotaPolicy.evidenceThreadLimit(for: entitlementStore.effectiveTier)
        let dailyLimit = QuotaPolicy.freeMaximumModeDailyLimit
        let maximumLeft = entitlementStore.maximumModeRemainingUses
        let maximum: SettingsStatusPanel.Block =
            entitlementStore.hasUnlimitedMaximumMode
            ? .init(
                symbol: "bolt.fill", name: "Maximum", color: .orange, figure: "No cap", share: nil,
                caption: "every day")
            : .init(
                symbol: "bolt.fill", name: "Maximum", color: .orange, figure: "\(maximumLeft) of \(dailyLimit)",
                share: Double(maximumLeft) / Double(max(1, dailyLimit)), caption: "left today")
        guard let usage else {
            return [
                .init(
                    symbol: "doc.text", name: "Documents", color: .blue, figure: Self.limitText(documentLimit),
                    share: nil, caption: "allowed"),
                .init(
                    symbol: "books.vertical", name: "Libraries", color: .purple, figure: Self.limitText(libraryLimit),
                    share: nil, caption: "allowed"),
                .init(
                    symbol: "bubble.left.and.bubble.right", name: "Chats", color: .green,
                    figure: Self.limitText(chatLimit), share: nil, caption: "per library"),
                maximum,
            ]
        }
        let documents = SettingsStatusPanel.used(usage.documents, of: documentLimit)
        let libraries = SettingsStatusPanel.used(usage.libraries, of: libraryLimit)
        let chats = SettingsStatusPanel.used(usage.chatsInOpenLibrary, of: chatLimit)
        return [
            .init(
                symbol: "doc.text", name: "Documents", color: .blue, figure: documents.figure,
                share: documents.share, caption: documents.caption),
            .init(
                symbol: "books.vertical", name: "Libraries", color: .purple, figure: libraries.figure,
                share: libraries.share, caption: libraries.caption),
            .init(
                symbol: "bubble.left.and.bubble.right", name: "Chats here", color: .green, figure: chats.figure,
                share: chats.share, caption: chats.caption),
            maximum,
        ]
    }

    private static func limitText(_ limit: Int) -> String {
        limit == .max ? "Unlimited" : limit.formatted()
    }

    /// The launch sale in one caption line, shown only when Lifetime has a confirmed discount; the Lifetime card
    /// carries the struck-through price and the percentage.
    ///
    /// Names the plan and its own real percentage rather than a headline figure, so the line
    /// cannot promise more than the card below it delivers. Only Lifetime is ever discounted;
    /// `LaunchSale` explains why the subscriptions are left alone.
    @ViewBuilder
    fileprivate var launchSaleLine: some View {
        if let offer = saleOffer(for: .lifetimeCohort) {
            Label {
                Text(
                    "Launch sale: Lifetime is \(offer.percentOff)% off until \(LaunchSale.deadlineText(for: offer.endDate)). One payment, no renewal."
                )
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "tag.fill")
                    .foregroundStyle(.green)
            }
            .font(DSTypography.caption)
            .foregroundStyle(DSColors.primaryText)
            .accessibilityElement(children: .combine)
        }
    }

    fileprivate func tierCard(for option: PlanTierOption) -> some View {
        PlanTierCard(
            option: option,
            price: priceLabel(for: option.product),
            priceSuffix: priceSuffix(for: option.product),
            saleOffer: saleOffer(for: option.product),
            dealBadge: dealBadge(for: option.product),
            comparisons: comparisons(for: option.product),
            hasAccess: entitlementStore.effectiveTier.isAtLeast(option.tier),
            // "canPurchase" here means StoreKit metadata has been loaded.
            // We still allow tapping the CTA while loading; the tap will refresh and retry.
            canPurchase: canPurchase(option.product),
            isProcessing: purchasingProduct == option.product || isRefreshingProducts,
            ctaAction: { purchase(option.product) }
        )
    }

    /// What each plan has of everything a paid plan changes, under the three cards. A label on its own line and
    /// three equal columns below it, so it still reads at the largest text sizes.
    fileprivate var planComparisonSection: some View {
        SurfaceCard {
            SectionHeader(icon: "tablecells", title: "Free, Pro and Lifetime")
            ForEach(PlanBenefits.comparison) { row in
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Label(row.name, systemImage: row.icon)
                        .font(DSTypography.body.weight(.medium))
                    HStack(alignment: .top, spacing: DSSpacing.sm) {
                        comparisonCell("Free", row.free, isCurrent: entitlementStore.effectiveTier == .free)
                        comparisonCell("Pro", row.pro, isCurrent: entitlementStore.effectiveTier == .pro)
                        comparisonCell(
                            "Lifetime", row.lifetime, isCurrent: entitlementStore.effectiveTier == .lifetime)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(row.name). Free: \(row.free). Pro: \(row.pro). Lifetime: \(row.lifetime).")
                if row.id != PlanBenefits.comparison.last?.id {
                    Divider()
                }
            }
            Text("Apple Intelligence on your device, Deep Think and Private Cloud Compute are in every plan.")
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func comparisonCell(_ plan: String, _ value: String, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(isCurrent ? "\(plan) (yours)" : plan)
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.secondaryText)
            Text(value)
                .font(DSTypography.body)
                .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Restore, manage, redeem, the renewal terms and the two legal links, as quiet links at the end. App Review needs
    /// each of them on the purchase screen, so none is gone, only smaller. The privacy label and the store rating, a
    /// banner near the top until 2026-11-15, are a caption here.
    fileprivate var storeLinks: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) { storeButtons }
                .font(DSTypography.body.weight(.medium))
                .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Label("App Store privacy label: Data Not Collected", systemImage: "hand.raised.fill")
                if let rating = AppStoreRatingService.cached(), rating.isWorthShowing {
                    Label {
                        Text(rating.line)
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: "star.fill")
                    }
                }
            }
            .font(DSTypography.caption)
            .foregroundStyle(DSColors.secondaryText)

            Text(
                "Subscriptions automatically renew at the price and duration selected above unless cancelled at least 24 hours before the end of the current period. Payments are charged to your App Store account. You can manage your subscriptions and turn off auto-renewal in your App Store Account Settings after purchase."
            )
            .font(DSTypography.meta)
            .foregroundStyle(DSColors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DSSpacing.lg) {
                Link(
                    "Terms of Use (EULA)",
                    destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
                )
                Link("Privacy Policy", destination: URL(string: "https://gunndamental.com/openintelligence/privacy/")!)
            }
            .font(DSTypography.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DSSpacing.xs)
    }

    @ViewBuilder
    private var storeButtons: some View {
        Button(action: restorePurchases) {
            if isRestoring {
                ProgressView()
            } else {
                Text("Restore Purchases")
            }
        }
        .disabled(isRestoring)

        Button("Manage Subscription", action: manageSubscriptions)

        // Apple's own sheet for an offer code made in App Store Connect. Apple's rule is that a
        // code is redeemed through that sheet and not through a field of the app's own.
        Button("Redeem a Code") {
            Tour.used(.redeemCode)
            showingRedeemCode = true
        }
        .tour(.redeemCode, in: Tour.plans)
        .redeemCodeSheet(isPresented: $showingRedeemCode) { outcome in
            // The case only (5.8 journal), never the failure's text.
            switch outcome {
            case .redeemed: VerificationJournal.record("plans.redeemCode", .ok, ["result": "redeemed"])
            case .closed: VerificationJournal.record("plans.redeemCode", .info, ["result": "closed"])
            case .cancelled: VerificationJournal.record("plans.redeemCode", .cancelled, ["result": "cancelled"])
            case .failed: VerificationJournal.record("plans.redeemCode", .failed, ["result": "failed"])
            }
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
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(option.planName)
                        .font(DSTypography.title)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    Text(option.tagline)
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.secondaryText)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                }
                Spacer()
                // Until 5.5 only the featured card drew its label, so "Flexible" and "One-Time"
                // were written for Monthly and Lifetime and never shown.
                if let badgeText = option.badgeText {
                    Text(badgeText)
                        .lineLimit(1)
                        .fixedSize()
                        .chipStyle(tint: DSColors.readable(option.tint))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
            }

            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                // The billed amount is the largest pricing text on the card (`PlanPriceComparison`), at the
                // type scale's figure size; everything computed from it sits below, smaller.
                HStack(alignment: .firstTextBaseline, spacing: DSSpacing.sm) {
                    Text(price + (priceSuffix ?? ""))
                        .font(DSTypography.figure)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)

                    if let saleOffer {
                        Text(saleOffer.regularDisplayPrice)
                            .font(DSTypography.body)
                            .monospacedDigit()
                            .foregroundStyle(DSColors.secondaryText)
                            .strikethrough(true, color: DSColors.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility1)

                        Text("\(saleOffer.percentOff)% off")
                            .monospacedDigit()
                            .chipStyle(tint: DSColors.readable(.green))
                            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    }
                }

                PlanPriceCaptions(saleOffer: saleOffer, dealBadge: dealBadge, lines: comparisons)

                if option.product.kind == .subscription {
                    Text(
                        option.product == .proMonthly
                            ? "1-Month Auto-Renewing Subscription" : "1-Year Auto-Renewing Subscription"
                    )
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.secondaryText)
                }
            }
            // Deliberately no accessibility modifiers here. The whole card is a single element
            // (see the bottom of this view), and a label applied inside it would be discarded.
            // The sale is spoken through `accessibilityValueText` instead.

            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                ForEach(option.features, id: \.self) { feature in
                    Label {
                        Text(feature)
                    } icon: {
                        Image(systemName: "checkmark")
                            .foregroundStyle(option.tint)
                    }
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.primaryText)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
            }

            ctaButton(hasAccess: hasAccess, canPurchase: canPurchase, isProcessing: isProcessing)
                // Important: don't disable the CTA when StoreKit metadata hasn't loaded yet.
                // In release builds, tapping triggers a refresh + retry; in DEBUG we may simulate.
                .disabled(hasAccess || isProcessing)
        }
        .padding(DSSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A `SurfaceCard`'s surface, drawn here so the featured plan can carry a thin outline in its tint instead of
        // the glow it had.
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.surface)
                .shadow(color: .black.opacity(0.04), radius: DSSpacing.sm, x: 0, y: DSSpacing.xs)
        )
        .overlay {
            if option.isFeatured {
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .strokeBorder(option.tint.opacity(0.6), lineWidth: 1)
            }
        }
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
                .monospacedDigit()
                .lineLimit(1)
                .chipStyle(tint: DSColors.readable(.green))
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

#Preview {
    PlanUpgradeSheet(entryPoint: .settings)
        .environmentObject(EntitlementStore(billingService: StoreKitBillingService()))
}
