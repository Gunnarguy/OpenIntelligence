# Current State

Updated: 2026-10-15, 18:15 PT (5.7 is open and unreleased, no 5.7 build in TestFlight; the 5.7 work since the last handoff is in 12 commits, `3c75a08` through `c300bf8`, each pushed with `[ci skip]`; 5.6 has been live on iPhone, iPad and Mac since 2026-10-08, build 485)
Branch/worktree: `main`, primary checkout
Last verified commit: c300bf8

Earlier detail is in git: `git show 3c75a08:Docs/ai/STATE.md` (the morning of 2026-10-15) and older copies named there;
the long record through 2026-10-10 is `Docs/Archive/STATE_record_through_2026-10-10.md`.

## Objective

**5.7: JSON Lines import and the Apple surfaces that carry the app to other apps and people, mainly for iPhone
and iPad.** Named by the owner on 2026-10-08, widened on 2026-10-09 and 2026-10-10. On 2026-10-15 he said "legit go
until all 5.7 is finished, all backlogs, EVerything", then "Those 13 partly built is bugging me, I want them fixed
entirely please or brought to full effect, completely integrated". The work is the Native Surfaces catalogue's
unfinished rows (below), one at a time, each finished, checked and committed before the next.

## Status (2026-10-15, evening)

| What | Where it stands |
|---|---|
| 5.7 source | All pushed (`git rev-list --count origin/main..HEAD` prints 0). Since the morning handoff: `d646afa` consent claims attributed to Apple; `cbaa772` Add to Library from Shortcuts with the app closed; `4c339e9` passages whose document is in no library; `e9de06d` Apple's token count in an answer's details; `e3d8831` delete with undo; `3b15d3f` the lab-science domain check reads whole words and only for lab questions; `eaccacc` an answer's heading is not a claim; `67857ee` money, dates and measurements read with Apple's data detector; `f3bf04f` QR codes and barcodes in a picture read by Vision; `af71989` swipe to delete; `7ac5c28` the "Your Library" widget (held out of the widget list until the app group); `c300bf8` the Atlas's work off the main thread. |
| Tests | 1,127 run, 0 failures, 6 skipped (two need Core AI, one layout case, the two scale benchmarks, and the QR read that Vision cannot do in the Simulator), 2026-10-15 at 18:09 PT on `c300bf8`'s tree; iOS test build and Mac build succeeded. The first attempt on that build hung before connecting; the second, after a simulator reboot, ran (the cause is in `Docs/ai/RUNBOOK.md`, "The test runner hung before establishing connection"). |
| TestFlight | No 5.7 build. Every 5.7 push carried `[ci skip]`; a push whose newest commit lacks it starts one. |
| His iPhone | A development build of `af720fb` installed 2026-10-15 at 09:39 PT; nothing after it. |
| Catalogue | https://claude.ai/artifact/Thu24syf3CbVtpwhjAm4mJ, version 18: 77 built, 3 checked, 4 partly, 8 needing him, 4 not started (96 rows with a status, 22 more the app already had). |
| Test simulator | `OI 5.7 tests` `7652732F-FCEA-47A3-B345-7EC57B9EFE67` (iPhone 18 Pro, iOS 27.0), shut down. It holds a scratch build's "Your Library" widget on its Home Screen. Simulators on this Mac are deleted between sessions: check `xcrun simctl list devices` first. |
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
  `AdaptiveVisualizationsView.swift`, `Embedding3DView.swift`.
- Undo: `PendingDocumentRemoval.swift`, `RAGService.scheduleRemoval`.

## Verification (2026-10-15, output read)

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
- **Nothing in 5.7 is closed on a device.** The phone's build is `af720fb`.
- **Two duplicate roadmap rows wait for him to delete:** https://app.notion.com/p/3f949a74d54f819d9fddd5a90087fb1e
  and https://app.notion.com/p/3fa49a74d54f815a98c9d84ea08d9287.

## Exact Next Action

Start the Mac session he approved on 2026-10-15 ("Yes, throwaway library"), for the catalogue rows "Run actions from
Spotlight on the Mac" and "Folder automations":

1. Build the Mac app unsigned, so it is not sandboxed and keeps its data in
   `~/Library/Application Support/OpenIntelligence`, which holds only "General" (empty) and "Home" (ten sample
   documents from a 2026-10-01 demo), not his libraries: in `/private/tmp/oi-src` (the copy above),
   `xcodebuild build -project OpenIntelligence.xcodeproj -scheme OpenIntelligence -configuration Debug
   -destination 'platform=macOS' -derivedDataPath /private/tmp/oi-build-mac -jobs 1 MARKETING_VERSION=5.7
   CODE_SIGNING_ALLOWED=NO`. Then `open /private/tmp/oi-build-mac/Build/Products/Debug/OpenIntelligence.app` and make a
   library named "Folder test".
2. With the computer-use tools (request access for the app, Shortcuts and Finder; Spotlight needs full-screen control):
   run one of the app's actions from Spotlight, then in Shortcuts make a folder automation ("When files are added to"
   a scratch folder) that runs Add to Library into "Folder test", drop a text file in the folder, and confirm the file
   is in the library and the action returned its result.
3. Delete the automation, the "Folder test" library and the scratch folder, quit the app, and record what was seen in
   the two catalogue rows, CHANGELOG and the roadmap rows. If macOS does not offer an unsigned build's actions, record
   that and use a development-signed build only after asking him, since signing moves it into his app container.

Then the phone session (tell him first): install a development build while the app is closed, and check the items
listed above under "His approval already given".
