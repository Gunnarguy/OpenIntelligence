# Current State

Updated: 2026-11-04 (5.8 open; all work committed locally with `[ci skip]`, nothing pushed. 5.7 is live on iPhone, iPad
and Mac since 2026-10-22, build 487. Xcode Cloud build 488 (`fb225053`) is VALID on both platforms and attached to
neither record.)
Branch/worktree: `main`, primary checkout
Last verified commit: 97c1cb93

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
| His devices | iPhone has the build of `97c1cb93` (installed 2026-11-03 about 21:35 PT). The Mac's `/Applications` copy is the build of `02158436` and lacks the one-engine fix: he must copy `/private/tmp/oi58-mac-dd/Build/Products/Debug/OpenIntelligence.app` there (the copy is refused to agents). Keep the Mac app to one window until then |
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

- Tree of `97c1cb93`: `xcodebuild test-without-building` on the iOS 27 Simulator -> 1,456 tests, 8 skipped, 0 failures
  (555 s); Mac `xcodebuild build` -> BUILD SUCCEEDED; iPhone build installed (5.8 build 150).
- `RebuildKeepsDocumentIdTests` 2 of 2 twice (same id, no deletion, passages back; all five documents restored at the
  Free plan's limit, both through the full re-import path); `AppServicesTests` 1 of 1; `ObservedChangeThrottleTests` 3 of 3.
- `python3 scripts/phone_evidence.py --since 2026-11-03T18:30` -> 6 PASS, 0 FAIL, 28 NOT SEEN (no questions were asked
  on either device that day, so every answer, Siri, Shortcuts and PCC row is unseen).
- The macOS unit-test target does not build ("Unable to resolve module dependency: 'OpenIntelligence'"), so no unit
  test has run on the Mac.

## Blockers / Unknowns

- 101 moved rows each say what closes them: most need him to use the iPhone (ask questions in each mode, Siri, Shortcuts,
  share, scan, dictate), about 15 need the Mac by hand, a few need him (TestFlight, offer code, App Store Connect).
- The blank Chat while switching libraries is not explained; the journal now records `chat.appear`, `chat.disappear`,
  `library.setActive`.
- Future Backlog row `40e49a74d54f81a0a963d0f0231776eb`: the relaunch passages check runs before the first sync pass, so
  the device opened second rebuilds documents the other already rebuilt.
- Future Backlog row `40e49a74d54f811ba216d705d776e3fc`: a tour tip may take the first tap; seen only in a laggy Simulator.

## Exact Next Action

When he is back: ask him to copy the Mac build to `/Applications`, then use the iPhone normally for a while (questions in
Standard, Deep Think and Maximum; one Siri and one Shortcuts request; a share), then run
`python3 scripts/phone_evidence.py --since <that morning>` and close every PASS row in Notion with its proof lines. After
that, his stated next work is putting more behind the paywall (auto memory `more-behind-the-paywall-is-next.md`).
