#!/usr/bin/env python3
"""Build a single table of every benchmark run on disk, newest first.

`BenchmarkRuns/LEDGER.md` is prose: it explains what each run settled and records which analyses
were wrong, which is the part that matters and the part a table cannot hold. What it cannot do is
show the shape of thirty runs at once — whether a stage is trending, which config produced which
number, or how often a run was even comparable.

So this is deliberately NOT a replacement for the ledger. It is an index over it. Every row carries
the config that produced it, because the single most expensive mistake in this project's benchmark
history was comparing two runs whose `pool_limit` differed (a "4-7x performance regression" that was
withdrawn). Config is shown so that a reader who compares two rows can see immediately whether the
comparison is legitimate.

Columns are chosen to make the incomparable obvious rather than to make the table pretty:
`cases`, `pool`, `seed`, `temp` and `vw` differing between two rows means those rows should not be
compared on accuracy at all.

Usage:
    python3 scripts/benchmark_progression.py                 # markdown to stdout
    python3 scripts/benchmark_progression.py --out FILE.md   # write to a file
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path

RUNS = Path(__file__).resolve().parent.parent / "BenchmarkRuns"


def stage(rows: list[dict], name: str, metric: str) -> float | None:
    for r in rows or []:
        if r.get("stage") == name:
            return r.get(metric)
    return None


def fmt(v, nd=3) -> str:
    if v is None:
        return "—"
    if isinstance(v, float):
        return f"{v:.{nd}f}"
    return str(v)


def suspect_flag(meta: dict, summary: dict) -> str:
    """Mark runs whose wall clock proves generation never really happened.

    `lexical-survival` completed 8 cases in 3 minutes on 2026-08-20 because Foundation Models was
    wedged machine-wide and every answer was the graceful-degradation fallback text. Its numbers are
    meaningless, the ledger says so in bold, and a table that silently lists them next to real runs
    would undo that warning for anyone who reads the table first.

    A real case is minutes: the fastest legitimate case observed is ~177s standard, ~200s
    deep-think. Under 60s per case, generation did not run. This is a heuristic and is labelled
    SUSPECT rather than INVALID — it flags for a human, it does not adjudicate.
    """
    runs = summary.get("runs") or 0
    wall = meta.get("wall_seconds") or 0
    if runs and wall and (wall / runs) < 60:
        return "SUSPECT"
    return ""


def collect() -> list[dict]:
    out = []
    for d in sorted(RUNS.iterdir()):
        rj = d / "results.json"
        if not d.is_dir() or not rj.exists():
            continue
        try:
            data = json.loads(rj.read_text())
        except Exception:
            continue
        meta = data.get("meta", {}) or {}
        cfg = {}
        cj = d / "run_config.json"
        if cj.exists():
            try:
                cfg = json.loads(cj.read_text())
            except Exception:
                cfg = {}
        summaries = data.get("summaries") or []
        if isinstance(summaries, dict):  # tolerate the older shape
            summaries = [dict(v, mode=k) for k, v in summaries.items()]
        for s in summaries:
            mode = s.get("mode", "?")
            st = (data.get("stage_summaries") or {}).get(mode) or []
            out.append({
                "run": d.name,
                "mode": mode,
                "when": (meta.get("run_id") or "")[:8],
                "commit": (cfg.get("commit") or "")[:7],
                "cases": s.get("runs"),
                "done": s.get("completed"),
                "pool": cfg.get("pool_limit"),
                "seed": cfg.get("seed"),
                "temp": cfg.get("temperature"),
                "vw": cfg.get("vector_weight"),
                "acc": s.get("accuracy"),
                "correct": s.get("correct"),
                "lex_mrr": stage(st, "lexical", "mrr"),
                "fus_mrr": stage(st, "fusion", "mrr"),
                "rr_mrr": stage(st, "rerank", "mrr"),
                "fin_r1": stage(st, "final", "r1"),
                "fin_r10": stage(st, "final", "r10"),
                "fin_mrr": stage(st, "final", "mrr"),
                "wall_min": round((meta.get("wall_seconds") or 0) / 60) or None,
                "flag": suspect_flag(meta, s),
            })
    out.sort(key=lambda r: (r["when"], r["run"], r["mode"]), reverse=True)
    return out


def render(rows: list[dict]) -> str:
    L = []
    L.append("# Benchmark progression")
    L.append("")
    L.append(f"Generated {dt.datetime.now():%Y-%m-%d %H:%M} by `scripts/benchmark_progression.py`. "
             f"{len(rows)} run/mode pairs across {len({r['run'] for r in rows})} runs.")
    L.append("")
    L.append("**Read the config columns before comparing any two rows.** Runs differing in "
             "`cases`, `pool`, `seed`, `temp` or `vw` are not comparable on accuracy — a withdrawn "
             "\"4-7x performance regression\" in `LEDGER.md` was exactly this mistake. For a real "
             "comparison use `scripts/compare_benchmark_runs.py`, which pairs by `case_id` and "
             "prints a control line.")
    L.append("")
    L.append("`LEDGER.md` remains authoritative for *what each run settled* and for the analyses "
             "that turned out to be wrong. This table is an index, not a replacement.")
    L.append("")
    hdr = ["", "run", "mode", "commit", "cases", "pool", "seed", "temp", "vw",
           "correct", "acc", "lexical MRR", "fusion MRR", "rerank MRR",
           "final r@1", "final r@10", "final MRR", "min"]
    L.append("| " + " | ".join(hdr) + " |")
    L.append("|" + "|".join([" :-- ", " :-- ", " :-- ", " :-- "] + [" --: "] * (len(hdr) - 4)) + "|")
    for r in rows:
        L.append("| " + " | ".join([
            "⚠" if r["flag"] else "", r["run"], r["mode"], r["commit"] or "—",
            f'{fmt(r["done"],0)}/{fmt(r["cases"],0)}',
            fmt(r["pool"], 0), fmt(r["seed"], 0), fmt(r["temp"], 1),
            fmt(r["vw"], 2) if r["vw"] is not None else "dflt",
            fmt(r["correct"], 0), fmt(r["acc"], 3),
            fmt(r["lex_mrr"]), fmt(r["fus_mrr"]), fmt(r["rr_mrr"]),
            fmt(r["fin_r1"]), fmt(r["fin_r10"]), fmt(r["fin_mrr"]),
            fmt(r["wall_min"], 0),
        ]) + " |")
    L.append("")
    n_sus = sum(1 for r in rows if r["flag"])
    if n_sus:
        L.append(f"**⚠ marks {n_sus} run/mode pair(s) averaging under 60s per case — generation "
                 "almost certainly did not run.** The known instance is `lexical-survival`, taken "
                 "while Foundation Models was wedged machine-wide; every answer was fallback text. "
                 "Treat any flagged row as unmeasured, not as a low score.")
        L.append("")
    L.append("**Columns.** `acc` is exact-match against the fixture's `expected_answer_patterns`; "
             "it is a floor, not a quality score. `final r@1`/`r@10` are **document-level** — they "
             "credit a whole document when any of its chunks appears, which inflated `r@1` to 1.000 "
             "on runs where a document summary was injected.")
    L.append("")
    L.append("**Do not read a one- or two-case accuracy difference as a result.** Two runs of the "
             "same build (`rescue-position-fix` and `passage-level-1`, differing only by debug "
             "output printed after generation) scored 11/24 and 10/24 with an identical lexical "
             "control. **\u00b11 case at n=24 is the measured noise floor**, so nothing smaller than "
             "roughly a 4-case swing resolves in the `correct`/`acc` columns. The stage columns are "
             "far more stable \u2014 22 of those 24 cases were identical at every retrieval stage \u2014 "
             "and are what a change should be judged on. `LEDGER.md` carries the decomposition.")
    return "\n".join(L)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="")
    a = ap.parse_args()
    text = render(collect())
    if a.out:
        Path(a.out).write_text(text)
        print(f"wrote {a.out}")
    else:
        print(text)


if __name__ == "__main__":
    main()
