# Current State

Updated: 2026-08-28
Branch/worktree: main (primary checkout, `~/Documents/GitHub/OpenIntelligence`)
Last verified commit: eb432d3

## Objective

Make a stage that silently drops data visible on any document, with no ground truth and no benchmark.
Complete for the transitions inside `DocumentProcessor`; **uncommitted**, see Exact Next Action.

## Status

The governance work from earlier today is committed (`3d32a8b`, `eb432d3`). This is the first
product change since, and the first Swift change since the enforcement layer was built.

**The plan's headline justification did not survive contact with the code, and the finding that
replaced it is better.** The 55% truncation I cited happens at *embed* time (a 128-token cap against
a 512-token model), downstream of everything measured here, and `DocumentProcessor.verifyTokenizerCounts`
already catches that class behaviourally. What was actually missing is narrower and was sitting in
plain sight.

## Completed

1. **`verifyContentCoverage` computed the volume metric and compared only the vocabulary one.** That
   function has two metrics. `coverage`, a set intersection of unique words, had a `< 90` threshold.
   `charRatio`, the same comparison by character volume, was computed, interpolated into the
   **healthy-path debug line**, and compared against nothing anywhere in the file. The two fail
   differently and that is the point: unique vocabulary saturates long before content does, so
   truncating the back half of a document leaves `coverage` above 90 while half the text is gone.
   `charRatio` now has a floor of 90% and a ceiling of 200%, and both numbers print on every warning.
   The function's own comment reads "This catches bugs where content is silently dropped during
   chunking."
2. **`IngestionStageLedger` records each transition, so a loss names its own stage.**
   `verifyContentCoverage` is one end-to-end comparison across four stages and can only say text was
   lost. The ledger bands each transition: chunking may exceed 1.0 because overlap repeats text,
   while metadata sanitising and token-limit splitting must conserve characters **exactly**. That
   last band is the sharp one, because a split raises the chunk count while keeping every character,
   so no count distinguishes a healthy split from a truncation. It also flags a run where every chunk
   came out the same length past three chunks. Every reading counts `chunk.text`, never
   `chunk.metadata.characterCount`.

Roadmap row, deliberately left **In Progress**:
[A content-loss check computed the volume metric and compared only the vocabulary one](https://app.notion.com/p/3ca49a74d54f813da47dee8ad5cd8442)
— `Future Backlog`. Suite-green does not close it; its own closing condition is an `[IngestionLedger]`
line from a real document on device.

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

Commit the six files in Working Set. This is the first Swift commit since the enforcement layer was
built, so `scripts/enforce_docs_hook.sh` gates it for real: it requires `Docs/INGESTION_PIPELINE.md`
and `CHANGELOG.md`, both of which are already updated.

```bash
git add OpenIntelligence/Services/Document/Processing/IngestionStageLedger.swift OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift OpenIntelligenceTests/Services/Document/Processing/IngestionStageLedgerTests.swift Docs/INGESTION_PIPELINE.md CHANGELOG.md Docs/ai/STATE.md
```

Then, to close the roadmap row: ingest one real document on device and read the log for
`[IngestionLedger]`. A healthy line reads `chunked 1.xx, sanitized 1.000, token-limited 1.000`. If
`sanitized` or `token-limited` is anything other than 1.000, that is a real defect this session
found and did not fix, not a band that needs widening.
