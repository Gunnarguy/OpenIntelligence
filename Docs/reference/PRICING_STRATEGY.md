# Pricing & Packaging Strategy (2025 Draft)

Last updated: 2025-11-11

## 1. Product Tiers

| Tier | Price (USD) | Core Allowances | Feature Highlights | Notes |
| --- | --- | --- | --- | --- |
| Free | $0 | 10 total documents, 1 active library, baseline retrieval | Standard hybrid search (no rerank tuning), queued ingestion, telemetry consent prompt | Surface remaining quota in Settings and in-library banners. Trigger paywall CTA at 8/10 documents. |
| Starter | $2.99/mo | 40 documents, 3 libraries, weekly rerank refresh | Faster ingestion queue, limited rerank sliders, manual export | Target self-serve researchers who occasionally spike usage. Offer $24.99/year anchor if platform enforces yearly listing. |
| Pro (Recommended) | $8.99/mo or $89/yr | Unlimited docs and libraries | Full hybrid retrieval (MMR tuning, BM25 weighting), automation hooks, team sharing, high-priority compute | Primary revenue driver; emphasize privacy, speed, collaboration. |
| Lifetime (Launch promo) | $59–$79 one-time | Unlimited docs **on-device only** | Local inference cartridge access, no cloud rerank, no team sharing | Offer in limited cohorts (cap redemption). Avoid exposing in paywall after initial promo. |
| Add-on Packs | $4.99 consumable | +25 documents or "Overage Credits" | Immediate quota boost, temporary compute priority | Starter users can burst without upgrading; do not stack beyond 3 packs. |

## 2. Rationale & Benchmarks

* **Cost containment:** GPU + storage average $0.60 per active heavy user monthly. A $2.99 entry tier preserves ~45% gross margin when usage is capped (10% refund buffer, 30% store fee). Unlimited usage remains gated to Pro.
* **Market positioning:** RevenueCat _State of Subscription Apps 2025_ indicates median annual pricing for Health/Fitness and Productivity peers in the $60–$120 band, with higher download→trial conversion (9.8%) at elevated price points. The $8.99/$89 anchor keeps us inside the upper quartile while Starter protects price-sensitive segments.
* **Hybrid monetization:** RevenueCat’s 2025 monetization trend analysis and "AI has broken subscription pricing" (Oct 2025) recommend pairing subscriptions with usage-based credits to offset variable inference cost.
* **Lifetime guardrails:** One-time payments should only unlock offline-first features (local vectors, Core ML cartridges). Limit availability to early backers to prevent long-term margin erosion.

## 3. Implementation Checklist

1. **Entitlement model**
   * Define SKU constants (`free`, `starter_monthly`, `pro_monthly`, `pro_annual`, `lifetime_cohort`, `doc_pack_addon`).
   * Extend `SettingsStore` to expose plan metadata + remaining document quota for UI.
   * Hook into ingestion pipeline to enforce hard stops at 10/40 docs.
2. **Paywall + messaging**
   * Build carousel explaining tier outcomes (speed, privacy, collaboration).
   * Add contextual paywall triggers: document quota nearing exhaustion, attempting pro-only rerank, creating >1 library.
   * Include "Refill documents" CTA that deep-links to consumable purchase.
3. **Billing plumbing**
   * Register StoreKit products + corresponding RevenueCat offerings (native IAP remains primary).
   * Stand up web2app checkout experiment (money-back guarantee for Pro annual).
4. **Telemetry & ops**
   * Instrument: `download_to_trial`, `trial_to_paid`, quota hit events, consumable redemption.
   * Set alerting on refund rate >5% or Starter overage >30% of revenue (indicates need for additional tiering).
5. **Support & policy**
   * Update ToS + privacy to cover consumables and quota messaging.
   * Ensure refunds auto-revoke add-on credits.

## 4. Success Metrics (Targets)

| Metric | Target | Notes |
| --- | --- | --- |
| Download → Trial | ≥10% (p50 baseline) | Expect higher conversion on hard paywall flows; monitor D0 intake. |
| Trial → Paid | ≥45% (p75) | Use 7-day trial on annual; gate monthly trials unless CAC demands. |
| Monthly Churn (Starter) | ≤9% | Keep usage caps tight to avoid compute spikes. |
| Monthly Churn (Pro) | ≤6% | Prioritize onboarding tours + automation templates. |
| Refund Rate (Pro) | <4% | Hard paywall requires clear value copy + reminder emails. |
| Consumable Attach Rate | 15% of Starter subs | Indicator of upsell momentum without forcing upgrade. |

## 5. Open Questions

1. Should Pro annual include additional storage (PDF archive) beyond unlimited docs?
2. Do we bundle third-party tool credits (e.g., future Foundation Model add-ons) within Pro?
3. Web checkout vs. in-app pricing parity—run tests before adjusting Apple-compliant pricing differentials.

## 6. Next Review

_Evaluate performance after 60 days post-launch._ Focus on:

* Quota-driven upgrade funnels (hits vs. conversions)
* Compute cost variance per tier
* Feedback from early lifetime buyers (determine if the SKU sunsets or becomes invite-only).
