# Current State

Updated: 2026-09-26 (RAG architecture audit saved and filed on the roadmap; development still paused after 5.4)
Branch/worktree: `claude/determined-ritchie-7y60am`, a cloud-session branch based on `main` at `b37ab4c`; not merged into `main`
Last verified commit: b37ab4c

## Objective

No build work is active. 5.4 shipped on both platforms on 2026-09-24, and the owner paused development
after it (`Docs/ai/DECISIONS.md`, 2026-09-24). What is open is the owner's call on the 2026-09-26 RAG
architecture audit: when to schedule its roadmap rows, and whether to approve the proposed extractor
fix with `PROCEED: IMPLEMENT`. The next version is 5.5, the owner's pick.

## Status

- **5.4 is live on iOS and macOS**, build 478 from `c276b9a`. `Docs/SHIPPED_VERSION.json` has
  `app_store` 5.4 on both platforms. No version is open in `CHANGELOG.md`. The full release, GitHub and
  website close-out record is the previous copy of this file: `git show 696680c:Docs/ai/STATE.md`.
- **Scheduled:** 2026-09-30 09:00 PT, task `openintelligence-end-lifetime-sale`, which takes the sale
  line off the listing and the three sites. It is still needed.
- **RAG architecture audit, 2026-09-26.** Everything is in
  `Docs/AuditArtifacts/RAGArchitectureAudit_2026-09-26/`; start with its `README.md`.
  - **Trigger.** On 2026-09-25, on the macOS Debug build of 5.4 in Deep Think, "How much notice do I
    have to give before I move out?" returned "1 lb." from an air fryer manual, marked Verified.
  - **Verdict** (`REPORT.md`). The proposed ~10-line extractor fix is correct but a band-aid: it
    changes 2 of the 11 decisions behind that answer. The pipeline's overall design is standard. The
    structural problems are:
    - regex extraction can pre-empt or overwrite the model's answer at five places;
    - verification never checks the answer, and never runs in Deep Think or Maximum;
    - the Verified label defaults to Verified;
    - ranking and storage plumbing discard or damage the pipeline's own work.
  - `REPORT.md` ranks ten changes and maps each to roadmap rows.
- **Roadmap, filed 2026-09-26.** All new rows are To Do, Future Backlog:
  - the "1 lb" incident and its proposed fix: https://app.notion.com/p/3e749a74d54f8115a76ad5b06b196956
  - regex extraction in the answer seat: https://app.notion.com/p/3e749a74d54f817083a6fbf197ff26db
  - the Verified badge on failed or unrun checks: https://app.notion.com/p/3e749a74d54f81b1ae8bc414159799ed
  - the semantic query cache is never cleared: https://app.notion.com/p/3e749a74d54f810c86fefac905fa1d6f
  - the vector index is deleted on a size mismatch: https://app.notion.com/p/3e749a74d54f81859f4dd44bc4c9e9b2
  - the splitter stores "4.5 L" as "4. 5 L": https://app.notion.com/p/3e749a74d54f8198b727fa124d5db474
  - Dated notes were added to the fusion, Evaluations and embedder rows (listed in the audit `README.md`).
  - Three rows (incident, answer seat, badge) state the case for release test 2, citing
    `fastlane/metadata/en-US/description.txt:23` and `:25`. The owner decides.

## Documentation overhaul (merged into `main` 2026-09-25), still open

- Roadmap row https://app.notion.com/p/3e549a74d54f815087d7db62848adb40 (Future Backlog, In Progress)
  closes when `/context` in a fresh Claude Code session on the Mac shows the lighter startup load.
- **Leads, not findings,** in `Docs/AuditArtifacts/DocOverhaul_2026-09-24/`: 100 unverified doc edits
  and 60 suspected code defects. Check first whether Evidence Threads sync copies anything:
  - the store writes `<AppSupport>/EvidenceThreads/` (`EvidenceThreadStore.swift:60`);
  - sync reads `<AppSupport>/OpenIntelligence/EvidenceThreads/` (`WorkspaceSyncService.swift:2739`);
  - roadmap row: https://app.notion.com/p/3e649a74d54f811492b6d0d8f5e89f71.
- The overhaul's two `[General]` changelog entries wait in that directory's `README.md`, to go under 5.5.
- Owner decisions carried: whether to rename Lifetime (needs a new IAP version), and `.build` (841 MB)
  and `build/` (444 MB) at the root lack `.nosync`.

## Active Constraints

- **No version is open in `CHANGELOG.md`.** Before any app-change push, open
  `## 5.5 <!-- unreleased -->` above `## 5.4` with `<!-- next-version: 5.5 -->`, and create the 5.5
  records in App Store Connect. Otherwise `ci_post_clone.sh` stamps 5.4 and App Store Connect rejects
  the upload.
  - Pushes of documentation only do not start a build. Xcode Cloud's filter covers only `*.md`,
    `Docs/`, `.claude/`, `.agents/`, `.codex/`, `fastlane/metadata/` and `.github/`.
  - A push that also touches `scripts/` does start a build. Put `[ci skip]` in that commit message.
- App Store Connect writes happen only at the owner's word.
- Guard memory on builds (18 GB Mac): `-jobs 2`, stop at 15% free, and build from `/private/tmp/oi-src`.
- swift-format rewrites Swift files edited with Edit/Write.
- Commits: commit to `main`, with no branches or pull requests unless the owner asks, and no AI
  trailer. Exception: the 2026-09-26 audit commit is on `claude/determined-ritchie-7y60am` because the
  cloud session was set to push there. Merging it into `main` is the owner's call.

## Working Set

| Path | Why it matters |
|---|---|
| `Docs/AuditArtifacts/RAGArchitectureAudit_2026-09-26/README.md` | Entry point: rows filed, open items |
| `Docs/AuditArtifacts/RAGArchitectureAudit_2026-09-26/REPORT.md` | The report, with the ranked changes table |
| `Docs/AuditArtifacts/RAGArchitectureAudit_2026-09-26/proposed/extractor-fix.patch` | The fix plus four regression tests; not applied |
| `OpenIntelligence/Services/Query/Analysis/SpecificationExtractor.swift` | What the patch changes: the "much/many" expansion at `:1482-1484` and the unit match at `:583-615` |
| `OpenIntelligenceTests/Services/RAG/Tuning/` | Where the patch creates the new test class `PrecisionLockAnswerTypeTests`, which does not exist yet |
| `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift` | Precision lookup at `:8578`. Override sites at `:8705`, `:8734`, `:9199`, `:14383` and `:15192` |
| `.claude/skills/apple-api-truth/SKILL.md` | Its `ContextOptions` fact needs re-checking (Blockers) |
| Release records | `Docs/SHIPPED_VERSION.json`, `CHANGELOG.md`, `Docs/USER_CHANGELOG.md`, `OpenIntelligence/Resources/VersionHistory.md` |

## Verification (2026-09-26, output read)

These ran in a Linux cloud container with no Swift toolchain. Nothing was compiled, built or run on a
device.
- `git diff --stat c276b9a b37ab4c -- '*.swift'` -> only `scripts/screenshots/winid.swift` and
  `winlist.swift` changed, so the app source at `b37ab4c` is the shipped 5.4 source.
- `git apply --check --verbose Docs/AuditArtifacts/RAGArchitectureAudit_2026-09-26/proposed/extractor-fix.patch`
  -> both files check clean at `b37ab4c`.
- In that folder's `port/`, `PYTHONHASHSEED=0 python3 validate_proposed_test.py` -> the Python port of
  the extractor predicts 3 of the 4 proposed tests fail on today's code and all 4 pass with the patch.
  This is a prediction from the port, not a Swift run.
- `python3 scripts/secret_scan.py` -> no sensitive tokens.
- `python3 scripts/verify_doc_claims.py`, run after this file was written -> 722 claims checked, all
  match the source.
- `python3 .codex/skills/route-openintelligence-work/scripts/test_repoos_router.py` -> 31 tests OK.
- Earlier checks of the 5.4 release are recorded in `git show 696680c:Docs/ai/STATE.md` and were not
  re-run: App Store Connect states, the three sites, and the 500-test suite on 2026-09-23.

## Blockers / Unknowns

- **Six `v5.4` rows close on the owner's device check**, and nothing can verify that from here:
  - answers finish when the last word appears: https://app.notion.com/p/3e449a74d54f818197d4c6e45f8d2142
  - haptic, badge and clock for an answer that finishes off screen: https://app.notion.com/p/3e449a74d54f8193964bdda0f50d16c3
  - Deep Think and Maximum stream: https://app.notion.com/p/3e449a74d54f813787a6cf91ef814767
  - the free plan's Maximum cap is enforced: https://app.notion.com/p/3e349a74d54f81b49205d1a75f2a4b99
  - the plans screen after setup does not crash: https://app.notion.com/p/3e449a74d54f81afb55fc318f81244f9
  - 5.4's What's New shows to updaters: https://app.notion.com/p/3e149a74d54f819aba78e2b85f0e9942

  When the owner confirms they work, set each row to `Completed` with `date:Completed:start`
  2026-09-24 or later.
- **The extractor patch has never been compiled.** To verify it on the Mac:
  1. Apply only the test file:
     `git apply --include='OpenIntelligenceTests/*' Docs/AuditArtifacts/RAGArchitectureAudit_2026-09-26/proposed/extractor-fix.patch`.
  2. Run the `Docs/ai/RUNBOOK.md` `## Test` invocation with
     `-only-testing:OpenIntelligenceTests/PrecisionLockAnswerTypeTests`. Expect 3 failures and 1 pass.
  3. Apply the rest of the patch and run the same command again. Expect 4 passes.
  4. Re-ask the incident question on a device in Deep Think. In Standard, use a fresh phrasing: an
     exact semantic-cache hit replays old retrieval (`RAGService.swift:9832-9850`).
- **The `ContextOptions` row in `.claude/skills/apple-api-truth/SKILL.md` may be wrong as worded.** It
  says `ContextOptions` is a defaulted argument on every `respond`/`streamResponse` overload. Apple's
  documentation, fetched 2026-09-26, shows it only on the 12 new iOS 27 overloads. Before editing the
  table, grep `contextOptions` in the iOS 27 SDK's `FoundationModels.swiftinterface` (path pattern in
  that skill) and count the overloads.
- The three subscription descriptions in App Store Connect are still wrong ("unlimited documents and
  5 libraries" for Pro, "10 Libraries" for Lifetime). The API refuses them (409, ACTIVE), so the fix is
  the owner's web-page edit.
- Cleanup, test data only: `/private/tmp/oi-ui-appsupport-2026-09-23`; `/private/tmp/oi-bench/`; three
  shut-down simulators (`6CD2218C-EA61-46B3-B31E-0667FBCDF2B6`, `57E0CE08-EA1A-4D02-9D74-FEBD238709ED`,
  `F798E00A-9F48-44B8-A087-45413A96783A`); and, in the owner's iCloud Documents,
  `~/Documents/SampleDocuments` and `~/Documents/SampleDocuments.evicted-2026-09-23`, which hold sample
  copies only.

## Exact Next Action

None until the owner decides on the audit. If the reply is `PROCEED: IMPLEMENT` for the extractor
patch, start on the Mac with step 1 of "The extractor patch has never been compiled" under Blockers.
Before any push to `main`, open 5.5 as Active Constraints describes.
