# Current State

Updated: 2026-11-19 12:35
Branch/worktree: `main`, primary checkout
Last verified commit: 7abf10eb

## Objective

**Ship 5.8 to App Review today** (owner, 2026-11-19: "in review in the next like 3 hours"). He tests on his iPhone; the
agent reads his trace, fixes what it shows, and keeps the device-pass page https://claude.ai/artifact/RyYN25e7RGMAFthrKnBtNT
ticked (ArtifactData collection `pass`, doc `checks`, version 9, 14 ticked). He said "stop submitting archives until we
square this stuff away": no Xcode Cloud build until his tests pass. Submitting is his word alone; ask once.

## Status

Main is at 7abf10eb, pushed. The owner said "Start the build" at 12:30: Xcode Cloud build **504** (workflow "Default",
main) started PENDING; watch it with `zsh -ic 'python3 -u /private/tmp/claude-501/xc_watch504.py'`. iPhone (12:23) and
Mac (12:25) run Debug builds of 7abf10eb. Device-pass page: 15 ticked (version 10), mac-4-1 added from the Mac sidebar
showing iPhone threads.

App Store Connect is staged for 5.8 on both platforms (PREPARE_FOR_SUBMISSION; iOS version 36314c13-d814-479f-8f11-95c2d8ea6794,
Mac 387cf5c0-eee7-41a5-8e4f-bd562435b1e0). Release notes are at 3,991 / 3,996 characters of 4,000 and do not mention
the afternoon's fixes; their iPhone bullet still says an answer "resumes when you come back". Rewording is the owner's call.

## Completed on 2026-11-19 (pushed)

| Commit | What |
|---|---|
| 6122d185, 19f31f53 | Mac redesign: sidebar window, Settings window, Documents details as an `HSplitView` pane (two inspectors crashed AppKit), Chat row selectable (`.badge` before `.tag`) |
| d43158e5, ec78e1de | In-app What's New for 5.8; App Store copy for both platforms, review notes, metadata history, Mac screenshot boxes |
| a292e89d, 00c2f8cc, 62b5dad7, 7ed65fec | Core ML embedder uses CPU and Neural Engine whenever the app is in the background (`DeviceCapabilityService.isAppInBackground`, set by ContentView): first load, pending switch, retry, and a prediction that starts in the background on GPU units. Seen on the phone 09:40 and 10:00 |
| 0a2e346a | Siri and Shortcuts no longer wait forever after a rate limit: only a Chat answer waits for the app to return; an action asks once to come forward, then retries and reports failure |
| e99bd165 | Search model and reranker warm up one second after each return to the front, once per launch |
| bcb9f12e | The on-device window keeps its last positive reading when `contextSize` reads 0 in the background (`FoundationModelTokenBudget.lastOnDeviceContext`); an answer resumed there had been packed to 800 characters and wrongly said the guide had no chicken temperature (165°F in front). 84 tests passed |
| 23eed636 | Fact Check ignores words a claim repeats from the question ("Chicken should reach 165°F" no longer Partial) |
| 6e6ba674 | The embedder's background form compiles during the warm-up, in front |
| 4bf4fb5e | Every answer holds a continued-processing task; no planner model call in the background; a rate-limited Chat answer retries in the background for ~52 s before waiting |
| ea8c5c03 | Mac: answer details are an HSplitView pane (crash at 10:46:58 in Chat); one Lock Screen card (no Live Activity while iOS shows the task's card) |
| 64f80816, 7d0be463 | Mac: colored mode pill, library name under "Chat", a library click keeps the area in front |
| 895597fe | `LiveFoundationModelCapabilityProvider` uses the kept window, so the plan no longer re-packs background answers into 800 characters (bags answered "$200") |
| 6ff02031 | `joiningContinuation` for continuations and resumes ("itemThe document"); Mac sidebar says Evidence Threads |
| 7abf10eb | `PendingAnswerStore.keepAnswer`: the written answer is saved when the stream ends; a relaunch shows it instead of asking again |

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

When build 504 completes and shows in App Store Connect, attach it to both 5.8 versions (`PATCH
appStoreVersions/<id>/relationships/build`; never `scripts/asc_prepare_release.rb` for text), read back the release notes,
screenshots and review notes, then ask the owner once whether to submit. After submission set `Docs/SHIPPED_VERSION.json`
to in_review. Open after 5.8: the continuation trigger on a final list item without a period (an extra model call), Siri
scope and open-document, the DHA named-document row, the planner model call in Standard.
