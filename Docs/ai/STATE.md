# Current State

Updated: 2026-08-28
Branch/worktree: main (primary checkout, `~/Documents/GitHub/OpenIntelligence`)
Last verified commit: 9d80e7d

## Objective

None active. Three pieces of work completed and committed today: the governance enforcement layer,
ingestion drop accounting, and a claims audit across every public surface.

## Status

**Live on the App Store, read from ASC 2026-08-28:** iOS **5.0** (approved 2026-08-27), macOS
**5.0.2** (approved 2026-08-28). Nothing in review. `v5.1` records exist for both platforms in
`PREPARE_FOR_SUBMISSION`.

**The platforms have diverged and it keeps getting lost.** macOS carries 5.0.1 and 5.0.2 fixes that
iOS has never received, so "shipped" and "fixed for the user" are not the same statement right now.
`Docs/SHIPPED_VERSION.json` is the per-platform record.

**Claims audit result: the public copy was already right; the internal docs were not.** All three
websites, the App Store description, the README's PCC statements, `SHIPPED_VERSION.json` and
`SHIPPED_CAPABILITIES.json` correctly describe PCC in the future tense. Four documents still said
GitHub Actions builds releases, and two described a two-day-stale release state. All corrected.

## Completed

1. **Governance enforcement layer** (`3d32a8b`, `eb432d3`). Path-aware pre-commit doc enforcement,
   Notion write receipts, an obligation-based Stop hook, and an `InstructionsLoaded` log that
   answers whether a rule actually loaded. It gated its first real Swift commit correctly.
2. **Ingestion drop accounting** (`6004d97`, `9d80e7d`). `verifyContentCoverage` computed a volume
   metric and compared only the vocabulary one; `IngestionStageLedger` now bands each transition in
   the unit that stage conserves. The `token-limited` band was wrong on first commit and fixed the
   same day.
3. **Claims audit.** Corrected `README.md`, `Docs/ROADMAP.md`, `Docs/README.md`, `Docs/ai/RUNBOOK.md`,
   `Docs/RELEASE_NOTES.md` and the note in `Docs/SHIPPED_CAPABILITIES.json`. Wrote the PCC enable-day
   procedure into the runbook.

Notion, this session: two rows created, three updated. The row
[Documents tab blocked its own appearance](https://app.notion.com/3c949a74d54f81d0911ac74bc4dafa3e)
was **deliberately left In Progress** — its fix shipped in 5.0.1, macOS only, so it is still live for
every iOS user. A dated note on the row explains that.

## Active Constraints

- **The Xcode Cloud workflow is pinned to Xcode 26.6 (17F113) and must not go back to "Latest
  Release".** Twelve sites sit behind `#if compiler(>=6.4)`. Measured 2026-08-28: Xcode 26.6 ships
  Swift 6.3.3 so PCC compiles **out**; Xcode 27 ships Swift 6.4 so it compiles **in**, contradicting
  the App Store description, the README and the in-app copy. Xcode 27 is at beta 6, so "Latest
  Release" becomes it silently. `ci_scripts/ci_post_xcodebuild.sh` is the backstop proving the pin
  still holds — verified against a real Xcode 27 binary where it found 18 PCC symbols and exited 1.
- **`app_store` in `Docs/SHIPPED_VERSION.json` stays at `5.0`** while iOS lags. macOS is 5.0.2.
  Per-platform truth lives in `app_store_by_platform`; understating is the safe direction and is why
  that file exists.
- **Put 5.1 entries under `## 5.1`, not `## [Unreleased]`.** `ci_post_clone.sh` stamps
  `MARKETING_VERSION` from the first numbered heading and refuses to build when `[Unreleased]` holds
  entries above an uncut heading. `scripts/enforce_docs_hook.sh` now rejects it at commit time too.
- **iOS 27 shipping does not enable PCC.** The gate is `#if compiler(>=6.4)`, resolved by the
  compiler, not the device. Every shipped binary was built on Xcode 26.6 / Swift 6.3.3, so PCC is not
  in it, and a user updating to iOS 27 runs that same binary. Enabling it needs an app release built
  on Xcode 27 — and **both release guards are built to refuse that build**. See "Enabling Private
  Cloud Compute" in `Docs/ai/RUNBOOK.md` before touching the gates.
- **Do not remove the `unreleased` HTML comment from the `## 5.1` heading line until 5.1 ships.** It
  is the only record in this repository that the section is open, `repoos_router.py` reads it from
  that line alone, and removing it is what "cutting the release" means.
- **`scripts/required_docs.sh` and the table in `.agents/rules/01-docs-and-notion-sync.md` are one
  fact in two files.** Change both in the same edit; the script is the copy that gets obeyed.
- **Paths in `ci_scripts/` must resolve from `$0`, not the working directory.** See Blockers.
- **No `xcodebuild test` runs in CI any more.** The Xcode Cloud TestFlight entries are post-actions,
  not test actions, and Actions is gone. Tests only run locally.

## Working Set

Six uncommitted files. Open these first:

| File | Why |
|---|---|
| `OpenIntelligence/Services/Document/Processing/IngestionStageLedger.swift` | **New.** The bands live here, each with the reason it holds |
| `OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift` | Four `stageLedger` calls near lines 831–958; `verifyContentCoverage` near 6690 |
| `OpenIntelligenceTests/Services/Document/Processing/IngestionStageLedgerTests.swift` | **New.** 10 cases. Imports `OpenIntelligenceEngine`, not `OpenIntelligence` |
| `Docs/INGESTION_PIPELINE.md` | New §3.5, including the table of which guard is blind to what |
| `CHANGELOG.md` | Two `[Ingestion]` entries under `## 5.1` |
| `Docs/ai/STATE.md` | This file |

**Do not loosen a band to make something pass.** Making the ledger agree with whatever broke is the
exact failure it was written against; `IngestionStageLedgerTests` fails if `.exact` moves.

## Verification

- `xcodebuild build -configuration Debug -destination 'generic/platform=iOS Simulator'` → **BUILD SUCCEEDED**
- `xcodebuild test` on the iOS 27 simulator, `IngestionStageLedgerTests` + `DocumentProcessorTests` +
  `SemanticChunkerTests` → **34 tests, 0 failures** (10 / 15 / 9)
- Router preflight for this task → route `ingestion_change`, allowed `Services/Document/**` only

**The iCloud `NSFileCoordinator` deadlock recurred, and intermittently.** `xcodebuild build` succeeded
from `~/Documents` at 16:59; `xcodebuild test` from the same directory minutes later hung at 0% CPU
with 2.29s of CPU time and never built the test bundle. `sample` showed
`DVTFilePath performCoordinatedReadRecursively:` → `NSFileCoordinator` → `semaphore_wait_trap` under
`Xcode3Project initWithFilePath:`. The recorded fix worked unchanged: `rsync` to `/private/tmp/oi-src`
and build there. Do not conclude from one successful build in `~/Documents` that the copy is
unnecessary.

**Not verified: the ledger has never run on a real document.** Every test drives the type directly
with synthetic readings. Nothing has yet observed an `[IngestionLedger]` line from an actual ingest,
which is the only thing that proves the four call sites are wired to the values they claim.

**Not covered: chunking → embedding and embedding → index.** Both live in `RAGService.swift`, outside
this route's `Services/Document/**` boundary. They need their own approval and are the next pass.

## Blockers / Unknowns

None blocking. Three defects filed in Notion:

1. **[Six file families sync without NSFileCoordinator](https://app.notion.com/p/3ca49a74d54f8103b69be921f0335171)**
   — **now `v5.1`**, promoted 2026-08-28. Corrupts user data and already has: 599 conflict copies,
   136 unreadable zero-block files, 17 days of dead sync, and real chat history and vector indexes
   destroyed when the container was cleaned. `coordinatedMergeData` covers 4 paths, which had 0
   conflict copies; the 6 uncoordinated families had all 599.
2. **[420 workspace reloads per import](https://app.notion.com/p/3ca49a74d54f81a6b8c1e4827a6585fa)**
   — `Future Backlog`. Quality, not data loss.
3. **[17 views still use NavigationView](https://app.notion.com/p/3ca49a74d54f81eb867cf24a119af0c1)**
   — `Future Backlog`.

**Worth checking, unresolved:** `ci_post_clone.sh` runs
`sh ../scripts/probe_afm_advanced_canary.sh || true`. The capability guard added on the line below it
used the same CWD-relative style and failed on Xcode Cloud with exit 2 — python3's "cannot open
file" — breaking build 426. The guard now resolves from `$0` and build 427 passed, but the canary
still uses the old style **and** swallows its own failure, so it may not have run on Xcode Cloud for
some time without saying so. Verify by making it print and dropping the `|| true` for one run.

**Unexplained, did not recur:** build 424 failed with actor-isolation errors on
`HybridSearchService.stableTieBreakKey`, `analyse` and `overridesLock`, in the **macOS archive only**
— iOS archived fine in the same run. It does not reproduce locally in any combination tried (Xcode
26.6 and 27, Debug and Release, iOS and macOS), and build 427 archived both platforms cleanly. If it
returns, pull the Xcode Cloud build log rather than guessing at a fix.

## Exact Next Action

None. All three pieces are committed and verified; the working tree is clean.

When 5.1 work starts, the open row that meets the release bar is
[Six file families sync without NSFileCoordinator](https://app.notion.com/p/3ca49a74d54f8103b69be921f0335171)
— the only one that loses user data.

**On PCC enable day (targeted at the iOS/macOS 27 public release):** read
"Enabling Private Cloud Compute" in `Docs/ai/RUNBOOK.md` first. It lists both guards that must be
inverted, every surface that states the claim, which of the three websites sync themselves, and the
ordering rule — ship first, then claim, and approval is the event, not submission.

Two things are still unverified and neither is blocking:
- `IngestionStageLedger` has never emitted on a real document. Ingest one on device and grep for
  `[IngestionLedger]`.
- **One semantic decision is open.** The roadmap now has `Shipped On`, so
  [the Documents-tab row](https://app.notion.com/3c949a74d54f81d0911ac74bc4dafa3e) could move to
  `Completed` with `Shipped On: macOS` — the work is done and live on macOS, and the iOS gap is now
  expressible rather than hidden. It is still `In Progress` with a dated note saying why, written
  before the property existed. Changing it means deciding that `Status` tracks the work and
  `Shipped On` tracks reach; leaving it means `Status` waits for every platform. Either is coherent;
  the board should pick one and say so in the skill.
- `Shipped On` is populated on two rows only, both verified. Everywhere else it is empty, which
  means *not recorded*, not *not shipped*. A bulk backfill is possible — every `Completed` row
  targeted `v5.0` or earlier shipped to both platforms, except the split-numbered `v4.7 (iOS) /
  v3.0 (macOS)` and `v4.8 (iOS)` options — but that is 200+ writes asserting a per-row fact, and it
  was not done.
