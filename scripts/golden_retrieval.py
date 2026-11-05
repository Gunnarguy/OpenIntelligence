#!/usr/bin/env python3
"""Prepare and compare golden retrieval runs (`DeepThinkRetrievalGoldenTests`).

    python3 scripts/golden_retrieval.py prepare <dir>
        Copies the committed benchmark fixtures into <dir>/fixtures and writes <dir>/queries.json from the two
        committed eval sets. Run once; the test imports the fixtures into its own simulator library on first use.

    python3 scripts/golden_retrieval.py compare <dir>/results-a.json <dir>/results-b.json
        Exit 0 only when every search returned the same passages in the same order with bit-identical scores.

The test runs with TEST_RUNNER_OI_GOLDEN_DIR=<dir> and TEST_RUNNER_OI_GOLDEN_LABEL=<label> in the environment of
`xcodebuild test-without-building -only-testing:OpenIntelligenceTests/DeepThinkRetrievalGoldenTests`.
"""

import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURE_DIRS = [
    ROOT / "Benchmarks/ResearchFixtures/qasper_external_v1/fixtures",
    ROOT / "Benchmarks/ResearchFixtures/tiny_research_suite/fixtures",
    ROOT / "Benchmarks/Fixtures",
]
EVAL_SETS = [ROOT / "Benchmarks/rag_eval_qasper_v1.jsonl", ROOT / "Benchmarks/rag_eval_v1.jsonl"]


def read_jsonl(path):
    rows = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("//"):
            rows.append(json.loads(line))
    return rows


def prepare(out):
    out = Path(out)
    fixtures = out / "fixtures"
    fixtures.mkdir(parents=True, exist_ok=True)
    names, digests = set(), {}
    import hashlib
    for d in FIXTURE_DIRS:
        for f in sorted(d.rglob("*")):
            if f.is_file() and f.suffix.lower() in {".md", ".txt", ".pdf"} and f.name.lower() != "readme.md":
                if f.name in names:
                    sys.exit(f"two fixtures share the name {f.name}")
                digest = hashlib.sha256(f.read_bytes()).hexdigest()
                if digest in digests:
                    # The app keeps one copy of identical content ("Skipping already imported document").
                    print(f"skipping {f.name}: identical to {digests[digest]}")
                    continue
                digests[digest] = f.name
                names.add(f.name)
                shutil.copy2(f, fixtures / f.name)
    single, seen = [], set()
    for path in EVAL_SETS:
        for row in read_jsonl(path):
            q = row.get("query")
            if not q or q in seen:
                continue
            seen.add(q)
            cites = row.get("expectedCitations") or []
            scope = next((c for c in cites if isinstance(c, str) and c in names), None)
            single.append({"query": q, "scope": scope})
    # Five questions at a time, the way Deep Think searches five rewrites of one question.
    groups = [[s["query"] for s in single[i:i + 5]] for i in range(0, min(len(single), 100) - 4, 5)]
    (out / "queries.json").write_text(json.dumps({"single": single, "groups": groups}, indent=1))
    print(f"{len(names)} fixtures, {len(single)} questions ({sum(1 for s in single if s['scope'])} scoped), "
          f"{len(groups)} groups of five -> {out}")


def compare(a_path, b_path):
    a, b = json.loads(Path(a_path).read_text()), json.loads(Path(b_path).read_text())
    for r, p in ((a, a_path), (b, b_path)):
        if r.get("passagesAfter") not in (None, r.get("passages")):
            print(f"{p}: the library changed during the run ({r['passages']} -> {r['passagesAfter']} passages)")
        if r.get("unsteady"):
            print(f"{p}: {len(r['unsteady'])} searches differed between its own two passes")
    for field in ("passages", "passagesAfter", "documents", "deviceWindow", "retrievalConfig"):
        if a.get(field) != b.get(field):
            print(f"inputs differ: {field} {a.get(field)!r} vs {b.get(field)!r}")
    ra, rb = a["results"], b["results"]
    keys = sorted(set(ra) | set(rb))
    diff = [k for k in keys if ra.get(k) != rb.get(k)]
    print(f"{a['label']}: {a['searches']} searches, {a['passages']} passages, "
          f"window {a.get('deviceWindow')}, {a['firstPassSeconds']:.1f} s / {a['secondPassSeconds']:.1f} s")
    print(f"{b['label']}: {b['searches']} searches, {b['passages']} passages, "
          f"window {b.get('deviceWindow')}, {b['firstPassSeconds']:.1f} s / {b['secondPassSeconds']:.1f} s")
    hits = sum(len(v) for v in ra.values())
    print(f"{len(keys)} searches, {hits} passages compared, {len(diff)} differ")
    for k in diff[:20]:
        x, y = ra.get(k) or [], rb.get(k) or []
        first = next((i for i in range(max(len(x), len(y))) if (x[i:i + 1] != y[i:i + 1])), None)
        print(f"  {k}: {len(x)} vs {len(y)} passages, first difference at position {first}")
    sys.exit(0 if not diff and not a.get("unsteady") and not b.get("unsteady") else 1)


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "prepare":
        prepare(sys.argv[2])
    elif len(sys.argv) == 4 and sys.argv[1] == "compare":
        compare(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)
