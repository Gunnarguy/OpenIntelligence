# Pricing and Packaging Strategy

**Updated**: April 25, 2026
**Status**: Working repo-grounded note. This is not a final enterprise pricing sheet.

## Current Status

This repo contains two different commercial stories:

- a live consumer app with StoreKit and quota logic
- a substantial engine/codebase asset that could support evaluation, licensing, or handoff discussions

Those are not the same thing.

Use app pricing as evidence that the product has been monetized and shipped in some form. Do not use app pricing as the main way to describe the engine's value.

## Current App Store Product Shape

Current code sources:

- `OpenIntelligence/Core/Models/WorkspaceTier.swift`
- `OpenIntelligence/Services/Billing/BillingProduct.swift`
- `OpenIntelligence/Services/Infrastructure/Configuration/QuotaPolicy.swift`
- `fastlane/subscriptions.json`

| Tier or SKU       | Current code reality                                                         | Notes                                               |
| ----------------- | ---------------------------------------------------------------------------- | --------------------------------------------------- |
| Free              | 5 documents, 1 library, Standard and Deep Think, 3 Maximum-mode uses per day | App-only limit                                      |
| `pro_monthly`     | Pro subscription                                                             | 1,000 documents, 5 libraries                        |
| `pro_annual`      | Pro subscription                                                             | same practical quota as monthly                     |
| `lifetime_cohort` | one-time purchase                                                            | unlimited documents in code, 10 libraries           |
| `doc_pack_addon`  | consumable add-on in code                                                    | still exists in billing code and fastlane artifacts |

## App-Only Pricing Caveats

Current mismatch to keep out of buyer overclaim language:

- `BillingProduct.swift` still includes `doc_pack_addon`
- `QuotaPolicy.swift` still supports add-on increments
- `TermsOfServiceView.swift` says legacy document packs are no longer sold in-app

That means app monetization is still in flux. Treat it as app-only business policy, not engine value.

## What Matters For Engine Conversations

For engine, licensing, or acquisition discussions, the buyer is not primarily paying for:

- consumer paywalls
- App Store pricing tiers
- in-app quota upsells

They are paying for some combination of:

- source code and app project
- working ingestion and retrieval engine
- benchmark harness and evaluation tooling
- prototype SDK facade
- founder knowledge transfer

## Best Current Commercial Framing

Use one of these frames instead of consumer subscription language:

### Technical evaluation

- buyer wants to inspect capability on a narrow corpus
- benchmark harness and code walkthrough matter more than packaging polish

### Design-partner pilot

- buyer wants a guided evaluation and early integration planning
- staged evaluation packet may help, but the real value is the codebase and founder guidance

### License, handoff, or acquisition discussion

- buyer wants the engine head start, not just app subscriptions
- requires clear scope around source, docs, limitations, and claims

## Healthcare, Safety, and Regulated Claims

Do not use pricing or sales language to imply:

- HIPAA compliance
- clinical decision support
- diagnostic assistance
- legal or safety readiness
- IFU reliability

If a regulated-adjacent buyer is interested, the correct commercial frame is:

- prototype evaluation on their own documents
- source inspection
- measured success criteria
- explicit limitations

## Practical Conclusion

Consumer app pricing is useful context.

It is not the engine sale story.

The current engine story is evaluation, pilot, licensing, or codebase transfer, with consumer monetization treated as separate app context.
