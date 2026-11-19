# Current State

Updated: 2026-11-19 10:35
Branch/worktree: `main`, primary checkout
Last verified commit: bcb9f12e

## Objective

**Ship 5.8 to App Review today** (owner, 2026-11-19: "in review in the next like 3 hours"). He tests on his iPhone; the
agent reads his trace, fixes what it shows, and keeps the device-pass page https://claude.ai/artifact/RyYN25e7RGMAFthrKnBtNT
ticked (ArtifactData collection `pass`, doc `checks`, version 9, 14 ticked). He said "stop submitting archives until we
square this stuff away": no Xcode Cloud build until his tests pass. Submitting is his word alone; ask once.

## Status

Main is at bcb9f12e, pushed, every commit `[ci skip]`. iPhone runs a Debug build of bcb9f12e (installed 10:24:37, first
launch 10:27:34; first-load compile 47 s embedder, 66 s reranker, as after every install). Mac /Applications runs the same
code (Debug, `/private/tmp/oi-mac-dd`). The Mac redesign (6122d185, 19f31f53) is on main. The Maximum A/B ended: the
18/20 was variance and the fix stays (a982716c, ledger).

App Store Connect is staged for 5.8 on both platforms (PREPARE_FOR_SUBMISSION; iOS version 36314c13-d814-479f-8f11-95c2d8ea6794,
Mac 387cf5c0-eee7-41a5-8e4f-bd562435b1e0): per-platform release notes, promo text, description, keywords, screenshots and
review notes (1,822 characters) were written and read back. No build is attached yet.

## Completed on 2026-11-19 (pushed)

| Commit | What |
|---|---|
| 6122d185, 19f31f53 | Mac redesign: sidebar window, Settings window, Documents details as an `HSplitView` pane (two inspectors crashed AppKit), Chat row selectable (`.badge` before `.tag`) |
| d43158e5, ec78e1de | In-app What's New for 5.8; App Store copy for both platforms, review notes, metadata history, Mac screenshot boxes |
| a292e89d, 00c2f8cc, 62b5dad7, 7ed65fec | Core ML embedder uses CPU and Neural Engine whenever the app is in the background (`DeviceCapabilityService.isAppInBackground`, set by ContentView): first load, pending switch, retry, and a prediction that starts in the background on GPU units. Seen on the phone 09:40 and 10:00 |
| 0a2e346a | Siri and Shortcuts no longer wait forever after a rate limit: only a Chat answer waits for the app to return; an action asks once to come forward, then retries and reports failure |
| e99bd165 | Search model and reranker warm up one second after each return to the front, once per launch |
| bcb9f12e | The on-device window keeps its last positive reading when `contextSize` reads 0 in the background (`FoundationModelTokenBudget.lastOnDeviceContext`); an answer resumed there had been packed to 800 characters and wrongly said the guide had no chicken temperature (165°F in front). 84 tests passed |

## Known and not fixed

- Identical files under two names import as one ("Already imported"), so the device pass's Kestrel prompt (the same PDF
  twice) cannot be set up as written; the queue card said "Paused after app restart" though the app had not restarted.
- Mac: Services Ask fills the other window's field with two windows open; Finder Add on an iCloud file not downloaded
  shows nothing for about 2 minutes (the Mac session lists both as follow-ups).
- The answer scorer (`scripts/score_answer_eval.py`) fails a right refusal that later lists any dollar amount.
- Held for after 5.8, Future Backlog rows, patches in `BenchmarkRuns/2026-11-18-held-after-5.8/`: Standard's planner
  model call (2.5 to 12 s before every question), and the case-insensitive Code/Standard spec patterns.

- Search setup after an install took 55 to 99 s (embedding) and 87 to 131 s (reranker) on his iPhone at thermal state serious.
- Main-thread stalls on Chat during rebuilds (worst 1,658 ms); the `@concurrent` fix (641c7aa9) is not yet seen on the
  phone. Next: `bash scripts/profile_phone.sh` while he rebuilds one library.
- The app never says the phone's storage is full (Future Backlog 41b49a74d54f81eebbc3fbbee08a878d).
- Open UI asks with no answer: the Standard picker on the Mac lacks its capsule; the colour and icon pickers; repeated plan-card bullets.
- `AtlasLabelingTests` adverb tests depend on the simulator having English word classes (skip on a fresh one).
- Axis ends title-case brand names wrong ("Ipad & Iphone", `AtlasLabeling.titleCase`).
- A label heading in a grounded answer stays 18 pt while body text scales, so at AX2 it is smaller than its bullets (as `###` headings already are); changing it needs the owner's word.

## Commands

```bash
rsync -a --delete --exclude .build --exclude .git --exclude .git.nosync --exclude BenchmarkRuns --exclude '.claude/worktrees' ./ /private/tmp/oi-src/
```

iPhone, from `/private/tmp/oi-src`: `xcodebuild build -project OpenIntelligence.xcodeproj -scheme OpenIntelligence
-configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/oi-build -jobs 2
MARKETING_VERSION=5.8`, then `xcrun devicectl device install app --device B1483F12-4FFD-5534-BA30-29FF48070549
/private/tmp/oi-build/Build/Products/Debug-iphoneos/OpenIntelligence.app`. Mac: the same build with
`-destination 'platform=macOS' -derivedDataPath /private/tmp/oi-mac-dd`; quit the app with `gtimeout 20 osascript -e
'tell application id "Gunndamental.OpenIntelligence" to quit'` (pkill fallback), replace
`/Applications/OpenIntelligence.app` with `ditto`, then `xattr -cr`. Logs: `python3 scripts/phone_evidence.py --since
<install time, local> --json`, and the same with `--mac`.

## Verification

- `xcodebuild test` (6 classes, 84 tests, iOS 27 simulator) after bcb9f12e -> passed. iOS and macOS Debug builds -> succeeded.
- Phone trace 09:40, 10:00 -> embedder loaded `cpuAndNeuralEngine` in the background; no 130 s GPU hang.
- Not yet seen on the phone: bcb9f12e (an answer left mid-way finishing with full evidence) and 0a2e346a (Siri Ask with a rate limit).

## Exact Next Action

Read his trace (`xcrun devicectl device copy from --device 00008140-001130DA1863C01C --domain-type appDataContainer
--domain-identifier Gunndamental.OpenIntelligence --source Documents/pipeline_trace.log --destination <file>`, then grep
after 10:27) for two tests: a Standard question in Library 11 left mid-answer (its `Context budget:` line must not read
`base=0`, and the answer must cite evidence), and "ask OpenIntelligence ..." from Siri (it must come forward or fail fast).
If both pass and he says go: `zsh -ic 'python3 /private/tmp/claude-501/xc_start_default.py'` (Xcode Cloud workflow
"Default", main), attach the build to both 5.8 versions (`PATCH appStoreVersions/<id>/relationships/build`; never
`scripts/asc_prepare_release.rb` for text, it writes the Mac notes to both platforms), read back text and screenshots,
then ask him once before submitting. After submission set `Docs/SHIPPED_VERSION.json` to in_review.
