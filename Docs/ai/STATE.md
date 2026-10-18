# Current State

Updated: 2026-10-18, 16:30 PT (5.7 is open and unreleased, no 5.7 build in TestFlight; 5.6 has been live on iPhone,
iPad and Mac since 2026-10-08; every commit since then is pushed with `[ci skip]`)
Branch/worktree: `main`, primary checkout
Last verified commit: 9e5a999

Earlier detail is in git: `git show 9c0d1dd:Docs/ai/STATE.md` (the night of 2026-10-17) and the copies it names; the
long record through 2026-10-10 is `Docs/Archive/STATE_record_through_2026-10-10.md`.

## Objective

**5.7 closes every open roadmap row and carries the owner's UI cleanup.** On 2026-10-18 he chose "Everything into 5.7"
over shipping 5.7 for its Nov 9 featuring window with the backlog in 5.8; that answer was his PROCEED: IMPLEMENT for
the plan. The cleanup is his list of 2026-08-10: every tab brought to one standard, Settings aligned with more control,
a modern picker for model and mode in chat (his choice), faster tab navigation, onboarding pointers in his words saying
the app runs on the device's hardware. The decisions are in auto memory `everything-into-5-7.md`.

## Status (2026-10-18, afternoon)

| What | Where it stands |
|---|---|
| Today's commits | `b70eea1` an answer's heading stays out of Fact Check, a bold sentence stays a claim, a citation leaves no gap, no token toast in the plain chat; `9e5a999` two Developer switches stop reverting, Deep Think's second research call applies the first call's checks. Both went through a refuting review that found defects, fixed before commit. |
| Roadmap | 40 Future Backlog rows moved to v5.7. 11 rows closed as decided, each Completed with a dated note (voting board, FTS5 trigram, CKSyncEngine, 86 MB model in git, Metal 4, iOS 27 OCR/Spotlight tools, OCR-a-region tool, visual retrieval, re-embed migration, thermal routing, cache warm). About 203 rows open. |
| Triage of all 214 open rows | `~/.agents/data/openintelligence-5.7-closeout/triage-2026-10-18/*.jsonl`, one line per row: state, check (simulator / unit-test / device / mac / benchmark / owner), evidence, what is missing, size. 147 built and waiting for a check (75 Simulator, 44 device), 27 part-built, 22 not started, 15 blocked on him. |
| UI audit | 41 screenshots of every tab, menu and Settings page and three contact sheets in `~/.agents/data/openintelligence-5.7-closeout/ui-audit-2026-10-18/`. Findings and the proposed cleanup are in this file under Blockers. |
| App Store media (not uploaded) | `~/Movies/App demos/OpenIntelligence/App Store/5.7 (2026-10-18)/`: the iPhone preview (19.4 s, 886x1920, 30 fps, H.264 High 4.0 with a silent stereo AAC track) and the 21:9 header loop (12 s, 3840x1646, 60 fps), with the raw take, plan and scripts. The preview's Fact Check row shows "except in an emergency ." (the gap `b70eea1` fixed), so it is refilmed before any upload. The live listing's iPhone preview is still the 5.1 video. |
| His iPhone | Development build of 9c0d1dd's app code, installed 2026-10-17 23:09. |
| Waiting on him | Picker style (A tidier chips, B one combined chip, C a mode bar; mockups shown 2026-10-18); localization languages; formatting his T7 drive as APFS (his Disk Utility step, then builds move to it, see Constraints). |

## Active Constraints

- A push whose newest commit lacks `[ci skip]` starts the first 5.7 Xcode Cloud build. Ask him first.
- Protected files he named on 2026-10-18 for this work: `project.pbxproj`, `WorkspaceSyncService.swift`,
  `BNNSVectorDatabase.swift`, `FoundationModelRoutePolicy.swift`, `FoundationModelSessionFactory.swift`, with his
  condition "Must be done flawlessly, without fucking anything up, and only if they're genuine full and well rounded
  improvements." Every change gets a refuting review (`reviewer` agent) before commit; both reviews today found real
  defects. Other hard-boundary files still need him to name them.
- App Store Connect writes and public pages only at his word; App Store Connect through `zsh -ic`.
- Never delete a doc, a benchmark run or a Notion row; no co-author lines; commit by name; leave `.agents/skills/` and
  `.codex/hooks*` alone. Edit Swift by script (the post-edit formatter rewraps whole files).
- One `xcodebuild` at a time; never edit the tree during a run; end only your own build by its process id; a test
  `xcodebuild` can hang after "Executed 1 test", so stop it 20 s later.
- **Disk and memory.** Free space swung between 1.7 and 13 GB on 2026-10-18 as swap went from 9 to 18 GB; Messages'
  `imagent` held 4 to 5 GB. The build guard killed one build at 1.7 GB. When his T7 shows up as `/Volumes/T7` (APFS),
  build output, source copies, demo copies and renders move there with a fallback to `/private/tmp` when it is absent,
  and nothing on it is ever the only copy (his rule: unplugging must never break anything).
- The Simulator now runs Apple's model through a demo copy: recipe in auto memory `simulator-demo-copy-pipeline.md`.
  Answers vary run to run; film or check until a clean take and read the tree in the log.

## Working Set

- Scratchpad `/private/tmp/claude-501/-Users-gunnarhostetler-Documents-GitHub-OpenIntelligence/02a2f913-1d63-449c-8ccc-8c198da128bc/scratchpad`:
  `build57.sh`, `cycle_lean.sh`, `uitests.sh`, `builddevice.sh` (test, device and Mac builds); `oi57h-build.sh` (demo
  copy build); `pvrec.sh` (film a scene, `OI_Q` sets the question), `pvtry.sh` (try a question without filming),
  `pvaudit.py` (photograph a scene's `shot-` marks); `pd/` (copies of PostDesk's demo tools).
- `/private/tmp/demodriver-pv` (this session's robot; scenes `OpenIntelligencePreview57Scenes.swift`,
  `OpenIntelligenceAuditTour.swift`), `/private/tmp/democut2-pv` (preview editor, boxed captions),
  `/private/tmp/stage3d-pv` (3D stage with a 21x9 shape; `oi57_header.py`).
- Demo copy source `/private/tmp/oi57-ios-src` (9c0d1dd plus PostDesk's five Simulator patches), build
  `/private/tmp/oi57-ios-dd`; simulator `OpenIntelligence 5.7 preview` `230C41D7-D64D-426E-B9E2-B0FF66BAF2ED`
  (iPhone 18 Pro Max, iOS 27.0, five sample PDFs in a Local Only library "Home", lifetime tier, no keys).
- Code touched today: `Core/Models/StructuredAnswer.swift`, `Services/RAG/Safety/VerificationGateService.swift`,
  `Services/RAG/Safety/SourceOnlyAnswerService.swift`, `Features/Chat/Conversation/ChatScreen.swift`,
  `Services/Infrastructure/Configuration/SettingsStore.swift`, `Services/Agentic/AgenticOrchestrator.swift`.

## Verification (2026-10-18, output read)

- `b70eea1`'s tree: TEST BUILD SUCCEEDED; `Executed 64 tests, with 0 failures` (HeadingClaimTests' ten and nine other
  classes) and `Executed 49 tests, with 0 failures` (gate and answer-path classes).
- `9e5a999`'s tree: TEST BUILD SUCCEEDED; `Executed 38 tests, with 0 failures`; the new settings test against the
  unfixed code: `Executed 1 test, with 7 failures`.
- `python3 scripts/verify_doc_claims.py` -> 961 claims, all match. `python3 .claude/codemap/codemap.py check` -> 0
  errors, 88 warnings (files from earlier 5.7 commits that no slice claims).
- Not run: the full suite since `3262001`; any of today's changes on a device or in the demo copy.

## Blockers / Unknowns

- **A second review of `b70eea1`** was running at 16:30; act on what it finds.
- **Onboarding's model step:** the `$selectedModel` sink in `SettingsStore.setupPipelines` has no `.dropFirst()`, so
  every launch marks the model as chosen by the person ("Selected by you") and ticks onboarding's
  `hasAcknowledgedModelSelection`, the only thing that ever ticks it. Fixing the sink alone would leave every new
  install's checklist at 2 of 3. Retire the step (Apple's models only, decided 2026-10-06) in the onboarding cleanup,
  then add `.dropFirst()`.
- `HybridSearchService.stableTieBreakKey` (line 203) is main-actor isolated by default and called from nonisolated
  code (`RAGEngine.swift:416`, `:1024`, `:1570`); mark it `nonisolated`.
- **UI cleanup, from the audit:** Intelligence Mode's 15-item feature wall and its badges ("98% target" is real: the
  Maximum loop stops at 0.98 confidence, `AgenticConfig.unlimited`; reword, don't delete), Apple Intelligence page
  jargon ("ADM 3", "AppIntents"), Device & Performance internals, the Database tab (SQLite FTS5, O(log n)), the
  Atlas ("PCA projection", cluster names like "Chicken & First"), the routing menu's "PCC (Requires Entitlement)",
  Siri & Shortcuts' hardcoded "10 of 10" and a hand list counting 27 of 35 actions, one title style per level. Plain
  by default behind the existing Technical Details switch.
- 44 device rows need his iPhone; Mac rows can run on this Mac.

## Exact Next Action

Rebuild the demo copy from HEAD: `git archive HEAD` into a new folder, run PostDesk's `patch_sim_switches.py` on it,
`rsync -a --checksum` it over `/private/tmp/oi57-ios-src`, run the scratchpad's `oi57h-build.sh
230C41D7-D64D-426E-B9E2-B0FF66BAF2ED`, install it, refilm with `OI_Q="How much notice does my landlord need to give
before entering?" pvrec.sh 230C41D7-D64D-426E-B9E2-B0FF66BAF2ED /private/tmp/oi57p-takes/preview5
OpenIntelligenceScenes/testPreview57` until the take's tree reads "1 Verified" with no gap before the full stop, then
recut with `/private/tmp/oi57p-cuts/preview-plan.json` (source and clip times updated to the new take's marks).
