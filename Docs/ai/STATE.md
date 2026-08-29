# Current State

Updated: 2026-08-28
Branch/worktree: main (primary checkout)
Last verified commit: 81add91

## Objective

None active. Three objectives ran to completion this session and all are committed, pushed and
verified. A fresh session should ask what to pick up, or take a roadmap row.

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

## Exact Next Action

None. All three objectives are complete and verified, and the working tree is clean. Ask the user
what to pick up, or take the highest-value open roadmap row:

[Six file families sync without NSFileCoordinator](https://app.notion.com/p/3ca49a74d54f8103b69be921f0335171)
— `v5.1`, the only open row that loses user data, with 599 conflict copies already observed.

If 5.1 work starts, write entries under the existing `## 5.1` heading in `CHANGELOG.md`, **not**
under `[Unreleased]`, and leave `app_store` at `5.0` in `Docs/SHIPPED_VERSION.json` until iOS ships
past it.
