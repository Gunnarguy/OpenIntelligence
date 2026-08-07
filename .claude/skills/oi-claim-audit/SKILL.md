---
name: oi-claim-audit
description: Use before removing, weakening, or "correcting" ANY factual claim in this repo - Settings copy, CHANGELOG entries, doc statements, code comments, or Notion roadmap rows. Triggers on claims audits, unverified-claim sweeps, doc/Notion drift passes, "this claim isn't supported", or any task that would delete a specific technical name, figure, or capability from user-facing text. Also use when a roadmap row appears to contradict the code.
---

# Claim audit discipline

This repo's differentiator is that its claims are true. That makes claim audits high value
and high risk: a bad audit corrupts accurate information and looks like diligence while
doing it.

## The core rule

**"I could not find evidence" is not "the claim is false."**

A claim-removal pass has the same failure mode as the claim-writing pass it is correcting.
Deleting an unverified claim feels safe. It is not. Both directions need evidence.

This has now caused three separate regressions in this repo. Do not make it four.

## Confirmed instances

**TinyBERT (twice).** Two consecutive sessions checked
`ReRankerModel.mlpackage/Manifest.json`, found no model family, and removed "TinyBERT" from
Settings. A Core ML `.mlpackage` manifest is a packaging descriptor listing item authors and
filenames. It never carries source architecture. Finding nothing there was the expected
result and proved nothing. Neither pass grepped the repo for the model name.
`THIRD_PARTY_NOTICES.md:10-15` binds `cross-encoder/ms-marco-TinyBERT-L2-v2` to that exact
artifact path.

**The Evaluations roadmap row.** A session rewrote the Notion row "Migrate to Native
Evaluations Framework" because the body said Swift Testing ("repo uses XCTest") and named a
Model-as-Judge pattern ("grep returns zero"). Apple's Evaluations framework, new in Xcode 27,
integrates with Swift Testing via the `.evaluates` trait and ships `ModelJudgeEvaluator`. The
row was a **migration** row. It described the target. Grepping the current repo and finding
zero was the expected result and *confirmed* the row rather than refuting it.

## Required checks before touching any claim

Run all that apply. Stop at the first one that resolves the question.

1. **`THIRD_PARTY_NOTICES.md`.** License attribution binds model names to exact artifact
   paths. Legally required attribution is the strongest provenance in this repository.
   Check it before touching any model name.

2. **Primary vendor documentation.** For anything about Apple frameworks, fetch
   `developer.apple.com` directly. **The assistant's knowledge cutoff predates WWDC 2026**,
   so any claim about what Apple does or does not ship must be verified against the live
   docs, never asserted from model knowledge. Cite the URL in the evidence tag.

3. **Roadmap-row semantics.** A `To Do` or migration row describes a **target state**. The
   correct test is whether the target is real and still wanted, not whether the repo already
   implements it. Absence in the code is what an open row *means*.

4. **Packaging metadata proves nothing about architecture.** `.mlpackage` manifests,
   `.aimodel` `metadata.json`, and similar descriptors carry producer and filenames, not
   model provenance.

5. **Grep the whole repo for the specific term**, including docs, notices, and comments, not
   just the file that prompted the question.

## When you cannot verify

Do not delete. Mark it:

`[evidence_level: unverified, confidence: low, evidence_source: <what you checked and why it was inconclusive>]`

Deleting destroys information. Downgrading the evidence level preserves it and tells the
next pass exactly where to resume. A withdrawal of a *measured-sounding* number is different
from a withdrawal of a *technical name*: unmeasured multipliers should go, verifiable names
should be checked first.

## Evidence tags

Every claim in this repo's docs carries
`[evidence_level: ..., confidence: ..., evidence_source: ...]`. Never upgrade an evidence
level without actually performing the verification the new level implies. `code_verified`
means you read the line. `test_verified` means you ran it. `build_verified` means it
compiled. `measured` means a benchmark produced the number, and until the harness lands,
almost nothing in retrieval qualifies.

## Before you finish

State plainly which checks you ran and which you skipped. An audit that reports "swept all N
rows" without saying how each was verified is the single most expensive artifact to inherit,
because the next session sequences work off it.
