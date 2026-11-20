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
tests laid over it, so the same robot photographs both. `compare` judges a screen two ways. Words: the element list
the tests save beside each shot, compared a page at a time, so a renamed, added or removed label is caught however
small; tips, file paths and "3 seconds ago" are left out, because they differ between two runs of one build. Look: the pixels,
after the two shots are slid to their best vertical fit, because two runs of one build never scroll to the same
pixel (41 of 145 screens of identical code differed by that alone on 2026-11-20). It writes, for each screen that
changed, one image with before on the left and after on the right; `sheet.png` stacks them, and `SUMMARY.txt` lists
what changed and why. Results: ~/Library/Developer/OpenIntelligence-evidence/ui-shots/<time>/.

What it can miss: a change of look smaller than 3% of the screen with no change of words (a recoloured icon, a
border), which is under the level two identical runs differ by. What it does not show: motion (a view that "jumps around" needs a recording), the Mac, iPad, Dark Mode and larger
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
CHANGED_SHARE = 0.002  # two shots are identical when no more than 0.2% of their pixels differ
# Two runs of the same build do not scroll to the same pixel: on 2026-11-20, 41 of 145 screens of identical code
# differed by this alone. So a pair that differs is slid up and down to its best fit before it is judged, and only
# what still differs then counts as a change of look. Words are compared separately, from the element list the
# tests save beside each shot, so a renamed label is caught however small it is.
ALIGNED_SHARE = 0.03  # after the best fit, more than 3% of the middle of the screen still differs (identical code: up to 1.9%)
FIXED_TOP, FIXED_BOTTOM = 0.16, 0.14  # the navigation bar and the tab bar do not scroll
MAX_SLIDE = 0.25  # how far, as a share of the height, one run may have scrolled past the other


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


def aligned_difference(path_a, path_b):
    """The share of the scrolling middle of the screen that still differs at the best vertical fit, and the slide
    in pixels. The fit is searched at a quarter size and then settled pixel by pixel at full size: a fit that is two
    pixels off makes every line of text differ along its edges."""
    from PIL import Image, ImageChops
    full_a, full_b = Image.open(path_a).convert("L"), Image.open(path_b).convert("L")
    if full_a.size != full_b.size:
        return 1.0, 0

    def share_at(a, b, dy):
        top, bottom = int(a.height * FIXED_TOP), int(a.height * (1 - FIXED_BOTTOM))
        y0, y1 = max(top, top + dy), min(bottom, bottom + dy)  # rows of a that have a partner in b
        if y1 - y0 < (bottom - top) // 2:
            return None
        diff = ImageChops.difference(a.crop((0, y0, a.width, y1)), b.crop((0, y0 - dy, b.width, y1 - dy)))
        return sum(diff.point(lambda v: 255 if v > CHANNEL_NOISE else 0).histogram()[255:]) / (a.width * (y1 - y0))

    scale = 4
    small_a, small_b = (i.resize((i.width // scale, i.height // scale)) for i in (full_a, full_b))
    reach = int(small_a.height * MAX_SLIDE)
    coarse = min(((share_at(small_a, small_b, dy), dy) for dy in range(-reach, reach + 1)
                  if share_at(small_a, small_b, dy) is not None), default=(1.0, 0))
    best = (1.0, 0)
    for dy in range(coarse[1] * scale - 2 * scale, coarse[1] * scale + 2 * scale + 1):
        share = share_at(full_a, full_b, dy)
        if share is not None and share < best[0]:
            best = (share, dy)
    return best


def labels(tree_path):
    """What a screen says, from the element list saved beside its shot: one entry per element that has words
    (its kind, its identifier, its label and its value), with positions and memory addresses left out."""
    import collections
    found = collections.Counter()
    if not os.path.exists(tree_path):
        return None
    for line in open(tree_path, encoding="utf-8", errors="replace"):
        kind = re.match(r"\s*(?:→)?\s*(\w+)", line)
        label = re.search(r"label: '((?:[^'\\]|\\.)*)'", line)
        value = re.search(r"value: (.+?)\s*$", line)
        identifier = re.search(r"identifier: '([^']*)'", line)
        if kind and (label or value) and kind.group(1) not in ("Attributes", "Application", "Path", "Query"):
            found[(kind.group(1), identifier.group(1) if identifier else "", label.group(1) if label else "",
                   value.group(1) if value else "")] += 1
    return found


def normal(text):
    """A label with what differs between two runs of one build taken out: file paths (they hold the simulator's
    id) and "3 seconds ago"."""
    text = re.sub(r"/(?:Users|private|var)/\S+", "<path>", text)
    return re.sub(r"\b\d+ (?:second|minute|hour|day)s? ago\b|\bjust now\b", "<when>", text)


def tip_texts(root=ROOT):
    """Every string in the app's tips source. A tip shows in one run and not the next (TipKit paces them), so its
    words, its Close button and the space it covers are not a change."""
    found = set()
    for path in glob.glob(os.path.join(root, "OpenIntelligence", "Services", "Infrastructure", "Tips", "*.swift")):
        found.update(m for m in re.findall(r'"((?:[^"\\]|\\.){4,})"', open(path, encoding="utf-8", errors="replace").read()))
    return found


def words(tree_path, tips=()):
    """(the words on the screen, whether a tip is showing, the words a tip could have put there). None when the
    element list is missing. A tip is a popover (the list has its dismiss region). Scroll bars are left out: their
    value is how far the page happens to be scrolled."""
    found = labels(tree_path)
    if found is None:
        return None
    tip = any(identifier == "PopoverDismissRegion" for (_, identifier, _, _) in found)
    said, tipish = set(), set()
    for (_, identifier, label, value), _count in found.items():
        if "scroll bar" in label.lower() or identifier == "PopoverDismissRegion":
            continue
        for text in (label, value):
            if not text:
                continue
            said.add(normal(text))
            if text == "Close" or any(text == t or (len(t) > 24 and text.startswith(t[:24])) for t in tips):
                tipish.add(normal(text))
    return said, tip, tipish


def page_of(name):
    """The page a shot belongs to: `settings-02-Plain-English-3.png` is the third screenful of
    `settings-02-Plain-English`. Words are compared a page at a time, because a long list holds only the rows
    near where it was scrolled to, and two runs never stop at the same row."""
    return re.sub(r"-\d+$", "", name[:-4] if name.endswith(".png") else name)


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
    tips = tip_texts()
    said = {}  # (side, shot) -> (words, tip showing)
    for side, folder, names in (("a", folder_a, names_a), ("b", folder_b, names_b)):
        for name in names:
            said[(side, name)] = words(os.path.join(folder, name[:-4] + ".tree.txt"), tips)
    page_words = {}  # page -> (gone, new), from every screenful of the page on each side
    for page in {page_of(n) for n in names_a & names_b}:
        shots_of = [n for n in names_a & names_b if page_of(n) == page]
        if any(said[(side, n)] is None for side in "ab" for n in shots_of):
            continue
        before = set().union(*(said[("a", n)][0] for n in shots_of))
        after = set().union(*(said[("b", n)][0] for n in shots_of))
        if any(said[(side, n)][1] for side in "ab" for n in shots_of):
            # A tip showed somewhere on this page in one of the runs: leave the words a tip can carry out of both
            # sides, or a label that happens to match a tip's text reads as new on the side without the tip.
            tipish = set().union(*(said[(side, n)][2] for side in "ab" for n in shots_of))
            before, after = before - tipish, after - tipish
        page_words[page] = (sorted(before - after), sorted(after - before))
    reported = set()
    for name in sorted(names_a | names_b):
        if name not in names_b:
            rows.append((name, "missing after", 1.0, ""))
            continue
        if name not in names_a:
            rows.append((name, "new", 1.0, ""))
            continue
        path_a, path_b = os.path.join(folder_a, name), os.path.join(folder_b, name)
        share, box = difference(path_a, path_b)
        note, kind = "", "same"
        gone, new = page_words.get(page_of(name), ([], []))
        if (gone or new) and page_of(name) not in reported:  # said once, on the page's first screenful
            reported.add(page_of(name))
            kind = "changed"
            note = "words: " + "; ".join([f"gone \"{w[:40]}\"" for w in gone[:2]] + [f"new \"{w[:40]}\"" for w in new[:2]])
            more = len(gone) + len(new) - min(2, len(gone)) - min(2, len(new))
            note += f" (+{more} more)" if more > 0 else ""
        tip_in_one = (said[("a", name)] is not None and said[("b", name)] is not None
                      and said[("a", name)][1] != said[("b", name)][1])
        if share > CHANGED_SHARE:
            fitted, slide = aligned_difference(path_a, path_b)
            if fitted > ALIGNED_SHARE and not tip_in_one:
                kind = "changed"
                note = (note + "; " if note else "") + f"look: {100 * fitted:.1f}% of the screen differs at the best fit"
                share = fitted
            elif kind == "same":
                kind = "scrolled"
                note = "a tip was showing in one run" if tip_in_one and fitted > ALIGNED_SHARE else f"same content, {abs(slide)} px apart"
        if kind == "changed":
            sheets.append(side_by_side(path_a, path_b, box if "look" in note else None, label_a, label_b,
                                       name[:-4], os.path.join(out, "changed", name)))
        rows.append((name, kind, share, note))
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
    count = {kind: sum(1 for r in rows if r[1] == kind) for kind in ("changed", "same", "scrolled", "new", "missing after")}
    lines = [f"{label_a} against {label_b}: {count['changed']} of {len(rows)} screens changed, "
             f"{count['same'] + count['scrolled']} the same ({count['scrolled']} of them scrolled to a different place), "
             f"{count['new']} new, {count['missing after']} missing after"]
    for name, kind, share, note in sorted(rows, key=lambda r: (r[1] != "changed", r[0])):
        if kind in ("changed", "new", "missing after"):
            lines.append(f"  {kind:<14} {name[:-4]:<44} {note}")
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
        for path in shots + glob.glob(os.path.join(SHOTS, "*.tree.txt")):
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
