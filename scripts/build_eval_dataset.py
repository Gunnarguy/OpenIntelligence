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

# Packs this script knows how to render, as manifest -> output. `--manifest`/`--output` override
# it for a one-off. The external pack is built by scripts/build_external_fixtures.py and carries
# ground truth this project did not author; see that script's header for why that matters.
PACKS = {
    MANIFEST: OUTPUT,
    REPO_ROOT / "Benchmarks/ResearchFixtures/qasper_external_v1/manifest.json":
        REPO_ROOT / "Benchmarks/rag_eval_qasper_v1.jsonl",
}

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
        # The pack's own tags are merged in rather than replaced, so subsets a builder marked
        # deliberately (`multi_paragraph`, for instance) survive into the JSONL and stay selectable.
        "tags": sorted({manifest_category, case.get("source_dataset", "synthetic")}
                       | set(case.get("tags") or [])),
        "notes": notes_for(case, input_files),
    }


def notes_for(case: dict, input_files: list) -> str:
    """Human-readable provenance for one case.

    A pool-based pack leaves `input_files` empty on purpose: its corpus is the manifest's shared
    `pool`, not a per-case list. Naming the paper and the annotator agreement is the useful thing
    there; falling back to an empty "fixtures: " string would have said nothing.
    """
    if input_files:
        return "fixtures: " + ", ".join(Path(f).name for f in input_files)
    paper = case.get("paper_id")
    if paper:
        agreement = case.get("annotator_agreement")
        detail = f", {agreement} annotators agreed" if agreement else ""
        return f"paper: {paper}{detail}; corpus is the manifest pool"
    return "corpus is the manifest pool"


def render(manifest_path: Path) -> str:
    manifest = json.loads(manifest_path.read_text())
    cases = manifest["cases"]
    source = manifest_path.relative_to(REPO_ROOT)
    pool = manifest.get("pool") or []

    datasets = sorted({c.get("source_dataset", "synthetic") for c in cases})
    if pool:
        corpus = (f"{len(cases)} cases over a shared {len(pool)}-document pool; "
                  f"ground truth from {', '.join(datasets)}.")
    else:
        corpus = f"{len(cases)} cases over committed fixtures; ground truth from {', '.join(datasets)}."

    header = [
        "// OpenIntelligence RAG evaluation dataset v1",
        "// GENERATED by scripts/build_eval_dataset.py. Do not edit by hand.",
        f"// Source of truth: {source}",
        f"// {corpus}",
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
        help="verify the committed datasets match their manifests; do not write",
    )
    parser.add_argument("--manifest", help="render only this manifest instead of every known pack")
    parser.add_argument("--output", help="destination JSONL; requires --manifest")
    args = parser.parse_args()

    if args.output and not args.manifest:
        print("error: --output requires --manifest", file=sys.stderr)
        return 2

    if args.manifest:
        manifest_path = Path(args.manifest)
        if not manifest_path.is_absolute():
            manifest_path = REPO_ROOT / manifest_path
        default_out = PACKS.get(manifest_path, manifest_path.parent / "rag_eval.jsonl")
        out_path = Path(args.output) if args.output else default_out
        if not out_path.is_absolute():
            out_path = REPO_ROOT / out_path
        packs = {manifest_path: out_path}
    else:
        # A pack whose manifest is absent is skipped rather than failing the run, so `--check`
        # still passes on a checkout that has only the synthetic suite.
        packs = {m: o for m, o in PACKS.items() if m.exists()}

    if not packs:
        print("error: no fixture manifests found", file=sys.stderr)
        return 2

    failed = False
    for manifest_path, out_path in packs.items():
        if not manifest_path.exists():
            print(f"error: manifest not found at {manifest_path}", file=sys.stderr)
            return 2

        rendered = render(manifest_path)
        count = sum(1 for line in rendered.splitlines() if not line.startswith("//"))
        name = out_path.relative_to(REPO_ROOT)

        if args.check:
            if not out_path.exists():
                print(f"error: {name} is missing", file=sys.stderr)
                failed = True
            elif out_path.read_text() != rendered:
                print(f"error: {name} is stale relative to {manifest_path.relative_to(REPO_ROOT)}",
                      file=sys.stderr)
                failed = True
            else:
                print(f"OK: {name} is up to date ({count} cases).")
            continue

        out_path.write_text(rendered)
        print(f"Wrote {name} ({count} cases).")

    if failed:
        print("       run: python3 scripts/build_eval_dataset.py", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
