# Visibility Policy

This is the policy for deciding what stays private, what can be mirrored to the
public repo, and what should only be described publicly without shipping the
underlying code.

If you forget everything else:

- private repo = source of truth
- App Store builds come from the private repo
- public repo = curated signal, not full implementation
- default to private unless there is a clear reason to publish

## Why This Exists

OpenIntelligence is doing two jobs at once:

- consumer app revenue via App Store / IAP
- commercial value via private engine / SDK / partner sales

Those goals are compatible only if the repo policy is explicit.

## The Three Lanes

### 1. Always Private

These are part of the moat, diligence surface, or partner/commercial track.
They should not be promoted to the public repo.

- engine orchestration
- retrieval, RAG, verification, trust, routing, and extraction logic
- ingestion and document-processing internals
- SDK/framework packaging work
- private evaluation and partner materials
- pricing, packaging, audits, regression plans
- internal agent instructions
- scripts used for SDK/productization or private evaluation

Examples:

- `OpenIntelligence/Services/Document/`
- `OpenIntelligence/Services/RAG/`
- `OpenIntelligence/Services/Query/`
- `OpenIntelligence/Services/Embedding/`
- `OpenIntelligence/Services/Storage/`
- `OpenIntelligence/SDK/`
- `OpenIntelligence/Core/Support/`
- `INTERNAL_LOGIC_AUDIT.md`
- `SDK_BOUNDARY_AUDIT.md`
- `REGRESSION_PLAN.md`
- `ENGINE_CAPABILITIES.md`
- `output/OpenIntelligence-Partner-Packet/`
- `output/OpenIntelligence-SDK-Package/`

### 2. Public-Safe

These are safe to mirror when they improve the public repo as a portfolio,
product signal, or public changelog.

- README improvements
- release notes
- public-facing metadata
- safe UI polish that does not expose moat logic
- marketing copy
- non-sensitive app-shell improvements
- general housekeeping that reveals no partner or engine strategy

Examples:

- `README.md`
- `WHATS_NEW.md`
- `fastlane/metadata/`
- selected `Features/` UI files
- `.gitignore`

### 3. Summary-Only

Some work should be mentioned publicly without publishing the implementation.
Use public release notes, README updates, or changelog summaries instead of code.

Examples:

- “improved document ingestion reliability”
- “better handling for difficult manuals and scanned PDFs”
- “improved grounded-answer quality and trust behavior”
- “performance and reliability improvements”

This is the correct lane for many engine changes that help App Store users but
should remain commercially private.

## Decision Rule

Ask:

1. Does this change improve or expose the moat?
2. Would publishing this help a competitor more than it helps my public signal?
3. If a buyer asked what is proprietary here, would this commit be part of that answer?

If any answer is `yes`, keep it private.

## App Store Rule

Do not confuse public GitHub with public product distribution.

- users get the latest app through the App Store
- the private repo can still be the shipping repo
- the public repo does not need to contain the latest engine implementation

## Commit Hygiene Rule

Do not mix public-safe and private-only work in the same commit if you can avoid it.

Preferred pattern:

1. commit core private engine work separately
2. commit public-facing copy/UI updates separately
3. promote only the safe commits

If a commit mixes both, leave it private and write a public summary instead.

## What I Would Do If This Were Mine

- keep the public repo alive
- keep the public repo useful
- stop treating the public repo as the real dev repo
- ship from private
- mirror intentionally
- let the public repo lag on purpose

That preserves:

- App Store momentum
- portfolio signal
- stars / discoverability
- commercial leverage

without giving away the engine.
