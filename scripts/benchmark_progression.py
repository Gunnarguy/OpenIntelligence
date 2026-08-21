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


def reconstruct(d: Path) -> dict | None:
    """Rebuild a run summary from `results.jsonl` when `results.json` is absent.

    Added 2026-08-21 after this script was found to be doing the thing it exists to prevent. Of 79
    run directories on disk, 65 carried `results.json` and the collector `continue`d silently past
    the other 14 — so a table whose entire purpose is "show every run" was quietly showing 82% of
    them, with no count of what it dropped and no way for a reader to tell.

    Eleven of those 14 still hold `results.jsonl`, one JSON object per case, which is the raw
    evidence the ledger cites. A run whose aggregate file is missing is usually one that was killed
    before the harness wrote its summary, and those are exactly the runs worth seeing rather than
    hiding. Reconstructed rows are marked so nobody mistakes a recomputed aggregate for one the
    harness wrote.
    """
    jl = d / "results.jsonl"
    if not jl.exists():
        return None
    by_mode: dict[str, list[dict]] = {}
    for line in jl.read_text(errors="replace").splitlines():
        try:
            r = json.loads(line)
        except Exception:
            continue
        if isinstance(r, dict) and r.get("case_id"):
            by_mode.setdefault(r.get("mode") or "?", []).append(r)
    if not by_mode:
        return None
    summaries, stages = [], {}
    for mode, rows in by_mode.items():
        correct = sum(1 for r in rows if (r.get("score") or {}).get("correct"))
        summaries.append({
            "mode": mode, "runs": len(rows), "completed": len(rows),
            "correct": correct, "accuracy": correct / len(rows) if rows else None,
        })
        agg: dict[str, list] = {}
        for r in rows:
            sm = (r.get("run") or {}).get("stage_metrics") or {}
            if isinstance(sm, list):
                sm = {x.get("stage"): x for x in sm if isinstance(x, dict)}
            for stage, vals in (sm or {}).items():
                if isinstance(vals, dict):
                    agg.setdefault(stage, []).append(vals)
        stages[mode] = [
            {"stage": st,
             **{m: (sum(v.get(m) or 0 for v in vs) / len(vs)) for m in ("r1", "r5", "r10", "mrr")}}
            for st, vs in agg.items() if vs
        ]
    return {"meta": {}, "summaries": summaries, "stage_summaries": stages, "_reconstructed": True}


def collect() -> tuple[list[dict], list[str]]:
    out: list[dict] = []
    unreadable: list[str] = []
    legacy: list[dict] = []
    for d in sorted(RUNS.iterdir()):
        if not d.is_dir():
            continue
        rj = d / "results.json"
        data = None
        if rj.exists():
            try:
                data = json.loads(rj.read_text())
            except Exception:
                data = None
        if data is None:
            data = reconstruct(d)
        if data is not None and "summaries" not in data and isinstance(data.get("cases"), list):
            # Pre-`summaries` harness schema, all from 2026-07-03. Counted and named below rather
            # than tabulated: every one is a 1-9 case bring-up run and not a single case ever
            # passed, so 25 rows of zeros would bury the runs that mean something. Silently
            # dropping them, which is what this script did until 2026-08-21, is the worse option.
            sm = data.get("summary") or {}
            legacy.append({"run": d.name, "total": sm.get("total") or len(data["cases"]),
                           "scored": sm.get("scored") or 0, "passed": sm.get("passed") or 0})
            continue
        if data is None:
            # Never drop a run silently. A directory with neither file is still a run that was
            # started, and the reader is entitled to know it exists and holds nothing.
            unreadable.append(d.name)
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
                "recon": bool(data.get("_reconstructed")),
            })
    out.sort(key=lambda r: (r["when"], r["run"], r["mode"]), reverse=True)
    return out, unreadable, legacy


def render(rows: list[dict], unreadable: list[str], legacy: list[dict]) -> str:
    L = []
    L.append("# Benchmark progression")
    L.append("")
    n_runs = len({r["run"] for r in rows})
    total_dirs = n_runs + len(unreadable) + len(legacy)
    n_recon = len({r["run"] for r in rows if r.get("recon")})
    L.append(f"Generated {dt.datetime.now():%Y-%m-%d %H:%M} by `scripts/benchmark_progression.py`. "
             f"{len(rows)} run/mode pairs across {n_runs} runs, "
             f"of {total_dirs} run directories on disk — every one accounted for below.")
    if n_recon or unreadable or legacy:
        L.append("")
        if n_recon:
            L.append(f"**† marks {n_recon} run(s) rebuilt from `results.jsonl`** because the harness "
                     "never wrote a `results.json` — normally a run killed before it finished. The "
                     "per-case data is real; the aggregates in those rows were recomputed here, not "
                     "written by the harness, and `min` is unavailable for them.")
        if legacy:
            L.append("")
            tp = sum(x["passed"] for x in legacy)
            tc = sum(x["total"] for x in legacy)
            L.append(f"**{len(legacy)} run(s) predate the current results schema** and are counted "
                     f"here rather than tabulated: all are from 2026-07-03, 1-9 cases each, "
                     f"{tc} cases total, and **{tp} passed**. They are harness bring-up, not "
                     "measurement, and 25 rows of zeros would bury the runs that mean something. "
                     "Named so the count reconciles: "
                     + ", ".join(f"`{x['run']}`" for x in sorted(legacy, key=lambda z: z["run"])) + ".")
        if unreadable:
            L.append("")
            L.append(f"**{len(unreadable)} run director(ies) hold no results data** and cannot be "
                     "tabulated (`latest` holds only a dashboard; the other two are empty): " + ", ".join(f"`{u}`" for u in unreadable) + ". They are listed "
                     "rather than dropped, because a table that silently omits runs is the exact "
                     "failure this file exists to prevent.")
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
            ("⚠" if r["flag"] else "") + ("†" if r.get("recon") else ""),
            r["run"], r["mode"], r["commit"] or "—",
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
    rows, unreadable, legacy = collect()
    text = render(rows, unreadable, legacy)
    if a.out:
        Path(a.out).write_text(text)
        print(f"wrote {a.out}")
    else:
        print(text)


if __name__ == "__main__":
    main()
