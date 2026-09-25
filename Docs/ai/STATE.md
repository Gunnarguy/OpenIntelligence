# Current State

Updated: 2026-09-25 (documentation overhaul done on a branch, awaiting the owner's merge; 5.4 still in review with build 478)
Branch/worktree: `claude/feature-knowledge-graph-fhu4mc` (cloud session), branched from `main` at d5cc916
Last verified commit: d5cc916

## Objective

The documentation overhaul the owner approved on 2026-09-24 (`PROCEED: IMPLEMENT`) is done on the
branch above and waits for the owner to merge it. It cut what agents load at the start of every
task and corrected documents that disagree with the code, without touching app source, build inputs
or store copy. Roadmap row (Future Backlog, In Progress):
https://app.notion.com/p/3e549a74d54f815087d7db62848adb40

5.4 is with Apple and needs nothing until review returns (section "5.4 release" below).

## Status: documentation overhaul

- **Done on the branch, committed:**
  - Every task reads 3 documents instead of 8 (22,981 bytes, down from 131,868). `AGENTS.md` rule 15 is
    the rule's one home, and `repoos_router.py` `UNIVERSAL_DOCS` executes it.
  - `CHANGELOG.md` went from 651 KB to 99 KB. Versions 2.0–5.2 moved verbatim to
    `Docs/Archive/CHANGELOG_2.0_to_5.2.md`.
  - `HANDOFF.md` is a 3 KB reading order. `.agents/AGENTS.md` and `.geminirules` are pointers.
  - `verify_doc_claims.py` checks symbols, route paths and instruction files. It runs on fresh clones
    and exits 0.
  - Hooks and tests use a portable `mktemp`.
- **Reference docs, 50 edits applied:**
  - Every edit to `Docs/ai/ARCHITECTURE.md` was checked by a second agent. That includes the corrected
    routing, fusion and reranker rows and a new product-vocabulary section.
  - From the rest, only low-risk kinds: version headers now point at `Docs/SHIPPED_VERSION.json`, plus
    `Docs/AUDIT/` pointers, dead paths and a historical banner on the Transition Plan.
  - Also the corrections confirmed another way: the Evidence Threads sync note, prefer-cloud, the
    Atlas `importDocument` history, and the reranker fallback.
- **Not applied:**
  - The review was stopped early to limit cost. 100 edit proposals nobody checked a second time are in
    `Docs/AuditArtifacts/DocOverhaul_2026-09-24/unverified_edit_proposals.json`.
  - 60 suspected code defects (leads, not findings) are listed in that directory's `README.md`.
  - The planned historical-banner pass over old audit docs was skipped. Agents do not load those docs
    by default.

## 5.4 release (with Apple; nothing to do until review returns)

- **In review, both platforms, build 478** (Xcode Cloud #478 from `c276b9a`), release MANUAL,
  submitted 2026-09-23 22:03 PT.
  - Submissions: iOS `0f601c16-8a6b-4d13-937d-c5a71803f6ce`, macOS `5a21fe94-a866-4c37-a412-a44f385f1b68`.
  - 474-477 are superseded. **Never submit 469.**
- **User-facing copy is function and performance only, in the owner's voice.** Plans, paywall,
  ratings and the Maximum cap stay in `CHANGELOG.md` `## 5.4` only.
- **Three subscription descriptions are wrong, and the API refuses the edit (409), so use the web page.**
  - Pro Annual: "Annual billing for 1,000 documents and 10 libraries."
  - Pro Monthly: "Monthly billing for 1,000 documents and 10 libraries."
  - Lifetime: "Permanent Pro - 20 Libraries + Unlimited Documents".
  - Submit both Pro subscriptions with the next version.
- **On approval** (`PENDING_DEVELOPER_RELEASE`), release only when the owner says. Then:
  1. Date `## v5.4 - unreleased` in `Docs/USER_CHANGELOG.md` and copy it byte-for-byte to
     `OpenIntelligence/Resources/VersionHistory.md`.
  2. Remove `<!-- unreleased -->` from `## 5.4` in `CHANGELOG.md`, then open the next version above it.
  3. In `Docs/SHIPPED_VERSION.json`, set `app_store` to 5.4 and clear `in_review`. Push.
- **Then the GitHub draft `v5.4.0` (at `c276b9a`, tag on origin), only when the owner says:**
  - Change its first line from "in App Review" to live with the date
    (`gh release view v5.4.0 -R Gunnarguy/OpenIntelligence --json body -q .body`).
  - Run `gh release edit v5.4.0 -R Gunnarguy/OpenIntelligence --notes-file <file> --draft=false --latest`.
  - A build other than 478 means the tag moves first, and that is the owner's call.
- **On a rejection,** fix what the resolution center names. The three v5.4 Notion rows close after
  the owner's device check.
- **Scheduled 2026-09-30 09:00 PT:** task `openintelligence-end-lifetime-sale`. It runs
  `scripts/asc_end_sale.rb` and strips the sale line from three websites. It runs only while the
  desktop app is open, otherwise at next launch. The in-app banner silences itself.

## Active Constraints

- **No new version heading while 5.4 is unsubmitted** (`Docs/ai/DECISIONS.md`, 2026-09-23). Xcode
  Cloud stamps builds from the first numbered heading in `CHANGELOG.md`.
- A local build calls itself 5.3 (150) unless built with `MARKETING_VERSION=5.4`.
- **Guard memory on builds** (18 GB Mac): `-jobs 2`, stop at 15% free.
  - Build from `/private/tmp/oi-src`, synced with rsync.
  - Exclude `BenchmarkRuns/`, `.simulator-smoke.nosync/`, `Benchmarks/run/`, `.build` anywhere,
    `/.device-smoke.nosync/` and `/build/`.
- The iOS simulator does not generate. Timing and streaming run on the unsigned macOS Debug build.
- Disk 96% on 2026-09-23. At 96% (2026-08-20) model assets were evicted.
- App Store Connect writes are the owner's. swift-format rewrites Swift files edited with Edit/Write.
- **Commit to `main`, no branches or pull requests unless the owner asks, no AI co-author trailer.**
  This is the owner's rule, carried over from `HANDOFF.md`. This overhaul is on a branch only
  because the cloud session requires one.

## Working Set (overhaul)

- The branch diff against `main` (`git diff main...claude/feature-knowledge-graph-fhu4mc --stat`) is the
  full list. All of it is documentation, agent instructions, `.codex/`/`.claude/` tooling, `scripts/`
  checks and `Docs/AuditArtifacts/`.
- `Docs/AuditArtifacts/DocOverhaul_2026-09-24/` holds the unapplied proposals and the defect leads.

## Verification

2026-09-24, Linux cloud container, output read:
- `python3 .codex/skills/route-openintelligence-work/scripts/test_repoos_router.py` -> 31 tests, OK (re-run 2026-09-25).
- `bash scripts/test_verify_doc_claims.sh` -> 8 passed, 0 failed, baseline included (2026-09-25).
- `python3 scripts/verify_doc_claims.py` -> 717 claims, every one matches, exit 0 (2026-09-25).
- `bash scripts/test_enforce_docs_hook.sh` -> 18 passed. It could not run on Linux before the `mktemp` fix.
- `bash scripts/test_stop_handoff.sh` -> 11 passed. It was 10 passed, 1 failed on `mktemp -t`.
- `python3 scripts/secret_scan.py` -> clean.
- Preflight after the `CHANGELOG.md` move -> `v5.4`, `## 5.4`, unchanged. Archive compared with
  `git show HEAD:CHANGELOG.md` -> 0 mismatched lines.

**Not run:** `build_simulator_smoke.sh` (no Xcode here) and `quick_validate.py` (Mac path). No app
source changed.

2026-09-23: full iOS suite on `b176da2` -> 500 tests, 0 failures. App Store Connect at 22:04 PT ->
both records `WAITING_FOR_REVIEW`, build 478 `VALID`. **Nothing verified on a device.**

## Blockers / Unknowns

- **Evidence Threads sync may copy nothing.** Code-read only, not observed.
  - The store writes `<AppSupport>/EvidenceThreads/<container>/` (`EvidenceThreadStore.swift:60`).
  - Sync reads `localRoot/EvidenceThreads/` with localRoot `<AppSupport>/OpenIntelligence`
    (`WorkspaceSyncService.swift:2739`, `OpenIntelligenceRuntimePaths.swift:105-111`).
  - Verify on a Pro build with library sync on: create a thread and look for its JSON under the
    library's iCloud root.
  - If real, it may pass release test 2. `WorkspaceSyncService.swift` is a hard-boundary file. A
    suggested task is queued in the desktop app.
- **Possible PCC in Standard** (inferred). `ModelExecutionPlanner.makePlan`'s branch for questions
  too large for the on-device model reportedly has no quality-mode check, while the setting reads
  "Allow for Deep Think and Maximum". Verify by reading `makePlan`.
- **Owner decisions:**
  - When may a new version heading open? `DECISIONS.md` ~757-759 says after submission; this file
    and `CHANGELOG.md` say after release.
  - Rename Lifetime? That needs a new IAP version.
  - `.build` (841 MB) and `build/` (444 MB) at the root lack `.nosync`.
  - Whether to narrow `AGENTS.md` rule 14's seven-document list, now the largest per-task doc cost.
- **Router gaps, not fixed:**
  - No route owns answer orchestration (`AgenticOrchestrator.swift`, `Services/Evaluation`).
  - Product terms (Deep Think, Maximum, Glossary, HUD, library deletion) route to nothing.
- **Test data to clean up:**
  - `/private/tmp/oi-ui-appsupport-2026-09-23` and `/private/tmp/oi-bench/`.
  - Simulators `6CD2218C-EA61-46B3-B31E-0667FBCDF2B6`, `57E0CE08-EA1A-4D02-9D74-FEBD238709ED` and
    `F798E00A-9F48-44B8-A087-45413A96783A`.
  - `~/Documents/SampleDocuments` and `~/Documents/SampleDocuments.evicted-2026-09-23`.

## Exact Next Action

The owner reviews and merges branch `claude/feature-knowledge-graph-fhu4mc` into `main`. It changes
only docs and agent tooling; a docs-only push to `main` starts no Xcode Cloud build. Then, in a fresh
Claude Code session on the Mac, run `/context` to confirm the lighter startup load, and close the
roadmap row above.
