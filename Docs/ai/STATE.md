# Current State

Updated: 2026-10-18, 22:40 PT (5.7 is open and unreleased, no 5.7 build in TestFlight; 5.6 has been live on iPhone,
iPad and Mac since 2026-10-08; every commit since then is pushed with `[ci skip]`)
Branch/worktree: `main`, primary checkout
Last verified commit: 35aae34

Earlier detail is in git: `git show 35aae34:Docs/ai/STATE.md` (the evening of 2026-10-18, before this change) and the
copies it names; the long record through 2026-10-10 is `Docs/Archive/STATE_record_through_2026-10-10.md`.

## Objective

**5.7 closes every open roadmap row and carries the owner's UI cleanup** ("Everything into 5.7", 2026-10-18, his
PROCEED: IMPLEMENT; decisions in auto memory `everything-into-5-7.md`). Tonight's piece, at his word on 2026-10-18:
"That one is device specific and you need to make sure that's conveyed and documented properly everywhere relevant"
(he chose the GPU setting, the context window and Deep Think's limits), then "Crank all of them. Enable them. Make them
collaborate/activate when they're supposed to be" after learning the CPU/GPU/Neural Engine text had been untrue.
His plan, as told to him: (1) make every hardware and device line true, (2) decide the default GPU profile and the
background GPU path by measurement, (3) size the Standard packing budget (`RAGService` `graphTokenBudget`, 6,000) to
each device's window.

## Status (2026-10-18, 22:40 PT)

| What | Where it stands |
|---|---|
| Step 1, "device truth" | **Uncommitted, 28 tracked files plus `OpenIntelligenceTests/Services/Infrastructure/Monitoring/BackgroundGPUAllowanceTests.swift` and `BenchmarkRuns/2026-10-18-compute-plan/` (git-ignored evidence).** A refuting review (reviewer agent) found 12 defects and 4 questions; all fixed in the tree (text that was still false: page cleanup, the background line, tiers vs chip families, Deep Think's stop rule and research rounds). The tree as it stood before those fixes built (`TEST BUILD SUCCEEDED`); the fixed tree's build and full suite were running at 22:40 (`build57.sh`, see Verification). |
| CHANGELOG | **Not yet in `CHANGELOG.md`.** The four entries are drafted in the scratchpad file `changelog-hw.md`; two end in the placeholder `VERIFY_LINE`, to be replaced with the test result. They go at the end of the 5.7 `### Fixed` list, just before `### Changed`. The pre-commit hook refuses the commit without CHANGELOG. |
| Release notes | `WHATS_NEW.md`, `Docs/USER_CHANGELOG.md`, `OpenIntelligence/Resources/VersionHistory.md` already edited (identical bullets, Settings section). |
| Roadmap | New rows, both v5.7: "The GPU setting claimed work the code didn't do..." `3fe49a74d54f8164a5fee6f0f53805ec` (In Progress; closes on Simulator screenshots of the new text plus the Mac build showing 8,192), and "Deep Think on an iPhone 15 Pro skips the Self-RAG check that newer devices run" `3fe49a74d54f8174886fed2904d86974` (To Do). Added at 22:35 at his word: "Revamp the Knowledge Atlas 3D view: axes go missing as the graph turns, and it needs an All Libraries view" `3fe49a74d54f81cc95faeeff91a69bc4` (To Do, High; his words and the plan are in the row: reproduce by dragging the graph in the Simulator, survey the best 3D embedding views and Apple's 3D frameworks on developer.apple.com, add All Libraries). |
| His iPhone | Development build of 9c0d1dd's app code from 2026-10-17. He was told a build of this change would be installed over Wi-Fi once it is committed, for him to open in the morning. |
| Waiting on him | Picker style (A, B or C); localization languages. |

## What the change does (so nothing is redone)

- `GPUExecutionProfile.engagement` builds each profile's list from the rules the app runs (`coreMLComputeUnits`,
  `embeddingComputeUnits`, new pure `cleansScannedPagesOnGPU` = an extra Core Image pass over a rendered PDF page,
  `searchesLargeLibrariesOnGPU` = Metal for 1,000+ passages and MMR over 50). Maximum = Performance while the app is
  open. `gpuConcurrency` (only the Live Activity's "Nx GPU") removed.
- `BackgroundGPUAllowance` (DeviceCapabilityService.swift) holds the per-device background-GPU thresholds, battery
  floors and the A17 Pro iPhone charging rule, shared by `BackgroundTaskService.continuedProcessingPolicy` and Settings'
  `backgroundImportNote`; `BackgroundTaskService.systemOffersBackgroundGPU` reads `BGTaskScheduler.supportedResources`.
- Import panel's GPU button (IngestionQueueOverlay) now writes the real profile; the Live Activity names the profile.
- Context window: `FoundationModelTokenBudget.reportedOnDeviceContextSize`; Glossary, model card, chat gauge, sample
  docs and three example questions use the device's figure.
- Deep Think: chain stops at 8 sessions on every device; device tiers set the confidence target (85 to 95%), steps,
  tokens; Settings, the thinking line, the badge and the Glossary say so.
- Chip claims removed or corrected: an answer's details, Library Settings' Accelerate line, the search screen's Core AI
  label, the silicon card, the sample docs' Silicon HUD paragraph.
- Also in the tree from before: the Apple Intelligence page's plain-words subtitles (`ui4.py`), a changelog entry drafted.

## Active Constraints

- A push whose newest commit lacks `[ci skip]` starts the first 5.7 Xcode Cloud build. Ask him first.
- Protected files (`project.pbxproj`, `WorkspaceSyncService.swift`, `BNNSVectorDatabase.swift`,
  `FoundationModelRoutePolicy.swift`, `FoundationModelSessionFactory.swift`): his condition "Must be done flawlessly,
  without fucking anything up, and only if they're genuine full and well rounded improvements." None is in this change.
- App Store Connect writes and public pages only at his word. Never delete docs, benchmark runs, Notion rows or agent
  histories; no co-author lines; commit by name, never `git add .`; leave `.agents/skills/` and `.codex/hooks*` alone.
  Edit Swift by script (the post-edit formatter rewraps whole files).
- Verify every Apple API claim on developer.apple.com (JSON endpoint `https://developer.apple.com/tutorials/data/documentation/<path>.json`)
  and cite the date; he asked again on 2026-10-18 that nothing be guessed.
- **Memory and disk.** This 18 GB Mac swaps hard: compiling `RAGService.swift` grows swap by about 5 GB, and the build
  guard (`guard.inc`, `GUARD_DISK_MB`) stopped four builds that night when free disk fell under its floor. World of
  Warcraft (6 GB), Messages' `imagent` (4.4 GB) and Codex (4.4 GB) held most of the memory. At 22:08 34 GB was freed: the
  iOS 18.0 and 18.3 simulator runtimes (back again after his 2026-09-29 delete) and the iOS 27.0 (24A437) DeviceSupport
  folder (his iPhone is on 27.0.1).
- **Every simulator was deleted at 22:07:48** (CoreSimulator log: "Delete device request", no requester), including
  `OI 5.7 tests` `3982899B-...` and `OpenIntelligence 5.7 preview` `230C41D7-...` (the preview's demo-copy library is
  gone with it). New test simulator: `OI 5.7 tests` `0FBB8C16-CB05-4DF2-A018-670190834AB6` (iPhone 18 Pro, iOS 27.0).
- The T7 (`/Volumes/T7`, plugged back in) is not used tonight: builds run with `OI_SCRATCH=/private/tmp`.

## Working Set

- Scratchpad `/private/tmp/claude-501/-Users-gunnarhostetler-Documents-GitHub-OpenIntelligence/02a2f913-1d63-449c-8ccc-8c198da128bc/scratchpad`:
  `build57.sh` (now `SIM=0FBB8C16-...`; `build-for-testing <log>` or `test-without-building <log>`; with
  `OI_SCRATCH=/private/tmp` it builds in `/private/tmp/oi-build` and tests there directly), `guard.inc`, `builddevice.sh`
  (device build to his iPhone over Wi-Fi), `changelog-hw.md` (the CHANGELOG entries to insert), `rv1.py`, `hw1-7.py`,
  `cw1-2.py`, `docs1-2.py`, `notes1.py`, `emb1.py` (the edit scripts, for reference), `unitprobe/` (the Core ML plan probe).
- Logs: `hw-build9.log` and `hw-test9.log` (the run started at about 22:20 on the new simulator).

## Verification (2026-10-18, output read)

- The tree before the review fixes: `** TEST BUILD SUCCEEDED **` (`hw-build6.log`), warnings in changed files: none new.
- `BenchmarkRuns/2026-10-18-compute-plan/README.md`: M3 Pro, macOS 27.0, `MLComputePlan`: MiniLM Core ML 150 of 161
  ops on the Neural Engine under `.all`; reranker 55 of 66; MiniLM fastest on this Mac's GPU (4.78 ms vs 6.90).
- Apple pages read 2026-10-18: `BGContinuedProcessingTaskRequest.Resources.gpu`, `BGTaskScheduler.supportedResources`,
  the GPU entitlement, Accelerate's overview (CPU), Foundation Models (no chip named), `MLComputeUnits` cases, TN3193.
- **Not yet run on the fixed tree:** the build, the full suite, `bash scripts/build_simulator_smoke.sh`,
  `python3 scripts/verify_doc_claims.py`, `python3 scripts/secret_scan.py`, `python3 .claude/codemap/codemap.py check`.

## Blockers / Unknowns

- Whether iOS offers his iPhone background GPU (Settings' new line will say), and what window his iPhone reports
  (Context Window card). Only his phone answers both.
- Review questions left open: #7 (the live session counter counts research calls past the chain's 8), #16 (no test
  reaches `backgroundImportNote`, the overlay or `continuedProcessingPolicy`).
- Onboarding's model step: the `$selectedModel` sink in `SettingsStore.setupPipelines` has no `.dropFirst()` (retire the
  step, then add it).

## Exact Next Action

1. Read `hw-test9.log` (`grep -E 'Executed [0-9]+ tests|error: -\[' hw-test9.log`). If it is missing or the run
   stopped (exit 143, "hung before establishing connection"), rerun:
   `OI_SCRATCH=/private/tmp GUARD_DISK_MB=3000 bash <scratchpad>/build57.sh build-for-testing <scratchpad>/hw-build10.log`
   then `test-without-building <scratchpad>/hw-test10.log`.
2. When the suite passes, put the four entries from `changelog-hw.md` into `CHANGELOG.md` (end of 5.7 `### Fixed`),
   replacing each `VERIFY_LINE` with the measured line, then run `python3 scripts/verify_doc_claims.py` and
   `python3 scripts/secret_scan.py`.
3. Commit by name (every path in `git status --porcelain` except `.agents/`, `.codex/`), message starting
   "5.7: the GPU setting, the window and Deep Think's limits are this device's own" and ending `[ci skip]`; push.
4. Install on his iPhone with `builddevice.sh` (read it first; pass the 5.7 MARKETING_VERSION), only if `devicectl device
   info processes` shows the app is not open.
5. Then step 1b: the hardware X-Ray credits the Neural Engine for Core AI (GPU) embeddings and for cloud answers
   (`HardwareActivityType.primaryComponent`, reporters in EmbeddingService, LLMService, RAGEngine, DocumentProcessor),
   and the embedding labels the app inventory found (AboutView has no Core AI case; ContainerSettingsSheet
   `friendlyProviderName` calls Core AI "Apple Natural Language"; DocumentDetailsView's nil id; AdaptiveVisualizationsView's
   fixed 512; onboarding's "via Neural Engine" import stage).
6. Then the Atlas revamp row above (he wants it "god mode, beautiful"); start from the codemap feature `embedding-visualizations-and-3d`.
