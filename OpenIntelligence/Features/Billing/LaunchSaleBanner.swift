//
//  LaunchSaleBanner.swift
//  OpenIntelligence
//
//  One line at the top of the Chat and Documents tabs while a Lifetime discount is genuinely
//  running, for people who have not bought. It says the real percentage and the real last day,
//  both computed by `LaunchSale` from StoreKit's live price against the recorded regular price,
//  so it cannot announce a discount that is not on. Dismissing it hides it until the next sale
//  window, keyed on the window's end date. Tapping it opens the plans.
//

import StoreKit
import SwiftUI

struct LaunchSaleBanner: View {
    @EnvironmentObject private var entitlementStore: EntitlementStore
    @AppStorage("launchSaleBanner.dismissedWindowEnd") private var dismissedWindowEnd: Double = 0
    @State private var showPlans = false

    var body: some View {
        if let offer = currentOffer, dismissedWindowEnd != offer.endDate.timeIntervalSince1970 {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("Lifetime is \(offer.percentOff)% off until \(LaunchSale.deadlineText(for: offer.endDate)). One payment, no renewal.")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DSSpacing.xs)
                Button {
                    withAnimation { dismissedWindowEnd = offer.endDate.timeIntervalSince1970 }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DSColors.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            .background(Color.orange.opacity(0.12))
            .contentShape(Rectangle())
            .onTapGesture { showPlans = true }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .sheet(isPresented: $showPlans) {
                PlanUpgradeSheet(entryPoint: .launchSale)
            }
        }
    }

    /// Nil for anyone who has paid, and nil whenever `LaunchSale` cannot prove a discount.
    private var currentOffer: LaunchSaleOffer? {
        guard !entitlementStore.effectiveTier.isAtLeast(.pro) else { return nil }
        guard let product = entitlementStore.product(for: .lifetimeCohort) else { return nil }
        return LaunchSale.offer(for: .lifetimeCohort, storeProduct: product)
    }
}
