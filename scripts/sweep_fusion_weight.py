#!/usr/bin/env python3
"""Score a different hybrid fusion weight against a finished benchmark run, without re-running it.

Why this exists
===============
`run_quality_matrix.py` answers exactly one fusion weight per invocation, and an invocation is a
full pipeline execution: ingest, retrieve, generate, for every case. On `qasper_external_v1` that is
about 4.7 hours and the whole machine. But the fusion weight is a parameter of an arithmetic step
that runs *after* retrieval, so paying a pipeline execution per value is paying for the wrong thing.

`RAGEngine.reciprocalRankFusion` is a pure function of the two arms' rank orders, the weight, and
k=60. `DebugRAGValidationHarness` records both arms in rank order in the report's STAGE SOURCES
block, so the fusion can be replayed here for any weight, across the whole range, in seconds.

On recomputing metrics in Python
================================
`run_quality_matrix.parse_stage_metrics` deliberately transports Swift's numbers rather than
recomputing them, on the grounds that two implementations of one metric drift and the one that
drifts silently is the one nobody is testing. That objection is correct, and it applies to this
file, which has no choice but to compute metrics for weights the app never ran.

So this script does not ask to be trusted. Calibration replays the fusion at the weight the run
actually used and checks it against the app's own recorded output, two ways:

  1. the replayed fusion ORDER against the recorded `fusion` stage, chunk id by chunk id
  2. the metrics recomputed here against the Swift STAGE METRICS row for `fusion`

The sweep is refused unless both pass. That turns "a second implementation that can drift" into
"a second implementation checked against the first on every invocation".

Requires the STAGE SOURCES format that carries ids (`<chunkId>#<documentId>#<name>`). Runs recorded
before that change emit `(unnamed)` for the five pre-rerank stages and cannot be swept; the script
says so rather than producing a plausible curve from nothing.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

RRF_K = 60  # RAGEngine.reciprocalRankFusion call site passes k: 60.

STAGE_HEADER = "stage\tresults\trelevant\tr1\tr3\tr5\tr10\tmrr\tndcg5\tndcg10\tp5"


# --------------------------------------------------------------------------------------
# Parsing
# --------------------------------------------------------------------------------------


class ReportFormatError(RuntimeError):
    """The report predates id-carrying STAGE SOURCES, or is otherwise unsweepable."""


def parse_expected_ids(text: str) -> list[str]:
    """Ground truth in the resolved form scoring actually used.

    `ExpectedSources` is the manifest's filenames. `ExpectedSourceIds` is what each one resolved to
    and is the only form that joins to the ids in STAGE SOURCES. An entry that is still a filename
    here never resolved to an ingested document, and is kept: it scores zero, which is the correct
    answer and is worth being able to see.
    """
    match = re.search(r"^ExpectedSourceIds:\s*(.*)$", text, re.MULTILINE)
    if not match:
        raise ReportFormatError(
            "no ExpectedSourceIds line: this report predates the id-carrying harness format"
        )
    return [part.strip() for part in match.group(1).split("|") if part.strip()]


def parse_stage_sources(text: str) -> dict[str, list[tuple[str, str, str]]]:
    """STAGE SOURCES -> {stage: [(chunk_id, document_id, name), ...]} in rank order.

    Entries are `<chunkId>#<documentId>#<name>`, split on the first two `#` only, because a
    filename is allowed to contain one and the ids are what must survive intact.
    """
    if "STAGE SOURCES" not in text:
        raise ReportFormatError("no STAGE SOURCES block in report")
    block = text.split("STAGE SOURCES", 1)[1].lstrip("\n")
    stages: dict[str, list[tuple[str, str, str]]] = {}
    for line in block.splitlines():
        if not line.strip():
            break
        parts = line.split("\t")
        if len(parts) != 2:
            break
        stage, joined = parts
        entries: list[tuple[str, str, str]] = []
        for item in joined.split("|"):
            if not item:
                continue
            fields = item.split("#", 2)
            if len(fields) != 3:
                raise ReportFormatError(
                    f"stage {stage!r} carries {item!r}, which is not <chunkId>#<documentId>#<name>. "
                    "This run predates the id-carrying format and cannot be swept."
                )
            entries.append((fields[0], fields[1], fields[2]))
        stages[stage] = entries
    return stages


def parse_stage_metrics(text: str) -> dict[str, dict[str, float]]:
    """The Swift-computed numbers, transported not recomputed. Used only to check this file."""
    if STAGE_HEADER not in text:
        return {}
    block = text.split(STAGE_HEADER, 1)[1].lstrip("\n")
    out: dict[str, dict[str, float]] = {}
    for line in block.splitlines():
        if not line.strip():
            break
        parts = line.rstrip().split("\t")
        if len(parts) != 11:
            break
        out[parts[0]] = {
            "results": int(parts[1]),
            "relevant": int(parts[2]),
            "r1": float(parts[3]),
            "r3": float(parts[4]),
            "r5": float(parts[5]),
            "r10": float(parts[6]),
            "mrr": float(parts[7]),
        }
    return out


def load_reports(run_dir: Path) -> list[tuple[str, str]]:
    """[(case_id, report_text)] from either artifact layout.

    A finished run moves each report out to `reports/<case>--<mode>.txt` and drops the inline copy.
    A paused one still carries it inside `results.jsonl`. Both are normal and both are read here,
    because the runs worth sweeping include the ones that were interrupted.
    """
    found: list[tuple[str, str]] = []
    reports_dir = run_dir / "reports"
    if reports_dir.is_dir():
        for path in sorted(reports_dir.glob("*.txt")):
            found.append((path.stem, path.read_text(errors="replace")))
    if found:
        return found

    checkpoint = run_dir / "results.jsonl"
    if not checkpoint.is_file():
        raise SystemExit(f"no reports/ and no results.jsonl under {run_dir}")
    for line in checkpoint.read_text(errors="replace").splitlines():
        if not line.strip():
            continue
        row = json.loads(line)
        report = (row.get("run") or {}).get("report")
        if report:
            found.append((row.get("case_id", "?"), report))
    return found


# --------------------------------------------------------------------------------------
# Fusion replay
# --------------------------------------------------------------------------------------


def replay_fusion(
    vector: list[tuple[str, str, str]],
    lexical: list[tuple[str, str, str]],
    vector_weight: float,
    k: int = RRF_K,
) -> list[tuple[str, str, str]]:
    """Reproduce `RAGEngine.reciprocalRankFusion` for an arbitrary weight.

    Mirrors that function deliberately, including the parts that look odd:

    - It returns nothing at all when the vector arm is empty (`guard !vectorResults.isEmpty`).
      Lexical hits are discarded in that case. Reproduced rather than corrected, because the point
      here is to predict what the app would do, not what it should do.
    - Candidates are the UNION, ordered vector-first, then lexical-only arrivals.
    - Contribution is `weight / (k + rank + 1)` with rank 0-based on each arm independently.

    One deliberate divergence: the app's final `sorted(by:)` has no tiebreak and Swift's sort is not
    stable, so chunks on equal fused scores come out in an unspecified order there. This sorts ties
    by chunk id so a sweep is reproducible. `count_top_ties` reports how much of the top of the list
    that affects, because where it is large the comparison between weights is correspondingly soft.
    """
    if not vector:
        return []

    scores: dict[str, float] = {}
    for rank, (chunk_id, _, _) in enumerate(vector):
        scores[chunk_id] = scores.get(chunk_id, 0.0) + vector_weight / (k + rank + 1)

    keyword_weight = 1.0 - vector_weight
    for rank, (chunk_id, _, _) in enumerate(lexical):
        scores[chunk_id] = scores.get(chunk_id, 0.0) + keyword_weight / (k + rank + 1)

    seen = {chunk_id for chunk_id, _, _ in vector}
    candidates = list(vector) + [e for e in lexical if e[0] not in seen]
    return sorted(candidates, key=lambda e: (-scores.get(e[0], 0.0), e[0]))


def count_top_ties(
    ranked: list[tuple[str, str, str]],
    vector: list[tuple[str, str, str]],
    lexical: list[tuple[str, str, str]],
    vector_weight: float,
    k: int = RRF_K,
    depth: int = 10,
) -> int:
    """How many of the top `depth` sit on a fused score shared with another candidate."""
    scores: dict[str, float] = {}
    for rank, (chunk_id, _, _) in enumerate(vector):
        scores[chunk_id] = scores.get(chunk_id, 0.0) + vector_weight / (k + rank + 1)
    for rank, (chunk_id, _, _) in enumerate(lexical):
        scores[chunk_id] = scores.get(chunk_id, 0.0) + (1.0 - vector_weight) / (k + rank + 1)
    top = ranked[:depth]
    return sum(
        1
        for entry in top
        if sum(1 for other in ranked if abs(scores.get(other[0], 0.0) - scores.get(entry[0], 0.0)) < 1e-12) > 1
    )


def infer_case_weight(
    case: dict,
    k: int = RRF_K,
    step: float = 0.01,
) -> tuple[float, float] | None:
    """Recover the fusion weight a case actually used, by fitting its recorded `fusion` order.

    Needed because the effective weight is not a run-level constant and is not written to the
    report. `QueryProfile.adjustedHybridWeights` starts from the container's `vectorWeight` preset
    (0.50, 0.75, 0.6 or 0.45 depending on preset), applies a per-query delta from
    `SearchIntent.weightAdjustment`, then clamps to [0.35, 0.65]. Two cases in one run can therefore
    fuse at different weights, and calibrating the replay against a single global value is wrong.

    The recorded `fusion` stage is the answer key. Replaying the two arms across the whole weight
    range and keeping whichever weight best reproduces that recorded order both calibrates the
    replay and tells you what the app actually did. A high agreement score means the replay models
    the real fusion; a low one means it does not, and no sweep built on it should be believed.

    Returns (weight, agreement) or None when the case lacks the stages to fit.
    """
    vector = case["stages"].get("vector", [])
    lexical = case["stages"].get("lexical", [])
    recorded = case["stages"].get("fusion", [])
    if not vector or not recorded:
        return None

    depth = min(10, len(recorded))
    if depth == 0:
        return None

    best_weight, best_agreement = 0.0, -1.0
    steps = int(round(1.0 / step))
    for i in range(steps + 1):
        weight = i * step
        replay = replay_fusion(vector, lexical, weight, k)
        hits = sum(
            1
            for rank in range(min(depth, len(replay)))
            if replay[rank][0] == recorded[rank][0]
        )
        agreement = hits / depth
        if agreement > best_agreement:
            best_weight, best_agreement = round(weight, 4), agreement
    return best_weight, best_agreement


# --------------------------------------------------------------------------------------
# Metrics, matching RetrievalStageMetrics.score exactly
# --------------------------------------------------------------------------------------


def credited_relevance(ranked: list[tuple[str, str, str]], expected: set[str]) -> list[bool]:
    """Each expected DOCUMENT credited once, at its first matching chunk.

    This mirrors `RetrievalRelevanceJudge.creditedRelevanceVector`. Crediting every chunk of a
    matching document instead is the defect that made nDCG@5 report 2.131 on a metric defined over
    [0, 1], and it inflates recall the same way. `k` still counts chunks, because chunks are what
    reach the model; only the credit is deduplicated.
    """
    credited: set[str] = set()
    out: list[bool] = []
    for _, document_id, _ in ranked:
        if document_id in expected and document_id not in credited:
            credited.add(document_id)
            out.append(True)
        else:
            out.append(False)
    return out


def score_ranking(ranked: list[tuple[str, str, str]], expected: set[str]) -> dict[str, float]:
    """Recall@{1,3,5,10} and RR@10 for one case.

    nDCG is deliberately absent. Recall and reciprocal rank have one unambiguous definition each and
    are enough to order fusion weights against one another; nDCG needs the gain and ideal-gain shape
    to agree with Swift's exactly, and every additional recomputed metric is additional surface for
    the drift this file is trying not to introduce. The Swift figure remains authoritative for nDCG.
    """
    relevance = credited_relevance(ranked, expected)
    total = len(expected)
    if total == 0:
        return {"r1": 0.0, "r3": 0.0, "r5": 0.0, "r10": 0.0, "mrr": 0.0}

    def recall(at: int) -> float:
        return sum(1 for flag in relevance[:at] if flag) / total

    reciprocal = 0.0
    for index, flag in enumerate(relevance[:10]):
        if flag:
            reciprocal = 1.0 / (index + 1)
            break

    return {
        "r1": recall(1),
        "r3": recall(3),
        "r5": recall(5),
        "r10": recall(10),
        "mrr": reciprocal,
    }


# --------------------------------------------------------------------------------------
# Calibration
# --------------------------------------------------------------------------------------


def calibrate(cases: list[dict], actual_weight: float, k: int, tolerance: float) -> dict:
    """Check the replay against the app's own recorded fusion, before trusting any other weight.

    Two independent checks, because they fail for different reasons. Order agreement catches a wrong
    fusion formula, a wrong k, or the lexical arm being recorded in a different order than the one
    RRF consumed. Metric agreement catches a correct fusion scored the wrong way.
    """
    order_hits = order_total = 0
    metric_deltas: list[float] = []
    compared = 0

    for case in cases:
        vector, lexical = case["stages"].get("vector", []), case["stages"].get("lexical", [])
        recorded = case["stages"].get("fusion", [])
        if not recorded:
            continue
        replayed = replay_fusion(vector, lexical, actual_weight, k)
        depth = min(10, len(recorded), len(replayed))
        if depth == 0:
            continue
        compared += 1
        for i in range(depth):
            order_total += 1
            if recorded[i][0] == replayed[i][0]:
                order_hits += 1

        swift = case["metrics"].get("fusion")
        if swift:
            mine = score_ranking(replayed, case["expected"])
            for key in ("r1", "r3", "r5", "r10", "mrr"):
                metric_deltas.append(abs(mine[key] - swift[key]))

    return {
        "cases_compared": compared,
        "order_agreement": (order_hits / order_total) if order_total else 0.0,
        "max_metric_delta": max(metric_deltas) if metric_deltas else 0.0,
        "metric_ok": (max(metric_deltas) if metric_deltas else 0.0) <= tolerance,
    }


# --------------------------------------------------------------------------------------
# Self test
# --------------------------------------------------------------------------------------


def self_test() -> int:
    """Verify the fusion arithmetic against a hand-computed example.

    This exists because the id-carrying report format is new: until a run is recorded with it there
    is no artifact to calibrate against, and an uncalibrated script that has never been exercised at
    all is worse than no script. This checks the part that is pure arithmetic.
    """
    failures = 0

    def chunk(n: str, doc: str) -> tuple[str, str, str]:
        return (f"chunk-{n}", f"doc-{doc}", f"{doc}.md")

    vector = [chunk("a", "1"), chunk("b", "2")]
    lexical = [chunk("b", "2"), chunk("c", "3")]

    # w=0.5, k=60. a: 0.5/61. b: 0.5/62 + 0.5/61. c: 0.5/62.
    # b is the only chunk scoring on both arms, so it must lead at an even weight.
    ranked = replay_fusion(vector, lexical, 0.5)
    if [e[0] for e in ranked] != ["chunk-b", "chunk-a", "chunk-c"]:
        print(f"FAIL even-weight order: {[e[0] for e in ranked]}")
        failures += 1

    # At w=1.0 the lexical arm contributes nothing, so lexical-only `c` must fall to last.
    ranked = replay_fusion(vector, lexical, 1.0)
    if [e[0] for e in ranked] != ["chunk-a", "chunk-b", "chunk-c"]:
        print(f"FAIL vector-only order: {[e[0] for e in ranked]}")
        failures += 1

    # Empty vector arm returns nothing, reproducing RAGEngine's guard rather than correcting it.
    if replay_fusion([], lexical, 0.5) != []:
        print("FAIL empty-vector guard")
        failures += 1

    # Credited relevance: two chunks of one expected document credit once, at the first.
    dupes = [chunk("a", "1"), chunk("b", "1"), chunk("c", "2")]
    if credited_relevance(dupes, {"doc-1", "doc-2"}) != [True, False, True]:
        print("FAIL credited relevance dedup")
        failures += 1

    # The 2.131 case: one expected doc, three of its chunks up top. Recall must not exceed 1.0.
    triple = [chunk("a", "1"), chunk("b", "1"), chunk("c", "1")]
    if score_ranking(triple, {"doc-1"})["r5"] != 1.0:
        print("FAIL recall ceiling")
        failures += 1

    # MRR is cut at rank 10: a first hit at rank 11 scores zero, not 1/11.
    deep = [chunk(str(i), "9") for i in range(10)] + [chunk("hit", "1")]
    if score_ranking(deep, {"doc-1"})["mrr"] != 0.0:
        print("FAIL rank-10 cutoff")
        failures += 1

    print("self-test: OK" if not failures else f"self-test: {failures} FAILED")
    return failures


# --------------------------------------------------------------------------------------
# Entry point
# --------------------------------------------------------------------------------------


def parse_weight_spec(spec: str) -> list[float]:
    start, stop, step = (float(part) for part in spec.split(":"))
    out, current = [], start
    while current <= stop + 1e-9:
        out.append(round(current, 6))
        current += step
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("run_dir", nargs="?", type=Path, help="a directory under BenchmarkRuns/")
    parser.add_argument("--weights", default="0.0:1.0:0.05", help="start:stop:step, default 0.0:1.0:0.05")
    parser.add_argument("--k", type=int, default=RRF_K, help=f"RRF constant, default {RRF_K}")
    parser.add_argument(
        "--actual-weight",
        type=float,
        help="the --vector-weight this run used, for calibration. Read from run_config.json if absent.",
    )
    parser.add_argument("--tolerance", type=float, default=1e-4, help="max metric delta in calibration")
    parser.add_argument(
        "--min-order-agreement",
        type=float,
        default=0.95,
        help="minimum top-10 order agreement with the recorded fusion before a sweep is emitted",
    )
    parser.add_argument("--force", action="store_true", help="emit the sweep even if calibration fails")
    parser.add_argument("--self-test", action="store_true", help="check the fusion arithmetic and exit")
    args = parser.parse_args()

    if args.self_test:
        return 1 if self_test() else 0
    if not args.run_dir:
        parser.error("run_dir is required unless --self-test is given")

    reports = load_reports(args.run_dir)
    if not reports:
        raise SystemExit(f"no reports found under {args.run_dir}")

    cases: list[dict] = []
    unsweepable = 0
    first_error = ""
    for case_id, text in reports:
        try:
            cases.append({
                "case_id": case_id,
                "expected": set(parse_expected_ids(text)),
                "stages": parse_stage_sources(text),
                "metrics": parse_stage_metrics(text),
            })
        except ReportFormatError as error:
            unsweepable += 1
            first_error = first_error or str(error)

    print(f"run: {args.run_dir}")
    print(f"cases: {len(cases)} sweepable, {unsweepable} not")
    if not cases:
        print()
        print(f"Nothing to sweep. {first_error}")
        print("Runs recorded before the id-carrying STAGE SOURCES format cannot be swept: their")
        print("pre-rerank stages hold `(unnamed)` placeholders, not identities. One fresh run fixes")
        print("this permanently, and every later weight question is then free.")
        return 2

    actual = args.actual_weight
    if actual is None:
        config = args.run_dir / "run_config.json"
        if config.is_file():
            actual = json.loads(config.read_text()).get("vector_weight")
    # Track which path supplied the weight. A run pinned with --vector-weight has one true weight
    # and should be checked against it; a run without one has no such value and is fitted instead.
    # Testing `args.actual_weight` here instead would skip calibration for a pinned run whose
    # weight came from run_config.json rather than the command line.
    inferred = actual is None
    if inferred:
        # No single weight to calibrate against. This is the normal case for a run that did not
        # pass --vector-weight: the effective weight is per query, so recover it per case by
        # fitting each recorded `fusion` order instead of demanding the operator supply one.
        print()
        print("No fixed weight for this run, so recovering the effective weight per case by")
        print("fitting each recorded fusion order.")
        fits = [(c["case_id"], infer_case_weight(c, args.k)) for c in cases]
        fitted = [(cid, w, a) for cid, r in fits if r for w, a in [r]]
        if not fitted:
            print("No case had both a vector arm and a recorded fusion stage. Cannot calibrate.")
            if not args.force:
                return 2
        else:
            weights = sorted(w for _, w, _ in fitted)
            agreements = sorted(a for _, _, a in fitted)
            median_w = weights[len(weights) // 2]
            median_a = agreements[len(agreements) // 2]
            poor = [cid for cid, _, a in fitted if a < args.min_order_agreement]
            print(
                f"  fitted {len(fitted)} cases: weight median {median_w:.2f}, "
                f"range {weights[0]:.2f} to {weights[-1]:.2f}"
            )
            print(
                f"  order agreement: median {median_a:.1%}, "
                f"{len(poor)} case(s) below {args.min_order_agreement:.0%}"
            )
            actual = median_w
            if median_a < args.min_order_agreement:
                print()
                print("Calibration FAILED. The replay does not reproduce the app's own recorded")
                print("fusion even at its best-fit weight, so every number below would be")
                print("unfounded. Do not read a curve out of this. Check first whether the lexical")
                print("arm is recorded pre-sort in a different order than RRF consumed, and whether")
                print("k is 60 on the path this run took.")
                if not args.force:
                    return 1
    if not inferred and actual is not None:
        result = calibrate(cases, actual, args.k, args.tolerance)
        print(
            f"calibration at w={actual}: order {result['order_agreement']:.1%} over "
            f"{result['cases_compared']} cases, max metric delta {result['max_metric_delta']:.6f}"
        )
        ok = result["order_agreement"] >= args.min_order_agreement and result["metric_ok"]
        if not ok:
            print()
            print("Calibration FAILED. This replay does not reproduce the app's own recorded fusion,")
            print("so every number it would print about another weight is unfounded. Do not read a")
            print("curve out of this. Likely causes, in the order worth checking:")
            print("  - the lexical arm is recorded pre-sort and RRF consumed a different order")
            print("  - k is not 60 on the path this run took")
            print("  - the run used a weight other than the one given here")
            if not args.force:
                return 1
            print("Continuing anyway because --force was given. The output below is not evidence.")

    print()
    header = f"{'weight':>8}  {'MRR@10':>8}  {'R@1':>7}  {'R@5':>7}  {'R@10':>7}  {'ties':>5}"
    print(header)
    print("-" * len(header))

    rows = []
    for weight in parse_weight_spec(args.weights):
        totals = {"r1": 0.0, "r5": 0.0, "r10": 0.0, "mrr": 0.0}
        ties = 0
        scored = 0
        for case in cases:
            vector, lexical = case["stages"].get("vector", []), case["stages"].get("lexical", [])
            ranked = replay_fusion(vector, lexical, weight, args.k)
            if not ranked:
                continue
            scored += 1
            values = score_ranking(ranked, case["expected"])
            for key in totals:
                totals[key] += values[key]
            ties += count_top_ties(ranked, vector, lexical, weight, args.k)
        if not scored:
            continue
        row = {key: value / scored for key, value in totals.items()}
        row["weight"], row["ties"] = weight, ties
        rows.append(row)
        marker = "  <- run" if actual is not None and abs(weight - actual) < 1e-9 else ""
        print(
            f"{weight:>8.2f}  {row['mrr']:>8.4f}  {row['r1']:>7.4f}  "
            f"{row['r5']:>7.4f}  {row['r10']:>7.4f}  {ties:>5}{marker}"
        )

    if rows:
        best = max(rows, key=lambda r: r["mrr"])
        print()
        print(f"best MRR@10 at weight {best['weight']:.2f}: {best['mrr']:.4f}")
        print()
        print("This is RETRIEVAL quality only. Answer accuracy cannot be recomputed here, because")
        print("generation ran once against one selection of chunks. Use this to pick the weight,")
        print("then spend a single confirming run on it rather than one run per candidate.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
