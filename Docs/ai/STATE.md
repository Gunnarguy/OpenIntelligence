# Current State

Updated: 2026-10-16, 10:30 PT (5.7 is open and unreleased, no 5.7 build in TestFlight; since the 2026-10-15 night handoff two commits, `54f0f84` and `89e14e9`, both pushed with `[ci skip]`; 5.6 has been live on iPhone, iPad and Mac since 2026-10-08, build 485)
Branch/worktree: `main`, primary checkout
Last verified commit: 89e14e9

Earlier detail is in git: `git show e13f664:Docs/ai/STATE.md` (the night of 2026-10-15) and older copies named there;
the long record through 2026-10-10 is `Docs/Archive/STATE_record_through_2026-10-10.md`.

## Objective

**5.7: JSON Lines import and the Apple surfaces that carry the app to other apps and people, mainly for iPhone
and iPad.** Named by the owner on 2026-10-08, widened on 2026-10-09 and 2026-10-10. On 2026-10-15 he said "legit go
until all 5.7 is finished, all backlogs, EVerything"; on 2026-10-16 he pulled the screens' accessibility fixes into 5.7
and said "go ahead, keep going until it's all done", then "keep going". The work is the open 5.7 roadmap rows, one at a
time, each finished, checked and committed before the next.

## Status (2026-10-16)

| What | Where it stands |
|---|---|
| Today | Accessibility on Chat, Documents and Settings, and one import fix. `54f0f84`: gray text at 5.2 to 1 (`DSColors.secondaryText`, systemGray at high contrast), text styles instead of fixed sizes, the upload panel drawn only while visible. `89e14e9`: words on tinted chips and pills in the label color with the color in the icon and the tint, and the AccentColor asset #005CDB in light (#007AFF in dark), both the owner's choices; the Mac's readable colors blended to 4.5 to 1 (`NSAppearance(named:)` is nil for the high-contrast names); rows of fixed-size pills wrap instead of squeezing (`WrappingRowLayout`, Chat's header and Settings' identity row); the model pill's running line is the route's short name; at accessibility sizes the Documents header scrolls with the documents; the question field in Callout on iPhone and iPad (16 points on the Mac); `-showSiliconHUD NO` works as a launch argument; and the import's stage-ledger counts run off the main actor without a substring per word. |
| Accessibility audit | Apple's audit with the X-Ray off, light and dark at the default and the largest text size: 54, 44, 35 and 31 issues on 2026-10-15, now 11, 14, 7 and 7 (7 at the largest standard size). Every contrast item it names an element for measures 5.06 to 13.3 to 1 on the screenshot; the rest are `.caption2` text it calls partial although it grows past 200%, and the system search field. White on a filled blue button in dark mode is 4.0 to 1, decided (`Docs/ai/DECISIONS.md`). Evidence `BenchmarkRuns/2026-10-16-accessibility-pass-1/` and `-pass-2/` (local). Not seen on a device. |
| Store notes | The fourth copy (an "Easier to read" line at the end of ALSO) is on both 5.7 records, read back identical (3,803 and 3,923 characters); the iPhone push was at his word after the session's permission check stopped it (`Docs/Release/APP_STORE_METADATA_HISTORY.md`, 5.7, "Fourth copy"). Nothing submitted. |
| 5.7 source | All pushed (`git rev-list --count origin/main..HEAD` prints 0). |
| Tests | 1,138 run, 0 failures, 6 skipped, and the 3 UI tests passed, on `89e14e9`'s tree, 2026-10-16 about 10:12 PT; device and Mac builds succeeded. |
| TestFlight | No 5.7 build. Every 5.7 push carried `[ci skip]`; a push whose newest commit lacks it starts one. |
| His iPhone | A development build of `89e14e9` is staged in `/private/tmp/oi-install/`, and `install_when_idle.sh` (started 10:26 PT, waits up to four hours) installs it once the phone is reachable and the app is closed; at 10:31 `devicectl list devices` showed the phone "unavailable". Until then the phone has `01fd0d1` (installed 2026-10-15 22:27). |
| Catalogue | https://claude.ai/artifact/Thu24syf3CbVtpwhjAm4mJ, version 21: header at `89e14e9`; the accessibility row has today's numbers. Version 20 (2026-10-15) had five rows ending in an extra `}`, so its script did not run and the list was empty; fixed in 21 and checked with `node --check`. |
| Test simulator | `OI 5.7 tests` `E2D49A91-0083-4BE1-831E-7675564CD7BA` (iPhone 18 Pro, iOS 27.0). Simulators on this Mac are deleted between sessions: check `xcrun simctl list devices` first. Its X-Ray stays off after the audit test (SettingsStore saves the launch argument). |

Open 5.7 rows that no session can finish alone (Notion, `Target Release` v5.7):

- **His word on a hard-boundary file:** "Deleting a library leaves its passages in the search cache" (a delete in
  `SQLiteFullTextService.swift`; the earlier approval named the cached-search delete, not this one).
- **His word on another repository:** the published privacy page on gunzino.me (Gunzino repo) still says Private Cloud
  Compute receives data only for the final synthesis and misses 5.7's three new flows (row "PRIVACY.md makes eight
  claims...").
- **His Apple account in Xcode (Settings, Accounts):** Widgets ("Your Library" waits on the app group), Share Sheet
  entry, Scan from the Lock Screen, Universal links, Enhanced Security. Their entitlements and project settings are held
  uncommitted (Active Constraints).
- **His word in App Store Connect:** the product page header and search image, a featuring nomination, the
  accessibility declarations (only what a test backs).
- **A device:** every built row closes on his iPhone or Mac, including the three fixes of 2026-10-15 and the
  accessibility pass (the three screens at the largest text size, light and dark).
- **Apple:** the background inference entitlement.

## Active Constraints

- A push whose newest commit lacks `[ci skip]` starts the first 5.7 Xcode Cloud build. Ask him first.
- Hard-boundary files only when he names them. Named for 5.7: `RAGAppIntents.swift`, `Info.plist`,
  `OpenIntelligence.entitlements`, `EngineSDKCompatibility.swift`, `project.pbxproj`, `WorkspaceSyncService.swift`,
  `FoundationModelSessionFactory.swift`, `SQLiteFullTextService.swift` (cached-search delete), `ChatMessage.swift`
  (token count). Not named: the billing files, `FoundationModelRoutePolicy.swift`, `Package.swift`.
- Held, uncommitted: `project.pbxproj` (Enhanced Security and the extension's entitlements file),
  `OpenIntelligence/OpenIntelligence.entitlements` and the untracked
  `OpenIntelligenceLiveActivities/OpenIntelligenceLiveActivities.entitlements` (App Groups and Enhanced Security).
  Builds use a copy of the tree in `/private/tmp/oi-src` with HEAD's two held files put back; commit by name, never
  `git add .`. After `codemap.py index`, take the held file's line out of `Docs/ai/codemap/UNMAPPED.md`. The provisioning
  commit also adds `LibraryWidget()` to `OpenIntelligenceLiveActivitiesBundle` and replaces the "A widget." bullet in
  `WHATS_NEW.md`, `Docs/USER_CHANGELOG.md` and `OpenIntelligence/Resources/VersionHistory.md` (text in
  `git show e13f664:Docs/ai/STATE.md`, Active Constraints).
- App Store Connect writes only at his word, through `zsh -ic`; never copy the key id, issuer or key anywhere. The
  session's permission check refuses a push to a record as a production deploy until he says it in chat.
- Public repository and site: no personal plans in public files or row titles. Never delete a doc, a benchmark run
  directory or a Notion row. No co-author or attribution lines in commits.
- One `xcodebuild` at a time on this 18 GB Mac (other sessions build too: check `pgrep -x xcodebuild`), DerivedData
  outside `~/Documents`, `-jobs 1` with a memory guard (`GUARD_DISK_MB=2500` while free disk is near 10 GB).
- Edit existing Swift files by script: the post-edit formatter rewraps a whole file Claude edits (a one-line edit to
  `SettingsView.swift` came back as a 905-line reformat on 2026-10-16).
- Stamp a codemap slice only when this change is all that moved in it: stamping re-resolves every citation and claims
  the whole slice is checked (`hybrid-retrieval-and-fusion` was left unstamped for that reason on 2026-10-16).
- This session's scripts are in
  `/private/tmp/claude-501/-Users-gunnarhostetler-Documents-GitHub-OpenIntelligence/02a2f913-1d63-449c-8ccc-8c198da128bc/scratchpad`
  (`cycle_full.sh`, `build57.sh`, `buildmac.sh`, `builddevice.sh`, `uitests.sh`, `install_when_idle.sh`,
  `a11y/run_label_audit_pass.sh` with `RUNS="light large|..."`, `a11y/pixel_contrast.py`) until `/private/tmp` is
  cleared; copies of the audit scripts are in `BenchmarkRuns/2026-10-16-accessibility-pass-2/`.
- Installing on his iPhone ends the running app: `install_when_idle.sh` waits until it is closed. Tell him first.

## Working Set

- Accessibility: `Theme.swift` (`readable`, `legible`, `relativeLuminance`), `AccentColor.colorset`,
  `UI/Components/WrappingRowLayout.swift`, `ChatScreen.swift` (`CompactChatHeader.bottomRowPills`, `bottomRowCounts`),
  `ChatComposerV2.swift` (`hint`), `ModelStatusIndicator.swift` (`routeName`), `SettingsView.swift` (`heroSummaryRow`,
  `statusPills`, `statusPill`), `DocumentLibraryView.swift` (`libraryContentView`, `documentSectionHeader`,
  `emptyStateStack`, `documentCards`, `withSwipeDeleteAlert`), `EmptyDocumentsView.swift`, `AppTips.swift`,
  `SettingsStore.swift` (`showSiliconHUD`), `OpenIntelligenceUITests/AccessibilityAuditTests.swift`, and the scratch
  audit `BenchmarkRuns/2026-10-16-accessibility-pass-2/AccessibilityLabelMeasurement.swift`.
- Import: `IngestionStageLedger.swift` (`counts(of:)`, `wordCount(of:)`), `DocumentProcessor.swift` (`ledgerCounts`;
  `createStructureAwareChunks` at about :5360 still runs on the main actor and calls about 25 instance helpers).

## Verification (2026-10-16, output read)

- `89e14e9`'s tree: `run_label_audit_pass.sh pass10` (five settings) -> 11, 14, 7, 7 and 7 issues;
  `cycle_full.sh r29` -> device `BUILD SUCCEEDED`, `TEST BUILD SUCCEEDED`, `Executed 1138 tests, with 6 tests skipped
  and 0 failures` (both new ledger tests passed), Mac `BUILD SUCCEEDED`; `uitests.sh r29ui` -> `Executed 3 tests, with 0
  failures`. No compiler warning in a changed file (iOS test build and Mac build logs).
- Pixel contrast of every reported item: `BenchmarkRuns/2026-10-16-accessibility-pass-2/pixel-contrast-final.txt`.
  The Mac's readable colors computed with AppKit's own colors and the same blend: `mac_readable_on_tint.swift` there.
- Ledger counts: a scratch probe (`scratchpad/ledger-probe`, -O on this Mac) timed the split at 430 ms for 8 MB and
  matched the substring-free count on every edge case.
- `python3 .claude/codemap/codemap.py check` -> 0 errors.
- Store notes: `asc_read_whatsnew.rb 5.7` -> both records match the files.
- Two refuting reviews ran: one on `54f0f84` (the Mac's colors did nothing; fixed) and one on the second pass (the
  fixed-size row overflow, the Mac's 12-point Callout, the runbook commands, a dated correction; all fixed). Open from
  it, not verified: whether the `LazyVStack` in the accessibility-size Documents scroll stays lazy on a large library,
  and whether `swipeActionsContainer()` around the header there gets in the way of dragging the library strip.
- Not run: anything on his iPhone after `01fd0d1`; VoiceOver on a device; the Mac colors on screen.

## Blockers / Unknowns

- **Provisioning.** Xcode here has no Apple account ("No Accounts"); his sign-in in Xcode unblocks the provisioning rows.
- **Nothing in 5.7 is closed on a device.**
- **The audit's frames and verdicts do not always match the screen** (it scrolls during its checks, some contrast
  verdicts contradict the pixels, and views swapped by `ViewThatFits` read as not growing); measure on the screenshot
  (`Docs/ai/RUNBOOK.md`, "Apple's accessibility audit, with the X-Ray off").
- **Two duplicate roadmap rows wait for him to delete:** https://app.notion.com/p/3f949a74d54f819d9fddd5a90087fb1e
  and https://app.notion.com/p/3fa49a74d54f815a98c9d84ea08d9287.

## Exact Next Action

Extend the scratch audit to the rest of the common tasks Apple asks a label to cover, in the same five settings with
the X-Ray off: the first-run screen (a fresh install shows it), an answer (`--uitest-stand-in-model` answers in the
Simulator), adding a document (the file picker is system-drawn; audit the import queue and the document's details), and
the purchase sheet. Add each screen to `AccessibilityLabelMeasurement.swift` in
`BenchmarkRuns/2026-10-16-accessibility-pass-2/`, run `run_label_audit_pass.sh` with `RUNS`, measure every contrast item
with `pixel_contrast.py`, look at every largest-size screenshot, and fix what is real, one screen per commit. After
that, `createStructureAwareChunks` off the main actor (row "Import still runs whole-document passes on the main thread").
