# Plan: know which build is on the phone

Written 2026-11-20. Gap 3 of `Docs/ai/RETRO_5.8.md`: about 27 owner messages on 13 days asked "is it on my phone" or
"was this the new build". **Steps 1 and 2 were built on 2026-11-20** (`scripts/install_to_phone.py`, results at the
end); step 3 is not. No file under `OpenIntelligence/`, no `Info.plist` and no `project.pbxproj` was edited.

## What is true today

| Fact | Evidence |
|---|---|
| Every development build carries build number 150. | 14 `CURRENT_PROJECT_VERSION = 150;` lines in `project.pbxproj`; the journal's last line on the phone reads `"v": "5.8 (150)"` (pulled 2026-11-20). `[measured]` |
| The app already shows and logs "version (build)". | Settings (`SettingsView.swift:115`, `Bundle.appVersion`), About and the feedback mail (`AboutView.swift:21`), the report sheet (`ReportMessageSheet.swift:102`), and every journal line (`VerificationJournal.swift:75-80`, field `v`). `[code_verified]` |
| A build setting given on the `xcodebuild` command line edits no file. | The device build already passes `MARKETING_VERSION=<X.Y>` this way (`Docs/ai/RUNBOOK.md`, "Building to the owner's iPhone"). `[measured]` for that setting. Not verified for `CURRENT_PROJECT_VERSION` until step 1's check. |
| A build number may be one to three integers separated by periods. | Apple, `CFBundleVersion`, read 2026-11-20: "one to three period-separated integers". |
| Two caches key on the build number, and both also key on the executable's install time. | `ModelCompileCache.currentVersion` (`ModelCompileCache.swift:25-32`) and `RerankerFastForm.stamp` (`RerankerSetupStatus.swift:186-192`). So a new build number per install changes nothing for them: each install already changes the key. `[code_verified]` |
| The search cache keys on "version (build)" alone. | `RAGService.appVersionForQueryCache` (`RAGService+ChatHistory.swift:398-403`). With every development build at 150, a search cached by one development build has the same key in the next. Whether a cached search has outlived an install in practice is not measured. `[code_verified]` for the key; the effect is not measured. |
| `main` is one line with no branches. | `git rev-list --count HEAD` was 1875 on 2026-11-20, so a commit count names one commit. `[measured]` |

## The finding

The stamp needs no app code. The app already prints and logs its build number everywhere it matters; the number has
just never changed. Give each device build its own number on the command line and the question answers itself in
Settings, in the feedback mail, and on every line the phone watch prints.

## Step 1: a build number that names the commit and the time (no app code)

Pass one more setting in the device build of the runbook:

```text
CURRENT_PROJECT_VERSION=<commits>.<DDHHMM>
```

`<commits>` is `git rev-list --count HEAD` and `<DDHHMM>` is the day of the month and the local time of the build,
so a build of commit 1875 at 09:41 on the 20th reads `5.8 (1875.200941)` in Settings and in the journal. The commit is
`git rev-list --reverse HEAD | sed -n '1875p'`. Two builds of the same commit (the usual case while a fix is still
uncommitted) differ by their time.

Check before relying on it, with the first build that uses it:

1. `xcodebuild -showBuildSettings ... CURRENT_PROJECT_VERSION=1875.200941 | grep CURRENT_PROJECT_VERSION` shows the
   value on every target (the widget and intents extensions must match the app, or the install warns).
2. The build installs over the current development build (a lower or higher number than 150 must both install).
3. Settings shows the new number, and `python3 scripts/phone_watch.py --once` prints it on the `app launched` line.
4. The first launch after the install does not show search setup again when the previous install did not
   (the two model caches above already change key on every install; this confirms it).

Xcode Cloud is untouched: store builds keep their run number (509 for 5.8), which `scripts/asc_submit_gate.py`
already ties to a commit.

## Step 2: an install script that keeps a record (no app code)

`scripts/install_to_phone.py`, wrapping the runbook's three commands (mirror out of iCloud, build with the settings
above, install and launch), which then:

- appends one line to `~/Library/Developer/OpenIntelligence-evidence/installs.jsonl`: time, build number, commit,
  whether the tree had uncommitted changes, and a hash of `git diff` when it had;
- prints one line for the owner: `installed 5.8 (1875.200941) = 8e148387 + uncommitted changes, launched`;
- treats `Locked` after a clean install as installed, not launched (the runbook's rule);
- refuses to start while another `xcodebuild` runs (one build at a time on this Mac).

`scripts/phone_watch.py` then reads that file and adds the commit to its `app launched` line, and says so when the
build on the phone is older than the newest install record ("the phone is still on 1874.191503").

Rule that goes with it, into `CLAUDE.md` next to the device-build memory: after a green build of a Swift change, when
the phone is reachable, install it and send the one line. The owner should never have to ask.

## Step 3: the commit itself in the app (app code, after 5.8 is live)

Only worth doing if step 1 leaves a gap, for example a tester's screenshot of About that should name a commit. A
resource file `BuildStamp.json` (commit, dirty flag, build time) written into the mirror before a device build and by
`ci_scripts/ci_post_clone.sh` on Xcode Cloud (from `CI_COMMIT`), read once at launch with a fallback of "unknown", and
shown in About. The file is generated and gitignored, so no hard-boundary file changes; it does add a file to a
synchronized folder, so check which targets pick it up (`OpenIntelligence/Resources` has an exception list for the
engine target in `project.pbxproj`). Needs the owner's `PROCEED: IMPLEMENT` and a roadmap row in Future Backlog.

## What done looks like

- He installs nothing by hand and asks nothing: after each fix a line arrives naming the build, and Settings on the
  phone shows the same number.
- Any journal line, crash log or screenshot can be traced to one commit and one build time.
- Closing condition for the retrospective's gap 3: one working day of his testing with no "is it on my phone"
  message.

## Order and size

Step 1 is a runbook change and four checks on the next device build. Step 2 is one script and a small change to the
phone watch, about half a day with its test. Step 3 waits for 5.8 to be live and for his word.

## Result, 2026-11-20

| Check | Result |
|---|---|
| The number reaches every target | The built app, `OpenIntelligenceShare.appex` and `OpenIntelligenceLiveActivities.appex` all read 5.8 / 1876.200935 (their `Info.plist`s; the script refuses to install when they differ). `[build_verified]` |
| It installs over the current development build | Installed over build 150 at 09:38; `devicectl device info apps` on the iPhone read `5.8 | 1876.200935`. A lower number over a higher one is not tried (a later build of the same day always has a higher one; the first build of a new month has a lower one). `[measured]` |
| Settings and the journal show it | The journal does: when the owner opened the app the phone watch printed `09:38:52 app launched: build 5.8 (1876.200935) = 19c36f86, pid 28040 (was pid 23309)`. `[measured]` Settings is not yet looked at. |
| Search setup is not shown again because of the number | Not yet seen, same reason. |
| Cost | First build into an empty folder and install: 163 s. A rebuild with only a new number: 13 s. `[measured]` |

Differences from the plan above: the script is Python (`scripts/install_to_phone.py`) so its parts have tests; it
installs when the app is not running or has been silent in its journal for ten minutes (the runbook's rule was "not
running"; the app was suspended and 603 minutes silent on this run); and it does not launch unless `--launch` is
given. The `CLAUDE.md` rule is not added; the standing memory "build every fix to his phone" now names the script.

