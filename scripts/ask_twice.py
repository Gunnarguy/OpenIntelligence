#!/usr/bin/env python3
"""Ask twice: import the test documents once, ask every question several times in the same library, and see whether
the answer repeats. No change to the app.

  python3 scripts/ask_twice.py run --mode standard --sampling shipped --repeat 3   one run (skipped if it exists)
  python3 scripts/ask_twice.py run ... --dry-run                                    print the command, run nothing
  python3 scripts/ask_twice.py report                                               the table from the runs that exist

Why: the stability battery of 2026-11-21 (`scripts/stability_battery.py`) found that two runs never asked the same
library, because each run imports the fixtures again and the import writes a model-made summary of each document.
So it could not say whether an answer repeats when nothing is imported in between, which is what a person asking the
same question twice meets. Here the answer test asks each question `--repeat` times in one process
(`OI_EVAL_REPEAT`), and prints every later answer whole beside the first.

For each run it prints, per pass, how many answers are right by rule (`scripts/score_answer_eval.py`'s rule), how many
are word for word the first answer, and which questions changed between right and wrong. `--sampling greedy` takes
the randomness out of the writing: if answers still differ there, something other than sampling varies inside one
process (the search, the prompt, or the model itself).

What it does not tell you: anything about a phone, or beyond these 20 questions. A repeated question can be served by
the app's own exact-question cache for its search step (the report counts those lines); that is what the app does
for a real second ask, so it is left on.

Safety is `scripts/paired_run.py`'s and the bench script's. Run folders are never deleted.
"""
import argparse, base64, os, re, shutil, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import json
import paired_run as pr
import score_answer_eval as scorer

SCRATCH = "/private/tmp/oi-twice"
SIM_NAME = "OI ask twice"
SAMPLING = {"shipped": {}, "greedy": {"OI_EVAL_SAMPLING": "greedy"}}
AGAIN = re.compile(r"\] again pass=(\d+) mode=\S+ seconds=(\d+) same=(true|false) question64=(\S+) first64=(\S*) again64=(\S*)\s*$")
QUESTIONS = 20


def run_name(mode, sampling, tag=""):
    """`tag` names a set of runs made under other test rules ("item8", 2026-11-23: the corrected scoring rule, the
    labelled fixtures and memory emptied before each ask), so they are made again instead of found done."""
    return f"twice-{mode}-{sampling}" + (f"-{tag}" if tag else "")


def folders_for(mode, sampling, runs_dir=pr.RUNS, tag=""):
    if not os.path.isdir(runs_dir):
        return []
    return [os.path.join(runs_dir, f) for f in sorted(os.listdir(runs_dir))
            if f.endswith(f"-answer-modes-{run_name(mode, sampling, tag)}")]


def text(b64):
    return base64.b64decode(b64).decode("utf-8", "replace") if b64 else ""


def parse(lines):
    """[(question, [answer of pass 1, pass 2, ...], [seconds of pass 2, ...])] in the order asked."""
    out, at = [], {}
    for line in lines:
        m = AGAIN.search(line)
        if not m:
            continue
        number, seconds, _, q64, first64, again64 = m.groups()
        question = text(q64)
        if int(number) == 2:
            at[question] = len(out)
            out.append((question, [text(first64), text(again64)], [int(seconds)]))
        elif question in at:
            out[at[question]][1].append(text(again64))
            out[at[question]][2].append(int(seconds))
    return out


def cases_in_order(questions, cases):
    """The manifest case for each asked question. Three cases share one question (lost in the middle): they are asked
    in the manifest's order, so the nth time a question appears it is the nth case that has it."""
    seen, out = {}, []
    for q in questions:
        same = [c for c in cases if c["query"] == q]
        n = seen.get(q, 0)
        seen[q] = n + 1
        out.append(same[min(n, len(same) - 1)] if same else None)
    return out


def summarize(asked, cases):
    """Numbers for one run. Pure: the tests feed it invented answers."""
    if not asked:
        return None
    passes = min(len(a) for _, a, _ in asked)
    matched = cases_in_order([q for q, _, _ in asked], cases)
    right = [[bool(c) and scorer.rule(c, answers[p], cases) for p in range(passes)] for (_, answers, _), c in zip(asked, matched)]
    ids = [c["id"] if c else q[:40] for (q, _, _), c in zip(asked, matched)]
    return {
        "questions": len(asked), "passes": passes,
        "right": [sum(r[p] for r in right) for p in range(passes)],
        "same_as_first": [sum(1 for _, a, _ in asked if a[p] == a[0]) for p in range(1, passes)],
        "all_same": sum(1 for _, a, _ in asked if len(set(a[:passes])) == 1),
        "flipped": [i for i, r in zip(ids, right) if len(set(r)) > 1],
        "always_right": sum(1 for r in right if all(r)),
    }


def row(mode, sampling, s, cache_hits):
    if s is None:
        return f"| {mode} | {sampling} | not run | | | | | |"
    n = s["questions"]
    rights = ", ".join(pr.pct(r, n) for r in s["right"])
    same = ", ".join(pr.pct(k, n) for k in s["same_as_first"])
    flipped = f"{len(s['flipped'])}: {', '.join(s['flipped'])}" if s["flipped"] else "0"
    return (f"| {mode} | {sampling} | {s['passes']} | {rights} | {same} | {pr.pct(s['all_same'], n)} | {flipped} | {cache_hits} |")


def report(runs_dir=pr.RUNS, tag=""):
    cases = json.loads(scorer.MANIFEST.read_text())["cases"]
    lines = ["| Mode | Sampling | Asks of each question | Right, each ask | Same words as the first ask, each later ask | "
             "Same words every ask | Questions that changed between right and wrong | Search-cache lines |", "|---|---|---|---|---|---|---|---|"]
    folders = []
    for mode in pr.MODES:
        for sampling in SAMPLING:
            found = folders_for(mode, sampling, runs_dir, tag)
            s, hits, used = None, 0, None
            for folder in found:  # the newest complete one
                log = pr.read_text(os.path.join(folder, f"{mode}-app.txt")) or ""
                got = summarize(parse(log.splitlines()), cases)
                if got and got["questions"] >= QUESTIONS:
                    s, used = got, folder
                    full = pr.read_text(os.path.join(folder, f"{mode}-app.log")) or ""
                    hits = full.count("Exact cache hit")
            if used:
                folders.append(used)
            lines.append(row(mode, sampling, s, hits))
    return "\n".join(lines), folders


def complete(mode, sampling, runs_dir=pr.RUNS, tag=""):
    cases = json.loads(scorer.MANIFEST.read_text())["cases"]
    for folder in folders_for(mode, sampling, runs_dir, tag):
        log = pr.read_text(os.path.join(folder, f"{mode}-app.txt")) or ""
        got = summarize(parse(log.splitlines()), cases)
        if got and got["questions"] >= QUESTIONS:
            return True
    return False


def main():
    p = argparse.ArgumentParser(description="Ask every question several times in one imported library.")
    sub = p.add_subparsers(dest="command", required=True)
    r = sub.add_parser("run")
    r.add_argument("--mode", default="standard", choices=pr.MODES)
    r.add_argument("--sampling", default="shipped", choices=list(SAMPLING))
    r.add_argument("--repeat", type=int, default=2)
    r.add_argument("--ref", default="HEAD")
    r.add_argument("--dry-run", action="store_true")
    r.add_argument("--limit-hours", type=float, default=pr.LIMIT_HOURS)
    r.add_argument("--tag", default="", help="names runs made under other test rules (folder suffix)")
    rp = sub.add_parser("report")
    rp.add_argument("--tag", default="")
    a = p.parse_args()

    if a.command == "report":
        table, folders = report(tag=a.tag)
        print(f"\nAsk twice, {len(folders)} runs\n\n{table}\n")
        print("Folders: " + ", ".join(f"`{os.path.basename(f)}`" for f in folders))
        return
    if complete(a.mode, a.sampling, tag=a.tag):
        print(f"{run_name(a.mode, a.sampling, a.tag)} exists and is complete; not made again")
        return
    shell = pr.Shell(a.dry_run)
    stage = os.path.join(SCRATCH, "stage")
    env = {"OI_BENCH_PRESTAGED": stage, "OI_BENCH_NAME": run_name(a.mode, a.sampling, a.tag),
           "OI_BENCH_SRC": os.path.join(SCRATCH, "src"), "OI_BENCH_DD": os.path.join(SCRATCH, "dd"),
           "OI_BENCH_SIM": SIM_NAME, "TEST_RUNNER_OI_EVAL_REPEAT": str(a.repeat)}
    env.update({"TEST_RUNNER_" + k: v for k, v in SAMPLING[a.sampling].items()})
    if a.dry_run:
        shell.show(f"python3 scripts/paired_run.py stage {a.ref} {stage}")
    else:
        # A run takes about 6 GiB at its peak (measured 2026-11-23: 17 GiB free fell to 11). OI_TWICE_MIN_FREE_GIB
        # lowers the floor when other sessions hold the disk; the queue then watches for under 3 GiB and stops.
        floor = float(os.environ.get("OI_TWICE_MIN_FREE_GIB", "15"))
        if shutil.disk_usage("/System/Volumes/Data").free / 2 ** 30 < floor:
            sys.exit(f"under {floor:g} GiB free on the internal disk: not running (~/.agents/STORAGE.md)")
        shutil.rmtree(stage, ignore_errors=True)
        os.makedirs(SCRATCH, exist_ok=True)
        pr.stage(a.ref, stage, shell)
    code = pr.run_bench(env, [a.mode], shell, a.limit_hours)
    if code not in (None, 0):
        sys.exit(f"run {run_name(a.mode, a.sampling, a.tag)} ended with exit {code}")


if __name__ == "__main__":
    main()
