#!/usr/bin/env python3
"""Reads what a development build recorded on a device and checks roadmap rows against it (5.8).

The app writes `Documents/verification_events.jsonl` (one JSON line per event, `VerificationJournal.swift`) and
`Documents/pipeline_trace.log` (every log line) in Debug builds. This copies both, with their rotated copies, the
MetricKit reports and the crash report list, off the iPhone over Wi-Fi with `devicectl`, then checks each rule in
`scripts/phone_evidence_rules.json` and prints, per roadmap row: PASS with the event lines that prove it, FAIL with
what was seen instead, or NOT SEEN.

Usage:
  python3 scripts/phone_evidence.py                 pull from the iPhone, then check
  python3 scripts/phone_evidence.py --mac           copy the Mac app's files from its sandbox container, then check
  python3 scripts/phone_evidence.py --dir DIR       check files already pulled into DIR
  python3 scripts/phone_evidence.py --since 2026-11-03T12:00   ignore events before a time (the install of the build):
                                                               this Mac's local time, or UTC with Z or an offset
  python3 scripts/phone_evidence.py --json          the result as JSON, for closing rows

The pulled files stay outside the repository (`~/Library/Developer/OpenIntelligence-evidence/<time>`): the trace holds
file names and questions. Never commit them.

A rule (see the rules file) names a roadmap row and lists conditions that must all hold:
  {"e": "liveactivity.answer.start", "o": "ok", "f": {"trigger": "leavingFront"}, "min": 1}
`e` may end in `*` to match a prefix. A field value of ">=N" or "<=N" compares numbers, and "!=X" matches any other
value. A field the line's `f` lacks is looked up on the line itself, so "os" ("iOS" or "macOS") and "ms" (the
measured duration) can be conditions too. `absent` lists conditions no event may match: an event that matches one
FAILs the rule. `absent_trace` lists patterns that must not appear in the trace, and `trace` lists ones that must.

`--mac` reads the Mac app's sandbox container, `~/Library/Containers/Gunndamental.OpenIntelligence/Data` (its
`Documents` folder holds the journal and the trace), copies the files into the same evidence folder an iPhone pull
uses, and lists the Mac's crash reports from `~/Library/Logs/DiagnosticReports`.

Lines a UI-test or screenshot launch wrote carry `"host": "uitest"` and are dropped: a robot's taps close no row.
"""
import argparse, datetime, glob, json, os, re, shutil, subprocess, sys

DEVICE = "00008140-001130DA1863C01C"
BUNDLE = "Gunndamental.OpenIntelligence"
FILES = [
    "Documents/verification_events.jsonl",
    "Documents/verification_events.prev.jsonl",
    "Documents/pipeline_trace.log",
    "Documents/pipeline_trace.prev.log",
    "Library/Application Support/OpenIntelligence/LocalCache/metric_reports.jsonl",
]
HERE = os.path.dirname(os.path.abspath(__file__))
# Fields that live on the line itself rather than in its `f`, which a condition may still name.
LINE_FIELDS = ("os", "ms", "v", "pid")


def mac_container(home=None):
    """The Mac app's sandbox data folder: the parent of the `Documents` and `Library` paths in FILES."""
    home = home or os.path.expanduser("~")
    return os.path.join(home, "Library", "Containers", BUNDLE, "Data")


def pull_mac(out, home=None):
    """Copies the Mac app's journal, trace and MetricKit reports out of its container, as `pull` does for the phone."""
    os.makedirs(out, exist_ok=True)
    root = mac_container(home)
    got = []
    for source in FILES:
        path = os.path.join(root, source)
        if os.path.exists(path):
            shutil.copy2(path, os.path.join(out, os.path.basename(source)))
            got.append(os.path.basename(source))
    reports = os.path.join(home or os.path.expanduser("~"), "Library", "Logs", "DiagnosticReports")
    crashes = sorted(os.path.basename(p) for p in glob.glob(os.path.join(reports, "OpenIntelligence*")))
    with open(os.path.join(out, "crash_reports.txt"), "w") as f:
        f.write("\n".join(crashes))
    return got


def pull(out):
    os.makedirs(out, exist_ok=True)
    got = []
    for source in FILES:
        dest = os.path.join(out, os.path.basename(source))
        r = subprocess.run(
            ["xcrun", "devicectl", "device", "copy", "from", "--device", DEVICE, "--domain-type", "appDataContainer",
             "--domain-identifier", BUNDLE, "--source", source, "--destination", dest],
            capture_output=True, text=True, timeout=180)
        if r.returncode == 0 and os.path.exists(dest):
            got.append(os.path.basename(source))
    r = subprocess.run(
        ["xcrun", "devicectl", "device", "info", "files", "--device", DEVICE, "--domain-type", "systemCrashLogs"],
        capture_output=True, text=True, timeout=120)
    crashes = [l.strip() for l in r.stdout.splitlines() if l.strip().startswith("OpenIntelligence")]
    with open(os.path.join(out, "crash_reports.txt"), "w") as f:
        f.write("\n".join(crashes))
    return got


def normalize_since(value):
    """`--since` as the journal writes times, UTC with milliseconds and a Z, so the two compare as text.

    A value with no zone ("2026-11-04T08:00", "2026-11-04") is this Mac's local time; one with Z or an offset is taken
    as given. The journal's `t` is UTC, so a local time compared as written was off by the zone (7 or 8 hours here).
    """
    if not value:
        return value
    text = value.strip()
    if text.endswith(("Z", "z")):
        text = text[:-1] + "+00:00"
    moment = datetime.datetime.fromisoformat(text)
    if moment.tzinfo is None:
        moment = moment.astimezone()  # a naive time is local
    moment = moment.astimezone(datetime.timezone.utc)
    return moment.strftime("%Y-%m-%dT%H:%M:%S.") + f"{moment.microsecond // 1000:03d}Z"


def load_events(folder, since):
    events = []
    for name in ("verification_events.prev.jsonl", "verification_events.jsonl"):
        path = os.path.join(folder, name)
        if not os.path.exists(path):
            continue
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    e = json.loads(line)
                except ValueError:
                    continue
                if since and e.get("t", "") < since:
                    continue
                if "host" in e:  # a UI-test or screenshot launch
                    continue
                events.append(e)
    events.sort(key=lambda e: e.get("t", ""))
    return events


def load_trace(folder):
    text = ""
    for name in ("pipeline_trace.prev.log", "pipeline_trace.log"):
        path = os.path.join(folder, name)
        if os.path.exists(path):
            with open(path, encoding="utf-8", errors="replace") as f:
                text += f.read()
    return text


def field_ok(actual, wanted):
    if actual is None:
        return False
    if isinstance(wanted, str) and wanted[:2] in (">=", "<="):
        try:
            a, w = float(actual), float(wanted[2:])
        except ValueError:
            return False
        return a >= w if wanted[:2] == ">=" else a <= w
    if isinstance(wanted, str) and wanted.startswith("!="):
        return str(actual) != wanted[2:]
    return str(actual) == str(wanted)


def field_value(e, key):
    fields = e.get("f", {})
    if key in fields:
        return fields[key]
    return e.get(key) if key in LINE_FIELDS else None


def matches(e, cond):
    name = cond["e"]
    if name.endswith("*"):
        if not e.get("e", "").startswith(name[:-1]):
            return False
    elif e.get("e") != name:
        return False
    if "o" in cond and e.get("o") != cond["o"]:
        return False
    return all(field_ok(field_value(e, k), v) for k, v in cond.get("f", {}).items())


def check(rule, events, trace):
    proof, problems = [], []
    for cond in rule.get("all", []):
        hits = [e for e in events if matches(e, cond)]
        if len(hits) >= cond.get("min", 1):
            proof.extend(hits[: cond.get("min", 1)])
        else:
            near = [e for e in events if e.get("e", "").startswith(cond["e"].rstrip("*"))]
            problems.append({"wanted": cond, "seen": near[-3:]})
    for pattern in rule.get("trace", []):
        m = re.search(pattern, trace)
        if m:
            proof.append({"trace": trace[max(0, m.start() - 20): m.end() + 60].replace("\n", " ")})
        else:
            problems.append({"wanted_trace": pattern})
    for cond in rule.get("absent", []):
        hits = [e for e in events if matches(e, cond)]
        if hits:
            problems.append({"unwanted": cond, "seen": hits[:3]})
    for pattern in rule.get("absent_trace", []):
        m = re.search(pattern, trace)
        if m:
            problems.append({"unwanted_trace": trace[max(0, m.start() - 40): m.end() + 80].replace("\n", " ")})
    if not problems:
        return "PASS", proof, problems
    # FAIL means something went wrong: an event of that name ended failed or cancelled, or the trace holds what must
    # not be there. An event seen with other fields (a Lock Screen check that found 0 scans, an import that ran with
    # the app in front) only means the step hasn't been done yet: NOT SEEN.
    went_wrong = any(
        e.get("o") in ("failed", "cancelled") for p in problems for e in p.get("seen", [])
    ) or any("unwanted_trace" in p or "unwanted" in p for p in problems)
    return ("FAIL" if went_wrong else "NOT SEEN"), proof, problems


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir")
    ap.add_argument("--mac", action="store_true", help="read the Mac app's container instead of the iPhone")
    ap.add_argument("--since")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--rules", default=os.path.join(HERE, "phone_evidence_rules.json"))
    args = ap.parse_args()
    folder = args.dir
    if not folder:
        stamp = datetime.datetime.now().strftime("%Y-%m-%d_%H%M%S")
        folder = os.path.expanduser(
            f"~/Library/Developer/OpenIntelligence-evidence/{stamp}{'-mac' if args.mac else ''}")
        if args.mac:
            got = pull_mac(folder)
            print(f"Copied into {folder}: {', '.join(got) or 'nothing (has a development build run on this Mac?)'}",
                  file=sys.stderr)
        else:
            got = pull(folder)
            print(f"Pulled into {folder}: {', '.join(got) or 'nothing (is the phone on Wi-Fi and unlocked?)'}",
                  file=sys.stderr)
    events = load_events(folder, normalize_since(args.since))
    trace = load_trace(folder)
    with open(args.rules) as f:
        rules = json.load(f)["rules"]
    results = []
    for rule in rules:
        status, proof, problems = check(rule, events, trace)
        results.append({"row": rule["row"], "url": rule.get("url"), "status": status, "proof": proof,
                        "problems": problems, "needs": rule.get("needs", "")})
    if args.json:
        print(json.dumps({"folder": folder, "events": len(events), "results": results}, indent=1))
        return
    print(f"{len(events)} events, trace {len(trace) // 1024} KB, from {folder}\n")
    for status in ("PASS", "FAIL", "NOT SEEN"):
        group = [r for r in results if r["status"] == status]
        print(f"== {status}: {len(group)}")
        for r in group:
            print(f"- {r['row']}")
            if status == "PASS":
                for p in r["proof"][:3]:
                    print("    ", json.dumps(p)[:200])
            elif status == "FAIL":
                for p in r["problems"][:2]:
                    print("    ", json.dumps(p)[:240])
            else:
                print(f"     do: {r['needs']}")
        print()


if __name__ == "__main__":
    main()
