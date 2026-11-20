#!/usr/bin/env python3
"""UI shots: every main screen before and after a change, side by side, so the owner sees a UI change before it is
on his phone.

  python3 scripts/ui_shots.py pair --before HEAD          the last commit against the working tree
  python3 scripts/ui_shots.py pair --before v5.7.0 --after HEAD
  python3 scripts/ui_shots.py take <label> [--ref worktree]   one set of screenshots
  python3 scripts/ui_shots.py compare <folder A> <folder B>   compare two sets taken earlier

Why (Docs/ai/RETRO_5.8.md, gap 7): during 5.8 about 35 of the owner's messages rejected a UI change after it was
already installed ("tacky", "jumps around", "looks the exact same just renamed"). Read `Docs/ai/DESIGN.md` first;
then run this and send him `sheet.png` before any install.

How: the screenshot tests that already exist (`OpenIntelligenceUITests/FiveChecksUITests`, every test whose name
starts with `testShotsOf`: Chat, Documents and its sheets, every Settings page, Plans, Database, Atlas) run on a new
iPhone simulator with the clock fixed at 9:41. For a `--before` ref the app is built from that ref with today's UI
tests laid over it, so the same robot photographs both. `compare` ignores the status bar and small rendering noise,
and writes, for each screen that changed, one image with before on the left and after on the right and the changed
area outlined; `sheet.png` stacks them, and `SUMMARY.txt` lists changed, unchanged, new and missing screens with
the share of pixels that differ. Results: ~/Library/Developer/OpenIntelligence-evidence/ui-shots/<time>/.

What it does not show: motion (a view that "jumps around" needs a recording), the Mac, iPad, Dark Mode and larger
text sizes, and any screen the screenshot tests do not open. The answers on the Chat screen come from the
screenshot stand-in model, not Apple's.

Safety is the lifecycle script's: waits while a game is open, one xcodebuild at a time, a memory and disk guard on
the build, a simulator of its own that is deleted afterwards.
"""
import argparse, datetime, glob, os, re, shutil, subprocess, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from install_to_phone import ROOT, free_gib, guarded, kill_tree, marketing_version, run

SIM_NAME = "OI ui shots"
DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
EVIDENCE = os.path.expanduser("~/Library/Developer/OpenIntelligence-evidence/ui-shots")
SHOTS = "/private/tmp/oi-checks-shots"  # where FiveChecksUITests writes
TEST_CLASS = "OpenIntelligenceUITests/FiveChecksUITests"
GAMES = "World of Warcraft.app/Contents/MacOS|League of Legends.app/Contents/MacOS"
STATUS_BAR = 0.065  # the top share of the screen that is ignored: clock, signal, battery
CHANNEL_NOISE = 24  # a pixel differs when a colour channel moves by more than this (antialiasing moves less)
CHANGED_SHARE = 0.002  # a screen changed when more than 0.2% of its pixels differ


# ---------------------------------------------------------------- comparing (needs Pillow, which this Mac's Python has)

def difference(path_a, path_b):
    """(share of pixels that differ, box around them or None). Different sizes count as wholly changed."""
    from PIL import Image, ImageChops
    a, b = Image.open(path_a).convert("RGB"), Image.open(path_b).convert("RGB")
    if a.size != b.size:
        return 1.0, (0, 0) + b.size
    top = int(a.height * STATUS_BAR)
    diff = ImageChops.difference(a, b).convert("L").point(lambda v: 255 if v > CHANNEL_NOISE else 0)
    diff.paste(0, (0, 0, a.width, top))
    box = diff.getbbox()
    if not box:
        return 0.0, None
    changed = diff.histogram()[255]
    return changed / (a.width * (a.height - top)), box


def side_by_side(path_a, path_b, box, label_a, label_b, name, out_path, height=1400):
    from PIL import Image, ImageDraw, ImageFont
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 40)
    except Exception:
        font = ImageFont.load_default()
    a, b = Image.open(path_a).convert("RGB"), Image.open(path_b).convert("RGB")
    if box:
        ImageDraw.Draw(b).rectangle([box[0] - 6, box[1] - 6, box[2] + 6, box[3] + 6], outline=(230, 40, 40), width=6)
    scaled = []
    for image in (a, b):
        ratio = height / image.height
        scaled.append(image.resize((int(image.width * ratio), height)))
    gap, band = 40, 110
    sheet = Image.new("RGB", (scaled[0].width + scaled[1].width + gap * 3, height + band + gap), (245, 245, 247))
    draw = ImageDraw.Draw(sheet)
    draw.text((gap, 14), name, fill=(20, 20, 20), font=font)
    draw.text((gap, 60), f"before: {label_a}", fill=(90, 90, 90), font=font)
    draw.text((gap * 2 + scaled[0].width, 60), f"after: {label_b}", fill=(90, 90, 90), font=font)
    sheet.paste(scaled[0], (gap, band))
    sheet.paste(scaled[1], (gap * 2 + scaled[0].width, band))
    sheet.save(out_path)
    return sheet


def compare(folder_a, folder_b, out, label_a="before", label_b="after"):
    """Writes the pairs, the sheet and the summary into `out`; returns the summary rows."""
    os.makedirs(os.path.join(out, "changed"), exist_ok=True)
    names_a = {os.path.basename(p) for p in glob.glob(os.path.join(folder_a, "*.png"))}
    names_b = {os.path.basename(p) for p in glob.glob(os.path.join(folder_b, "*.png"))}
    rows, sheets = [], []
    for name in sorted(names_a | names_b):
        if name not in names_b:
            rows.append((name, "missing after", 1.0))
        elif name not in names_a:
            rows.append((name, "new", 1.0))
        else:
            share, box = difference(os.path.join(folder_a, name), os.path.join(folder_b, name))
            if share > CHANGED_SHARE:
                rows.append((name, "changed", share))
                sheets.append(side_by_side(os.path.join(folder_a, name), os.path.join(folder_b, name), box, label_a, label_b,
                                           name[:-4], os.path.join(out, "changed", name)))
            else:
                rows.append((name, "same", share))
    if sheets:
        from PIL import Image
        shown = sheets[:12]
        width = max(s.width for s in shown)
        stack = Image.new("RGB", (width, sum(s.height for s in shown)), (245, 245, 247))
        y = 0
        for s in shown:
            stack.paste(s, (0, y))
            y += s.height
        if stack.width > 1800:
            stack = stack.resize((1800, int(stack.height * 1800 / stack.width)))
        stack.save(os.path.join(out, "sheet.png"))
    with open(os.path.join(out, "SUMMARY.txt"), "w") as f:
        f.write(render(rows, label_a, label_b) + "\n")
    return rows


def render(rows, label_a="before", label_b="after"):
    count = {kind: sum(1 for r in rows if r[1] == kind) for kind in ("changed", "same", "new", "missing after")}
    lines = [f"{label_a} against {label_b}: {count['changed']} of {len(rows)} screens changed, {count['same']} the same, "
             f"{count['new']} new, {count['missing after']} missing after"]
    for name, kind, share in sorted(rows, key=lambda r: (r[1] == "same", -r[2], r[0])):
        if kind != "same":
            lines.append(f"  {kind:<14} {name[:-4]:<48} " + (f"{100 * share:.1f}% of pixels" if kind == "changed" else ""))
    return "\n".join(lines)


# ---------------------------------------------------------------- taking

def simctl(*args, timeout=300):
    return run("xcrun", "simctl", *args, timeout=timeout)


def stage(ref, scratch):
    """The source to build: the working tree, or a ref with today's UI tests laid over it. Shares the lifecycle
    script's build copy (patched the same way), so going from one to the other rebuilds only what differs."""
    stage_dir, source = os.path.join(scratch, "oi-life-stage"), os.path.join(scratch, "oi-life-src")
    shutil.rmtree(stage_dir, ignore_errors=True)
    os.makedirs(stage_dir)
    os.makedirs(source, exist_ok=True)
    excludes = ["--exclude", ".build", "--exclude", ".git", "--exclude", ".git.nosync", "--exclude", "BenchmarkRuns",
                "--exclude", ".claude/worktrees", "--exclude", ".env*"]
    if ref == "worktree":
        r = run("rsync", "-a", *excludes, ROOT + "/", stage_dir + "/", timeout=1800)
        if r.returncode != 0:
            sys.exit("rsync to the stage failed: " + r.stderr[-300:])
    else:
        archive = subprocess.Popen(["git", "-C", ROOT, "archive", ref], stdout=subprocess.PIPE)
        untar = subprocess.run(["tar", "-x", "-C", stage_dir], stdin=archive.stdout)
        if archive.wait() != 0 or untar.returncode != 0:
            sys.exit(f"git archive {ref} failed")
        tests = os.path.join(stage_dir, "OpenIntelligenceUITests")
        shutil.rmtree(tests, ignore_errors=True)
        shutil.copytree(os.path.join(ROOT, "OpenIntelligenceUITests"), tests)
    r = run(sys.executable, os.path.join(ROOT, "scripts", "sim_model_copy.py"), stage_dir)
    if r.returncode != 0:
        print(f"note: {ref} could not be patched for the Simulator model (not needed for screenshots)", flush=True)
    r = run("rsync", "-a", "--checksum", "--delete", stage_dir + "/", source + "/", timeout=1800)
    if r.returncode != 0:
        sys.exit("rsync to the build copy failed: " + r.stderr[-300:])
    version = marketing_version(open(os.path.join(stage_dir, "CHANGELOG.md"), encoding="utf-8").read())
    shutil.rmtree(stage_dir, ignore_errors=True)
    return source, version


def take(ref, out, scratch="/private/tmp", ignore_games=False):
    """Builds `ref`, runs the screenshot tests on a new simulator, and copies the screenshots into `out`."""
    while not ignore_games and run("pgrep", "-f", GAMES).stdout.strip():
        print("A game is running; waiting for it to close (checking every 5 minutes).", flush=True)
        time.sleep(300)
    if run("pgrep", "-x", "xcodebuild").stdout.strip():
        sys.exit("another xcodebuild is running; one at a time on this Mac")
    if free_gib() < 12:
        sys.exit(f"{free_gib():.1f} GiB free on the internal disk, under 12: not running (~/.agents/STORAGE.md)")
    os.makedirs(out, exist_ok=True)
    derived = os.path.join(scratch, "oi-life-dd")
    source, version = stage(ref, scratch)
    for line in simctl("list", "devices").stdout.splitlines():
        if f"{SIM_NAME} (" in line:
            found = re.search(r"[0-9A-F-]{36}", line)
            if found:
                simctl("delete", found.group(0))
    created = simctl("create", SIM_NAME, DEVICE_TYPE, RUNTIME)
    if created.returncode != 0:
        sys.exit("could not create the simulator: " + created.stderr.strip()[-300:])
    udid = created.stdout.strip()
    try:
        began = time.time()
        code, stopped = guarded(
            ["xcodebuild", "build-for-testing", "-project", "OpenIntelligence.xcodeproj", "-scheme", "OpenIntelligenceUITests",
             "-destination", f"platform=iOS Simulator,id={udid}", "-derivedDataPath", derived, "-jobs", "2",
             f"MARKETING_VERSION={version}"], source, os.path.join(out, "build.log"))
        if stopped or code != 0:
            tail = [l for l in open(os.path.join(out, "build.log"), errors="replace").read().splitlines()
                    if "error:" in l or "BUILD" in l][-10:]
            sys.exit(f"the build of {ref} {'was stopped: ' + stopped if stopped else 'failed'}\n" + "\n".join(tail))
        print(f"{ref}: built in {time.time() - began:.0f} s", flush=True)
        simctl("boot", udid)
        simctl("bootstatus", udid, "-b", timeout=600)
        simctl("status_bar", udid, "override", "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100",
               "--wifiBars", "3", "--cellularBars", "4")
        shutil.rmtree(SHOTS, ignore_errors=True)
        names = sorted(set(re.findall(r"func (testShotsOf\w+)\(", open(
            os.path.join(source, "OpenIntelligenceUITests", "FiveChecksUITests.swift"), encoding="utf-8").read())))
        cmd = ["xcodebuild", "test-without-building", "-project", os.path.join(source, "OpenIntelligence.xcodeproj"),
               "-scheme", "OpenIntelligenceUITests", "-destination", f"platform=iOS Simulator,id={udid}",
               "-derivedDataPath", derived] + [f"-only-testing:{TEST_CLASS}/{n}" for n in names]
        log_path = os.path.join(out, "tests.log")
        with open(log_path, "w") as log:
            process = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT)
            started, finished_at = time.time(), None
            while process.poll() is None:
                time.sleep(5)
                if finished_at is None and re.search(r"Executed \d+ tests?, with", open(log_path, errors="replace").read()):
                    finished_at = time.time()
                if (finished_at and time.time() - finished_at > 45) or time.time() - started > 2400:
                    kill_tree(process.pid)
                    break
        shots = glob.glob(os.path.join(SHOTS, "*.png"))
        for path in shots:
            shutil.copy2(path, out)
        print(f"{ref}: {len(shots)} screenshots from {len(names)} tests in {time.time() - began:.0f} s", flush=True)
        return len(shots)
    finally:
        simctl("shutdown", udid)
        simctl("delete", udid)


def main():
    p = argparse.ArgumentParser(description="Screenshots of every main screen before and after a change, side by side.")
    sub = p.add_subparsers(dest="command", required=True)
    one = sub.add_parser("take")
    one.add_argument("label")
    one.add_argument("--ref", default="worktree")
    two = sub.add_parser("pair")
    two.add_argument("--before", required=True, help="a git ref: HEAD, a commit, a tag")
    two.add_argument("--after", default="worktree")
    both = sub.add_parser("compare")
    both.add_argument("a")
    both.add_argument("b")
    for parser in (one, two):
        parser.add_argument("--ignore-games", action="store_true")
    a = p.parse_args()
    stamp = datetime.datetime.now().strftime("%Y-%m-%d_%H%M%S")
    if a.command == "take":
        out = os.path.join(EVIDENCE, f"{stamp}-{a.label}")
        take(a.ref, out, ignore_games=a.ignore_games)
        print(out)
    elif a.command == "compare":
        out = os.path.join(EVIDENCE, f"{stamp}-compare")
        print(render(compare(a.a, a.b, out, os.path.basename(a.a.rstrip('/')), os.path.basename(a.b.rstrip('/')))))
        print(out)
    else:
        out = os.path.join(EVIDENCE, stamp)
        before, after = os.path.join(out, "before"), os.path.join(out, "after")
        take(a.before, before, ignore_games=a.ignore_games)
        take(a.after, after, ignore_games=a.ignore_games)
        rows = compare(before, after, out, a.before, a.after)
        print(render(rows, a.before, a.after))
        print(f"send the owner {os.path.join(out, 'sheet.png')}" if any(r[1] == "changed" for r in rows)
              else "no screen changed, so there is nothing to show him")
        print(out)


if __name__ == "__main__":
    main()
