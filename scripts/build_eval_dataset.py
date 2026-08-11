#!/usr/bin/env python3
"""Convert the tiny_research_suite manifest into RAGEvalCase JSONL.

Why this exists
---------------
Two evaluation systems grew up side by side:

  * ``Benchmarks/ResearchFixtures/tiny_research_suite/manifest.json`` holds real,
    committed, ground-truthed cases over synthetic fixtures — but in its own
    schema, consumed by the in-app validation harness.
  * ``RAGEvalDataset`` / ``RAGEvalMetrics`` (documented in ``Docs/EVALS.md``) is
    the formal quality-gate framework. It loads JSONL of ``RAGEvalCase`` — and
    no such file existed anywhere in the repository, so the documented gates
    had nothing to run against.

This script bridges them rather than inventing a second corpus. Ground truth
stays in the manifest; the JSONL is generated output.

Usage
-----
    python3 scripts/build_eval_dataset.py            # write the dataset
    python3 scripts/build_eval_dataset.py --check    # verify it is up to date

``--check`` exits non-zero if the committed JSONL differs from what the current
manifest would produce, so drift between the two is detectable rather than
silent.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST = REPO_ROOT / "Benchmarks/ResearchFixtures/tiny_research_suite/manifest.json"
OUTPUT = REPO_ROOT / "Benchmarks/rag_eval_v1.jsonl"

# manifest category -> EvalCategory raw value (see RAGEvalCase.swift).
# `retrieval_only` and `lost_in_middle` have no dedicated EvalCategory; both are
# grounded single-document recall, so they map to `factual` and keep their
# original category as a tag so subsets stay selectable.
CATEGORY_MAP = {
    "exact_value": "exact_value",
    "retrieval_only": "factual",
    "lost_in_middle": "factual",
    "multi_hop": "multi_document",
    "missing_evidence": "abstention",
}

# manifest quality_mode -> the string RAGEvalCase.qualityMode carries.
QUALITY_MAP = {"standard": "standard", "deep-think": "deepThink", "maximum": "maximum"}


def readable_answer(patterns: list[str]) -> str:
    """Turn expected-answer regexes into the plain text they match.

    The manifest stores answers as case-insensitive regexes (``(?i)14\\.3\\s+US\\s+gal``)
    because its own harness pattern-matches. ``RAGEvalCase.expectedAnswer`` is
    plain text, so the escaping is reversed here. This is a presentation change
    only — the manifest remains the source of truth for matching.
    """
    out = []
    for pattern in patterns:
        text = pattern
        text = re.sub(r"^\(\?[a-z]+\)", "", text)  # strip inline flags
        text = text.replace(r"\s+", " ").replace(r"\s", " ")
        text = re.sub(r"\\([.\-$,()\[\]{}+*?^|])", r"\1", text)  # unescape literals
        text = re.sub(r"\s+", " ", text).strip()
        if text:
            out.append(text)
    return " / ".join(out)


def convert(case: dict) -> dict:
    """Map one manifest case onto a RAGEvalCase-shaped dict."""
    manifest_category = case["category"]
    should_abstain = case["expected_behavior"] == "abstain"

    # Ground truth is plural, because some cases genuinely require more than one document.
    #
    # This read only `expected_source.filename` and emitted a one-element list. Every
    # `multi_hop_project_m*` case asks a two-part question whose halves live in different
    # fixtures, so crediting one of the two made a correct pipeline look like a broken one: on
    # the 2026-08-11 run, `rerank` MRR@10 read 0.972 and `final` 0.917 purely because three of
    # those cases ranked the *other* required document first. The arithmetic closed exactly at
    # (17 + 0.5)/18 and (15 + 1.5)/18. All five answered correctly.
    #
    # `expected_sources` (plural) wins when the manifest carries it. The singular key is kept as
    # the fallback so the twelve single-source cases are untouched and any consumer not yet
    # updated still reads something valid.
    plural = case.get("expected_sources") or []
    citations = [
        (entry or {}).get("filename")
        for entry in plural
        if (entry or {}).get("filename")
    ]
    if not citations:
        single = (case.get("expected_source") or {}).get("filename")
        citations = [single] if single else []
    input_files = case.get("input_files", [])

    # Ordered so the JSONL reads naturally; key names must match RAGEvalCase.
    return {
        "id": case["id"],
        "query": case["query"],
        "expectedAnswer": readable_answer(case.get("expected_answer_patterns", [])),
        "category": CATEGORY_MAP[manifest_category],
        "groundTruthChunkIds": None,  # chunk IDs are assigned at ingestion time
        "expectedCitations": citations if citations and not should_abstain else None,
        "shouldAbstain": should_abstain,
        "containerId": None,
        "qualityMode": QUALITY_MAP.get(case.get("quality_mode", "standard"), "standard"),
        "tags": sorted({manifest_category, case.get("source_dataset", "synthetic")}),
        "notes": "fixtures: " + ", ".join(Path(f).name for f in input_files),
    }


def render() -> str:
    manifest = json.loads(MANIFEST.read_text())
    cases = manifest["cases"]

    header = [
        "// OpenIntelligence RAG evaluation dataset v1",
        "// GENERATED by scripts/build_eval_dataset.py — do not edit by hand.",
        "// Source of truth: Benchmarks/ResearchFixtures/tiny_research_suite/manifest.json",
        f"// {len(cases)} cases over committed synthetic fixtures (no private content).",
        "// Regenerate: python3 scripts/build_eval_dataset.py",
        "// Verify:     python3 scripts/build_eval_dataset.py --check",
    ]

    lines = list(header)
    for case in cases:
        lines.append(json.dumps(convert(case), separators=(",", ":"), sort_keys=False))
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify the committed dataset matches the manifest; do not write",
    )
    args = parser.parse_args()

    if not MANIFEST.exists():
        print(f"error: manifest not found at {MANIFEST}", file=sys.stderr)
        return 2

    rendered = render()

    if args.check:
        if not OUTPUT.exists():
            print(f"error: {OUTPUT.relative_to(REPO_ROOT)} is missing", file=sys.stderr)
            print("       run: python3 scripts/build_eval_dataset.py", file=sys.stderr)
            return 1
        if OUTPUT.read_text() != rendered:
            print(
                f"error: {OUTPUT.relative_to(REPO_ROOT)} is stale relative to the manifest",
                file=sys.stderr,
            )
            print("       run: python3 scripts/build_eval_dataset.py", file=sys.stderr)
            return 1
        count = sum(1 for line in rendered.splitlines() if not line.startswith("//"))
        print(f"OK: {OUTPUT.relative_to(REPO_ROOT)} is up to date ({count} cases).")
        return 0

    OUTPUT.write_text(rendered)
    count = sum(1 for line in rendered.splitlines() if not line.startswith("//"))
    print(f"Wrote {OUTPUT.relative_to(REPO_ROOT)} ({count} cases).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
