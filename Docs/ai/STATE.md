# Current State

Updated: 2026-10-14, 11:37 PT (5.7 is open and unreleased, no 5.7 build in TestFlight; the system surfaces of 2026-10-14 are in `131f989`, pushed with `[ci skip]`; 5.6 has been live on iPhone, iPad and Mac since 2026-10-08, build 485)
Branch/worktree: `main`, primary checkout
Last verified commit: 131f989

Earlier detail is in git: `git show c73b3b9:Docs/ai/STATE.md` (the storage change) and
`git show 5bf6860:Docs/ai/STATE.md` (2026-10-13), and the long record through 2026-10-10 is
`Docs/Archive/STATE_record_through_2026-10-10.md`.

## Objective

**5.7: JSON Lines import and the Apple surfaces that carry the app to other apps and people, mainly for iPhone
and iPad.** Named by the owner on 2026-10-08, widened on 2026-10-09 (the Apple model APIs) and 2026-10-10 (the
whole import path, very large libraries). On 2026-10-14 he asked whether the Native Surfaces Catalogue and the
open Notion rows were done, and said "5.7 is to be massive": build the rest of the catalogue and the open rows
into 5.7, everything that can live inside the app first.

## Status (2026-10-14)

| What | Where it stands |
|---|---|
| 5.7 source | `131f989` holds the system surfaces below and the fixes from two refuting reviews; pushed. `git rev-list --count origin/main..HEAD` prints 0 when everything is pushed. |
| Tests | 938 run, 0 failures, 5 skipped (two need Core AI, one layout test, the two scale benchmarks), 2026-10-14 at 11:24 PT, with a device build before and a Mac build after. After two last edits (`AskActionRunner.spoken` made nonisolated, the user changelogs), the 26 tests they touch passed on the committed tree at 11:30 PT, with a device build and a Mac build. |
| TestFlight | No 5.7 build. Every 5.7 push carried `[ci skip]`; a push whose newest commit lacks it starts one. |
| His iPhone | Which 5.7 build is installed is not known from here: every 5.7 build reads 5.7 (150). As of 2026-10-13 it was `ec4fb74`'s. The build of `131f989`'s tree is staged at `/private/tmp/oi-install/OpenIntelligence.app` (built 2026-10-14 at 11:28 PT), and a script of this session polls to install it the first time the app is absent from two process listings in a row; it gives up after six hours and never launches the app. Its output is `install_when_idle.out` in `/private/tmp/claude-501/-Users-gunnarhostetler-Documents-GitHub-OpenIntelligence/02a2f913-1d63-449c-8ccc-8c198da128bc/scratchpad/` (`INSTALLED` with a time when it did). |
| Roadmap | 112 rows on `v5.7`: 88 In Progress, 24 To Do, none Completed (queried 2026-10-14 after the updates). 22 rows moved to In Progress that day with a dated note naming `131f989` and what closes each; 7 of them came from the backlog with the scope test that admits them. One row added: https://app.notion.com/p/3f949a74d54f81bfb4c0d0a0cd179326 (a changed setting reverted on relaunch). |
| Catalogue | https://claude.ai/artifact/Thu24syf3CbVtpwhjAm4mJ, updated 2026-10-14 with each row's state. |

## Completed (2026-10-14)

Built, compiled for iPhone and Mac, and in the suite, none of it seen on a device:

- Handoff for chat, Documents and a document's page; on-screen items named to Siri (`appEntityIdentifier`).
- Spotlight: documents and libraries as `IndexedEntity` items; entries no longer expire and leave with their
  document wherever it was deleted (`SpotlightIndexService.documentsLoaded`, a device-local list); the
  Settings switch's off removes every entry, saved activity and Open Library donation; the first launch of
  5.7 writes every entry again whole, with its preview read from the full-text store.
- Siri: "Search OpenIntelligence for" (`SearchInAppIntent`, 27); Open Library donations while Spotlight
  Indexing is on; the ask actions cancellable (26.4) and long-running with progress (27).
- A Focus filter for libraries; three controls (Ask, Add, Scan) on iPhone and iPad; a Live Activity for a long
  answer; the Mac's Services menu (text and Finder files); Quick Look on a document's page; an answer shared
  as an image card; link previews in the share sheet; dictation into the chat field (iPhone and iPad);
  "Scan a Document" with Apple's document scanner.
- Fixed on the way: a changed setting is saved with its new value (it reverted on relaunch); a PDF's page rows
  take their numbers from the pages with text (a blank page shifted every later row and page citation); a
  one-page batch keeps its row; a failed read of the document records changes nothing.

`CHANGELOG.md`, section 5.7, has one entry per change with its evidence and what closes it.

## Active Constraints

- A push whose newest commit lacks `[ci skip]` starts the first 5.7 Xcode Cloud build. Ask him first.
- Hard-boundary files only when he names them. Named for 5.7: `RAGAppIntents.swift` (10 of 10 App Shortcut
  slots used; an eleventh breaks them all), `Info.plist`, `OpenIntelligence.entitlements`,
  `EngineSDKCompatibility.swift`, `project.pbxproj`, `WorkspaceSyncService.swift`, the tool registry work.
  Not named: `ChatMessage.swift`, the billing files, `SQLiteFullTextService.swift` (the preflight protects the
  whole file), `FoundationModelSessionFactory.swift`, `FoundationModelRoutePolicy.swift`, `Package.swift`.
  `BNNSVectorDatabase.swift`: read-side additions on 2026-10-13 that he has not confirmed; nothing further
  without his word. A new entitlement (the Mac's audio input) is a new capability: ask.
- App Store Connect writes only at his word, through `zsh -ic`; never copy the key id, issuer or key anywhere.
- Public repository and site: no personal plans in public files or row titles. Never delete a doc or a
  benchmark run directory. No co-author or attribution lines in commits.
- One `xcodebuild` at a time on this 18 GB Mac, DerivedData outside `~/Documents`. The post-edit format hook
  rewrites whole Swift files it has not formatted before; apply edits to those by script.
- Installing on his iPhone ends the running app: check `xcrun devicectl device info processes` first, never
  launch it remotely.
- Untracked and left alone: `.agents/skills/`, `.codex/hooks.json`, `.codex/hooks/`.

## Working Set

- `OpenIntelligence/Services/Infrastructure/Background/SpotlightIndexService.swift`, `QueryLiveActivityService.swift`,
  `BackgroundTaskService.swift`; `OpenIntelligence/Services/Agentic/RAGAppIntents.swift` (`AskControl`,
  `AskActionRunner`), `SearchInAppIntent.swift`, `LibraryFocusFilterIntent.swift`, `AppNavigationRequest.swift`
  (`AppActivity`, `AppLink`); `OpenIntelligence/App/ContentView.swift` (`show`, `route`, the Spotlight switch),
  `MacServicesProvider.swift`, `OpenIntelligenceApp.swift`.
- `OpenIntelligence/Features/Chat/Conversation/VoiceDictation.swift`, `ChatComposerV2.swift`, `ChatScreen.swift`,
  `SiriDonations.swift`, `SharePreviewItem.swift`; `Features/Chat/Response/AnswerCardRenderer.swift`;
  `Features/Camera/SystemDocumentScanner.swift`; `OpenIntelligenceLiveActivities/IngestionLiveActivityWidget.swift`.
- `OpenIntelligence/Services/Infrastructure/Configuration/SettingsStore.swift` (the save after the set) and
  `OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift` (`numberedPages`, `storeText`).
- `Docs/PRIVACY_AND_ROUTING.md`, "What the app hands to the system"; the Atlas; `Docs/INGESTION_PIPELINE.md`.
- Scratchpad drafts for the next batch (not in the repository): `VisualDocumentSearch.swift`.

## Verification (2026-10-14, output read)

- Device build, simulator test build, the suite and the Mac build, one after another (cycle `f3`) ->
  `BUILD SUCCEEDED`, `TEST BUILD SUCCEEDED`, `Executed 938 tests, with 5 tests skipped and 0 failures` (11:24 PT),
  `BUILD SUCCEEDED` (11:27 PT). Simulator `OI 5.7 tests`, `DE0883DB-2849-47F9-93AE-23C4E880FDED`.
- On the committed tree (cycle `f4`): device build `BUILD SUCCEEDED` with no `spoken` isolation warning,
  `Executed 26 tests, with 0 failures` (AskControlTests, AppLinkTests, AppShortcutsProviderTests,
  VersionHistoryTests, WhatsNewCoverageTests, SpotlightItemsTests, SettingsPersistenceTests), Mac `BUILD SUCCEEDED`
  (11:30 PT).
- `python3 scripts/verify_doc_claims.py` -> 871 claims checked, all match. `python3 .claude/codemap/codemap.py check`
  -> 0 errors, 0 warnings. `python3 scripts/secret_scan.py` -> nothing found.
- After the push, the newest Xcode Cloud run was still #485 (2026-10-08): no 5.7 build started.
- Not run: any of this on his iPhone or a Mac in use. The whole session's work is build- and suite-verified only.

## Blockers / Unknowns

- **Nothing in 5.7 is closed.** Every row waits on a device. For today's surfaces the checks are in each
  row's note and each CHANGELOG entry's evidence tag; the older checks are in `git show 5bf6860:Docs/ai/STATE.md`
  under Blockers and Exact Next Action.
- **Owner decisions open:** the Mac's microphone (the audio-input entitlement, a new capability); naming
  `FoundationModelSessionFactory.swift` (dynamic profiles, the system OCR and barcode tools); provisioning for
  an app group, associated domains and new extension targets (Share Sheet entry, widgets, universal links);
  a read-only viewer for files opened from outside versus the current Open In import; Evidence Threads sync
  versus conflict copies; confirming the `BNNSVectorDatabase.swift` additions of 2026-10-13.
- **Not seen working:** whether Core Spotlight moves an entry's expiry on an update (avoided by writing entries
  whole); whether a Live Activity started as the app leaves the front succeeds; whether `intent.progress` read
  before `performBackgroundTask` is the object the system shows.
- **Simulators on this Mac are deleted between sessions.** Expect to make one before any test run.

## Exact Next Action

Build the Visual Intelligence search, the first not-started row of the catalogue that needs nothing from him.
In `OpenIntelligence/Features/Camera/VisualDocumentSearch.swift` (the app target only: `Services/Agentic` also
compiles into the engine framework), an `IntentValueQuery` whose `values(for: SemanticContentDescriptor)` reads the
picture's text with Vision's `RecognizeTextRequest`, adds the system's `labels`, searches
`SQLiteFullTextService.shared.searchChunks` across every library and returns at most 100 `OIDocumentEntity`
(document names first), plus an `@AppIntent(schema: .visualIntelligence.semanticContentSearch)` intent that posts
`.searchFor` with the same words for "More results". Apple's guide (read 2026-10-14) allows one such query per app;
the app has none. A draft is in the scratchpad named above, under `next/`, while `/private/tmp` survives. Then the
rest of the not-started rows in the catalogue that live inside the app: delete actions with confirmation, a Mac menu
bar item, list reordering and swipe actions, snippet buttons on Siri's answer card.
