---
name: lifecycle-check
description: Run the app-lifecycle scenarios (a new install, leaving during an import, leaving, locking or ending the app during an answer) in the iOS 27 Simulator and read each verdict from the app's journal. Use before a build goes to the owner's phone after any change to answers, the import queue, background tasks, Live Activities, launch or app state; before every submission; and whenever he reports that something broke "when I left the app", "after I locked it", "when I came back", "after a restart" or "after the update". Also use to read how answers on his phone fared when the app left or restarted.
---

# Lifecycle check

During 5.8, answers failing after leaving the app were raised on 2026-11-04 and were still being fixed on the day it
was submitted, with 14 crash or freeze reports on the way, and no test covered any of it (`Docs/ai/RETRO_5.8.md`, gap
4). This runs those situations before he has to find them.

## Run it

```bash
python3 scripts/lifecycle_scenarios.py
```

About 11 minutes on this Mac (a 25 s incremental build, then six scenarios). It waits while a game is open, refuses
while another `xcodebuild` runs, makes its own simulator ("OI lifecycle") and deletes it at the end. Run it in the
background and read the last lines:

```text
6 of 6 scenarios passed
PASS       A new install opens, and opens again                   Chat usable after 1.8 s, 1.7 s; search setup ran once; ...
PASS       Leave during an import, come back                      imported once, in 68 s, finishing after coming back; ...
PASS       An answer with the app in front (the baseline)         answered in 67 s; ...
PASS       Leave for the Home Screen during an answer, come back  answered in 68 s after coming back; ...
PASS       Lock the phone during an answer, unlock                answered in 67 s after coming back; ...
PASS       End the app during an answer, open it again            the answer finished after the app was opened again; ...
```

`python3 scripts/lifecycle_scenarios.py leave lock` runs only those; `--skip-build` reuses the last build; `--keep`
leaves the simulator up to look at; `--check <run folder>` judges a finished run again with no simulator. Run folders
are in `~/Library/Developer/OpenIntelligence-evidence/lifecycle/`.

## Reading a verdict

- **PASS**: the journal shows the condition happened (the app really left the front while the answer ran) and the
  work finished once, in the right process, with no crash report.
- **FAIL**: read `<scenario>.jsonl` in the run folder (that scenario's journal lines) and `tests.log`. A crash report's
  name is in the verdict; the report is in `~/Library/Logs/DiagnosticReports`.
- **NOT TESTED**: the run did not reach the condition (the answer finished before the app left, the library was
  empty, the model was not ready). It is not a pass. Run that scenario again.
- **longest main-thread stall**: printed from 1 s up, and a FAIL from 10 s, where iOS would have ended the app on a
  phone (the two 0x8BADF00D kills of 2026-11-19). A new simulator's first launch has measured 3.1, 3.9 and 8.7 s; his
  iPhone's median for the same moment is 0.3 s.

Find the cause before fixing (`diagnose-before-claiming`): the verdict says what broke, not why.

## What a pass does not cover

The Simulator is not the phone. It refuses the continued-processing task the phone gets (`bgtask.* submissionFailed`
in the journal), so the app runs its fallback there; it does not withhold the Neural Engine in the background; it has
no heat, no memory pressure and no Private Cloud Compute; and the scenarios ask in Standard only. A pass means the
app's own logic held. Device behaviour is still checked on his phone, with the `phone-watch` skill.

## How answers fared on his phone

No driving of the phone: this reads what his own use recorded.

```bash
python3 scripts/lifecycle_scenarios.py --real-use ~/Library/Developer/OpenIntelligence-evidence/watch/verification_events.jsonl --since 2026-11-19T00:00
```

It prints every answer by what happened to the app while it ran (stayed in front, left the front, restarted) and the
share that finished. Baseline, 2026-11-19 00:00 to 2026-11-20 09:44 on the builds that became 5.8: in front 100% (11
of 11), left 100% (11 of 11), restarted 71% (10 of 14; a restart is an install or the system ending the app, and
"finished" means the reopened app showed the written answer or asked again and answered). The journal there is the
copy `scripts/phone_watch.py` pulls; run that first for fresh lines.

## When a scenario is missing

Add a test to `OpenIntelligenceUITests/LifecycleScenarioUITests.swift` (the number in its name sets the order), a row
in `SCENARIOS` and a judge in `scripts/lifecycle_scenarios.py`, and a case in `scripts/test_lifecycle_scenarios.py`.
The tests only drive; the judge decides from journal events, so a new scenario needs an event that proves it. No
launch may carry `--screenshot` or `--uitest-stand-in-model`: those mark its journal lines as a robot's.
