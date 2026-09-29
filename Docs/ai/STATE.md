# Current State

Updated: 2026-09-29, 10:40 PT (entitlement fix committed and pushed for a new 5.5 build; attaching it waits on Xcode Cloud)
Branch/worktree: `main`, primary checkout
Last verified commit: a747ece

## Objective

5.5 is the open release: one app change (the "how much" extractor fix), staged in App Store Connect on
both platforms with build 481, and nothing submitted. Submitting is the owner's call, and new work
starts only when he says to (`Docs/ai/DECISIONS.md`, 2026-09-24).

On 2026-09-29 he said to carry out the cleanup plan's recommendations as long as nothing fundamental
breaks. That is done and pushed (Status). He then asked for the entitlement defect to be fixed and approved
the plan that named `EntitlementStore.swift` ("yep, go for it"), with everyone who already has the protection
keeping it. The fix is committed and pushed; the next 5.5 build carries it (Blockers).

## Status

- **Entitlement fix, 2026-09-29, at the owner's word**, in the commit after `a747ece`. Through 5.4 every paid
  purchase, a free trial included, became permanent protection that resolves to Lifetime. Now only a Lifetime
  purchase, or a subscription that began before 2026-09-30 00:00 UTC, earns it, through one rule,
  `EntitlementStore.protectionEarned` (`EntitlementStore.swift:242`); stored protection is never lowered.
  `EntitlementProtectionTests` (8), `Docs/BILLING_AND_LIMITS.md` section 4, `CHANGELOG.md` 5.5 Fixed, the
  2026-09-29 entry in `Docs/ai/DECISIONS.md`, and the restamped `billing-and-quotas` codemap slice. Roadmap row
  https://app.notion.com/p/3ea49a74d54f8163865ff0a7c1ef55e6 (In Progress, v5.5).
- **Cleanup, done 2026-09-29, pushed as `35024f0` with `[ci skip]` at the owner's word.** GitHub showed 0
  checks and 0 statuses on it 3.5 minutes later, so no Xcode Cloud build started. Documentation and tooling only; no file
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

- Entitlement fix: guarded `xcodebuild test -scheme OpenIntelligence` on simulator
  `244AA789-A9EA-403B-A922-F12083D14495` (iOS 27), `-jobs 2`, DerivedData `/private/tmp/oi-build`, built from the
  `/private/tmp/oi-src` copy -> `** TEST SUCCEEDED **`, 512 tests, 4 skipped, 0 failures, 262 s, lowest free
  memory 24%. All 8 `EntitlementProtectionTests` passed. Not run yet: the route's manual StoreKit check.
- Cleanup, 2026-09-29: `verify_doc_claims.py` -> all claims match; `test_verify_doc_claims.sh` 8/8;
  `test_enforce_docs_hook.sh` 18/18; `test_stop_handoff.sh` 11/11; router tests 31 OK; codemap 0 errors;
  `test_build_map.py` 10 OK; secret scan clean; changed scripts parse (`ruby -c`, `swiftc -parse`, `ast.parse`);
  full audio text equals passes 1-5 (12,043 words); the ledger's tar `--exclude` flags drop exactly its two
  files (1,628 members to 1,626, listed only). Not run: `build_simulator_smoke.sh` (nothing compiled changed).

## Blockers / Unknowns

- **New 5.5 build with the entitlement fix.** The push of the fix starts Xcode Cloud. When the build is `VALID`
  on iOS and macOS (the dry run `zsh -ic 'ruby scripts/asc_prepare_release.rb 5.5 <build>'` finds it, or
  App Store Connect's TestFlight tab shows it), attach it in place of 481 with the same command plus `--apply`;
  the owner approved that swap on 2026-09-29, and nothing is submitted. Then the route's manual check, in the
  `OpenIntelligence-StoreKitTesting` scheme or TestFlight sandbox: buy Pro Monthly, Settings shows Pro, not
  Lifetime; expire it and relaunch, Free. That check closes https://app.notion.com/p/3ea49a74d54f8163865ff0a7c1ef55e6.
  Anyone who starts a subscription or trial on 5.4 still gets the old stored protection until they update.
- **Privacy row stays open:** https://app.notion.com/p/3e949a74d54f81b79775e99953132f98 has a dated note of
  2026-09-29. The new `PRIVACY.md` is pushed; the published policy still says Private Cloud Compute gets data
  for final synthesis only (see the next item), so the row closes when that page or the code changes.
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
- **Carried:** six `v5.4` rows close on the owner's device check (URLs in `git show 8be003a:Docs/ai/STATE.md`);
  Evidence Threads sync may copy nothing (`EvidenceThreadStore.swift:60` against `WorkspaceSyncService.swift:2739`);
  the three subscription descriptions in App Store Connect are a web-page edit (the API returns 409).

## Exact Next Action

Wait for Xcode Cloud to build 5.5 from the entitlement-fix commit (the first after `a747ece`). When the build is
`VALID` on iOS and macOS, attach it in place of 481 with
`zsh -ic 'ruby scripts/asc_prepare_release.rb 5.5 <build> --apply'` (approved by the owner on 2026-09-29;
nothing is submitted), then do the manual StoreKit check under Blockers.
