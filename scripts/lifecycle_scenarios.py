#!/usr/bin/env python3
"""Lifecycle scenarios: what happens to an answer or an import when the person leaves, locks, or ends the app.

  python3 scripts/lifecycle_scenarios.py                  build, then run every scenario and print a verdict each
  python3 scripts/lifecycle_scenarios.py leave lock       only these scenarios
  python3 scripts/lifecycle_scenarios.py --skip-build     reuse the last build (nothing in the app changed)
  python3 scripts/lifecycle_scenarios.py --check DIR      judge a run folder again, with no simulator
  python3 scripts/lifecycle_scenarios.py --keep           leave the simulator up afterwards, to look at it
  python3 scripts/lifecycle_scenarios.py --real-use JOURNAL [--since 2026-11-19T12:00]
                                                          no simulator: every answer in a journal of real use (the
                                                          phone's, as scripts/phone_watch.py pulls it), by whether the
                                                          app stayed in front, left or restarted, and how it ended

Why (Docs/ai/RETRO_5.8.md, gap 4): answers failing after leaving the app were raised on 2026-11-04 and were still
being fixed on the day 5.8 was submitted, with 14 crash or freeze reports on the way, and no test covered any of it.

How: `OpenIntelligenceUITests/LifecycleScenarioUITests.swift` drives the app (ask, press Home, lock, end the app,
open it again). This script copies the working tree out of iCloud, patches the copy so Apple's model answers in the
Simulator (`scripts/sim_model_copy.py`), builds it once, makes a simulator of its own ("OI lifecycle", nothing of the
owner's is on it), runs the scenarios in order in one test run, and reads each verdict from the journal the development build writes
(`Documents/verification_events.jsonl`): the screen is never the evidence. Results go to
~/Library/Developer/OpenIntelligence-evidence/lifecycle/<time>/ (outside the repository).

Verdicts: PASS, FAIL, or NOT TESTED when the run did not reach the condition (the answer finished before the app
left, say). NOT TESTED is not a pass.

What the Simulator cannot show, so a pass here is not a pass on a phone: iOS's real background limits (the Simulator
refuses the continued-processing task the phone gets, `bgtask.* submissionFailed`, so the app runs its fallback
there), the Neural Engine being withheld in the background, heat, memory pressure, and Private Cloud Compute. Those stay with the
phone (`scripts/phone_watch.py`, the `device-pass` skill).

Safety, as in scripts/install_to_phone.py: waits while a game is open, one xcodebuild at a time, a memory and disk
guard on the build, and its own simulator, which it shuts down and deletes at the end.
"""
import argparse, datetime, glob, json, os, re, shutil, subprocess, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from install_to_phone import ROOT, free_gib, guarded, kill_tree, marketing_version, run
from phone_evidence import BUNDLE

SIM_NAME = "OI lifecycle"
DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
EVIDENCE = os.path.expanduser("~/Library/Developer/OpenIntelligence-evidence/lifecycle")
TEST_CLASS = "OpenIntelligenceUITests/LifecycleScenarioUITests"
# iOS ends an app whose main thread does not answer a scene update for about 10 s (0x8BADF00D, the two 5.8 kills of
# 2026-11-19). The Simulator does not enforce it, so a stall this long here is a kill on a phone. Shorter stalls are
# printed, not failed: a new simulator's first launch measured 3.1 s and 8.7 s on 2026-11-20, where the owner's iPhone
# has a median of 0.3 s for the same moment (99 first launches after an install).
STALL_FAIL_MS = 10000
GAMES = "World of Warcraft.app/Contents/MacOS|League of Legends.app/Contents/MacOS"
# name, the test that drives it, what it is. The order matters (the numbers in the test names set it): the first needs a
# new install, the second imports the note the answers are asked about, the third warms the model.
SCENARIOS = [
    ("first-launch", "test1FirstLaunchAfterInstall", "A new install opens, and opens again"),
    ("import", "test2LeaveDuringAnImport", "Leave during an import, come back"),
    ("in-front", "test3AnswerInFront", "An answer with the app in front (the baseline)"),
    ("leave", "test4LeaveDuringAnAnswer", "Leave for the Home Screen during an answer, come back"),
    ("lock", "test5LockDuringAnAnswer", "Lock the phone during an answer, unlock"),
    ("end-app", "test6EndTheAppDuringAnAnswer", "End the app during an answer, open it again"),
]


# ---------------------------------------------------------------- judging a scenario: pure functions of its events

def named(events, name, **fields):
    out = []
    for e in events:
        if e.get("e") != name:
            continue
        f = e.get("f") or {}
        if all(str(f.get(k, e.get(k))) == str(v) for k, v in fields.items()):
            out.append(e)
    return out


def pids(events):
    seen = []
    for e in events:
        if e.get("pid") is not None and e["pid"] not in seen:
            seen.append(e["pid"])
    return seen


def went_away_between(events, start, end):
    """True when the app left the front (phase background) after `start` and before `end` (None: any time after)."""
    return any(e["t"] > start["t"] and (end is None or e["t"] < end["t"]) for e in named(events, "app.phase", to="background"))


def judge_answer(events, must_leave, same_process=True):
    """An answer that started must end ok, once, in the same process; `must_leave`: the app left while it ran."""
    starts, done_ok = named(events, "answer.start"), named(events, "answer.done", o="ok")
    done_bad = [e for e in named(events, "answer.done") if e.get("o") != "ok"]
    if not starts:
        return "NOT TESTED", "no answer started (the question was never sent, or the model was not ready)"
    if not done_ok:
        why = f"; {len(done_bad)} ended {done_bad[-1].get('o')}" if done_bad else ""
        return "FAIL", f"the answer never finished{why}"
    first, last = starts[0], done_ok[-1]
    if str((first.get("f") or {}).get("passages", "")) == "0":
        return "NOT TESTED", "the library was empty, so the answer ran no search"
    if must_leave and not went_away_between(events, first, last):
        return "NOT TESTED", "the answer finished before the app left the front"
    if not must_leave and went_away_between(events, first, last):
        return "NOT TESTED", "the app left the front during the baseline answer"
    if same_process and len(pids([e for e in events if first["t"] <= e["t"] <= last["t"]])) > 1:
        return "FAIL", "the app was restarted while the answer ran"
    seconds = (parse(last["t"]) - parse(first["t"])).total_seconds()
    note = f"answered in {seconds:.0f} s"
    if must_leave:
        note += " while away" if (last.get("f") or {}).get("scene") == "background" else " after coming back"
    if len(starts) > 1:
        note += f", asked {len(starts)} times"
    if done_bad:
        note += f", {len(done_bad)} earlier attempt{'s' if len(done_bad) != 1 else ''} ended {done_bad[-1].get('o')}"
    return "PASS", note


def judge_first_launch(events):
    launches = named(events, "launch.chatUsable")
    if len(launches) < 2:
        return "FAIL", f"Chat became usable {len(launches)} time(s) in two launches"
    if len(pids(launches)) < 2:
        return "NOT TESTED", "the app was not ended between the two launches"
    second = [e for e in events if e.get("pid") == launches[1].get("pid")]
    again = [e["e"] for e in named(second, "embedding.load", newInstall="true") + named(second, "reranker.load", newInstall="true")]
    if again:
        return "FAIL", "the second launch set search up again as if newly installed (" + ", ".join(again) + ")"
    times = ", ".join(f"{float((e.get('f') or {}).get('ms', e.get('ms', 0)) or 0) / 1000:.1f} s" for e in launches[:2])
    return "PASS", f"Chat usable after {times}; search setup ran once"


def judge_end_app(events):
    """The app is ended mid-answer and opened again: the answer must finish in the new process, or be kept."""
    starts = named(events, "answer.start")
    if not starts:
        return "NOT TESTED", "no answer started"
    seen = pids(events)
    if len(seen) < 2:
        return "NOT TESTED", "the app was never ended and opened again"
    first_pid = starts[0].get("pid")
    if named(events, "answer.done", o="ok") and all(e.get("pid") == first_pid for e in named(events, "answer.done", o="ok")):
        return "NOT TESTED", "the answer finished before the app was ended"
    after = [e for e in events if e.get("pid") != first_pid]
    if named(after, "answer.restoredWritten"):
        return "PASS", "the reopened app showed the answer it had already written"
    if named(after, "answer.done", o="ok"):
        return "PASS", "the answer finished after the app was opened again"
    if named(after, "answer.start"):
        return "FAIL", "the question was asked again after reopening and did not finish"
    return "FAIL", "after reopening, the question was neither answered nor asked again"


def judge_import(events):
    stages = named(events, "import.stage")
    if not stages:
        return "NOT TESTED", "no import started"
    if named(events, "import.stage", to="failed"):
        return "FAIL", "the import failed"
    complete = named(events, "import.stage", to="complete")
    if not complete:
        return "FAIL", f"the import never finished (last stage {(stages[-1].get('f') or {}).get('to')})"
    if not went_away_between(events, stages[0], complete[0]):
        return "NOT TESTED", "the import finished before the app left the front"
    if len(complete) > 1:
        return "FAIL", f"the file was imported {len(complete)} times"
    seconds = (parse(complete[0]["t"]) - parse(stages[0]["t"])).total_seconds()
    back = [e for e in named(events, "app.phase", to="active") if e["t"] > stages[0]["t"]]
    where = "after coming back" if back and back[0]["t"] < complete[0]["t"] else "while away"
    return "PASS", f"imported once, in {seconds:.0f} s, finishing {where}"


JUDGES = {
    "first-launch": judge_first_launch,
    "in-front": lambda events: judge_answer(events, must_leave=False),
    "leave": lambda events: judge_answer(events, must_leave=True),
    "lock": lambda events: judge_answer(events, must_leave=True),
    "end-app": judge_end_app,
    "import": judge_import,
}


def judge(name, events, crashes):
    """(verdict, why). A crash report during the scenario fails it whatever else happened."""
    if crashes:
        return "FAIL", "crash report: " + ", ".join(sorted(crashes))
    verdict, why = JUDGES[name](events)
    stalls = [float((e.get("f") or {}).get("ms", 0) or 0) for e in named(events, "mainThread.stall")]
    if stalls and max(stalls) >= 1000:
        why += f"; longest main-thread stall {max(stalls) / 1000:.1f} s"
    if stalls and max(stalls) >= STALL_FAIL_MS:
        verdict = "FAIL" if verdict == "PASS" else verdict
    return verdict, why


def real_use(events):
    """Every answer in a journal of real use, by what happened to the app while it ran, and how it ended.

    For the phone: nobody drives it, so this reads what the owner's own use recorded. An answer is `stayed` when the
    app was in front throughout, `left` when it went to the background before the answer ended, and `restarted` when
    the app's process changed before it ended. It ended `ok`, with another outcome, or `never` (no end was recorded
    before the next question or the end of the journal). A restarted answer counts as `ok` when the reopened app
    showed the answer it had written (`answer.restoredWritten`), or asked the question again within five minutes and
    that answer ended ok; that second answer is not counted twice.
    """
    starts = named(events, "answer.start")
    rows = []
    for i, start in enumerate(starts):
        until = starts[i + 1]["t"] if i + 1 < len(starts) else "9"
        window = [e for e in events if start["t"] <= e["t"] < until]
        done = next((e for e in window if e.get("e") == "answer.done"), None)
        span = [e for e in window if done is None or e["t"] <= done["t"]]
        if len(pids(span)) > 1:
            kind = "restarted"
        elif any(e.get("e") == "app.phase" and (e.get("f") or {}).get("to") == "background" for e in span):
            kind = "left"
        else:
            kind = "stayed"
        end = done.get("o") if done else "never"
        if done is None and kind == "restarted" and named(window, "answer.restoredWritten"):
            end = "ok"  # the reopened app showed the answer it had already written, with no second question
        rows.append({"t": start["t"], "mode": (start.get("f") or {}).get("mode"), "kind": kind, "pid": start.get("pid"),
                     "end": end})
    # An answer cut off by a restart never ends in its own process. What matters is whether the question was asked
    # again by the reopened app within five minutes, and how that ended.
    for i, row in enumerate(rows):
        if row["kind"] == "restarted" and row["end"] == "never" and i + 1 < len(rows):
            following = rows[i + 1]
            if following["pid"] != row["pid"] and (parse(following["t"]) - parse(row["t"])).total_seconds() <= 300:
                row["end"] = "ok" if following["end"] == "ok" else f"asked again, {following['end']}"
                following["resume"] = True
    return [r for r in rows if not r.get("resume")]


def render_real_use(rows):
    lines = [f"{len(rows)} answers"]
    for kind, label in (("stayed", "app in front throughout"), ("left", "app left the front during the answer"),
                        ("restarted", "app restarted during the answer (finished = shown or answered again on reopening)")):
        group = [r for r in rows if r["kind"] == kind]
        if not group:
            continue
        ok = sum(1 for r in group if r["end"] == "ok")
        other = {}
        for r in group:
            if r["end"] != "ok":
                other[r["end"]] = other.get(r["end"], 0) + 1
        rest = ", ".join(f"{n} {end}" for end, n in sorted(other.items()))
        lines.append(f"  {label}: {100 * ok / len(group):.0f}% finished ({ok} of {len(group)})" + (f"; {rest}" if rest else ""))
    return "\n".join(lines)


def parse(t):
    return datetime.datetime.fromisoformat(t.replace("Z", "+00:00"))


def utc_now():
    now = datetime.datetime.now(datetime.timezone.utc)
    return now.strftime("%Y-%m-%dT%H:%M:%S.") + f"{now.microsecond // 1000:03d}Z"


def newest_journal(apps_folder):
    """The app's journal on the simulator. An install can move the app's data folder, so it is looked up by date."""
    found = glob.glob(os.path.join(apps_folder, "*", "Documents", "verification_events.jsonl"))
    return max(found, key=os.path.getmtime) if found else None


def windows(log_text):
    """Each test's BEGIN and END time from the lines the tests print: {test method: (begin, end)}."""
    out = {}
    for when, kind, test in re.findall(r"\[Lifecycle\] (\S+) (BEGIN|END) -\[\S+ (\w+)\]", log_text):
        begin, end = out.get(test, (None, None))
        out[test] = (when, end) if kind == "BEGIN" else (begin, when)
    return out


def read_journal(path, since=None, until=None):
    events = []
    if path and os.path.exists(path):
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    e = json.loads(line)
                except ValueError:
                    continue
                if isinstance(e, dict) and e.get("t") and (not since or e["t"] > since) and (not until or e["t"] <= until):
                    events.append(e)
    return events


def render(results):
    width = max(len(r["what"]) for r in results)
    lines = [f"{r['verdict']:<10} {r['what']:<{width}}  {r['why']}" for r in results]
    bad = [r for r in results if r["verdict"] != "PASS"]
    head = f"{len(results) - len(bad)} of {len(results)} scenarios passed" + ("" if not bad else f"; {len(bad)} did not")
    return head + "\n" + "\n".join(lines)


def check_folder(folder):
    results = []
    for name, _, what in SCENARIOS:
        path = os.path.join(folder, f"{name}.jsonl")
        if not os.path.exists(path):
            continue
        crashes_path = os.path.join(folder, f"{name}.crashes.txt")
        crashes = open(crashes_path).read().split() if os.path.exists(crashes_path) else []
        verdict, why = judge(name, read_journal(path), crashes)
        results.append({"name": name, "what": what, "verdict": verdict, "why": why})
    return results


# ---------------------------------------------------------------- running

def simctl(*args, timeout=300):
    return run("xcrun", "simctl", *args, timeout=timeout)


def stage_and_patch(scratch):
    """The working tree, copied out of iCloud and patched so the app's own model answers in the Simulator."""
    stage, source = os.path.join(scratch, "oi-life-stage"), os.path.join(scratch, "oi-life-src")
    os.makedirs(source, exist_ok=True)
    r = run("rsync", "-a", "--delete", "--exclude", ".build", "--exclude", ".git", "--exclude", ".git.nosync",
            "--exclude", "BenchmarkRuns", "--exclude", ".claude/worktrees", "--exclude", ".env*", ROOT + "/", stage + "/", timeout=1800)
    if r.returncode != 0:
        sys.exit("rsync to the stage failed: " + r.stderr[-300:])
    r = run(sys.executable, os.path.join(ROOT, "scripts", "sim_model_copy.py"), stage)
    if r.returncode != 0:
        sys.exit("sim_model_copy.py failed (a switch moved): " + (r.stdout + r.stderr)[-400:])
    # By content, so files that did not change keep their dates and the build stays incremental.
    r = run("rsync", "-a", "--checksum", "--delete", stage + "/", source + "/", timeout=1800)
    if r.returncode != 0:
        sys.exit("rsync to the build copy failed: " + r.stderr[-300:])
    shutil.rmtree(stage, ignore_errors=True)  # 305 MB that the build copy now holds
    return source


def new_simulator():
    listing = simctl("list", "devices").stdout
    for line in listing.splitlines():
        if f"{SIM_NAME} (" in line:
            m = re.search(r"[0-9A-F-]{36}", line)
            if m:
                simctl("delete", m.group(0))
    r = simctl("create", SIM_NAME, DEVICE_TYPE, RUNTIME)
    if r.returncode != 0:
        sys.exit("could not create the simulator: " + r.stderr.strip()[-300:])
    return r.stdout.strip()


def run_tests(source, derived, udid, tests, apps_folder, log_path, limit=3000):
    """Every wanted scenario in one xcodebuild run, so the app is installed once. xcodebuild can hang after the
    tests have run, so it is ended 45 s after the log reports the result."""
    env = dict(os.environ, TEST_RUNNER_OI_SIM_APPS=apps_folder)
    cmd = ["xcodebuild", "test-without-building", "-project", os.path.join(source, "OpenIntelligence.xcodeproj"),
           "-scheme", "OpenIntelligenceUITests", "-destination", f"platform=iOS Simulator,id={udid}",
           "-derivedDataPath", derived] + [f"-only-testing:{TEST_CLASS}/{t}" for t in tests]
    shown = 0
    with open(log_path, "w") as log:
        process = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT, env=env)
        started, finished_at = time.time(), None
        while process.poll() is None:
            time.sleep(5)
            text = open(log_path, errors="replace").read()
            said = [l.strip() for l in text.splitlines() if "[Lifecycle]" in l]
            for line in said[shown:]:
                print("  " + line[line.index("[Lifecycle]"):], flush=True)
            shown = len(said)
            if finished_at is None and re.search(r"Executed \d+ tests?, with", text):
                finished_at = time.time()
            if (finished_at and time.time() - finished_at > 45) or time.time() - started > limit:
                kill_tree(process.pid)
                break
        try:
            process.wait(timeout=60)
        except subprocess.TimeoutExpired:
            pass
    return open(log_path, errors="replace").read()


def crash_reports(since_epoch):
    folder = os.path.expanduser("~/Library/Logs/DiagnosticReports")
    return [os.path.basename(p) for p in glob.glob(os.path.join(folder, "OpenIntelligence*"))
            if os.path.getmtime(p) >= since_epoch and "UITests" not in os.path.basename(p)]


def main():
    p = argparse.ArgumentParser(description="Run the app-lifecycle scenarios in the iOS 27 Simulator and judge each from the journal.")
    p.add_argument("scenarios", nargs="*", help="names to run (default all): " + ", ".join(s[0] for s in SCENARIOS))
    p.add_argument("--check", metavar="DIR")
    p.add_argument("--real-use", metavar="JOURNAL", help="report every answer in a journal of real use (the phone's), "
                   "by whether the app stayed, left or restarted; with --since to start at a local time")
    p.add_argument("--since")
    p.add_argument("--skip-build", action="store_true")
    p.add_argument("--keep", action="store_true")
    p.add_argument("--ignore-games", action="store_true")
    p.add_argument("--scratch", default="/private/tmp")
    a = p.parse_args()

    if a.real_use:
        from phone_evidence import normalize_since
        events = [e for e in read_journal(a.real_use, since=normalize_since(a.since) if a.since else None) if e.get("host") != "uitest"]
        print(render_real_use(real_use(events)))
        return
    if a.check:
        results = check_folder(a.check)
        print(render(results) if results else "no scenario journals in " + a.check)
        sys.exit(0 if results and all(r["verdict"] == "PASS" for r in results) else 1)

    wanted = [s for s in SCENARIOS if not a.scenarios or s[0] in a.scenarios]
    unknown = set(a.scenarios) - {s[0] for s in SCENARIOS}
    if unknown or not wanted:
        sys.exit("unknown scenario: " + ", ".join(sorted(unknown)))
    while not a.ignore_games and run("pgrep", "-f", GAMES).stdout.strip():
        print("A game is running; waiting for it to close (checking every 5 minutes).", flush=True)
        time.sleep(300)
    if run("pgrep", "-x", "xcodebuild").stdout.strip():
        sys.exit("another xcodebuild is running; one at a time on this Mac")
    if free_gib() < 12:
        sys.exit(f"{free_gib():.1f} GiB free on the internal disk, under 12: not running (~/.agents/STORAGE.md)")

    stamp = datetime.datetime.now().strftime("%Y-%m-%d_%H%M%S")
    out = os.path.join(EVIDENCE, stamp)
    os.makedirs(out, exist_ok=True)
    derived = os.path.join(a.scratch, "oi-life-dd")
    source = os.path.join(a.scratch, "oi-life-src")
    version = marketing_version(open(os.path.join(ROOT, "CHANGELOG.md"), encoding="utf-8").read())
    udid = new_simulator()
    print(f"simulator {udid}, results in {out}", flush=True)
    try:
        if not a.skip_build:
            source = stage_and_patch(a.scratch)
            began = time.time()
            code, stopped = guarded(
                ["xcodebuild", "build-for-testing", "-project", "OpenIntelligence.xcodeproj", "-scheme", "OpenIntelligenceUITests",
                 "-destination", f"platform=iOS Simulator,id={udid}", "-derivedDataPath", derived, "-jobs", "2",
                 f"MARKETING_VERSION={version}"], source, os.path.join(out, "build.log"))
            if stopped or code != 0:
                tail = [l for l in open(os.path.join(out, "build.log"), errors="replace").read().splitlines()
                        if "error:" in l or "BUILD" in l][-10:]
                sys.exit(f"the build {'was stopped: ' + stopped if stopped else 'failed'}\n" + "\n".join(tail))
            print(f"built in {time.time() - began:.0f} s", flush=True)
        app = os.path.join(derived, "Build", "Products", "Debug-iphonesimulator", "OpenIntelligence.app")
        if not os.path.exists(app):
            sys.exit(f"no built app at {app}; run without --skip-build")
        simctl("boot", udid)
        simctl("bootstatus", udid, "-b", timeout=600)
        apps_folder = os.path.expanduser(f"~/Library/Developer/CoreSimulator/Devices/{udid}/data/Containers/Data/Application")
        os.makedirs(apps_folder, exist_ok=True)
        since_epoch = time.time()
        print("running: " + ", ".join(s[0] for s in wanted), flush=True)
        log_text = run_tests(source, derived, udid, [s[1] for s in wanted], apps_folder, os.path.join(out, "tests.log"))
        journal = newest_journal(apps_folder)
        if journal:
            shutil.copy2(journal, os.path.join(out, "journal.jsonl"))
        spans = windows(log_text)
        crashes = crash_reports(since_epoch)
        results = []
        for name, test, what in wanted:
            begin, end = spans.get(test, (None, None))
            if not begin:
                results.append({"name": name, "what": what, "verdict": "NOT TESTED", "why": "the test did not start"})
                continue
            events = read_journal(journal, since=begin, until=end or utc_now())
            mine = [c for c in crashes if os.path.getmtime(os.path.join(os.path.expanduser("~/Library/Logs/DiagnosticReports"), c))
                    >= parse(begin).timestamp() and (not end or os.path.getmtime(os.path.join(
                        os.path.expanduser("~/Library/Logs/DiagnosticReports"), c)) <= parse(end).timestamp() + 30)]
            with open(os.path.join(out, f"{name}.jsonl"), "w") as f:
                f.write("\n".join(json.dumps(e) for e in events))
            with open(os.path.join(out, f"{name}.crashes.txt"), "w") as f:
                f.write("\n".join(mine))
            verdict, why = judge(name, events, mine)
            if not end:
                verdict, why = ("FAIL", "the test never ended; " + why) if verdict == "PASS" else (verdict, why)
            results.append({"name": name, "what": what, "verdict": verdict, "why": why})
        text = render(results)
        with open(os.path.join(out, "SUMMARY.txt"), "w") as f:
            f.write(text + "\n")
        print("\n" + text)
        sys.exit(0 if all(r["verdict"] == "PASS" for r in results) else 1)
    finally:
        if not a.keep:
            simctl("shutdown", udid)
            simctl("delete", udid)


if __name__ == "__main__":
    main()
