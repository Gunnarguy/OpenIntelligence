# Current State

Updated: 2026-08-29
Branch/worktree: main (primary checkout)
Last verified commit: adb0cda

## Objective

**Make macOS ingestion usable.** An external tester on a fanless M5 MacBook Air ingested a 210-page,
64 MB PDF on 2026-08-29. It completed, correctly, in **five hours**, producing ~5000 chunks. The
owner has committed to the tester, in writing, that macOS ingestion performance and a pause control
are top priority for `v5.1`.

Diagnosis is done and is code-read, not measured. Three defects, all in `#if canImport(UIKit)` /
`#elseif canImport(AppKit)` seams, none of them in the routing policy where they were first assumed
to be. See "External device evidence" below. No source has been edited: this is a diagnosis, and the
implementation gate has not been passed.

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

**Not run this session:** the full `xcodebuild test` suite, and `bash scripts/build_simulator_smoke.sh`.
Only the three targeted test classes above were executed.

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

Three defects found, all verified by reading code and the MacOSX27.0 SDK headers
`[evidence_level: code_read, confidence: high]`:

1. **`renderPDFPageAsImage` macOS branch.** Uses deprecated `NSImage.lockFocus` plus a full
   `tiffRepresentation` -> `NSBitmapImageRep(data:)` CPU round-trip per page. `AppKit/NSImage.h:294`
   states the deprecation reason: the method "is incompatible with resolution-independent drawing",
   so its backing store follows the display scale factor and is 4x the requested pixel count on a
   Retina display. iOS renders the same page through `UIGraphicsImageRenderer` with an explicit
   `format.scale = 1.0` and no serialization at all. Filed `v5.1`.
2. **`renderPageForAnalysis` returns `nil` on macOS** (`#else return nil`), and both production call
   sites reach it through `analyzeBatch`, which passes no `pageImage`. The Vision refinement pass in
   `PageComplexityAnalyzer` therefore never runs on macOS, and `isMixedModeScanned` is permanently
   false there. Filed `Future Backlog`.
3. **`[GPU-accelerated]` is a string literal** selected by a config flag, appended to a macOS log
   line whose dominant stages are CPU. This is why the logs pointed away from the bottleneck. Filed
   `Future Backlog`.

**Two owner statements that the code contradicts, both told to the tester and worth correcting:**

- *"It SHOULD save the progress if you close out and reopen it."* It does not. `RAGService.swift:1186`
  sets `stage = .paused` and `progress = nil` on restart, and `IngestionItem` has no checkpoint
  field, so resuming re-runs the document from the start.
- *"Macs treat everything as needing to be visually interpreted."* There are **zero** platform
  conditionals in `OpenIntelligence/Services/Document/`. Losing the Vision pass biases macOS toward
  classifying pages as *less* visual, not more. The slowness is mechanical, not a routing choice.

## Exact Next Action

Instrument a macOS ingestion run before changing anything, so the fix is tuned against measurement
rather than against the code-read diagnosis above. Then take the render path:

[macOS renders every OCR page through deprecated lockFocus and a full TIFF round-trip](https://app.notion.com/p/3cb49a74d54f8150b2dbc1ef12d7f3e0)
— `v5.1`. The fix Apple's own header names is
`+[NSGraphicsContext graphicsContextWithBitmapImageRep:]`, which takes explicit pixel dimensions and
removes both the 4x oversize and the TIFF round-trip in one change.

`DocumentProcessor.swift` is not a hard-boundary file, but the route is `core_ai_ios27_change` and
carries `Approval: always`. **A source edit needs `PROCEED: IMPLEMENT` from the user first.**

The other open `v5.1` rows:

- [Ingestion cannot be paused, and restarting discards in-flight progress](https://app.notion.com/p/3cb49a74d54f819797e8cea0e96d62b9)
- [Six file families sync without NSFileCoordinator](https://app.notion.com/p/3ca49a74d54f8103b69be921f0335171)
  — the only open row that loses user data, with 599 conflict copies already observed.

If 5.1 work starts, write entries under the existing `## 5.1` heading in `CHANGELOG.md`, **not**
under `[Unreleased]`, and leave `app_store` at `5.0` in `Docs/SHIPPED_VERSION.json` until iOS ships
past it.
