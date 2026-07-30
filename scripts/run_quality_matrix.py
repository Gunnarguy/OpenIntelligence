#!/usr/bin/env python3
"""Run every evaluation case under every quality mode and report the deltas.

Phase B of the benchmark plan. The question this answers is the app's central
claim: **does more compute actually buy more correctness?** Standard, Deep
Think, and Maximum cost very different amounts of time and battery, and until
now nothing measured whether that spend changes the answer.

How it works
------------
The app already supports headless benchmark runs
(`DebugRAGValidationHarness.runHeadlessIfNeeded`): given launch arguments it
constructs its own RAGService, ingests the named files, runs one query, prints
a report, and exits. This script drives that entry point once per
(case x mode) pair and parses the reports into a comparison.

Ground truth comes from the tiny_research_suite manifest -- the same source
`build_eval_dataset.py` uses -- so scoring uses the manifest's
`expected_answer_patterns` regexes rather than the prose rendering in the JSONL.

Local-only by default
---------------------
PCC consent defaults to `deny` so the matrix isolates the quality-mode
variable. Cloud routing adds network latency, quota state, and consent as
confounds; measure modes first, then re-run with `--pcc allow` to measure the
cloud axis separately.

Usage
-----
    python3 scripts/run_quality_matrix.py --app <path/to/OpenIntelligence.app>
    python3 scripts/run_quality_matrix.py --app ... --modes standard,deep-think
    python3 scripts/run_quality_matrix.py --app ... --limit 3    # smoke test

Writes `results.json` and `report.md` into --output-dir (default:
BenchmarkRuns/<timestamp>-matrix/, which is gitignored).
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST = REPO_ROOT / "Benchmarks/ResearchFixtures/tiny_research_suite/manifest.json"
ALL_MODES = ["standard", "deep-think", "maximum"]

# Report lines the harness prints, mapped to the fields we care about.
FIELD_PATTERNS = {
    "quality_mode": re.compile(r"^Quality Mode:\s*(.+)$", re.M),
    "model": re.compile(r"^Model:\s*(.+)$", re.M),
    "runtime": re.compile(r"^Runtime:\s*(.+)$", re.M),
    "confidence": re.compile(r"^Confidence:\s*([0-9.]+)$", re.M),
    "retrieved_chunks": re.compile(r"^Retrieved Chunks:\s*(\d+)$", re.M),
    "llm_calls": re.compile(r"^LLM Calls:\s*(\d+)$", re.M),
    "total_tokens": re.compile(r"^Total Tokens Across Calls:\s*(\d+)$", re.M),
    "top_similarity": re.compile(r"^Top Similarity:\s*([0-9.]+)$", re.M),
    "context_chars": re.compile(r"^Context Chars:\s*(\d+)/", re.M),
    "ingest_success": re.compile(r"^Success:\s*(\d+)/(\d+)$", re.M),
}


def parse_report(text: str) -> dict:
    """Pull structured fields out of the harness's plain-text report."""
    out: dict = {}
    for key, pattern in FIELD_PATTERNS.items():
        m = pattern.search(text)
        if not m:
            continue
        if key == "ingest_success":
            out["ingest_ok"], out["ingest_total"] = int(m.group(1)), int(m.group(2))
        elif key in {"confidence", "top_similarity"}:
            out[key] = float(m.group(1))
        elif key in {"retrieved_chunks", "llm_calls", "total_tokens", "context_chars"}:
            out[key] = int(m.group(1))
        else:
            out[key] = m.group(1).strip()

    # The answer body sits between the "Response:" marker and the next section.
    m = re.search(r"^Response:\s*\n(.*?)(?=\n[A-Z][A-Z ]{3,}\n|\Z)", text, re.S | re.M)
    out["answer"] = m.group(1).strip() if m else ""
    return out


def score(case: dict, parsed: dict) -> dict:
    """Score one run against the manifest's ground truth."""
    answer = parsed.get("answer", "")
    abstained = bool(re.search(
        r"\b(cannot|can't|could not|couldn't|unable to|not (?:enough|sufficient)|"
        r"does not (?:contain|include|provide)|no (?:information|evidence|mention)|"
        r"isn't (?:in|available)|not (?:found|available|provided|specified))\b",
        answer, re.I,
    ))

    if case["expected_behavior"] == "abstain":
        return {"expected": "abstain", "abstained": abstained, "correct": abstained}

    patterns = case.get("expected_answer_patterns") or []
    hits = [p for p in patterns if re.search(p, answer)]
    return {
        "expected": "answer",
        "abstained": abstained,
        "patterns_total": len(patterns),
        "patterns_hit": len(hits),
        # Every required pattern must appear, and abstaining is a miss.
        "correct": bool(patterns) and len(hits) == len(patterns) and not abstained,
    }


def run_one(
    app_bin: Path, case: dict, mode: str, pcc: str, timeout: int,
    storage: Path, ingest: bool,
) -> dict:
    """Launch the app headlessly for a single (case, mode) pair.

    Every run gets its own `storage` and ingests fresh. Sharing one index
    across modes via `--rag-validation-skip-ingest` was tried and rejected: it
    is much faster, but the reused index loses the document-name mapping, so
    citations degrade from `[vehicle_specs.md, p.1]` to `[Unknown, p.1]`. That
    silently corrupts the citation quality this matrix exists to measure. The
    real cost was never ingestion anyway -- it is first-run model warm-up,
    which the OS amortizes across subsequent launches.
    """
    inputs = [str(REPO_ROOT / p) for p in case["input_files"]]
    missing = [p for p in inputs if not Path(p).exists()]
    if missing:
        return {"ok": False, "error": f"missing fixtures: {missing}"}

    cmd = [
        str(app_bin),
        "--rag-validation",
        "--rag-validation-query", case["query"],
        "--rag-validation-files", ",".join(inputs),
        "--rag-validation-quality", mode,
        "--rag-validation-storage", str(storage),
        "--rag-validation-pcc-consent", pcc,
        "--rag-validation-entitlement", "lifetime",
    ]
    if not ingest:
        cmd.append("--rag-validation-skip-ingest")

    started = dt.datetime.now()
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        elapsed = (dt.datetime.now() - started).total_seconds()
        report = proc.stdout
        if "OPENINTELLIGENCE RAG VALIDATION" not in report:
            tail = (proc.stderr or report or "").strip().splitlines()[-4:]
            return {"ok": False, "seconds": elapsed, "error": "no report", "tail": tail}
        parsed = parse_report(report)
        return {"ok": True, "seconds": elapsed, "ingested": ingest, "report": report, **parsed}
    except subprocess.TimeoutExpired:
        return {"ok": False, "seconds": timeout, "error": f"timeout after {timeout}s"}


def summarize(rows: list[dict], mode: str) -> dict:
    """Aggregate every run for one mode."""
    mine = [r for r in rows if r["mode"] == mode]
    ok = [r for r in mine if r["run"].get("ok")]
    scored = [r for r in ok if r.get("score")]
    correct = [r for r in scored if r["score"]["correct"]]

    abstain_cases = [r for r in scored if r["score"]["expected"] == "abstain"]
    abstain_ok = [r for r in abstain_cases if r["score"]["correct"]]
    answer_cases = [r for r in scored if r["score"]["expected"] == "answer"]
    answer_ok = [r for r in answer_cases if r["score"]["correct"]]
    # A false answer on a negative control is the failure that matters most.
    hallucinated = [r for r in abstain_cases if not r["score"]["abstained"]]

    def mean(vals):
        vals = [v for v in vals if v is not None]
        return round(statistics.mean(vals), 2) if vals else None

    return {
        "mode": mode,
        "runs": len(mine),
        "completed": len(ok),
        "failed": len(mine) - len(ok),
        "correct": len(correct),
        "accuracy": round(len(correct) / len(scored), 3) if scored else None,
        "answer_accuracy": round(len(answer_ok) / len(answer_cases), 3) if answer_cases else None,
        "abstention_rate": round(len(abstain_ok) / len(abstain_cases), 3) if abstain_cases else None,
        "hallucinated_on_negative_control": len(hallucinated),
        "mean_seconds": mean([r["run"].get("seconds") for r in ok]),
        "mean_llm_calls": mean([r["run"].get("llm_calls") for r in ok]),
        "mean_tokens": mean([r["run"].get("total_tokens") for r in ok]),
        "mean_confidence": mean([r["run"].get("confidence") for r in ok]),
        "mean_retrieved": mean([r["run"].get("retrieved_chunks") for r in ok]),
    }


def render_markdown(summaries: list[dict], rows: list[dict], meta: dict) -> str:
    L: list[str] = []
    L.append("# Quality-Mode Matrix")
    L.append("")
    L.append(f"- Run: `{meta['run_id']}`  ·  App: `{meta['app']}`")
    L.append(f"- Cases: {meta['cases']}  ·  Modes: {', '.join(meta['modes'])}  ·  PCC consent: `{meta['pcc']}`")
    L.append(f"- Total wall clock: {meta['wall_seconds'] / 60:.1f} min")
    L.append("")
    L.append("Does more compute buy more correctness? Each mode ran the same cases "
             "against the same fixtures; the only variable is the quality mode.")
    L.append("")
    L.append("| Mode | Correct | Accuracy | Answers | Abstentions | Hallucinated | Mean s | LLM calls | Tokens |")
    L.append("| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for s in summaries:
        def fmt(v, pct=False):
            if v is None:
                return "-"
            return f"{v * 100:.0f}%" if pct else str(v)
        L.append(
            f"| {s['mode']} | {s['correct']}/{s['completed']} | {fmt(s['accuracy'], True)} | "
            f"{fmt(s['answer_accuracy'], True)} | {fmt(s['abstention_rate'], True)} | "
            f"{s['hallucinated_on_negative_control']} | {fmt(s['mean_seconds'])} | "
            f"{fmt(s['mean_llm_calls'])} | {fmt(s['mean_tokens'])} |"
        )
    L.append("")
    L.append("**Hallucinated** counts negative-control cases that produced a confident "
             "answer instead of abstaining. That column mattering more than accuracy is "
             "the whole premise of the verification gates.")
    L.append("")

    failures = [r for r in rows if not r["run"].get("ok")]
    if failures:
        L.append(f"## Failed runs ({len(failures)})")
        L.append("")
        for r in failures[:20]:
            L.append(f"- `{r['case_id']}` / {r['mode']}: {r['run'].get('error')}")
        L.append("")

    L.append("## Per-case results")
    L.append("")
    L.append("| Case | Category | " + " | ".join(meta["modes"]) + " |")
    L.append("| :--- | :--- | " + " | ".join([":---:"] * len(meta["modes"])) + " |")
    by_case: dict[str, dict] = {}
    for r in rows:
        by_case.setdefault(r["case_id"], {"category": r["category"]})[r["mode"]] = r
    for cid, entry in by_case.items():
        cells = []
        for m in meta["modes"]:
            r = entry.get(m)
            if not r or not r["run"].get("ok"):
                cells.append("ERR")
            elif r["score"]["correct"]:
                cells.append("PASS")
            elif r["score"]["expected"] == "abstain":
                cells.append("**HALLUC**")
            else:
                cells.append("miss")
        L.append(f"| `{cid}` | {entry['category']} | " + " | ".join(cells) + " |")
    L.append("")
    return "\n".join(L)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--app", required=True, help="path to built OpenIntelligence.app (or its binary)")
    ap.add_argument("--modes", default=",".join(ALL_MODES))
    ap.add_argument("--pcc", default="deny", choices=["allow", "deny"])
    ap.add_argument("--limit", type=int, default=0, help="run only the first N cases (smoke test)")
    ap.add_argument("--timeout", type=int, default=600, help="per-run timeout in seconds")
    ap.add_argument("--output-dir", default="")
    args = ap.parse_args()

    app = Path(args.app).expanduser().resolve()
    app_bin = app / "Contents/MacOS/OpenIntelligence" if app.suffix == ".app" else app
    if not app_bin.exists():
        print(f"error: app binary not found at {app_bin}", file=sys.stderr)
        return 2

    modes = [m.strip() for m in args.modes.split(",") if m.strip()]
    bad = [m for m in modes if m not in ALL_MODES]
    if bad:
        print(f"error: unknown mode(s) {bad}; choose from {ALL_MODES}", file=sys.stderr)
        return 2

    cases = json.loads(MANIFEST.read_text())["cases"]
    if args.limit:
        cases = cases[: args.limit]

    run_id = dt.datetime.now().strftime("%Y%m%d-%H%M%S") + "-matrix"
    out_dir = Path(args.output_dir) if args.output_dir else REPO_ROOT / "BenchmarkRuns" / run_id
    out_dir.mkdir(parents=True, exist_ok=True)

    total = len(cases) * len(modes)
    print(f"Quality-mode matrix: {len(cases)} cases x {len(modes)} modes = {total} runs")
    print(f"App: {app_bin}")
    print(f"PCC consent: {args.pcc}  ·  timeout: {args.timeout}s/run")
    print(f"Output: {out_dir}\n", flush=True)

    rows: list[dict] = []
    started = dt.datetime.now()
    n = 0
    for case in cases:
        for mode in modes:
            storage = Path(tempfile.mkdtemp(prefix=f"matrix-{case['id']}-{mode}-"))
            try:
                n += 1
                print(f"[{n}/{total}] {mode:11} {case['id']}", end=" ", flush=True)
                run = run_one(
                    app_bin, case, mode, args.pcc, args.timeout,
                    storage=storage, ingest=True,
                )
                row = {"case_id": case["id"], "category": case["category"], "mode": mode, "run": run}
                if run.get("ok"):
                    row["score"] = score(case, run)
                    verdict = "PASS" if row["score"]["correct"] else (
                        "HALLUC" if row["score"]["expected"] == "abstain" else "miss")
                    print(f"{verdict} ({run['seconds']:.1f}s, {run.get('llm_calls', '?')} calls)", flush=True)
                else:
                    print(f"ERROR: {run.get('error')}", flush=True)
                rows.append(row)
            finally:
                shutil.rmtree(storage, ignore_errors=True)

    wall = (dt.datetime.now() - started).total_seconds()
    summaries = [summarize(rows, m) for m in modes]
    meta = {
        "run_id": run_id, "app": str(app_bin), "cases": len(cases),
        "modes": modes, "pcc": args.pcc, "wall_seconds": round(wall, 1),
    }

    # Keep full reports out of the JSON index; write them beside it instead.
    reports_dir = out_dir / "reports"
    reports_dir.mkdir(exist_ok=True)
    for r in rows:
        if r["run"].get("report"):
            (reports_dir / f"{r['case_id']}--{r['mode']}.txt").write_text(r["run"].pop("report"))

    (out_dir / "results.json").write_text(json.dumps(
        {"meta": meta, "summaries": summaries, "rows": rows}, indent=2))
    md = render_markdown(summaries, rows, meta)
    (out_dir / "report.md").write_text(md)

    print("\n" + md)
    print(f"\nWrote {out_dir}/results.json and report.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
