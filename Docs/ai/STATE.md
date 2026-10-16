# Current State

Updated: 2026-10-15, 22:40 PT (5.7 is open and unreleased, no 5.7 build in TestFlight; since the evening handoff four commits, `7f13889` through `01fd0d1`, each pushed with `[ci skip]`; 5.6 has been live on iPhone, iPad and Mac since 2026-10-08, build 485)
Branch/worktree: `main`, primary checkout
Last verified commit: 01fd0d1

Earlier detail is in git: `git show 3c75a08:Docs/ai/STATE.md` (the morning of 2026-10-15) and older copies named there;
the long record through 2026-10-10 is `Docs/Archive/STATE_record_through_2026-10-10.md`.

## Objective

**5.7: JSON Lines import and the Apple surfaces that carry the app to other apps and people, mainly for iPhone
and iPad.** Named by the owner on 2026-10-08, widened on 2026-10-09 and 2026-10-10. On 2026-10-15 he said "legit go
until all 5.7 is finished, all backlogs, EVerything", then "Those 13 partly built is bugging me, I want them fixed
entirely please or brought to full effect, completely integrated". The work is the Native Surfaces catalogue's
unfinished rows (below), one at a time, each finished, checked and committed before the next.

## Status (2026-10-15, night)

| What | Where it stands |
|---|---|
| Tonight | `7f13889` the hardware X-Ray restyled (solid dark backing, white text, Dynamic Type up to 1.8x) and hidden from accessibility (SwiftUI `accessibilityHidden` plus UIKit `accessibilityElementsHidden` on its window); `32e5179` the Atlas names clusters and axis ends with `AtlasLabeling.contrast` instead of a ratio whose ties went alphabetically (his phone showed "Agent & Alert", "Annual & App"); `227b842` `DayOrdinals`: "September 30th" is searched as "September 30" (his question missed that day twice); `01fd0d1` the Verified badge, the response details and the rating and plan prompts read Fact Check's claims (`VerificationOutcome.from(gatingDecision:claims:)`; his phone showed Verified over "0 of 2 Verified"). |
| 5.7 source | All pushed (`git rev-list --count origin/main..HEAD` prints 0). Earlier on 2026-10-15: `d646afa` consent claims attributed to Apple; `cbaa772` Add to Library from Shortcuts with the app closed; `4c339e9` passages whose document is in no library; `e9de06d` Apple's token count in an answer's details; `e3d8831` delete with undo; `3b15d3f` the lab-science domain check reads whole words and only for lab questions; `eaccacc` an answer's heading is not a claim; `67857ee` money, dates and measurements read with Apple's data detector; `f3bf04f` QR codes and barcodes in a picture read by Vision; `af71989` swipe to delete; `7ac5c28` the "Your Library" widget (held out of the widget list until the app group); `c300bf8` the Atlas's work off the main thread. |
| Tests | 1,136 run, 0 failures, 6 skipped (two need Core AI, one layout case, the two scale benchmarks, and the QR read that Vision cannot do in the Simulator), 2026-10-15 at 22:26 PT on `01fd0d1`'s tree; device, iOS test and Mac builds succeeded. The first attempt on that build hung before connecting; the second, after a simulator reboot, ran (`Docs/ai/RUNBOOK.md`, "The test runner hung before establishing connection"). The three commits before it ran 1,133, 0 failures, at 22:07. |
| TestFlight | No 5.7 build. Every 5.7 push carried `[ci skip]`; a push whose newest commit lacks it starts one. |
| His iPhone | A development build of `01fd0d1` installed 2026-10-15 at 22:27 PT (the 21:14 install before it had everything through `94c4007` and the X-Ray restyle). On it at 21:16 he asked "What happened on September 30th" and got the wrong day; that trace is why `227b842` exists. Nothing tonight is checked there yet. |
| Catalogue | https://claude.ai/artifact/Thu24syf3CbVtpwhjAm4mJ, version 20: header at `01fd0d1`; the accessibility row says the morning audit mostly measured the X-Ray. |
| Accessibility audit | While the X-Ray's floating window is up, Apple's audit reports mostly that window. With the X-Ray off (written into the app's container plist; memory `accessibility-audit-blind-behind-the-x-ray`), Chat, Documents and Settings have 54, 44, 35 and 31 issues (light and dark, default and largest text): contrast on secondary text, fixed text sizes, clipping. `BenchmarkRuns/2026-10-15-accessibility-audit-xray-off/` (local). Notion row "With the X-Ray off, Apple's audit finds contrast, text-size and clipping issues on Chat, Documents and Settings", Future Backlog unless he pulls it into 5.7. |
| Test simulator | `OI 5.7 tests` `E2D49A91-0083-4BE1-831E-7675564CD7BA` (iPhone 18 Pro, iOS 27.0), made 2026-10-15 at about 19:05 after the previous one, `7652732F-...`, was deleted at 18:58 by a request CoreSimulator did not attribute. Simulators on this Mac are deleted between sessions: check `xcrun simctl list devices` first. |
| Demos session | Confirmed on its own demo library (a demo copy of `eaccacc`, simulator `64C1FEA3`) that the travel-insurance, hotel-address and check-out answers read Verified now. |

Unfinished catalogue rows, by what each waits on:

- **His approval already given, waiting for a session here (approved 2026-10-15):**
  - Mac (a throwaway library, deleted afterwards): "Run actions from Spotlight on the Mac", "Folder automations".
  - iPhone, driven through iPhone Mirroring, a development build installed only while the app is closed, any import
    into a throwaway library deleted afterwards, and he is told before each session: "Long jobs that continue in the
    background" (record the expiry conditions), "Import activity in the Mac menu bar and CarPlay", "The Atlas ends the
    app on a very large library" (open the Atlas on his large library), Siri "Delete Documents" with the app open and
    Undo (closes the undo roadmap row), the context window in Settings (a sample document says 4,096 tokens and this Mac
    measured 8,192), and the Verified badge.
- **His Apple account in Xcode (Settings, Accounts):** Widgets ("Your Library" is built and waits on the app group in the
  App ID), Share Sheet entry, Scan from the Lock Screen, Universal links (and a file on the website), Enhanced Security.
  The entitlements and project settings for these are held uncommitted (Active Constraints).
- **His word in App Store Connect:** product page header and search image (the upload was refused by the session's
  permission check), a featuring nomination (draft it, show it to him, send only at his word), accessibility labels
  (`POST /v1/accessibilityDeclarations`; read Apple's criteria for each label first and declare only what a test backs).
- **Apple:** the background inference entitlement ("not a valid entitlement" in Xcode; the iOS 27.0 SDK names only the GPU key).
- **Backlog with reasons (3):** large result sets by reference, dynamic instructions and profiles, one passage per embedding call (measured, nothing to change).

## Active Constraints

- A push whose newest commit lacks `[ci skip]` starts the first 5.7 Xcode Cloud build. Ask him first.
- Hard-boundary files only when he names them. Named for 5.7: `RAGAppIntents.swift` (10 of 10 App Shortcut
  slots used), `Info.plist`, `OpenIntelligence.entitlements`, `EngineSDKCompatibility.swift`, `project.pbxproj`,
  `WorkspaceSyncService.swift`, `FoundationModelSessionFactory.swift`, `SQLiteFullTextService.swift` (cached-search
  delete), `ChatMessage.swift` (token count). Not named: the billing files, `FoundationModelRoutePolicy.swift`,
  `Package.swift`.
- Held, uncommitted: `project.pbxproj` (Enhanced Security and the extension's entitlements file), 
  `OpenIntelligence/OpenIntelligence.entitlements` and the untracked
  `OpenIntelligenceLiveActivities/OpenIntelligenceLiveActivities.entitlements` (App Groups and Enhanced Security). The
  app's entitlements file signs the Mac build too, so the Mac profile needs the app group as well. Builds use a copy of
  the tree in `/private/tmp/oi-src` with HEAD's two held files put back (`git show HEAD:<file> > /private/tmp/oi-src/<file>`
  for `OpenIntelligence/OpenIntelligence.entitlements` and `OpenIntelligence.xcodeproj/project.pbxproj`); commit by
  name, never `git add .`. After `codemap.py index`, take the held file's line out of `Docs/ai/codemap/UNMAPPED.md`.
  The provisioning commit also adds `LibraryWidget()` to `OpenIntelligenceLiveActivitiesBundle` and replaces the
  "A widget." bullet in `WHATS_NEW.md`, `Docs/USER_CHANGELOG.md` and `OpenIntelligence/Resources/VersionHistory.md`
  with this one:
  `- **Widgets.**  Add OpenIntelligence to the Home Screen or the Lock Screen.  The small one asks a question, and the medium one has Ask, Add and Scan.  "Your Library" shows the library you have open and how many documents it holds, and on the medium size your last question in that library with the start of its answer, marked private so iOS can hide it on a locked phone.  Clearing the conversation clears it from the widget too.`
- App Store Connect writes only at his word, through `zsh -ic`; never copy the key id, issuer or key anywhere.
- Public repository and site: no personal plans in public files or row titles. Never delete a doc, a benchmark run
  directory or a Notion row. No co-author or attribution lines in commits.
- One `xcodebuild` at a time on this 18 GB Mac (other sessions build too: check `pgrep -x xcodebuild`), DerivedData
  outside `~/Documents`, `-jobs 1` with a memory guard (`GUARD_DISK_MB=2500` while free disk is near 12 GB).
- Edit `RAGService.swift` and other large Swift files by script: the post-edit formatter re-wraps a file Claude edits.
- This session's scripts (build, test with a simulator retry, Mac build, the App Group Simulator build) are in
  `/private/tmp/claude-501/-Users-gunnarhostetler-Documents-GitHub-OpenIntelligence/02a2f913-1d63-449c-8ccc-8c198da128bc/scratchpad`
  (`build57.sh`, `buildmac.sh`, `hold_provisioning.sh`, `widget_sim_build.sh`, `guard.inc`) until `/private/tmp` is
  cleared; the RUNBOOK's `## Test` section has the same commands written out.
- Installing on his iPhone ends the running app: check `xcrun devicectl device info processes` first.

## Working Set

- Widget: `OpenIntelligence/App/WidgetSnapshot.swift`, `OpenIntelligenceLiveActivities/IngestionLiveActivityWidget.swift`
  (`LibraryWidget` at the end), the hooks in `ContentView.swift`, `ChatScreen.recordForLibraryWidget`,
  `MessageBubbleV2.swift`, `ThreadSidebarView.swift`, `ContainerService+Focus.swift`.
- Atlas: `LibraryVisualizationEngine.swift` (`analyzePassages`, `ContentCategory.of`), `ProjectionService.swift`,
  `AdaptiveVisualizationsView.swift`, `Embedding3DView.swift`, `AtlasLabeling.swift` (`contrast`, `ranked`).
- Tonight: `MotherboardHUDView.swift` (`SiliconLegend`, `FloatingLegendWindowManager.ensureVisible`),
  `DayOrdinals.swift`, `RAGService.queryInternal` (top) and `executeFullRetrievalPipeline`, `VerificationOutcome.swift`,
  `ReviewPromptService.isVerified`.
- Undo: `PendingDocumentRemoval.swift`, `RAGService.scheduleRemoval`.

## Verification (2026-10-15, output read)

- `01fd0d1`: `cycle_full.sh r21` -> device `BUILD SUCCEEDED`, `TEST BUILD SUCCEEDED`, the runner hung before connecting,
  then `build57.sh test-without-building` after a simulator reboot -> `Executed 1136 tests, with 6 tests skipped and 0
  failures`; Mac `BUILD SUCCEEDED`. `7f13889`, `32e5179`, `227b842`: `cycle_full.sh r20` -> all three builds succeeded,
  `Executed 1133 tests, with 6 tests skipped and 0 failures`. `devicectl device install app` -> `App installed` 22:27:12.
- Atlas names, scratch probe on passages cut from his three Library 3 documents (`scratchpad/atlas-probe`): the paper's
  cluster "Activation & Activities" before, "Dopamine & Serotonin" after. Not yet seen in the app.
- `codemap.py check` at `01fd0d1` -> 0 errors, 48 warnings.

- `c300bf8` (Atlas): `build57.sh build-for-testing` -> `TEST BUILD SUCCEEDED`, no warning in the changed files;
  `test-without-building` -> `Executed 1127 tests, with 6 tests skipped and 0 failures`, `AtlasContentCategoryTests` 4
  passed, `AtlasLabelingTests` and `LibraryMapSampleTests` passed; `buildmac.sh` -> `BUILD SUCCEEDED` (18:10 PT).
- `7ac5c28` (widget): `TEST BUILD SUCCEEDED`; `Executed 1123 tests, with 6 tests skipped and 0 failures`,
  `WidgetSnapshotTests` 9 passed; Mac `BUILD SUCCEEDED` (17:36 PT). In the iOS 27 Simulator with the app group added to
  a scratch build (`widget_sim_build.sh` in the scratchpad): the app wrote `widget_snapshot.json` (library, 2 documents,
  then the question and the start of its answer); both sizes of "Your Library" drew it on the Home Screen; tapping it
  opened Chat; Clear Chat took the answer off at once.
- Timings behind the Atlas change, this Mac built -O on synthetic input: the old category search 3.5 s for 6,000
  passages; PCA 227 ms, UMAP 13.4 s, t-SNE 30.8 s on 6,000 x 512. Probes and output in
  `BenchmarkRuns/2026-10-15-atlas-main-thread/` (gitignored, this Mac only).
- Two refuting reviews (widget, Atlas) ran before the commits; every finding was fixed or answered in the commit.
- `python3 .claude/codemap/codemap.py check` -> 0 errors, 60 warnings (files changed since their slice was stamped by
  earlier commits).
- After each push `git rev-list --count origin/main..HEAD` printed 0; every push carried `[ci skip]`.
- Not run: anything on his iPhone after `af720fb`; the Mac app's actions from Spotlight; a folder automation.

## Blockers / Unknowns

- **Provisioning.** Xcode here has no Apple account ("No Accounts"), and `xcodebuild -allowProvisioningUpdates` with
  the App Store Connect key failed on 2026-10-14 with "Authentication failed: Make sure a bearer token was provided,
  it is properly configured and signed, and it has not expired". His sign-in in Xcode unblocks the provisioning rows.
- **Nothing in 5.7 is closed on a device.** The phone's build is `01fd0d1`.
- **Why the audit sees only the X-Ray's window** is not established; VoiceOver on the phone is the check that matters.
- **Two duplicate roadmap rows wait for him to delete:** https://app.notion.com/p/3f949a74d54f819d9fddd5a90087fb1e
  and https://app.notion.com/p/3fa49a74d54f815a98c9d84ea08d9287.

## Exact Next Action

Ask him what tonight's four fixes showed on his iPhone (build `01fd0d1`, installed 22:27): in a new chat, "What happened
on September 30th" in Library 3 should answer from the September 30 section; Library 3's Atlas should name its
clusters and axes with words most of each group shares; an answer whose Fact Check supports no claim should not show a
green Verified. If one did not, pull `Documents/pipeline_trace.log` with `xcrun devicectl device copy from` (memory
`building-to-gunnars-iphone`) and read that query's block; the day fix logs `[Query] Day read as a number for the search`.
Then ask whether the screens' accessibility issues go into 5.7; if he says yes, start with the 13 contrast failures in
light at the default size (`BenchmarkRuns/2026-10-15-accessibility-audit-xray-off/audit-light-large-xray-off.txt`).

The Mac and phone sessions are paused, not cancelled. He approved them, then paused the Mac one a few minutes in
("lets just not do this", then "i didnt say dont ever do this. i just said for now"). Pick them up when he says; right
before starting, tell him in a line what will open on his screen. The rows waiting on those sessions are listed under
"His approval already given" above.
