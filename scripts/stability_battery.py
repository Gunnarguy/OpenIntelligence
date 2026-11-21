#!/usr/bin/env python3
"""Stability battery: how much do answers vary when nothing changes, where does the variation come from, and what
would remove it. One command, a few hours, no change to the app.

  python3 scripts/stability_battery.py --dry-run     print every run it would make, and run none
  python3 scripts/stability_battery.py               run what is not done yet (a stopped battery picks up where it was)
  python3 scripts/stability_battery.py --report      print the table from the runs that exist, and run none
  python3 scripts/stability_battery.py --max-runs 1  make the next run only (for a queue that yields between runs)
  python3 scripts/stability_battery.py --mode deepThink --arms shipped   the same question for Deep Think (hours)

Why: on 2026-11-20 two runs of one build in Standard scored 80% (16 of 20) and 90% (18 of 20). The app's promise
is the same answer from the same documents, and the plan in `Docs/ai/plans/consistent-answers.md` needs to know the
cause before anything in the app changes. The model call that writes an answer samples at a temperature above
zero (0.4 in Standard), and an August note recorded the search itself returning different passages between runs.

It asks the same 20 questions (the tiny research suite, `scripts/bench_answer_modes.sh`) several times under five
settings (and a sixth on request). Nothing is changed in the app: the three benchmark-only sampling switches the app
already reads, and its adaptive-profiles setting, are set for the run by the answer test (`OI_EVAL_SAMPLING`,
`OI_EVAL_SEED`, `OI_EVAL_TEMPERATURE`, `OI_EVAL_ADAPTIVE`) and removed when it ends.

  shipped   as the app ships                                   the baseline: how far apart identical runs land
  greedy    always the likeliest word, no randomness           two things at once. If two of these still differ,
                                                               something before the writing varies (the passages or
                                                               their order). And: does removing the randomness cost
                                                               right answers
  seeded    as shipped, with the random draws held fixed       does Apple's fixed seed repeat across launches? In
                                                               August 2026 it did not (roadmap row "Two runs of one
                                                               build return different evidence for the same question")
  cool      temperature 0.1                                    is a lower temperature better, the same or worse
  adaptive  the app's own "adaptive profiles" switch, on       the switch exists in Settings and is off by default
                                                               because its effect was never measured: a temperature
                                                               by the kind of question (0.1 for a lookup, up to 0.4
                                                               for a summary). Is it better, the same or worse
  hashed    greedy, with Swift's hashing held fixed            not in the default set: run it with `--arms hashed` only
                                                               when two greedy runs differ, to see whether set and
                                                               dictionary order is the cause

For each setting it prints every run's score, the questions whose right or wrong changed between runs, and how
many answers came out word for word the same (on the first 300 characters the test prints). It ends with what the
numbers say against the plan's decision rules and the lines for `BenchmarkRuns/LEDGER.md`.

What it does not tell you: anything about a phone; anything beyond these 20 questions; whether an answer is good
(right and wrong are the scorer's rule); and, for the search step, more than an inference. The search is checked
directly by the golden harnesses (`Docs/ai/RUNBOOK.md`, "Proving a retrieval change changes nothing"), which this
battery does not run.

Safety is `scripts/paired_run.py`'s and the bench script's: a scratch copy outside the repository, one xcodebuild at
a time, waits while a game is open, a disk check, a time limit on each run, its own simulator. Run folders are
never deleted; a run that exists is not made again.
"""
import argparse, datetime, os, re, shutil, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paired_run as pr

SCRATCH = "/private/tmp/oi-stability"
SIM_NAME = "OI stability"
# name, what it is, the answer test's settings (given to xcodebuild with the TEST_RUNNER_ prefix), runs
ARMS = [
    ("shipped", "as the app ships", {}, 3),
    ("greedy", "always the likeliest word", {"OI_EVAL_SAMPLING": "greedy"}, 2),
    ("seeded", "as shipped, the random draws held fixed (seed 42)", {"OI_EVAL_SAMPLING": "topk", "OI_EVAL_SEED": "42"}, 2),
    ("cool", "temperature 0.1", {"OI_EVAL_TEMPERATURE": "0.1"}, 2),
    ("adaptive", "the app's adaptive-profiles switch on", {"OI_EVAL_ADAPTIVE": "1"}, 3),
    ("hashed", "greedy, Swift's hashing held fixed", {"OI_EVAL_SAMPLING": "greedy", "SWIFT_DETERMINISTIC_HASHING": "1"}, 2),
]
DEFAULT_ARMS = ["shipped", "greedy", "seeded", "cool", "adaptive"]  # `hashed` only when two greedy runs differ
# Runs of the same app code made before this script existed, counted toward an arm so they are not made again.
EARLIER = {("standard", "shipped"): ["2026-11-20-1249-answer-modes-noise-before", "2026-11-20-1306-answer-modes-noise-after"]}
ANSWER = re.compile(r"\] (?:answered|refused) mode=\S+ seconds=\d+ question=(.*?) (?:answer|error)=(.*)$")


def run_name(mode, arm, n):
    return f"stab-{mode}-{arm}-{n}"


def folders_for(mode, arm, runs_dir=pr.RUNS):
    """Run folders that count toward an arm, oldest first: earlier runs of the same code, then this script's."""
    found = [os.path.join(runs_dir, f) for f in EARLIER.get((mode, arm), []) if os.path.isdir(os.path.join(runs_dir, f))]
    if os.path.isdir(runs_dir):
        mine = sorted(f for f in os.listdir(runs_dir) if re.search(rf"-answer-modes-stab-{mode}-{arm}-\d+$", f))
        found += [os.path.join(runs_dir, f) for f in mine]
    return found


def results_of(folder, mode):
    """({question id: right}, {question: first 300 characters of its answer}) for a run folder's app-model results."""
    run = pr.read_run(folder)
    key = f"{mode}-app"
    results = (run["modes"].get(key) or {}).get("results") or {}
    answers = {}
    text = pr.read_text(os.path.join(folder, key + ".txt")) or ""
    for line in text.splitlines():
        m = ANSWER.search(line)
        if m:
            answers[m.group(1)] = m.group(2)
    return results, answers


QUESTIONS = 20  # the tiny research suite; a run with fewer scored questions was cut short and does not count


def complete(folder, mode):
    """True when a run folder holds a score for every question. A run that was stopped, or never got past its build,
    leaves a folder too; counting it would end an arm early and shrink the questions every other run is compared on."""
    return len(results_of(folder, mode)[0]) >= QUESTIONS


def done_for(mode, arm, runs_dir=pr.RUNS, complete=complete):
    return [f for f in folders_for(mode, arm, runs_dir) if complete(f, mode)]


def summarize(runs):
    """One arm's numbers from its runs, each a (results, answers) pair. Pure: the tests feed it invented runs."""
    scored = [r for r, _ in runs if r]
    if not scored:
        return None
    questions = sorted(set.intersection(*(set(r) for r in scored)))
    rights = [sum(1 for q in questions if r[q]) for r in scored]
    unstable = [q for q in questions if len({r[q] for r in scored}) > 1]
    always_right = sum(1 for q in questions if all(r[q] for r in scored))
    texts = [a for _, a in runs if a]
    asked = sorted(set.intersection(*(set(a) for a in texts))) if texts else []
    identical = sum(1 for q in asked if len({a[q] for a in texts}) == 1)
    return {"runs": len(scored), "questions": len(questions), "rights": rights,
            "mean": sum(rights) / len(rights), "spread": max(rights) - min(rights), "unstable": unstable,
            "always_right": always_right, "identical": identical, "asked": len(asked)}


def row(arm, what, s):
    if s is None:
        return f"| {arm} | {what} | 0 | not run | | | |"
    n = s["questions"]
    scores = ", ".join(pr.pct(r, n) for r in s["rights"])
    same = f"{pr.pct(s['identical'], s['asked'])}" if s["runs"] > 1 and s["asked"] else "one run"
    flips = f"{len(s['unstable'])}: {', '.join(s['unstable'])}" if s["unstable"] else ("0" if s["runs"] > 1 else "one run")
    return (f"| {arm} | {what} | {s['runs']} | {scores} | {pr.pct(round(s['mean']), n)} mean | {flips} | {same} |")


def reading(by_arm):
    """What the numbers say against the plan's decision rules. Each line is conditional on the arms that ran."""
    out = []
    shipped, seeded, greedy, cool, hashed, adaptive = (by_arm.get(a) for a in ("shipped", "seeded", "greedy", "cool", "hashed", "adaptive"))
    if shipped and shipped["runs"] > 1:
        out.append(f"As shipped, {len(shipped['unstable'])} of {shipped['questions']} questions changed between right and wrong "
                   f"across {shipped['runs']} runs, and {shipped['identical']} of {shipped['asked']} answers were word for word "
                   "the same. That is the variation a user can meet today.")
    exact = lambda s: s["identical"] == s["asked"] and not s["unstable"]
    if greedy and greedy["runs"] > 1:
        if exact(greedy):
            out.append("With no randomness in the writing every answer repeated exactly, so each run gave the model the "
                       "same passages in the same order: the variation as shipped is the writing's randomness.")
        else:
            out.append(f"With no randomness in the writing, {greedy['asked'] - greedy['identical']} of {greedy['asked']} answers "
                       "still differed between runs. Something before the writing varies (the passages or their order): "
                       "run `--arms hashed`, then the golden harnesses, before changing any temperature.")
    if hashed and hashed["runs"] > 1 and greedy and greedy["runs"] > 1 and not exact(greedy):
        out.append("With Swift's hashing held fixed as well, " + (
            "every answer repeated exactly, so the order of a set or dictionary reaches the prompt somewhere."
            if exact(hashed) else
            f"{hashed['asked'] - hashed['identical']} of {hashed['asked']} answers still differed, so hashing order is not the "
            "whole cause."))
    if seeded and seeded["runs"] > 1:
        if exact(seeded):
            out.append("With the random draws held fixed every answer repeated exactly: the fixed seed repeats across "
                       "launches on this system (in August 2026 it did not).")
        else:
            out.append(f"With the random draws held fixed, {seeded['asked'] - seeded['identical']} of {seeded['asked']} answers "
                       "still differed between runs" + (
                           ", while greedy runs repeated: the fixed seed does not repeat across launches, so a seed is "
                           "not a route to the same answer twice." if greedy and greedy["runs"] > 1 and exact(greedy) else "."))
    for name, s, words in (("greedy", greedy, "no randomness in the writing"), ("cool", cool, "temperature 0.1"),
                           ("adaptive", adaptive, "the adaptive-profiles switch on")):
        if s and shipped:
            gap = s["mean"] - shipped["mean"]
            noise = max(shipped["spread"], s["spread"])
            verdict = ("is not distinguishable from as shipped" if abs(gap) <= noise else
                       "scored higher than as shipped" if gap > 0 else "scored lower than as shipped")
            out.append(f"With {words} the mean was {s['mean']:.1f} right against {shipped['mean']:.1f} ({gap:+.1f}), which "
                       f"{verdict} (runs of one setting differ by up to {noise}). "
                       f"{len(s['unstable'])} questions changed between its runs.")
    return out or ["Not enough runs yet to say anything."]


def planned(mode, arms, max_runs=None, runs_dir=pr.RUNS, complete=complete):
    """The runs still to make, in order, as (setting, its test settings, run number); at most `max_runs` of them.
    Only complete runs count as made, so a run that failed is made again (under the same number, in a new folder)."""
    todo = []
    for arm, _, settings, runs in ARMS:
        if arm not in arms:
            continue
        have = len(done_for(mode, arm, runs_dir, complete))
        todo += [(arm, settings, n) for n in range(have + 1, runs + 1)]
    return todo if max_runs is None else todo[:max_runs]


def report(mode, runs_dir=pr.RUNS):
    by_arm, lines, folders, cut_short = {}, [], [], 0
    lines.append("| Setting | What | Runs | Each run | Mean | Questions that changed between runs | Answers word for word the same |")
    lines.append("|---|---|---|---|---|---|---|")
    for arm, what, _, _ in ARMS:
        found = done_for(mode, arm, runs_dir)
        cut_short += len(folders_for(mode, arm, runs_dir)) - len(found)
        folders += found
        s = summarize([results_of(f, mode) for f in found])
        by_arm[arm] = s
        lines.append(row(arm, what, s))
    read = reading(by_arm)
    if cut_short:
        read.append(f"{cut_short} run folder(s) were cut short (fewer than {QUESTIONS} scored questions) and are not counted.")
    return "\n".join(lines), read, folders


def ledger(mode, table, read, folders):
    names = ", ".join(f"`{os.path.basename(f)}`" for f in folders)
    today = datetime.date.today().isoformat()
    return (f"### {today} Stability battery, {mode}: the same 20 questions under several sampling settings ({names})\n\n"
            "`scripts/stability_battery.py`: one build, the tiny research suite's 20 questions, the app's own model service "
            "in the iOS 27.0 Simulator (a scratch copy patched by `scripts/sim_model_copy.py`). The settings are the "
            "benchmark-only sampling switches `AppleFoundationLLMService` reads; the app is unchanged. Right and wrong by "
            "rule (`scripts/score_answer_eval.py`); \"word for word\" compares the first 300 characters of each answer.\n"
            "`[evidence_level: measured, confidence: low to medium: few runs per setting, one question set]`\n\n"
            + table + "\n\nRead: " + " ".join(read) + "\n")


def main():
    p = argparse.ArgumentParser(description="Measure how much answers vary between identical runs, and why.")
    p.add_argument("--mode", default="standard", choices=pr.MODES)
    p.add_argument("--arms", nargs="*", default=DEFAULT_ARMS, help="which settings to run (default: all but hashed)")
    p.add_argument("--ref", default="HEAD", help="the commit to measure (default HEAD)")
    p.add_argument("--max-runs", type=int, default=None,
                   help="make at most this many runs and stop (a queue that lets other builds in between runs)")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--report", action="store_true")
    p.add_argument("--limit-hours", type=float, default=pr.LIMIT_HOURS)
    a = p.parse_args()

    if not a.report:
        todo = planned(a.mode, a.arms, a.max_runs)
        shell = pr.Shell(a.dry_run)
        shell.note(f"Stability battery, {a.mode}, commit {a.ref}: {len(todo)} runs to make"
                   + (" (DRY RUN: no command below is run)" if a.dry_run else ""))
        if todo:
            stage = os.path.join(SCRATCH, "stage")
            if not a.dry_run:
                if shutil.disk_usage("/System/Volumes/Data").free / 2 ** 30 < 15:
                    sys.exit("under 15 GiB free on the internal disk: not running (~/.agents/STORAGE.md)")
                shutil.rmtree(stage, ignore_errors=True)
                os.makedirs(SCRATCH, exist_ok=True)
            shell.note(f"one scratch copy of {a.ref}, patched for the Simulator model, used by every run")
            if a.dry_run:
                shell.show(f"python3 scripts/paired_run.py stage {a.ref} {stage}")
            else:
                pr.stage(a.ref, stage, shell)
            for arm, settings, n in todo:
                env = {"OI_BENCH_PRESTAGED": stage, "OI_BENCH_NAME": run_name(a.mode, arm, n),
                       "OI_BENCH_SRC": os.path.join(SCRATCH, "src"), "OI_BENCH_DD": os.path.join(SCRATCH, "dd"),
                       "OI_BENCH_SIM": SIM_NAME}
                env.update({"TEST_RUNNER_" + k: v for k, v in settings.items()})
                code = pr.run_bench(env, [a.mode], shell, a.limit_hours)
                if code not in (None, 0):
                    print(f"run {run_name(a.mode, arm, n)} ended with exit {code}; stopping here. Run the command again to go on.")
                    break
        if a.dry_run:
            return

    table, read, folders = report(a.mode)
    print(f"\nStability, {a.mode}, {len(folders)} runs\n\n{table}\n")
    for line in read:
        print("- " + line)
    print("\n# Lines for BenchmarkRuns/LEDGER.md (this script does not edit that file)\n")
    print(ledger(a.mode, table, read, folders))


if __name__ == "__main__":
    main()
