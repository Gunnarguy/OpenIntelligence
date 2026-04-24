# Pricing and Packaging Strategy

**Updated**: April 24, 2026
**Status**: Repo-grounded working strategy. Do not use the older Starter/RevenueCat draft numbers.

This document separates the current App Store SKU set from enterprise/buyer packaging. The consumer app pricing is not the same thing as the sales story for EHR, medical-device, field-service, or enterprise document-intelligence buyers.

## Current App Store Product Shape

Current repo sources:

- `OpenIntelligence/Core/Models/WorkspaceTier.swift`: `free`, `pro`, `lifetime`
- `OpenIntelligence/Services/Billing/BillingProduct.swift`: `pro_monthly`, `pro_annual`, `lifetime_cohort`, `doc_pack_addon`
- `OpenIntelligence/Services/Infrastructure/Configuration/QuotaPolicy.swift`: limits and daily Maximum-mode quota
- `fastlane/subscriptions.json`: App Store Connect product setup reference

| Tier / SKU | Current Price | Current Allowance | Notes |
| --- | ---: | --- | --- |
| Free | $0 | 5 documents, 1 library, Standard/Deep Think, 3 Maximum-mode uses per day | Keep this as the frictionless reviewer/demo tier. |
| `pro_monthly` | $5.99/mo | 1,000 documents, 5 libraries, unlimited Maximum mode | Main consumer subscription. |
| `pro_annual` | $49.99/yr | 1,000 documents, 5 libraries, unlimited Maximum mode | Annual Pro. Fastlane marks Family Sharing enabled. |
| `lifetime_cohort` | $59.99 one-time | Unlimited documents in `QuotaPolicy`, 10 libraries, unlimited Maximum mode | The fastlane localization still says 1,000 docs in one English string. Fix before release if Lifetime is meant to be unlimited. |
| `doc_pack_addon` | $2.99 consumable | +10 documents | Code and fastlane still include the SKU. Current Terms copy says legacy document packs are no longer sold in-app. Decide before release. |

## Immediate Pricing Loose Ends

1. Pick one `doc_pack_addon` policy:
   - Keep selling it as a consumable and update Terms.
   - Hide it and keep it only as a grandfathering/receipt-migration SKU.
2. Align Lifetime copy:
   - `QuotaPolicy.lifetimeDocumentLimit` is unlimited.
   - `fastlane/subscriptions.json` has at least one Lifetime review/localization string saying "up to 1,000 documents."
3. Keep external-provider claims precise:
   - Do not promise third-party API egress is impossible if the app still has explicitly authorized provider paths.
   - For the core shipped positioning, say core document ingestion, indexing, retrieval, and Apple FoundationModels generation are local-first/Apple-native.
4. Do not market a Starter tier unless the product IDs, entitlement model, StoreKit config, UI, and Terms all implement it.

## Consumer Packaging

Use simple consumer copy:

- Free: try the full engine on a small library.
- Pro: serious personal or professional document libraries.
- Lifetime Cohort: early-supporter one-time unlock, availability controlled by release strategy.

Avoid "unlimited" language for Pro while the code caps Pro at 1,000 documents and 5 libraries.

## Enterprise and Acquisition Packaging

Do not lead enterprise conversations with App Store prices. Lead with a pilot or design-partner package:

| Package | Audience | Shape | Success Criteria |
| --- | --- | --- | --- |
| Evaluation Pilot | EHR, medical-device, field-service, compliance teams | 2-4 week device-local evaluation against their documents | Exact-value accuracy, citation faithfulness, abstention quality, offline behavior, ingestion success. |
| Design Partner | Strategic buyer that wants workflow integration | Custom dataset, feedback loop, SDK package, support channel | Clear integration path and repeatable eval metrics. |
| License / Acquisition | Buyer wants the engine or team/IP | SDK artifact, source diligence, architecture review, privacy/security review | Reproducible package, clean claims, current docs, eval evidence. |

## Healthcare and Medical Device Sales Notes

Safe language:

- "Designed for private technical documents on Apple devices."
- "Local full-text and vector indexes."
- "Cited answers with source inspection."
- "No third-party model dependency for core document QA."
- "Evaluation required on your source documents."

Unsafe language unless formally verified:

- "HIPAA compliant."
- "Clinical decision support."
- "Diagnostic assistant."
- "Guaranteed correct."
- "Certified medical workflow."
- "Uses Apple's PCC server model directly."

## Metrics to Track

For consumer:

- Free-to-Pro conversion after document quota hit.
- Maximum-mode daily quota hits.
- Ingestion failure rate by file type.
- Restore-purchase success rate.
- Refund rate by SKU.

For enterprise:

- Retrieval recall on known-answer questions.
- Numeric/specification exactness.
- Citation faithfulness.
- Abstention rate when evidence is missing.
- Time to ingest buyer sample corpus.
- Offline query latency on target devices.

## Next Review

Review after the next release candidate and before any serious buyer packet is sent. The key release decision is whether `doc_pack_addon` remains sold or becomes legacy-only.
