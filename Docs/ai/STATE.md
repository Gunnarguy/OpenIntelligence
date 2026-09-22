# Current State

Updated: 2026-09-22, after the plans and ratings change
Branch/worktree: `main`, primary checkout, pushed to `origin/main`
Last verified commit: `3140f13`

## Objective

**5.3 is live on the App Store on both platforms. 5.4 is the open release and now carries its first
user-facing change: the Maximum cap enforced, one rating request on the first answer, and a plans
screen once at the end of setup (`0f6c5a0`, `3140f13`).** The evidence and the rest of the plan are in
`Docs/Release/CONVERSION_AND_REVIEWS_2026-09.md`. No code work is outstanding from that plan. Everything still open is either the owner's to do outside this
repository or a decision nobody has made yet; both lists are below.

**Read fact 6 before running any build.** A full test build crashed this Mac on 2026-09-20, and
the owner was away and could not restart it.

## The six facts that order everything else

1. **5.3 shipped on both platforms on 2026-09-18, from build 464.** The owner released it manually
   after both platforms were approved. `Docs/SHIPPED_VERSION.json` reads `app_store` 5.3, both
   per-platform values 5.3, `preparing` 5.4, `in_review` empty, `updated` 2026-09-18.
   `[evidence_level: measured, confidence: exact, evidence_source: Docs/SHIPPED_VERSION.json read 2026-09-20]`
2. **5.4 is open and carries nothing yet.** `CHANGELOG.md` has `## 5.4 <!-- unreleased -->` above
   the dated `## 5.3` heading, and the router reports `v5.4 (in_development, last shipped v5.3,
   0 unreleased entries)`. That heading is not cosmetic: `ci_scripts/ci_post_clone.sh` stamps
   `MARKETING_VERSION` from the first numbered heading, so without it the next Xcode Cloud build
   stamps an already-released 5.3 and App Store Connect rejects it, which is the exact failure of
   2026-07-28. Both 5.4 version records exist in App Store Connect; the owner created them on
   2026-09-18. `[evidence_level: measured, confidence: exact, evidence_source: repoos_router.py preflight, 2026-09-20]`
3. **Private Cloud Compute shipped in 5.2 and is live to users.** `Docs/SHIPPED_CAPABILITIES.json`
   carries `private_cloud_compute` at `status: shipping`, flipped when 5.2 reached the store. Any
   document that still calls PCC staged, pending, compiled out or unshipped is stale, and three
   such sentences have already been corrected across this repository and the websites. Public copy
   uses the present tense. `[evidence_level: measured, confidence: exact, evidence_source: Docs/SHIPPED_CAPABILITIES.json read 2026-09-20]`
4. **The toolchain is the Xcode 27 release.** Xcode 27.0, build `27A266a`, Swift 6.4, at
   `/Applications/Xcode.app`, and `xcode-select` points at it. `/Applications/Xcode-beta.app` no
   longer exists, so any command naming that path fails. The host is macOS 27.0 build `26A428`.
   `[evidence_level: measured, confidence: exact, evidence_source: sw_vers, 2026-09-20]`
5. **Xcode Cloud has one workflow and it is correct.** `Default`, pinned to Xcode 27 (`27A266a`)
   on macOS `Latest Release`, with exactly two archive actions, iOS and macOS, and **no test
   action**. Start condition is branch `main` only. A `DO_NOT_START_IF_ALL_FILES_MATCH` path filter
   covers `*.md`, `Docs/`, `.claude/`, `.agents/`, `.codex/`, `fastlane/metadata/` and `.github/`,
   so a documentation push does not burn build compute; this account has hit the compute cap before.
   The pin was verified on 2026-09-22 by `zsh -ic 'ruby scripts/xcode_cloud_toolchain.rb'`, which prints
   `Workflow 'Default' currently builds with: Xcode 27 (27A266a)`. The start condition and the seven
   matchers were re-read from `ciWorkflows` the same day and match this paragraph exactly; the actions
   are `Archive - macOS` and `Archive - iOS`, both `ARCHIVE`. Build #465, from `bdec851`, succeeded
   on all four actions at 15:43Z. **Open observation:** `8c99a6b`, pushed 2026-09-22 15:42Z, changed `OpenIntelligenceTests/Services/Document/Processing/IngestionFormatCoverageTests.swift` and `scripts/asc_end_sale.rb` alongside two markdown files, and no build had started when checked at 15:51Z. Neither path is in the filter, so one was expected. Nothing shipped depends on it, since neither file reaches the archive. Before the next real source push, check `ruby scripts/xcode_cloud_toolchain.rb` and the build list; if a source push does not start a build, the candidates are the account's compute cap, which it has hit before, or a missed webhook, and a build can be started by hand in App Store Connect.
   `[evidence_level: measured, confidence: exact, evidence_source: ciWorkflows branchStartCondition and ciBuildRuns read 2026-09-22]`
6. **A cold full build can take this Mac down.** It has **18 GB** of memory and 11 cores. On
   2026-09-20 at 04:41 a full `xcodebuild test` ran two `swift-frontend` processes that grew to
   15.5 GB and 15.4 GB. Resident memory reached 60 GB, macOS killed 340 processes at 04:44 and 888
   at 04:45, and the Mac rebooted uncleanly at 04:52. What looked like a stalled build was swap
   death. An **incremental** build is safe: on 2026-09-21 the same suite, reusing DerivedData,
   peaked at 1.9 GB per compiler and never took free memory below 32%. For any long build while the
   owner is away, poll `memory_pressure` and kill `xcodebuild` and `swift-frontend` below 15% free.
   Which file drives one compiler to 15 GB is **not known**. A separate kernel panic on 2026-09-21
   at 20:38, `watchdog timeout: no checkins from watchdogd in 90 seconds`, has no memory-pressure
   report before it, so its cause is not established and it is not attributed to a build.
   `[evidence_level: measured, confidence: exact, evidence_source: /Library/Logs/DiagnosticReports JetsamEvent-2026-09-20-044424 and -044524, panic-full-2026-09-21-203802; last reboot]`

## Working tree

Clean. Suite at `0f6c5a0`: 495 executed, 3 skipped, 0 failures, on the iOS 27 simulator with the
memory guard armed and never fired. `testSilentAudio` passed in that run rather than skipping.

Clean after the earlier handoff, as it was then: The three edits the previous version of this file described landed
in the 2026-09-22 commits, with the rest of that night's work:

| Commit | What |
|---|---|
| `8378a3e` | The README and eight docs brought to 5.3 live and 5.4 open |
| `ff7f493` | The session brief's backtick bug; both red test gates repaired; `ci_post_clone.sh` message |
| `f14ffa0` | Both metadata trees set to 5.4's non-sale text; fastlane stops pushing screenshots; the store-copy script |
| `e51dbeb` | The missing 5.3 What's New entry, and the test that fails the build next time |

Run `git status` when you read this; git is the authority over this paragraph.

## Open work, and who owns it

None of it is code. Nothing below blocks anything else.

### Owner, outside this repository

- **Three items from the conversion plan, each about ten minutes, none of which an agent can do:** reply to the
  one written review (2026-03-25, US, 4 stars; Apple notifies the reviewer, who can update); set a retention
  message and a win-back offer in App Store Connect (5 of 5 cancel-sheet views ended in a cancel with no message);
  and hand Lifetime offer codes to the heaviest users (offer codes work for non-consumables from iOS 16.3, up to
  10 active offers). Details and sources in `Docs/Release/CONVERSION_AND_REVIEWS_2026-09.md`, section 5.
- **Device verification of the enforced cap** closes the roadmap row filed 2026-09-22: on a free-tier device on 5.4,
  the fourth Maximum send of a day shows the limit dialog, and the next morning the pill reads "3 left today".
- **Done 2026-09-22: fascinaiting.me no longer publishes its internal files.** Before: all
  HTTP 200: `/CLAUDE.md`, `/ANALYTICS_AUDIT.md`, `/google_ads_config.json` and
  `/FACT_CHECK-2026-09.md`. The ads file holds the Google Ads customer ID, every campaign, ad and
  asset-group ID, and all ad copy; no password or API key appeared among its field names. The
  site's `robots.txt` says `Allow: /`. Fixed by a Jekyll exclude list, Fascinaiting commit
  `572a5d51`; every listed file now returns 404 and the home page 200.
  `[evidence_level: measured, confidence: exact, evidence_source: curl status codes before and after, 2026-09-22]`
- **Half done 2026-09-22: of two wrong statements on the App Store, one is fixed and one Apple
  refuses.** The live 5.3 promotional text said
  "Lifetime is 33% off", which one string cannot be across storefronts measuring 30.8% to 40%.
  Both Pro subscription descriptions promise "unlimited documents and 5 libraries", against
  `QuotaPolicy`'s 1,000 and 10. The correction is `scripts/asc_fix_listing_copy.rb`, which carries
  the localization ids and a `--dry-run`. Run 2026-09-22: both promotional texts corrected, HTTP
  200. Both subscription descriptions returned 409 `UNMODIFIABLE` (localization in `ACTIVE`
  state) plus `TOO_LONG` (the field caps at 55 characters). The app never renders a product
  description and has zero promoted purchases, so no customer sees the string; it is corrected
  whenever a subscription change next goes through review, in 55 characters or fewer.
- **Scheduled, no longer the owner's: the sale comes down on 2026-09-30.** The one-time task
  `openintelligence-end-lifetime-sale` fires at 09:00 Pacific and runs `scripts/asc_end_sale.rb`
  (dry-run verified against the live store), then strips the sale line from all three sites and
  checks each page live. It runs only while the desktop app is open; if it is closed that morning
  it runs at next launch. The original instructions follow. Replace the sale text on the **live 5.3 records only**, both
  platforms, and strip the sale line from the three websites. The non-sale wording is in the 5.3
  entry of `Docs/Release/APP_STORE_METADATA_HISTORY.md`. **5.4 needs no action**: a new App Store
  version inherits no promotional text, both 5.4 records read empty, and they were filled with the
  non-sale wording on 2026-09-19, which is correct whether 5.4 ships before or after the sale ends.
  Each website line carries a comment naming its removal date.
- **The macOS `APP_DESKTOP` screenshot set**, still seven captures from 2026-06-21. Every iPhone and
  iPad set was regenerated on 2026-09-19 from clean simulators, twenty images across
  `APP_IPHONE_67`, `APP_IPHONE_65`, `APP_IPHONE_61` and `APP_IPAD_PRO_3GEN_129`, all reading
  `COMPLETE` on the 5.4 records. macOS cannot be done the same way: there is no macOS simulator and
  window capture needs a Screen Recording grant this process does not have. The recipe for the rest
  is in `Docs/ai/RUNBOOK.md` under "Regenerating App Store screenshots, with no device and no screen
  permission".
- **Rename the Lifetime product from "Lifetime Cohort" to "Lifetime"**, if it is still wanted.
  Apple refuses the edit, not the tooling: `PATCH inAppPurchaseLocalizations/{id}` returns HTTP 409
  `ENTITY_ERROR.ATTRIBUTE.INVALID.UNMODIFIABLE`, because an approved in-app purchase localization is
  immutable and the product's only version is `APPROVED`. Changing the name means creating a new
  in-app purchase version and putting it through review. That is a paid-product change tied to a
  review cycle, so it is the owner's call. **Note for whoever does it:** in-app purchase resources
  live under the `/v2/` API base, while the `api` helper in `scripts/xcode_cloud_toolchain.rb`
  hardcodes `/v1/`, which makes a wrong-path 404 read like a missing endpoint.
- **Device verification of what 5.3 shipped.** 5.3 was submitted without the device checks, at the
  owner's instruction. Nothing in this repository records a device run against build 464. Suite-green
  closes nothing here, so the roadmap rows those checks belong to are still open until someone opens
  the app on a phone. **The roadmap is the authority on which rows those are**; read it with the
  `notion-roadmap` skill rather than from this file. What is known: the sample-library fix was
  observed working on a **simulator** during the 2026-09-19 screenshot pass (three documents, 41
  chunks, no duplicates, hand-written questions rather than the template fallback), which is
  evidence and is not a device.

### Decisions nobody has made

These have been carried for several sessions. None of them is an agent's to make.

1. **The camera's release gate.** `ChatScreen.visionCaptureAction` is `#if os(iOS) && DEBUG`, so the
   screen is unreachable from a Release build. Before removing it: run the screen on a device
   through every dismissal path and confirm the camera indicator goes out each time, because a path
   where `.onDisappear` does not fire leaves the capture session live; and decide whether an in-app
   "experimental" label should accompany it, since someone who never reads release notes gets no
   signal that the feature is new. The held user-facing notes are in
   `Docs/Release/5.3/camera_user_notes_held.md`, ready for whichever release carries the camera.
   `[evidence_level: code_verified, confidence: exact]`
2. **The system prompt on the owner's own install**, reported as "You are an extremely unhelpful
   assistant...". This is a stored user setting, not a default: the default in source is "You are a
   helpful assistant." It cannot be checked from this repository. If it is set, it reaches
   `FoundationModelPromptCompiler` on every Standard answer and degrades answers more than any
   control on the Model Parameters screen. `[evidence_level: code_verified, confidence: high]`
3. **`.build` (841 MB) and `build/` (444 MB)** at the repository root lack the `.nosync` suffix that
   `.build.nosync`, `.simulator-smoke.nosync` and `.device-smoke.nosync` all carry, so iCloud syncs
   about 1.3 GB of build output. This is the same mechanism that starves builds run against the
   checkout. Renaming or removing them is the owner's call.
   `[evidence_level: measured, confidence: exact, evidence_source: du -sh, 2026-09-20]`
4. **Resolved 2026-09-22: `testSilentAudio`.** See the next section. The remaining question needs
   a device, not a decision.
5. **A design question rather than a decision:** a custom reasoning profile currently reaches only
   Apple's model-internal effort dial, which is PCC-only. The app's own reasoning, the multi-session
   chains in Deep Think and Maximum pinned on-device, is driven by this app's prompts and is
   untouched by what the owner writes in that field. Feeding that text into the reasoning chain's
   prompts is what would make the feature match its name. It was deliberately not attempted: those
   prompts are the product, and answer quality cannot be A/B tested here, because retrieval is
   nondeterministic.

## `testSilentAudio`: the exclusion is gone, because the test can now skip itself

**Resolved 2026-09-22.** The test always intended to `XCTSkip` on timeout, and never could: its
helper waited with `XCTestCase.fulfillment(of:)`, which records a failure when the wait expires,
before the skip branch runs. The helper now waits on a standalone `XCTestExpectation` through a
delegate-less `XCTWaiter`, which reports the timeout as a result. Verified both ways on the iOS 27
simulator: normally the WAV throws in 0.8 s and the test passes; with the timeout forced to 1 ms in
a throwaway copy it skips with its own message and the run succeeds. No `-skip-testing:` flag is
needed anywhere. What is still open is the test's own question, hang versus missing speech model,
which needs an audio file with no speech imported on a device. The history below is kept as record.
`[evidence_level: measured, confidence: exact, evidence_source: two runs 2026-09-22, 12/0 and "1 test skipped, 0 failures"]`

### History, superseded

`IngestionFormatCoverageTests.testSilentAudio_FailsLoudlyInsteadOfProducingAnEmptyDocument` exists
in `OpenIntelligenceTests/Services/Document/Processing/IngestionFormatCoverageTests.swift`. Earlier
revisions of this file recorded that it was "excluded by name" from every run, passed to
`-skip-testing:` because it hangs its full 60-second timeout on this simulator, and that it was not
counted in the totals.

**Nothing enforces that exclusion.** A repository-wide search for `-skip-testing` on 2026-09-20
returns exactly one hit, and it is the sentence in this file describing the exclusion. It is in no
script, no runbook command, no scheme and no CI configuration. So the flag exists only where a
person retypes it, and the recorded pass counts cannot be reconciled against a written command.
`[evidence_level: measured, confidence: exact, evidence_source: grep for "-skip-testing" across the repository, 2026-09-20]`

What is known about the test itself: its own failure message states the open question, "Unresolved:
whether ingestion genuinely hangs on speechless audio, or this simulator has no speech model." The
simulator log carries `[UAFAssetProvider] ... com.apple.linguisticdata failed`, which points at a
missing speech model rather than at an ingestion hang, but that is a lead and not a finding.

**This is an open decision for the owner, with three ways out.** It should not be treated as settled.

- Put the flag in `Docs/ai/RUNBOOK.md` and in whatever script runs the suite, so the exclusion is
  real and visible in the command rather than implied by a paragraph.
- Mark the test skipped in Swift with `XCTSkip` and a reason, so it reports itself.
- Resolve the underlying question by importing an audio file with no speech on a real device and
  watching the ingestion queue. Either ingestion hangs on speechless audio, which is a real defect,
  or the simulator has no speech model, which is not.

Until one of those happens, treat every pass count in this file as "with one test of unknown state".

**2026-09-21, run without the flag:** it failed again, `Asynchronous wait failed: Exceeded timeout
of 60 seconds` on `processDocument(silence.wav)`, now on the iOS 27.0 simulator rather than 26.5.
So it is not a runtime-specific flake, and it is the only failure in that run.

## Active constraints

- **Only the iOS 27.0 simulator runtime exists now.** 18.0, 18.3 and 26.5 were removed on
  2026-09-21 at 20:57, nine minutes after the second reboot, by a burst of short `simctl` calls
  whose source was not identified; no script in this repository or the global kit deletes
  simulators. Their devices went with them, including the iPhone 17 Pro
  `DA9536BA-F048-4352-92AA-66A7E1A464BA` the memory used to recommend and PlantParenthood's QA
  simulator. **Use `25E29FA1-6A22-4A86-AE9F-A6F48411E6D0`** (iPhone 18 Pro, iOS 27.0). Boot it and
  wait until `simctl list devices` shows it `(Booted)` before starting `xcodebuild`: launching
  straight after restarting `CoreSimulatorService` made a run exit 70, "Unable to find a device".
  `[evidence_level: measured, confidence: exact, evidence_source: simctl runtime list; ~/Library/Developer/CoreSimulator/Devices; log show 20:55-20:58]`
- **Never build against the checkout.** The repository lives in iCloud-synced `~/Documents`. When the
  tree has been written to, `fileproviderd` saturates a core and `xcodebuild` gets almost no CPU: a
  run once sat over ten minutes without creating its DerivedData directory. Copy the sources out and
  build there, with `-derivedDataPath` also outside `~/Documents`. Run
  `scripts/check_icloud_conflicts.sh --fix` before debugging any build failure that makes no sense,
  because iCloud writes `Foo 2.swift` conflict copies that Xcode's synchronized file groups compile
  for real. `.git` is a file pointing at `.git.nosync` on purpose.

```bash
rsync -a --delete --exclude='.build*' --exclude='build' --exclude='*.nosync' --exclude='.git' \
  OpenIntelligence OpenIntelligence.xcodeproj OpenIntelligenceTests OpenIntelligenceLiveActivities \
  Package.swift Package.resolved Info.plist Docs CHANGELOG.md ci_scripts /private/tmp/oi-src/
xattr -cr /private/tmp/oi-src
```

- **The camera is experimental, by the owner's own word on 2026-09-13.** Roughly 4,300 lines under
  `Features/Camera/` compile into every build and cannot be reached from a Release one. Its detection
  behaviour has been observed by one person on one phone. Do not promote it to settled language in a
  later pass, and do not cite it as a shipped capability in Settings copy, the App Store listing or
  the roadmap until it has real use behind it. The rationale is in `Docs/ai/DECISIONS.md` under
  2026-09-13. Session teardown is already written and does not need re-investigating:
  `CameraVisionOverlayView` pairs `startSession()` on appear with `stopSession()` on disappear. The
  failure worth watching for is `.onDisappear` not firing on some dismissal path, whose symptom is
  the green camera indicator staying lit after the screen closes.
- **Do not delete Frequency, Presence or Repetition Penalty from Model Parameters.** They do nothing
  today: `GenerationOptions` in the iOS 27 SDK exposes `samplingMode`, `temperature`,
  `maximumResponseTokens` and `toolCallingMode`, and the string "penalty" does not occur anywhere in
  the FoundationModels interface. They are still collected by `ChatScreen`, persisted by
  `SettingsStore` and threaded into `InferenceConfig` before being dropped where `GenerationOptions`
  is built. **Deleting them is the obvious move and it is wrong.** Their consumer,
  `OpenIntelligence/Services/LLM/LocalOpenAIServerLLMService.swift`, is scaffolding for the open
  roadmap row about a third-party model host on Mac. Zero call sites is what an open roadmap row
  looks like. What was actually wrong was the footer claiming they affect sampling, and that is
  fixed. `[evidence_level: code_verified, confidence: exact]`
- **Adaptive generation profiles are unmeasured.** Retrieval is nondeterministic, so no A/B here is
  trustworthy. The values are reasoned, not measured. Do not claim they improve answers. They are
  off by default for that reason.
- **Adaptive profiles now reach Deep Think and Maximum, and the old constraint saying otherwise is
  withdrawn.** The first version gated them below the `if useAgentic` return, so only Standard saw
  them; `0da8528` set `activeAdaptiveProfile` on the agentic path as well, and the 5.3 release notes
  say the feature applies in all three modes. The original warning still has a live edge: the
  agentic path does not read `InferenceConfig` for generation, so a value mutated on a local that
  `AgenticOrchestrator` never reads will log as though it took effect while changing nothing. Read
  the comment block above `activeAdaptiveProfile` in
  `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift` before moving anything.
  `[evidence_level: code_verified, confidence: exact]`
- **Entities still come from table cells only.** `extractDetectedData` has exactly one call site, in
  `parseTable`, so paragraphs on the same page contribute nothing. Most documents are not tables.
  The 5.3 release notes state this limit plainly rather than hiding it.
  `[evidence_level: code_verified, confidence: exact]`
- **`fastlane/metadata/` and `fastlane/metadata-ios/` are a push source for 5.4, not a record of
  what is live.** Since `f14ffa0` both promotional text files carry the non-sale text already on
  the 5.4 records, and the two trees match; before it they disagreed and both held 5.3's sale
  text. The release notes are still 5.3's, because 5.4 has nothing user-facing yet. `push_metadata` targets a version record by number, so
  naming the wrong version overwrites a live listing with the wrong text. Check the version argument
  before running it, and set `LC_ALL=en_US.UTF-8` in a non-interactive shell or `deliver` fails on
  the bullet character. `[evidence_level: measured, confidence: exact, evidence_source: fastlane metadata read 2026-09-20]`
- **Use Xcode Cloud for releases; do not archive releases on this Mac.** The rule stands, because
  `ci_scripts/ci_post_clone.sh` stamps the version and `ci_scripts/ci_post_xcodebuild.sh` gates the
  binary, and a local archive gets neither. **Its recorded rationale no longer holds, and that gap
  is open.** `Docs/ai/RUNBOOK.md` says every local archive is rejected with `ITMS-90111` because
  this machine runs a prerelease macOS whose `BuildMachineOSBuild` stamp ends in a lowercase letter.
  The host now reports build `26A428`, which has no trailing lowercase letter. Nobody has tested
  whether a local archive would now pass ingestion, and nobody should find out during a release.
  Correcting that runbook section is work for whoever owns it next.
  `[evidence_level: measured, confidence: exact for the OS build; unknown for whether ingestion would accept it]`
- **The three website patches under `Docs/Release/5.2/sites/` were applied on 2026-09-14** and are
  history, not pending work. The earlier note calling them unapplied is withdrawn. All three sites
  have since been bumped to 5.3 and verified live.

## Verification

Run today, 2026-09-20, output read:

- `scripts/check_icloud_conflicts.sh` reported `OK: .git is a gitdir pointer`, `OK: no iCloud damage found`.
- `python3 scripts/verify_doc_claims.py Docs/ai/STATE.md HANDOFF.md` reported that every checked claim matches
  source.
- `zsh -ic 'ruby scripts/xcode_cloud_toolchain.rb'` printed `Workflow 'Default' currently builds with:
  Xcode 27 (27A266a)`.
- `python3 .codex/skills/route-openintelligence-work/scripts/repoos_router.py preflight` reported
  `v5.4 (in_development, last shipped v5.3, 0 unreleased entries)`.
- `diff Docs/USER_CHANGELOG.md OpenIntelligence/Resources/VersionHistory.md` reported no difference.
- `git rev-list --count origin/main..HEAD` printed 0.

**Run 2026-09-21 and 2026-09-22, output read:**

- Full suite from `/private/tmp/oi-src` on the iOS 27.0 iPhone 18 Pro, with every change in `e51dbeb`:
  **481 executed, 4 skipped, 1 failure**, `** TEST FAILED **`, exit 65. The failure is
  `testSilentAudio`, described above; nothing in this change touches audio. The count reconciles:
  the 476 recorded on 2026-09-18 had that test skipped by flag, plus the four new
  `WhatsNewCoverageTests`, all of which passed, plus the unskipped one. A memory guard ran alongside
  and never fired.
- `scripts/test_verify_doc_claims.sh` 6 passed 0 failed; `scripts/test_stop_handoff.sh` 11 passed
  0 failed; `scripts/test_enforce_docs_hook.sh` 16 passed 0 failed; `test_repoos_router.py` 29 OK;
  `secret_scan.py` clean.
- The Notion `Target Release` property had no `v5.4` option, so no 5.4 row could be filed; the API
  refuses to create one implicitly. It was added on 2026-09-21, every existing row kept its release
  (counts compared before and after), and the What's New defect was filed against it.

The run before that, 2026-09-18, from `/private/tmp/oi-src` against
the iOS 27 simulator with the review alert, the months arithmetic and the reordered notes in the
tree, reported `** TEST SUCCEEDED **`, exit 0, **476 executed, 3 skipped, 0 failures**, and
`xcodebuild -destination "platform=macOS" build` reported `** BUILD SUCCEEDED **`, exit 0. The three
skips are the tests' own guards, two in `EmbeddingProviderAgreementTests` and one in
`LayoutReadingOrderTests`, not a clean pass. Read the section above on `testSilentAudio` before
quoting any of these counts.

Earlier runs, all from `/private/tmp/oi-src` against the iOS 27 simulator, kept as the shape of the
trend rather than as current evidence; the full entries are in this file's git history:
2026-09-18 473 executed, 2026-09-18 467 executed, 2026-09-14 467 executed, 2026-09-14 446 executed,
2026-09-13 440 executed, 2026-09-11 416 passed. Each reported 0 failures. macOS built green
alongside all of them, which matters because the `#else` half of a `canImport(UIKit)` pair has
diverged silently in this repository before.

**Not verified:** no device run of anything in 5.3. Adaptive profiles have never been switched on
outside a unit test. The camera's detection has been seen by one person on one phone and never in a
Release build, because a Release build cannot reach the screen.

## Exact next action

1. **Run the preflight for whatever you are about to do.** It reports the binding read-first docs,
   the allowed and forbidden edit paths, the required tests and the required doc updates for the
   matched route, and those are not advisory.

```bash
python3 .codex/skills/route-openintelligence-work/scripts/repoos_router.py preflight --task "<what you are about to do>" --path <path>
```

2. **Deal with the working tree.** Run `git status`. It should be clean. If it is not, commit to
   `main`; this repository commits directly to `main` with no branches
   and no pull requests, and no AI co-author trailer. The pre-commit hook resolves changed paths to
   the docs they require through `scripts/required_docs.sh`, so let it tell you what else the commit
   needs rather than guessing. A push starts an Xcode Cloud build unless every changed path matches
   the workflow's documentation filter.
3. **Read the roadmap before choosing new work.** The Notion database is the source of truth for
   plans, not `Docs/ROADMAP.md`. Use the `notion-roadmap` skill; never answer a roadmap question
   from memory, and never locate the database by workspace search. Work that is not on the board is
   work nobody decided to do. New findings default to `Future Backlog`: a defect earns the active
   release only if it loses or corrupts user data, makes an advertised capability not work, or
   blocks the build from shipping, and the row has to say which.
4. **If the work is a 5.4 change**, it lands under the `## 5.4` heading in `CHANGELOG.md`, which is
   the only version authority in this repository. Leave the `<!-- unreleased -->` marker alone until
   5.4 is actually live on both platforms.

## Where things live

| Need | Read |
|---|---|
| What the project is, scope, constraints | `Docs/ai/PROJECT.md` |
| Component map and which doc owns which area | `Docs/ai/ARCHITECTURE.md` |
| Why something is the way it is | `Docs/ai/DECISIONS.md` |
| How to build, test, release, recover | `Docs/ai/RUNBOOK.md` |
| Full agent directives | `AGENTS.md` |
| Cross-tool handoff, for any agent and not only Claude | `HANDOFF.md` |
| Routing, edit boundaries, release gate | `Docs/RepoOS/` |
| Ground truth on product claims | `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md` |
| Every accuracy or retrieval number this project has claimed, including the retracted ones | `BenchmarkRuns/LEDGER.md` |
| Every version of the App Store copy since 2.1.1, per platform, with live dates | `Docs/Release/APP_STORE_METADATA_HISTORY.md` |
