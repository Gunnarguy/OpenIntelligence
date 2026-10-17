# Current State

Updated: 2026-10-16, 18:10 PT (5.7 is open and unreleased, no 5.7 build in TestFlight; since the 10:30 handoff four commits, `3c4d648`, `3964575`, `fc1a377` and `6fcb2c6`, all pushed with `[ci skip]`; 5.6 has been live on iPhone, iPad and Mac since 2026-10-08, build 485)
Branch/worktree: `main`, primary checkout
Last verified commit: 6fcb2c6

Earlier detail is in git: `git show 429f80e:Docs/ai/STATE.md` (10:30 the same day), `git show e13f664:Docs/ai/STATE.md`
(the night of 2026-10-15) and older copies named there; the long record through 2026-10-10 is
`Docs/Archive/STATE_record_through_2026-10-10.md`.

## Objective

**5.7: JSON Lines import and the Apple surfaces that carry the app to other apps and people, mainly for iPhone
and iPad.** Named by the owner on 2026-10-08, widened on 2026-10-09 and 2026-10-10. On 2026-10-15 he said "legit go
until all 5.7 is finished, all backlogs, EVerything". On 2026-10-16 he pulled the screens' accessibility fixes into 5.7,
then two changes from showing the app to someone new ("1 and 2 into 5.7": the hardware X-Ray off on a new install, and a
cited page opening at the passage), then the Atlas's axis labels from a screenshot ("this is just another thing that I
want to fix"). The work is the open 5.7 roadmap rows, one at a time, each finished, checked and committed before the next.

## Status (2026-10-16 evening)

| What | Where it stands |
|---|---|
| Today's commits | `3c4d648`: Apple's common tasks at every text size, and a paused file no longer stays at "Storing" after Continue. `3964575`: a cited passage opens on its PDF page with the passage highlighted (`SourcePageView`, PDFKit; a reopened conversation reads the whole passage again by id), and the X-Ray starts off on a new install (`SettingsStore`). `fc1a377`: every switch and slider has a VoiceOver name (five switches, five sliders). `6fcb2c6`: every end of every Atlas axis has a label ("Component N" where nothing sets an end apart), no adverb names one (NaturalLanguage word classes in context, per passage language), no word names two ends, labels one size on screen (presentation positions, depth along the view). Each had a refuting review before it was committed. |
| His iPhone | A development build of `6fcb2c6` (everything above), installed 18:09 while the app was closed. |
| Seen on his iPhone | The page view, 2026-10-16 ("pull up the PDF and highlight the section"), on the build before its review's fixes. Nothing else in 5.7 has been seen there. |
| 5.7 source | All pushed (`git rev-list --count origin/main..HEAD` prints 0). |
| Tests | On `6fcb2c6`'s tree: device `BUILD SUCCEEDED`, `TEST BUILD SUCCEEDED`, `Executed 1164 tests, with 6 tests skipped and 0 failures`, Mac `BUILD SUCCEEDED`, UI tests `Executed 4 tests, with 0 failures`, 2026-10-16 about 17:45. |
| TestFlight | No 5.7 build. Every 5.7 push carried `[ci skip]`; a push whose newest commit lacks it starts one. |
| Catalogue | https://claude.ai/artifact/Thu24syf3CbVtpwhjAm4mJ, version 24: header at `6fcb2c6` and the 18:09 phone build; the Quick Look row has the page view and the accessibility row `fc1a377`. Run `node --check` on its script and count its rows (118) before every publish. |
| Test simulator | `OI 5.7 tests` `3982899B-3D70-4C87-B957-D104ECDECB5F` (iPhone 18 Pro, iOS 27.0). Simulators here are deleted between sessions: check `xcrun simctl list devices` first. |

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
- **His word on a network fetch:** `NLTagger.requestAssets(for:tagScheme:)` would let the Atlas's adverb filter work for
  Spanish and German on an iPhone (the iOS 27 Simulator has no word classes for them; macOS 27 has). Not called.
- **A device:** every built row closes on his iPhone or Mac: the page view on the Mac, the Atlas on his library (label at
  every end, no adverb, one size as the map turns), the X-Ray on a fresh install, VoiceOver, the largest text size.
- **Apple:** the background inference entitlement.

New rows today: "A new install opened with the hardware X-Ray over Chat" (v5.7), "Chat shows every control at once to
someone seeing the app for the first time" (Future Backlog, the owner's option 3: a plainer Chat screen).

## Active Constraints

- A push whose newest commit lacks `[ci skip]` starts the first 5.7 Xcode Cloud build. Ask him first.
- Hard-boundary files only when he names them (`Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md`). `ChatMessage.swift` keeps
  saved passages cut to 600 characters; `SourcePageView` reads the whole passage by id instead of changing it.
- Held, uncommitted: `project.pbxproj` (Enhanced Security and the extension's entitlements file),
  `OpenIntelligence/OpenIntelligence.entitlements` and the untracked
  `OpenIntelligenceLiveActivities/OpenIntelligenceLiveActivities.entitlements`. Builds use a copy of the tree in
  `/private/tmp/oi-src` with HEAD's two held files put back; commit by name, never `git add .`. After
  `codemap.py index`, take the held file's line out of `Docs/ai/codemap/UNMAPPED.md`. Leave `.agents/skills/` and
  `.codex/hooks*` alone.
- App Store Connect writes only at his word, through `zsh -ic`; never copy the key id, issuer or key anywhere.
- Public repository and site: no personal plans in public files or row titles. Never delete a doc, a benchmark run
  directory or a Notion row. No co-author or attribution lines in commits.
- One `xcodebuild` at a time (other sessions build too: check `pgrep -x xcodebuild`); never edit the tree while a cycle
  runs (it copies the tree three times). End only your own build, by its process id.
- Edit existing Swift files by script: the post-edit formatter rewraps a whole file Claude edits.
- Stamp a codemap slice only when every change since its stamp was reviewed (`embedding-visualizations-and-3d` and
  `what-s-new-and-version-history` were left unstamped today).
- The unit-test runner here hangs before connecting on about half of today's runs; rerun `test-without-building` on the
  same build (`scratchpad/cycle_and_retry.sh` does), and rebuild the unit-test products first only after a UI-test build.
- This session's scripts are in
  `/private/tmp/claude-501/-Users-gunnarhostetler-Documents-GitHub-OpenIntelligence/02a2f913-1d63-449c-8ccc-8c198da128bc/scratchpad`
  (`cycle_full.sh`, `cycle_and_retry.sh`, `uitests.sh`, `build57.sh`, `builddevice.sh`, `buildmac.sh`,
  `install_when_idle.sh`, `copy57/patch_*.py`, `nlprobe/`, `macpdfprobe/`) until `/private/tmp` is cleared.

## Working Set

- Page view: `OpenIntelligence/Features/Chat/Response/SourcePageView.swift` (`SourcePageView`, `PassageLocator`,
  `PassageReveal`, `RevealingPDFView.show`), `CitationSourceDocument.swift` (`LibraryDocumentLookup.passageText`),
  `GroundedAnswerView.swift` (`evidenceDestinations`, `ClaimCard`), `ResponseDetailsView.swift` (`SourceCard`).
- X-Ray default: `SettingsStore.swift` (`showSiliconHUD`), `SettingsView.swift` (Appearance keywords "x-ray").
- VoiceOver names: `SettingsView.swift`, `ContainerSettingsSheet+Sections.swift`, `VisualizationsView.swift`,
  `CameraVisionOverlayView.swift`, `OpenIntelligenceUITests/AccessibilityAuditTests.swift`.
- Atlas: `Services/Infrastructure/Presentation/AtlasLabeling.swift` (`axisEnds`, `axisLabels`, `namingTerms`,
  `namingDistinguishingTerms`), `LibraryVisualizationEngine.swift`, `Features/Telemetry/Visualizations/Embedding3DView.swift`
  (`sizeLabelsForScreen`, `viewDepth`, `screenScale`, `mapLabelNodes`), `AdaptiveVisualizationsView.swift`.
- Next: `OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift`, `createStructureAwareChunks` at :5357.

## Verification (2026-10-16, output read)

- `6fcb2c6`'s tree: as in Status. The new Atlas tests (`AtlasLabelingTests`, `AtlasLabelSizeTests`, 23 in all) passed;
  the test log printed "WORD CLASSES: Spanish false, German false" in the iOS 27 Simulator.
- `fc1a377`'s tree: 1,155 unit tests and 4 UI tests, 0 failures; the new UI test's audit of Settings' Apple Intelligence
  and Appearance pages printed "No issues".
- `3964575`'s tree: 1,155 unit tests (the 9 new page-view tests among them), 3 UI tests, iPhone and Mac builds.
- Probes on macOS 27 (scratchpad `macpdfprobe/`, `nlprobe/`): a PDF view hosted in SwiftUI gets `layout()` once sized
  and measures 0 by 0 with no frame; a 500-page PDF opens and finds a passage in about 2 ms; NLTagger misreads lone
  words and reads them right in a sentence (memory `naturallanguage-word-classes-need-context`).
- `python3 .claude/codemap/codemap.py check` -> 0 errors. `python3 scripts/secret_scan.py` -> no tokens.
- Not run: anything of `fc1a377` or `6fcb2c6` on a device; the spinning Atlas's label sizes (only a running renderer
  fills the presentation nodes, so the tests cover the arithmetic); the page view on the Mac.

## Blockers / Unknowns

- **Provisioning.** Xcode here has no Apple account ("No Accounts"); his sign-in in Xcode unblocks the provisioning rows.
- **Nothing in 5.7 is closed on a device** except what he saw of the page view (its row closes on the Mac too).
- **The audit's frames and verdicts do not always match the screen**, and it only sees the open screen; search the code
  for empty labels as well (`Docs/ai/RUNBOOK.md`, "Apple's accessibility audit, with the X-Ray off").

## Exact Next Action

Take the row "Import still runs whole-document passes on the main thread after text cleanup and chunking were moved off
it": in `DocumentProcessor.swift`, `createStructureAwareChunks` (line 5357) runs on
the main actor and calls about 25 instance helpers; list what they read (`grep -n` each helper), move the function and
those helpers off the main actor (`@concurrent` or `nonisolated`, as `docs/ai` memory `module-default-isolation` says),
and time an import of a large PDF before and after on the iOS 27 Simulator.
