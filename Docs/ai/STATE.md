# Current State

Updated: 2026-10-19, 12:40 PT (5.7 is open and unreleased, no 5.7 build in TestFlight; 5.6 has been live on iPhone,
iPad and Mac since 2026-10-08; every commit since then is pushed with `[ci skip]`)
Branch/worktree: `main`, primary checkout
Last verified commit: 040951d

Earlier detail is in git: `git show 664e69b:Docs/ai/STATE.md` (the night of 2026-10-18) and the copies it names; the
long record through 2026-10-10 is `Docs/Archive/STATE_record_through_2026-10-10.md`.

## Objective

**5.7 closes every open roadmap row and carries the owner's UI cleanup** ("Everything into 5.7", 2026-10-18, his
PROCEED: IMPLEMENT; decisions in auto memory `everything-into-5-7.md`). The current thread, all at his word on
2026-10-18 and 10-19: make every device-specific line true (the GPU setting, the window, Deep Think's limits), decide the
GPU default by measurement, size graph packing to the device's window, and revamp the Knowledge Atlas's 3D view ("not
showing certain axes", "god mode, beautiful", an "all libraries" selection). On 10-19 he said "do. them. all."

## Status

| What | Where it stands |
|---|---|
| Atlas revamp | **Committed `13a42f5`.** Row `3fe49a74d54f81cc95faeeff91a69bc4` (In Progress). Closes on Mac screenshots and his look; the Simulator parts of its condition are met (below). |
| Device truth | `16d6827`, `081f49d`, `5a521b1`, `4fc6236`, `7b75138`, and `ab2a1fb` (the glossary's GPU entry). Row `3fe49a74d54f8164a5fee6f0f53805ec` (In Progress). Every Simulator part of its condition is met (2026-10-19, on the iPhone 15 Pro simulator: Device & Performance, the glossary's Context window technical text, an answer's details, the import panel's profile chip). Left: the Mac build showing 8,192, which needs his Mac and libraries. |
| Deep Think on A17 Pro | **Completed 2026-10-19.** Row `3fe49a74d54f8174886fed2904d86974`. On the iPhone 15 Pro simulator (`OI 5.7 A17 Pro` `0F072FEC-D590-4651-BCA8-D5D8D01E25FC`, demo copy of `040951d` with Release logging patched to info in `/private/tmp/oi57-ios-src` only) the trace logged `[Self-RAG 2.0] Starting verification` and `Verification complete: accept (relevance=91%, ...)`. |
| Graph packing | `749031e`. Row `3fe49a74d54f81d494a5f0842cb8f40e` (In Progress). |
| GPU default | Balanced stays (`Docs/ai/DECISIONS.md` 2026-10-19, `664e69b`). |
| Simulator memory | `ab2a1fb`: the Simulator reads the Mac's free memory. Before it, every Simulator run read "0 MB, Critical" and answered at `.efficient`, so earlier Simulator checks (and the 5.7 preview) ran a reduced pipeline. |
| His iPhone | Dev build of `16d6827` installed 2026-10-18; it reported 4,096 tokens and no background GPU (recorded in `Docs/LIMITATIONS.md` and the Atlas). |

## What the Atlas change does (so nothing is redone)

- The card (`CompactAtlasSceneView`) and full screen (`Fullscreen3DAtlasView`) draw `AtlasChart3D` (Swift Charts
  `Chart3D`), square in its frame, X/Y/Z on the chart, `AtlasAxisKey` under or beside it. The parent holds the pose.
- All Libraries: `RAGService.atlasGroupChoice` (space with the most passages), `atlasShares` (at most 6,000),
  `atlasSamplesForAllLibraries` (`dbForContainer`), `Fullscreen3DAtlasView.distinctLibraryColors`.
- `chunksForVisualization` samples from `visiblePassageRecords` (no documents in their undo seconds) and keeps only
  full-size vectors (`passagesWithVectors`); `passageCountForActiveContainer` counts the same passages.
- All three views load on `AtlasContentKey` (records the key when a load finishes, `settlesFirst` waits 0.8 s when only
  the count moved, because `reembedDocuments` flips `isProcessing` per document).
- The "3D Semantic Map" tile and its insight open the full screen. The Embedding Space explorer (`EmbeddingSpaceView`)
  is reachable from no screen; it keeps SceneKit (framing fixed, `SceneBuildKey`).
- Measured with a probe app (`scratchpad/c3dprobe`, iOS 27 Simulator): Chart3D sizes its cube from the frame's longer
  side, its x/y/z selection reports nothing for a tap, a pinch doesn't zoom, `symbolSize` floods the chart. All in auto
  memory `swift-charts-chart3d-measured.md`.

## Active Constraints

- A push whose newest commit lacks `[ci skip]` starts the first 5.7 Xcode Cloud build. Ask him first.
- Protected files (`project.pbxproj`, `WorkspaceSyncService.swift`, `BNNSVectorDatabase.swift`,
  `FoundationModelRoutePolicy.swift`, `FoundationModelSessionFactory.swift`): "Must be done flawlessly ... only if
  they're genuine full and well rounded improvements." None touched today. `RAGService.swift` is Tier 2.
- App Store Connect writes and public pages only at his word. Never delete docs, benchmark runs, Notion rows or agent
  histories; no co-author lines; commit by name; leave `.agents/skills/` and `.codex/hooks*` alone. Edit Swift by script.
- A development build on his Mac opens his real libraries: don't launch one without asking. The plan sheet in the
  Simulator loads real App Store prices; never tap its buttons.
- Verify Apple API claims on developer.apple.com (`https://developer.apple.com/tutorials/data/documentation/<path>.json`)
  or the SDK's `.swiftinterface`, and date them.

## Working Set

- Scratchpad `/private/tmp/claude-501/-Users-gunnarhostetler-Documents-GitHub-OpenIntelligence/02a2f913-1d63-449c-8ccc-8c198da128bc/scratchpad`:
  `build57.sh` (`OI_SCRATCH=/private/tmp`; `build-for-testing <log>` / `test-without-building <log> [-only-testing:...]`),
  `buildmac.sh`, `pvaudit.py <udid> <out> <Class/test>` (robot runner, screenshots at each `shot-` mark), `sheet.py`
  (contact sheets), `c3dprobe/` (the Chart3D probe app, built with `swiftc`), `changelog-b.md`, `commit-a.txt`.
- Robot: `/private/tmp/demodriver-pv` (xcodegen project; `xcodegen generate` after adding a scene file). Scenes added
  today: `testAtlasAngles`, `testExplorer`, `testAllLibrariesTwo`, `testAllLibrariesTwoFromFile`, `testDeviceTruth`,
  `testDeepThinkA17` (`OpenIntelligence*Scenes.swift`), and `Chart3DProbeScenes` (selection, pinch, framing, size).
- Test simulator `OI 5.7 tests` `0FBB8C16-CB05-4DF2-A018-670190834AB6` (iPhone 18 Pro, iOS 27.0): holds a second
  library "Product Notes" added by hand to the app's `containers.json` plus the Ingestion Pipeline doc. Hosted unit tests
  share that data: `ShortcutsActionTests.testAskAnswersFromANoteAddedThroughAddToLibrary` fails while two libraries
  exist (another test's engine writes the saved active library). Reinstall the app before a full suite:
  `xcrun simctl uninstall <udid> Gunndamental.OpenIntelligence` then `install` the Debug app from
  `/private/tmp/oi-build/Build/Products/Debug-iphonesimulator/`. The Files app's On My iPhone holds
  `Ingestion Pipeline.md` (a copy of `Docs/INGESTION_PIPELINE.md`) for the robot's file imports.

## Verification (2026-10-19, output read)

- Final tree (`ab2a1fb` plus the user-note sentence): `** TEST BUILD SUCCEEDED **` (iOS Simulator), `** BUILD SUCCEEDED **`
  (Mac, `buildmac.sh`), no warnings in changed files; full suite on a clean install of `0FBB8C16-...`:
  `Executed 1233 tests, with 7 tests skipped and 0 failures`; after the user-note sentence, VersionHistoryTests and
  WhatsNewCoverageTests: `Executed 7 tests, with 0 failures`.
- `codemap.py check`: 0 errors, 108 warnings. `verify_doc_claims.py`: all claims match. `secret_scan.py`: clean.
- Robot shots (`scratchpad/final-*`, `r2-*`, `r3-atlas`): the card and full screen at seven angles with 31 and 218
  passages, the cube and axes in frame at each; All Libraries with General and Product Notes in one map, the angle kept
  across the scope switch, the two in indigo and orange; Settings, Device & Performance reads 8,192 tokens and, after
  `ab2a1fb`, "Available RAM 3.6 GB, Full Quality" where it read "0 MB, Critical, Power Saver".
- Two refuting reviews of the Atlas change (21 findings, then 12); every confirmed one fixed or recorded in CHANGELOG 5.7.

## Blockers / Unknowns

- Mac screenshots of the Atlas and the Mac's 8,192 in the Glossary need a run on his Mac with his libraries: ask him to
  open the Atlas there, or for a go-ahead to launch a development build.
- Not measured: Chart3D's cost at 6,000 passages on a phone (the full screen now starts with Rotate off).
- Review questions left open: #7 (the live session counter counts research calls past the chain's 8), #16 (no test
  reaches `backgroundImportNote`, the overlay or `continuedProcessingPolicy`).
- Onboarding's model step: the `$selectedModel` sink in `SettingsStore.setupPipelines` has no `.dropFirst()`.

## Exact Next Action

Read the open v5.7 rows (the SQL in `.claude/skills/notion-roadmap/SKILL.md`, with `WHERE "Status" != 'Completed' AND "Target Release" = 'v5.7'`)
and take the next one whose closing condition the Simulator can meet. Two rows wait on his Mac: the Atlas row
(`3fe49a74d54f81cc95faeeff91a69bc4`, Mac screenshots and his look) and the device-truth row (`3fe49a74d54f8164a5fee6f0f53805ec`,
8,192 in the Mac's Glossary and Context Window card); ask him once whether to launch a development build on his Mac.
