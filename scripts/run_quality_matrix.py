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

Ground truth comes from the manifest named by `--manifest`, the same source
`build_eval_dataset.py` uses, so scoring uses the manifest's
`expected_answer_patterns` regexes rather than the prose rendering in the JSONL.

Two packs exist and they measure different things. `tiny_research_suite` is
synthetic and self-authored, and every case is ingested alone, so its retrieval
stages sit at a ceiling by construction. `qasper_external_v1` carries external
ground truth and a shared `pool` of distractor documents that is ingested for
every case, which is what allows retrieval to fail and therefore to improve.
Figures from the two are not comparable.

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
import collections
import datetime as dt
import hashlib
import json
import math
import os
import random
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_MANIFEST = REPO_ROOT / "Benchmarks/ResearchFixtures/tiny_research_suite/manifest.json"
ALL_MODES = ["standard", "deep-think", "maximum"]


def repo_relative(path: Path) -> str:
    """Repo-relative where the path is inside the tree, absolute where it is not.

    `Path.relative_to` raises rather than falling back, and a manifest outside the tree is a normal
    thing to pass: fixture packs get built into scratch directories. The bare call sat in the
    `results.json` write, which is the last step of a multi-hour run, so an out-of-tree manifest
    crashed after all the compute had been spent and took the run index down with it.
    """
    try:
        return str(path.relative_to(REPO_ROOT))
    except ValueError:
        return str(path)


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


STAGE_HEADER = "stage\tresults\trelevant\tr1\tr3\tr5\tr10\tmrr\tndcg5\tndcg10\tp5"


def parse_stage_metrics(text: str) -> list[dict]:
    """Pull the STAGE METRICS block out of the harness report.

    The metrics themselves are computed in Swift by RetrievalStageEvaluator, which is unit-tested,
    and are only transported here. They are deliberately NOT recomputed in Python: two
    implementations of the same metric drift, and the one that drifts silently is the one nobody
    is testing. The STAGE SOURCES block in the same report carries the ranked source documents, so
    any number below can be re-derived by hand without trusting either implementation.
    """
    if STAGE_HEADER not in text:
        return []
    # lstrip the newline the header itself ends with. Without this the first splitlines() entry is
    # the empty remainder of the header line, the blank-line terminator fires immediately, and the
    # parser silently returns no stages at all — which reads exactly like a run that produced none.
    block = text.split(STAGE_HEADER, 1)[1].lstrip("\n")
    rows: list[dict] = []
    for line in block.splitlines():
        line = line.rstrip()
        if not line.strip():
            break
        parts = line.split("\t")
        if len(parts) != 11:
            break
        try:
            rows.append({
                "stage": parts[0],
                "results": int(parts[1]),
                "relevant": int(parts[2]),
                "r1": float(parts[3]), "r3": float(parts[4]),
                "r5": float(parts[5]), "r10": float(parts[6]),
                "mrr": float(parts[7]),
                "ndcg5": float(parts[8]), "ndcg10": float(parts[9]),
                "p5": float(parts[10]),
            })
        except ValueError:
            break
    return rows


def wilson_interval(successes: float, n: int, z: float = 1.96) -> tuple[float, float]:
    """95% Wilson score interval for a proportion.

    Not the normal approximation. At n=18 with a proportion near 0 or 1 — which is exactly where
    retrieval recall lands — the normal approximation produces bounds outside [0, 1] and is known
    to under-cover. Wilson stays inside the unit interval and behaves at the extremes, which is why
    it is the standard recommendation for small samples.

    `successes` may be fractional because per-query recall is itself a fraction when a case has
    several expected documents. That makes this an approximation rather than an exact binomial
    interval, and it is reported as such.
    """
    if n <= 0:
        return (0.0, 0.0)
    p = successes / n
    denom = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / denom
    margin = (z / denom) * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return (max(0.0, centre - margin), min(1.0, centre + margin))


def _cmd(*args: str, merge_stderr: bool = False) -> str:
    """Run a probe and return its output. Never raises; a missing tool records as empty.

    `merge_stderr` exists for `fm available`, which prints "System model available" to stdout and
    the far more important "Private Cloud Compute is not available in this context" to stderr.
    Capturing stdout alone records the reassuring half and drops the caveat, which would defeat the
    entire point of probing.
    """
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=15)
        out = p.stdout.strip()
        if merge_stderr and p.stderr.strip():
            # Strip ANSI colour so the recorded provenance is plain text.
            err = re.sub(r"\x1b\[[0-9;]*m", "", p.stderr).strip()
            out = f"{out} | stderr: {err}" if out else f"stderr: {err}"
        return out
    except Exception:
        return ""


def collect_provenance(argv: list[str], manifest: Path) -> dict:
    """Everything needed to say whether two runs are comparable.

    A benchmark number without this is an assertion. The dirty-tree flag matters most: a result
    produced from uncommitted work cannot be reproduced from the recorded commit, and saying so is
    the difference between a measurement and a story.

    `pcc_context` is load-bearing on this machine specifically: `fm available` reports "Private
    Cloud Compute is not available in this context. Please use the Terminal app." from a
    non-Terminal shell, so a run recorded as PCC from an agent-spawned shell is silently measuring
    the on-device model instead. Record it rather than trusting the flag that was requested.
    """
    dataset = REPO_ROOT / "Benchmarks/rag_eval_v1.jsonl"
    # Derived from the manifest in use rather than hardcoded, so a run against a different pack
    # records that pack's corpus hash instead of silently stamping the synthetic suite's.
    fixtures = sorted((Path(manifest).parent / "fixtures").rglob("*"))
    h = hashlib.sha256()
    for f in fixtures:
        if f.is_file():
            h.update(f.name.encode())
            h.update(f.read_bytes())

    dirty = _cmd("git", "-C", str(REPO_ROOT), "status", "--porcelain")
    return {
        "commit": _cmd("git", "-C", str(REPO_ROOT), "rev-parse", "HEAD"),
        "tree_dirty": bool(dirty),
        "tree_dirty_files": len([l for l in dirty.splitlines() if l.strip()]),
        "dataset_sha256": hashlib.sha256(dataset.read_bytes()).hexdigest() if dataset.exists() else None,
        "fixture_corpus_sha256": h.hexdigest(),
        "fixture_file_count": sum(1 for f in fixtures if f.is_file()),
        "os_build": _cmd("sw_vers", "-buildVersion"),
        "os_version": _cmd("sw_vers", "-productVersion"),
        "hardware": _cmd("sysctl", "-n", "machdep.cpu.brand_string"),
        "xcode": _cmd("xcodebuild", "-version").replace("\n", " "),
        "launch_context": _cmd("launchctl", "managername"),
        "pcc_context": _cmd("fm", "available", merge_stderr=True) or "unknown",
        "swift_deterministic_hashing": os.environ.get("SWIFT_DETERMINISTIC_HASHING", "unset"),
        "argv": " ".join(argv),
    }


def bootstrap_ci(values: list[float], iterations: int = 2000, seed: int = 20260808) -> tuple[float, float]:
    """95% bootstrap percentile interval for a mean.

    Wilson is only valid for proportions, so nDCG and MRR — which are means of bounded continuous
    per-query scores — need a different interval rather than being reported as bare means.
    Seeded so the interval is reproducible; an unseeded interval changes between runs of the same
    data, which is the same reproducibility failure as an unstable sort.
    """
    if not values:
        return (0.0, 0.0)
    rng = random.Random(seed)
    n = len(values)
    means = sorted(sum(rng.choices(values, k=n)) / n for _ in range(iterations))
    return (means[int(0.025 * iterations)], means[int(0.975 * iterations) - 1])


DISCORDANT_FOR_SIGNIFICANCE = 6


def minimum_detectable_effect(n: int) -> str:
    """Plain statement of what this sample size can and cannot resolve.

    Reported next to every recall figure because a flat result at n=18 reads as "no regression"
    when it actually means "no regression large enough to see".

    Corrected 2026-08-12. This returned a fixed "differences below about 25 points are not
    resolvable" for every `n`: the sentence interpolated the sample size but the threshold was
    a constant, so it printed the same power claim at n=18 and n=150. Every archived report in
    `BenchmarkRuns/` carries the constant, and it was quoted as measured in `Docs/ai/RUNBOOK.md`,
    `Docs/ai/STATE.md` and the Notion row that tracks this fixture work.

    What is actually true. Under the exact two-sided sign test this sentence describes,
    `2 * 0.5**d < 0.05` first holds at d=6, so six discordant pairs all favouring one side is
    the significance threshold, and that part was right and is genuinely independent of `n`.
    The smallest *difference* that can reach it is b=6, c=0, which is `6/n`. That is 33 points
    at n=18, not 25, so the old figure overstated the harness's sensitivity by a third.
    """
    if n <= 0:
        return "no scored cases"
    d = DISCORDANT_FOR_SIGNIFICANCE
    if n < d:
        return (f"at n={n}, no difference is resolvable: the exact sign test needs {d} discordant "
                f"cases to reach p<0.05 and there are only {n} cases in total")
    return (f"at n={n}, a paired comparison needs {d} discordant cases all favouring one side to "
            f"reach p<0.05, so the smallest resolvable difference is {d}/{n}, about "
            f"{d / n * 100:.0f} points")


def summarize_stages(rows: list[dict], mode: str) -> list[dict]:
    """Aggregate per-stage retrieval metrics across every case for one mode.

    Deliberately includes runs where generation produced no answer. Retrieval ran on those cases
    regardless of whether the model later said anything, and excluding them would throw away most
    of the deep-think and maximum samples for no reason. This is the whole argument for measuring
    retrieval separately from generation.
    """
    per_stage: dict[str, list[dict]] = {}
    order: list[str] = []
    for row in rows:
        if row["mode"] != mode:
            continue
        for metric in (row["run"].get("stage_metrics") or []):
            if metric["stage"] not in per_stage:
                per_stage[metric["stage"]] = []
                order.append(metric["stage"])
            per_stage[metric["stage"]].append(metric)

    out = []
    for stage in order:
        entries = per_stage[stage]
        n = len(entries)
        def mean(key): return sum(e[key] for e in entries) / n if n else 0.0
        lo, hi = wilson_interval(sum(e["r5"] for e in entries), n)
        ndcg5_ci = bootstrap_ci([e["ndcg5"] for e in entries])
        ndcg10_ci = bootstrap_ci([e["ndcg10"] for e in entries])
        mrr_ci = bootstrap_ci([e["mrr"] for e in entries])
        out.append({
            "stage": stage, "n": n,
            "r1": mean("r1"), "r3": mean("r3"), "r5": mean("r5"), "r10": mean("r10"),
            "mrr": mean("mrr"), "ndcg5": mean("ndcg5"), "ndcg10": mean("ndcg10"),
            "p5": mean("p5"),
            "r5_ci": [lo, hi],
            "ndcg5_ci": list(ndcg5_ci), "ndcg10_ci": list(ndcg10_ci), "mrr_ci": list(mrr_ci),
            # Every case on this fixture names exactly one source, so recall degenerates to a hit
            # rate. Recorded so a future fixture with multi-source cases invalidates the note
            # rather than silently keeping it.
            "all_single_source": all(e["relevant"] == 1 for e in entries),
            "mean_results": mean("results"),
        })
    return out


# The reason block's closing ")*" is OPTIONAL here on purpose, and `.*` runs to the end of the
# string rather than to the end of the line. Requiring a well-formed `*(Reason: …)*` meant an
# unterminated reason was not stripped at all, because the whole optional group failed to match and
# the reason text stayed inside group(1). See `strip_verification_banner` for what that cost.
VERIFICATION_BANNER = re.compile(
    r"^\s*⚠️\s*\*\*\[Needs Verification\]\*\*[^\n]*\n+(.*?)(?:\n+\*\(Reason:.*)?\s*$",
    re.S,
)


def strip_verification_banner(answer: str) -> tuple[str, bool]:
    """Separate the engine's verification wrapper from the answer it wraps.

    `SourceOnlyAnswerService.swift:349` prepends "⚠️ **[Needs Verification]** This answer was
    drafted but could not be strictly verified against the retrieved evidence:" to an otherwise
    complete answer, and appends a reason. The answer is still there and may be entirely correct.

    This function exists because grading the wrapper instead of the answer cost 15 points of
    measured accuracy. The banner contains the words "could not", the abstention regex below matches
    "could not", so every wrapped answer was classified as a refusal and every refusal on an
    answer-case scores wrong. Verified on the 2026-08-08 run: `multi_hop_project_m2`, `m3` and `m5`
    each hit 2 of 2 required patterns and were all scored incorrect. Real accuracy was 17/20, not
    14/20.

    Returns the inner answer and whether the banner was present. The flag is kept rather than
    discarded: "answered correctly but the verification gate was not satisfied" is a genuinely
    different outcome from "answered correctly", and it is worth reporting on its own.

    The same bug then recurred in a second form, and the fix is why the closing ")*" is optional in
    the pattern above. The engine emits reasons that arrive unterminated -- the closing ")*" is a
    literal at `SourceOnlyAnswerService.swift:349` but is absent from the delivered answer, and the
    app-side cause of that is still unidentified. A strict pattern failed to match those, so the
    whole reason survived into the graded answer and the abstention regex below fired on the
    *verifier's* prose instead of the model's. Verified on the 2026-08-09 run:
    `multi_hop_project_m1` named the right owner and the right deadline, hit 2 of 2 required
    patterns, and scored wrong on the phrase "does not specify" inside its own reason.
    `multi_hop_project_m4` leaked identically and survived only because its reason happened to read
    "All necessary claims are supported by the evidence." Grading that depends on the wording of a
    diagnostic is not grading. Real accuracy for that run was 18/20, not 17/20.
    """
    m = VERIFICATION_BANNER.match(answer or "")
    if not m:
        return (answer or ""), False
    return m.group(1).strip(), True


def plain_answer(pattern: str) -> str:
    """Recover the literal text a manifest answer-regex was built from.

    The manifest stores answers as case-insensitive regexes because the harness pattern-matches.
    Token-F1 needs the plain string. Mirrors `readable_answer` in build_eval_dataset.py.
    """
    text = re.sub(r"^\(\?[a-z]+\)", "", pattern)
    text = text.replace(r"\s+", " ").replace(r"\s", " ")
    text = re.sub(r"\\([.\-$,()\[\]{}+*?^|])", r"\1", text)
    return re.sub(r"\s+", " ", text).strip()


def _normalize(text: str) -> list[str]:
    """SQuAD-style normalisation: lowercase, drop articles and punctuation, split on whitespace."""
    text = text.lower()
    text = re.sub(r"\b(a|an|the)\b", " ", text)
    text = re.sub(r"[^a-z0-9 ]", " ", text)
    return text.split()


def gold_recall(predicted: str, gold: str) -> float:
    """Fraction of the gold answer's tokens that appear in the generated answer.

    NOT token-F1, and deliberately so. F1 was implemented here first and produced 3.3 against a
    44% exact-match rate, which is a broken metric rather than a bad system: on the 2026-08-12
    run the median generated answer is 59 tokens and the median gold span is 1. F1 divides by
    the prediction length, so a correct answer wrapped in an explanatory sentence scores near
    zero on precision.

    That mismatch also retracts a comparison made earlier the same day. Published QASPER
    figures (Longformer 39.4, CoLT5 XL 53.9, RAPTOR+GPT-4 55.7) are token-F1 over
    SPAN-EXTRACTION output. This app generates prose. **Those numbers and this app's are not on
    the same scale in either direction**, and claiming this app beats the baseline because
    44 > 39.4 was wrong. Comparing properly would mean constraining generation to a span, which
    would change the product.

    Recall answers the question that actually matters here: did the expected answer make it into
    the response at all. It is blind to verbosity, which is the correct behaviour when the app is
    designed to explain rather than to emit a span. It is generous where exact match is strict,
    so the pair brackets the truth: exact match is a floor, recall is a ceiling.
    """
    pred_tokens = _normalize(predicted)
    gold_tokens = _normalize(gold)
    if not pred_tokens or not gold_tokens:
        return float(pred_tokens == gold_tokens)

    common = collections.Counter(pred_tokens) & collections.Counter(gold_tokens)
    overlap = sum(common.values())
    return overlap / len(gold_tokens) if gold_tokens else 0.0


def score(case: dict, parsed: dict) -> dict:
    """Score one run against the manifest's ground truth."""
    answer, verification_flagged = strip_verification_banner(parsed.get("answer", ""))
    # Abstention phrasing varies more than expected. An early version missed
    # "I do not have access to confidential pricing information" and scored a
    # correct refusal as a hallucination -- the worst possible direction for
    # this metric to be wrong in. Keep this list generous; a false "abstained"
    # only downgrades an answer case, while a false "hallucinated" defames a
    # refusal that was exactly right.
    abstained = bool(re.search(
        r"\b(cannot|can't|could not|couldn't|unable to|not (?:enough|sufficient)|"
        r"does not (?:contain|include|provide|specify|mention)|"
        r"(?:do|does) not have access|don't have access|no access to|"
        r"no (?:information|evidence|mention|details)|not disclosed|"
        # "not stated" was missing and cost a correct refusal on 2026-08-08:
        # missing_unreleased_battery answered "…is not stated in the document", a textbook
        # abstention, and was scored as a hallucination on a negative control — the single worst
        # direction for this metric to be wrong in, and exactly what the note above warns about.
        r"isn't (?:in|available)|not (?:found|available|provided|specified|stated|mentioned|listed|given))\b",
        answer, re.I,
    ))

    if case["expected_behavior"] == "abstain":
        return {"expected": "abstain", "abstained": abstained, "correct": abstained,
                "verification_flagged": verification_flagged}

    patterns = case.get("expected_answer_patterns") or []
    hits = [p for p in patterns if re.search(p, answer)]
    return {
        "expected": "answer",
        "abstained": abstained,
        "patterns_total": len(patterns),
        "patterns_hit": len(hits),
        # Every required pattern must appear, and abstaining is a miss.
        "correct": bool(patterns) and len(hits) == len(patterns) and not abstained,
        # Gold-token recall alongside the exact match. Exact match is a floor and recall a
        # ceiling; see `gold_recall` for why F1 is not used here.
        "gold_recall": (sum(gold_recall(answer, plain_answer(p)) for p in patterns) / len(patterns)) if patterns else 0.0,
        # Reported separately: a correct answer the verification gate would not certify is a
        # different outcome from a correct answer, and worth seeing.
        "verification_flagged": verification_flagged,
    }


# The four documents in the shared library that are not benchmark output. Everything else there
# was put there by a benchmark run, verified 2026-08-12 against filename and containerId.
REAL_LIBRARY_DOCUMENTS = {
    "Apple-Intelligence-&-Private-Cloud-Compute.md",
    "OpenIntelligence-Product-Guide.md",
    "RAG-Technical-Architecture.md",
    "ingestion4.5.1.txt",
}


def reset_shared_library() -> None:
    """Clear benchmark residue from the app's shared library between cases.

    `WorkspaceSyncService` resolves its root with `OpenIntelligenceRuntimePaths.applicationSupportRoot()`
    rather than `baseDirectory()`, and only the latter honours the `--rag-validation-storage`
    override. Ingested documents therefore land in the user's real library no matter what storage
    the harness was given. Left alone they accumulate across cases: a run that started against a
    library holding 241 stale documents spent longer than the 600s timeout on its first case and
    produced no report at all.

    This removes only what a benchmark put there and never touches transcripts, chat history,
    conversation memory, containers.json, Gazetteers, LocalCache or FullText.
    """
    library = Path.home() / "Library/Application Support/OpenIntelligence"
    if not library.exists():
        return
    imported = library / "ImportedDocuments"
    if imported.exists():
        for path in imported.iterdir():
            if path.name not in REAL_LIBRARY_DOCUMENTS and path.is_file():
                path.unlink(missing_ok=True)
    try:
        live = {c["id"] for c in json.loads((library / "containers.json").read_text())}
    except Exception:
        live = set()
    for path in library.glob("vector_database_*"):
        if not any(path.name.startswith(f"vector_database_{cid}") for cid in live):
            path.unlink(missing_ok=True)
    (library / "documents_metadata.json").write_text("[]")
    (library / "ingestion_queue.json").write_text("[]")


def run_one(
    app_bin: Path, case: dict, mode: str, pcc: str, timeout: int,
    storage: Path, ingest: bool, pool: list[str] | None = None, pool_limit: int = 0,
    top_k: int = 0, vector_weight: float | None = None,
    sampling: str | None = None, temperature: float | None = None, seed: int | None = None,
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
    # The shared pool is ingested alongside the case's own files, so the index holds documents
    # that are *not* the answer. Without it every case was scored against an index containing
    # only its own expected file: the 2026-08-11 run gave the vector stage two to five candidates
    # per case, all of them correct, which forced R@5 and MRR@10 to 1.000 arithmetically. A
    # fixture with no distractors can register a regression but can never show an improvement.
    #
    # `pool_limit` trades distractors against wall clock. Ingestion measured 2026-08-12 at roughly
    # 15s per paper, so the full 40-paper pool is about 10 minutes per case and 14 hours for 83
    # cases. Reusing one index instead would be far faster and does not work: the vector store
    # follows `--rag-validation-storage` while document metadata does not, so a reused index
    # resolves every source name to `Unknown` and scores 0.000 across the board. See the Notion
    # row "Benchmark runs write their fixtures into the real on-device document library".
    #
    # The case's own expected documents are always included, and the rest of the slots are filled
    # in manifest order, so the selection is deterministic and reproducible from the run metadata.
    selected_pool = list(pool or [])
    if pool_limit and pool_limit > 0:
        own = set(case["input_files"]) | {
            p for p in selected_pool
            if Path(p).name in {(e or {}).get("filename") for e in (case.get("expected_sources") or [])}
        }
        keep = [p for p in selected_pool if p in own]
        keep += [p for p in selected_pool if p not in own][: max(0, pool_limit - len(keep))]
        selected_pool = keep

    ordered = list(dict.fromkeys(selected_pool + list(case["input_files"])))
    inputs = [str(REPO_ROOT / p) for p in ordered]
    missing = [p for p in inputs if not Path(p).exists()]
    if missing:
        return {"ok": False, "error": f"missing fixtures: {missing[:3]}"}

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
    if sampling:
        cmd += ["--rag-validation-sampling", sampling]
    if temperature is not None:
        cmd += ["--rag-validation-temperature", str(temperature)]
    if seed is not None:
        cmd += ["--rag-validation-seed", str(seed)]
    # Ground truth for the retrieval metrics. The negative-control cases have no expected source by
    # construction; passing nothing makes the harness emit no STAGE METRICS block at all, so those
    # cases stay unscored rather than contributing a meaningless 0.0 to the aggregate.
    # Negative controls are NOT retrieval-scored, even though the manifest gives them an
    # `expected_source`. For an abstention case the correct pipeline behaviour is to retrieve
    # nothing usable and refuse, so scoring it as retrieval counts a working relevance gate as a
    # retrieval failure. Observed on 2026-08-08: `missing_confidential_price` correctly abstained
    # and was recorded as `rerank R@5=1.00 -> final R@5=0.00`, dragging the aggregate `final` recall
    # down by a stage doing exactly its job. Abstention correctness is reported separately, as its
    # own count, and never folded into a retrieval rate.
    # All required documents, not just the first.
    #
    # This passed only `expected_source.filename`, so a two-document question was scored against
    # one document and the pipeline was penalised for ranking the other required one first. That
    # is where the apparent `rerank` 0.972 and `final` 0.917 on the 2026-08-11 run came from; all
    # five multi-hop cases answered correctly. The flag is comma-separated and
    # `DebugRAGValidationHarness` already splits it, so multi-source scoring needed no app change.
    expected_sources = [
        (entry or {}).get("filename")
        for entry in (case.get("expected_sources") or [])
        if (entry or {}).get("filename")
    ]
    if not expected_sources:
        single = (case.get("expected_source") or {}).get("filename")
        expected_sources = [single] if single else []
    if expected_sources and case.get("expected_behavior") != "abstain":
        cmd += ["--rag-validation-expected-sources", ",".join(expected_sources)]
    # Final retrieval breadth. Omitted unless swept, so a default run measures shipped
    # behaviour: the chat UI's `retrievalTopK` AppStorage default and `queryWithAudit`'s own
    # default are both 3.
    if top_k:
        cmd += ["--rag-validation-topk", str(top_k)]
    # Fusion weight for the dense arm; lexical gets the remainder. Omitted unless swept, so a
    # default run keeps the shipped clamped policy.
    if vector_weight is not None:
        cmd += ["--rag-validation-vector-weight", str(vector_weight)]
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

        # A report can be emitted with no ANSWER section at all: the harness
        # writes its header and artifacts, but generation produced nothing.
        # That is an unmeasured run, NOT a wrong answer, and scoring it as a
        # miss would slander the mode. Observed on 2026-07-30: Deep Think and
        # Maximum hit this on every case that engages the agentic loop, while
        # cases that shortcut to Direct Source Extraction complete normally.
        # Retrieval metrics are attached on BOTH paths. A run with no answer is unmeasured for
        # ANSWER QUALITY only: retrieval still executed, and its stages were still recorded. The
        # 2026-07-30 matrix discarded 31 such runs wholesale and so measured deep-think on 5 of 20
        # cases; those runs had retrieval data all along and nobody could see it.
        stage_metrics = parse_stage_metrics(report)

        if not (parsed.get("answer") or "").strip():
            return {
                "ok": False, "seconds": elapsed, "report": report,
                "error": "no answer produced (agentic path did not complete headlessly)",
                "model": parsed.get("model"), "unmeasured": True,
                "stage_metrics": stage_metrics,
            }
        return {
            "ok": True, "seconds": elapsed, "ingested": ingest, "report": report,
            "stage_metrics": stage_metrics, **parsed,
        }
    except subprocess.TimeoutExpired:
        return {"ok": False, "seconds": timeout, "error": f"timeout after {timeout}s"}


def summarize(rows: list[dict], mode: str) -> dict:
    """Aggregate every run for one mode."""
    mine = [r for r in rows if r["mode"] == mode]
    ok = [r for r in mine if r["run"].get("ok")]
    unmeasured = [r for r in mine if r["run"].get("unmeasured")]
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
        "unmeasured": len(unmeasured),
        "failed": len(mine) - len(ok) - len(unmeasured),
        "correct": len(correct),
        # Denominator is every attempted run, not just the ones that answered. A system that
        # returns nothing scores 0 on that topic; it is not excused from it. trec_eval ships `-c`
        # for exactly this and the canonical shared-task invocation uses it. The 2026-07-30 report
        # quoting deep-think accuracy over 5 of 20 cases is this bug: a mode that failed 15 times
        # was credited with 80% because the failures were removed from the denominator.
        "accuracy": round(len(correct) / len(mine), 3) if mine else None,
        # Kept as clearly secondary. Useful for asking "when it did answer, was it right", never
        # for a headline. Must not reach CHANGELOG or Settings.
        "accuracy_completed_only": round(len(correct) / len(scored), 3) if scored else None,
        "answer_accuracy": round(len(answer_ok) / len(answer_cases), 3) if answer_cases else None,
        "abstention_rate": round(len(abstain_ok) / len(abstain_cases), 3) if abstain_cases else None,
        "hallucinated_on_negative_control": len(hallucinated),
        "mean_seconds": mean([r["run"].get("seconds") for r in ok]),
        "mean_llm_calls": mean([r["run"].get("llm_calls") for r in ok]),
        "mean_tokens": mean([r["run"].get("total_tokens") for r in ok]),
        "mean_confidence": mean([r["run"].get("confidence") for r in ok]),
        "mean_retrieved": mean([r["run"].get("retrieved_chunks") for r in ok]),
    }


def render_markdown(summaries: list[dict], rows: list[dict], meta: dict,
                    stage_summaries: dict[str, list[dict]] | None = None) -> str:
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
    L.append("| Mode | Measured | Unmeasured | Correct | Accuracy | Abstentions | Hallucinated | Mean s |")
    L.append("| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for s in summaries:
        def fmt(v, pct=False):
            if v is None:
                return "-"
            return f"{v * 100:.0f}%" if pct else str(v)
        L.append(
            f"| {s['mode']} | {s['completed']}/{s['runs']} | {s.get('unmeasured', 0)} | "
            f"{s['correct']} | {fmt(s['accuracy'], True)} | "
            f"{fmt(s['abstention_rate'], True)} | "
            f"{s['hallucinated_on_negative_control']} | {fmt(s['mean_seconds'])} |"
        )
    L.append("")
    L.append("**Unmeasured** runs produced no ANSWER section at all -- generation returned "
             "nothing. These are excluded from accuracy rather than counted as wrong; a mode "
             "that could not run is not a mode that answered badly. Accuracy is over measured "
             "runs only, so a low Measured count means the number beside it is weak evidence.")
    L.append("")

    if stage_summaries and any(stage_summaries.values()):
        L.append("## Retrieval, per stage")
        L.append("")
        L.append("Where in the pipeline the right document is found, or lost. Unlike the table "
                 "above, these include runs where generation produced nothing: retrieval still "
                 "ran on those cases, and that is the point of scoring it separately.")
        L.append("")
        L.append("Ground truth is document-level (the manifest's `expected_sources`, falling back "
                 "to `expected_source.filename`), so each expected document is credited once, at "
                 "the rank of its first matching chunk. `k` still counts chunks, because chunks "
                 "are what reach the model. Multi-document cases credit every document the "
                 "question requires; crediting only the first made a correct pipeline read as a "
                 "ranking regression.")
        L.append("")
        for mode, stages in stage_summaries.items():
            if not stages:
                continue
            L.append(f"### {mode}")
            L.append("")
            L.append("| Stage | n | R@1 | R@3 | R@5 | R@5 95% CI | R@10 | MRR@10 | nDCG@5 | P@5 | Mean results |")
            L.append("| :--- | ---: | ---: | ---: | ---: | :---: | ---: | ---: | ---: | ---: | ---: |")
            for s in stages:
                lo, hi = s["r5_ci"]
                L.append(
                    f"| {s['stage']} | {s['n']} | {s['r1']:.2f} | {s['r3']:.2f} | "
                    f"**{s['r5']:.2f}** | [{lo:.2f}, {hi:.2f}] | {s['r10']:.2f} | "
                    f"{s['mrr']:.2f} | {s['ndcg5']:.2f} | {s['p5']:.2f} | {s['mean_results']:.0f} |"
                )
            L.append("")

        L.append("**Reading it.** Recall should be flat or falling left to right; a stage that "
                 "drops it is where the right document is being lost. `boosted` to `candidates` "
                 "is top-K truncation. `candidates` to `rerank` is the cross-encoder demoting the "
                 "right chunk. Reranking cannot recover a document the first stage never returned, "
                 "so a low `vector`/`lexical` number caps everything downstream.")
        L.append("")
        L.append("**The interval is not decoration.** With this sample size the 95% Wilson "
                 "interval on R@5 is wide, so two stages whose intervals overlap have not been "
                 "shown to differ. Use these to find where recall collapses, not to defend a "
                 "two-point difference. Per-case numbers are in `results.json`, and each case "
                 "report under `reports/` carries a STAGE SOURCES block so any figure here can be "
                 "recomputed by hand.")
        L.append("")

        any_stage = next((s for stages in stage_summaries.values() for s in stages), None)
        if any_stage and any_stage.get("all_single_source"):
            L.append("**Recall here is a hit rate.** Every scored case names exactly one expected "
                     "source, so `totalRelevant == 1` and recall@k is numerically identical to "
                     "Success@k: it only answers \"did a chunk from the right file appear in the "
                     "top k\". It carries no information beyond that. **MRR@10 and nDCG are the "
                     "only metrics here that discriminate between stages**, because they are "
                     "sensitive to *where* in the ranking the right document landed.")
            L.append("")

        n = any_stage["n"] if any_stage else 0
        L.append("### What this number can and cannot support")
        L.append("")
        L.append("> These are fixture-corpus figures, not a quality claim about the app. The cases "
                 "are drawn from a single synthetic corpus that was authored alongside the "
                 "questions, so every chunk not from a named file is implicitly judged "
                 "non-relevant — defensible only because the corpus is closed and small, and false "
                 "the day this points at real user documents. The numbers do not generalise.")
        L.append("")
        floor = (DISCORDANT_FOR_SIGNIFICANCE / n * 100) if n >= DISCORDANT_FOR_SIGNIFICANCE else None
        L.append(f"**Statistical power:** {minimum_detectable_effect(n)}. When a run shows no "
                 "movement, the correct wording is " + (
                     f"*\"no change larger than about {floor:.0f} points would have been "
                     "detected\"*" if floor else "*\"nothing would have been detected\"*") +
                 ", never *\"no regression\"*. The risk at this sample size is not only missing "
                 "a regression but reporting one as an apparent improvement.")
        L.append("")
        L.append("**Never ship a retrieval change on a delta from this table alone.** Require a "
                 "mechanism-level explanation for the movement. These cases have also been tuned "
                 "against repeatedly, which is adaptive reuse of a holdout and voids the nominal "
                 "coverage of any interval computed on them.")
        L.append("")

        prov_keys = ["commit", "tree_dirty", "dataset_sha256", "fixture_corpus_sha256",
                     "os_version", "os_build", "hardware", "xcode", "launch_context",
                     "pcc_context", "swift_deterministic_hashing"]
        if any(k in meta for k in prov_keys):
            L.append("### Provenance")
            L.append("")
            L.append("Two runs are comparable only if these match.")
            L.append("")
            for k in prov_keys:
                if k in meta:
                    v = meta[k]
                    if k == "tree_dirty" and v:
                        v = f"**yes ({meta.get('tree_dirty_files', '?')} files)** — this result "
                        v += "cannot be reproduced from the recorded commit alone"
                    L.append(f"- `{k}`: {v}")
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
    ap.add_argument("--sampling", default=None, choices=["greedy", "topk", "topp"],
                    help="pin the on-device sampling strategy. `greedy` makes two runs of the same "
                         "build comparable; without it samplingStrategy defaults to topK with no "
                         "seed and a single case has swung 3613 -> 68 -> 3357 chars between runs.")
    ap.add_argument("--no-ingest", action="store_true",
                    help="reuse the existing index instead of ingesting. DIAGNOSTIC ONLY: the "
                         "reused index loses document-name mapping so citations resolve to "
                         "Unknown and scores go to zero. Its one legitimate use is holding chunk "
                         "UUIDs fixed to test whether retrieval is reproducible at all.")
    ap.add_argument("--seed", type=int, default=None,
                    help="fixed sampling seed. Required to compare temperatures: greedy ignores "
                         "temperature entirely, so a controlled temperature A/B needs random "
                         "sampling with the draws held fixed.")
    ap.add_argument("--temperature", type=float, default=None,
                    help="override generation temperature. The shipped RAG preset is 0.7, labelled "
                         "'balanced creativity'; 0.3 is the 'precise' preset. Separate from "
                         "--sampling because comparability and quality are different questions.")
    ap.add_argument("--vector-weight", type=float, default=None,
                    help="dense-arm weight in RRF fusion; lexical gets 1-w. Bypasses the shipped "
                         "0.35-0.65 clamp, which is the hypothesis under test: on 2026-08-12 "
                         "fusion scored worse than the lexical arm alone at p=0.0005 while the "
                         "clamp guaranteed the weaker dense arm at least 35%%.")
    ap.add_argument("--top-k", type=int, default=0,
                    help="final retrieval breadth handed to queryWithAudit. 0 leaves the "
                         "shipped default of 3, which the chat UI also uses. Set it to sweep: "
                         "on 2026-08-12 the right document reached the final ranking on 75%% of "
                         "MISSED cases, so answers are arriving and being truncated away.")
    ap.add_argument("--resume", default="",
                    help="continue a previous run directory, skipping (case, mode) pairs "
                         "already recorded in its results.jsonl checkpoint")
    ap.add_argument("--pool-limit", type=int, default=0,
                    help="ingest at most N pool documents per case, always including the "
                         "case's own expected sources. 0 uses the whole pool. Ingestion is "
                         "roughly 15s per document, so this is the wall-clock dial.")
    ap.add_argument("--reset-shared-library", action="store_true",
                    help="clear the app's shared document library before each case. The app "
                         "writes ingested documents there regardless of "
                         "--rag-validation-storage, so without this every case is slower than "
                         "the last and later cases time out.")
    ap.add_argument("--manifest", default=str(DEFAULT_MANIFEST.relative_to(REPO_ROOT)),
                    help="fixture manifest to run. A pack may declare a top-level `pool`, which "
                         "is ingested for every case so retrieval has distractors. For external "
                         "ground truth: "
                         "Benchmarks/ResearchFixtures/qasper_external_v1/manifest.json")
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

    manifest_path = Path(args.manifest)
    if not manifest_path.is_absolute():
        manifest_path = REPO_ROOT / manifest_path
    manifest = json.loads(manifest_path.read_text())
    cases = manifest["cases"]
    pool = manifest.get("pool", [])
    if args.limit:
        cases = cases[: args.limit]

    if args.resume:
        out_dir = Path(args.resume)
        if not out_dir.is_absolute():
            out_dir = REPO_ROOT / out_dir
        run_id = out_dir.name
    else:
        run_id = dt.datetime.now().strftime("%Y%m%d-%H%M%S") + "-matrix"
        out_dir = Path(args.output_dir) if args.output_dir else REPO_ROOT / "BenchmarkRuns" / run_id
    out_dir.mkdir(parents=True, exist_ok=True)

    # Run parameters, written at START. `results.json` below records the same things but is only
    # written after the whole loop finishes, so a run that was paused or killed left the weight it
    # was testing recorded nowhere except the directory name someone typed by hand.
    # `sweep_fusion_weight.py` needs that number to calibrate its replay against, and a reader needs
    # it to know what a half-finished checkpoint actually measured.
    #
    # On resume the recorded file wins and a conflicting argument is refused rather than merged.
    # Resuming with a different --vector-weight would append cases scored under a second
    # configuration into one results.jsonl, and no downstream reader could tell the halves apart.
    run_config = {
        "run_id": run_id,
        "manifest": repo_relative(manifest_path),
        "modes": modes,
        "pcc": args.pcc,
        "pool_limit": args.pool_limit,
        "top_k": args.top_k or 3,
        "vector_weight": args.vector_weight,
        # Recorded for the same reason as vector_weight: resuming a run under different sampling
        # would append cases drawn from a different distribution into one results.jsonl, and no
        # downstream reader could tell the halves apart.
        "sampling": args.sampling,
        "temperature": args.temperature,
        "seed": args.seed,
    }
    config_path = out_dir / "run_config.json"
    if config_path.exists():
        previous = json.loads(config_path.read_text())
        conflicts = {
            key: (previous.get(key), value)
            for key, value in run_config.items()
            if key != "run_id" and previous.get(key) != value
        }
        if conflicts:
            print("error: this run directory was created with different parameters:", file=sys.stderr)
            for key, (was, now) in conflicts.items():
                print(f"  {key}: recorded {was!r}, given {now!r}", file=sys.stderr)
            print("Resuming would mix two configurations into one results.jsonl.", file=sys.stderr)
            print("Pass the original arguments, or start a new run with --output-dir.", file=sys.stderr)
            return 2
    else:
        config_path.write_text(json.dumps(run_config, indent=2))

    # Checkpoint file, one JSON row per completed (case, mode). Written as each case finishes.
    #
    # This exists because `results.json` is only written after the whole loop, so the run of
    # 2026-08-12 lost 27 completed cases, about 1.4 hours of compute, when the machine slept
    # mid-run. At roughly three minutes per case a full pack is a multi-hour job on a laptop, and
    # a job that long must survive a closed lid.
    checkpoint = out_dir / "results.jsonl"
    rows: list[dict] = []
    done: set[tuple[str, str]] = set()
    if checkpoint.exists():
        for line in checkpoint.read_text().splitlines():
            if line.strip():
                row = json.loads(line)
                rows.append(row)
                done.add((row["case_id"], row["mode"]))

    total = len(cases) * len(modes)
    print(f"Quality-mode matrix: {len(cases)} cases x {len(modes)} modes = {total} runs")
    print(f"App: {app_bin}")
    print(f"PCC consent: {args.pcc}  ·  timeout: {args.timeout}s/run")
    print(f"Output: {out_dir}")
    if done:
        print(f"Resuming: {len(done)} of {total} already complete, skipping those")
    print(flush=True)

    started = dt.datetime.now()
    n = 0
    for case in cases:
        for mode in modes:
            n += 1
            if (case["id"], mode) in done:
                continue
            if args.reset_shared_library:
                reset_shared_library()
            storage = Path(tempfile.mkdtemp(prefix=f"matrix-{case['id']}-{mode}-"))
            try:
                print(f"[{n}/{total}] {mode:11} {case['id']}", end=" ", flush=True)
                run = run_one(
                    app_bin, case, mode, args.pcc, args.timeout,
                    storage=storage, ingest=not args.no_ingest, pool=pool, pool_limit=args.pool_limit,
                    top_k=args.top_k, vector_weight=args.vector_weight,
                    sampling=args.sampling, temperature=args.temperature, seed=args.seed,
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
                with checkpoint.open("a") as fh:
                    fh.write(json.dumps(row) + "\n")
            finally:
                shutil.rmtree(storage, ignore_errors=True)

    wall = (dt.datetime.now() - started).total_seconds()
    summaries = [summarize(rows, m) for m in modes]
    stage_summaries = {m: summarize_stages(rows, m) for m in modes}
    meta = {
        "run_id": run_id, "app": str(app_bin), "cases": len(cases),
        "modes": modes, "pcc": args.pcc, "wall_seconds": round(wall, 1),
        "manifest": repo_relative(manifest_path),
        "pool_documents": len(pool),
        "pool_limit": args.pool_limit,
        "top_k": args.top_k or 3,
        "vector_weight": args.vector_weight,
        **collect_provenance(argv=sys.argv, manifest=manifest_path),
    }

    # Keep full reports out of the JSON index; write them beside it instead.
    reports_dir = out_dir / "reports"
    reports_dir.mkdir(exist_ok=True)
    for r in rows:
        if r["run"].get("report"):
            (reports_dir / f"{r['case_id']}--{r['mode']}.txt").write_text(r["run"].pop("report"))

    (out_dir / "results.json").write_text(json.dumps(
        {"meta": meta, "summaries": summaries, "stage_summaries": stage_summaries,
         "rows": rows}, indent=2))
    md = render_markdown(summaries, rows, meta, stage_summaries)
    (out_dir / "report.md").write_text(md)

    print("\n" + md)
    print(f"\nWrote {out_dir}/results.json and report.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
