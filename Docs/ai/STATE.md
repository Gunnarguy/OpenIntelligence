# Current State

Updated: 2026-10-13, 06:40 PT (5.7 is open and unreleased; the storage change the owner asked for on 2026-10-12 is built, was reviewed by a second agent and corrected, and is in `1fdf69e` and the commit that carries this file, both marked `[ci skip]`; the 5.7 store notes are on both App Store Connect records and nothing is submitted; 5.6 has been live on iPhone, iPad and Mac since 2026-10-08, build 485)
Branch/worktree: `main`, primary checkout
Last verified commit: 1fdf69e

The long form this file had grown to (1,129 lines: every status and verification block since 2026-09-29, the
open checks for 5.6 and earlier, the owner decisions still open) is kept word for word in
`Docs/Archive/STATE_record_through_2026-10-10.md`. This file names what is live now and points there for the rest.

## Objective

**5.7: JSON Lines import and the Apple surfaces that carry the app to other apps and people (Share Sheet,
Shortcuts, App Intents), mainly for iPhone and iPad.** The owner named it on 2026-10-08. He widened it twice:
on 2026-10-09 to the Apple model APIs, and on 2026-10-10 to the whole import path and to how the app feels
with a very large library ("all done and squared away for 5.7"). On 2026-10-12 he asked for everything to be
committed and pushed and every document, the App Store Connect metadata, the READMEs and the roadmap brought
up to date, which `ec4fb74` completed. At about 21:40 PT he said "ok now do the storage change": the plan
in the decision record of 2026-10-10, which `1fdf69e` builds and the commit carrying this file corrects after
a review.

## Status (2026-10-13)

| What | Where it stands |
|---|---|
| 5.7 source | `cdb2bec` and everything before it is on origin. `1fdf69e` (the storage change as first built) and the commit carrying this file (what the review changed, and the scoped-search fix) follow it. `git rev-list --count origin/main..HEAD` prints 0 when everything is pushed; if it prints more, push with the newest commit still marked `[ci skip]`. |
| Tests | 864 run, 0 failures, 4 skipped (the fourth is the scale benchmark, which runs only when asked), 2026-10-13 at 06:29 PT, with a device build before it and a Mac build after. |
| App Store Connect | 5.7 exists on both platforms in PREPARE_FOR_SUBMISSION, release set to manual, no build. Release notes pushed 2026-10-12 (Mac 20:11 PT, iPhone and iPad 20:16 PT). App Review's notes carry the 5.7 addition and are at 3,990 of 4,000 characters. |
| TestFlight | No 5.7 build has ever been made. Every 5.7 push carried `[ci skip]`, and four minutes after the 20:59 push the newest Xcode Cloud run was still #485, the 5.6 build of 2026-10-08. |
| His iPhone | A Debug build of the Swift in `ec4fb74` (5.7, build 150), installed 2026-10-12 at 21:25 PT once the app was seen not running, and not launched. It does not have the storage change unless the Verification section below records a later install. The device build of the tree this commit holds is at `/private/tmp/oi-install/OpenIntelligence.app` (built 2026-10-13 at 06:27 PT); `/private/tmp` does not survive a restart of the Mac. |
| Roadmap | 103 rows on `v5.7`: 64 In Progress and 39 To Do (queried 2026-10-13, after the row for the scoped search's ranking was added). None is Completed, because nothing in 5.7 has had its device check. One row was added to the backlog the same day (lexical recall). |

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
- 2026-10-12, 21:40 to 22:45 PT, the storage change: the vector store opens a library by indexing its
  passage file (`PassageFileIndex.swift`, new) and decodes a passage when asked; a save copies bytes instead
  of encoding every passage again; ten callers read only the passages they use. The file format is
  unchanged. On the Mac with 144,247 synthetic passages: load 1.97 s to about 0.62 s, memory after a load
  276 MB to 11 MB, the saves of building the library 60.8 s to 13.8 s. `CHANGELOG.md` (5.7, Changed, first
  entry) and the decision record of 2026-10-12 have the rest, including what it does not change.
- 2026-10-12 to 2026-10-13, the review of the storage change. A second agent was told to refute `1fdf69e`
  before it was pushed and found seven things, two of which could have damaged a library (a delete ended
  part-way could leave every passage on a neighbour's vector; `allChunks()` came back short when one passage
  failed to decode, and sync pairs it with the vectors by position). All seven are dealt with in the commit
  carrying this file: `CHANGELOG.md` (5.7, Changed, the second Indexing entry) lists them and the decision
  record "After review of the storage change" says what was chosen and what was rejected. The review also
  showed that a question limited to one document was ranked by its words alone, because the store hands
  passages back without vectors; that is fixed in `HybridSearchService.swift` only (5.7, Fixed, the
  Retrieval entry after "Ask About a Document").
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
  `BNNSVectorDatabase.swift` itself was edited for the storage change and its review, on his words "ok now
  do the storage change", with the file format untouched. Nothing else goes into that file without his word:
  a method that scores passages where the vectors are was written for the scoped search and taken out again
  for that reason. `WorkspaceSyncService.swift` was read and not edited in this change.
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
- `OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift` and `PassageFileIndex.swift` (the storage
  change), `OpenIntelligence/Services/VectorStore/VectorDatabase.swift` (the protocol's read methods, and the
  comment that says how a passage that cannot be read is treated),
  `OpenIntelligenceTests/Services/Storage/VectorStorePassageIndexTests.swift` (22 tests),
  `BNNSVectorDatabasePersistenceTests.swift` (10 tests, the cut-off saves and deletes) and
  `VectorStoreScaleBenchmarkTests.swift` (the benchmark; the runbook says how to run it).
- `OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift`, `searchInsideScope` and
  `storedSimilarities` (the scoped search's ranking), with three tests in `HybridSearchServiceTests.swift`.
- `OpenIntelligence/Services/Embedding/EmbeddingService.swift` (`EmbeddingProviderDefaults`),
  `OpenIntelligence/Services/Infrastructure/Presentation/AtlasLabeling.swift`,
  `OpenIntelligence/App/MetricDiagnostics.swift`, `OpenIntelligence/App/DebugEmbeddingBench.swift`.
- Local and git-ignored: `BenchmarkRuns/2026-10-10-large-library/` (the cost maps, the SDK surveys, and
  `W3-store-callers.md`, whose caller list was checked against a fresh search before the storage change), and
  `BenchmarkRuns/2026-10-12-docs-sync/` (the audit and the drafted decision records).

## Verification (2026-10-13, output read)

For the storage change as corrected by the review, on the tree this commit holds:

- Device build, simulator test build, the suite and the Mac build, one after another -> `BUILD SUCCEEDED`,
  `TEST BUILD SUCCEEDED`, `Executed 864 tests, with 4 tests skipped and 0 failures` (06:29 PT),
  `BUILD SUCCEEDED`. Skipped: the two `EmbeddingProviderAgreementTests` (no Core AI in the Simulator),
  `testInterleavedContentStreamIsReorderedByGeometry`, and the scale benchmark, which runs only when asked.
  Simulator `OI 5.7 tests`, `DE0883DB-2849-47F9-93AE-23C4E880FDED`.
- `VectorStoreScaleBenchmarkTests` with 144,247 passages, on files the 5.6 code had written, on files the
  first version wrote and on files this code wrote -> load 0.68 to 0.73 s in four runs where the 5.6 code took
  1.97 s (a fifth run, just after the Mac woke from sleep, read 1.31 s), 10 to 12 MB held after a load where
  it held 276 MB, the 49 saves of a build 15.5 and 16.3 s where they took 60.8 s, a delete 0.27 to 0.52 s
  where it took 2.31 s. The Mac slept from 23:49 to 05:34 in the middle of one set of runs; those runs are
  not used.
- The walk alone, compiled by itself, over the same 216 MB file -> every record equal to what `JSONDecoder`
  reads; 0.018 s on eleven threads optimised, 0.19 s unoptimised.
- The walk as committed over fresh copies of the nine metadata files on his iPhone (145,500 passages, the
  159 MB file among them; copied with `devicectl device copy from` on 2026-10-13, deleted afterwards) -> the
  same passages as the decoder in every file, every record equal, every byte range decoding to its passage;
  the 159 MB file in 0.015 s optimised and 0.17 s unoptimised on the Mac.
- `python3 scripts/verify_doc_claims.py`, `python3 .claude/codemap/codemap.py check` (after stamping eight
  slices) -> each passes; the commit's hook runs the first again with the secret scan.
- Not run: the app itself with this change, on his iPhone or on the Mac. Not tested: two stores open on one
  library's files at the same moment (sync opens a second one), and the `RAGService` call sites that were
  moved, apart from the suggested-question pool's selection.

Earlier, for `ec4fb74` (2026-10-12): 832 tests with 0 failures, both store-copy pushes and the App Review
addition accepted by App Store Connect, and the newest Xcode Cloud run still #485 four minutes after the push.
That tree's build went onto his iPhone at 21:25 PT with the app not running, and was not launched.

## Blockers / Unknowns

- **Nothing in 5.7 is closed.** Every row waits on being seen on a device. The list of checks, in the order
  they were written, is in the archive file under "Exact Next Action", items 1b and 3, and the checks still
  open for 5.6 follow them there.
- **Two lines in the store notes have not been seen to work:** "Open in" on iPhone and iPad, and dropping a
  file on the app's icon on the Mac. Verify by sending a PDF from Files' share sheet and by dropping a text
  file on the Dock icon. Row https://app.notion.com/p/3f449a74d54f8132a024ffec0182528a says what closes it.
- **The storage change has not been seen on a device.** Everything about it is measured on the Mac. On his
  iPhone, with the build that has it: read the `[VectorLoad]` line of a cold launch in
  `Documents/pipeline_trace.log` (it read 2.2 to 2.5 s in the six loads before this change, and a second line, "decoded every passage",
  now reports the decode that used to be inside the load), ask one question, and delete one document.
  The line in `Docs/USER_CHANGELOG.md` that says opening a library that size "still takes a few seconds" was
  left as it is until that figure is read; change it, and its mirror `OpenIntelligence/Resources/VersionHistory.md`,
  in one edit when it is.
- **Memory is unchanged once a question has been asked or the library analysis has run.** Eleven callers
  still read every passage's text: ten through `readableChunks()` (the question path, `refreshIntelligence`
  at launch and after an import, the pre-import analysis, the audit screen, the search-index rebuild, lexical
  recall) and the sync merge through `allChunks()`. Moving the question path onto the keyword index, and
  sampling the analysis without shifting the embedding plan it feeds, are each their own piece of work. The
  changelog entry lists the eleven.
- **The scoped search's ranking has not been seen on a device.** Row
  https://app.notion.com/p/3f849a74d54f81609d79e3a41e229eb1 says what closes it: a question from "Ask About a
  Document" whose log line reads `Document scope: scored N passages ... M of them by vector as well as by
  words` with M above 0. On his 144,247-passage document that search reads every passage's text and asks for
  the vectors 2,048 at a time, so expect it to be slow there; scoring them where they are needs a method in
  `BNNSVectorDatabase.swift`, which waits for his word.
- **Lexical recall keeps nothing with this vector store** on the search path a library takes without a keyword
  index (it wants a vector on each passage). Read from the code, not changed, filed in the backlog:
  https://app.notion.com/p/3f849a74d54f81eba369ff0faa1ba190, which also lists three other readers of a
  passage's own vector that were not checked.
- **A library with a passage that cannot be read does not sync.** It answers questions without that passage
  and its pipeline log says so; `allChunks()` refuses it, and the sync merge is `allChunks()`'s caller.
  Deleting the document, or importing it again, clears it. No such library is known to exist.
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

Put the build with the storage change on his iPhone when the app is not running there, and never launch it.
`xcrun devicectl device info processes --device 00008140-001130DA1863C01C` lists what is running; the app was
in that list at 06:35 PT on 2026-10-13. The build is `/private/tmp/oi-install/OpenIntelligence.app`; if the Mac
has been restarted since, build it again (`xcodebuild build` for `generic/platform=iOS`, Debug, from a copy of
the tree outside `~/Documents`, with `MARKETING_VERSION=5.7`) and install it with
`xcrun devicectl device install app --device 00008140-001130DA1863C01C <path to the .app>`.

When he has opened it, copy `Documents/pipeline_trace.log` out of the app's container and read two lines:
`[VectorLoad] vector_database_54E48F9A-...: <n>ms for 144247 chunk(s)`, which read 2,189 to 2,526 ms in the
six loads the log held at 22:43 PT on 2026-10-12 (builds without this change), and
`[VectorLoad] decoded every passage: 144247 in <n>ms`. If the first is not well under a second, the walk is
slow in an unoptimised build on the phone, and the place to look is `PassageFileIndex.scan` (it walks in
stretches on all processors; on the Mac the 159 MB file took 0.17 s unoptimised). Then the device checks under
Blockers, which decide whether 5.7's notes can stand.

After that, the work that would lower memory, in the order of least risk: let `refreshIntelligence` read a
sample of a large library (first make sure a sampled vocabulary cannot change the embedding plan it feeds,
`resolveAutoAdjustments` and `evaluateEmbeddingShift` in `RAGService.swift`), then move the question path's
six steps off the full array one at a time, each behind a test that it finds the same passages.
