# Workflow

This repo is the private engine and commercialization working copy for OpenIntelligence.

If you forget everything else, remember this:

- `OpenIntelligence/` is the shipping app repo
- `OpenIntelligence-Engine/` is the private engine / SDK / partner-materials repo
- `OpenIntelligence-Public/` is a local working copy for the public-safe branch of the public GitHub repo
- public-safe work flows out deliberately from private work, not the other way around

There is no separate public GitHub repository named `OpenIntelligence-Public`.
That local folder points at the same GitHub repository as `OpenIntelligence/`:

- `https://github.com/Gunnarguy/OpenIntelligence.git`

The difference is the branch you should treat as authoritative inside each local clone.

## The Three Local Working Copies

### 1. Shipping App Repo

Path:

- `/Users/gunnarhostetler/Documents/GitHub/OpenIntelligence`

Remote:

- `origin = https://github.com/Gunnarguy/OpenIntelligence.git`

Primary branch in use:

- `main`

Purpose:

- App Store shipping product
- app development
- App Store Connect release work
- public app code that is allowed in the shipping repo
- limited SDK-facing bridge code that belongs with the app target

This is the repo you should think of as:

- the shipping app brain
- the place for real product code that ships to users
- the place that pushes to public `main` only when the content is actually safe

### 2. Private Engine Repo

Path:

- `/Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Engine`

Remote:

- `origin = https://github.com/Gunnarguy/OpenIntelligence-Engine.git`

Primary branches in use:

- `main`
- `engine-founder-trials`

Purpose:

- private engine work
- SDK/framework packaging
- evaluation packet creation
- partner and commercialization materials
- internal audits
- verification and retrieval logic that should not be exposed publicly

This is the repo you should think of as:

- the private engine lab
- the SDK / evaluation packet / partner-packet brain
- the place where closed-source and commercialization work belongs

### 3. Public-Safe Working Copy

Path:

- `/Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public`

Remote:

- `origin = https://github.com/Gunnarguy/OpenIntelligence.git`

Primary branch you should use:

- `public-safe`

Purpose:

- safe mirror working copy for public GitHub changes
- README / release-note / marketing / public-safe app changes you intentionally want visible
- nothing private, nothing commercial, nothing SDK-diligence-specific

This is not a distinct GitHub repo.
It is a convenience working copy for the `public-safe` branch on the same public GitHub repository.

## The One-Sentence Mental Model

Use this:

- `OpenIntelligence` = shipping app repo
- `OpenIntelligence-Engine` = private engine + SDK + partner materials repo
- `OpenIntelligence-Public` = local staging clone for the public-safe branch of the public app repo

## The Correct Direction

The normal flow is:

`private engine/app work -> selective public-safe promotion`

Not:

`public repo -> private repo`

Why:

- the private engine repo is the superset for SDK/commercial work
- the shipping app repo is the real product repo
- the public-safe working copy is just a filtered mirror/staging area
- this prevents the public clone from becoming the accidental source of truth

## App Store Rule

App Store Connect does not require the public-safe working copy to be the primary repo.

Use `OpenIntelligence/` for:

- app code changes
- release prep
- metadata iteration
- shipping builds

Use `OpenIntelligence-Engine/` for:

- SDK packaging
- evaluation XCFramework work
- partner packet and commercialization work
- engine verification and retrieval logic

Use `OpenIntelligence-Public/` only when you intentionally want to prepare or review what will live on the public-safe branch.

## Simple Daily Rule

When working, ask one question:

"Is this something I would be comfortable publishing on public GitHub?"

If the answer is:

- `no` -> do it in `OpenIntelligence-Engine/` or keep it in the private side of your workflow
- `maybe` -> keep it out of the public-safe clone until you intentionally review it
- `yes` -> it can go to `OpenIntelligence/` and, if appropriate, to `public-safe` later

## What Must Stay Private

Do not publish these from `OpenIntelligence-Engine/` or from private work into the public-safe branch:

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

Public-safe usually means:

- product-facing docs
- release notes
- marketing metadata
- UI-level app improvements that do not expose private engine logic

## Public Demo Export

When the public repo needs to behave like a SideProjectors-safe demo snapshot,
do not curate it manually inside the public working copy.

Use the private engine repo as source of truth and run the engine-side export
tools:

- `scripts/public_demo_manifest.sh` — exact allowlist, denylist, and stub-needed paths
- `scripts/export_public_demo.sh` — dry-run or apply the curated export into `OpenIntelligence-Public/`
- `scripts/audit_public_demo_boundary.sh` — fail-closed audit that checks the public repo against the boundary

The export flow also overlays curated files from:

- `public_demo_overlay/`

That overlay is where the public demo app shell and public-facing doc overrides belong.

Recommended flow:

1. build and commit normally in `OpenIntelligence-Engine/`
2. run `./scripts/export_public_demo.sh` first without `--apply`
3. run it again with `--apply` once the plan looks right
4. run `./scripts/audit_public_demo_boundary.sh` if you want an explicit standalone check
5. review the diff in `OpenIntelligence-Public/`
6. keep or add demo stubs for any stripped service areas before pushing public changes

This keeps the public repo as a generated publish target rather than another dev repo.

## Summary-Only Rule

Some changes should be described publicly without promoting the code.

Use this for:

- engine reliability improvements
- ingestion fixes
- retrieval/groundedness improvements
- trust and verification improvements
- SDK/productization progress

For those, update public copy or release notes, but keep the implementation in
the private engine side.

## Promotion Process

When you want something public:

1. Decide which repo the work belongs in.
2. If it is shipping app code, do it in `OpenIntelligence/`.
3. If it is SDK / engine / partner / evaluation work, do it in `OpenIntelligence-Engine/`.
4. Commit in that source repo first.
5. Only then promote intentionally public-safe work into `OpenIntelligence-Public/` or directly onto the `public-safe` branch.
6. Push `public-safe` when you are ready.
7. Merge `public-safe` to public `main` only intentionally.

Important:

- do not treat `OpenIntelligence-Public/` as the canonical source repo
- do not develop private engine logic there
- do not assume its local `main` branch is the branch you should be using day to day

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

`OpenIntelligence/`:

- `main` tracks `origin/main`
- remote is the public GitHub repo

`OpenIntelligence-Engine/`:

- `main` tracks `origin/main`
- `engine-founder-trials` tracks `origin/engine-founder-trials`
- remote is the private engine GitHub repo

`OpenIntelligence-Public/`:

- `public-safe` is the public review branch
- it also points to `https://github.com/Gunnarguy/OpenIntelligence.git`
- its local `main` can diverge and confuse you, so prefer to stay on `public-safe`
- merge from `public-safe` to public `main` only on purpose

## If You Feel Lost

Use this rule:

- shipping app feature / App Store / product runtime -> `OpenIntelligence/`
- package / SDK / sales / internal logic -> `OpenIntelligence-Engine/`
- public GitHub / stars / safe open history -> `OpenIntelligence-Public/` on `public-safe`

If unsure, keep it private first.

## Staleness Rule

The public repo is allowed to lag.

That is not failure. It is the design.

What must stay current is:

- `OpenIntelligence/` as the shipping app source of truth
- `OpenIntelligence-Engine/` as the private engine/source-of-truth for SDK and commercialization work
- `OpenIntelligence-Public/` only when you intentionally want public-safe visibility
