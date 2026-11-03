#!/usr/bin/env python3
"""Reads what a development build recorded on a device and checks roadmap rows against it (5.8).

The app writes `Documents/verification_events.jsonl` (one JSON line per event, `VerificationJournal.swift`) and
`Documents/pipeline_trace.log` (every log line) in Debug builds. This copies both, with their rotated copies, the
MetricKit reports and the crash report list, off the iPhone over Wi-Fi with `devicectl`, then checks each rule in
`scripts/phone_evidence_rules.json` and prints, per roadmap row: PASS with the event lines that prove it, FAIL with
what was seen instead, or NOT SEEN.

Usage:
  python3 scripts/phone_evidence.py                 pull from the iPhone, then check
  python3 scripts/phone_evidence.py --dir DIR       check files already pulled into DIR
  python3 scripts/phone_evidence.py --since 2026-11-03T12:00   ignore events before a time (the install of the build)
  python3 scripts/phone_evidence.py --json          the result as JSON, for closing rows

The pulled files stay outside the repository (`~/Library/Developer/OpenIntelligence-evidence/<time>`): the trace holds
file names and questions. Never commit them.

A rule (see the rules file) names a roadmap row and lists conditions that must all hold:
  {"e": "liveactivity.answer.start", "o": "ok", "f": {"trigger": "leavingFront"}, "min": 1}
`e` may end in `*` to match a prefix. A field value of ">=N" compares numbers. `absent_trace` lists patterns that must
not appear in the trace, and `trace` lists ones that must.
"""
import argparse, datetime, json, os, re, subprocess, sys

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
    if isinstance(wanted, str) and wanted.startswith(">="):
        try:
            return float(actual) >= float(wanted[2:])
        except ValueError:
            return False
    return str(actual) == str(wanted)


def matches(e, cond):
    name = cond["e"]
    if name.endswith("*"):
        if not e.get("e", "").startswith(name[:-1]):
            return False
    elif e.get("e") != name:
        return False
    if "o" in cond and e.get("o") != cond["o"]:
        return False
    fields = e.get("f", {})
    return all(field_ok(fields.get(k), v) for k, v in cond.get("f", {}).items())


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
    ) or any("unwanted_trace" in p for p in problems)
    return ("FAIL" if went_wrong else "NOT SEEN"), proof, problems


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir")
    ap.add_argument("--since")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--rules", default=os.path.join(HERE, "phone_evidence_rules.json"))
    args = ap.parse_args()
    folder = args.dir
    if not folder:
        stamp = datetime.datetime.now().strftime("%Y-%m-%d_%H%M%S")
        folder = os.path.expanduser(f"~/Library/Developer/OpenIntelligence-evidence/{stamp}")
        got = pull(folder)
        print(f"Pulled into {folder}: {', '.join(got) or 'nothing (is the phone on Wi-Fi and unlocked?)'}",
              file=sys.stderr)
    events = load_events(folder, args.since)
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
