# Release and Operations Guide

**Last Updated**: April 25, 2026
**Status**: App release operations guide.

## Current Status

This document is about releasing the app.

It is not evidence that the repo is a finished enterprise SDK or that the engine is ready for regulated deployment.

Use this guide for:

- app-release operations
- StoreKit and App Store submission workflow
- app claim checks before submission

Do not use it as proof of:

- SDK maturity
- buyer readiness on its own
- healthcare, legal, safety, or IFU readiness

Primary companion docs:

- [Current State and Gaps](./CURRENT_STATE_AND_GAPS.md)
- [Hard Limits](./HARD_LIMITS.md)
- [Pricing and Packaging Strategy](./PRICING_STRATEGY.md)
- [Buyer Readiness and Evaluation](./BUYER_READINESS_AND_EVALUATION.md)

## 1. Pre-Release Checklist

### Code quality

- [ ] Build succeeds from Xcode and `xcodebuild`
- [ ] No new compiler warnings introduced by release changes
- [ ] Secret scan passes
- [ ] No release-blocking TODO or FIXME items remain in shipping code

### Claim and copy checks

- [ ] App metadata does not claim direct PCC server-model access
- [ ] App metadata does not claim a 65K public Foundation Models context
- [ ] App metadata does not claim Apple Foundation Models embeddings
- [ ] Buyer-facing or review-facing copy does not imply HIPAA, diagnostic, clinical, legal, safety, or IFU readiness
- [ ] Release notes do not describe the current repo as a finished enterprise SDK

### StoreKit and pricing checks

- [ ] Product catalog loads correctly
- [ ] Purchase flow completes
- [ ] Restore purchases works
- [ ] Quota enforcement matches current product policy
- [ ] `doc_pack_addon` policy is consistent across code, Terms, and App Store metadata

### Runtime checks

- [ ] Ingestion works on a representative sample document set
- [ ] Exact-value query works on a representative technical doc
- [ ] Missing-evidence behavior is still sane
- [ ] Container isolation still works
- [ ] Physical-device Apple Intelligence validation was performed for Apple FM behavior

## 2. Smoke Test Protocol

**Device**: Use a real Apple Intelligence-capable device for generation validation. Simulator is acceptable only for UI, storage, and fallback-path smoke tests.

### Basic smoke flow

1. Launch the app.
2. Import a small sample document.
3. Verify ingestion completes.
4. Ask one exact-value question.
5. Ask one missing-evidence question.
6. Inspect citations or source cards.
7. Switch containers and confirm isolation.

### Minimum accuracy sanity checks

- [ ] Exact numeric/specification query returns the source value and a usable source reference
- [ ] Missing-evidence query abstains or states the gap clearly
- [ ] Broad summary query does not obviously fabricate unsupported claims
- [ ] Multi-container query does not leak unrelated content

## 3. Versioning

Update both debug and release project settings:

- `MARKETING_VERSION`
- `CURRENT_PROJECT_VERSION`

Update `CHANGELOG.md` with the shipped version and the user-visible changes.

## 4. StoreKit Testing

Use two modes intentionally:

- Local StoreKit simulation for normal development
- Apple sandbox validation before App Store submission

Important current repo note:

- consumer billing is app-only
- StoreKit behavior is not evidence of engine maturity

## 5. Build and Archive Commands

App build:

```bash
xcodebuild -scheme OpenIntelligence -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Current repo note:

- the project also contains a shared `OpenIntelligenceEngine` evaluation scheme, but this guide is about the app release path rather than the framework handoff
- the staged engine evaluation materials live under `output/OpenIntelligence-SDK-Package/`
- do not treat this release guide as proof of a currently shared, reproducible engine-framework build path

Release helper scripts:

```bash
./scripts/preflight_check.sh
./scripts/package_submission.sh
```

## 6. Submission Notes

Before submission, verify:

- App Store metadata matches actual behavior
- privacy language matches actual data handling
- monetization copy matches current product behavior
- no buyer or marketing materials accidentally present the app as a finished enterprise SDK

## 7. What This Document Does Not Prove

This document does not prove:

- the benchmark harness is mature enough for production accuracy claims
- the SDK packaging story is complete
- the engine is ready for regulated decision-making

Those questions belong in the diligence docs, not the app-release guide.
