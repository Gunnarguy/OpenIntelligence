# Current State

Updated: 2026-10-18, 22:45 PT (5.7 is open and unreleased, no 5.7 build in TestFlight; 5.6 has been live on iPhone,
iPad and Mac since 2026-10-08; every commit since then is pushed with `[ci skip]`)
Branch/worktree: `main`, primary checkout
Last verified commit: 5a521b1

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
| Step 1, "device truth" | **Committed and pushed as `16d6827`** ("5.7: the GPU setting, the window and Deep Think's limits are this device's own", `[ci skip]`), after a refuting review whose 12 defects were fixed. What it does is listed below. |
| Roadmap | New rows, both v5.7: "The GPU setting claimed work the code didn't do..." `3fe49a74d54f8164a5fee6f0f53805ec` (In Progress; closes on Simulator screenshots of the new text plus the Mac build showing 8,192), and "Deep Think on an iPhone 15 Pro skips the Self-RAG check that newer devices run" `3fe49a74d54f8174886fed2904d86974` (To Do). Added at 22:35 at his word: "Revamp the Knowledge Atlas 3D view: axes go missing as the graph turns, and it needs an All Libraries view" `3fe49a74d54f81cc95faeeff91a69bc4` (To Do, High; his words and the plan are in the row: reproduce by dragging the graph in the Simulator, survey the best 3D embedding views and Apple's 3D frameworks on developer.apple.com, add All Libraries). |
| His iPhone | **Development build of `16d6827`, 5.7, installed 2026-10-18 22:39 over Wi-Fi** (`builddevice.sh` with `OI_SCRATCH=/private/tmp`, then `devicectl device install app`; the app was not open). He was asked to look at two things only the phone can answer: the window its Context Window card shows (Settings, Device & Performance) and the line under the GPU choices (whether iOS offers it background GPU). |
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
- `16d6827`'s tree, iOS 27 Simulator `0FBB8C16-...`: `TEST BUILD SUCCEEDED`; `Executed 1215 tests, with 7 tests skipped
  and 3 failures`, all in `AtlasLabelingTests` on the brand-new simulator, which then passed alone (`Executed 20 tests,
  with 0 failures`). `verify_doc_claims.py`: 968 claims, all match. `secret_scan.py`: clean. Phone build: `XCODEBUILD_EXIT=0`,
  installed (`devicectl device info apps`: 5.7).
- After `16d6827`: `bash scripts/build_simulator_smoke.sh` (through `smoke_guarded.sh`, simulator `0FBB8C16-...`): `** BUILD SUCCEEDED **`, `SMOKE_EXIT=0`. `codemap.py check`: 0 errors after the onboarding slice's quoted line was updated to the new example question (102 warnings, among them the new `BackgroundGPUAllowanceTests.swift`, unmapped).

## Blockers / Unknowns

- Whether iOS offers his iPhone background GPU (Settings' new line will say), and what window his iPhone reports
  (Context Window card). Only his phone answers both.
- Review questions left open: #7 (the live session counter counts research calls past the chain's 8), #16 (no test
  reaches `backgroundImportNote`, the overlay or `continuedProcessingPolicy`).
- Onboarding's model step: the `$selectedModel` sink in `SettingsStore.setupPipelines` has no `.dropFirst()` (retire the
  step, then add it).

## Exact Next Action

1. Ask him what his iPhone showed in Settings, Device & Performance: the Context Window card's figure and the line under
   the GPU choices. Record both (the window in `Docs/LIMITATIONS.md` beside the Mac's 8,192, the background GPU answer
   in the Atlas paragraph on background GPU), dated, as measured on his iPhone 16 Pro Max.
2. Done 2026-10-19 in `081f49d` (full suite 1215 tests, 0 failures): the embedding-label part of step 1b (Library Settings,
   About, the 384D option, the Atlas view's 512, onboarding's import log, the empty library) and the codemap entry for the
   new test. Left of step 1b: the X-Ray's attribution (item 4).
3. Close row `3fe49a74d54f8164a5fee6f0f53805ec` on Simulator screenshots of Settings, Device & Performance, the Glossary
   and an answer's details (the robot's `OpenIntelligenceScenes/testAuditTour` through `pvaudit.py`; the preview
   simulator it used was deleted, so it needs a new simulator and the demo copy, `demo_refresh.sh <udid>`).
4. Step 1b, done 2026-10-19: `5a521b1` (the X-Ray lights the embedding provider's chip and the reranker's only when the
   cross-encoder runs; an answer's details name the Neural Engine again, because Apple's 2024 research article says the
   on-device model's key-value cache runs on its neural engines, and the release note that said otherwise is withdrawn)
   and the commit after it (a Private Cloud Compute answer lights no chip, `LLMService.generate`). Left: Vision OCR is
   reported as `.reranking` (`DocumentProcessor`, the OCR pulse) with a unit Vision chooses; Settings' X-Ray switch
   says "Real-time model routing and token telemetry" and its Live Metrics switch "Show ops count and latency in
   legend", neither of which the X-Ray shows (`SettingsView`, Appearance).
5. Row `3fe49a74d54f8174886fed2904d86974`, fixed in `5a521b1` (In Progress): closes on a Deep Think run in a Simulator
   set up as an iPhone 15 Pro whose log shows the Self-RAG lines (needs the demo copy, `demo_refresh.sh <udid>`).
6. The Atlas revamp row above (he wants it "god mode, beautiful"); start from the codemap feature
   `embedding-visualizations-and-3d`.
7. Steps 2 and 3 of his plan: measure the default GPU profile (Metal against Accelerate on a large library on this Mac;
   the embedder on the GPU against the Neural Engine, which differ by device per the compute-plan run) and size
   `graphTokenBudget` to the device's window.
