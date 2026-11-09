#!/usr/bin/env python3
"""Score stored passages against per-page checks written from the page images (olmOCR-Bench form).

`extraction_fidelity.py` scores against `pdftotext -layout`, which is itself an extractor: a number it runs together or a
column it interleaves counts as truth. These checks were read off each page image, so they score the import against
what the page says (2026-11-08).

Check types, one JSON object per line in `<tests dir>/<name>.jsonl`:
  present  {"page", "text"}                     the span appears in the stored text
  absent   {"page", "text"}                     running furniture (a footer on every page) appears at most once
  order    {"page", "before", "after"}          both appear, `before` first (reading order, column breaks)
  table    {"page", "cell", "row", "column"}    one stored line holds the row label and the cell, and its passage
                                                names the column

Each span is compared after folding (NFKC, dashes and quotes to ASCII, lower case, runs of space joined). A check that
fails only on spacing (it passes once every space is removed) is counted as `spacing`, so run-together words are told
apart from lost or changed text.

Usage:
  python3 scripts/ingestion_unit_tests.py <tests dir> <run dir> [--compare <other run dir>] [--show N] [--json out]
where a run dir holds `<name>.passages.json` from `ExtractionFidelityRecorder`.
"""

import argparse
import json
import re
import sys
import unicodedata
from pathlib import Path

LABELS = re.compile(r"^\[Part [0-9.]+\]$|\bROW \d+:\s*", re.MULTILINE)
DASHES = dict.fromkeys(map(ord, "‐‑‒–—―−"), "-")
QUOTES = {ord("‘"): "'", ord("’"): "'", ord("“"): '"', ord("”"): '"', ord("′"): "'"}


def fold(text: str) -> str:
    text = unicodedata.normalize("NFKC", text).translate(DASHES).translate(QUOTES).lower()
    text = re.sub(r"\s*-\s*", "-", text)  # "1 - 2 g" and "1-2 g" are the same range
    return re.sub(r"\s+", " ", text).strip()


def squeeze(text: str) -> str:
    return re.sub(r"\s", "", text)


class Stored:
    def __init__(self, passages: list[dict]):
        self.records = passages
        self.passages = [LABELS.sub(" ", p["text"]) for p in passages]
        self.joined = fold(" \n ".join(self.passages))
        self.squeezed = squeeze(self.joined)
        self.folded_passages = [fold(p) for p in self.passages]
        self.lines = [[fold(line) for line in p.split("\n")] for p in self.passages]

    def near(self, page: int) -> "Stored":
        """The passages stored for `page` and the pages beside it (a span can run onto the next page). A passage with no
        page (0) is kept."""
        cache = self.__dict__.setdefault("_near", {})
        if page not in cache:
            cache[page] = Stored([p for p in self.records if not p.get("page") or abs(p["page"] - page) <= 1])
        return cache[page]

    def find(self, span: str) -> str:
        """`exact`, `spacing` (found only with spaces removed) or `missing`."""
        folded = fold(span)
        if folded in self.joined:
            return "exact"
        if squeeze(folded) in self.squeezed:
            return "spacing"
        return "missing"


def run_check(check: dict, stored: Stored) -> str:
    kind = check["type"]
    # Present, order and table checks count only text stored for the check's page or the pages beside it, so a span
    # found somewhere else in the document (a summary, another page's copy) does not pass it (refuting review,
    # 2026-11-08). Absent stays document-wide.
    if kind != "absent" and check.get("page"):
        stored = stored.near(check["page"])
    if kind == "present":
        return stored.find(check["text"])
    if kind == "absent":
        # One copy is allowed: a first page prints its own citation ("Int. J. Mol. Sci. 2020, 21, 3624") once.
        return "exact" if stored.joined.count(fold(check["text"])) <= 1 else "repeated"
    if kind == "order":
        before, after = fold(check["before"]), fold(check["after"])
        if before in stored.joined and after in stored.joined:
            return "exact" if stored.joined.index(before) < stored.joined.index(after) else "order"
        b, a = squeeze(before), squeeze(after)
        if b in stored.squeezed and a in stored.squeezed:
            return "spacing" if stored.squeezed.index(b) < stored.squeezed.index(a) else "order"
        return "missing"
    if kind == "table":
        cell, row, column = fold(check["cell"]), fold(check["row"]), fold(check["column"])
        best = "missing"
        for passage, lines in zip(stored.folded_passages, stored.lines):
            for line in lines:
                if cell in line and row in line:
                    if column in passage:
                        return "exact"
                    best = "no column"
                elif squeeze(cell) in squeeze(line) and squeeze(row) in squeeze(line) and best == "missing":
                    best = "spacing"
        if best == "missing" and cell in stored.joined:
            best = "cell apart"
        return best
    raise ValueError(f"unknown check type {kind}")


def score(tests_dir: Path, run_dir: Path) -> dict:
    out = {}
    for tests_path in sorted(tests_dir.glob("*.jsonl")):
        name = tests_path.stem
        record = run_dir / f"{name}.passages.json"
        if not record.exists():
            continue
        stored = Stored(json.loads(record.read_text())["passages"])
        results = []
        for line in tests_path.read_text().splitlines():
            if line.strip():
                check = json.loads(line)
                results.append((check, run_check(check, stored)))
        out[name] = results
    return out


def summary(results: dict) -> dict:
    rows = {}
    for name, checks in results.items():
        by_type = {}
        for check, outcome in checks:
            t = by_type.setdefault(check["type"], [0, 0])
            t[1] += 1
            t[0] += outcome == "exact"
        passed = sum(outcome == "exact" for _, outcome in checks)
        spacing = sum(outcome == "spacing" for _, outcome in checks)
        rows[name] = {"passed": passed, "spacing": spacing, "total": len(checks), "by_type": by_type}
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("tests", type=Path)
    parser.add_argument("run", type=Path)
    parser.add_argument("--compare", type=Path)
    parser.add_argument("--show", type=int, default=0, help="print up to N failing checks per file")
    parser.add_argument("--json", type=Path)
    args = parser.parse_args()

    current = score(args.tests, args.run)
    other = score(args.tests, args.compare) if args.compare else None
    rows, other_rows = summary(current), summary(other) if other else None

    types = ["present", "absent", "order", "table"]
    print(f"{'file':28} {'pass':>9} {'spacing':>8} " + " ".join(f"{t:>9}" for t in types) + ("   vs" if other else ""))
    totals = {"passed": 0, "total": 0, "spacing": 0}
    other_passed = 0
    for name, row in rows.items():
        cells = []
        for t in types:
            p, n = row["by_type"].get(t, [0, 0])
            cells.append(f"{p:>4}/{n:<4}" if n else f"{'-':>9}")
        line = f"{name[:28]:28} {row['passed']:>4}/{row['total']:<4} {row['spacing']:>8} " + " ".join(cells)
        if other_rows and name in other_rows:
            line += f"   {other_rows[name]['passed']:>4}/{other_rows[name]['total']}"
            other_passed += other_rows[name]["passed"]
        print(line)
        for key in totals:
            totals[key] += row[key]
    share = totals["passed"] / max(totals["total"], 1)
    line = f"{'TOTAL':28} {totals['passed']:>4}/{totals['total']:<4} {totals['spacing']:>8}   pass rate {share:.3f}"
    if other_rows:
        line += f"   vs {other_passed}/{totals['total']} ({other_passed / max(totals['total'], 1):.3f})"
    print(line)

    if args.show:
        for name, checks in current.items():
            failing = [(c, o) for c, o in checks if o != "exact"]
            if other:
                before = {json.dumps(c, sort_keys=True): o for c, o in other.get(name, [])}
                failing = [(c, o, before.get(json.dumps(c, sort_keys=True))) for c, o in failing]
            else:
                failing = [(c, o, None) for c, o in failing]
            for check, outcome, was in failing[: args.show]:
                span = check.get("text") or check.get("cell") or f"{check.get('before')} -> {check.get('after')}"
                extra = f" row={check['row']!r} col={check['column']!r}" if check["type"] == "table" else ""
                prior = f" (was {was})" if was else ""
                print(f"  {name[:20]} p{check.get('page')} {check['type']} {outcome}{prior}: {span!r}{extra}")
    if args.json:
        args.json.write_text(json.dumps({"summary": rows, "results": {n: [[c, o] for c, o in r] for n, r in current.items()}}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
