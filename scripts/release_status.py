#!/usr/bin/env python3
"""Release status: where the release stands, in a dozen lines, from records that already exist.

  python3 scripts/release_status.py              local records only, under a second
  zsh -ic 'python3 scripts/release_status.py --asc'   also runs the submit gate against App Store Connect (about 25 s)

Why (Docs/ai/RETRO_5.8.md, gap 5): one conversation carried 5.8 and was compacted 49 times, and "where are we" was
answered from memory. This is a page nobody maintains: every line is read from a file a tool already writes, so a
new session, or the owner, gets the same answer.

What each line reads:
- the version: `Docs/SHIPPED_VERSION.json` and the first numbered heading of `CHANGELOG.md`;
- app code since the last tag: `git diff` over `OpenIntelligence/` and the project file;
- the phone: the install record of `scripts/install_to_phone.py` and the last build `scripts/phone_watch.py` saw;
- how answers fared on the phone: `scripts/lifecycle_scenarios.py --real-use` over the pulled journal, last 7 days;
- the last lifecycle run, UI shots and release health report: their own summary files;
- the store copy's figures: `scripts/check_claims.py`, when it exists;
- with `--asc`, the submit gate's first line.
A line whose record does not exist says so. Nothing here is typed by hand, and nothing is written.
"""
import argparse, datetime, glob, json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
EVIDENCE = os.path.expanduser("~/Library/Developer/OpenIntelligence-evidence")
HEALTH = os.path.expanduser("~/.agents/data/oi-release-health/latest.md")
sys.path.insert(0, HERE)


def git(*args):
    try:
        r = subprocess.run(["git", "-C", ROOT, *args], capture_output=True, text=True, timeout=90)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def age(path):
    days = (datetime.datetime.now().timestamp() - os.path.getmtime(path)) / 86400
    return "today" if days < 1 else f"{days:.0f} day{'s' if days >= 1.5 else ''} ago"


def newest(pattern):
    found = glob.glob(pattern)
    return max(found, key=os.path.getmtime) if found else None


def first_line(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.readline().strip()


def version_line():
    try:
        shipped = json.load(open(os.path.join(ROOT, "Docs", "SHIPPED_VERSION.json")))
    except Exception:
        return "version: Docs/SHIPPED_VERSION.json could not be read"
    heading = re.search(r"^## ([0-9][0-9.]*)(.*)$", open(os.path.join(ROOT, "CHANGELOG.md"), encoding="utf-8").read(), re.M)
    review = shipped.get("in_review") or {}
    parts = [f"live {shipped.get('app_store')}"]
    if review:
        parts.append("in review " + ", ".join(f"{k} {v}" for k, v in sorted(review.items())))
    if heading:
        parts.append(f"CHANGELOG's open section {heading.group(1)}")
    return "version: " + "; ".join(parts) + f" (SHIPPED_VERSION.json updated {shipped.get('updated')})"


def code_line():
    tag = git("describe", "--tags", "--abbrev=0")
    if not tag:
        return "app code: no tag found"
    changed = [l for l in git("diff", "--name-only", tag, "HEAD", "--", "OpenIntelligence", "OpenIntelligence.xcodeproj").splitlines() if l]
    commits = git("rev-list", "--count", f"{tag}..HEAD")
    dirty = [l for l in git("status", "--porcelain").splitlines() if l]
    return (f"app code: {len(changed)} app files changed since {tag} ({commits} commits since, "
            f"{len(dirty)} uncommitted files in the checkout)")


def phone_line():
    record = os.path.join(EVIDENCE, "installs.jsonl")
    installed = None
    if os.path.exists(record):
        for line in open(record):
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            if entry.get("installed"):
                installed = entry
    seen = None
    try:
        seen = (json.load(open(os.path.join(EVIDENCE, "watch", "state.json"))).get("process") or [None])[0]
    except Exception:
        pass
    if not installed:
        return "phone: no install recorded by scripts/install_to_phone.py" + (f"; last build seen running: {seen}" if seen else "")
    name = f"{installed['version']} ({installed['build']})"
    text = (f"phone: last install {name} = {installed['commit'][:8]}"
            + (" + uncommitted changes" if installed.get("dirty") else "") + f", {installed['t'][:16].replace('T', ' ')}")
    head = git("rev-parse", "HEAD")
    if head and not head.startswith(installed["commit"][:8]):
        behind = git("rev-list", "--count", f"{installed['commit']}..HEAD")
        app = [l for l in git("diff", "--name-only", installed["commit"], "HEAD", "--", "OpenIntelligence",
                              "OpenIntelligence.xcodeproj").splitlines() if l]
        text += f"; main is {behind} commits past it, {len(app)} app files different"
    if seen and seen != name:
        text += f"; the watch last saw {seen} running, not that build"
    return text


def real_use_line():
    journal = os.path.join(EVIDENCE, "watch", "verification_events.jsonl")
    if not os.path.exists(journal):
        return "answers on the phone: no journal pulled yet (scripts/phone_watch.py pulls it)"
    try:
        import lifecycle_scenarios as life
        since = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=7)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
        rows = life.real_use([e for e in life.read_journal(journal, since=since) if e.get("host") != "uitest"])
    except Exception as e:
        return f"answers on the phone: could not be read ({type(e).__name__})"
    if not rows:
        return f"answers on the phone: none in the last 7 days (journal pulled {age(journal)})"
    parts = []
    for kind, label in (("stayed", "in front"), ("left", "left"), ("restarted", "restarted")):
        group = [r for r in rows if r["kind"] == kind]
        if group:
            ok = sum(1 for r in group if r["end"] == "ok")
            parts.append(f"{label} {100 * ok / len(group):.0f}% ({ok} of {len(group)})")
    return f"answers on the phone, last 7 days: finished {', '.join(parts)} (journal pulled {age(journal)})"


def summary_line(label, pattern, missing):
    path = newest(pattern)
    return f"{label}: {first_line(path)} ({age(path)})" if path else f"{label}: {missing}"


def health_line():
    if not os.path.exists(HEALTH):
        return "release health: no report yet (scripts/release_health.py)"
    text = open(HEALTH, encoding="utf-8").read()
    new = re.search(r"## New since the last run\n\n(.*?)\n\n", text, re.S)
    lines = [l[2:] for l in (new.group(1).splitlines() if new else []) if l.startswith("- ")]
    rating = re.search(r"- US store: (.*)", text)
    return (f"release health ({age(HEALTH)}): " + ("; ".join(lines)[:220] if lines else "nothing new")
            + (f"; {rating.group(1)}" if rating else ""))


def claims_line():
    if not os.path.exists(os.path.join(HERE, "check_claims.py")):
        return None
    try:
        import check_claims
        result = check_claims.check(ROOT)
        counts = result.get("counts", {})
        state = "FAIL" if result.get("failures") else "ok"
        return (f"store copy figures: {state}, " + ", ".join(f"{v} {k}" for k, v in sorted(counts.items()))
                + (f"; first failure: {str(result['failures'][0])[:140]}" if result.get("failures") else ""))
    except Exception as e:
        return f"store copy figures: check_claims.py could not run ({type(e).__name__}: {str(e)[:80]})"


def gate_line():
    r = subprocess.run([sys.executable, os.path.join(HERE, "asc_submit_gate.py"), version_in_review()],
                       capture_output=True, text=True, timeout=300)
    return "submit gate: " + ((r.stdout.strip().splitlines() or [r.stderr.strip()[-200:]])[0])


def version_in_review():
    shipped = json.load(open(os.path.join(ROOT, "Docs", "SHIPPED_VERSION.json")))
    return str(shipped.get("preparing") or shipped.get("app_store"))


def lines(asc=False):
    out = [version_line(), code_line(), phone_line(), real_use_line(),
           summary_line("lifecycle scenarios", os.path.join(EVIDENCE, "lifecycle", "*", "SUMMARY.txt"),
                        "never run (scripts/lifecycle_scenarios.py)"),
           summary_line("UI shots", os.path.join(EVIDENCE, "ui-shots", "*", "SUMMARY.txt"), "never run (scripts/ui_shots.py)"),
           health_line(), claims_line()]
    if asc:
        out.append(gate_line())
    return [l for l in out if l]


def main():
    p = argparse.ArgumentParser(description="Where the release stands, from records that already exist.")
    p.add_argument("--asc", action="store_true", help="also run the submit gate (needs the key: use zsh -ic)")
    a = p.parse_args()
    print("\n".join(lines(a.asc)))


if __name__ == "__main__":
    main()
