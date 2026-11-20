#!/usr/bin/env python3
"""Phone watch: prints one line each time the development build on the iPhone does something worth reading.

The owner should not have to type "check trace". This polls the build's journal (`Documents/verification_events.jsonl`,
written by `VerificationJournal.swift` in Debug builds) and the phone's crash reports over Wi-Fi with `devicectl`, keeps
a cursor on this Mac, and prints a line for each new question, answer, failure, restart, long stall or crash. Run it
under the agent's Monitor tool and each line wakes the agent (see `.claude/skills/phone-watch/SKILL.md`).

Usage:
  python3 scripts/phone_watch.py                 watch from now on, until stopped
  python3 scripts/phone_watch.py --since 2026-11-20T09:00   first report everything since a local time
  python3 scripts/phone_watch.py --once          one pass, then exit
  python3 scripts/phone_watch.py --dir DIR --state FILE     one pass over files already in DIR (the tests use this)

Privacy: the journal holds document names, library names and questions. A line printed here carries only numbers,
true/false and single enumerated words (a mode, a stage, an error type), from a fixed list of fields per event; any
other value prints as <text>. So a line can be pasted or logged. The pulled journal itself stays outside the
repository, in ~/Library/Developer/OpenIntelligence-evidence/watch, and is never committed.

Cost, measured 2026-11-20 on the iPhone 16 Pro Max over Wi-Fi: a change check (a file listing) 0.9 s, a journal
copy of 7.2 MB 4.2 s. It copies only when the listing changed or changed within the last two minutes.

It only reads. For checking roadmap rows against the same journal use `scripts/phone_evidence.py`.
"""
import argparse, datetime, json, os, re, subprocess, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from phone_evidence import BUNDLE, DEVICE  # the owner's iPhone and the app's bundle id

HOME = os.path.expanduser("~/Library/Developer/OpenIntelligence-evidence/watch")
INSTALLS = os.path.expanduser("~/Library/Developer/OpenIntelligence-evidence/installs.jsonl")
JOURNAL, PREVIOUS = "verification_events.jsonl", "verification_events.prev.jsonl"
TOKEN = re.compile(r"^[A-Za-z0-9_.+-]{1,32}$")
STALL_MS = 2000
MAX_LINES = 12
BAD_OUTCOMES = {"failed", "cancelled"}
# Events printed one line each, with the only fields a line may carry.
SHOW = {
    "answer.start": ("mode", "passages", "first"),
    "answer.done": ("mode", "badge", "scene", "inFront", "sources", "error"),
    "model.failure": ("kind", "mode", "action"),
    "launch.chatUsable": ("ms", "passages", "watchdog"),
    "metrickit.diagnostic": (),
}
# Events printed only when a field has one of these values.
SHOW_WHEN = {
    "answer.responsiveness": ("verdict", {"partial", "unjudged"}, ("verdict", "stage")),
    "bgtask.answer": ("phase", {"expired", "failed"}, ("phase", "fraction")),
    "bgtask.import": ("phase", {"expired", "failed"}, ("phase", "fraction")),
    "liveactivity.answer.end": ("success", {"false"}, ("success", "shown")),
    "system.state": ("thermal", {"2", "3"}, ("thermal", "lowPower", "memoryPressure")),
}
# Fields a failed event of any other kind may carry.
GENERIC = ("mode", "phase", "stage", "kind", "result", "type", "trigger", "attempt", "background")
LABEL = {"answer.start": "question asked", "answer.done": "answer done", "model.failure": "MODEL FAILURE",
         "launch.chatUsable": "app launched", "metrickit.diagnostic": "MetricKit diagnostic arrived",
         "answer.responsiveness": "answer judged", "bgtask.answer": "background answer",
         "bgtask.import": "background import", "liveactivity.answer.end": "Live Activity ended without success",
         "system.state": "device state"}


def load_installs(path):
    """Build name ("5.8 (1876.201041)") to its line in the record `scripts/install_to_phone.py` keeps, plus the
    newest build that was installed under the key None."""
    known = {}
    if path and os.path.exists(path):
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    entry = json.loads(line)
                    name = f"{entry['version']} ({entry['build']})"
                except (ValueError, KeyError, TypeError):
                    continue
                if entry.get("installed"):
                    known[name] = entry
                    known[None] = dict(entry, name=name)
    return known


def commit_of(build, installs):
    """" = 19c36f86 + uncommitted changes" for a build this Mac installed; a note when it is not the newest one."""
    if not installs:
        return ""
    entry, newest = installs.get(build), installs.get(None)
    text = ""
    if entry and re.fullmatch(r"[0-9a-f]{7,40}", str(entry.get("commit", ""))):
        text = f" = {entry['commit'][:8]}" + (" + uncommitted changes" if entry.get("dirty") else "")
    if newest and newest["name"] != build:
        text += f" (NOT the newest install, which is {build_name(newest['name'])})"
    return text


def safe(value):
    """A value that can be printed: a number, true/false, or one enumerated word. Anything else is <text>."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return f"{value:g}"
    if isinstance(value, str) and TOKEN.match(value):
        return value
    return "<text>"


def build_name(value):
    """The journal's version stamp, "5.8 (150)", when it has that shape."""
    return value if isinstance(value, str) and re.match(r"^[0-9.]{1,12}( \([0-9.]{1,18}\))?$", value) else safe(value)


def fields(event, names):
    f = event.get("f") or {}
    parts = []
    for name in names:
        value = f.get(name, event.get(name) if name in ("ms",) else None)
        if value is not None and value != "" and not (name == "error" and value == "none"):
            parts.append(f"{name}={safe(value)}")
    return ", ".join(parts)


def local_time(t):
    try:
        moment = datetime.datetime.fromisoformat(t.replace("Z", "+00:00")).astimezone()
        return moment.strftime("%H:%M:%S")
    except Exception:
        return "??:??:??"


def number(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def describe(events, process, installs=None):
    """Lines for a batch of new events. `process` is the last seen (version, pid), updated in place."""
    lines, imports, stalls, longest = [], {}, 0, (0.0, "")
    for e in events:
        name, f, when = e.get("e", ""), e.get("f") or {}, local_time(e.get("t", ""))
        seen = [build_name(e.get("v")), safe(e.get("pid"))]
        if e.get("pid") is not None and seen != process.get("now"):
            if process.get("now") and process["now"][1] != seen[1]:
                lines.append(f"{when} app restarted: build {seen[0]}{commit_of(seen[0], installs)}, pid {seen[1]} "
                             f"(was pid {process['now'][1]})")
            process["now"] = seen
        if name == "mainThread.stall":
            ms = number(f.get("ms", e.get("ms")))
            if ms >= STALL_MS:
                stalls += 1
                if ms > longest[0]:
                    longest = (ms, safe(f.get("phase")))
            continue
        if name == "import.stage" and f.get("to") in ("complete", "failed"):
            key = (safe(f.get("to")), safe(f.get("type")))
            imports[key] = imports.get(key, 0) + 1
            continue
        if name in SHOW:
            detail = fields(e, SHOW[name])
            took = f", took {number(e['ms']) / 1000:.1f} s" if name == "answer.done" and e.get("ms") else ""
            outcome = "" if e.get("o") in ("ok", "info", "started", None) else f" [{safe(e.get('o'))}]"
            build = f" build {seen[0]}{commit_of(seen[0], installs)}," if name == "launch.chatUsable" else ""
            if build and lines and " app restarted: " in lines[-1]:
                was = lines.pop().rsplit("(was ", 1)[-1].rstrip(")")
                build = f" build {seen[0]}{commit_of(seen[0], installs)}, pid {seen[1]} (was {was}),"
            lines.append(f"{when} {LABEL[name]}{outcome}:{build} {detail}{took}".rstrip(": ").rstrip())
            continue
        if name in SHOW_WHEN:
            field, values, show = SHOW_WHEN[name]
            if str(f.get(field)) in values:
                lines.append(f"{when} {LABEL[name]}: {fields(e, show)}")
            continue
        if e.get("o") in BAD_OUTCOMES:
            detail = fields(e, GENERIC)
            lines.append(f"{when} {safe(e.get('o')).upper()} {safe(name)}" + (f": {detail}" if detail else ""))
    for (outcome, kind), count in sorted(imports.items()):
        lines.append(f"{count} import{'s' if count != 1 else ''} {outcome} ({kind})")
    if stalls:
        lines.append(f"{stalls} main-thread stall{'s' if stalls != 1 else ''} of {STALL_MS / 1000:g} s or more, "
                     f"longest {longest[0] / 1000:.1f} s (phase {longest[1]})")
    if len(lines) > MAX_LINES:
        extra = len(lines) - MAX_LINES
        lines = lines[:MAX_LINES] + [f"and {extra} more lines; run python3 scripts/phone_evidence.py for all of it"]
    return lines


def read_events(path):
    events = []
    if os.path.exists(path):
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    event = json.loads(line)
                except ValueError:
                    continue
                if isinstance(event, dict) and event.get("t") and event.get("host") != "uitest":
                    events.append(event)
    return events


def new_events(folder, cursor):
    """Events after the cursor, oldest first. Reads the rotated journal too when the current one starts after it."""
    current = read_events(os.path.join(folder, JOURNAL))
    if cursor and current and current[0]["t"] > cursor:
        current = read_events(os.path.join(folder, PREVIOUS)) + current
    return [e for e in current if not cursor or e["t"] > cursor]


def devicectl(*args, timeout=120):
    try:
        return subprocess.run(["xcrun", "devicectl", *args], capture_output=True, text=True, timeout=timeout)
    except Exception:
        return None


def listing():
    """The journal's line in the app's file listing (size and date), or None when the phone does not answer."""
    r = devicectl("device", "info", "files", "--device", DEVICE, "--domain-type", "appDataContainer",
                  "--domain-identifier", BUNDLE, "--subdirectory", "Documents", timeout=60)
    if not r or r.returncode != 0:
        return None
    return next((l.strip() for l in r.stdout.splitlines() if l.strip().startswith(JOURNAL)), "")


def copy(source, folder):
    r = devicectl("device", "copy", "from", "--device", DEVICE, "--domain-type", "appDataContainer",
                  "--domain-identifier", BUNDLE, "--source", "Documents/" + source,
                  "--destination", os.path.join(folder, source), timeout=180)
    return bool(r and r.returncode == 0)


def crash_names(folder=None):
    """Names of the phone's crash reports for the app (a name holds the app's name and a time, nothing else)."""
    if folder:
        path = os.path.join(folder, "crash_reports.txt")
        text = open(path).read() if os.path.exists(path) else ""
    else:
        r = devicectl("device", "info", "files", "--device", DEVICE, "--domain-type", "systemCrashLogs", timeout=60)
        if not r or r.returncode != 0:
            return None
        text = r.stdout
    names = set()
    for line in text.splitlines():
        m = re.search(r"OpenIntelligence[-\w.]*\.ips", line)
        if m:
            names.add(m.group(0))
    return names


def load_state(path):
    try:
        return json.load(open(path))
    except Exception:
        return {}


def save_state(path, state):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".tmp", "w") as f:
        json.dump(state, f)
    os.replace(path + ".tmp", path)


def one_pass(folder, state, from_device, installs_path=None):
    """Reads what is new, returns the lines to print, and moves the cursor in `state`."""
    lines = []
    if from_device:
        line = listing()
        if line is None:
            return None
        now = time.time()
        changed = line != state.get("listing")
        if changed:
            state["listing"], state["changedAt"] = line, now
        if changed or now - state.get("changedAt", 0) < 120:
            if not copy(JOURNAL, folder):
                return None
            first = read_events(os.path.join(folder, JOURNAL))[:1]
            if state.get("cursor") and first and first[0]["t"] > state["cursor"]:
                copy(PREVIOUS, folder)
    events = new_events(folder, state.get("cursor"))
    if events:
        process = {"now": state.get("process")}
        lines += describe(events, process, load_installs(installs_path))
        state["process"], state["cursor"] = process["now"], events[-1]["t"]
    crashes = crash_names(None if from_device else folder)
    if crashes is not None:
        known = set(state.get("crashes") or [])
        if "crashes" in state:
            lines += [f"CRASH report on the phone: {name}" for name in sorted(crashes - known)]
        state["crashes"] = sorted(crashes | known)
    return lines


def main():
    p = argparse.ArgumentParser(description="Print a line for each new event from the iPhone's development build.")
    p.add_argument("--interval", type=float, default=20, help="seconds between checks (default 20)")
    p.add_argument("--since", help="start from this local time instead of from now")
    p.add_argument("--once", action="store_true")
    p.add_argument("--dir", help="read journal files from this folder instead of the phone, one pass")
    p.add_argument("--state", default=os.path.join(HOME, "state.json"))
    p.add_argument("--installs", help="the install record (default: the one scripts/install_to_phone.py writes; "
                                      "with --dir, installs.jsonl in that folder)")
    a = p.parse_args()
    folder = a.dir or HOME
    installs_path = a.installs or (os.path.join(a.dir, "installs.jsonl") if a.dir else INSTALLS)
    os.makedirs(folder, exist_ok=True)
    state = load_state(a.state)
    if a.since:
        from phone_evidence import normalize_since
        state["cursor"] = normalize_since(a.since)
    elif not state.get("cursor") and not a.dir:
        state["cursor"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    misses, away = 0, False
    while True:
        lines = one_pass(folder, state, from_device=not a.dir, installs_path=installs_path)
        if lines is None:
            misses += 1
            if misses == 3 and not away:
                away = True
                print("phone not answering (locked a long time, off Wi-Fi or away); still watching", flush=True)
        else:
            if away:
                print("phone answering again", flush=True)
            misses, away = 0, False
            for line in lines:
                print(line, flush=True)
            save_state(a.state, state)
        if a.once or a.dir:
            return
        time.sleep(a.interval if not away else max(a.interval, 60))


if __name__ == "__main__":
    main()
