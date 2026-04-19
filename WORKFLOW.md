# Workflow

This repo is the private-primary working copy for OpenIntelligence.

If you forget everything else, remember this:

- build here
- iterate here
- ship App Store work from here if needed
- do SDK/commercial work here
- only copy intentionally public-safe work into the public repo

Read [VISIBILITY_POLICY.md](/Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/VISIBILITY_POLICY.md:1)
if you need the exact `always private` vs `public-safe` rules.

## The Two Repos

### 1. Private-primary repo

Path:

- `/Users/gunnarhostetler/Documents/GitHub/OpenIntelligence`

Remote:

- `engine`

Purpose:

- main source of truth
- app development
- App Store Connect release work
- SDK/framework packaging
- internal audits
- regression planning
- partner/sales materials

### 2. Public-safe repo

Path:

- `/Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public`

Remote:

- `origin`

Branch:

- `public-safe`

Purpose:

- public GitHub history
- safe README/release/app updates you intentionally want visible
- nothing private, nothing commercial, nothing SDK-diligence-specific

## The Correct Direction

The flow is:

`private repo -> public repo`

Not:

`public repo -> private repo`

Why:

- the private repo is the superset
- the public repo is the filtered mirror
- this prevents the public repo from becoming the accidental source of truth

## App Store Rule

App Store Connect does not require the public repo to be the primary repo.

Use the private repo for:

- app code changes
- release prep
- metadata iteration
- shipping builds

The public repo is optional and selective.

## Simple Daily Rule

When working, ask one question:

"Is this something I would be comfortable publishing on public GitHub?"

If the answer is:

- `no` -> do it only in the private repo
- `maybe` -> keep it private until you intentionally review it
- `yes` -> it can be promoted to the public repo later

## What Must Stay Private

Do not publish these from the private repo into the public repo:

- `INTERNAL_LOGIC_AUDIT.md`
- `SDK_BOUNDARY_AUDIT.md`
- `REGRESSION_PLAN.md`
- `ENGINE_CAPABILITIES.md`
- `output/OpenIntelligence-Partner-Packet/*`
- `output/OpenIntelligence-SDK-Package/*`
- `.github/copilot-instructions.md`
- `.github/instructions/swift.instructions.md`
- SDK packaging/build scripts
- internal framework/productization details
- pricing or partner strategy

## What Can Be Public-Safe

Usually safe candidates:

- `README.md`
- `WHATS_NEW.md`
- public-facing release notes
- safe app UI/content improvements
- safe app bug fixes you are comfortable showing

Still review them before promotion.

## Summary-Only Rule

Some changes should be described publicly without promoting the code.

Use this for:

- engine reliability improvements
- ingestion fixes
- retrieval/groundedness improvements
- trust and verification improvements
- SDK/productization progress

For those, update public copy or release notes, but keep the implementation in
the private repo.

## Promotion Process

When you want something public:

1. Make the change in the private repo first.
2. Commit it in the private repo.
3. Push it to `engine`.
4. Promote only the safe commit(s) into the public repo.
   - Preferred path:
   - `./scripts/promote_public_safe.sh <commit> [<commit> ...]`
   - Add `--push` when you want the public branch updated on GitHub immediately.
5. Push `public-safe` when you are ready.
6. Merge to public `main` only intentionally.

## Public Freshness

If you want the public repo to stay active without exposing the engine, use the
automated summary path:

- `./scripts/update_public_release_summary.sh --write`
- or the one-command wrapper:
- `./scripts/refresh_public_signal.sh`

That keeps both:

- `WHATS_NEW.md`
- `fastlane/metadata/en-US/release_notes.txt`

current from private activity using public-safe, feature-facing language instead
of mirroring engine code.

The Fastlane release lanes also call the generator automatically, so App Store
release notes stay in sync even when the underlying implementation work remains
private.

`release` and `beta` also advance the local summary baseline only after a
successful upload, so the next version summary reflects what actually shipped.

## Current Local Setup

Private repo:

- `main` tracks `engine/main`
- default push remote for `main` is `engine`

Public repo:

- `public-safe` is the public review branch
- once published, it tracks `origin/public-safe`
- merge from `public-safe` to public `main` only on purpose

## If You Feel Lost

Use this rule:

- package / SDK / sales / internal logic -> private repo
- public GitHub / stars / safe open history -> public repo

If unsure, keep it private first.

## Staleness Rule

The public repo is allowed to lag.

That is not failure. It is the design.

What must stay current is:

- the private repo as source of truth
- the public repo only when you intentionally want public-safe visibility
