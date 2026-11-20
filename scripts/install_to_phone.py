#!/usr/bin/env python3
"""Builds the app for the owner's iPhone with a build number that names the commit and the time, installs it, and
keeps a record, so "which build is on my phone" has an answer on the phone and on this Mac.

  python3 scripts/install_to_phone.py              mirror out of iCloud, build, install if the app is not running
  python3 scripts/install_to_phone.py --dry-run    print the build number and the commands, change nothing
  python3 scripts/install_to_phone.py --no-install build only
  python3 scripts/install_to_phone.py --launch     also launch it (only when the owner is not holding the phone)
  python3 scripts/install_to_phone.py --force      install although the app is running (ends an answer or an import)

The build number is `<commits>.<DDHHMM>`: `git rev-list --count HEAD`, then the day of the month and the local time
of the build. A build of commit 1876 at 10:41 on the 20th reads "5.8 (1876.201041)" in Settings, in the feedback
mail and on every journal line, with no app code: `CURRENT_PROJECT_VERSION` is given on the xcodebuild command line,
as `MARKETING_VERSION` already is, so no file changes. Apple's `CFBundleVersion` allows one to three integers
separated by periods (developer.apple.com, read 2026-11-20). Xcode Cloud builds keep their run number.

Each run appends one line to ~/Library/Developer/OpenIntelligence-evidence/installs.jsonl (time, build number,
commit, whether app files had uncommitted changes and a hash of them, installed or not, why not).
`scripts/phone_watch.py` reads that file and names the commit when the app launches.

Safety, from Docs/ai/RUNBOOK.md: it builds in a mirror outside iCloud; it refuses to start while another xcodebuild
runs or with less than 12 GiB free; while it builds it stops its own build (never another session's) if free memory
drops under 15% or the disk under 6 GiB; it installs only when the app is not running on the phone or has
written nothing to its journal for ten minutes, because an install ends the app and with it an answer or an import;
and it does not launch the app unless asked.
"""
import argparse, datetime, glob, hashlib, json, os, plistlib, re, shutil, signal, subprocess, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from phone_evidence import BUNDLE, DEVICE

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RECORD = os.path.expanduser("~/Library/Developer/OpenIntelligence-evidence/installs.jsonl")
# Paths whose changes do not change the app, left out of "uncommitted changes".
NOT_APP = ["Docs", "scripts", "BenchmarkRuns", "fastlane", ".claude", ".codex", ".agents", ".github", "ci_scripts", "*.md"]
MIN_FREE_GIB, STOP_FREE_GIB, STOP_FREE_MEMORY = 12, 6, 15
IDLE_MINUTES = 10  # a running app silent this long has no answer or import in flight


def run(*cmd, cwd=None, timeout=120):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)


def git(*args):
    r = run("git", "-C", ROOT, *args, timeout=120)
    if r.returncode != 0:
        sys.exit(f"git {' '.join(args[:2])} failed: {r.stderr.strip()[:300]}")
    return r.stdout


def build_number(commits, moment):
    """`<commits>.<DDHHMM>`: two integers, the second from the day of the month and the local time."""
    return f"{int(commits)}.{moment.day}{moment:%H%M}"


def marketing_version(changelog_text):
    """The first numbered heading of CHANGELOG.md, the version in development (what ci_post_clone.sh stamps)."""
    m = re.search(r"^## ([0-9][0-9.]*)", changelog_text, re.M)
    if not m:
        sys.exit("no numbered heading in CHANGELOG.md")
    return m.group(1)


def source_state():
    """The commit, its count on main, and whether files that go into the app differ from it."""
    excludes = [f":(exclude){p}" for p in NOT_APP]
    diff = git("diff", "HEAD", "--", ".", *excludes)
    untracked = git("ls-files", "--others", "--exclude-standard", "--", ".", *excludes).strip()
    dirty = bool(diff.strip() or untracked)
    digest = hashlib.sha256((diff + "\n" + untracked).encode()).hexdigest()[:12] if dirty else ""
    return {"commit": git("rev-parse", "HEAD").strip(), "commits": int(git("rev-list", "--count", "HEAD")),
            "dirty": dirty, "diff": digest}


def free_gib(path="/System/Volumes/Data"):
    return shutil.disk_usage(path).free / 2 ** 30


def free_memory_percent():
    try:
        m = re.search(r"free percentage: (\d+)%", run("memory_pressure", timeout=30).stdout)
        return int(m.group(1)) if m else None
    except Exception:
        return None


def kill_tree(pid):
    """Ends one process and everything it started, and nothing else on the Mac."""
    children = run("pgrep", "-P", str(pid)).stdout.split()
    for child in children:
        kill_tree(int(child))
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass


def guarded(cmd, cwd, log_path):
    """Runs a build, stopping it if memory or disk run short. Returns (exit code, reason it was stopped or None)."""
    with open(log_path, "w") as log:
        process = subprocess.Popen(cmd, cwd=cwd, stdout=log, stderr=subprocess.STDOUT)
        while process.poll() is None:
            time.sleep(5)
            memory, disk = free_memory_percent(), free_gib()
            reason = (f"free memory fell to {memory}%" if memory is not None and memory < STOP_FREE_MEMORY else
                      f"free disk fell to {disk:.1f} GiB" if disk < STOP_FREE_GIB else None)
            if reason:
                kill_tree(process.pid)
                process.wait(timeout=60)
                return process.returncode, reason
        return process.returncode, None


def app_running():
    """True when the app runs on the phone, False when it does not, None when the phone did not answer."""
    r = run("xcrun", "devicectl", "device", "info", "processes", "--device", DEVICE, timeout=90)
    if r.returncode != 0 or "/" not in r.stdout:
        return None
    return "OpenIntelligence.app/OpenIntelligence" in r.stdout


def idle_minutes():
    """Minutes since the app last wrote to its journal on the phone, or None when that cannot be read.

    A running app that has written nothing for ten minutes is suspended with no answer or import in flight
    (both write events every few seconds), so an install ends nothing the owner would miss.
    """
    folder = os.path.expanduser("~/Library/Developer/OpenIntelligence-evidence/watch")
    os.makedirs(folder, exist_ok=True)
    target = os.path.join(folder, "verification_events.jsonl")
    r = run("xcrun", "devicectl", "device", "copy", "from", "--device", DEVICE, "--domain-type", "appDataContainer",
            "--domain-identifier", BUNDLE, "--source", "Documents/verification_events.jsonl", "--destination", target, timeout=180)
    if r.returncode != 0 or not os.path.exists(target):
        return None
    last = None
    with open(target, "rb") as f:
        f.seek(max(0, os.path.getsize(target) - 20000))
        for line in f.read().decode("utf-8", "replace").splitlines():
            try:
                last = json.loads(line).get("t") or last
            except ValueError:
                continue
    if not last:
        return None
    then = datetime.datetime.fromisoformat(last.replace("Z", "+00:00"))
    return (datetime.datetime.now(datetime.timezone.utc) - then).total_seconds() / 60


def bundle_versions(app):
    """CFBundleVersion of the app and of each extension inside it; they have to agree."""
    found = {}
    for plist in [os.path.join(app, "Info.plist")] + glob.glob(os.path.join(app, "PlugIns", "*.appex", "Info.plist")):
        with open(plist, "rb") as f:
            info = plistlib.load(f)
        found[os.path.basename(os.path.dirname(plist))] = (info.get("CFBundleShortVersionString"), info.get("CFBundleVersion"))
    return found


def record(entry, path=RECORD):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a") as f:
        f.write(json.dumps(entry) + "\n")


def summary(entry):
    """The one line the owner reads."""
    what = f"{entry['version']} ({entry['build']}) = {entry['commit'][:8]}" + (" + uncommitted changes" if entry["dirty"] else "")
    if not entry["installed"]:
        return f"built {what}, NOT installed: {entry['why']}"
    return f"installed {what}, " + ("launched" if entry.get("launched") else "not launched: open it on the phone")


def main():
    p = argparse.ArgumentParser(description="Build for the iPhone with a build number that names the commit; install; record.")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--no-install", action="store_true")
    p.add_argument("--launch", action="store_true")
    p.add_argument("--force", action="store_true", help="install although the app is running on the phone")
    p.add_argument("--provisioning", action="store_true", help="pass -allowProvisioningUpdates (only after an entitlement change)")
    p.add_argument("--scratch", help="folder for the mirror and the build (default: ~/.agents/bin/scratch_root.sh, else /private/tmp)")
    a = p.parse_args()

    scratch = a.scratch
    if not scratch:
        helper = os.path.expanduser("~/.agents/bin/scratch_root.sh")
        scratch = (run(helper).stdout.strip() if os.path.exists(helper) else "") or "/private/tmp"
    mirror, derived = os.path.join(scratch, "oi-src"), os.path.join(scratch, "oi-build")
    app = os.path.join(derived, "Build", "Products", "Debug-iphoneos", "OpenIntelligence.app")

    state = source_state()
    now = datetime.datetime.now().astimezone()
    version = marketing_version(open(os.path.join(ROOT, "CHANGELOG.md"), encoding="utf-8").read())
    build = build_number(state["commits"], now)
    entry: dict = dict(state, t=now.isoformat(timespec="seconds"), version=version, build=build, installed=False, launched=False, why="")

    sync = ["rsync", "-a", "--delete", "--exclude", ".build", "--exclude", ".git", "--exclude", ".git.nosync",
            "--exclude", "BenchmarkRuns", "--exclude", ".claude/worktrees", "--exclude", ".env*", ROOT + "/", mirror + "/"]
    xcodebuild = ["xcodebuild", "build", "-project", "OpenIntelligence.xcodeproj", "-scheme", "OpenIntelligence",
                  "-configuration", "Debug", "-destination", "generic/platform=iOS", "-derivedDataPath", derived,
                  "-jobs", "2", f"MARKETING_VERSION={version}", f"CURRENT_PROJECT_VERSION={build}"]
    if a.provisioning:
        xcodebuild.insert(-2, "-allowProvisioningUpdates")

    if a.dry_run:
        print(f"would build {version} ({build}) = {state['commit'][:8]}" + (" + uncommitted changes" if state["dirty"] else ""))
        print(" ".join(sync))
        print(f"cd {mirror} && " + " ".join(xcodebuild))
        return

    if run("pgrep", "-x", "xcodebuild").stdout.strip():
        sys.exit("another xcodebuild is running; one build at a time on this Mac")
    if free_gib() < MIN_FREE_GIB:
        sys.exit(f"{free_gib():.1f} GiB free on the internal disk, under {MIN_FREE_GIB}: not building (~/.agents/STORAGE.md)")
    check = run("bash", os.path.join(ROOT, "scripts", "check_icloud_conflicts.sh"), timeout=300)
    if check.returncode != 0:
        sys.exit("iCloud conflict copies found; run scripts/check_icloud_conflicts.sh --fix first\n" + check.stdout[-600:])

    started = time.time()
    os.makedirs(mirror, exist_ok=True)
    r = run(*sync, timeout=1800)
    if r.returncode != 0:
        sys.exit("rsync failed: " + r.stderr[-400:])
    log_path = os.path.join(scratch, f"oi-build-{build}.log")
    code, stopped = guarded(xcodebuild, mirror, log_path)
    entry["buildSeconds"] = round(time.time() - started)
    if stopped or code != 0:
        entry["why"] = f"build stopped, {stopped}" if stopped else f"build failed (exit {code}), log {log_path}"
        record(entry)
        print(summary(entry))
        tail = [l for l in open(log_path, errors="replace").read().splitlines() if "error:" in l or "BUILD" in l][-12:]
        print("\n".join(tail))
        sys.exit(1)

    versions = bundle_versions(app)
    if {v for v in versions.values()} != {(version, build)}:
        entry["why"] = f"the bundles do not all read {version} ({build}): {versions}"
        record(entry)
        print(summary(entry))
        sys.exit(1)

    if a.no_install:
        entry["why"] = "--no-install"
    else:
        running = app_running()
        idle = idle_minutes() if running else None
        if running is None:
            entry["why"] = "the phone did not answer (locked a long time, off Wi-Fi or away)"
        elif running and not a.force and (idle is None or idle < IDLE_MINUTES):
            entry["why"] = ("the app is in use on the phone" + (f" (active {idle:.0f} min ago)" if idle is not None else "")
                            + " and an install would end it; run again when it is closed, or with --force")
        else:
            r = run("xcrun", "devicectl", "device", "install", "app", "--device", DEVICE, app, timeout=900)
            if r.returncode != 0:
                entry["why"] = "devicectl install failed: " + (r.stderr or r.stdout).strip()[-300:]
            else:
                entry["installed"] = True
                if a.launch:
                    r = run("xcrun", "devicectl", "device", "process", "launch", "--device", DEVICE, "--terminate-existing", BUNDLE, timeout=120)
                    entry["launched"] = r.returncode == 0  # "Locked" after a clean install: installed, not launched
    record(entry)
    print(summary(entry))
    sys.exit(0 if entry["installed"] or a.no_install else 2)


if __name__ == "__main__":
    main()
