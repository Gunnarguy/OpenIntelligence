# Current State

Updated: 2026-11-03 (5.8 open; `fb225053` pushed and built as Xcode Cloud build 488, VALID on iOS and macOS, not attached to either record. Later 5.8 work is committed locally with `[ci skip]`. 5.7 is live on iPhone, iPad and Mac since 2026-10-22, build 487. The 5.7
closeout record, with its open device checks, is in git: `git show a27abbe8:Docs/ai/STATE.md`.)
Branch/worktree: `main`, primary checkout
Last verified commit: 77aeedfa

## Objective

**5.8: make paying worth more, and make every answer checkable.** A citation that shows its passage in every kind of document,
watched folders and a clearer plans screen are built and tested in the working tree, and wait on a device check. The App Store numbers and the ranked list behind this are in auto memory
`more-behind-the-paywall-is-next.md`.

## Status

| What | Where it stands |
|---|---|
| Watched folders | Built, tests pass, committed. Row `40c49a74d54f818a9311cb37fbc4db3a`, In Progress. Closes on a real iPhone and Mac |
| Citations in every file type (`SourceTextView.swift`, `SourceMatchBanner`) | Built, tests pass, committed. Row `40c49a74d54f81c199dccc5e6b911e38`, In Progress. audio not measured (no recognizer in the Simulator) |
| Library Settings | Two bugs fixed, neither with a test (Save after the library changed; opening it saving a size). The overclaiming copy is unfixed: row `40c49a74d54f81fb8e6ef32ac1549e2b`. Run `oi-claim-audit` first |
| Plans screen ("What you get", `PlanBenefits.swift`) | Done, tests pass, committed |
| iCloud bullet on the plan cards | **Held back on purpose.** Waits for the two-device check on row `3ca49a74d54f8103b69be921f0335171`. The copies were 497 on 2026-11-03 and 0 after the Mac's first launch of `5c13a375` (see the next row), so the baseline is now 0 |
| Mac launch freeze and orphaned conflict copies (`WorkspaceSyncService.swift`, named by him 2026-11-03) | Committed `5c13a375`. `waitUntilSyncFilesAreFree` (six lists, off the main thread, 20 s limit) runs before the pass at the existing `await` after `prepareWorkspaceDownloads`; `removeOrphanedConflictCopies` runs last in `synchronizeConfiguredLibraries`. Mac launch 21:34 UTC: `removed 497, failed 0`, waits 3 to 9 ms, no claim wait on the main thread. Freeze row `40d49a74d54f81779bfaea8b13628d5a` In Progress: closes on a launch that logs a `sync.waitForFiles` over 500 ms while `sample` shows the main thread in its run loop. Not done from the review: a follow-up pass when the app writes during the wait (the suppressed `.localWorkspaceDidChange`), and the pass's own coordinated writes still run on the main thread (about 3% of samples during an import) |
| Rebuild loop between devices (row `40d49a74d54f81dbb75bd6daf9309f50`, In Progress) | Committed `77aeedfa`: a rebuild keeps each document's id, record and file (`removeDocument(forRebuild:)`, `addDocument(documentId:)`), skips the plan limit, starts large files over, keeps going past a failure, no longer switches the open library; banner shows "Rebuilding n of m" / "Waiting". RebuildKeepsDocumentIdTests 2 of 2, twice. **The Mac's `/Applications` copy is still the old build and still runs the loop**: the new one is `/private/tmp/oi58-mac-dd/Build/Products/Debug/OpenIntelligence.app`. Lost on his iPhone: MoreMacintoshToolbox.pdf (Library 3), a Library 2 PDF, AAMI-ST79-2017-COMPLETA-ESPANOL.pdf (library 65557D64, deleted); copies in `~/Downloads/OpenIntelligence recovered 2026-11-03` for him to re-import. Closes on both devices running it with no `Wiping orphaned vector database chunks` on the other device after a rebuild |
| Sync passes once a second during an import (row `3ca49a74d54f81a6b8c1e4827a6585fa`) | `ObservedChangeThrottle` in `77aeedfa` (5 s per trigger, no overlap). Rate not re-measured. The triggers inside `WorkspaceSyncService.swift` (watcher seeing a pass's own writes, 2 s debounce) are unchanged and need him to name the file |
| Blank Chat while switching libraries | Cause not established. Removed the rebuild's own library switch, which landed in the same second; the journal now records `chat.appear`, `chat.disappear`, `library.setActive` |
| Tour tips and Watched Folder copy | Rewritten in `77aeedfa` (41 tips up to 220 characters, `TourTipTests`) |
| Per-library Face ID lock | Built, reviewed and **taken out** 2026-11-02 at the owner's word. Copy in `Growth/library-lock-attempt-2026-11-02/`. An app-wide lock is not built: iOS offers Require Face ID free |
| App Store Connect | 5.8 records exist on iOS and macOS, PREPARE_FOR_SUBMISSION, release AFTER_APPROVAL. Build 488 (`fb225053`) is VALID on both and attached to neither: he wants more in 5.8 before another build, to save Xcode Cloud hours |
| Rating request (`ReviewPromptService.swift`) | Done 2026-11-03: Apple's sheet only, on the first verified or third finished answer, once per version, 14 days apart; the custom "Enjoying" alert is gone (App Review 5.6.1). Row `40d49a74d54f81b8a754e342bf1d90d0`, In Progress. Closes when a development build on his iPhone shows the sheet |
| Lock Screen and Watch cards (`IngestionLiveActivityService.dismissFinished(importIsMoving:)`) | Done 2026-11-03: on foreground an import card stays only while an import moves. Row `40d49a74d54f818f92cdfe37eb7164ed`, In Progress. Cause read from code, not seen on a device |
| Sample Product Guide | Updated 2026-11-03 for Paste, Share, "Open in", icon drop, Watch a Folder, highlighted citations |
| Multi-file imports (`RAGService.shouldDeferEnrichment`) | Done 2026-11-03: a file's overview, tags and suggested questions wait while other files are queued. Row `40d49a74d54f81a9bcaec77f3061c10e` |
| Atlas card axis labels (`AxisLabelInsets.boxes`) | Done 2026-11-03: labels clear the cluster box only where they would cover it |
| Device event log (`VerificationJournal.swift`, `scripts/phone_evidence.py`) | Done 2026-11-03, Debug builds only. Row `40d49a74d54f81b59f23ce86c142e2a2`. The phone has the build (10:33). First pull: trace and MetricKit copied, no events yet (app not opened since install). `RAGAppIntents.swift`'s 12 intents covered too, at his word (the file named 2026-11-03), 10 App Shortcuts unchanged |
| 107 open 5.0 to 5.7 rows | Sorted 2026-11-03: 19 checkable headless, 20 Mac by hand, 61 iPhone, 7 his. None already evidenced. 32 iPhone rows have rules in `scripts/phone_evidence_rules.json` |
| 5.8 copy | Committed `55366647`: What's New (12 items), `Docs/USER_CHANGELOG.md` and its byte copy `VersionHistory.md`, `WHATS_NEW.md`, both platforms' `release_notes.txt` (Mac 2,062 characters, iPhone and iPad 2,143) and `promotional_text.txt`, the `### 5.8` entry in `APP_STORE_METADATA_HISTORY.md`. **Not pushed to App Store Connect**: `fastlane push_metadata version:5.8` waits for his word, and the copy must grow with anything else that lands in 5.8 |

## Active Constraints

- **Done 2026-10-21 at his word ("do consent fix first"):** a request with no `ModelExecutionPlan` now runs on the
  device (`FoundationModelRoutePolicy.determineRoute`), so nothing reaches Private Cloud Compute without the consent step.
  `PlanlessRouteTests` pins it. Not run on a device. A question to an empty library longer than the device window now
  stays on the device and may fail for length (read in code, not run). Still his call: whether a public roadmap row is
  filed for it (none was). The developer diagnostics hub's "Maximum Reasoning" row can now only read N/A.
- Every commit ends with `[ci skip]` until he asks for a build (2026-11-03: "dont wanna waste those xcode cloud hours").
- Protected files he named on 2026-10-18: `project.pbxproj`, `WorkspaceSyncService.swift`, `BNNSVectorDatabase.swift`,
  `FoundationModelRoutePolicy.swift`, `FoundationModelSessionFactory.swift` ("Must be done flawlessly"). `ChatMessage.swift`,
  `RAGAppIntents.swift`, `EntitlementStore.swift` and `KnowledgeContainer.swift`'s route were not named.
- App Store Connect writes and public pages only at his word. Never delete docs, benchmark runs, Notion rows or agent
  histories; no co-author lines; commit by name; leave `.agents/skills/`, `.codex/hooks*`, `.codex/config.toml` and
  `scripts/run_quality_matrix.py` (uncommitted on purpose) alone; edit Swift by script.
- Another session (PostDesk, "Demos") also commits docs in this checkout and does not push: before pushing, check every
  commit since `origin/main` for `[ci skip]`, no co-author line and docs-only paths.
- One `xcodebuild` at a time; stop only processes this session started. Don't build while World of Warcraft is open.
  `build57.sh` stops its own build when free disk falls under `GUARD_DISK_MB` (pass 1500) or free memory under 15%.

## Working Set

- `OpenIntelligence/Features/Documents/WatchedFolders/`: `WatchedFolder.swift` (model, pure decisions, store),
  `WatchedFolderService.swift` (checks; `settle` is the part that removes documents), `WatchedFolderSection.swift` (Library Settings).
- `OpenIntelligence/App/ContentView.swift`: starts checks. `RAGService+Streaming.swift`, `RAGService+TextStreaming.swift`: record `fileHash`.
- `OpenIntelligence/Features/Chat/Response/SourceTextView.swift`, `SourcePageView.swift` (`PassageLocator.exactRange`, `withoutImportLabels`, `cellValues`), `OpenIntelligenceTests/Features/Chat/SourceTextViewTests.swift` (prints SOURCE-MATCH-RATE).
- `OpenIntelligence/Features/Billing/PlanBenefits.swift`: every plan bullet. `PlanUpgradeEntryPoint.swift`: `.watchedFolder`.
- `OpenIntelligenceTests/Features/Documents/WatchedFolderTests.swift`, `Features/Billing/PlanBenefitsTests.swift`.
- `Docs/USER_CHANGELOG.md` and its copy `OpenIntelligence/Resources/VersionHistory.md` must match exactly, or `VersionHistoryTests` fails.
- Test simulator `OI 5.8 tests` `603FB180-AB3B-4175-A051-336FA55A0F78`. Builds copy the tree to `/private/tmp/oi58-src`, DerivedData
  `/private/tmp/oi58-dd`, `-jobs 1` after a change to anything `RAGService` compiles.

## Verification (2026-11-03, output read)

- Tree of `5c13a375`: `SyncFileWaitTests` 4 of 4, `OrphanedConflictCopyTests` 6 of 6, then `xcodebuild test-without-building` -> 1,450 tests, 8 skipped, 0 failures (527 s); Mac `xcodebuild build` -> BUILD SUCCEEDED. The Mac build (`/private/tmp/oi58-mac-dd/Build/Products/Debug/OpenIntelligence.app`) was launched from there, not `/Applications`; event log and `sample` results are in the status table.
- Tree of `55366647`: `VersionHistoryTests` 3 of 3, `WhatsNewCoverageTests` 4 of 4.
- Tree of `77aeedfa`: `xcodebuild test-without-building` -> 1,455 tests, 8 skipped, 0 failures (517 s); Mac `xcodebuild build` -> BUILD SUCCEEDED; iPhone build installed (5.8 build 150).

- 2026-11-03, final tree `3c42daa9`: `xcodebuild test-without-building` -> 1,428 tests, 8 skipped, 0 failures (481 s; 495 s before the trace kept every category). `python3 scripts/phone_evidence.py` against the phone -> pulled the trace and MetricKit, 0 events.
- `xcodebuild test-without-building` with the rating and Live Activity changes -> 1,415 tests, 8 skipped, 0 failures. After the Product Guide edit: `SampleQuestionHeadingsTests`, `SampleDocumentCopyCleanupTests`, `ImportLiveActivityRuleTests`, `ReviewPromptServiceTests` -> 25 of 25.

## Verification (2026-11-02, output read)

- `xcodebuild test-without-building` on the final tree, simulator above -> 1,405 tests, 8 skipped. The last full run had 2 failures, both `SourceLookupImportTests` expecting `.doc` and `.m4a` to import; that test was corrected and passed alone afterwards, with the rest unchanged.
- `WatchedFolderTests`: 16 of 16, through a real folder and the import queue, including the person's own document surviving an
  edit, two files sharing bytes, a deleted file's name reused, and Stop Watching during a check.
- A sandboxed probe made and resolved a read-only security-scoped bookmark with the current entitlements, on a folder in its own
  container. A folder chosen in the picker on a real Mac is not tested.
- `python3 scripts/verify_doc_claims.py` -> all match. `python3 scripts/secret_scan.py` -> clean.
- `SourceScreensUITests` (`xcodebuild test -scheme OpenIntelligenceUITests`) -> 4 of 4: citation screen at default and largest text, Library Settings to the plans screen, a watched file arriving with the panel small.
- Measured by `SourceLookupImportTests` with files in `/private/tmp/oi58-fixtures`: Word, PowerPoint, Markdown, HTML, RTF, Swift, an image's OCR text all exact. CSV 5 of 7, Excel 3 of 5. Numbers are in `CHANGELOG.md`.
- `xcodebuild build -destination platform=macOS` -> BUILD SUCCEEDED.
- Not run: anything on a real device, purchase and restore in `OpenIntelligence-StoreKitTesting`, dark mode.

## Blockers / Unknowns

- The system folder picker, a relaunch with a saved bookmark, a transcript citation, and iCloud Drive placeholders need a device. `.name.icloud` handling in
  `WatchedFolderService.walk` is untested.
- Whether a saved answer's citation opens after its document is replaced was not tried; the footer says it may not.
- Known limits: a replacement can be named `name-2.ext` until the next change; a staged copy of a failed import waits for the orphan sweep.

## Exact Next Action

After he has used the phone build for a while: `python3 scripts/phone_evidence.py --since 2026-11-03T18:33`, close every
PASS row in Notion with its proof lines quoted, and tell him the FAIL rows. Then run the 12 ready headless checks from
the 2026-11-03 sort (saved conversation [S13]+, Glossary PCC screenshots, Export, Siri tips, answer-card taps, no-passage
self-heal, paragraph entities, no-Apple-Intelligence samples, PDF GPU log, Mac SpeechTranscriptionTests, 5.0 blocked
rebuild, MMR and few-spaces benchmarks). The Mac-by-hand rows and the 420-reloads count wait for him to say the screen is
free. No push, App Store Connect write or Xcode Cloud build without his word.
