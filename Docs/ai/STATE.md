# Current State

Updated: 2026-11-02 (5.8 open, nothing committed. 5.7 is live on iPhone, iPad and Mac since 2026-10-22, build 487. The 5.7
closeout record, with its open device checks, is in git: `git show a27abbe8:Docs/ai/STATE.md`.)
Branch/worktree: `main`, primary checkout
Last verified commit: a27abbe8

## Objective

**5.8: make paying worth more, and make every answer checkable.** A citation that shows its passage in every kind of document,
watched folders and a clearer plans screen are built and tested in the working tree, and wait on a device check and his word to commit. The App Store numbers and the ranked list behind this are in auto memory
`more-behind-the-paywall-is-next.md`.

## Status

| What | Where it stands |
|---|---|
| Watched folders | Built, tests pass, uncommitted. Row `40c49a74d54f818a9311cb37fbc4db3a`, In Progress. Closes on a real iPhone and Mac |
| Citations in every file type (`SourceTextView.swift`, `SourceMatchBanner`) | Built, tests pass, uncommitted. Row `40c49a74d54f81c199dccc5e6b911e38`, In Progress. audio not measured (no recognizer in the Simulator) |
| Library Settings | Two bugs fixed, neither with a test (Save after the library changed; opening it saving a size). The overclaiming copy is unfixed: row `40c49a74d54f81fb8e6ef32ac1549e2b`. Run `oi-claim-audit` first |
| Plans screen ("What you get", `PlanBenefits.swift`) | Done, tests pass, uncommitted |
| iCloud bullet on the plan cards | **Held back on purpose.** Waits for the two-device check on row `3ca49a74d54f8103b69be921f0335171`; baseline 519 conflict copies, unchanged on 2026-11-02 |
| Per-library Face ID lock | Built, reviewed and **taken out** 2026-11-02 at the owner's word. Copy in `Growth/library-lock-attempt-2026-11-02/`. An app-wide lock is not built: iOS offers Require Face ID free |
| App Store Connect | No 5.8 record exists. He creates it |

## Active Constraints

- **Done 2026-10-21 at his word ("do consent fix first"):** a request with no `ModelExecutionPlan` now runs on the
  device (`FoundationModelRoutePolicy.determineRoute`), so nothing reaches Private Cloud Compute without the consent step.
  `PlanlessRouteTests` pins it. Not run on a device. A question to an empty library longer than the device window now
  stays on the device and may fail for length (read in code, not run). Still his call: whether a public roadmap row is
  filed for it (none was). The developer diagnostics hub's "Maximum Reasoning" row can now only read N/A.
- A push whose newest commit lacks `[ci skip]` starts an Xcode Cloud build, which would be the first 5.8 one. Ask him first.
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

On his iPhone: Library Settings, Watch a Folder, choose a folder in iCloud Drive or On My iPhone, add a file, reopen the app, and
confirm it imports. Then the same on the Mac after a relaunch. Commit when he says.
