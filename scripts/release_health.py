#!/usr/bin/env python3
"""Release health: what Apple reports about the live app, and what changed since the last look.

  zsh -ic 'python3 scripts/release_health.py'      read, print the report and what is new since the last run
  python3 scripts/release_health.py --install      run it every Monday at 09:15 from launchd, with a notification
                                                   only when something changed
  python3 scripts/release_health.py --uninstall    stop that
  python3 scripts/release_health.py --show         print the last report, read nothing

Why (Docs/ai/RETRO_5.8.md, gap 9): once a version shipped, nothing watched it. Crashes and reviews reached the
agent only when the owner pasted them.

What it reads, all read-only:
- the live version on each platform (App Store Connect);
- written reviews (App Store Connect `customerReviews`): rating, date, country, title, text;
- the public rating and its count in the US store (Apple's lookup service);
- Apple's power and performance metrics for iPhone and iPad (launch time, hangs, memory, disk writes, battery),
  with the regressions Apple itself flags between versions (`perfPowerMetrics`; the API has no Mac platform for
  this, measured 2026-11-20);
- hang, launch and disk-write signatures for the live build of each platform (`diagnosticSignatures`).

What it cannot read: crash reports. They are in Xcode's Organizer, which an agent reads with Xcode's own tools
(`GetTopCrashIssues`), and on the owner's phone, which `scripts/phone_watch.py` watches. Apple shows metrics and
diagnostics only once enough people who share analytics use a version: on 2026-11-20, with 5 ratings, it returned
none, so most weeks this prints "nothing new", and that is the answer.

State and reports are kept outside the repository, in ~/.agents/data/oi-release-health/ (`latest.md`, `state.json`,
`log.txt`). `--install` copies this file there, because a launchd job cannot read ~/Documents.
"""
import argparse, datetime, json, os, plistlib, shutil, subprocess, sys, urllib.parse, urllib.request

APP_ID = "6756559175"
HOME = os.path.expanduser("~/.agents/data/oi-release-health")
STATE, REPORT, LOG = (os.path.join(HOME, n) for n in ("state.json", "latest.md", "log.txt"))
LABEL = "com.gunnarguy.oi-release-health"
PLIST = os.path.expanduser(f"~/Library/LaunchAgents/{LABEL}.plist")
DEPLOYED = os.path.join(HOME, "release_health.py")
PYTHON = os.path.expanduser("~/.pyenv/versions/3.12.13/bin/python3")
LIVE = {"READY_FOR_SALE", "READY_FOR_DISTRIBUTION"}
METRICS_ACCEPT = "application/vnd.apple.xcode-metrics+json"


def reader():
    """A function get(path, params, accept) -> dict. With the key's variables set (zsh -ic) it signs with openssl,
    as scripts/asc_submit_gate.py does; from launchd, where they are not, it uses the owner's ~/ASC client."""
    if os.environ.get("APP_STORE_CONNECT_API_KEY_ID"):
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        from asc_submit_gate import Connect
        return Connect().get
    sys.path.insert(0, os.path.expanduser("~/ASC"))
    from asc.client import API, Client, load_config
    client = Client(load_config())

    def get(path, params=None, accept="application/json"):
        url = (path if path.startswith("http") else API + path) + ("?" + urllib.parse.urlencode(params) if params else "")
        raw, _ = client._request("GET", url, accept=accept)
        return json.loads(raw)
    return get


def soft(get, path, params=None, accept="application/json"):
    """A read that answers {} when Apple refuses it, so one missing data set does not stop the report."""
    try:
        return get(path, params, accept)
    except Exception as e:
        return {"error": str(e)[:200]}


def collect(get):
    snap = {"read": datetime.datetime.now().astimezone().isoformat(timespec="seconds"), "live": {}, "reviews": [],
            "rating": None, "regressions": [], "metrics": [], "signatures": {}}
    versions = soft(get, f"/v1/apps/{APP_ID}/appStoreVersions", {"limit": 30}).get("data") or []
    for v in versions:
        a = v["attributes"]
        if (a.get("appVersionState") or a.get("appStoreState")) in LIVE and a["platform"] not in snap["live"]:
            build = soft(get, f"/v1/appStoreVersions/{v['id']}/build").get("data")
            snap["live"][a["platform"]] = {"version": a.get("versionString"),
                                           "build": build["attributes"]["version"] if build else None,
                                           "buildId": build["id"] if build else None}
    reviews = soft(get, f"/v1/apps/{APP_ID}/customerReviews", {"sort": "-createdDate", "limit": 50}).get("data") or []
    for r in reviews:
        a = r["attributes"]
        snap["reviews"].append({"id": r["id"], "rating": a.get("rating"), "date": (a.get("createdDate") or "")[:10],
                                "country": a.get("territory"), "title": a.get("title") or "", "body": a.get("body") or ""})
    try:
        with urllib.request.urlopen(f"https://itunes.apple.com/lookup?id={APP_ID}&country=us", timeout=20) as response:
            found = (json.loads(response.read()).get("results") or [{}])[0]
        snap["rating"] = {"average": found.get("averageUserRating"), "count": found.get("userRatingCount"),
                          "storeVersion": found.get("version")}
    except Exception:
        pass
    metrics = soft(get, f"/v1/apps/{APP_ID}/perfPowerMetrics", {"filter[platform]": "IOS"}, METRICS_ACCEPT)
    for item in (metrics.get("insights") or {}).get("regressions") or []:
        snap["regressions"].append(item.get("summaryString") or f"{item.get('metric')} regressed in {item.get('latestVersion')}")
    for product in metrics.get("productData") or []:
        for category in product.get("metricCategories") or []:
            for metric in category.get("metrics") or []:
                for data in metric.get("datasets") or []:
                    points = data.get("points") or []
                    if not points:
                        continue
                    criteria = data.get("filterCriteria") or {}
                    snap["metrics"].append({
                        "metric": metric.get("identifier"), "unit": (metric.get("unit") or {}).get("displayName"),
                        "device": criteria.get("deviceMarketingName") or criteria.get("device"),
                        "percentile": (criteria.get("percentile") or "").replace("percentile.", ""),
                        "latest": points[-1], "previous": points[-2] if len(points) > 1 else None})
    for platform, live in snap["live"].items():
        found = []
        for kind in ("HANGS", "LAUNCHES", "DISK_WRITES"):
            if not live.get("buildId"):
                continue
            data = soft(get, f"/v1/builds/{live['buildId']}/diagnosticSignatures",
                        {"filter[diagnosticType]": kind, "limit": 10}).get("data") or []
            found += [{"id": d["id"], "kind": kind, "weight": d["attributes"].get("weight"),
                       "signature": (d["attributes"].get("signature") or "")[:160]} for d in data]
        snap["signatures"][platform] = found
    return snap


def changes(old, new):
    """What is new since the last run, one line each. Empty when nothing changed."""
    out = []
    for platform, live in sorted(new["live"].items()):
        before = (old.get("live") or {}).get(platform, {})
        if before.get("version") != live["version"]:
            out.append(f"{platform}: version {live['version']} (build {live['build']}) is live"
                       + (f", was {before['version']}" if before.get("version") else ""))
    known = {r["id"] for r in old.get("reviews") or []}
    for r in new["reviews"]:
        if r["id"] not in known:
            text = " ".join((r["title"] + ". " + r["body"]).split())[:220]
            out.append(f"new review: {r['rating']} stars, {r['date']}, {r['country']}: {text}")
    before, after = old.get("rating") or {}, new.get("rating") or {}
    if after and (before.get("count") != after.get("count") or before.get("average") != after.get("average")):
        was = f", was {before.get('average')} from {before.get('count')}" if before else ""
        out.append(f"US rating: {after.get('average')} from {after.get('count')} ratings{was}")
    for line in new["regressions"]:
        if line not in (old.get("regressions") or []):
            out.append("Apple flags a regression: " + line)
    seen = {s["id"] for found in (old.get("signatures") or {}).values() for s in found}
    for platform, found in sorted(new["signatures"].items()):
        fresh = [s for s in found if s["id"] not in seen]
        if fresh:
            top = max(fresh, key=lambda s: s.get("weight") or 0)
            out.append(f"{platform}: {len(fresh)} new {top['kind'].lower().replace('_', ' ')} signature(s), heaviest "
                       f"{top.get('weight')}%: {top['signature']}")
    if new["metrics"] and not old.get("metrics"):
        out.append(f"Apple now reports {len(new['metrics'])} performance figures for iPhone and iPad")
    return out


def render(snap, new_lines):
    lines = [f"# OpenIntelligence release health, read {snap['read']}", ""]
    lines += ["## New since the last run", ""] + ([f"- {l}" for l in new_lines] or ["Nothing new."]) + [""]
    lines += ["## Live", ""] + [f"- {p}: {l['version']} (build {l['build']})" for p, l in sorted(snap["live"].items())] + [""]
    rating = snap.get("rating") or {}
    lines += ["## Ratings and reviews", "",
              f"- US store: {rating.get('average')} from {rating.get('count')} ratings (store shows version {rating.get('storeVersion')})",
              f"- Written reviews: {len(snap['reviews'])}"]
    lines += [f"  - {r['rating']} stars, {r['date']}, {r['country']}: {' '.join((r['title'] + '. ' + r['body']).split())[:200]}"
              for r in snap["reviews"][:5]] + [""]
    lines += ["## Apple's performance figures (iPhone and iPad)", ""]
    if not snap["metrics"]:
        lines.append("None reported: Apple shows them only once enough people who share analytics use a version.")
    for m in snap["metrics"][:30]:
        change = ""
        if m["previous"] and m["previous"].get("value"):
            delta = 100 * (m["latest"]["value"] - m["previous"]["value"]) / m["previous"]["value"]
            change = f", {delta:+.0f}% against {m['previous'].get('version')}"
        lines.append(f"- {m['metric']} ({m['device']}, {m['percentile']}): {m['latest'].get('value')} {m['unit']} "
                     f"in {m['latest'].get('version')}{change}")
    lines += [""] + [f"- Apple flags a regression: {r}" for r in snap["regressions"]]
    lines += ["", "## Hang, launch and disk-write signatures for the live builds", ""]
    total = sum(len(v) for v in snap["signatures"].values())
    if not total:
        lines.append("None reported.")
    for platform, found in sorted(snap["signatures"].items()):
        lines += [f"- {platform} {s['kind']}: {s.get('weight')}% {s['signature']}" for s in found[:8]]
    lines += ["", "Not here: crash reports (Xcode's Organizer, or the owner's phone through scripts/phone_watch.py)."]
    return "\n".join(lines) + "\n"


def install():
    os.makedirs(HOME, exist_ok=True)
    shutil.copy2(os.path.abspath(__file__), DEPLOYED)
    plist = {"Label": LABEL, "ProgramArguments": [PYTHON, DEPLOYED, "--notify"],
             "StartCalendarInterval": {"Weekday": 1, "Hour": 9, "Minute": 15},
             "StandardOutPath": os.path.join(HOME, "launchd.out"), "StandardErrorPath": os.path.join(HOME, "launchd.err")}
    with open(PLIST, "wb") as f:
        plistlib.dump(plist, f)
    domain = f"gui/{os.getuid()}"
    subprocess.run(["launchctl", "bootout", f"{domain}/{LABEL}"], capture_output=True)
    r = subprocess.run(["launchctl", "bootstrap", domain, PLIST], capture_output=True, text=True)
    print(f"installed: Mondays 09:15, {PLIST}" if r.returncode == 0 else f"launchctl refused: {r.stderr.strip()}")
    print(f"it runs the copy at {DEPLOYED}; run --install again after changing this script")
    return r.returncode


def uninstall():
    subprocess.run(["launchctl", "bootout", f"gui/{os.getuid()}/{LABEL}"], capture_output=True)
    if os.path.exists(PLIST):
        os.remove(PLIST)
    print("removed the weekly run; the reports in " + HOME + " are kept")


def main():
    p = argparse.ArgumentParser(description="What Apple reports about the live app, and what changed since the last look.")
    p.add_argument("--install", action="store_true")
    p.add_argument("--uninstall", action="store_true")
    p.add_argument("--show", action="store_true")
    p.add_argument("--notify", action="store_true", help="post a Mac notification when something changed")
    a = p.parse_args()
    if a.install:
        sys.exit(install())
    if a.uninstall:
        return uninstall()
    if a.show:
        print(open(REPORT).read() if os.path.exists(REPORT) else "no report yet; run it once")
        return
    os.makedirs(HOME, exist_ok=True)
    try:
        old = json.load(open(STATE))
    except Exception:
        old = {}
    snap = collect(reader())
    new_lines = changes(old, snap) if old else []
    report = render(snap, new_lines if old else ["First run: this is the baseline."])
    with open(REPORT, "w") as f:
        f.write(report)
    with open(STATE, "w") as f:
        json.dump(snap, f, indent=1)
    with open(LOG, "a") as f:
        f.write(f"{snap['read']} {len(new_lines)} new: " + " | ".join(new_lines)[:400] + "\n")
    print(report)
    if a.notify and new_lines:
        text = new_lines[0].replace('"', "'")[:180] + (f" (+{len(new_lines) - 1} more)" if len(new_lines) > 1 else "")
        subprocess.run(["osascript", "-e", f'display notification "{text}" with title "OpenIntelligence release health"'], check=False)


if __name__ == "__main__":
    main()
