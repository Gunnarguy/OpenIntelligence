# Current State

Updated: 2026-10-14, 20:15 PT (5.7 is open and unreleased, no 5.7 build in TestFlight; the 5.7 work of 2026-10-14 is in 13 commits through `86cc299`, each pushed with `[ci skip]`; 5.6 has been live on iPhone, iPad and Mac since 2026-10-08, build 485)
Branch/worktree: `main`, primary checkout
Last verified commit: 86cc299

Earlier detail is in git: `git show 9d3dcee:Docs/ai/STATE.md` (the afternoon of 2026-10-14), `git show 131f989:Docs/ai/STATE.md`
(that morning), and the long record through 2026-10-10 is `Docs/Archive/STATE_record_through_2026-10-10.md`.

## Objective

**5.7: JSON Lines import and the Apple surfaces that carry the app to other apps and people, mainly for iPhone
and iPad.** Named by the owner on 2026-10-08, widened on 2026-10-09 (the Apple model APIs) and 2026-10-10 (the
whole import path, very large libraries). On 2026-10-14 he said "5.7 is to be massive" and, asked about each
protected change, approved everything that upgrades the app, with best practice for consent. Everything that can be
built inside the app is built. What is left waits on his Apple account in Xcode, his word for App Store Connect,
or a device.

## Status (2026-10-14, evening)

| What | Where it stands |
|---|---|
| 5.7 source | All pushed (`git rev-list --count origin/main..HEAD` prints 0). The evening's commits: `a873811` dictation on the Mac, Enhanced Security set up and held back; `63021fd` a file opened from another app shows before anything is added; `2afc9f2` a UI-testing target that runs actions through the system; `e7604f8` an action that needs the Private Cloud Compute consent sheet comes forward and asks; `b4618e0` conversations saved where iCloud sync reads them, a crash report the person can send, a question asked again searches what the libraries hold now; `86cc299` what a refuting review of that work found, fixed. The afternoon's seven are listed in `git show 9d3dcee:Docs/ai/STATE.md`. |
| Tests | 1,003 run, 0 failures, 5 skipped (two need Core AI, one layout case, the two scale benchmarks), 2026-10-14 at 19:50 PT (cycle `i9c`) on `86cc299`'s tree before a test-only isolation fix in `EvidenceThreadStoreTests`, which then ran alone: 12, 0 failures. The two runs before it on the same build stopped before any test started ("The test runner hung before establishing connection"; `Docs/ai/RUNBOOK.md` has the note). UI tests (scheme `OpenIntelligenceUITests`): 2 run, 0 failures. Device and Mac builds succeeded. |
| TestFlight | No 5.7 build. Every 5.7 push carried `[ci skip]`; a push whose newest commit lacks it starts one. The newest Xcode Cloud run is still #485 (2026-10-08). |
| His iPhone | Not updated. The installer started at 11:30 PT gave up at 17:31 PT: every process listing that succeeded showed the app on the phone, and it never installs over a running app. `/private/tmp/oi-install/OpenIntelligence.app` is the build of `07c0cbb`, now stale. |
| Roadmap | 113 rows on `v5.7`: 105 In Progress, 7 To Do (each waits on his Apple account in Xcode, App Store Connect or the website), 1 Completed (the action tests, closed on the Simulator as the row says). Moved to Future Backlog that day: one model profile per answer mode, and passages by reference. Pulled into 5.7: conversation sync (https://app.notion.com/p/3e649a74d54f811492b6d0d8f5e89f71) and the query cache (https://app.notion.com/p/3e749a74d54f810c86fefac905fa1d6f). |
| Catalogue | https://claude.ai/artifact/Thu24syf3CbVtpwhjAm4mJ, version 10: 69 built, 13 partly, 4 not started, 8 needing him, 2 checked, 22 the app already had (118 rows). |
| Test simulator | `OI 5.7 tests` `7652732F-FCEA-47A3-B345-7EC57B9EFE67` (iPhone 18 Pro, iOS 27.0), made 2026-10-14 at 17:02 after DeviceHub's deletion of every simulator at 16:49. Simulators on this Mac are deleted between sessions: check `xcrun simctl list devices` first. |

## Completed (2026-10-14, evening)

Built, compiled for iPhone and Mac, and in the suite; none of it seen on a device. `CHANGELOG.md`, section 5.7,
has one entry per change with its evidence and what closes it.

- `a873811`: the chat's microphone on the Mac (`com.apple.security.device.audio-input`, at his word). Enhanced
  Security was switched on and the device build failed: the provisioning profile lacks the capability and Xcode here
  has no Apple account to add it. Reverted; the exact settings are in `Docs/ai/DECISIONS.md` (2026-10-14).
- `63021fd`: "Open in OpenIntelligence" shows `OpenedFilesSheet` first: Quick Look to read, then Add to Library
  (the usual plan check and import review) or Don't Add (the copies are removed).
- `2afc9f2`: `OpenIntelligenceUITests`, its own scheme, with Apple's AppIntentsTesting. It adds a note with Add to
  Library and runs Ask My Documents' own `perform()` and Open Document through the system. Debug-only
  `UITestSupport` gives the ask actions a stand-in model. Roadmap row for action tests: Completed.
- `e7604f8`: the five ask actions run in the background and may come forward (`[.background,
  .foreground(.dynamic)]`). When the system lets one come forward, its question counts as one a person can be asked
  about; the consent gate brings the app forward and shows the sheet. A request from an action's engine is shown by
  `ContentView` through `CloudConsentRelay`; one no window shows within 15 s is given up, nothing remembered. This
  also ends a hang: with the app in front (on the Mac, whenever it was active), an action's question that reached
  the consent step waited for good.
- `b4618e0`: conversations (`EvidenceThreadStore`) saved in `baseDirectory()/EvidenceThreads`, the folder sync
  reads, with old threads moved there; crash reports from MetricKit (`CrashReports`), offered once, emailed or
  shared from Settings, About; the query cache keyed to the libraries' documents and the model, with a stale hit
  refused and no lookup by similarity (it had replayed passages from deleted documents since 3.7.0).
- `86cc299`, after a refuting review (reasons in `Docs/ai/DECISIONS.md`, 2026-10-14): no window could claim the relay's request, so the consent sheet never showed (now it does), only an action's engine uses the relay, and a stored choice comes first and is read again; deleted conversations sync as a list (`deleted_threads.json`); crash reports leave out the memory region, a crash delivered twice is kept once, and one window offers it; the opened-file sheet closes only with its two buttons and its copies wait outside the folder sync sweeps; the query cache's key carries the app's version; Settings says voice input on the Mac.
- Roadmap housekeeping at his word ("whatever is best for this app"): the model-profile row and the
  passages-by-reference row moved to Future Backlog with their reasons; the conversation-sync row and the
  query-cache row (filed 2026-09-26) pulled into 5.7 under release test 2.

## Active Constraints

- A push whose newest commit lacks `[ci skip]` starts the first 5.7 Xcode Cloud build. Ask him first.
- Hard-boundary files only when he names them. Named for 5.7: `RAGAppIntents.swift` (10 of 10 App Shortcut
  slots used; an eleventh breaks them all), `Info.plist`, `OpenIntelligence.entitlements`,
  `EngineSDKCompatibility.swift`, `project.pbxproj`, `WorkspaceSyncService.swift`, `FoundationModelSessionFactory.swift`
  (2026-10-14). Not named: `ChatMessage.swift`, the billing files, `SQLiteFullTextService.swift` (the preflight
  protects the whole file, which is why the query cache's old rows stay in its table), `FoundationModelRoutePolicy.swift`,
  `Package.swift`. He approved on 2026-10-14 the app group, extension targets, associated domains and Enhanced
  Security; each is blocked only by provisioning (Blockers).
- The provider internals (`CoreAISentenceEmbeddingProvider`, `CoreMLSentenceEmbeddingProvider`) are out of bounds.
- App Store Connect writes only at his word, through `zsh -ic`; never copy the key id, issuer or key anywhere.
  Asked on 2026-10-14 he said he had no idea, which is not a yes.
- Public repository and site: no personal plans in public files or row titles. Never delete a doc, a benchmark run
  directory or a Notion row (two duplicate rows wait for him to delete, under Blockers). No co-author or
  attribution lines in commits.
- One `xcodebuild` at a time on this 18 GB Mac, DerivedData outside `~/Documents`, `-jobs 1` with a memory guard.
  Start long jobs with the Bash tool's background option, never `&`. Never edit the repository between a run's
  start and its last copy of the tree (the scratchpad scripts copy it at the device build, the test build and the
  UI tests).
- Installing on his iPhone ends the running app: check `xcrun devicectl device info processes` first, never
  launch it remotely.
- Untracked and left alone: `.agents/skills/`, `.codex/hooks.json`, `.codex/hooks/`.

## Working Set

- Consent: `OpenIntelligence/Services/RAG/Orchestration/CloudConsentRelay.swift`; `RAGService.swift`
  (`bringAppForwardForConsent`, `ensureCloudConsentIfNeeded`, `cloudConsentDecision`, `abandonCloudConsentRequest`,
  `makePostRetrievalModelPlan`'s `canAskForConsent`); `RAGAppIntents.swift` (`AskControl.bringForward`,
  `AskActionRunner.foregroundRequest`, the five `supportedModes`); `OpenIntelligence/App/ContentView.swift`.
- Query cache: `RAGService.swift` (`queryCacheKey`, `appVersionForQueryCache`, `cachedResultsAreCurrent`, the
  lookup and write in `queryInternal`).
- Conversations: `OpenIntelligence/Services/Storage/EvidenceThreadStore.swift`.
- Crash reports: `OpenIntelligence/App/CrashReports.swift`, `MetricDiagnostics.swift`, `ContentView.swift`
  (`offerCrashReportIfAny`), `Features/Settings/AboutView.swift`, `Features/Billing/PrivacyPolicyView.swift`.
- Opened files: `OpenIntelligence/Features/Documents/Components/OpenedFilesSheet.swift`, `DocumentLibraryView.swift`.
- UI tests: `OpenIntelligenceUITests/ShortcutsSystemTests.swift`, `OpenIntelligence/App/UITestSupport.swift`,
  `OpenIntelligence.xcodeproj/xcshareddata/xcschemes/OpenIntelligenceUITests.xcscheme`; how to run them is in
  `Docs/ai/RUNBOOK.md`, "The actions through the system: the UI-testing target".
- Tests added: `CloudConsentRelayTests`, `QueryCacheKeyTests` (`OpenIntelligenceTests/Services/RAG/Orchestration/`),
  `CrashReportsTests` (`OpenIntelligenceTests/App/`), five in `EvidenceThreadStoreTests`.

## Verification (2026-10-14, output read)

- `86cc299` (cycles `i9`, `i9b`, `i9c`, `i10b`): device `BUILD SUCCEEDED`, `TEST BUILD SUCCEEDED`, Mac `BUILD SUCCEEDED`;
  test runs `i9` and `i9b` "The test runner hung before establishing connection" with no test run; `i9c` `Executed 1003 tests,
  with 5 tests skipped and 0 failures` (19:50 PT); after the test-only fix, `-only-testing:OpenIntelligenceTests/EvidenceThreadStoreTests`
  `Executed 12 tests, with 0 failures`; UI tests `Executed 2 tests, with 0 failures`.
- `b4618e0` (cycle `i8`): `Executed 997 tests, with 5 tests skipped and 0 failures`, UI tests 2 and 0 failures, device and Mac
  builds succeeded; `bash scripts/build_simulator_smoke.sh` from `/private/tmp/oi-src` -> `BUILD SUCCEEDED` (RUNBOOK has the command).
- `e7604f8` (cycle `i6`): `Executed 986 tests, with 5 tests skipped and 0 failures`, UI tests 2 and 0 failures.
- `2afc9f2` (cycle `i5`): `Executed 981 tests, with 5 tests skipped and 0 failures`; UI tests alone 2 and 0 failures.
- `63021fd` (cycle `i4b`): `Executed 981 tests, with 6 tests skipped and 0 failures` (the sixth, the silent-audio test, waits and
  skips on a newly made simulator).
- `python3 scripts/verify_doc_claims.py` -> every claim matches; `python3 .claude/codemap/codemap.py check` -> 0 errors, 0 warnings;
  `python3 scripts/secret_scan.py` -> nothing found; `grep -c "AppShortcut(" RAGAppIntents.swift` -> 10.
- After every push the newest Xcode Cloud run was still #485: no 5.7 build started.
- Not run: any of this on his iPhone or on a Mac in use.

## Blockers / Unknowns

- **Xcode on this Mac has no Apple account.** `xcodebuild -allowProvisioningUpdates` for the device build failed
  with "No Accounts: Add a new account in Accounts settings." That one gap blocks every remaining row that needs a
  new App ID capability or target: Enhanced Security, widgets, the Share Sheet entry (web clipper), Scan from the
  Lock Screen, the app group, and associated domains for universal links (which also need a file on the website, a
  public change made at his word). His approval for all of them was given on 2026-10-14.
- **App Store Connect, at his word:** nominating 5.7 for featuring, the product page header and search image,
  5.7's App Store notes on both records.
- **Two duplicate roadmap rows wait for him to delete:** https://app.notion.com/p/3f949a74d54f819d9fddd5a90087fb1e
  and https://app.notion.com/p/3fa49a74d54f815a98c9d84ea08d9287 (filed in error on 2026-10-14, retitled as a
  duplicate).
- **Nothing in 5.7 is closed on a device.** Each row's note and each CHANGELOG entry's evidence tag says what closes it.
- **The Simulator cannot check:** Private Cloud Compute (never chosen there), Find Passages and Check a Claim
  through the system (a library made there holds all-zero vectors, so their similarity floor drops everything), and
  Visual Intelligence.
- **A refuting review of the evening's work** (its findings are in the commit message of `86cc299`): each finding
  was traced to code and is fixed or recorded (whole-file conflicts for conversations are accepted, as for the chat
  history). One question it raised stays open: whether App Store validation accepts the audio-input entitlement key
  in the iOS binary (a macOS sandbox key; the first Xcode Cloud archive answers it).

## Exact Next Action

A device pass on his iPhone. Build the current tree for the device (`builddevice.sh` in the scratchpad, or the
RUNBOOK's "Building to the owner's iPhone"), and install it with `xcrun devicectl device install app --device
00008140-001130DA1863C01C <app>` only after `xcrun devicectl device info processes` shows OpenIntelligence is not
running. Then, in this order: (1) ask a question in a library, add a document that answers it, and ask the same
question again: the answer uses the new document (closes the query-cache row,
https://app.notion.com/p/3e749a74d54f810c86fefac905fa1d6f, with step 2: delete that document and ask once more;
nothing from it comes back); (2) open a PDF from Files with "Open in OpenIntelligence": the sheet shows it and Add to
Library imports it (https://app.notion.com/p/3f449a74d54f8184a7f8ff4afb6abeea); (3) with Private Cloud Compute
allowed in Settings and consent never given, ask Siri a Deep Think question across two documents: the app comes
forward with the consent sheet, and nothing is sent before a choice
(https://app.notion.com/p/3f449a74d54f81fdaac9e3f22ba32c84).
