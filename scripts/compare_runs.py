#!/usr/bin/env python3
"""Compare two benchmark runs case by case, paired, with an exact sign test.

Why paired
==========
Comparing two aggregate accuracy figures wastes most of the information in a run. These fixtures
are a fixed ordered list, so two runs over the same manifest answer the *same questions*, and the
right question is not "did the average move" but "on how many individual questions did the change
win, and on how many did it lose". That is a paired comparison, and it is what produced the only
statistically meaningful retrieval finding this project has: RRF fusion losing to the lexical arm
alone, 26 wins to 6, exact sign test p = 0.0005.

It also rescues an interrupted run. A run killed at 40 of 83 cases cannot be compared to an 83-case
aggregate, because the two cover different questions. Paired against the same 40 cases of the
baseline it is a perfectly valid measurement, just with less power.

The test
========
Exact two-sided binomial sign test on the discordant pairs only, which is McNemar's test in its
exact form. Ties carry no information about direction and are excluded from the statistic, though
they are reported because a change that moves nothing is itself a result.

Usage
=====
    python3 scripts/compare_runs.py <baseline_run_dir> <candidate_run_dir>
    python3 scripts/compare_runs.py BenchmarkRuns/qasper-overnight BenchmarkRuns/qasper-postfix-20260813
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path


def load_cases(run_dir: Path) -> dict[str, dict]:
    """{case_id: row}, preferring the incremental checkpoint so partial runs are usable.

    `results.json` only exists once a run finishes. `results.jsonl` is written per case, which is
    the whole point of comparing this way: an interrupted run still holds a real measurement.
    """
    checkpoint = run_dir / "results.jsonl"
    index = run_dir / "results.json"
    rows: list[dict] = []
    if checkpoint.is_file():
        rows = [json.loads(line) for line in checkpoint.read_text().splitlines() if line.strip()]
    elif index.is_file():
        rows = json.loads(index.read_text()).get("rows", [])
    else:
        raise SystemExit(f"error: no results.jsonl or results.json in {run_dir}")
    return {r["case_id"]: r for r in rows}


def exact_sign_test(wins: int, losses: int) -> float:
    """Exact two-sided binomial p under p=0.5 on the discordant pairs.

    Written out rather than pulled from scipy because this repository has no scientific-stack
    dependency and adding one for a binomial tail would be a poor trade. `math.comb` is exact for
    these counts, so there is no approximation to justify either.
    """
    n = wins + losses
    if n == 0:
        return 1.0
    observed = min(wins, losses)
    tail = sum(math.comb(n, i) for i in range(observed + 1)) / (2 ** n)
    return min(1.0, 2 * tail)


def correctness(row: dict) -> bool | None:
    """True/False for an answerable case, None for an abstention control.

    Abstention cases are excluded from the accuracy comparison on purpose: folding a refusal into
    an accuracy rate hides the behaviour this app most needs to get right, and they are scored
    separately for that reason.
    """
    score = row.get("score") or {}
    if score.get("expected") != "answer":
        return None
    return bool(score.get("correct"))


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--by-category", action="store_true", help="break results down by category")
    args = parser.parse_args()

    base, cand = load_cases(args.baseline), load_cases(args.candidate)
    shared = [cid for cid in cand if cid in base]

    print(f"baseline : {args.baseline}  ({len(base)} cases)")
    print(f"candidate: {args.candidate}  ({len(cand)} cases)")
    print(f"paired on {len(shared)} shared cases")
    if len(cand) < len(base):
        print(f"  candidate is partial; this compares the {len(shared)} cases it reached, not all "
              f"{len(base)}. Do not quote its accuracy against a full-run figure.")
    if not shared:
        print("\nNo shared case ids. Are these runs over the same manifest?")
        return 2

    wins = losses = ties_right = ties_wrong = 0
    win_ids: list[str] = []
    loss_ids: list[str] = []
    for cid in shared:
        b, c = correctness(base[cid]), correctness(cand[cid])
        if b is None or c is None:
            continue
        if c and not b:
            wins += 1
            win_ids.append(cid)
        elif b and not c:
            losses += 1
            loss_ids.append(cid)
        elif b and c:
            ties_right += 1
        else:
            ties_wrong += 1

    answerable = wins + losses + ties_right + ties_wrong
    base_correct = losses + ties_right
    cand_correct = wins + ties_right
    print()
    print(f"answerable paired cases: {answerable}")
    if answerable:
        print(f"  baseline  correct: {base_correct}/{answerable} = {base_correct/answerable:.1%}")
        print(f"  candidate correct: {cand_correct}/{answerable} = {cand_correct/answerable:.1%}")
    print()
    print(f"  candidate wins  (fixed by the change): {wins}")
    print(f"  candidate loses (broken by the change): {losses}")
    print(f"  both correct: {ties_right}   both wrong: {ties_wrong}")

    p = exact_sign_test(wins, losses)
    print()
    print(f"exact two-sided sign test on {wins + losses} discordant pairs: p = {p:.4f}")
    if wins + losses == 0:
        print("  Nothing moved in either direction. The change altered no individual answer.")
    elif p > 0.05:
        print("  Not significant. The direction may be real and this run cannot show it; with")
        print(f"  {wins + losses} discordant pairs only a large effect would reach significance.")
    else:
        better = "candidate" if wins > losses else "baseline"
        print(f"  Significant, favouring the {better}.")

    if loss_ids:
        print()
        print("Cases the change BROKE, which are the ones worth reading first:")
        for cid in loss_ids[:10]:
            print(f"  {cid}")
    if win_ids:
        print()
        print("Cases the change FIXED:")
        for cid in win_ids[:10]:
            print(f"  {cid}")

    if args.by_category:
        print()
        print(f"{'category':<22} {'n':>4} {'base':>7} {'cand':>7} {'delta':>7}")
        print("-" * 50)
        cats: dict[str, list[str]] = {}
        for cid in shared:
            cats.setdefault(cand[cid].get("category", "?"), []).append(cid)
        for cat, ids in sorted(cats.items()):
            pairs = [(correctness(base[i]), correctness(cand[i])) for i in ids]
            pairs = [(b, c) for b, c in pairs if b is not None and c is not None]
            if not pairs:
                continue
            b_rate = sum(1 for b, _ in pairs if b) / len(pairs)
            c_rate = sum(1 for _, c in pairs if c) / len(pairs)
            print(f"{cat:<22} {len(pairs):>4} {b_rate:>6.1%} {c_rate:>6.1%} {c_rate-b_rate:>+6.1%}")

    # Wall clock, because a change that buys accuracy at 3x the latency is a different decision.
    def secs(rows: dict[str, dict]) -> list[float]:
        return [rows[c]["run"].get("seconds", 0) for c in shared if c in rows]

    b_s, c_s = secs(base), secs(cand)
    if b_s and c_s:
        print()
        print(f"seconds per case, median: baseline {sorted(b_s)[len(b_s)//2]:.0f}s, "
              f"candidate {sorted(c_s)[len(c_s)//2]:.0f}s")
        print("  A large gap here is not necessarily the change: these runs are months apart on a")
        print("  shared laptop, and machine load moves this number more than most code does.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
