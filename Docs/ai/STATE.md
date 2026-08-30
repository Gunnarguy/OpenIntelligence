# Current State

Updated: 2026-08-29
Branch/worktree: main (primary checkout)
Last verified commit: adb0cda

## Objective

**Make macOS ingestion usable.** Three fixes are **implemented, built and suite-verified**; none is
verified on device, which is what closes their rows. An external tester on a fanless M5 MacBook Air ingested a 210-page,
64 MB PDF on 2026-08-29. It completed, correctly, in **five hours**, producing ~5000 chunks. The
owner has committed to the tester, in writing, that macOS ingestion performance and a pause control
are top priority for `v5.1`.

Three defects, all in `#if canImport(UIKit)` / `#elseif canImport(AppKit)` seams, none of them in the
routing policy where they were first assumed to be. See "External device evidence" below. The owner
granted `PROCEED: IMPLEMENT` on 2026-08-29 and defect 1 is fixed in that session.

## Status

**Live on the App Store**, read from App Store Connect 2026-08-28: iOS **5.0** (approved 08-27),
macOS **5.0.2** (approved 08-28). Nothing is in review. `v5.1` records exist for both platforms in
`PREPARE_FOR_SUBMISSION` and have not shipped.

**The platforms have diverged and it keeps causing errors.** macOS carries 5.0.1 and 5.0.2 fixes iOS
has never received, so "shipped" and "fixed for the user" are different statements.
`Docs/SHIPPED_VERSION.json` is the per-platform record; the Notion `Shipped On` property is the
per-row one.

**Public claims are accurate.** All three websites, the App Store description, `README.md`,
`SHIPPED_VERSION.json` and `SHIPPED_CAPABILITIES.json` describe PCC correctly in the future tense and
5.0 correctly as shipped. Verified live on 2026-08-28 after the sync fixes below.

## Completed

1. **Governance enforcement layer** (`3d32a8b`, `eb432d3`). `scripts/required_docs.sh` is the single
   executable path-to-document table; `scripts/enforce_docs_hook.sh` fails a commit whose staged
   source lacks its required docs and enforces `ci_post_clone.sh`'s empty-`[Unreleased]` invariant at
   commit time. `.claude/hooks/notion-receipt.sh` receipts real Notion writes. The Stop hook checks
   three obligations, not one. An `InstructionsLoaded` hook logs which rule files actually loaded.
2. **Ingestion drop accounting** (`6004d97`, `9d80e7d`). `verifyContentCoverage` computed a volume
   metric (`charRatio`) and asserted only on the vocabulary one, so a 55% volume loss could pass
   while unique-word coverage stayed above 90%. `IngestionStageLedger` now bands each transition in
   the unit that stage actually conserves. **The `token-limited` band was wrong on first commit and
   fixed the same day** — it asserted exact character conservation, and
   `splitOversizedChunkByTokens` discards every `.!?` separator via `components(separatedBy:)`.
3. **Claims audit and doc corrections** (`d5e9310`). Four documents said GitHub Actions builds
   releases, including `README.md` linking to a workflow file that no longer exists and
   `Docs/ai/RUNBOOK.md` telling a future session to ship with it. Corrected, plus a written PCC
   enable-day procedure.
4. **Roadmap schema and semantics** (`6f0620f`, `786b70d`). Added `v5.0.1`/`v5.0.2` and a `Shipped On`
   multi-select; backfilled 88 rows. Rationale in `Docs/ai/DECISIONS.md` 2026-08-28.
5. **Website sync repair.** Both public sites were serving stale generated artifacts. Root cause was
   that the day's commits were unpushed, so the portfolio sync had nothing to copy. Both sync
   workflows had silent-failure modes; both fixed in their own repositories (see Blockers).

## Active Constraints

- **iOS 27 shipping does not enable PCC.** The gate is `#if compiler(>=6.4)`, resolved by the
  compiler, not the device. Shipped binaries were built on Xcode 26.6 / Swift 6.3.3, so PCC is not in
  them and a user updating to iOS 27 gets nothing new. **Both release guards are built to refuse the
  build that enables it** — read "Enabling Private Cloud Compute" in `Docs/ai/RUNBOOK.md` before
  touching the gates.
- **Do not remove the `unreleased` HTML comment from the `## 5.1` heading line** in `CHANGELOG.md`
  until 5.1 ships. `repoos_router.py` reads it from that line and nowhere else; without it the router
  reports 5.1 as already shipped.
- **`Status` tracks the work; `Shipped On` tracks reach.** The rule lives in `CLAUDE.md`,
  `.claude/skills/notion-roadmap/SKILL.md` and `.agents/rules/01-docs-and-notion-sync.md`. All three
  must move together.
- Releases are built by **Xcode Cloud**, pinned to Xcode 26.6. `.github/workflows/` no longer exists
  in this repository.

## Working Set

| Path | Why it matters |
|---|---|
| `OpenIntelligence/Services/Document/Processing/IngestionStageLedger.swift` | The per-stage conservation ledger. Its header explains what it does and does not replace. |
| `OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift` | Ledger is threaded at four points around lines 826–958. `verifyContentCoverage` is at 6653, `splitOversizedChunkByTokens` at 6539. |
| `Docs/ai/RUNBOOK.md` | Contains the PCC enable-day procedure, including both guards that must be inverted. |
| `Docs/SHIPPED_VERSION.json`, `Docs/SHIPPED_CAPABILITIES.json` | The two markers every public claim is checked against. |
| `scripts/enforce_docs_hook.sh`, `scripts/required_docs.sh` | The pre-commit enforcement and its single source table. |
| `OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift:6923-7018` | `renderPDFPageAsImage`. The UIKit and AppKit branches are not equivalent; the AppKit one is the macOS bottleneck. |
| `OpenIntelligence/Services/Document/Chunking/PageComplexityAnalyzer.swift:1045-1072` | `renderPageForAnalysis` returns `nil` on macOS, which disables the Vision pass at `:298`. |
| `OpenIntelligence/Services/Infrastructure/Monitoring/DeviceCapabilityService.swift:412-470` | Vision concurrency and cooldown ceilings, chosen from the chip with no thermal input. |

Working tree is clean. Nothing uncommitted in this repository.

## Verification

- `bash scripts/test_enforce_docs_hook.sh` -> 10 passed, 0 failed.
- `bash scripts/test_stop_handoff.sh` -> 8 passed, 0 failed.
- `python3 .codex/skills/route-openintelligence-work/scripts/test_repoos_router.py` -> 29 tests, OK.
- `xcodebuild test` on iOS 27 simulator, `-only-testing` IngestionStageLedgerTests +
  DocumentProcessorTests + SemanticChunkerTests -> **35 tests, 0 failures**.
- `python3 scripts/verify_capabilities.py` -> all declared capabilities have their implementation.
- `python3 scripts/secret_scan.py` -> clean.
- Notion: 224 rows, per-option `Target Release` counts identical before and after the schema change.
- Websites: gunzino.me, fascinaiting.me and gunnarguy.me each fetched live and confirmed to describe
  5.0 as shipped and PCC in the future tense.

### 2026-08-29, the macOS render fix

- Standalone AppKit probe on this host, `backingScaleFactor` 2.0, reproducing the old code path:
  `NSImage.lockFocus` rasters a 3060×3960 request at **6120×7920** (4.0× the pixels, 16 bits per
  component) with a **370 MB** `tiffRepresentation`; the replacement `CGBitmapContext` produces
  3060×3960 with a 46 MB backing store and no serialization. **8× less raster.**
- macOS Debug build from `/private/tmp/oi-src` -> **BUILD SUCCEEDED**, 0 errors, 0 warnings.
- `xcodebuild test` on iOS 27 sim `8FA2B3CE-…`, `-only-testing` DocumentProcessorTests +
  SemanticChunkerTests + IngestionStageLedgerTests -> **35 tests, 0 failures**.
- `bash scripts/build_simulator_smoke.sh` (from the copy, fresh DerivedData) -> **BUILD SUCCEEDED**,
  ad-hoc codesign clean.
- `python3 scripts/secret_scan.py` -> clean.
- `bash scripts/enforce_docs_hook.sh` over the staged set -> exit 0.

**Not run:** the full `xcodebuild test` suite, and the route's "large PDF (>10MB) manual ingest",
which needs a device. **Not measured:** the wall-clock effect of the render
fix on a real document. No speedup is claimed anywhere, deliberately — the per-page render timing now
logged is what will measure it.

### 2026-08-29, OCR language narrowing

- Full `xcodebuild test` -> **392 tests, 3 skipped, 0 failures** (380 before, plus 12 new).
- `OCRLanguageNarrowingTests` -> 12 cases, 0 failures.
- macOS Debug build -> **BUILD SUCCEEDED**, 0 errors.
- `bash scripts/build_simulator_smoke.sh` -> **BUILD SUCCEEDED**, ad-hoc codesign clean.

Came out of an audit of the ingestion path against Apple's SDK headers rather than from a bug
report. **`Docs/ai/DECISIONS.md` and the artifact linked from the roadmap rows carry the reasoning;
the short version is that four independent controls all govern how many pixels of each character
reach Vision, and all four were set to maximum.** This change addresses one of them. The other
three are filed and deliberately not started, because attributing the tester's five hours to any one
of them is still inference.

### 2026-08-29, restored-progress reporting

- Full `xcodebuild test` on iOS 27 sim -> **380 tests, 3 skipped, 0 failures**. The three skips are
  in `EmbeddingProviderAgreementTests` and `LayoutReadingOrderTests` and are unrelated to this work.
- macOS Debug build with the wiring -> **BUILD SUCCEEDED**, 0 errors.
- `bash scripts/build_simulator_smoke.sh` -> **BUILD SUCCEEDED**, ad-hoc codesign clean.
- `RestoredIngestionProgressTests` -> 14 cases, 0 failures.
- Repo-wide grep required by `.claude/rules/orchestration-and-routing.md`: all three
  `PrivateCloudComputeLanguageModel` uses remain gated by `EntitlementChecker`
  (`FoundationModelRoutePolicy.swift:124`, `FoundationModelSessionFactory.swift:89`,
  `FoundationModelCapabilityProvider.swift:39`).

**`RAGService.swift` is a Tier-2 hard-boundary file** (`Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md`
line 32). The owner approved the named change on 2026-08-29 after being shown the exact diff. The
edit is two assignments inside the `.paused` branch of queue restore. **The streaming contract the
boundary exists to protect — page batching, `db.persist()` cadence, incremental FTS5 appends, the
`localCacheDir()/IngestionCheckpoints` location — is untouched.**

**Two `.claude/rules/` files that govern this code never loaded during the work.**
`scripts/instructions_report.sh` shows `ingestion-and-indexing.md` and `orchestration-and-routing.md`
as matched-but-`NOT LOADED`. The globs are correct; the loader keys off Read/Edit/Write and every
edit in this session went through Bash. Between them those rules carried four requirements the
session would otherwise have missed: the ingestion Mermaid, the **full** suite rather than the
preflight's targeted classes, the Atlas service map, and the PCC gating grep. All four were
satisfied only because the Stop hook fired. Filed as a `Future Backlog` row.

**`xcodebuild` deadlocked on `~/Documents` again** at the start of this work: 7 log lines, 0% CPU,
`sample` showed `-[DVTFilePath performCoordinatedReadRecursively:]` in `semaphore_wait_trap`. Building
from a `ditto` copy at `/private/tmp/oi-src` fixed it, as the runbook says. `rsync` is blocked by the
agent permission classifier in this environment; `ditto` is not.

## Blockers / Unknowns

None blocking. Four open items, each with a verification path:

1. **`IngestionStageLedger` has never emitted on a real document.** Ingest a document on device and
   grep the log for `[IngestionLedger]`. A healthy line reads roughly
   `chunked 1.xx, sanitized 1.000, token-limited 1.0x`. If a warning fires, read the named stage
   before touching the band — widening a band to silence a warning is always the wrong response.
2. **The sync-workflow fixes are verified on the success path only.** `Fascinaiting@4461907e` (rebase
   and retry the push) and `Gunnarguy-Portfolio@265306a` (verify each source checkout, fail the run
   if one is missing) both ran green with everything healthy. Neither red path was exercised, because
   proving it meant committing a broken workflow. The guards are wired and their conditions evaluate;
   the first real failure is still their first real test.
3. **`Shipped On` is empty on 68 rows targeted `v4.0`–`v4.5`.** The only macOS versions documented
   anywhere in this repository are 2.5, 3.0, 4.8, 5.0 and 5.0.2, the earliest tied to iOS 4.6, so
   macOS parity before that cannot be established from what is written down. Empty means *not
   recorded*. If the early macOS release history turns up, that is the gap to fill.
4. **`Gunnarguy-Portfolio` has uncommitted `styles.css` changes** that block `git pull`, so that
   local checkout silently lags `origin/main`. Not this repository, and left alone deliberately.
5. **The macOS ingestion diagnosis has not been measured.** Every claim in "External device evidence"
   below is read from source and from Apple's SDK headers. Nobody has instrumented a macOS ingestion
   run to confirm how the five hours actually divide between the render path, OCR and embedding. Do
   that before tuning anything, or the fix gets tuned against a guess.

## External device evidence, 2026-08-29

First real observation of the macOS ingestion path under load, from a free-lifetime-cohort tester on
a fanless MacBook Air (M5). 210-page, 64 MB PDF of *Science*: five hours, ~5000 chunks, completed
correctly. CPU oscillating 400% to 100%, GPU idle in Activity Monitor, 33% battery in the first
1h20m. Owner reports an 8-page document takes ~1 minute on iPhone against ~30 minutes on Mac.

Three defects found. Defect 1 is now measured; 2 and 3 are read from code and the MacOSX27.0 SDK
headers `[evidence_level: code_read, confidence: high]`:

1. **`renderPDFPageAsImage` macOS branch.** Uses deprecated `NSImage.lockFocus` plus a full
   `tiffRepresentation` -> `NSBitmapImageRep(data:)` CPU round-trip per page. `AppKit/NSImage.h:294`
   states the deprecation reason: the method "is incompatible with resolution-independent drawing",
   so its backing store follows the display scale factor. **Measured on this host with a standalone
   AppKit probe:** a page requested at 3060x3960 rasters at 6120x7920, exactly 4.0x the pixels, and
   its `tiffRepresentation` is 370 MB encoded and decoded per page, against 46 MB and no
   serialization through the `CGBitmapContext` that replaced it. iOS renders the same page through `UIGraphicsImageRenderer` with an explicit
   `format.scale = 1.0` and no serialization at all. Filed `v5.1`.
2. **`renderPageForAnalysis` returns `nil` on macOS** (`#else return nil`), and both production call
   sites reach it through `analyzeBatch`, which passes no `pageImage`. The Vision refinement pass in
   `PageComplexityAnalyzer` therefore never runs on macOS, and `isMixedModeScanned` is permanently
   false there. Filed `Future Backlog`.
3. **`[GPU-accelerated]` is a string literal** selected by a config flag, appended to a macOS log
   line whose dominant stages are CPU. This is why the logs pointed away from the bottleneck. Filed
   `Future Backlog`.

**One owner statement the code contradicts, and one this session got wrong:**

- *"Macs treat everything as needing to be visually interpreted."* There are **zero** platform
  conditionals in `OpenIntelligence/Services/Document/`. Losing the Vision pass biases macOS toward
  classifying pages as *less* visual, not more. The slowness is mechanical, not a routing choice.
- *"Progress is not preserved across a restart."* **This session claimed that and it was wrong.**
  `importLargePDFStreamed` checkpoints `lastCompletedPage` to
  `localCacheDir()/IngestionCheckpoints/<fingerprint>/ingestion_state.json` after every 15-page batch
  and skips completed batches on re-entry (`RAGService+Streaming.swift:36-88`). The owner's statement
  to the tester was correct for that 64MB document. The error came from grepping only
  `Services/Storage/`; `Docs/INGESTION_PIPELINE.md` §5 had it documented correctly all along. What is
  genuinely missing: no user-facing pause control, checkpointing gated on `fileSizeMB > 10 && .pdf`
  (`RAGService.swift:5666`), and a restored item showing `progress = nil` so the UI looks like the
  work was lost when it was not.

## Exact Next Action

**Get a macOS device run.** Everything else is blocked on this. It closes all three open fixes at
once: build the Mac app, ingest a large PDF, then

1. read the per-page render line for render-vs-OCR cost,
2. check `OCR languages narrowed 13 -> N` fired rather than `NOT narrowed`,
3. quit mid-ingest and reopen, and confirm the restored item reports its true page count.

**Do not tune any further OCR threshold before that run.** The remaining three controls
(render scale, `minimumTextHeight`, Vision concurrency) are filed with the evidence, and changing
them now would be tuning against a guess.

```
[DocumentProcessor] Rendered PDF page at WxHpx (N DPI) in X.Xms via CGBitmapContext, CPU raster
```

Paired with the existing `Page N: OCR extracted ... (Y.YYs)` line that splits render cost from OCR
cost per page for the first time. That tells us whether the render path owned the five hours or only
part of them, and it is what closes
[the render row](https://app.notion.com/p/3cb49a74d54f8150b2dbc1ef12d7f3e0) (`In Progress`).

Sending the same document back to the tester is the highest-value version of this, since his machine
is fanless and the maintainer's is not.

Then, in order:

- [Render scale and minimumTextHeight both max out the same quantity](https://app.notion.com/p/3cc49a74d54f816f8ee4d2ed6e687cb3)
  — `Future Backlog`. Blocked on the device run above; the two controls must be coupled to one
  derived target rather than tuned separately.
- [Retrieval is nondeterministic, which makes every quality change unfalsifiable](https://app.notion.com/p/3cc49a74d54f81d7a88dffe679ce9bb1)
  — `Future Backlog`, and it gates every other retrieval row including contextual retrieval and the
  embedding migration. Two runs of one build return different evidence for one question.
- [Ingestion has no pause control, and only PDFs over 10MB checkpoint](https://app.notion.com/p/3cb49a74d54f819797e8cea0e96d62b9)
  — `v5.1`. The restored-progress display is **done**; what remains on this row is the pause button
  itself and the `fileSizeMB > 10 && .pdf` gate on checkpointing.
- [Six file families sync without NSFileCoordinator](https://app.notion.com/p/3ca49a74d54f8103b69be921f0335171)
  — `v5.1`, the only open row that loses user data, with 599 conflict copies already observed.
- [Vision pass never runs on macOS](https://app.notion.com/p/3cb49a74d54f81fbb47cec6d8ed526d8)
  — `Future Backlog`. Re-measure after the render fix lands: adding the macOS Vision pass adds work,
  so it should not go in until the render cost is known to be down.

If 5.1 work starts, write entries under the existing `## 5.1` heading in `CHANGELOG.md`, **not**
under `[Unreleased]`, and leave `app_store` at `5.0` in `Docs/SHIPPED_VERSION.json` until iOS ships
past it.
