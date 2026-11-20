#!/usr/bin/env python3
"""Paired run: answer quality before a change and after it, on the same questions, with the difference printed.

  python3 scripts/paired_run.py compare <runA> <runB>                 two run folders, question by question
  python3 scripts/paired_run.py compare <runA> <runB> --noise <runA2> [...]
                                                                      also: how many questions flip between runs
                                                                      of A's build (--noise-after for B's build,
                                                                      --same-build when A and B are one build)
  python3 scripts/paired_run.py stage <git-ref|worktree> <dir>        a patched scratch copy of a ref, or of the
                                                                      working tree, for OI_BENCH_PRESTAGED
  python3 scripts/paired_run.py pair --before <ref> --after <ref|worktree> [--mode standard] [--repeats 1]
                                     [--name <label>] [--test-from <ref>] [--dry-run]
                                                                      stage both, run both one after the other,
                                                                      compare, print the LEDGER.md lines

Why (Docs/ai/RETRO_5.8.md, gap 6): during 5.8, days of answer-quality work changed nothing that could be shown,
because no baseline was measured before the change. And two runs of the SAME build give different answers here (a
measured fact of this app), so "18 of 20 became 19 of 20" proves nothing until the run-to-run variation is known.

How: `scripts/bench_answer_modes.sh` runs the answer test per mode in the iOS 27 Simulator and writes
`BenchmarkRuns/<stamp>-answer-modes-<name>/`. `pair` stages each build as a scratch copy (`git archive <ref>`, or an
rsync of the working tree), patches it with `scripts/sim_model_copy.py`, and runs the bench script once per build and
repeat with OI_BENCH_PRESTAGED, OI_BENCH_NAME, OI_BENCH_SRC, OI_BENCH_DD and OI_BENCH_SIM, so each build has its own
name, source copy, build folder and simulator. Runs alternate (before, after, before, after) and never overlap.

Where right and wrong come from: the PASS/fail column of `<mode>-<model>.score.txt`, which
`scripts/score_answer_eval.py` writes from the whole answers inside the run's .xcresult. The judge column beside it
is not used (the model judge agreed with a plain reading on 8 of 20, 2026-11-13). When a run has no score rows (it
was stopped, or it predates the scorer), the answer lines of `<mode>-<model>.txt` are scored with the same rule.
Those lines hold only the first 300 characters of each answer, so a line is scored only when that settles the rule:
the whole answer is there (under 300 characters), or the cut answer already shows the value or the file name the
rule looks for. Measured 2026-11-20 on the 20 scored result files of 2026-11-14 to 2026-11-19: 312 of 400 answers
could be scored this way, and all 312 agreed with the score file; scoring the other 88 from their cut text would
have been wrong 32 times, so they are left unscored and named. A comparison over fewer questions than a run asked
is printed and gets no verdict.

The noise rule: with two or more runs of one build, count the questions whose right/wrong differs between each two
of them, and take the largest count. A net change (fixed minus broken) no larger than that is "within run-to-run
noise". With one run per build the tool says "noise not measured" and gives no verdict. `pair --before X --after X`
measures the noise of one build by itself; `--repeats 2` measures it on both sides of a change.

What it cannot tell you:
  - Whether an answer is good. "Right" is the rule's reading of 20 questions over the tiny research suite: a
    pattern matched, a file was named, a refusal was a refusal.
  - Anything about a phone. This is the Simulator with a patched copy; heat, memory, the Neural Engine and Private
    Cloud Compute stay with the device (the `device-pass` skill).
  - That a change is safe on other document sets. The owner's rule 6 asks for every benchmark set, and this is one.
  - That a change larger than the noise is caused by the code. Two or three runs are a small sample: the label says
    the difference is larger than what these runs showed between identical builds, and no more.
  - Speed. Minutes are in each run's SUMMARY.md and are comparable only on an idle Mac.
  - Whether an old ref builds. `stage` patches the four switches by content when the files have moved (v5.7.0 is
    from before the file split), and `--test-from` gives a ref from before 2026-11-11 an answer test that can choose
    a mode (the 2026-11-13 runs of v5.7.0 used 02044980's), but only the build shows whether that test compiles there.

Safety: never patches or builds in the repository (the stage folder must be outside it and outside ~/Documents); one
xcodebuild at a time (it stops if one is running, and removes OI_BENCH_ALLOW_PARALLEL from the bench's environment);
a disk check before staging; a time limit on every run; it never writes inside an existing run folder and never
edits BenchmarkRuns/LEDGER.md: it prints the lines to add. `--dry-run` prints every command and runs none.
"""
import argparse, datetime, json, os, re, shlex, shutil, signal, subprocess, sys, textwrap

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RUNS = os.path.join(ROOT, "BenchmarkRuns")
BENCH = os.path.join(HERE, "bench_answer_modes.sh")
PATCH = os.path.join(HERE, "sim_model_copy.py")
MANIFEST = os.path.join(ROOT, "Benchmarks", "ResearchFixtures", "tiny_research_suite", "manifest.json")
ANSWER_TEST = "OpenIntelligenceTests/Services/Evaluation/AnswerQualityEvaluationTests.swift"
MODE_SWITCH = "OI_EVAL_MODE"  # the answer test reads it since d8a5cead (2026-11-11); v5.7.0's test does not
MARKER = "SIM_MODEL_COPY"  # bench_answer_modes.sh refuses a prestaged copy without it; sim_model_copy.py writes it
STAGING = ".paired_run_stage"  # written first, so a stage that stopped half way is still known as this script's own
# Left out of a copy of the working tree. `.env*` holds release secrets a test build has no use for (git ignores
# it, so a `git archive` copy never has it either).
EXCLUDES = [".git", ".git.nosync", ".build", "BenchmarkRuns", ".claude/worktrees", ".env*"]
SCRATCH = "/private/tmp/oi-pair"
MODES = ("standard", "deepThink", "maximum")
# One pair holds two stages and two source copies (305 MB each) and two build folders (1.2 GB each), measured on
# /private/tmp/oi-life-src and oi-life-dd, 2026-11-20: about 4 GiB. The bench script itself stops under 15.
MIN_FREE_GIB = 20
LIMIT_HOURS = 6  # per bench run; Maximum took 74 minutes at its longest (2026-11-18) and a first build is extra
PRINTED = 300  # characters of each answer the test prints (`answer.text.prefix(300)`)
PREFIX_NOTE = "from the answer lines of the .txt (300 characters of each answer)"
# Cases whose rule passes on evidence that is present (a value, a file name): once it is in the printed part, the
# rest of the answer cannot take it away. An abstain case can still state a made-up amount later, and a
# lost-in-the-middle case another case's token, so a cut answer of those kinds is never scored.
SETTLED_WHEN_FOUND = ("exact_value", "multi_hop", "retrieval_only")
# The four switches of sim_model_copy.py, by content, for a ref whose files are laid out differently (v5.7.0 holds
# two of them in RAGService.swift). test_paired_run.py fails if these stop matching that script.
SWITCH_MARKERS = [
    "// Foundation Models + PCC are not available inside the simulator runtime",
    "// Simulator: Foundation Models not available",
    "return .simulatorUnsupported",
]
CHIP_OLD = "return .a14Bionic  // Don't claim Apple Intelligence support in simulator"
CHIP_NEW = "return .a18Pro  // Model copy (scripts/sim_model_copy.py): the chip of the owner's iPhone 16 Pro Max"
SIM_IF = "#if targetEnvironment(simulator)"
SIM_OFF = "#if targetEnvironment(simulator) && OI_SIM_MODEL_COPY_KEEP_SWITCH"


# ---------------------------------------------------------------- reading a run folder: pure functions of its text

SCORE_ROW = re.compile(r"^\s+(PASS|fail) judge=(?:pass|fail)\s+(\S+)\s+\d+ chars")
SCORE_TOTAL = re.compile(r"^\s+rule (\d+)/(\d+)\s")
ANSWER_LINE = re.compile(r"\] (answered|refused) mode=\S+ seconds=\d+ question=(.*?) (?:answer|error)=(.*)$")
RESULT_FILE = re.compile(r"^([A-Za-z]+-[A-Za-z]+)(\.score\.txt|\.txt|\.log)$")


def parse_score(text):
    """The rows of a `.score.txt`: ({question id: right by rule}, [what did not add up]).

    The scorer prints one `== <file>` section per evaluation report; the last section with rows is the one the bench
    script's own summary uses (`tail -1`), so it is the one read here.
    """
    sections = []
    for line in text.splitlines():
        if line.startswith("== ") or not sections:
            sections.append({"rows": [], "total": None})
        row, total = SCORE_ROW.match(line), SCORE_TOTAL.match(line)
        if row:
            sections[-1]["rows"].append((row.group(2), row.group(1) == "PASS"))
        elif total:
            sections[-1]["total"] = (int(total.group(1)), int(total.group(2)))
    scored = [s for s in sections if s["rows"]]
    if not scored:
        return {}, []
    problems = [f"{len(scored)} scored sections in the file; the last one is read"] if len(scored) > 1 else []
    rows, total = scored[-1]["rows"], scored[-1]["total"]
    results = {}
    for number, (name, right) in enumerate(rows, 1):
        if name == "?":
            name = f"?row{number}"  # the scorer found no case for this question
        while name in results:
            name += "#2"
        results[name] = right
    counted = (sum(results.values()), len(results))
    if total is None:
        problems.append("no 'rule N/M' line: the scorer did not finish")
    elif total != counted:
        problems.append(f"the 'rule {total[0]}/{total[1]}' line disagrees with the rows ({counted[0]} of {counted[1]})")
    return results, problems


def parse_answer_lines(text):
    """The answered and refused lines of a `<mode>-<model>.txt`, in order: [(question, answer or None if refused)]."""
    found = []
    for line in text.splitlines():
        m = ANSWER_LINE.search(line)
        if m:
            found.append((m.group(2), m.group(3) if m.group(1) == "answered" else None))
    return found


def score_prefixes(lines, cases, rule):
    """Right or wrong for answer lines by the scorer's rule, where the printed part of the answer settles it.

    Returns ({question id: right}, [ids left unscored]). The test prints the first 80 characters of the question,
    and three cases share one question, so the nth line with a question is the nth case with it (the test asks in
    the manifest's order). A refusal is wrong. A printed answer under 300 characters is the whole answer. A cut one
    is scored only when the rule already passes on a case of SETTLED_WHEN_FOUND; otherwise it is left unscored. A
    question that is not in the manifest is unscored under its first words.
    """
    results, unscored, seen = {}, [], {}
    for question, answer in lines:
        same = [c for c in cases if c["query"][:80] == question]
        nth = seen.get(question, 0)
        seen[question] = nth + 1
        if nth >= len(same):
            unscored.append("? " + " ".join(question.split()[:6]))
            continue
        case = same[nth]
        right = answer is not None and bool(rule(case, answer, cases))
        cut = answer is not None and len(answer) >= PRINTED
        settled = right and case.get("expected_behavior") != "abstain" and case.get("category") in SETTLED_WHEN_FOUND
        if cut and not settled:
            unscored.append(case["id"])
        else:
            results[case["id"]] = right
    return results, unscored


def scorer():
    """(the rule of scripts/score_answer_eval.py, the cases of its manifest), or None when they cannot be loaded."""
    try:
        sys.path.insert(0, HERE)
        import score_answer_eval
        with open(MANIFEST, encoding="utf-8") as f:
            return score_answer_eval.rule, json.load(f)["cases"]
    except Exception:
        return None


def questions():
    """{question id: its text} from the manifest, for printing beside an id. Empty when the manifest is not there."""
    try:
        with open(MANIFEST, encoding="utf-8") as f:
            return {c["id"]: c["query"] for c in json.load(f)["cases"]}
    except Exception:
        return {}


def summary_results(text):
    """{`<mode>-<model>`: the Result cell} from a run's SUMMARY.md table ("passed", "failed (exit 143)")."""
    out = {}
    for line in text.splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if line.startswith("|") and len(cells) >= 3 and cells[0] in MODES:
            out[f"{cells[0]}-{cells[1]}"] = cells[-1]
    return out


def read_text(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def read_run(folder, prefix_scorer=None):
    """One run folder: {"name", "folder", "modes": {`<mode>-<model>`: {"source", "results", "problems"}}}.

    "source" is "score" (the score file's rows), "prefix" (answer lines scored on their first 300 characters, when
    there are no score rows) or None (nothing to read). `prefix_scorer` is (rule, cases); None loads the scorer.
    """
    folder = os.path.abspath(folder)
    names = sorted(os.listdir(folder))
    summary = summary_results(read_text(os.path.join(folder, "SUMMARY.md")) or "")
    keys = sorted({m.group(1) for m in map(RESULT_FILE.match, names) if m})
    modes = {}
    for key in keys:
        score_text = read_text(os.path.join(folder, key + ".score.txt"))
        results, problems = parse_score(score_text or "")
        source = "score" if results else None
        if not results:
            why = ("no score file" if score_text is None else "the score file is empty" if not score_text.strip()
                   else "the score file has no rows")
            lines = parse_answer_lines(read_text(os.path.join(folder, key + ".txt")) or "")
            loaded = prefix_scorer or (scorer() if lines else None)
            if lines and loaded:
                results, unscored = score_prefixes(lines, loaded[1], loaded[0])
                source = "prefix" if results else None
                problems = [f"{why}; {len(results)} of {len(lines)} answers scored {PREFIX_NOTE}"]
                if unscored:
                    problems.append(f"{len(unscored)} answers cut at {PRINTED} characters, where the printed part does "
                                    f"not settle the rule, are left unscored: {', '.join(unscored)}")
            else:
                problems = [f"{why}, and " + ("the scorer's manifest could not be loaded" if lines else "no answer lines")]
        if summary.get(key, "passed") != "passed":
            problems.append(f"SUMMARY.md says this mode {summary[key]}")
        modes[key] = {"source": source, "results": results, "problems": problems}
    return {"name": os.path.basename(folder), "folder": folder, "modes": modes}


# ---------------------------------------------------------------- comparing: pure functions of the results

def pct(right, total):
    """"88% (15 of 17)": the percentage first, the count beside it; halves round up."""
    if not total:
        return "none scored"
    return f"{(200 * right + total) // (2 * total)}% ({right} of {total})"


def tally(results):
    return sum(1 for right in results.values() if right), len(results)


def flips(before, after):
    """(questions both runs scored, those that went wrong to right, those that went right to wrong)."""
    common = [q for q in before if q in after]
    fixed = [q for q in common if not before[q] and after[q]]
    broken = [q for q in common if before[q] and not after[q]]
    return common, fixed, broken


def noise_between(groups):
    """How many questions flip between runs of one build.

    `groups` holds, per build, the results of each of its runs. Every two runs of one build are compared on the
    questions both scored; "flips" is the largest count of differing questions in any such pair. None when no build
    has two runs.
    """
    most, pairs, unstable = 0, 0, []
    for runs in groups:
        for i in range(len(runs)):
            for j in range(i + 1, len(runs)):
                differ = [q for q in runs[i] if q in runs[j] and runs[i][q] != runs[j][q]]
                pairs += 1
                most = max(most, len(differ))
                unstable += [q for q in differ if q not in unstable]
    return {"flips": most, "pairs": pairs, "unstable": unstable} if pairs else None


def reading(net, noise, no_verdict=""):
    """What a net change of `net` questions is, against the noise measured (or not)."""
    if no_verdict:
        return "no verdict: " + no_verdict
    if noise is None:
        return "no net change; noise not measured" if net == 0 else "noise not measured"
    return "within run-to-run noise" if abs(net) <= noise["flips"] else "larger than run-to-run noise"


def net_text(net, total):
    """"+5 points (+1 question of 20)"."""
    if not total:
        return "nothing to compare"
    points = (200 * abs(net) + total) // (2 * total)
    sign = "+" if net > 0 else "-" if net < 0 else ""
    return f"{sign}{points} points ({sign}{abs(net)} question{'' if abs(net) == 1 else 's'} of {total})"


def compare_runs(before, after, more_before=(), more_after=(), same_build=False):
    """Every mode both runs hold, compared. `more_before` and `more_after` are further runs of the same builds."""
    out = {"before": before["name"], "after": after["name"], "more_before": [r["name"] for r in more_before],
           "more_after": [r["name"] for r in more_after], "same_build": same_build, "modes": [], "skipped": []}
    for key in sorted(set(before["modes"]) | set(after["modes"])):
        a, b = before["modes"].get(key), after["modes"].get(key)
        if not a or not b or not a["results"] or not b["results"]:
            missing = [run["name"] for run, m in ((before, a), (after, b)) if not m or not m["results"]]
            out["skipped"].append(f"{key}: nothing scored in {' or '.join(missing)}")
            continue
        common, fixed, broken = flips(a["results"], b["results"])

        def full(run):  # only whole-answer scores measure noise
            m = run["modes"].get(key)
            return [m["results"]] if m and m["source"] == "score" else []
        befores = full(before) + [r for run in more_before for r in full(run)]
        afters = full(after) + [r for run in more_after for r in full(run)]
        noise = noise_between([befores + afters] if same_build else [befores, afters])
        asked = max(len(a["results"]), len(b["results"]))
        no_verdict = f"only {len(common)} of {asked} questions were scored in both runs" if len(common) < asked else ""
        net = len(fixed) - len(broken)
        out["modes"].append({
            "mode": key, "before": tally(a["results"]), "after": tally(b["results"]),
            "sources": (a["source"], b["source"]), "common": len(common),
            "before_common": tally({q: a["results"][q] for q in common}),
            "after_common": tally({q: b["results"][q] for q in common}),
            "fixed": fixed, "broken": broken, "net": net, "noise": noise,
            "reading": reading(net, noise, no_verdict),
            "others": [(side, run["name"], tally(run["modes"][key]["results"]), run["modes"][key]["source"])
                       for side, runs in (("before", more_before), ("after", more_after)) for run in runs
                       if key in run["modes"] and run["modes"][key]["results"]],
            "problems": [f"{run['name']}: {p}" for run, m in ((before, a), (after, b)) for p in m["problems"]]})
    return out


def mode_label(key):
    mode, _, model = key.partition("-")
    return f"{mode} ({model} model)"


def table(result):
    """The comparison as a Markdown table: the same text for the terminal and for LEDGER.md."""
    lines = ["| Mode | Before | After | Fixed | Broken | Net | Reading |", "|---|---|---|---|---|---|---|"]
    for m in result["modes"]:
        fixed = ", ".join(m["fixed"]) or "none"
        broken = ", ".join(m["broken"]) or "none"
        lines.append(f"| {mode_label(m['mode'])} | {pct(*m['before'])} | {pct(*m['after'])} | {len(m['fixed'])}: {fixed} "
                     f"| {len(m['broken'])}: {broken} | {net_text(m['net'], m['common'])} | {m['reading']} |")
    return "\n".join(lines)


def describe(result, texts=None):
    """The whole comparison as text. `texts` maps a question id to its words, printed beside the id."""
    texts = texts or {}
    out = ["Paired comparison of answers. Right and wrong are the rule's (the PASS/fail column of",
           "<mode>-<model>.score.txt, written by scripts/score_answer_eval.py from the whole answers).", "",
           f"  before  {result['before']}", f"  after   {result['after']}"]
    out += [f"  also    {name} (the before build again)" for name in result["more_before"]]
    out += [f"  also    {name} (the after build again)" for name in result["more_after"]]
    if result["same_build"]:
        out.append("  Before and after are one build: every flip below is run-to-run noise.")
    if not result["modes"]:
        return "\n".join(out + ["", "No mode was scored in both runs."] + ["  " + s for s in result["skipped"]])
    out += ["", table(result)]
    for m in result["modes"]:
        unstable = m["noise"]["unstable"] if m["noise"] else []

        def listed(names):
            width = max(len(n) for n in names)
            return [f"    {n.ljust(width)}  {texts.get(n, '')}".rstrip()
                    + ("  (also flips between runs of one build)" if n in unstable else "") for n in names]
        out += ["", mode_label(m["mode"]),
                f"  before  {pct(*m['before'])}" + ("" if m["sources"][0] == "score" else f"  scored {PREFIX_NOTE}"),
                f"  after   {pct(*m['after'])}" + ("" if m["sources"][1] == "score" else f"  scored {PREFIX_NOTE}")]
        out += [f"  {side.ljust(6)}  {pct(*count)}  {name}" + ("" if source == "score" else f"  scored {PREFIX_NOTE}")
                for side, name, count, source in m["others"]]
        if m["common"] < max(m["before"][1], m["after"][1]):
            out.append(f"  on the {m['common']} questions both runs scored: before {pct(*m['before_common'])}, "
                       f"after {pct(*m['after_common'])}")
        out.append(f"  fixed, wrong to right: {len(m['fixed'])}")
        out += listed(m["fixed"]) if m["fixed"] else []
        out.append(f"  broken, right to wrong: {len(m['broken'])}")
        out += listed(m["broken"]) if m["broken"] else []
        out.append(f"  net change: {net_text(m['net'], m['common'])}")
        if m["noise"]:
            n = m["noise"]
            out.append(f"  noise: at most {n['flips']} of {m['common']} questions flipped between two runs of one build "
                       f"({n['pairs']} pair{'' if n['pairs'] == 1 else 's'} of runs compared)"
                       + (": " + ", ".join(n["unstable"]) if n["unstable"] else ""))
            out.append(f"  answers that changed between before and after: {len(m['fixed']) + len(m['broken'])}")
        else:
            out.append("  noise: not measured. One run of each build cannot tell a change from the variation between")
            out.append("         two runs of one build. Give --noise <another run of the before build>.")
        out.append(f"  reading: {m['reading']}")
        out += [f"  note: {p}" for p in m["problems"]]
    if result["skipped"]:
        out += ["", "Not compared:"] + ["  " + s for s in result["skipped"]]
    return "\n".join(out)


def ledger_lines(date, label, sides, modes, repeats, folders, result_table):
    """The entry to add to BenchmarkRuns/LEDGER.md, in that file's form. `sides` is [(side, what was built)]."""
    names = ", ".join(f"`{name}`" for name in folders) or "no run folder was made"
    built = "; ".join(f"{side} is {what}" for side, what in sides)
    same_build = len({what for _, what in sides}) == 1 and len(sides) > 1
    if same_build:  # before and after are one commit: the run is the noise measurement itself
        runs = f"{repeats * len(sides)} runs of one build, so every flip is run-to-run noise"
        confidence = f"low: {repeats * len(sides)} runs of one build, one question set"
    else:
        runs = "one run of each build, so run-to-run noise was not measured" if repeats == 1 else \
            f"{repeats} runs of each build, alternating"
        confidence = "low: one run per build" if repeats == 1 else f"medium: {repeats} runs per build, one question set"
    how = (f"`scripts/paired_run.py pair`: {built}. Modes: {', '.join(modes)}; {runs}. Each build is a scratch copy "
           "with the Simulator switches of `scripts/sim_model_copy.py` turned off, its own build folder and its own "
           "simulator (iOS 27.0, iPhone 17 Pro), run one after the other. Right and wrong by rule "
           "(`scripts/score_answer_eval.py`), the questions of the tiny research suite.")
    return "\n".join([
        f"### {date} Paired answer run \"{label}\" ({names})", "",
        textwrap.fill(how, width=118, break_long_words=False, break_on_hyphens=False),
        f"`[evidence_level: measured, confidence: {confidence}]`", "",
        result_table or "(no comparison table: no mode was scored in both runs; see each folder's SUMMARY.md)", "",
        "Read: (one or two sentences in your words: what this shows, and what it does not)"])


# ---------------------------------------------------------------- staging: a patched scratch copy of one build

def source_kind(source):
    """("tree", folder) for the word "worktree" or a folder given as a path; ("ref", name) for anything else."""
    if source == "worktree":
        return "tree", ROOT
    expanded = os.path.expanduser(source)
    if os.sep in source and os.path.isdir(expanded):
        return "tree", os.path.abspath(expanded)
    return "ref", source


def stage_dir_problem(dest, root=ROOT, home=None):
    """Why `dest` may not hold a patched copy, or "" when it may. Reads the folder, changes nothing."""
    home = os.path.realpath(home or os.path.expanduser("~"))
    dest, root = os.path.realpath(dest), os.path.realpath(root)
    inside = lambda child, parent: child == parent or child.startswith(parent.rstrip(os.sep) + os.sep)
    if inside(dest, root) or inside(root, dest):
        return f"{dest}: a patched copy never goes inside the repository, or around it"
    if inside(home, dest):
        return f"{dest}: not a scratch folder"
    if inside(dest, os.path.join(home, "Documents")):
        return f"{dest}: ~/Documents is iCloud-synced; builds and their sources stay outside it"
    if os.path.isdir(dest) and os.listdir(dest) and not any(os.path.exists(os.path.join(dest, m)) for m in (MARKER, STAGING)):
        return f"{dest}: holds something that is not an earlier copy of this script's (no {MARKER} file); give an empty folder"
    if os.path.exists(dest) and not os.path.isdir(dest):
        return f"{dest}: is a file"
    return ""


class Shell:
    """Prints each command, and runs it unless this is a dry run."""

    def __init__(self, dry):
        self.dry = dry

    def note(self, text):
        print(f"# {text}", flush=True)

    def show(self, line):
        print(f"$ {line}", flush=True)

    def run(self, *argv, timeout=600, shown=None):
        """A CompletedProcess, or None in a dry run."""
        self.show(shown or " ".join(shlex.quote(a) for a in argv))
        if self.dry:
            return None
        return subprocess.run(argv, capture_output=True, text=True, timeout=timeout)

    def must(self, *argv, timeout=600, why=""):
        r = self.run(*argv, timeout=timeout)
        if r is not None and r.returncode != 0:
            sys.exit(f"{why or argv[0]} failed: {(r.stderr or r.stdout).strip()[-500:]}")
        return r.stdout if r is not None else ""


def patch_by_content(stage):
    """The four switches of sim_model_copy.py, found by content in any Swift file under OpenIntelligence/.

    For a ref whose files are laid out differently from HEAD's. Each switch must be found exactly once, patched or
    not, so a copy sim_model_copy.py left half patched is finished and nothing is patched twice. Returns the files
    changed; stops with the switch's name when one is not found exactly once.
    """
    files = {}
    for folder, _, names in os.walk(os.path.join(stage, "OpenIntelligence")):
        for name in names:
            if name.endswith(".swift"):
                path = os.path.join(folder, name)
                text = read_text(path)
                if text and "targetEnvironment(simulator)" in text:
                    files[path] = text.split("\n")
    changed = set()
    for marker in SWITCH_MARKERS:
        hits = [(path, i, lines[i].strip() == SIM_OFF) for path, lines in files.items() for i in range(len(lines) - 1)
                if lines[i].strip() in (SIM_IF, SIM_OFF) and lines[i + 1].strip().startswith(marker)]
        if len(hits) != 1:
            sys.exit(f"the Simulator switch before {marker!r} was found {len(hits)} times in {stage}, not once")
        path, i, done = hits[0]
        if not done:
            files[path][i] = files[path][i].replace(SIM_IF, SIM_OFF)
            changed.add(path)
    old = [(path, i) for path, lines in files.items() for i, line in enumerate(lines) if CHIP_OLD in line]
    new = [(path, i) for path, lines in files.items() for i, line in enumerate(lines) if CHIP_NEW in line]
    if len(old) + len(new) != 1:
        sys.exit(f"the Simulator's chip line was found {len(old) + len(new)} times in {stage}, not once")
    for path, i in old:
        files[path][i] = files[path][i].replace(CHIP_OLD, CHIP_NEW)
        changed.add(path)
    for path in sorted(changed):
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(files[path]))
    with open(os.path.join(stage, MARKER), "w", encoding="utf-8") as f:
        f.write("Patched by scripts/paired_run.py (the switches of sim_model_copy.py, by content): never commit from this folder.\n")
    return sorted(os.path.relpath(path, stage) for path in changed)


def mark_staging(dest):
    os.makedirs(dest, exist_ok=True)
    with open(os.path.join(dest, STAGING), "w", encoding="utf-8") as f:
        f.write("A scratch copy made by scripts/paired_run.py: never commit from this folder.\n")


def extract_ref(ref, dest):
    """`git archive <ref> | tar -x -C <dest>`: the files of a ref, with no checkout and nothing written to the repository."""
    archive = subprocess.Popen(["git", "-C", ROOT, "archive", ref], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    tar = subprocess.run(["tar", "-x", "-C", dest], stdin=archive.stdout, capture_output=True, timeout=1800)
    archive.stdout.close()
    error = archive.stderr.read().decode("utf-8", "replace")
    archive.stderr.close()
    if archive.wait(timeout=60) != 0 or tar.returncode != 0:
        sys.exit(f"git archive {ref} failed: {(error or tar.stderr.decode('utf-8', 'replace')).strip()[-400:]}")


def ref_file(ref, path):
    """The text of one file at a ref (`git show <ref>:<path>`), or "" when it is not there."""
    r = subprocess.run(["git", "-C", ROOT, "show", f"{ref}:{path}"], capture_output=True, text=True, timeout=120)
    return r.stdout if r.returncode == 0 else ""


def stage(source, dest, shell, test_from=None):
    """Make `dest` a patched copy of `source` (a git ref, "worktree", or a folder). Returns what was staged."""
    dest = os.path.abspath(os.path.expanduser(dest))
    problem = stage_dir_problem(dest)
    if problem:
        sys.exit("Refusing: " + problem)
    kind, what = source_kind(source)
    if kind == "ref":
        if os.path.isdir(dest) and os.listdir(dest):
            shell.show(f"rm -rf {shlex.quote(dest)}    # an earlier copy made by this script")
            if not shell.dry:
                shutil.rmtree(dest)
        shell.show(f"mkdir -p {shlex.quote(dest)}")
        shell.show(f"git -C {shlex.quote(ROOT)} archive {shlex.quote(what)} | tar -x -C {shlex.quote(dest)}")
        if not shell.dry:
            mark_staging(dest)
            extract_ref(what, dest)
    else:
        shell.show(f"mkdir -p {shlex.quote(dest)}")
        if not shell.dry:
            mark_staging(dest)
        excludes = [part for name in EXCLUDES + [STAGING] for part in ("--exclude", name)]
        shell.must("rsync", "-a", "--delete", *excludes, what + "/", dest + "/", timeout=1800, why="rsync to the stage")
    test_path = os.path.join(dest, ANSWER_TEST)
    if test_from:
        shell.note(f"only when the staged answer test cannot choose a mode (no {MODE_SWITCH} in it): the test of {test_from}")
        shell.show(f"git -C {shlex.quote(ROOT)} show {shlex.quote(test_from + ':' + ANSWER_TEST)} > {shlex.quote(test_path)}")
    else:
        shell.note(f"stops here when the staged answer test cannot choose a mode (no {MODE_SWITCH}: refs before "
                   "2026-11-11, v5.7.0 among them); --test-from <ref> gives such a copy a newer answer test")
    overlaid = False
    if not shell.dry and MODE_SWITCH not in (read_text(test_path) or ""):
        if not test_from:
            sys.exit(f"{source}: its answer test does not read {MODE_SWITCH}, so every mode would run the same test. "
                     "Pass --test-from <ref> to use a newer answer test (the 2026-11-13 runs of v5.7.0 used 02044980's).")
        newer = ref_file(test_from, ANSWER_TEST)
        if MODE_SWITCH not in newer:
            sys.exit(f"--test-from {test_from}: no answer test with {MODE_SWITCH} there.")
        os.makedirs(os.path.dirname(test_path), exist_ok=True)
        with open(test_path, "w", encoding="utf-8") as f:
            f.write(newer)
        overlaid = True
    r = shell.run(sys.executable, PATCH, dest, timeout=300)
    patched_by = "scripts/sim_model_copy.py"
    if shell.dry:
        shell.note("when sim_model_copy.py does not fit the copy (an older layout of the files): its four switches, by content")
    if r is not None and r.returncode != 0:
        said = ((r.stderr or r.stdout).strip().splitlines() or ["no output"])[-1][:200]
        shell.note(f"sim_model_copy.py did not fit this copy ({said}); patching by content")
        changed = patch_by_content(dest)
        patched_by = "the switches of scripts/sim_model_copy.py, found by content"
        shell.note("patched by content: " + (", ".join(changed) or "nothing left to change"))
    if not shell.dry and not os.path.exists(os.path.join(dest, MARKER)):
        sys.exit(f"{dest}: no {MARKER} file after patching; bench_answer_modes.sh would refuse this copy")
    return {"source": source, "kind": kind, "dest": dest, "patched_by": patched_by,
            "test_from": test_from if overlaid else None}


def built_from(source, shell):
    """Words for the ledger: which commit a source is, read with git. Stops on a ref git does not know."""
    kind, what = source_kind(source)
    if kind == "ref":
        commit = shell.must("git", "-C", ROOT, "rev-parse", "--short", what + "^{commit}", timeout=120,
                            why=f"git rev-parse {what}").strip()
        return f"`{what}` ({commit or 'commit read at run time'})"
    commit = shell.run("git", "-C", what, "rev-parse", "--short", "HEAD", timeout=120)
    dirty = shell.run("git", "-C", what, "status", "--porcelain", timeout=120)
    tree = "the working tree" if what == ROOT else f"the working tree of {what}"
    if commit is None or dirty is None:
        return f"{tree} (commit and uncommitted changes read at run time)"
    if commit.returncode != 0:
        return f"the folder {what} (not a git checkout)"
    extra = " with uncommitted changes, so this build cannot be made again from git" if dirty.stdout.strip() else ""
    return f"{tree} at {commit.stdout.strip()}{extra}"


# ---------------------------------------------------------------- pair: stage both, run both, compare

def run_names(label, repeats):
    """[(side, OI_BENCH_NAME)] in the order run: before, after, before, after."""
    return [(side, f"{label}-{side}" + (f"-r{n}" if repeats > 1 else ""))
            for n in range(1, repeats + 1) for side in ("before", "after")]


def bench_env(side, name, scratch):
    return {"OI_BENCH_PRESTAGED": os.path.join(scratch, f"{side}-stage"), "OI_BENCH_NAME": name,
            "OI_BENCH_SRC": os.path.join(scratch, f"{side}-src"), "OI_BENCH_DD": os.path.join(scratch, f"{side}-dd"),
            "OI_BENCH_SIM": f"OI pair {side}"}


def run_folders(name):
    """The run folders the bench script has made for this name."""
    if not os.path.isdir(RUNS):
        return set()
    return {f for f in os.listdir(RUNS) if f.endswith(f"-answer-modes-{name}")}


def run_bench(env, modes, shell, limit_hours):
    """One bench run, in front, with a time limit. Returns its exit code (None in a dry run)."""
    shown = " ".join(f"{k}={shlex.quote(v)}" for k, v in env.items())
    shell.show(f"{shown} bash {shlex.quote(BENCH)} {' '.join(modes)}")
    if shell.dry:
        return None
    full = dict(os.environ, **env)
    full.pop("OI_BENCH_ALLOW_PARALLEL", None)  # never beside another xcodebuild
    process = subprocess.Popen(["bash", BENCH, *modes], env=full, start_new_session=True)
    try:
        return process.wait(timeout=limit_hours * 3600)
    except (subprocess.TimeoutExpired, KeyboardInterrupt) as stop:
        # Only the process group this run started (the bench script, its xcodebuild, its caffeinate): nothing else.
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=120)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
        print(f"Stopped the run. Its simulator \"{env['OI_BENCH_SIM']}\" may still be booted: xcrun simctl list devices")
        if isinstance(stop, KeyboardInterrupt):
            raise
        print(f"The run passed its limit of {limit_hours} hours (--limit-hours).")
        return 124


def pair(a):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", a.name):
        sys.exit("--name: letters, digits, dot, dash and underscore only (it becomes part of a folder name)")
    modes = [m for part in a.mode for m in part.split(",") if m]
    for m in modes:
        if not re.fullmatch(f"({'|'.join(MODES)})(:(app|test))?", m):
            sys.exit(f"--mode {m}: one of {', '.join(MODES)}, optionally with :app or :test")
    if a.repeats < 1:
        sys.exit("--repeats: at least 1")
    scratch = os.path.abspath(os.path.expanduser(a.scratch))
    shell = Shell(a.dry_run)
    names = run_names(a.name, a.repeats)
    print(f"Paired run \"{a.name}\": before {a.before}, after {a.after}; modes {', '.join(modes)}; "
          f"{a.repeats} run{'' if a.repeats == 1 else 's'} of each build, one after the other."
          + (" DRY RUN: no command below is run." if a.dry_run else ""), flush=True)

    shell.note("1. Both sources, and the Mac, before anything is staged")
    sides = [("before", built_from(a.before, shell)), ("after", built_from(a.after, shell))]
    busy = shell.run("pgrep", "-x", "xcodebuild", timeout=30)
    if busy is not None and busy.stdout.strip():
        sys.exit("Another xcodebuild is running; one at a time on this Mac. Nothing was staged.")
    free = shutil.disk_usage("/System/Volumes/Data" if os.path.isdir("/System/Volumes/Data") else "/").free / 2 ** 30
    shell.note(f"{free:.0f} GiB free on the internal disk; a pair needs {MIN_FREE_GIB} (two source copies and two build folders)")
    if not a.dry_run and free < MIN_FREE_GIB:
        sys.exit(f"{free:.1f} GiB free, under {MIN_FREE_GIB}: not staging (~/.agents/STORAGE.md).")
    # One build on both sides (a noise measurement): both are git refs and git names one commit for them.
    both_refs = source_kind(a.before)[0] == "ref" and source_kind(a.after)[0] == "ref"
    same_build = both_refs and (a.before == a.after if a.dry_run else sides[0][1].split()[-1] == sides[1][1].split()[-1])

    for number, (side, source) in enumerate((("before", a.before), ("after", a.after)), 2):
        shell.note(f"{number}. Stage {side}: {source}")
        staged = stage(source, os.path.join(scratch, f"{side}-stage"), shell, a.test_from)
        if staged["test_from"]:
            sides[number - 2] = (side, sides[number - 2][1] + f", with the answer test of `{staged['test_from']}`")
        if staged["patched_by"] != "scripts/sim_model_copy.py":
            sides[number - 2] = (side, sides[number - 2][1] + ", its four Simulator switches patched by content")

    shell.note("4. Run: one build at a time, each with its own name, source copy, build folder and simulator")
    made = {"before": [], "after": []}
    failed = ""
    for side, name in names:
        known = run_folders(name)
        code = run_bench(bench_env(side, name, scratch), modes, shell, a.limit_hours)
        if a.dry_run:
            made[side].append(f"<stamp>-answer-modes-{name}")
            continue
        new = sorted(run_folders(name) - known)
        made[side] += new[-1:]
        if code != 0 or not new:
            failed = f"The {side} run \"{name}\" ended with exit {code}" + ("" if new else " and made no run folder") + "."
            break

    shell.note("5. Compare")
    folders = [f for pair_of in zip(made["before"], made["after"]) for f in pair_of]
    folders += [f for f in made["before"] + made["after"] if f not in folders]
    result_table = ""
    if a.dry_run:
        shell.show(compare_command(made, same_build))
        result_table = "(the comparison table goes here)"
    elif made["before"] and made["after"]:
        print(compare_command(made, same_build), flush=True)
        runs = {side: [read_run(os.path.join(RUNS, f)) for f in made[side]] for side in made}
        result = compare_runs(runs["before"][0], runs["after"][0], runs["before"][1:], runs["after"][1:], same_build)
        print("\n" + describe(result, questions()), flush=True)
        result_table = table(result) if result["modes"] else ""
    if failed:
        print("\n" + failed + " The pair is incomplete.")

    shell.note("6. Lines for BenchmarkRuns/LEDGER.md (this script does not edit that file; add them by hand)")
    print()
    print(ledger_lines(datetime.date.today().isoformat(), a.name, sides, modes, a.repeats, folders, result_table))
    return 1 if failed else 0


def compare_command(made, same_build):
    """The compare call that gives this pair's comparison again."""
    line = f"python3 scripts/paired_run.py compare BenchmarkRuns/{made['before'][0]} BenchmarkRuns/{made['after'][0]}"
    if made["before"][1:]:
        line += " --noise " + " ".join("BenchmarkRuns/" + f for f in made["before"][1:])
    if made["after"][1:]:
        line += " --noise-after " + " ".join("BenchmarkRuns/" + f for f in made["after"][1:])
    return line + (" --same-build" if same_build else "")


# ---------------------------------------------------------------- command line

def resolve_run(path):
    """A run folder given as a path, or as its name under BenchmarkRuns/."""
    for candidate in (os.path.expanduser(path), os.path.join(RUNS, path)):
        if os.path.isdir(candidate):
            return candidate
    sys.exit(f"{path}: no such run folder (looked here and under BenchmarkRuns/)")


def main(argv=None):
    p = argparse.ArgumentParser(description="Answer quality before and after a change, on the same questions.",
                                epilog="The docstring at the top of this file says why, how, and what it cannot tell you.")
    sub = p.add_subparsers(dest="command", required=True)
    c = sub.add_parser("compare", help="two run folders, question by question")
    c.add_argument("before", help="a run folder, or its name under BenchmarkRuns/")
    c.add_argument("after")
    c.add_argument("--noise", nargs="+", default=[], metavar="RUN", help="more runs of the before build")
    c.add_argument("--noise-after", nargs="+", default=[], metavar="RUN", help="more runs of the after build")
    c.add_argument("--same-build", action="store_true", help="before and after are one build: every flip is noise")
    s = sub.add_parser("stage", help="a patched scratch copy of a git ref, or of the working tree")
    s.add_argument("source", help='a git ref, the word "worktree", or a folder given as a path')
    s.add_argument("dir", help="an empty folder outside the repository and outside ~/Documents")
    s.add_argument("--test-from", metavar="REF", help=f"use this ref's answer test when the source's has no {MODE_SWITCH}")
    s.add_argument("--dry-run", action="store_true")
    r = sub.add_parser("pair", help="stage both builds, run both, compare")
    r.add_argument("--before", required=True, help="a git ref")
    r.add_argument("--after", required=True, help='a git ref, the word "worktree", or a folder given as a path')
    r.add_argument("--mode", action="append", metavar="MODE", help="standard (the default), deepThink, maximum; repeat it or use commas")
    r.add_argument("--repeats", type=int, default=1, help="runs of each build; 2 or more measure run-to-run noise")
    r.add_argument("--name", default="pair", help="label in the run folders' names")
    r.add_argument("--test-from", metavar="REF", help=f"answer test for a build whose own has no {MODE_SWITCH}")
    r.add_argument("--scratch", default=SCRATCH, help=f"where the copies and build folders go (default {SCRATCH})")
    r.add_argument("--limit-hours", type=float, default=LIMIT_HOURS, help="time limit of each run")
    r.add_argument("--dry-run", action="store_true", help="print every command, run none")
    a = p.parse_args(argv)

    if a.command == "compare":
        before, after = read_run(resolve_run(a.before)), read_run(resolve_run(a.after))
        more_before = [read_run(resolve_run(f)) for f in a.noise]
        more_after = [read_run(resolve_run(f)) for f in a.noise_after]
        print(describe(compare_runs(before, after, more_before, more_after, a.same_build), questions()))
        return 0
    if a.command == "stage":
        staged = stage(a.source, a.dir, Shell(a.dry_run), a.test_from)
        if not a.dry_run:
            print(f"Staged {a.source} in {staged['dest']}, patched by {staged['patched_by']}"
                  + (f", with the answer test of {staged['test_from']}" if staged["test_from"] else "") + ".")
            print(f"Run it with OI_BENCH_PRESTAGED={shlex.quote(staged['dest'])} and an OI_BENCH_NAME, OI_BENCH_SRC, "
                  "OI_BENCH_DD and OI_BENCH_SIM of its own.")
        return 0
    a.mode = a.mode or ["standard"]
    return pair(a)


if __name__ == "__main__":
    sys.exit(main())
