# Current State

Updated: 2026-09-26 (the approved "1 lb" extractor fix is committed on the session branch and verified as Swift 6.4 on Linux; 5.5 is open there; nothing is built in Xcode yet)
Branch/worktree: `claude/determined-ritchie-7y60am`, a cloud-session branch from `main` at `b37ab4c` carrying the audit (`cd11c4f`), the fix (`9478d59`), the test layout (`62c9e35`) and handoffs; not merged into `main`
Last verified commit: 6651d08

## Objective

Take the extractor fix from "verified on Linux" to closed:

1. Build and test it in Xcode on the Mac.
2. Re-ask the incident question on a device.
3. Merge the branch into `main`, which also opens 5.5 there. Merging is the owner's call.

5.4 shipped on both platforms on 2026-09-24 and development paused after it (`Docs/ai/DECISIONS.md`).
On 2026-09-26 the owner approved this one fix with `PROCEED: IMPLEMENT`. Anything else in 5.5 is the
owner's call.

## Status

- **5.4 is live on iOS and macOS**, build 478 from `c276b9a`, and `Docs/SHIPPED_VERSION.json` agrees.
  The release record is `git show 696680c:Docs/ai/STATE.md`.
- **Scheduled:** 2026-09-30 09:00 PT, task `openintelligence-end-lifetime-sale`. It is still needed.
- **The fix.** On 2026-09-25, Deep Think answered "How much notice do I have to give before I move
  out?" with "1 lb." from an air fryer manual, marked Verified.
  In `SpecificationExtractor`, "much" and "many" add the volume words only when the question names a
  measurement anchor (`:1502`); the liquid-unit test compares the unit exactly (`:587`, `:625`); the
  keyword log keeps the question's order (`:1526`). Four tests in `PrecisionLockAnswerTypeTests`.
  Recorded in `CHANGELOG.md` `## 5.5` and item 22 of `Docs/RETRIEVAL_PIPELINE.md`.
- **Linux harness** (`Docs/AuditArtifacts/RAGArchitectureAudit_2026-09-26/swift/`): 3 of the 4 tests
  fail before the fix and 4 of 4 pass after it. An 18-question probe: three wrong locks removed, one
  right lock gained ("4.5L" without a space), one right lock lost ("How much water does the reservoir
  take?" now goes to the model).
- **Found, not fixed.** When volumes in one passage tie, the extractor keeps the first
  (`SpecificationExtractor.swift:300-305`). On a car manual's capacities list, the fuel-tank and
  coolant questions lock the engine oil's figure, before and after the fix. It is noted on the
  answer-seat row.
- **Docs corrected in the same commit.** `Docs/HOW_IT_WORKS.md` step 5.10, `Docs/STUDY_GUIDE.md` and
  `Docs/Engineering/RAG_TECHNICAL.md` said extraction was off and every question reaches the model.
  In fact `RAGService.highPrecisionLookupOverrideAnswer` has five live call sites (`:8705`, `:8734`,
  `:9199`, `:14383`, `:15192`). Each doc is corrected in place, with the withdrawn wording quoted.
- **Roadmap, 2026-09-26:**
  - The incident row https://app.notion.com/p/3e749a74d54f8115a76ad5b06b196956 is `In Progress`,
    `v5.5`. It moved under test 2 when the owner approved the fix. To reverse it, set Future Backlog
    and leave the branch unmerged.
  - The answer-seat row https://app.notion.com/p/3e749a74d54f817083a6fbf197ff26db has a dated note on
    the tie and the doc corrections.
  - The other audit rows are unchanged (To Do, Future Backlog), listed in the audit `README.md`.

## Documentation overhaul (merged into `main` 2026-09-25), still open

- Row https://app.notion.com/p/3e549a74d54f815087d7db62848adb40 (Future Backlog, In Progress) closes
  when `/context` in a fresh Claude Code session on the Mac shows the lighter startup load.
- **Leads, not findings,** in `Docs/AuditArtifacts/DocOverhaul_2026-09-24/`: 100 unverified doc edits
  and 60 suspected code defects. First check whether Evidence Threads sync copies anything: the store
  writes `<AppSupport>/EvidenceThreads/` (`EvidenceThreadStore.swift:60`), sync reads
  `<AppSupport>/OpenIntelligence/EvidenceThreads/` (`WorkspaceSyncService.swift:2739`); row
  https://app.notion.com/p/3e649a74d54f811492b6d0d8f5e89f71.
- Its two `[General]` changelog entries are filed under `## 5.5` on this branch and reach `main` with it.
- Owner decisions carried: renaming Lifetime (needs a new IAP version); `.build` (841 MB) and `build/`
  (444 MB) at the root lack `.nosync`.

## Active Constraints

- **5.5 is open only on this branch.** `main` still has no version open.
  - An app-source push to `main` before this merge must first open `## 5.5 <!-- unreleased -->` with
    `<!-- next-version: 5.5 -->`. Otherwise `ci_post_clone.sh` stamps 5.4 and App Store Connect
    rejects the build. Merging this branch does both.
  - The 5.5 records in App Store Connect are not created. Create them before the first 5.5 build.
- **Xcode Cloud.** It skips pushes that touch only `*.md`, `Docs/`, `.claude/`, `.agents/`, `.codex/`,
  `fastlane/metadata/` and `.github/`. App source or `scripts/` starts a build, so every branch
  commit carries `[ci skip]`.
- App Store Connect writes happen only at the owner's word.
- Guard memory on builds (18 GB Mac): `-jobs 2`, stop at 15% free, build from `/private/tmp/oi-src`.
- **swift-format rewrites Swift files edited with Edit/Write on the Mac.** `SpecificationExtractor.swift`
  has 96 lint warnings, all older than the fix (99 before it), so its next edit may bring a whitespace
  diff that is not the fix. The new test file is clean.
- **Commits** go to `main`, with no branches or pull requests unless the owner asks, and no AI trailer.
  This session's commits are on the branch because the cloud session pushes there. The branch
  fast-forwards onto `main` at `b37ab4c`.

## Working Set

| Path | Why it matters |
|---|---|
| `Docs/AuditArtifacts/RAGArchitectureAudit_2026-09-26/README.md` | Entry point: rows, the fix's state, open items |
| `Docs/AuditArtifacts/RAGArchitectureAudit_2026-09-26/swift/run.sh` | Rebuilds the extractor from source with Swift 6.4 on PATH: `run.sh before b37ab4c`, `run.sh after` |
| `OpenIntelligence/Services/Query/Analysis/SpecificationExtractor.swift` | The fix at `:587`, `:625`, `:1502`, `:1526`; the unfixed tie at `:300-305` |
| `OpenIntelligenceTests/Services/RAG/Tuning/PrecisionLockAnswerTypeTests.swift` | The four regression tests, `@MainActor`, importing `OpenIntelligenceEngine` |
| `CHANGELOG.md`, `Docs/RETRIEVAL_PIPELINE.md` | `## 5.5 <!-- unreleased -->`; item 22 |
| `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift` | The five lock call sites; the source-only decline at `:17293` |
| `.claude/skills/apple-api-truth/SKILL.md` | Its `ContextOptions` fact needs re-checking (Blockers) |

## Verification (2026-09-26, output read)

These ran in a Linux cloud container with no Xcode.

- **The toolchain.** Swift 6.4 (`swift-6.4-RELEASE`), the toolchain layer of the official
  `swift:6.4-noble` image, fetched from `mirror.gcr.io` and checked against its sha256 digest. It lived
  in the session scratchpad and goes with the container.
- `run.sh before b37ab4c` -> 3 of 4 fail ("1 lb" 0.85, "5.8 qt" 0.88, "3,200 lb" 0.88).
  `run.sh after` -> 4 of 4 pass. Both repeat byte for byte, with no build diagnostics beyond two old
  `LoggingConfiguration.swift` warnings.
- `swift-format lint` on the test file -> 20 warnings, 0 after `swift-format format`; results unchanged.
- `python3 scripts/verify_doc_claims.py` -> 727 claims, all match.
- `python3 scripts/secret_scan.py` -> clean. `test_repoos_router.py` -> 31 OK.
- `bash scripts/enforce_docs_hook.sh` -> passes on the staged set, and fails naming
  `Docs/RETRIEVAL_PIPELINE.md` when it is unstaged.
- The preflight reports `v5.5` in development. Both Notion rows read back.

## Blockers / Unknowns

- **Xcode verification** is the next action. Nothing was built by Xcode or run on a simulator.
- **The device check**, which with the tests closes the incident row: re-ask the incident question in
  Deep Think over the same 10-document library and expect no "Direct Source Extraction" answer. In
  Standard use a fresh phrasing, since an exact semantic-cache hit replays old retrieval
  (`RAGService.swift:9832-9850`).
- **Six `v5.4` rows close on the owner's device check**; set each `Completed`, dated 2026-09-24 or
  later: [answers finish at the last word](https://app.notion.com/p/3e449a74d54f818197d4c6e45f8d2142),
  [off-screen finish signals](https://app.notion.com/p/3e449a74d54f8193964bdda0f50d16c3),
  [agentic streaming](https://app.notion.com/p/3e449a74d54f813787a6cf91ef814767),
  [free Maximum cap](https://app.notion.com/p/3e349a74d54f81b49205d1a75f2a4b99),
  [plans screen after setup](https://app.notion.com/p/3e449a74d54f81afb55fc318f81244f9),
  [5.4 What's New](https://app.notion.com/p/3e149a74d54f819aba78e2b85f0e9942).
- **Owner decisions:** whether the answer-seat and Verified-label rows join 5.5 (both state test 2),
  and whether to widen the anchor list (for example "water"), which needs a golden set to judge.
- **`ContextOptions` in `.claude/skills/apple-api-truth/SKILL.md` may be wrong as worded.** Count
  `contextOptions` overloads in the iOS 27 SDK's `FoundationModels.swiftinterface` (the path pattern is
  in that skill) before editing.
- **Three subscription descriptions in App Store Connect are wrong.** The API refuses them (409), so
  they need the owner's web edit.
- **Cleanup, test data only:** `/private/tmp/oi-ui-appsupport-2026-09-23`, `/private/tmp/oi-bench/`,
  simulators `6CD2218C-EA61-46B3-B31E-0667FBCDF2B6`, `57E0CE08-EA1A-4D02-9D74-FEBD238709ED` and
  `F798E00A-9F48-44B8-A087-45413A96783A`, and in iCloud Documents `~/Documents/SampleDocuments` and
  `~/Documents/SampleDocuments.evicted-2026-09-23`.

## Exact Next Action

On the Mac, at `claude/determined-ritchie-7y60am` `62c9e35` or later:

1. Take an iOS 27 simulator UDID from `xcrun simctl list devices available`.
2. Run the `Docs/ai/RUNBOOK.md` `## Test` invocation with
   `-only-testing:OpenIntelligenceTests/PrecisionLockAnswerTypeTests`,
   `-only-testing:OpenIntelligenceTests/HybridSearchServiceTests` and
   `-only-testing:OpenIntelligenceTests/ContextPackingServiceTests`.
3. Run `bash scripts/build_simulator_smoke.sh`.

Expect everything to pass, with 4 of 4 in the new class. Record the result here and on the incident
row, then ask the owner about the device check and the merge.
