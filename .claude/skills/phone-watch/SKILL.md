---
name: phone-watch
description: Watch the development build on the owner's iPhone so the agent reports what happened without being told. Use as soon as a development build is installed on his phone and he is going to test it, when he says "check trace", "just ran it", "did you see that", "it crashed", "it froze" or "try again", and before asking him what happened on the phone. Starts a background poll of the build's journal and crash reports that wakes the agent with one line per question, answer, failure, restart, long stall or crash.
---

# Phone watch

During 5.8 the owner typed "check trace" or "just ran" about 40 times on 10 days, and the agent pulled the trace 522
times by hand (`Docs/ai/RETRO_5.8.md`, gap 2). The watch removes the asking: he uses the app, and each thing the app
does arrives here as a line.

## Start it

Right after a development build is installed and launched on his phone, arm the Monitor tool (load it with ToolSearch
`select:Monitor` if it is deferred):

```text
command:     cd <repo> && python3 scripts/phone_watch.py
description: OpenIntelligence on the iPhone: questions, answers, failures, restarts, crashes
timeout_ms:  1800000
```

A monitor lives 30 minutes at most. When it expires and he is still testing, arm it again with the same command: the
cursor is on disk (`~/Library/Developer/OpenIntelligence-evidence/watch/state.json`), so nothing between two watches
is lost or reported twice. Run one watch at a time; two share the cursor and each sees half.

To report what happened before the watch started, add `--since 2026-11-20T09:00` (this Mac's local time) to the first
run. With no cursor and no `--since` it starts from now.

## What a line means, and what to do with it

| Line | Do |
|---|---|
| `question asked: mode=..., passages=...` | Nothing yet. An `answer done` should follow; if none comes in about 5 minutes for Deep Think (2 for Standard), pull the evidence and look. |
| `answer done: mode, badge, scene, inFront, sources, took N s` | Tell him in one line what the build did (mode, time, sources, in front or in the background). `error=...` or `[failed]`: pull the evidence at once. |
| `answer judged: verdict=partial` | The answer check found it incomplete. Read that answer's lines in the trace before saying anything about quality. |
| `MODEL FAILURE: kind=rateLimited ...` | Apple's model refused or limited the call. Not a defect by itself; say so if the answer was slow. |
| `background answer: phase=expired` or `failed` | iOS ended the background time. Check that the answer resumed (`answer done` after it). |
| `app launched: build 5.8 (150), pid N (was pid M)` | The app restarted. If he did not relaunch it, it was killed: look for a `CRASH report` line and the crash log. |
| `N main-thread stalls of 2 s or more` | A freeze he probably felt. The trace has the phase. |
| `FAILED <event>` | An event recorded as failed. Pull the evidence and read that event. |
| `CRASH report on the phone: <name>.ips` | Copy it off (`xcrun devicectl device copy from --domain-type systemCrashLogs --source <name>`), read the crashed thread, and tell him the cause before he asks. |
| `phone not answering ...` | Locked a long time, off Wi-Fi, or away. Keep the watch; it says when the phone answers again. |

For anything past the one line, pull everything and read it: `python3 scripts/phone_evidence.py --since <time>` (the
`device-pass` skill covers closing roadmap rows from it).

Reply to him in one or two lines per thing that happened, unprompted. Do not wait for "check trace".

## Limits

- **Debug builds only.** The App Store and TestFlight builds write no journal, so the watch is silent on them.
- **It cannot say which commit is on the phone.** Every line carries the version and build number, and every
  development build has been build 150. `Docs/ai/plans/build-stamp.md` is the plan that fixes this.
- **A line holds no document name, library name or question**: only numbers, true/false and single enumerated words
  from a fixed list of fields, with anything else printed as `<text>`. The pulled journal does hold them; it stays in
  `~/Library/Developer/OpenIntelligence-evidence/watch` and is never committed or pasted whole.
- Whether a pull works while the phone is locked is not measured.
- Not yet proven end to end with him testing: on 2026-11-20 it was run against his phone (one pass, 6.6 s) and against
  the journal of 2026-11-19, with nothing live to report.

## Check it works

```bash
python3 scripts/test_phone_watch.py
```

```bash
python3 scripts/phone_watch.py --once --since 2026-11-19T12:00
```
