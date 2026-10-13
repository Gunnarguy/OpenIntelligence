# Current State

Updated: 2026-10-12, 21:30 PT (5.7 is open and unreleased; all of its work is committed and pushed, `ec4fb74` at 20:59 PT with `[ci skip]`; the 5.7 store notes are on both App Store Connect records and nothing is submitted; that tree's build was installed on the owner's iPhone at 21:25 PT; 5.6 has been live on iPhone, iPad and Mac since 2026-10-08, build 485)
Branch/worktree: `main`, primary checkout
Last verified commit: ec4fb74

The long form this file had grown to (1,129 lines: every status and verification block since 2026-09-29, the
open checks for 5.6 and earlier, the owner decisions still open) is kept word for word in
`Docs/Archive/STATE_record_through_2026-10-10.md`. This file names what is live now and points there for the rest.

## Objective

**5.7: JSON Lines import and the Apple surfaces that carry the app to other apps and people (Share Sheet,
Shortcuts, App Intents), mainly for iPhone and iPad.** The owner named it on 2026-10-08. He widened it twice:
on 2026-10-09 to the Apple model APIs, and on 2026-10-10 to the whole import path and to how the app feels
with a very large library ("all done and squared away for 5.7"). On 2026-10-12 he asked for everything to be
committed and pushed and every document, the App Store Connect metadata, the READMEs and the roadmap brought
up to date. `ec4fb74` completed that request, and the commit carrying this file only records what
happened after the push.

## Status (2026-10-12)

| What | Where it stands |
|---|---|
| 5.7 source | `ec4fb74` is on origin, pushed 2026-10-12 at 20:59 PT: ten commits after `55af072`, each marked `[ci skip]`. The commit carrying this file changes this file only. `git rev-list --count origin/main..HEAD` prints 0 when everything is pushed; if it prints more, push with the newest commit still marked `[ci skip]`. |
| Tests | 832 run, 0 failures, 4 skipped, on a simulator made that evening (see Verification). |
| App Store Connect | 5.7 exists on both platforms in PREPARE_FOR_SUBMISSION, release set to manual, no build. Release notes pushed 2026-10-12 (Mac 20:11 PT, iPhone and iPad 20:16 PT). App Review's notes carry the 5.7 addition and are at 3,990 of 4,000 characters. |
| TestFlight | No 5.7 build has ever been made. Every 5.7 push carried `[ci skip]`, and four minutes after the 20:59 push the newest Xcode Cloud run was still #485, the 5.6 build of 2026-10-08. |
| His iPhone | A Debug build of the Swift in `ec4fb74` (5.7, build 150), installed 2026-10-12 at 21:25 PT once the app was seen not running, and not launched. It carries that day's text corrections, and it imports the sample documents again the first time it opens. |
| Roadmap | 101 rows on `v5.7`: 62 In Progress and 39 To Do (queried 2026-10-12). None is Completed, because nothing in 5.7 has had its device check. |

## Completed (2026-10-10 to 2026-10-12, this session)

- The 88.50 MB JSON Lines import finished on his iPhone as 144,247 passages, and the app opens, answers and
  draws the Atlas with that library (his words and screenshots, 2026-10-10).
- Committed on 2026-10-10: the sync guard during an import, the embedder default (Core ML for a new library
  on iPhone and iPad, Core AI on macOS 27), the sampling limits for a very large library, MetricKit
  diagnostics kept on the device, two system model tools wired in and off, the Background GPU Access
  entitlement, and Atlas names taken from the library's own words. Each has a `CHANGELOG.md` entry under 5.7
  and a record in `Docs/ai/DECISIONS.md`.
- 2026-10-12: an audit by a delegated read-only agent listed 67 stale or incomplete statements. Each quoted
  line was checked against its file here; the stale ones were corrected, and three were left by decision
  (the store description and keywords, which are his to cut, and `Docs/SHIPPED_CAPABILITIES.json`, which
  lists shipping builds only). In the app: Library Settings, the diagnostics card, the Settings feature list,
  the Atlas information sheet, the document timing row, the glossary, the How It Works card and the sample
  documents no longer say the embedder runs on the Neural Engine whichever copy a library uses, and the
  What's New list for 5.7 has twelve items. In the docs: the Canonical, the Atlas, How It Works, the
  ingestion, retrieval and privacy docs, Limitations, `PROJECT.md`, `ARCHITECTURE.md`, the runbook, both
  READMEs and `PRIVACY.md`.
- 2026-10-12: where the Core AI copy runs was measured on the Mac (4.71 ms a passage by default, 112.26 ms
  CPU-only), which replaced an inference in the changelog and the decision record.
- 2026-10-12: release notes for both platforms, the App Review addition, and the 5.7 entry in
  `Docs/Release/APP_STORE_METADATA_HISTORY.md`.
- 2026-10-12: thirteen 5.7 decisions that had only changelog entries got records in `Docs/ai/DECISIONS.md`,
  drafted by a delegated read-only agent and spot-checked here. A second delegated agent (Gemini 3.8 Flash,
  after Antigravity's Claude quota ran out) was asked to refute the corrected statements against the code
  before the push. It reported 540 statements checked and none wrong, with code evidence for twenty. That is
  a second reading, not proof.

## Active Constraints

- **A push whose newest commit lacks `[ci skip]` starts the first 5.7 Xcode Cloud build and puts it in
  TestFlight.** He has not asked for one. Ask before sending it.
- Hard-boundary files are edited only when he names the file. Named for 5.7: `RAGAppIntents.swift`,
  `Info.plist`, `OpenIntelligence.entitlements`, `EngineSDKCompatibility.swift`, `project.pbxproj`,
  `WorkspaceSyncService.swift`, and the tool registry work. Not named: `ChatMessage.swift`, the billing files,
  the `SQLiteFullTextService.swift` schema, the `BNNSVectorDatabase.swift` format,
  `FoundationModelSessionFactory.swift`, `FoundationModelRoutePolicy.swift`, `Package.swift`.
- App Store Connect writes happen only at his word. Run anything that needs its credentials through
  `zsh -ic`, and never copy the key id, the issuer or the key into a file, a log or a chat.
- The repository and gunnarguy.me are public. Keep his personal plans out of public files and out of roadmap
  row titles. Never delete a doc or a benchmark run directory.
- One `xcodebuild` at a time on this 18 GB Mac, with DerivedData outside `~/Documents`.
- Installing a build on his iPhone ends the running app. Check `xcrun devicectl device info processes` first,
  and do not launch the app remotely while he may be holding the phone.
- Untracked and left alone: `.agents/skills/`, `.codex/hooks.json`, `.codex/hooks/` (another tool wrote them
  on 2026-10-08).

## Working Set

- `CHANGELOG.md`, the section `## 5.7 <!-- unreleased -->`: one entry per change with its evidence and what
  has not been seen on a device. Read by section, never whole.
- `Docs/ai/DECISIONS.md`, the records dated 2026-10-09 to 2026-10-12, the storage plan among them.
- `Docs/Release/APP_STORE_METADATA_HISTORY.md`, `### 5.7`: the store notes as pushed, per platform.
- `fastlane/metadata/en-US/release_notes.txt` (Mac), `fastlane/metadata-ios/en-US/release_notes.txt` (iPhone
  and iPad), `fastlane/review_notes/5.7.txt`.
- `OpenIntelligence/Services/Embedding/EmbeddingService.swift` (`EmbeddingProviderDefaults`),
  `OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift` (what the storage plan changes),
  `OpenIntelligence/Services/Infrastructure/Presentation/AtlasLabeling.swift`,
  `OpenIntelligence/App/MetricDiagnostics.swift`, `OpenIntelligence/App/DebugEmbeddingBench.swift`.
- Local and git-ignored: `BenchmarkRuns/2026-10-10-large-library/` (the cost maps, the SDK surveys, and
  `W3-store-callers.md`, the caller inventory the storage plan needs, not yet read or checked), and
  `BenchmarkRuns/2026-10-12-docs-sync/` (the audit and the drafted decision records).

## Verification (2026-10-12, output read)

- Device build, simulator test build, the suite and the Mac build, one after another, run twice that evening.
  The second run is on the Swift this commit holds -> `BUILD SUCCEEDED`, `TEST BUILD SUCCEEDED`,
  `Executed 832 tests, with 3 tests skipped and 0 failures`, `BUILD SUCCEEDED` (20:45 PT). Skipped: the two
  `EmbeddingProviderAgreementTests` (no Core AI in the Simulator) and
  `testInterleavedContentStreamIsReorderedByGeometry`. The first run, 20 minutes earlier on a simulator that
  had just been made, also skipped `testSilentAudio_FailsLoudlyInsteadOfProducingAnEmptyDocument` after a 60 s
  wait. Simulator `OI 5.7 tests`, `DE0883DB-2849-47F9-93AE-23C4E880FDED`; the runbook's `## Test` section says
  how to make one when the list is empty. Docs changed after that run and no Swift did.
- `python3 scripts/verify_doc_claims.py` -> 836 claims checked, every one matches source (936 before this file
  was shortened; the long form carried about a hundred of them).
- `python3 scripts/secret_scan.py` -> no sensitive tokens discovered.
- `python3 .claude/codemap/codemap.py check` -> 46 slices, 0 errors, 0 warnings, after stamping seven slices.
- `scripts/check_icloud_conflicts.sh` -> no iCloud damage found.
- `cmp Docs/USER_CHANGELOG.md OpenIntelligence/Resources/VersionHistory.md` -> identical.
- `fastlane push_metadata version:5.7 platform:osx`, then `platform:ios` with the runbook's swap -> each log
  names its platform and `app_version` 5.7 and ends "finished successfully"; `fastlane/report.xml` held no
  failure; the Mac copy in the repository was restored (checksums compared).
- `ruby scripts/asc_listing_extras.rb 5.7 --apply` -> both notes 3,042 to 3,990 characters, HTTP 200.
- A read of the four newest Xcode Cloud runs through the API at 21:03 PT -> #485 (2026-10-08) is the newest, so
  the push started no build.
- `xcrun devicectl device install app` at 21:25 PT, after two process listings without the app -> installed.
- Not run: the app itself, on his iPhone or on the Mac, since 2026-10-10.

## Blockers / Unknowns

- **Nothing in 5.7 is closed.** Every row waits on being seen on a device. The list of checks, in the order
  they were written, is in the archive file under "Exact Next Action", items 1b and 3, and the checks still
  open for 5.6 follow them there.
- **Two lines in the store notes have not been seen to work:** "Open in" on iPhone and iPad, and dropping a
  file on the app's icon on the Mac. Verify by sending a PDF from Files' share sheet and by dropping a text
  file on the Dock icon. Row https://app.notion.com/p/3f449a74d54f8132a024ffec0182528a says what closes it.
- **The storage change is designed and not started.** Loading the 144,247-passage library still decodes
  159 MB of passage text (3.0 to 3.2 s) and every save rewrites the whole store. The plan is the decision
  record "The vector store keeps its file format" of 2026-10-10.
- **A background import has not been observed since the Background GPU Access entitlement went in.** Verify by
  starting an import on the phone, leaving the app, and reading `continued_ingestion_status.json` in the app's
  container (`backgroundGPUSupported` read false before the entitlement). Whether App Store signing accepts
  the key is unknown until the first Xcode Cloud build of 5.7.
- **The two copies of the embedder have not been compared in use.** A flag file for the second half of the
  benchmark was left on the phone on 2026-10-10 and no result came back; `DebugEmbeddingBench.runProviders`
  is the code, and the runbook section "Timing the embedding model on a device" is the recipe.
- **The first sync pass after an import still copies the whole vector store to iCloud Drive.**
- **The vector similarity scan was not moved to `MLTensor` or `cblas_sgemv`.** It already runs as one
  `vDSP_mmul` over the whole store (`BNNSVectorDatabase.search`), so the gain is unknown and may be small.
  Time that call on the phone with the 144,247-passage library before changing it.
- **The two system model tools have no Settings control and have never been called on a device.**
- **The sample documents changed, so 5.7 imports them again on first launch.** Not seen on a device.
- **The App Store description does not name JSON import, Shortcuts results or sharing.** It is 3,997 of 4,000
  characters, so adding one means cutting something, which is his call.
- **App Review's notes are full.** The next version's addition will be refused until older additions are
  removed from the notes on the record (the runbook says where).
- **The hosted privacy policy at gunzino.me does not mention the web page download, notifications or the
  on-device diagnostics.** It lives in the Gunzino repository and is due when 5.7 is released.
- **At release, `Docs/SHIPPED_CAPABILITIES.json` needs 5.7's capabilities** (JSON records, Shortcuts results,
  sharing with sources, notifications, the web page download). It lists shipping builds only, so it was left
  as it is while 5.7 is unreleased.
- **Simulators on this Mac are deleted between sessions.** Expect to make one before any test run.

## Exact Next Action

Read `BenchmarkRuns/2026-10-10-large-library/W3-store-callers.md` and check ten of its call sites against the
code with `grep -n 'allChunks()' -r OpenIntelligence --include='*.swift'`. If the inventory holds, write the
failing test first: a `BNNSVectorDatabase` loaded from a store of 1,000 passages must answer `count`, a
passage by index and the passages of one document without decoding every passage's text (new methods beside
`allChunks()`, in `BNNSVectorDatabase.swift`, whose on-disk format stays as it is). If that directory is gone,
rebuild the inventory from the same `grep`. Before any of it, if he is at his phone, the device checks under
Blockers come first, because they decide whether 5.7's notes can stand.
