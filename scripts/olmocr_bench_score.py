#!/usr/bin/env python3
"""Score an import's stored passages with olmOCR-Bench's own checks (allenai/olmOCR-bench, ODC-BY).

The 2026-11-08 checks written from eight of the owner's PDFs were also what the extraction was tuned on, so a gain there
may not carry over. olmOCR-Bench's checks were written by its authors on 1,403 public PDFs, one page each, and nothing in
OpenIntelligence was set by looking at them.

Each record from `ExtractionFidelityRecorder` (run with `TEST_RUNNER_OI_FIDELITY_LIST`) is turned into the one Markdown
document the benchmark scores: passages in order, the import's labels removed, the words a passage repeats from the one
before (chunk overlap) removed, and every table as a Markdown table from its stored grid (headers, then rows).

Checks are ported from olmocr/bench/tests.py and table_parsing.py (read 2026-11-08, main branch):
  present / absent  text found with at most `max_diffs` edits (the benchmark uses rapidfuzz partial_ratio against a
                    threshold of 1 - max_diffs/len; here an edit-distance substring search, Sellers' algorithm, with the
                    same allowance)
  order             `before` found starting before `after`, each within `max_diffs` edits (fuzzysearch there)
  table             a cell within the similarity threshold whose up/down/left/right neighbour and top/left heading match
                    (`fuzz.ratio` there, the indel similarity here, computed exactly); a Markdown table's first row and
                    first column are its headings
  baseline          some letters or digits, no CJK or emoji
Text is normalized as the benchmark's `normalize_text` does.

Usage:
  python3 scripts/olmocr_bench_score.py <bench dir> <run dir> [--compare <run dir>] [--list <pdf list>] [--show N]
"""

import argparse
import hashlib
import json
import re
import sys
import unicodedata
from collections import defaultdict
from pathlib import Path

CATEGORIES = {
    "headers_footers": "headers_footers.jsonl",
    "multi_column": "multi_column.jsonl",
    "tables": "table_tests.jsonl",
    "long_tiny_text": "long_tiny_text.jsonl",
    "old_scans": "old_scans.jsonl",
}
LABEL_LINE = re.compile(r"^(\[Part [0-9.]+\]|Section Path:.*|TABLE:.*|HEADERS:.*|SOURCE:.*|\[Specifications\])$")
ROW_LABEL = re.compile(r"\bROW \d+:\s*")


def normalize_text(text: str) -> str:
    text = re.sub(r"<br/?>", " ", text)
    text = re.sub(r"\*\*(.*?)\*\*", r"\1", text)
    text = re.sub(r"__(.*?)__", r"\1", text)
    text = re.sub(r"</?b>", "", text)
    text = re.sub(r"</?i>", "", text)
    text = re.sub(r"(\*\*|__)(.*?)\1", r"\2", text)
    text = re.sub(r"(\*|_)(.*?)\1", r"\2", text)
    text = re.sub(r"\s+", " ", text)
    text = unicodedata.normalize("NFC", text)
    for fancy, plain in {"‘": "'", "’": "'", "‚": "'", "“": '"', "”": '"', "„": '"', "＿": "_", "–": "-", "—": "-",
                         "‑": "-", "‒": "-", "−": "-", "µ": "μ"}.items():
        text = text.replace(fancy, plain)
    return text


def substring_matches(query: str, text: str, k: int) -> list[int]:
    """Start positions (approximate for k > 0) where `query` occurs in `text` within `k` edits (Sellers)."""
    if not query:
        return [0]
    if k == 0 or query in text:
        starts, at = [], text.find(query)
        while at != -1:
            starts.append(at)
            at = text.find(query, at + 1)
        if starts or k == 0:
            return starts
    m = len(query)
    previous = list(range(m + 1))
    ends = []
    for j, character in enumerate(text, 1):
        current = [0] * (m + 1)
        for i in range(1, m + 1):
            cost = 0 if query[i - 1] == character else 1
            current[i] = min(previous[i - 1] + cost, previous[i] + 1, current[i - 1] + 1)
        if current[m] <= k:
            ends.append(j)
        previous = current
    return [max(0, end - m) for end in ends]


def indel_ratio(a: str, b: str) -> float:
    """rapidfuzz's fuzz.ratio / 100: 1 - indel distance / (len a + len b), via the longest common subsequence."""
    if not a and not b:
        return 1.0
    if not a or not b:
        return 0.0
    previous = [0] * (len(b) + 1)
    for x in a:
        current = [0]
        for j, y in enumerate(b, 1):
            current.append(previous[j - 1] + 1 if x == y else max(previous[j], current[j - 1]))
        previous = current
    return 2 * previous[-1] / (len(a) + len(b))


def markdown_of(record: dict) -> str:
    """The document an import stored, as the one Markdown file the benchmark scores."""
    parts: list[str] = []
    seen_tables: set[str] = set()
    previous_words: list[str] = []
    for passage in record["passages"]:
        table = passage.get("table")
        if table:
            key = hashlib.sha1(json.dumps(table, sort_keys=True).encode()).hexdigest()
            if key in seen_tables:
                continue
            seen_tables.add(key)
            grid = ([table["headers"]] if table.get("headers") else []) + table.get("rows", [])
            width = max((len(row) for row in grid), default=0)
            if width == 0:
                continue
            lines = []
            for index, row in enumerate(grid):
                cells = [str(cell).replace("|", "/").replace("\n", " ") for cell in row] + [""] * (width - len(row))
                lines.append("| " + " | ".join(cells) + " |")
                if index == 0:
                    lines.append("|" + "---|" * width)
            parts.append("\n".join(lines))
            previous_words = []
            continue
        if passage.get("structure") == "table":
            continue  # the table's rows as text, its summary and "Specifications": the grid above is the table
        lines = [line for line in passage["text"].split("\n") if not LABEL_LINE.match(line.strip())]
        text = ROW_LABEL.sub("", "\n".join(lines)).strip()
        if not text:
            continue
        words = text.split()
        # Chunk overlap: the longest run of words this passage opens with that the previous one ended with.
        overlap = 0
        for size in range(min(len(words), len(previous_words), 120), 0, -1):
            if previous_words[-size:] == words[:size]:
                overlap = size
                break
        if overlap:
            text = " ".join(words[overlap:])
        previous_words = words
        if text:
            parts.append(text)
    return "\n\n".join(parts)


def markdown_tables(markdown: str) -> list[list[list[str]]]:
    tables, current = [], []
    for line in markdown.split("\n") + [""]:
        if "|" in line:
            current.append(line)
            continue
        if len(current) >= 2:
            rows = []
            for row_line in current:
                body = row_line.replace("|", "").strip()
                if body and all(c in "- :" for c in body):
                    continue
                cells = [cell.strip() for cell in row_line.split("|")]
                if cells and cells[0] == "":
                    cells = cells[1:]
                if cells and cells[-1] == "":
                    cells = cells[:-1]
                if cells:
                    rows.append(cells)
            if rows:
                tables.append(rows)
        current = []
    return tables


def run_table_check(check: dict, tables: list[list[list[str]]]) -> bool:
    k = check.get("max_diffs", 0)
    cell = normalize_text(check["cell"])

    def ok(expected: str, actual: str) -> bool:
        expected = normalize_text(expected)
        return indel_ratio(expected, normalize_text(actual)) >= max(0.5, 1 - k / max(len(expected), 1))

    for rows in tables:
        width = max(len(row) for row in rows)
        grid = [row + [""] * (width - len(row)) for row in rows]
        for r, row in enumerate(grid):
            for c, text in enumerate(row):
                if indel_ratio(cell, normalize_text(text)) < max(0.5, 1 - k / max(len(cell), 1)):
                    continue
                checks = []
                if check.get("up"):
                    checks.append(r > 0 and ok(check["up"], grid[r - 1][c]))
                if check.get("down"):
                    checks.append(r + 1 < len(grid) and ok(check["down"], grid[r + 1][c]))
                if check.get("left"):
                    checks.append(c > 0 and ok(check["left"], grid[r][c - 1]))
                if check.get("right"):
                    checks.append(c + 1 < width and ok(check["right"], grid[r][c + 1]))
                if check.get("top_heading"):
                    # Headings are row 0 and column 0; walking up a column > 0 reaches only row 0's cell, walking up
                    # column 0 reaches every cell above.
                    above = [grid[0][c]] if c > 0 and r > 0 else [grid[i][c] for i in range(r)]
                    checks.append(any(ok(check["top_heading"], text) for text in above))
                if check.get("left_heading"):
                    left = [grid[r][0]] if r > 0 and c > 0 else [grid[r][j] for j in range(c)]
                    checks.append(any(ok(check["left_heading"], text) for text in left))
                if all(checks):
                    return True
    return False


def run_check(check: dict, markdown: str, normalized: str, tables) -> bool:
    kind = check["type"]
    k = check.get("max_diffs", 0)
    if kind in ("present", "absent"):
        query = normalize_text(check["text"])
        text = normalized
        if not check.get("case_sensitive", True):
            query, text = query.lower(), text.lower()
        if check.get("first_n") and check.get("last_n"):
            text = text[: check["first_n"]] + text[-check["last_n"] :]
        elif check.get("first_n"):
            text = text[: check["first_n"]]
        elif check.get("last_n"):
            text = text[-check["last_n"] :]
        found = bool(substring_matches(query, text, k))
        return found if kind == "present" else not found
    if kind == "order":
        before = substring_matches(normalize_text(check["before"]), normalized, k)
        after = substring_matches(normalize_text(check["after"]), normalized, k)
        return any(b < a for b in before for a in after)
    if kind == "table":
        return run_table_check(check, tables)
    if kind == "baseline":
        alnum = sum(c.isalnum() for c in markdown)
        if check.get("max_length") is not None:
            return alnum <= check["max_length"]
        return alnum > 0 and not re.search(r"[一-鿿぀-ヿ]", markdown)
    return False


def score(bench: Path, run: Path, wanted: set[str] | None):
    results = defaultdict(list)
    for category, tests_file in CATEGORIES.items():
        for line in (bench / tests_file).read_text().splitlines():
            check = json.loads(line)
            if wanted is not None and check["pdf"] not in wanted:
                continue
            record_path = run / (check["pdf"].removesuffix(".pdf").replace("/", "__") + ".passages.json")
            if not record_path.exists():  # a record named by the file name alone
                record_path = run / (check["pdf"].split("/")[-1].removesuffix(".pdf") + ".passages.json")
            if not record_path.exists():
                results[category].append((check, None))
                continue
            results[category].append((check, record_path))
    cache = {}
    outcomes = defaultdict(list)
    for category, items in results.items():
        for check, record_path in items:
            if record_path is None:
                outcomes[category].append((check, False, "no record"))
                continue
            if record_path not in cache:
                markdown = markdown_of(json.loads(record_path.read_text()))
                cache[record_path] = (markdown, normalize_text(markdown), markdown_tables(markdown))
            markdown, normalized, tables = cache[record_path]
            outcomes[category].append((check, run_check(check, markdown, normalized, tables), ""))
    return outcomes


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("bench", type=Path)
    parser.add_argument("run", type=Path)
    parser.add_argument("--compare", type=Path)
    parser.add_argument("--list", type=Path, help="PDF paths (relative to bench/pdfs) to score; others are left out")
    parser.add_argument("--show", type=int, default=0)
    args = parser.parse_args()
    wanted = set(args.list.read_text().split()) if args.list else None
    current = score(args.bench, args.run, wanted)
    other = score(args.bench, args.compare, wanted) if args.compare else None

    print(f"{'category':18} {'pass':>12} {'rate':>7}" + ("   vs" if other else ""))
    rates, other_rates = [], []
    for category in CATEGORIES:
        items = current.get(category, [])
        if not items:
            continue
        passed = sum(ok for _, ok, _ in items)
        rate = passed / len(items)
        rates.append(rate)
        line = f"{category:18} {passed:>5}/{len(items):<6} {rate:7.3f}"
        if other:
            o = other[category]
            o_passed = sum(ok for _, ok, _ in o)
            other_rates.append(o_passed / len(o))
            lost = sum(1 for (_, ok1, _), (_, ok2, _) in zip(items, o) if ok2 and not ok1)
            gained = sum(1 for (_, ok1, _), (_, ok2, _) in zip(items, o) if ok1 and not ok2)
            line += f"   {o_passed:>5} ({o_passed / len(o):.3f})  +{gained} -{lost}"
        print(line)
    overall = sum(rates) / len(rates) if rates else 0
    line = f"{'MEAN of categories':18} {'':>12} {overall:7.3f}"
    if other_rates:
        line += f"   ({sum(other_rates) / len(other_rates):.3f})"
    print(line)
    if args.show:
        for category, items in current.items():
            shown = 0
            for index, (check, ok, why) in enumerate(items):
                if ok or shown >= args.show:
                    continue
                was = ""
                if other:
                    was = " (passed before)" if other[category][index][1] else ""
                span = check.get("text") or check.get("cell") or f"{check.get('before')} -> {check.get('after')}"
                print(f"  {category} {check['pdf']} {check['type']}{was}: {str(span)[:100]!r} {why}")
                shown += 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
