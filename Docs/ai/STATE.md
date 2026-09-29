# Current State

Updated: 2026-09-29, 10:00 PT (repository cleanup done and committed locally; not pushed)
Branch/worktree: `main`, primary checkout
Last verified commit: 8be003a

## Objective

5.5 is the open release: one app change (the "how much" extractor fix), staged in App Store Connect on
both platforms with build 481, and nothing submitted. Submitting is the owner's call, and new work
starts only when he says to (`Docs/ai/DECISIONS.md`, 2026-09-24).

On 2026-09-29 he said to carry out the cleanup plan's recommendations as long as nothing fundamental
breaks. That is done and committed locally (Status). Pushing waits on his word: the repository is public.

## Status

- **Cleanup, done 2026-09-29, committed locally with `[ci skip]`.** Documentation and tooling only; no file
  Xcode compiles changed. The two 2026-09-29 `[General]` entries under `## 5.5` in `CHANGELOG.md` list it:
  - 27 files moved with `git mv` into `Docs/Archive/`; its README has a row for each and an old-to-new
    path table. Archived text is not edited to follow a move; the table resolves old citations.
  - `PRIVACY.md` and `Docs/ROADMAP.md` are pointers now, with their old bodies archived.
  - 14 scripts and one unreferenced screenshot deleted (all in git history), and
    the September conversion and reviews notes moved out of `Docs/Release/` to
    `~/ASC/CONVERSION_AND_REVIEWS_2026-09.md` after a byte-for-byte copy.
  - 86 documents edited: corrected against the code, repointed, or given dated banners, each correction
    citing its line. Three adversarial reviewers then made 34 findings; each was fixed or is recorded below.
  - Kept on purpose (reasons in `Docs/ai/DECISIONS.md`, 2026-09-29): the four June audits,
    `Docs/AppleIntelligenceTransitionPlan.md`, the engine SDK and `.agent/RISK_REGISTER.md`.
  - Local disk, outside git: 1.2 GB of old build products moved to the Trash, not emptied.
- **Roadmap rows filed 2026-09-29**, all Future Backlog, each with evidence and a closing condition:
  - https://app.notion.com/p/3ea49a74d54f81fd814ae82ce9449e41 (High): in Deep Think and Maximum a
    "Just Once" consent for Private Cloud Compute carries over to later questions. The only line that
    clears it, `RAGService.swift:9641`, runs after the agentic path returns at `:9544-9552`. The row says
    why it may belong in a release in progress; that is the owner's call.
  - https://app.notion.com/p/3ea49a74d54f8167a9b3d92c94539567: Settings lists 4 tool functions; 6 run.
  - https://app.notion.com/p/3ea49a74d54f8126a005f0a27a318498: iOS 26 Settings blames the build for PCC.
  - https://app.notion.com/p/3ea49a74d54f817ab4bcf5bb6ad07509: each mode's MMR lambda is never read.
  - https://app.notion.com/p/3ea49a74d54f81059b20e8bda0663798: sentence-opening words become entities.
  - Corrected in place: https://app.notion.com/p/38049a74d54f81dcae32fce70ba7751b (View Entity
    Annotations) is To Do, Future Backlog; the feature has no call sites.
- **5.5 in App Store Connect:** both records (iOS `d7b9bb32-0694-41fc-9692-75cc63cb4a7f`, macOS
  `73bc0eaa-c670-479c-941e-b75998ac0142`) are `PREPARE_FOR_SUBMISSION` with build 481, notes, promo,
  description and keywords (read back 2026-09-28 22:00 PT). The extractor row stays In Progress:
  https://app.notion.com/p/3e749a74d54f8115a76ad5b06b196956 (on 2026-09-26 Deep Think still answered
  "at least 30 days" where the lease says 60, marked Verified).
- **5.4 is live** on iOS and macOS, build 478, closed out on GitHub (`v5.4.0` Latest), the three websites
  and Notion.
- Scheduled: 2026-09-30 09:00 PT, task `openintelligence-end-lifetime-sale`. Still needed.

## Active Constraints

- **5.5 is open** (`## 5.5 <!-- unreleased -->`; `preparing` 5.5 in `Docs/SHIPPED_VERSION.json`). A push
  whose latest commit touches a path outside Xcode Cloud's filter builds 5.5 for TestFlight unless that
  commit says `[ci skip]` (`Docs/ai/RUNBOOK.md`, verified against Apple's documentation 2026-09-29). The
  filter skips only `*.md`, `Docs/`, `.claude/`, `.agents/`, `.codex/`, `fastlane/metadata/`, `.github/`.
- Pushing publishes to a public repository and to gunnarguy.me, which mirrors `README.md` and top-level
  `Docs/*.md` by glob; no page on the three sites links to a moved path (checked 2026-09-29). Ask before
  pushing. Keep the owner's personal plans out of public files.
- `CLAUDE.md` forbids deleting docs: removing one means `git mv` into `Docs/Archive/`.
- App Store Connect writes happen only at the owner's word. Guard memory on builds (18 GB Mac): `-jobs 2`,
  stop at 15% free, DerivedData outside `~/Documents`. Commit to `main`, explicit paths, no AI trailer.

## Working Set

- `Docs/Archive/README.md`: every archived file and the old-to-new path table.
- `Docs/README.md`: the documentation index, including what was kept and why.
- `Docs/ai/DECISIONS.md`: the 2026-09-29 entries (DEC-35 reversal, engine SDK, the cleanup's rules).
- `CHANGELOG.md` `## 5.5`: the two 2026-09-29 `[General]` entries.
- `PRIVACY.md`, `Docs/ROADMAP.md`: the two pointers.

## Verification (2026-09-29, output read)

- `python3 scripts/verify_doc_claims.py` -> 764 claims checked, all match (the old `STATE.md:186` failure
  is gone with the rewrite). `bash scripts/test_verify_doc_claims.sh` -> 8 passed, 0 failed.
- `bash scripts/test_enforce_docs_hook.sh` -> 18 passed, 0 failed. `bash scripts/test_stop_handoff.sh` ->
  11 passed, 0 failed. `python3 .codex/skills/route-openintelligence-work/scripts/test_repoos_router.py`
  -> 31 OK.
- `python3 .claude/codemap/codemap.py check` -> 46 slices, 0 errors, 0 warnings.
  `python3 .claude/skills/repo-map/scripts/test_build_map.py` -> 10 tests OK.
  `python3 scripts/secret_scan.py` -> no sensitive tokens.
- Scripts whose text changed still parse: `ruby -c` on `asc_winback_offers.rb` and `asc_certificates.rb`,
  `xcrun swiftc -parse scripts/screenshots/winlist.swift`, and `ast.parse` on the three Python files;
  `prepare_rag_research_fixtures.py --help` and `benchmark_progression.py --help` run.
- `cat Docs/Audio/PASS_1..5 | cmp - Docs/Audio/STUDY_GUIDE_AUDIO_FULL.txt` -> identical; 12,043 words.
- `tar -tzf ~/OpenIntelligence-BenchmarkArchive/BenchmarkRuns-2026-09-01.tar.gz` -> 1,628 members; with
  the two `--exclude` flags the ledger header gives -> 1,626, dropping exactly its `LEDGER.md` and
  `PROGRESSION.md`. Listed only, never extracted.
- `{ git diff --name-only HEAD; git ls-files --others --exclude-standard; } | bash scripts/required_docs.sh`
  -> no required document for any changed path.
- Not run: `bash scripts/build_simulator_smoke.sh`, which the `repoos_workspace_automation` route lists.
  No file Xcode compiles changed, so it would be a cold build that tests nothing new. The route's
  `quick_validate.py` lives under `~/.codex`, which the machine map says not to read; the one skill file
  edited under `.codex/` changed a sentence, not its structure.

## Blockers / Unknowns

- **Push:** the cleanup commit is local and waits on the owner's word. Once it is on `origin/main`, close
  https://app.notion.com/p/3e949a74d54f81b79775e99953132f98 (the old `PRIVACY.md`'s false claims): the new
  file states only what the code does, and the published policy
  (`~/Documents/GitHub/Gunzino/src/content/pages/openintelligence.privacy.md`, `cb4aab6`, 2026-09-23) already matches it on
  iCloud Sync, the non-expiring cache and what PCC receives. Set Completed with the push date.
- **Public Private Cloud Compute wording, the owner's call.** `README.md:30-32`, the 5.5 store notes
  (`fastlane/metadata/en-US/release_notes.txt:13`), `Docs/SHIPPED_CAPABILITIES.json:102`,
  `Docs/PRIVACY_AND_ROUTING.md:116`, `Docs/ai/ARCHITECTURE.md:113-114` and `CLAUDE.md:7` say or imply that
  only the final answer can reach PCC and that the sheet always shows first. With PCC chosen in the model
  picker, Deep Think and Maximum's reasoning passes can go too (`AgenticOrchestrator.swift:9000-9014`, since
  `6f29d2d`), and after Always Allow no sheet appears (`RAGService.swift:3729-3733`). Either keep the
  reasoning passes on device in code, or change the wording. The docs corrected on 2026-09-29 already say it.
- **Unverified, needs a device:** tapping a source chip may open nothing (the live chips at
  `ChatScreen.swift:901` get an empty handler; `RetrievalSourcesTray` wires one but appears only in
  previews), and inline citations may not be tappable (`humanizeCitations`, `RAGService.swift:17623`,
  rewrites `[S1]` as file and page, while `GroundedAnswerView.swift:31-35` links only a bare `[N]`). Tap
  both in an answer on a device; if nothing opens, file a row and correct `Docs/HOW_IT_WORKS.md:787`.
- **Owner decisions the plan left open** (none blocks anything):
  - Six Google Ads scripts with no copy elsewhere: `scripts/google_ads/delete_campaigns.py`,
    `scripts/google_ads/deploy_pmax_campaign.py`, `scripts/populate_core_v2.py`,
    `scripts/link_youtube_oauth.py`, `scripts/prepare_pmax_assets.py`, `scripts/create_video_campaign.py`.
  - The 28 Swift files no other file names, the evaluation types and the extractive QA mode: deleting any
    is an app change for a release, with a guarded build and the test suite.
  - `Docs/AppleIntelligenceTransitionPlan.md`: app comments cite it (`ContainerSettingsSheet.swift:445,491`).
  - `THIRD_PARTY_NOTICES.md` lacks the Rust crates swift-tokenizers links statically (tokenizers 0.22.2,
    minijinja 2.19.0, uniffi 0.31.1 and more, per its `rust/Cargo.lock` at `e4e01cb`); no license text is
    on this Mac.
  - By design since `6dc093c`, any verified paid purchase, a Pro subscription included, resolves to
    Lifetime for good (`EntitlementStore.swift:205,381-382`; `Docs/BILLING_AND_LIMITS.md` section 4).
    Whether that still fits monthly and annual Pro is a product question.
  - `Docs/RepoOS/01_TASK_ROUTER.md:9` and `00_REPO_COMMAND_CENTER.md:72` still cite playbook 07, which
    `AGENTS.md` rule 11 supersedes; changing them is a governance edit.
  - Recorded audio made from the old study text still says the old facts.
- **Carried, unchanged:** six `v5.4` rows close on the owner's device check (URLs in
  `git show 8be003a:Docs/ai/STATE.md`); Evidence Threads sync may copy nothing
  (`EvidenceThreadStore.swift:60` against `WorkspaceSyncService.swift:2739`; verify on a Pro build with
  library sync on); the three subscription descriptions in App Store Connect are a web-page edit (the API
  returns 409).

## Exact Next Action

Ask the owner whether to push `main` to `origin`: one local commit on top of `8be003a`, holding the cleanup
and this handoff, with `[ci skip]` in its message. If yes: `gtimeout 60 git push origin main`; a minute later,
`gh api repos/Gunnarguy/OpenIntelligence/commits/$(git rev-parse HEAD)/check-runs --jq .total_count`
should print 0 (a push that starts Xcode Cloud shows a check within twenty seconds, `Docs/ai/RUNBOOK.md`);
then close the PRIVACY.md row as described under Blockers. If no, nothing else is pending.
