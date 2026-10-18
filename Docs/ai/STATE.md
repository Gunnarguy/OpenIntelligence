# Current State

Updated: 2026-10-17, 23:00 PT (5.7 is open and unreleased, no 5.7 build in TestFlight; today's 5.7 commits run from
`3c93acb` to `3d00e54`, all pushed with `[ci skip]`; 5.6 has been live on iPhone, iPad and Mac since 2026-10-08)
Branch/worktree: `main`, primary checkout
Last verified commit: 3d00e54

Earlier detail is in git: `git show b093743:Docs/ai/STATE.md` (the evening of 2026-10-16) and the copies it names; the
long record through 2026-10-10 is `Docs/Archive/STATE_record_through_2026-10-10.md`.

## Objective

**5.7: JSON Lines import and the Apple surfaces that carry the app to other apps and people, mainly for iPhone and
iPad.** Named by the owner on 2026-10-08 and widened since. On 2026-10-17 he said "Everything. Add everything not added
yet. I basically want the entire Notion to do, done, no holding back", asked for a plainer chat with the technical view
behind a switch, and for a finished task's notification to go once he is back in the app. The work is the open roadmap
rows (Notion, `Target Release` v5.7 first), each finished, checked and committed before the next.

## Status (2026-10-17, night)

| What | Where it stands |
|---|---|
| Today's commits | `43febb5` notifications go once you're back; `3c93acb` the plainer chat; `6ebf96e` the app group and Enhanced Security; `6ebf70e` the share sheet; `37f20d6` score ties in one order; `a30dba7` chunker overlap and keyword order; `18c11fa` the listing scene; `ef71d96` the nomination script; `3c41994` the last passage; `3b1ad54` the sale's price by territory; `2492894` web links; `4b10a16` Scan into Library from the Lock Screen; `3a1cf81` shares wait for room; `7563d69` Copy Link; `3262001` the listing scenes' pill; `3d00e54` store notes, art and the hook's character count. |
| The roadmap's 5.7 To Do rows | None left. Share sheet, web links, Lock Screen scan, header and search image: In Progress (built, close on a device or at review). Nomination: Completed. |
| App Store Connect, at his word | 5.7 featuring nomination SUBMITTED (2026-11-09 to 11-30). Fifth copy of the notes on both 5.7 records (read back identical). Header and search image placed on the iPhone record (A, from a contact sheet). Nothing submitted for review. |
| gunzino.me, at his word | Privacy page names the share sheet (Gunzino `8a53660`); the association file and `/openintelligence/open` are live (`5c10b42`), and Apple's CDN serves the file. |
| His iPhone | Still the development build of `6fcb2c6` from 2026-10-16 18:09. Nothing built on 2026-10-17 is on it. |
| Catalogue | https://claude.ai/artifact/Thu24syf3CbVtpwhjAm4mJ, version 25: 84 of 118 rows built, 2 need him. Run `node --check` on the page script and count ROWS before every publish. |
| Future Backlog | 4 rows pulled in and done today (ties, keyword order, overlap, the sale). 38 open; most need a benchmark run, a device, or a decision he has already made (the 27 SDK deprecations wait for a minimum of 27, decided 2026-10-15). |

## Active Constraints

- A push whose newest commit lacks `[ci skip]` starts the first 5.7 Xcode Cloud build. Ask him first.
- Hard-boundary files only when he names them (`Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md`). On 2026-10-17 he named
  `project.pbxproj` and the entitlements for this work, and `SQLiteFullTextService.swift`.
- App Store Connect writes and public pages only at his word; App Store Connect through `zsh -ic`; never copy the key id,
  issuer or key anywhere. Show him a contact sheet before any store image goes up.
- Never delete a doc, a benchmark run directory or a Notion row; no co-author or attribution lines; commit by name, never
  `git add .`; leave `.agents/skills/` and `.codex/hooks*` alone.
- One `xcodebuild` at a time; never edit the tree while a run is going; end only your own build, by its process id.
- Edit existing Swift files by script: the post-edit formatter rewraps a whole file Claude edits (it rewrapped
  `SemanticChunker.swift` on 2026-10-17 and the change was redone by script).
- **Disk.** Free space swung between 2 and 12 GB on 2026-10-17 with swap at 12 to 14 GB (other apps open). The build
  guard stopped four runs below its floor; `GUARD_DISK_MB=2000` and erasing this session's own simulators (the test and
  store devices, no keys) kept runs going. A freshly erased test simulator fails three `AtlasLabelingTests` on its first
  run until the system's word-class data downloads, and the share-inbox check leaves its library at the free plan's
  limit, which stops the UI tests' notes; erase or reset it before a full run.
- This session's scripts are in
  `/private/tmp/claude-501/-Users-gunnarhostetler-Documents-GitHub-OpenIntelligence/02a2f913-1d63-449c-8ccc-8c198da128bc/scratchpad`
  (`cycle_lean.sh`, `uitests.sh`, `build57.sh`, `builddevice.sh`, `macsigned_reuse.sh`, `capture_store.sh`,
  `inbox_coldlaunch.sh`, `snap.sh`, `commit_snap.sh`, `fix_everywhere.py`) until `/private/tmp` is cleared.

## Working Set

- Share sheet: `OpenIntelligenceShare/`, `OpenIntelligence/App/SharedInbox.swift`,
  `Features/Documents/Library/SharedInboxImport.swift`, `App/ContentView.swift` (`takeSharedItems`, `documentRoom`).
- Lock Screen scan: `OpenIntelligenceCapture/`, `App/ScanIntoLibraryIntent.swift`, `App/OpenIntelligenceApp.swift`
  (`openCaptureInApp`), `Features/Camera/LockedCaptureImport.swift`, `ContentView.takeLockedCaptures`.
- Links: `Services/Agentic/AppNavigationRequest.swift` (`AppLink.webURL`, `appURL(forWebURL:)`), `DocumentCard.swift`
  and `ContainerPicker.swift` (Copy Link), Gunzino `public/.well-known/apple-app-site-association`.
- Sale: `Features/Billing/LaunchSale.swift`, `scripts/verify_sale_prices.py`.
- Chunker: `Services/Document/Chunking/SemanticChunker.swift` (`advancePosition`); harness in
  `BenchmarkRuns/2026-10-17-chunker-overlap-and-ties/` (local, gitignored).
- Store: `scripts/asc_nominate_release.rb`, `scripts/asc_upload_listing_art.rb`, `fastlane/nominations/5.7.json`,
  `Docs/Release/APP_STORE_METADATA_HISTORY.md` (5.7, fifth copy).

## Verification (2026-10-17, output read)

- `3a1cf81`'s tree (five commits): signed device BUILD SUCCEEDED, TEST BUILD SUCCEEDED, signed Mac BUILD SUCCEEDED,
  `Executed 1186 tests, with 7 tests skipped and 0 failures` after resetting the test simulator, 4 UI tests passed (one
  alone after a launch timeout).
- `3262001`'s tree: the same steps; `Executed 1186 tests, with 6 tests skipped and 0 failures` on the second run (the
  first failed three Atlas tests waiting for word-class data on the erased simulator); 4 UI tests passed (the audit alone
  after "Audit failed to complete in time").
- `zsh -ic 'python3 scripts/verify_sale_prices.py'` -> 175 territories, 141 match, 34 no recorded price, 0 differ.
- Share inbox in the iOS 27 Simulator (`inbox_coldlaunch.sh`): taken on a cold launch and on a return, both imported.
- Chunker harness: overlap at the setting, no passage inside its neighbour at the app's settings, two launches identical.
- `bash scripts/test_enforce_docs_hook.sh` -> 19 passed, 0 failed (the new case fails on the old count).
- `python3 .claude/codemap/codemap.py check` -> 0 errors. `python3 scripts/secret_scan.py` -> no tokens.
- Not run: anything from 2026-10-17 on a device; the capture extension (the Simulator has no camera); a web link opening
  the app; the Mac app launched with the new entitlement (its profile allows associated domains).

## Blockers / Unknowns

- **Every row built today closes on a device**: share from Safari on the iPhone, a Lock Screen scan, a web link from
  Notes, Copy Link from Notes on iPhone and Mac, the widget on a Home Screen, a large PDF with Enhanced Security on.
- **Retrieval half of the overlap row**: a before-and-after retrieval run on code and JSON text is not done.
- **The tie-break row** closes on a greedy A/A pair on HEAD, not run.

## Exact Next Action

Install a development build of HEAD on his iPhone over Wi-Fi while the app is closed (memory
`building-to-gunnars-iphone`; the scratchpad's `install_when_idle.sh` waits for that), then ask him to try, in order:
share a Safari page to OpenIntelligence, add Scan into Library to the Lock Screen and take a page, Copy Link on a
document and open it from Notes, and the Your Library widget. Close each row in Notion only on what he sees.
