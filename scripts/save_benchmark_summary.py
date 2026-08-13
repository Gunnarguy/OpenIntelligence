#!/usr/bin/env python3
"""Distil one benchmark run into a small committed summary.

Why this exists
---------------
`BenchmarkRuns/` is gitignored, so until 2026-08-12 no benchmark result had ever survived a
fresh clone. Every measurement this project made existed only on one machine and disappeared.
That is why "has retrieval regressed?" was unanswerable, why the quality modes had no
post-fix measurement, and why `Docs/EVALS.md` described a framework while recording no numbers.

The full artifacts stay ignored, and should: they are bulky and older ones referenced private
fixtures. What was being thrown out with them is the *summary*, which is a few hundred bytes
and is the part anyone actually needs later.

Output is one Markdown file per run under `Docs/AuditArtifacts/Benchmarks/`, carrying the
headline counts, the per-stage retrieval table, and enough provenance to know what produced it:
commit, whether the tree was dirty, the manifest, the fixture-corpus hash, and the pool size.

Usage
-----
    python3 scripts/save_benchmark_summary.py BenchmarkRuns/<run-dir>
    python3 scripts/save_benchmark_summary.py BenchmarkRuns/<run-dir> --stdout
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = REPO_ROOT / "Docs/AuditArtifacts/Benchmarks"

STAGE_ORDER = ["vector", "lexical", "fusion", "boosted", "candidates", "rerank", "final"]


def load(run_dir: Path) -> tuple[dict, list[dict]]:
    """Prefer results.json; fall back to the incremental checkpoint.

    The checkpoint matters: a run interrupted partway still has every completed case in
    `results.jsonl`, and a partial measurement that is recorded beats a complete one that
    evaporated. The 2026-08-12 run lost 27 cases to a closed lid before checkpointing existed.
    """
    index = run_dir / "results.json"
    if index.exists():
        data = json.loads(index.read_text())
        return data.get("meta", {}), data.get("rows", [])

    checkpoint = run_dir / "results.jsonl"
    if checkpoint.exists():
        rows = [json.loads(l) for l in checkpoint.read_text().splitlines() if l.strip()]
        return {"run_id": run_dir.name, "note": "partial run; read from checkpoint"}, rows

    raise SystemExit(f"error: no results.json or results.jsonl in {run_dir}")


def verdicts(rows: list[dict], mode: str) -> Counter:
    out: Counter = Counter()
    for row in rows:
        if row.get("mode") != mode:
            continue
        run = row.get("run") or {}
        score = row.get("score") or {}
        if not run.get("ok"):
            out["error"] += 1
        elif score.get("correct"):
            out["correct"] += 1
        elif score.get("expected") == "abstain":
            out["hallucinated"] += 1
        else:
            out["miss"] += 1
    return out


def abstention(rows: list[dict], mode: str) -> tuple[int, int]:
    """Correct abstentions over abstention cases seen. Reported separately from accuracy.

    Kept apart on purpose: folding a refusal into an accuracy rate hides the single behaviour
    this app most needs to get right, and the two move independently. On 2026-08-12 the
    synthetic pack scored 2/2 here while the external pack scored 0/2.
    """
    seen = correct = 0
    for row in rows:
        if row.get("mode") != mode:
            continue
        score = row.get("score") or {}
        if score.get("expected") != "abstain":
            continue
        seen += 1
        if score.get("correct"):
            correct += 1
    return correct, seen


def stage_table(rows: list[dict], mode: str) -> list[str]:
    acc: dict[str, list[dict]] = defaultdict(list)
    for row in rows:
        if row.get("mode") != mode:
            continue
        for stage in (row.get("run") or {}).get("stage_metrics") or []:
            acc[stage["stage"]].append(stage)
    if not acc:
        return []

    lines = ["| Stage | n | R@1 | R@5 | R@10 | MRR@10 | nDCG@5 | Mean candidates |",
             "| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
    ordered = [s for s in STAGE_ORDER if s in acc] + [s for s in acc if s not in STAGE_ORDER]
    for stage in ordered:
        entries = acc[stage]
        n = len(entries)
        def mean(key: str) -> float:
            return sum(e.get(key, 0.0) for e in entries) / n if n else 0.0
        lines.append(
            f"| `{stage}` | {n} | {mean('r1'):.2f} | **{mean('r5'):.2f}** | {mean('r10'):.2f} | "
            f"{mean('mrr'):.2f} | {mean('ndcg5'):.2f} | {mean('results'):.0f} |"
        )
    return lines


def minimum_detectable(n: int) -> str:
    if n < 6:
        return f"at n={n}, nothing is resolvable: the exact sign test needs 6 discordant cases"
    return (f"at n={n}, the smallest resolvable difference is 6/{n}, about "
            f"{6 / n * 100:.0f} points")


def render(meta: dict, rows: list[dict]) -> str:
    modes = meta.get("modes") or sorted({r.get("mode") for r in rows if r.get("mode")})
    manifest = meta.get("manifest", "unknown")
    synthetic = "tiny_research_suite" in str(manifest)

    L = [f"# Benchmark run {meta.get('run_id', 'unknown')}", ""]
    if meta.get("note"):
        L += [f"> **{meta['note']}**", ""]

    L += ["| | |", "| :--- | :--- |",
          f"| Manifest | `{manifest}` |",
          f"| Commit | `{meta.get('commit', 'unknown')[:12]}` |",
          f"| Tree dirty at run time | {meta.get('tree_dirty', 'unknown')} |",
          f"| Modes | {', '.join(modes)} |",
          f"| PCC consent | {meta.get('pcc', 'unknown')} |",
          f"| Pool documents | {meta.get('pool_documents', 'n/a')} |",
          f"| Pool limit per case | {meta.get('pool_limit') or 'whole pool'} |",
          f"| Fixture corpus SHA-256 | `{str(meta.get('fixture_corpus_sha256', ''))[:16]}` |",
          f"| Wall clock | {meta.get('wall_seconds', 'unknown')}s |", ""]

    if synthetic:
        L += ["> **This is the synthetic pack.** Each case is scored against an index holding only",
              "> its own expected documents, so retrieval cannot fail and its stage figures are",
              "> arithmetic rather than quality. Not comparable to an external-pack run.", ""]

    for mode in modes:
        v = verdicts(rows, mode)
        total = sum(v.values())
        scored = total - v["error"]
        L += [f"## {mode}", ""]
        if not total:
            L += ["No cases recorded.", ""]
            continue
        pct = f"{v['correct'] / scored * 100:.0f}%" if scored else "n/a"
        L += [f"**{v['correct']}/{scored} correct ({pct})**, {v['miss']} miss, "
              f"{v['hallucinated']} hallucinated, {v['error']} error, {total} attempted.", ""]

        correct_ab, seen_ab = abstention(rows, mode)
        if seen_ab:
            L += [f"Abstention: **{correct_ab}/{seen_ab}** correct. Reported separately from "
                  "accuracy on purpose; a refusal folded into an accuracy rate hides the "
                  "behaviour this app most needs to get right.", ""]

        table = stage_table(rows, mode)
        if table:
            L += ["### Retrieval, per stage", "", *table, "",
                  f"**Statistical power:** {minimum_detectable(scored)}. A flat result means "
                  "\"no change larger than that would have been detected\", never \"no "
                  "regression\".", ""]

    L += ["---", "",
          "Generated by `scripts/save_benchmark_summary.py`. Full artifacts stayed in "
          "`BenchmarkRuns/`, which is gitignored; this summary exists so the measurement "
          "survives the machine that made it.", ""]
    return "\n".join(L)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("run_dir")
    parser.add_argument("--stdout", action="store_true", help="print instead of writing")
    args = parser.parse_args()

    run_dir = Path(args.run_dir)
    if not run_dir.is_absolute():
        run_dir = REPO_ROOT / run_dir
    if not run_dir.exists():
        print(f"error: {run_dir} does not exist", file=sys.stderr)
        return 2

    meta, rows = load(run_dir)
    text = render(meta, rows)

    if args.stdout:
        print(text)
        return 0

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / f"{meta.get('run_id', run_dir.name)}.md"
    out.write_text(text)
    print(f"Wrote {out.relative_to(REPO_ROOT)} ({len(rows)} rows)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
