#!/usr/bin/env python3
"""Compare two benchmark runs paired by case_id.

Runs disagree about which cases complete. Timeouts and hangs differ between them, and a case
that produced no stage metrics contributes nothing to one run and a real number to the other.
Averaging each run over its own case set therefore compares two different corpora and moves the
result in whichever direction the missing cases happened to fall.

This happened. An interim `coreml-provider` figure recorded in BenchmarkRuns/LEDGER.md showed the
lexical control dropping, which under ledger rule 4 would have invalidated the whole run. The
control had not moved at all: two cases present in the new run and absent from the baseline were
dragging the new average down. See ledger rule 5.

So: intersect first, then average, and always show the per-case flips so a mean cannot hide a
mix of gains and regressions.

Usage:
    python3 scripts/compare_benchmark_runs.py BenchmarkRuns/tokfix BenchmarkRuns/coreml-provider
    python3 scripts/compare_benchmark_runs.py <baseline> <candidate> --stage vector --metric r1
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Ordered as the retrieval pipeline runs, so the printed table reads top to bottom as the
# pipeline does. `lexical` is the control: it reads full text through FTS5 and must not move
# when only the embedding provider changes.
STAGES = ["vector", "lexical", "fusion", "boosted", "candidates", "rerank", "final"]
CONTROL_STAGE = "lexical"
METRICS = ["r1", "r5", "r10", "mrr", "ndcg10"]


def load(run_dir: Path) -> dict[str, dict]:
    results = run_dir / "results.jsonl"
    if not results.exists():
        sys.exit(f"no results.jsonl in {run_dir}")
    rows = {}
    with results.open() as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            row = json.loads(line)
            rows[row["case_id"]] = row
    return rows


def metric(row: dict, stage: str, key: str):
    """Return one stage metric, or None when the case produced no metrics for that stage.

    None and 0.0 mean different things here. None is 'this case did not report', which excludes
    it from the pairing. 0.0 is a real miss and counts.
    """
    for entry in (row.get("run") or {}).get("stage_metrics") or []:
        if entry.get("stage") == stage:
            value = entry.get(key)
            return value if isinstance(value, (int, float)) else None
    return None


def mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else float("nan")


def sign_test(gained: int, lost: int, alpha: float = 0.05) -> str:
    """Exact two-sided sign test over discordant pairs, reported in words.

    Only pairs that changed carry information, so `n` here is gained + lost, never the case count.
    That matters more than it sounds: a run of one-directional flips looks decisive well before it
    is significant. Four better and zero worse is p = 0.125. Six discordant pairs, all one way, is
    the first point a two-sided test clears 0.05, which is where 'six' comes from in this repo's
    minimum-detectable-effect rule of thumb.
    """
    n = gained + lost
    if n == 0:
        return "sign test: no discordant pairs, nothing to test"

    from math import comb

    extreme = min(gained, lost)
    # Two-sided: sum both tails at or beyond the observed imbalance.
    p = min(1.0, 2 * sum(comb(n, k) for k in range(extreme + 1)) / (2 ** n))

    verdict = "SIGNIFICANT" if p < alpha else "not significant"
    detail = ""
    if p >= alpha:
        # Say what it would take, so the run has a stopping rule instead of a vibe.
        need = next((m for m in range(n + 1, 40) if 2 / (2 ** m) < alpha), None)
        if need and lost == 0:
            detail = f"; needs {need} one-directional discordant pairs at this alpha, have {n}"
    return f"sign test: {gained} better vs {lost} worse, p = {p:.4f}, {verdict} at alpha {alpha}{detail}"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--stage", default="vector", help="stage to break down per case (default: vector)")
    parser.add_argument("--metric", default="r1", help="metric to break down per case (default: r1)")
    args = parser.parse_args()

    base = load(args.baseline)
    cand = load(args.candidate)

    # Intersect on cases that BOTH runs scored for the breakdown stage. A case present in the
    # file but without stage metrics did not complete retrieval and cannot be paired.
    paired = [
        case_id
        for case_id in cand
        if case_id in base
        and metric(base[case_id], args.stage, args.metric) is not None
        and metric(cand[case_id], args.stage, args.metric) is not None
    ]

    print(f"baseline  {args.baseline}  {len(base)} cases")
    print(f"candidate {args.candidate}  {len(cand)} cases")
    print(f"paired    {len(paired)} cases with '{args.stage}' metrics in both\n")

    dropped = sorted(set(cand) - set(paired))
    if dropped:
        # Named, not counted. Ledger rule: a silent cap reads as full coverage.
        print(f"excluded from pairing ({len(dropped)}): {', '.join(sorted(dropped))}\n")

    print(f"{'stage':11s} " + "  ".join(f"{m:>16s}" for m in METRICS))
    for stage in STAGES:
        cells = []
        present = False
        for key in METRICS:
            before = [v for c in paired if (v := metric(base[c], stage, key)) is not None]
            after = [v for c in paired if (v := metric(cand[c], stage, key)) is not None]
            if before and after:
                present = True
                cells.append(f"{mean(before):.3f} -> {mean(after):.3f}")
            else:
                cells.append("-")
        if present:
            marker = "  <- CONTROL" if stage == CONTROL_STAGE else ""
            print(f"{stage:11s} " + "  ".join(f"{c:>16s}" for c in cells) + marker)

    # Per-case flips. A mean of 0.500 hides whether five cases improved and one regressed or
    # whether three did each.
    gained, lost, same = [], [], []
    for case_id in paired:
        before = metric(base[case_id], args.stage, args.metric)
        after = metric(cand[case_id], args.stage, args.metric)
        (gained if after > before else lost if after < before else same).append(case_id)

    print(f"\nper-case {args.stage} {args.metric}: {len(gained)} better, {len(lost)} worse, {len(same)} unchanged")
    for label, group in (("better", gained), ("worse", lost)):
        for case_id in group:
            before = metric(base[case_id], args.stage, args.metric)
            after = metric(cand[case_id], args.stage, args.metric)
            print(f"  {label:6s} {case_id:36s} {before:.2f} -> {after:.2f}")

    # Exact two-sided sign test on the discordant pairs. Printed because a run of one-directional
    # flips reads as overwhelming long before it is significant: 4 better and 0 worse is p = 0.125,
    # not the near-certainty it looks like. Ties carry no information and are excluded, which is
    # why the count that matters is discordant pairs and not total cases.
    print(f"\n{sign_test(len(gained), len(lost))}")

    control_moved = any(
        metric(base[c], CONTROL_STAGE, "r1") != metric(cand[c], CONTROL_STAGE, "r1") for c in paired
    )
    print(
        f"\ncontrol ({CONTROL_STAGE} r1): "
        + ("MOVED -- runs are not comparable, see ledger rule 4" if control_moved
           else "identical case for case, runs are comparable")
    )

    correct = lambda rows, ids: sum(1 for c in ids if (rows[c].get("score") or {}).get("correct"))
    print(f"correct: {correct(base, paired)}/{len(paired)} -> {correct(cand, paired)}/{len(paired)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
