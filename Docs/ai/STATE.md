# Current State

Updated: 2026-09-24 (documentation overhaul in progress on a branch; 5.4 still in review with build 478)
Branch/worktree: `claude/feature-knowledge-graph-fhu4mc` (cloud session), branched from `main` at d5cc916
Last verified commit: d5cc916

## Objective

Finish the documentation overhaul the owner approved on 2026-09-24 (`PROCEED: IMPLEMENT`): cut what
agents load at the start of every task, and correct documents that disagree with the code, without
touching app source, build inputs or store copy. It lives on the branch above and reaches `main`
only when the owner merges it. Roadmap row (Future Backlog, In Progress):
https://app.notion.com/p/3e549a74d54f815087d7db62848adb40

5.4 is with Apple and needs nothing until review returns (section "5.4 release" below).

## Status: documentation overhaul

- **Pass 1 (agent instruction layer): done.**
  - Every task reads 3 documents instead of 8 (22,981 bytes, down from 131,868): `Docs/ai/STATE.md`,
    the superseding protocol and `Docs/ai/ARCHITECTURE.md`. Everything else loads on demand, by section.
  - `AGENTS.md` rule 15 is that rule's one home, and `repoos_router.py` `UNIVERSAL_DOCS` executes it.
  - `CHANGELOG.md` went from 651 KB to 99 KB. Versions 2.0–5.2 moved verbatim to
    `Docs/Archive/CHANGELOG_2.0_to_5.2.md`.
  - `HANDOFF.md` is a 3 KB reading order. `.agents/AGENTS.md` and `.geminirules` are pointers.
- **Checker and hooks: done.**
  - `scripts/verify_doc_claims.py` now also checks `Type.member` names, route-table paths and the
    instruction files, and skips gitignored machine-local paths.
  - The pre-commit gate runs it with `-f`, not `-x`.
  - `mktemp` is portable in 3 hooks/scripts and 1 test.
- **Pass 2 (reference docs): pending.** A review workflow in this session proposes code-verified
  edits. Drift already verified by reading code:
  - **`Docs/ai/ARCHITECTURE.md`:**
    - The model-routing row points at `Services/AIPlatform/`. The decision is
      `ModelExecutionPlanner.makePlan` in `Services/RAG/Orchestration/`; `AIPlatform` enforces the route.
    - Fusion is `RAGEngine.reciprocalRankFusion` (`Services/RAG/Orchestration/RAGEngine.swift`), not
      in `Retrieval/`.
    - `HybridSearchService` does not rerank: `RAGService` calls `RAGEngine.rerank` after it returns.
    - A missing reranker model runs a heuristic fallback (`RAGEngine.swift` ~340-400), not "fusion
      order". `Docs/RETRIEVAL_PIPELINE.md` item 21 says the same wrong thing.
  - **The Atlas, ~line 381,** cites `RAGService.importDocument`, which does not exist. This is the
    only failure `verify_doc_claims.py` reports.
  - **Stale citations:**
    - `Docs/INGESTION_PIPELINE.md:5` and `Docs/RETRIEVAL_PIPELINE.md:15` cite `Docs/AUDIT/` (not in
      the repo) and `CHANGELOG.md` 4.8–4.9 (now archived).
    - `INGESTION_PIPELINE.md` ~200 anchors `CHANGELOG.md:162`, now `Docs/Archive/CHANGELOG_2.0_to_5.2.md:48`.
  - **Also to add:**
    - In `INGESTION_PIPELINE.md`, after "...nothing in the log said which stage owned the time.":
      page render is 12–16 ms a page at 360 DPI, so OCR time is Vision recognition (source:
      `Docs/EdgeToEdge/02_File_extraction_and_document_understanding.md:15`).
    - A "read by section" line at the top of the Atlas and `INGESTION_PIPELINE.md`.
- **Pass 3 (every other doc): pending.** Historical banners and dead-reference fixes only:
  `Docs/AuditArtifacts`, `EdgeToEdge`, `Research`, `Engineering`, `Release`, `Archive`, `.agent`,
  `Docs/AgentPlaybooks`.
- **Off limits under the approval:**
  - App source.
  - The top heading and 5.4 section of `CHANGELOG.md`. One `[General]` line was added there, as the
    route requires.
  - User changelogs, `WHATS_NEW.md`, fastlane text, release notes, `Docs/SHIPPED_*.json`,
    `HOW_IT_WORKS.md`, benchmark fixtures.

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

- The instruction planes: `AGENTS.md` (rules 3, 4, 11-17), `CLAUDE.md`, `HANDOFF.md`, `GEMINI.md`,
  `.geminirules`, `.agents/**`.
- Routing:
  - `.codex/skills/route-openintelligence-work/` (`SKILL.md`, `repoos_router.py`,
    `test_repoos_router.py`).
  - `Docs/AuditArtifacts/RepoOS/change_impact_matrix.csv`.
  - `Docs/RepoOS/00_*.md`, `01_*.md`.
- Enforcement:
  - `scripts/verify_doc_claims.py` and `scripts/test_verify_doc_claims.sh`.
  - `scripts/enforce_docs_hook.sh`, `scripts/instructions_report.sh` and `scripts/test_enforce_docs_hook.sh`.
  - `.claude/hooks/instructions-loaded.sh`, `.claude/hooks/notion-receipt.sh`, `.claude/rules/repo-governance.md`.
- `CHANGELOG.md`, `Docs/Archive/` (3 new files and the README), `Docs/ai/*`.
- Next: `Docs/ai/ARCHITECTURE.md`, the Atlas, `Docs/RETRIEVAL_PIPELINE.md`,
  `Docs/INGESTION_PIPELINE.md`, `Docs/PRIVACY_AND_ROUTING.md`, the canonical doc.

## Verification

2026-09-24, Linux cloud container, output read:
- `python3 .codex/skills/route-openintelligence-work/scripts/test_repoos_router.py` -> 31 tests, OK.
- `bash scripts/test_verify_doc_claims.sh` -> all 7 break cases caught. The baseline case fails on the
  pass-2 drift.
- `python3 scripts/verify_doc_claims.py` -> 600 claims, 1 failure (Atlas:381).
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

On branch `claude/feature-knowledge-graph-fhu4mc`, correct `Docs/ai/ARCHITECTURE.md` for the
routing, fusion and reranker items under "Status: documentation overhaul". Verify each against the
named Swift file first. Then fix the Atlas line citing `RAGService.importDocument` so that
`python3 scripts/verify_doc_claims.py` exits 0, and commit with explicit paths.
