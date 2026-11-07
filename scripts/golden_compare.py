#!/usr/bin/env python3
"""Prepare and compare the before-and-after recordings of the 2026-11-06 decomposition.

The recorders (`StructuredParsingGoldenTests`, `ImportGoldenTests`, `StandardPipelineGoldenTests`) each run their work
twice, fail when the two passes differ, and write `<kind>-<label>.json`. Breaking `RAGService.queryInternal`,
`RAGService.addDocument` and the structured PDF parser into steps must leave these files identical.

    python3 scripts/golden_compare.py prepare <dir>
        Copies the parsing and import fixtures into <dir>/parse-fixtures and <dir>/import-fixtures.
    python3 scripts/golden_compare.py compare <dir>/<kind>-a.json <dir>/<kind>-b.json
        Exit 0 only when the two recordings are identical; otherwise prints the first differing key paths.

The recorders run with TEST_RUNNER_OI_GOLDEN_DIR=<dir> and TEST_RUNNER_OI_GOLDEN_LABEL=<label> in the environment of
`xcodebuild test-without-building -only-testing:OpenIntelligenceTests/<Recorder>`.
"""
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# Six household documents (text-layer PDFs written for the 2026-10 household benchmark) and the Sportage owner's
# manual, of which the parser reads the first 40 pages.
PARSE_FIXTURES = sorted((ROOT / "BenchmarkRuns/household_v1/fixtures").glob("*.pdf")) + [
    ROOT / "Benchmarks/Fixtures/2024-sportage.pdf"]
# The import recorder imports the household PDFs plus the small text and Markdown research fixtures.
IMPORT_FIXTURES = sorted((ROOT / "BenchmarkRuns/household_v1/fixtures").glob("*.pdf")) + sorted(
    p for p in (ROOT / "Benchmarks/ResearchFixtures/tiny_research_suite/fixtures").rglob("*")
    if p.is_file() and p.suffix.lower() in {".md", ".txt"} and p.name.lower() != "readme.md")


# The Standard recorder's library leaves out the two synthetic sets whose files are near copies of one another
# (lost_in_middle, retrieval): their passages tie exactly in BM25, and on 2026-11-06 the order of those tied passages
# differed between two launches of the same build with the same keyword index (111 rows), which no recorder can hold
# still. Recorded as a finding in BenchmarkRuns/2026-11-06-decomposition/PLAN.md.
STANDARD_FIXTURES = [p for p in IMPORT_FIXTURES if p.parent.name not in ("lost_in_middle", "retrieval")]


# Recorded items that differ between two launches of the same build, each with what was measured. They are still
# recorded and still compared; a difference in one is reported as a note, not a failure. Anything else must match.
KNOWN_LAUNCH_SENSITIVE = {
    # 2026-11-06, runs std-a and std-b: every stage up to rerank identical; at the final stage two passages of
    # "Home Insurance Declarations 2026.pdf" carry the same score bits (1061662230) and the tie was broken differently,
    # which changed the rest of the context.
    "05 A pipe burst in my kitchen. Am I covered?",
}


def prepare(out):
    out = Path(out)
    for name, files in (("parse-fixtures", PARSE_FIXTURES), ("import-fixtures", IMPORT_FIXTURES),
                        ("standard-fixtures", STANDARD_FIXTURES)):
        folder = out / name
        folder.mkdir(parents=True, exist_ok=True)
        for f in files:
            if not f.exists():
                sys.exit(f"missing fixture {f}")
            shutil.copy2(f, folder / f.name)
        print(f"{len(files)} files -> {folder}")


def differences(a, b, path="$", out=None, limit=40):
    out = [] if out is None else out
    if len(out) >= limit:
        return out
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a) | set(b)):
            if k not in a or k not in b:
                out.append(f"{path}.{k}: {'missing' if k not in a else 'present'} vs {'missing' if k not in b else 'present'}")
            else:
                differences(a[k], b[k], f"{path}.{k}", out, limit)
    elif isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            out.append(f"{path}: {len(a)} items vs {len(b)}")
        for i, (x, y) in enumerate(zip(a, b)):
            differences(x, y, f"{path}[{i}]", out, limit)
    elif a != b:
        out.append(f"{path}: {str(a)[:80]} vs {str(b)[:80]}")
    return out


def compare(a_path, b_path):
    a, b = json.loads(Path(a_path).read_text()), json.loads(Path(b_path).read_text())
    for r, p in ((a, a_path), (b, b_path)):
        if r.get("unsteady"):
            print(f"{p}: its own two passes differed at {len(r['unsteady'])} places, so it proves nothing")
            return 2
    # The inputs must match too: a rebuilt library or a different fixture count makes the comparison meaningless.
    for field in ("library", "passages", "documents", "keywordRows"):
        if a.get(field) != b.get(field):
            print(f"DIFFERENT INPUT: {field} {a.get(field)} vs {b.get(field)}")
            return 3
    ra, rb = dict(a.get("results") or {}), dict(b.get("results") or {})
    for key in sorted(KNOWN_LAUNCH_SENSITIVE):
        if key in ra and key in rb and ra[key] != rb[key]:
            print(f"note: {key!r} differs; it is known to differ between launches (see KNOWN_LAUNCH_SENSITIVE)")
        ra.pop(key, None); rb.pop(key, None)
    diff = differences(ra, rb)
    if diff:
        print(f"DIFFERENT: {a_path} vs {b_path}")
        print("\n".join(diff))
        return 1
    n = len(a.get("results") or {})
    print(f"IDENTICAL: {n} recorded items, {Path(a_path).name} == {Path(b_path).name}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "prepare":
        prepare(sys.argv[2])
    elif len(sys.argv) == 4 and sys.argv[1] == "compare":
        sys.exit(compare(sys.argv[2], sys.argv[3]))
    else:
        sys.exit(__doc__)
