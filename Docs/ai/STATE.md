# Current State

Updated: 2026-11-05 about 17:45 PT (5.8 open; all work committed with `[ci skip]` and pushed to origin/main on 2026-11-05 evening (through 2f443996, then the citation fix after it). 5.7 is live on iPhone, iPad
and Mac since 2026-10-22, build 487. Xcode Cloud build 488 (`fb225053`) is VALID on both platforms and attached to
neither record.)
Branch/worktree: `main`, primary checkout
Last verified commit: 2f443996

## Objective

**Finish 5.8 so the owner can move on to more behind the paywall** (his words 2026-11-03: "only have 5.8 stuff showing
so I can finally move on to the next parts of this app, like even putting more stuff behind the paywall"). The board is
now 5.8 and Future Backlog only. What remains is checks on his iPhone and Mac, then shipping 5.8 when he says so.

## Status

| What | Where it stands |
|---|---|
| Roadmap | 2026-11-04 night: every In Progress row of 5.0 to 5.7 was read. 5 closed with device proof (document without passages repaired after a library switch; MetricKit reports read back; per-state metrics; import background task ran; Library 6's `_norms.bin` off the iPhone, 8,182 vectors, 0 zero). The other 101 moved to 5.8, each with a dated note "Moved to 5.8 … Closes when … Needs …". Now: 5.8 In Progress 119, 5.8 To Do 30, Future Backlog 9, nothing open in older releases |
| Rebuild loop between devices (row `40d49a74d54f81dbb75bd6daf9309f50`) | Built `77aeedfa`, `50ebc713`, `02158436`: a rebuild keeps each document's id, record and file and records no deletion; it joins the Live Activity and asks for continued processing; a saved rebuild item gets `evaluateSemanticIndexHealth` at relaunch instead of a restart (the queue file is shared, so it can hold another device's). Closes on both devices running 5.8 with no `Wiping orphaned vector database chunks` on one after the other rebuilds |
| One engine per launch (row `40e49a74d54f819ebd0dd44c102c37fd`) | Built `97c1cb93`: `AppServices.shared` (`OpenIntelligence/App/AppServices.swift`) builds the engine, sync, libraries, billing, plan, settings and model resolution once; `ContentView` observes them. Two Mac windows had started the same rebuild twice 29 ms apart. Closes on two Mac windows logging each event once |
| Atlas | Built `a19e107d`: topics once, library-wide counts, the random-colour heatmap and the "coming soon" document network removed |
| Sync | Freeze fix and orphaned-copy cleanup `5c13a375`; iCloud-change passes throttled `77aeedfa` (`ObservedChangeThrottle`). The triggers inside `WorkspaceSyncService.swift` (watcher sees a pass's own writes; 2 s debounce) are unchanged and need him to name the file |
| 5.8 copy | What's New (now 15 items), `Docs/USER_CHANGELOG.md` and its byte copy `VersionHistory.md`, `WHATS_NEW.md`, both `release_notes.txt`, the `### 5.8` entry in `APP_STORE_METADATA_HISTORY.md`. **Not pushed to App Store Connect** |
| His devices | iPhone runs the build of `e83502fb` (pause and resume in the background, one answer card, off-main suggestion sampling). The build of `9917b9d4` + `3f2d40b9` is built (`/private/tmp/oi58-dd/Build/Products/Debug-iphoneos/OpenIntelligence.app`) and waits to install: scratchpad `install_when_idle.sh` was polling for the phone, which read "unavailable" (needs it unlocked and in reach). The Mac's `/Applications` copy is older: he copies `/private/tmp/oi58-mac-dd/Build/Products/Debug/OpenIntelligence.app` there (refused to agents) |
| Fixed 2026-11-04, committed | HUD Spacer loop (`2ba01e81`); answers pause in the background and resume (`a3046281`); crash on return from suggestion sampling, one answer card, cleaner Live Activity (`e83502fb`); **Developer & Diagnostics rebuild loop** (`9917b9d4`: `DeveloperDiagnosticsHubView` built a new `SettingsStore` on every redraw, which saved every setting and rebuilt the model service without end, 17 min on his iPhone, answers stalled; it takes the app's store now), plus a routing-signature guard in `SettingsStore.applySettingsDebounced` and plan reuse in `QueryExecutionPlannerService.buildPlan` (one Deep Think question plans once instead of three times; not yet measured on the device) |
| Tip X needing several taps | Not reproduced. `TourTipCloseUITests` (`3f2d40b9`) closes the first two Settings tips and "Want to see the work?" in Appearance with one tap each, HUD off and on, all pass. His journal (pull `2026-11-04_145216`, pid 7358) shows the tip up at 17:10:34 UTC with the main thread free afterwards; taps are not journaled. The HUD window hides while anything is presented, so it can't cover a tip |
| Deep Think speed, still open | Side jobs now yield to the answer (decode 8-9 to 18-19 tok/s; Deep Think 4:31 then 3:56). Done 2026-11-04 night: one shared Core ML embedding provider (`EmbeddingService.sharedCoreMLProvider`; every search used to reload the tokenizer and 43 MiB model, about 0.6 s per sub-query on his iPhone), and one library analysis at a time (`refreshIntelligence` worker). Left: plan reuse and the provider change measured on the device; the ranked list in the speed audit (below) |
| Speed audit, 2026-11-04 night | At his request ("make this app and all parts of each and every process lightning speed while retaining every bit of accuracy"). Research and measurements in `BenchmarkRuns/2026-11-04-speed-research/` (gitignored): measured budget from his iPhone (Deep Think 236 to 271 s, model calls 59 to 78%), Apple SDK 27 and WWDC26 findings, papers, a code inventory, main-thread findings, Mac Foundation Models probes, the off-main embedding patch with its Simulator numbers. Report page published as a private artifact. Skill `.claude/skills/measure-speed` holds the method. Three items wait for his word: the background Neural Engine entitlement `com.apple.developer.background-tasks.continued-processing.inference` (`OpenIntelligence.entitlements`, hard boundary; iOS 27 blocks the Neural Engine in the background without it), the off-main embedding patch (provider internals out of bounds; +49% in the Simulator, 240 of 240 vectors identical), and the slim MACHINE-MAP (`~/.agents/MACHINE-MAP.slim.draft.md`, 15 contradictions listed in the report). A chat-history-off-main change was reverted before commit (a review found it could save one library's conversation into another); its row is in Future Backlog with the design it needs |
| His three decisions, 2026-11-05 | He said yes to all three. (1) Off-main embedding is in: `CoreMLSentenceEmbeddingProvider` is `nonisolated`, `@concurrent` `embed`/`embedBatch`, tokenizer behind `tokenizerLock`, ingestion flag under `modelLock`, `embedBatch` loads the model once before fanning out (reviewer's finding). Row `40f49a74d54f81ed8ff4c73eeab5d415` in 5.8 In Progress; closes on an import on his iPhone at or above the old throughput with no hang reports. (2) The background inference entitlement is in: the App ID `66ZHDUSVAQ` lacked the capability and the App Store Connect API cannot add it, so it was turned on at developer.apple.com (Background Inference, `BACKGROUND_PROCESSING_INFERENCE`; Apple warned existing profiles must be regenerated), the key went back into `OpenIntelligence.entitlements`, and the iPhone build signed with it. Untested: a Mac build and the first Xcode Cloud build with the key. Row `40f49a74d54f81e691f1c552e094e373`; closes on a background rebuild on his iPhone near the foreground's 47.0 passages/s. (3) The slim MACHINE-MAP is installed: `~/.agents/MACHINE-MAP.md` 25,774 chars, dated history in `~/.agents/MACHINE-LOG.md`, original kept as `~/.agents/MACHINE-MAP.full-2026-11-05.bak.md`; the split check found 0 of 1,041 sentences missing; one stale line (MMT-2025's deploy) fixed |
| 2026-11-05 afternoon | Committed `fb5f0107`: the source-only check stops before its two model calls when it could only keep the answer (exact; `SourceOnlyVerdictTests` walks 504 outcomes; 46.6 s on his iPhone 2026-11-04, 1 of 3 checks in his traces). His stress test at 11:34 to 11:41 on the build of `78ab05f8` (journal and trace in `~/Library/Developer/OpenIntelligence-evidence/2026-11-05_114329`, facts in `BenchmarkRuns/2026-11-04-speed-research/phone-2026-11-05-stress-test.md`) filed three 5.8 rows: answer ended unfinished (`40f49a74d54f812dbdd8fd628b622299`), Chat blank during an answer (`40f49a74d54f81eb9b32d9ec3292c817`), progress panel count, HyDE label and the X-Ray outline (`40f49a74d54f81b4b22bc0b52bf566c8`; the box is `HardwareXRayOverlay`'s Neural Engine outline, by design). **Uncommitted, not yet built:** live session count during an answer (`ChatScreen.consolidatedMetricsData`), Gate 2 renamed "Query Expansion" in Deep Think and Maximum (`VerificationGatesOverlayView`, `Glossary`), the Atlas keeps its profile for unchanged inputs and waits while an answer runs (`LibraryVisualizationEngine.analyzedInputs`, `AdaptiveVisualizationsView.refreshAnalysis`), the parent-expansion sibling lookup by document (`RAGService.performFullRetrievalPipeline`), and the golden harness (`DeepThinkRetrievalGoldenTests`, `scripts/golden_retrieval.py`, the Debug window override in `FoundationModelTokenBudget`, `executeMultiQuerySearch` made internal). |
| Telemetry (`3d7820d6`) | 78 new development-journal events, `os` on every line, a Debug-only `MainThreadWatchdog`, test hosts write nothing; `scripts/phone_evidence.py` has 96 rules plus `--mac`, `<=`, `!=`, `absent` and local-time `--since` (`Docs/ai/RUNBOOK.md`). Events that need a hard-boundary file were left out: `RAGAppIntents.swift` (patch saved in session scratchpad `a4f11230-.../scratchpad/ragappintents_telemetry.patch`; 3 rules wait on it), `WorkspaceSyncService.swift` (`sync.conflictCopies`, `sync.fileFromICloud`, `sync.threads`, `sync.vectorStoreSkipped`, `sync.orphanFileDeleted`), `BNNSVectorDatabase.swift` (`vectorStore.save/load`) |
| Mac crash, row `40e49a74d54f81099f05c28eb6c091f1` | `BNNSVectorDatabase.writeMetadataFile` trapped (`Data` subscript, line 605 of the crash report `~/Library/Logs/DiagnosticReports/OpenIntelligence-2026-11-03-222028.ips`) when a passage's place ran past the mapped metadata, during a self-healing rebuild with an import into the same library. Guard committed 2026-11-04 at his word ("just proceed implement"): the run join stops at such a slot and the save throws `storeFailed`, leaving the old file in place. Why the records and the file disagree is not established. Closes when the Mac, running a build with the guard, goes through a self-healing rebuild plus import without a crash |
| Lost files | MoreMacintoshToolbox.pdf (Library 3), a Library 2 PDF and AAMI-ST79-2017-COMPLETA-ESPANOL.pdf (library deleted) are saved in `~/Downloads/OpenIntelligence recovered 2026-11-03` for him to re-import |

## Active Constraints

- Every commit ends with `[ci skip]` until he asks for a build. App Store Connect writes and public pages only at his word.
- Hard-boundary files need him to name them (`Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md`). Source edits need PROCEED: IMPLEMENT.
- Never delete docs, benchmark runs, Notion rows or agent histories; commit by name; no co-author lines; leave
  `.agents/skills/`, `.codex/*` and `scripts/run_quality_matrix.py` alone; edit Swift by script.
- A row closes only on proof where the defect appears ("Fixed is not closed").
- One `xcodebuild` at a time. Builds run from `/private/tmp/oi58-src` (scratchpad `build58.sh`, `run_full.sh`).

## Working Set

- `OpenIntelligence/App/AppServices.swift`, `ContentView.swift`: one service set per launch.
- `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift`: `reembedDocuments`, `removeDocument(forRebuild:)`,
  `addDocument(documentId:)`, `listImportedDocument`, `restorePersistedIngestionQueueIfNeeded`, `nextQueuedIngestionItem`.
- `RAGService+Streaming.swift`, `RAGService+TextStreaming.swift`: rebuild under the same id, saved session cleared.
- `OpenIntelligence/App/ObservedChangeThrottle.swift`; `Features/Telemetry/Visualizations/AdaptiveVisualizationsView.swift`,
  `Services/Infrastructure/Presentation/LibraryVisualizationEngine.swift`, `AtlasLabeling.swift`.
- `scripts/phone_evidence.py` pulls the iPhone's journal and trace; the last pull is
  `~/Library/Developer/OpenIntelligence-evidence/2026-11-03_211350/`.

## Verification (output read)

- Working tree after `a0602f1c` (off-main embedder + review fixes): iOS 27 Simulator build-for-testing -> TEST BUILD SUCCEEDED, 0 warnings on the provider; `EmbeddingConcurrencyIdentityTests` 4 passed (180 passages concurrent vs one at a time, max abs diff 0; 16 cold first callers; 16 callers on a warm provider; ingestion mode toggled mid-batch, cosine > 0.99), `IngestionModeSwitchTests` 2 passed; the same 6 under `-enableThreadSanitizer YES` -> passed, 0 ThreadSanitizer warnings. Generic iOS device build (signed with the App Store Connect API key, no new certificate) -> BUILD SUCCEEDED. `verify_doc_claims.py` 1,568 claims match; codemap check 0 errors 0 warnings; `secret_scan.py` clean.

- Tree of `1f1d9cb3` (shared Core ML provider, analysis worker, ingestion-mode count): iOS 27 Simulator build-for-testing -> TEST BUILD SUCCEEDED, no warnings on the changed lines; `LibraryAnalysisSampleTests` 14 passed (the first run hung before connecting, passed after a simulator reboot), `EvidenceThreadStoreTests` 12, `IngestionModeSwitchTests` 2, `ShortcutsActionTests` 13, 0 failures. Two adversarial reviews of the diff; the first found a data-loss race in a chat-history change, which was reverted before commit.
- Off-main embedding patch (build copy only, not committed): `-embeddingBenchProviders` in the Simulator 19.0/14.4/16.3 -> 21.8/25.9/26.3 passages/s; `sample` main thread idle 1,627 of 1,634 after; identity test 240 of 240 vectors bit-identical.
- `python3 scripts/verify_doc_claims.py` -> 1,567 claims, all match. `python3 .claude/codemap/codemap.py check` -> 0 errors, 0 warnings at `9dc6d34e`.
- Tree of `9917b9d4`: `DiagnosticsSettingsLoopUITests` on a wiped iOS 27 Simulator -> before the fix 182 `settings.set` per key and 92 "Updated model:" in about 35 s; after -> 1 and 1, test passed. Generic iOS device build -> BUILD SUCCEEDED.
- Tree of `3f2d40b9`: `TourTipCloseUITests` -> 3 tests passed (list tips, Appearance tip HUD off, HUD on). The full suite was not rerun after `13bf9400`.
- Tree of `13bf9400`: iOS 27 Simulator full suite -> 1,463 tests, 3 failures, all in `AtlasLabelingTests` on a freshly erased simulator; that class rerun alone -> 26 tests, 0 failures. `SettingsRowsUITests` on the code before the fix -> all 7 rows shut (HUD off and on); after -> 2 tests, 0 failures. Mac Debug build and iPhone build -> BUILD SUCCEEDED; `devicectl device install` -> "App installed".
- Tree of `3d7820d6` (less one RUNBOOK sentence): iOS 27 Simulator `test-without-building` -> 1,461 tests, 8 skipped,
  0 failures (517 s; the first launch hung before connecting, the second ran); Mac Debug build -> BUILD SUCCEEDED;
  Release iOS Simulator build -> BUILD SUCCEEDED; `python3 scripts/test_phone_evidence.py` -> 16 tests OK; device
  install -> "App installed".
- Tree of `b2fe74ca`: iOS 27 Simulator full suite -> 1,461 tests, 8 skipped, 0 failures (529 s; first launch hung again, second ran); Mac Debug build and generic iOS device build -> BUILD SUCCEEDED; `devicectl device install` -> "App installed".
- `python3 scripts/phone_evidence.py --dir <empty dir>` -> 96 rules, all NOT SEEN (the rules parse).
- macOS unit tests: build with `SDKROOT=macosx` (RUNBOOK `## Test`). `SpeechTranscriptionTests` passed on the Mac
  (2 tests, 1 skipped for Speech Recognition permission). **The whole Mac suite must not be run**: on 2026-11-03 it ran
  hosted in his real Mac container, imported and removed ~40 test notes in Library 6, ran answer-mode, active-library
  and create-library actions on his settings, and crashed once (above). Nothing of his was deleted (every removed name
  was a test name; Library 6 holds 7,573 passages with matching vectors and norms). Left behind in Library 6:
  `enrichment-undo-A7A97B1B.txt` and `Shortcuts test DCB0EB71.txt`, which iCloud will carry to the iPhone.

## Blockers / Unknowns

- 101 moved rows each say what closes them: most need him to use the iPhone (ask questions in each mode, Siri, Shortcuts,
  share, scan, dictate), about 15 need the Mac by hand, a few need him (TestFlight, offer code, App Store Connect).
- The blank Chat while switching libraries is not explained; the journal now records `chat.appear`, `chat.disappear`,
  `library.setActive`.
- Future Backlog row `40e49a74d54f81a0a963d0f0231776eb`: the relaunch passages check runs before the first sync pass, so
  the device opened second rebuilds documents the other already rebuilt.
- Future Backlog row `40e49a74d54f811ba216d705d776e3fc`: a tour tip may take the first tap; seen only in a laggy Simulator.

## Exact Next Action

**The RAGService/AgenticOrchestrator split is committed** as `d355dda5` ("Split RAGService and AgenticOrchestrator
into files by job, a pure move"; pushed 2026-11-05). Its first citation pass skipped 18 follow-ons written ":N" after "and" or "or" (13 in CANONICAL, 2 RETRIEVAL_PIPELINE, 2 PRIVACY_AND_ROUTING, 1 Atlas); fixed in the commit after 2f443996 by the same line map, and `BenchmarkRuns/2026-11-05-file-split/translate_citations.py` now accepts them. verify_doc_claims 0 failures at that commit (citations pinned to older commits now read `File.swift@sha:N`). A Debug device build of it was started 2026-11-05 evening and installs on his iPhone once it answers with the app closed (`BenchmarkRuns/2026-11-05-file-split/device_split.sh`, log `/private/tmp/oi58-device-split.log`); if the session ended first, check `xcrun devicectl device info apps` against the build time. Proven and read before committing: the move check (0 lines added or lost; original order
except the 5 stored properties moved into the class by design; 236 access keywords removed across 204 names, no call can
bind differently); iOS Simulator build-for-testing, macOS Debug build and iOS Release build all succeeded; golden harness
760 of 760 identical to the code before the split in the same simulator state; full suite 1,199 passed, the 16 failures
all simulator state (free-plan limit filled by the golden library, a language asset after an erase, a duplicate note
left by a run the owner's closing the simulators cut off) and each passing on a clean `OI 5.8 checks`; a Fable 5.1
review found no behaviour change; codemap 0 errors, 0 warnings.

**Waiting for the owner's "go"** to run `BenchmarkRuns/2026-11-05-file-split/OVERNIGHT.md` on the other 15 large
files. The scripts there take any file as of 2026-11-05 evening: `access_loop.sh <label> <globs>`, `fix_access.py`
(setter search limited to the globs), `prove_move.py --plan` (move, order and access-keyword counts; on the committed
split against `e68facb2` it still reads 0 added, 0 lost, 236 removed) and `translate_citations.py --old/--merge/--base`
(one run per file; it refuses a second). A dry run of `split_type.py` plus `prove_move.py --plan` on the SemanticChunker
and SuggestedQuestionsService drafts read 0 added and 0 lost. Still for the night itself: name each `plans/*.json` by
job (the drafts are cut by size: SQLiteFullTextService's first group takes the singleton, properties and init out of
the main file) and write plans for the four files without one (DocumentLibraryView, LLMService, VisualizationsView,
ContainerSettingsSheet+Sections). A stray
`.git.nosync/.DS_Store` is reported by `scripts/check_icloud_conflicts.sh`; harmless (not in `refs/`), and the
permission check refused deleting it, so the owner removes it if he wants.

**Overnight: the other 15 large files** (owner, 2026-11-05 evening: "I'm gonna name those files those excluded ones so like whatever needs to be done to literally square all this off"; that names the hard-boundary `WorkspaceSyncService.swift` and `SQLiteFullTextService.swift` for a pure move only: no change to the FTS5 schema or to sync behaviour, proven by the move check). Runbook: `BenchmarkRuns/2026-11-05-file-split/OVERNIGHT.md`.

After the split: a separate, reviewed commit for the main-actor warnings in `CoreMLSentenceEmbeddingProvider.swift`
(lines with `DeviceCapabilityService.shared`, `MLArrayBufferSet`; from `b70da2d3`, no race found by the 2026-11-05
review); the 5.8 user copy (What's New, `Docs/USER_CHANGELOG.md`, release notes) for the week's user-visible changes;
then the speed list in `BenchmarkRuns/2026-11-04-speed-research/` (one evidence session, prewarm, planner schema,
parallel sub-searches) and the three 2026-11-05 rows from his stress test.
