# Current State

Updated: 2026-10-13, 13:15 PT (5.7 is open and unreleased; the storage change of 2026-10-12 is on origin as `1fdf69e` and `c73b3b9`; the work that followed it on 2026-10-13, at the owner's go-ahead for everything that change had left open, is in the commit that carries this file, marked `[ci skip]`; the 5.7 store notes are on both App Store Connect records and nothing is submitted; 5.6 has been live on iPhone, iPad and Mac since 2026-10-08, build 485)
Branch/worktree: `main`, primary checkout
Last verified commit: c73b3b9

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
in the decision record of 2026-10-10, which `1fdf69e` builds and `c73b3b9` corrects after a review. On
2026-10-13 he answered the list of what that change had left open with a go-ahead for all of it; the commit
carrying this file is that work.

## Status (2026-10-13)

| What | Where it stands |
|---|---|
| 5.7 source | `c73b3b9` and everything before it is on origin. The commit carrying this file follows it. `git rev-list --count origin/main..HEAD` prints 0 when everything is pushed; if it prints more, push with the newest commit still marked `[ci skip]`. |
| Tests | 892 run, 0 failures, 5 skipped (two need Core AI, one layout test, and the two scale benchmarks, which run only when asked), 2026-10-13 at 11:52 PT, with a device build before it and a Mac build after. |
| App Store Connect | 5.7 exists on both platforms in PREPARE_FOR_SUBMISSION, release set to manual, no build. Release notes pushed 2026-10-12 (Mac 20:11 PT, iPhone and iPad 20:16 PT). App Review's notes carry the 5.7 addition and are at 3,990 of 4,000 characters. |
| TestFlight | No 5.7 build has ever been made. Every 5.7 push carried `[ci skip]`, and four minutes after the 20:59 push the newest Xcode Cloud run was still #485, the 5.6 build of 2026-10-08. |
| His iPhone | A Debug build of the Swift in `ec4fb74` (5.7, build 150), installed 2026-10-12 at 21:25 PT once the app was seen not running, and not launched. It has neither the storage change nor this commit's work. The device build of this commit's tree is staged at `/private/tmp/oi-install/OpenIntelligence.app` (built 2026-10-13 at 11:45 PT; `/private/tmp` does not survive a restart). The app was running on the phone at every check from 06:35 to 13:09 PT, so nothing was installed. A script of the session that wrote this file was left polling from 13:10 PT to install it the first time the app is absent from two process listings in a row; it gives up after six hours and never launches the app. |
| Roadmap | 104 rows on `v5.7`: 65 In Progress and 39 To Do (queried 2026-10-13, after the row for the launch analysis was added). None is Completed, because nothing in 5.7 has had its device check. One row was added to the backlog the same day (lexical recall). |

## Completed (2026-10-10 to 2026-10-13, this session)

- 2026-10-10 to 2026-10-12: the 88.50 MB JSON Lines import finished on his iPhone as 144,247 passages (his
  words and screenshots). Committed: the sync guard during an import, the embedder default (Core ML for a
  new library on iPhone and iPad, Core AI on macOS 27), the sampling limits for a very large library,
  MetricKit diagnostics kept on the device, two system model tools wired in and off, the Background GPU
  Access entitlement, Atlas names from the library's own words, the corrections from an audit of 67 stale
  statements in the docs and the app's own text, thirteen decision records, and the store notes for both
  platforms. `git show c73b3b9:Docs/ai/STATE.md` lists each with its evidence.
- 2026-10-12 to 2026-10-13, the storage change and its review (`1fdf69e`, then `c73b3b9`): the vector store
  opens a library by indexing its passage file (`PassageFileIndex.swift`) and decodes a passage when asked;
  a save copies bytes instead of encoding every passage again. The file format is unchanged. A second agent
  told to refute it before the push found seven things, two of which could have damaged a library, and all
  seven are dealt with in `c73b3b9`. `CHANGELOG.md` (5.7, Changed, the two Indexing entries about the
  vector store) and the decision records of 2026-10-12 and "After review of the storage change" have it.
- 2026-10-13, after the storage change, at his go-ahead for everything it had left open. Found by timing
  it: the library analysis that ran at every launch took 199 s, and 1,054 MB over what the process held, on
  the 144,247-passage benchmark store. It now reads at most 4,000 passages, and its report and the first
  question's vocabulary are kept on disk until the library's documents change (`LibraryIntelligenceCache`).
  With it: the vocabulary build, the picking of the sample and the audit's word count moved off the main
  actor; an import in pieces ends with the same refresh as any other; a question inside one very large
  document scores every vector in the store and compares words for its candidates only; the audit no longer
  reports every passage as a dimension mismatch; the search-index rebuild reads one document at a time; on
  iPhone and iPad a library lets go of its decoded passages when the app goes to the background; parent
  expansion looks only at the documents it needs. Two full reviews by a second agent (18 and 13 findings)
  and a short third (8) came before the push; the changes made for the third were not reviewed again.
  `CHANGELOG.md` (5.7: under Changed, the Indexing entries that begin "Opening a library no longer
  analyses", "The storage audit" and "The search-index rebuild", and the Retrieval entry "Parent
  expansion"; under Fixed, "A question limited to a document is ranked by meaning") and the two decision
  records dated 2026-10-13 say what each changed and what each review found.

## Active Constraints

- **A push whose newest commit lacks `[ci skip]` starts the first 5.7 Xcode Cloud build and puts it in
  TestFlight.** He has not asked for one. Ask before sending it.
- Hard-boundary files are edited only when he names the file. Named for 5.7: `RAGAppIntents.swift`,
  `Info.plist`, `OpenIntelligence.entitlements`, `EngineSDKCompatibility.swift`, `project.pbxproj`,
  `WorkspaceSyncService.swift`, and the tool registry work. Not named: `ChatMessage.swift`, the billing files,
  the `SQLiteFullTextService.swift` schema, the `BNNSVectorDatabase.swift` format,
  `FoundationModelSessionFactory.swift`, `FoundationModelRoutePolicy.swift`, `Package.swift`.
  `BNNSVectorDatabase.swift` itself was edited for the storage change and its review, at his word for that
  change, with the file format untouched. On 2026-10-13 it got two additions that read and do not write:
  `similarities(to:forChunkIDs:)` and the release of decoded passages (`releaseDecodedPassages(because:)`,
  `releaseCount`). The report before them had said the first waited on his word for that file; he answered
  with a go-ahead for everything in it, and the agent read that as his word and told him so. **He did not
  name the file himself.** If that reading was wrong, both come out without touching anything stored (the
  protocol's default then answers `similarities` from `getEmbeddings(forChunkIDs:)`). Nothing further goes
  into that file without his word. `WorkspaceSyncService.swift` and `SQLiteFullTextService.swift` were read
  and not edited.
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
- `Docs/ai/DECISIONS.md`, the records dated 2026-10-09 to 2026-10-13, the storage plan among them.
- `Docs/Release/APP_STORE_METADATA_HISTORY.md`, `### 5.7`: the store notes as pushed, per platform.
- `fastlane/metadata/en-US/release_notes.txt` (Mac), `fastlane/metadata-ios/en-US/release_notes.txt` (iPhone
  and iPad), `fastlane/review_notes/5.7.txt`.
- `OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift` and `PassageFileIndex.swift` (the storage
  change, and the two read-side additions of 2026-10-13), `VectorDatabase.swift` (the protocol's read
  methods), `OpenIntelligenceTests/Services/Storage/VectorStorePassageIndexTests.swift` (24 tests),
  `BNNSVectorDatabasePersistenceTests.swift` (10 tests) and `VectorStoreScaleBenchmarkTests.swift`.
- `OpenIntelligence/Services/Embedding/AdaptiveEmbeddingOptimizer.swift` (`LibraryIntelligenceCenter`,
  `samplePositions`, `LibraryIntelligenceCache`), and in `RAGService.swift`: `refreshIntelligence`,
  `removeStaleKeptAnalysis`, `generateIntelligenceSnapshot`, `libraryAnalysisInput`, `libraryVocabulary`,
  `vocabularyMayBeKept`, `resolveAutoAdjustments`, `holdsAReadablePassage`, `vectorAuditFigures`. Tests:
  `OpenIntelligenceTests/Services/Embedding/LibraryAnalysisSampleTests.swift` (14) and
  `OpenIntelligenceTests/Services/Storage/LibraryAnalysisScaleBenchmarkTests.swift` (the benchmark; the
  runbook's "Timing the vector store" says how to run it).
- `OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift`, `searchInsideScope` and
  `closestPositionsOffMainActor`, with nine tests in `HybridSearchServiceTests.swift`;
  `ParentDocumentService.swift` with `ParentDocumentServiceTests.swift` (5).
- `OpenIntelligence/Services/Embedding/EmbeddingService.swift` (`EmbeddingProviderDefaults`),
  `OpenIntelligence/Services/Infrastructure/Presentation/AtlasLabeling.swift`,
  `OpenIntelligence/App/MetricDiagnostics.swift`, `OpenIntelligence/App/DebugEmbeddingBench.swift`.
- Local and git-ignored: `BenchmarkRuns/2026-10-10-large-library/` (the cost maps, the SDK surveys, and
  `W3-store-callers.md`), `BenchmarkRuns/2026-10-12-docs-sync/` (the audit and the drafted decision records)
  and `BenchmarkRuns/2026-10-13-launch-analysis/` (the analysis and store timings, with a README).

## Verification (2026-10-13, output read)

For the tree this commit holds:

- Device build, simulator test build, the suite and the Mac build, one after another -> `BUILD SUCCEEDED`
  (11:45 PT), `TEST BUILD SUCCEEDED`, `Executed 892 tests, with 5 tests skipped and 0 failures` (11:52 PT),
  `BUILD SUCCEEDED` (11:56 PT). Skipped: the two `EmbeddingProviderAgreementTests` (no Core AI in the
  Simulator), `testInterleavedContentStreamIsReorderedByGeometry`, and the two scale benchmarks. Simulator
  `OI 5.7 tests`, `DE0883DB-2849-47F9-93AE-23C4E880FDED`.
- `LibraryAnalysisScaleBenchmarkTests` on the 144,247-passage store -> the analysis as it ran through 5.6:
  199.1 s and 1,054 MB over what the process held (11.4 s for 6,000 passages, 43.4 s for 24,000). The
  sampled path: 6.54, 6.06, 6.11 and 6.22 s for 3,999 passages, 0 to 4 MB added, the same recommended
  plan (the last run at 11:58 PT, on this tree). The vocabulary build: 2.57 to 2.65 s.
- `python3 scripts/verify_doc_claims.py` -> 854 claims checked, all match. `python3
  .claude/codemap/codemap.py check` -> 0 errors and 0 warnings after the changed slices were refreshed.
  `python3 scripts/secret_scan.py` -> nothing found. The commit's hook runs the first and the last again.
- Not run: the app itself with any of this, on his iPhone or on the Mac. No test builds `RAGService`, so
  these are read from the code and not exercised: the calls that remove kept files, the refresh after an
  import in pieces, the two call sites of `libraryVocabulary`, and which actor each piece runs on.

Earlier, for `c73b3b9` (the storage change as corrected, 2026-10-13 at 06:29 PT): 864 tests with 0 failures;
`VectorStoreScaleBenchmarkTests` with 144,247 passages (load 0.68 to 0.73 s where the 5.6 code took 1.97 s,
10 to 12 MB held after a load where it held 276 MB, the 49 saves of a build 15.5 and 16.3 s where they took
60.8 s); and the file walk checked against fresh copies of the nine passage files on his iPhone (145,500
passages, no differences, copies deleted). `git show c73b3b9:Docs/ai/STATE.md` has those blocks in full.

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
- **Memory still rises to about 330 MB for the 144,247-passage library at the first question.** The question
  path, lexical recall and the sync merge read every passage's text. The launch analysis, the audit, the
  index rebuild and a large scoped search no longer do, and on iPhone and iPad the decoded passages are let
  go when the app goes to the background. What that gives back on a device is not measured: read the app's
  footprint in Xcode's memory gauge, or `[BNNS] Released N decoded passage(s): the app left the foreground`
  in the log. Moving the question path onto the keyword index is retrieval work and is not started.
- **The launch analysis and its kept files have not been seen on a device.** Exact Next Action says which
  log lines settle it. Row https://app.notion.com/p/3f849a74d54f8133b045db2c09a0ba2a says what closes it.
- **He has not confirmed that his go-ahead covered `BNNSVectorDatabase.swift`.** See Active Constraints. Ask
  him; the report of 2026-10-13 put the question at its top.
- **Most of a question's own work still runs on the main actor.** `RAGService` and `HybridSearchService` are
  main-actor classes by the module's default isolation. The vocabulary build was moved off it on 2026-10-13;
  the scoring loops (bounded since 2026-10-10) and, in debug builds with the pipeline trace on,
  `runViscosityScan` were not. Measure a first question on the phone with the 144,247-passage library
  before moving more.
- **The scoped search's ranking has not been seen on a device.** Row
  https://app.notion.com/p/3f849a74d54f81609d79e3a41e229eb1 says what closes it: a question from "Ask About a
  Document" whose log line reads `Document scope: scored N of M passages ... K of them by vector as well as
  by words` with K above 0. On his 144,247-passage document the line before it reads `Document scope: 144247
  passages is past 6000, so every vector was scored and words were compared for the 2000 closest and N
  keyword hit(s)`.
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

Put the build of this commit's tree on his iPhone when the app is not running there, and never launch it.
`xcrun devicectl device info processes --device 00008140-001130DA1863C01C` lists what is running. The build
is `/private/tmp/oi-install/OpenIntelligence.app` (2026-10-13 at 11:45 PT); if the Mac has been restarted
since, build it again (`xcodebuild build` for `generic/platform=iOS`, Debug, from a copy of the tree outside
`~/Documents`, with `MARKETING_VERSION=5.7`) and install it with
`xcrun devicectl device install app --device 00008140-001130DA1863C01C <path to the .app>`.

Both builds on the phone and staged read 5.7 (150), so the version does not say which one is installed. Two
things do. The script left polling writes its last lines to `install_when_idle.out` in
`/private/tmp/claude-501/-Users-gunnarhostetler-Documents-GitHub-OpenIntelligence/02a2f913-1d63-449c-8ccc-8c198da128bc/scratchpad/`
(`INSTALLED` with a time when it did). And only this build writes lines that begin `[Intelligence] Library`
to the app's `Documents/pipeline_trace.log`.

When he has opened the app twice, copy `Documents/pipeline_trace.log` out of the app's container and read:

- `[VectorLoad] vector_database_54E48F9A-...: <n>ms for 144247 chunk(s)`. It read 2,189 to 2,526 ms in the
  six loads before the storage change. If it is not well under a second, look at `PassageFileIndex.scan`.
- First launch: `[Intelligence] Library <id>: analysed N of 144247 passages in <n>ms`, with N at or just
  under 4,000. That <n> is the first figure anyone has for this on a phone.
- Second launch: `[Intelligence] Library <id>: using the analysis kept on disk`. If it analyses again, the
  kept file's name did not match the library: list
  `Library/Application Support/OpenIntelligence/LocalCache/LibraryIntelligence` in the container after each
  launch and compare the two names (`<library>.report.<hash of the documents>.<passages>.json`); the hash is
  `LibraryIntelligenceCache.documentsSignature`, over each document's id, file hash, passage count, date
  and name.

Then the device checks under Blockers, which decide whether 5.7's notes can stand.
