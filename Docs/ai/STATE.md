# Current State

Updated: 2026-11-04 about 00:00 PT (5.8 open; all work committed locally with `[ci skip]`, nothing pushed. 5.7 is live on iPhone, iPad
and Mac since 2026-10-22, build 487. Xcode Cloud build 488 (`fb225053`) is VALID on both platforms and attached to
neither record.)
Branch/worktree: `main`, primary checkout
Last verified commit: b2fe74ca

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
| His devices | iPhone has the build of `b2fe74ca` (installed 2026-11-04, 5.8 build 150, telemetry and the save guard included; before that `3d7820d6`, 2026-11-03 about 23:55 PT, 5.8 build 150, telemetry included). The Mac's `/Applications` copy is older and lacks the one-engine fix and the telemetry: he copies `/private/tmp/oi58-mac-dd/Build/Products/Debug/OpenIntelligence.app` there (the copy is refused to agents). Keep the Mac app to one window until then |
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

When he is back: tell him the two test notes to delete in Library 6 and, if he wants their events, ask him to name `RAGAppIntents.swift` and
`WorkspaceSyncService.swift`. After a day of normal iPhone use (questions in Standard, Deep Think and Maximum; one Siri
and one Shortcuts request; a share), run `python3 scripts/phone_evidence.py --since <the morning, local time>` and close
every PASS row in Notion with its proof lines; for Mac rows, after he copies the Mac build to `/Applications`, run it
with `--mac`. After that, his stated next work is putting more behind the paywall (auto memory
`more-behind-the-paywall-is-next.md`).
