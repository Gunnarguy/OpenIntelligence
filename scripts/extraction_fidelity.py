#!/usr/bin/env python3
"""Score the passages an import stored against each PDF's own text layer.

Garbage in, garbage out: on 2026-11-07 a PDF with a perfect text layer stored its Table 1 as Vision OCR read it ("1-2 g"
as "1-28", "IU" as "TU"), and every later stage repeated it. This measures that for any set of PDFs.

Inputs: a folder of PDFs, each with `<name>.txt` from `pdftotext -layout <name>.pdf`, and a run folder written by
`ExtractionFidelityRecorder` (`<folder>/<label>/<name>.passages.json`).

Per file and in total:
  number recall   share of the text layer's numbers (ranges such as "1-2" are one number) found in the passages
  body num rec    the same, leaving out lines printed on three or more pages (running headers and footers such as
                  "Int. J. Mol. Sci. 2020, 21, 3624"), which the import drops on purpose; a fall in number recall that
                  body recall does not show is furniture removal, not lost content
  word recall     share of the text layer's words (3+ letters) found in the passages
  body word rec   the same without running lines
  invented numbers  numbers in the passages that the text layer never prints (misreads such as "1-28"), per 1,000
  invented words    words in the passages the text layer never prints, labels the import adds left out, per 1,000

Usage:
  python3 scripts/extraction_fidelity.py <pdf folder> <label> [--compare <other label>] [--show N]
"""

import argparse
import json
import re
import sys
import unicodedata
from collections import Counter
from pathlib import Path

NUMBER = re.compile(r"\d+(?:[.,]\d+)*(?:\s?-\s?\d+(?:[.,]\d+)*)?")
WORD = re.compile(r"[a-z]{3,}")
# Words the import writes around passages (table labels, summaries, section paths); not source text.
IMPORT_WORDS = set(
    """row rows table headers source section path column columns page values value specifications research data
    describes appears under include includes listed passage document technical reference regulatory compatibility
    category this from has the and with part image nearby before after figure caption type kind content""".split()
)


def fold(text: str) -> str:
    text = unicodedata.normalize("NFKC", text)
    for dash in ("–", "—", "−", "‐", "‑"):
        text = text.replace(dash, "-")
    return text.lower()


def numbers(text: str) -> list[str]:
    return [re.sub(r"\s", "", m.group(0)) for m in NUMBER.finditer(fold(text))]


def words(text: str) -> list[str]:
    return WORD.findall(fold(text))


def body_text(source: str) -> str:
    """The text layer without lines that repeat on three or more pages (`pdftotext` separates pages with a form feed)."""
    pages = source.split("\f")
    # Keyed with page numbers as "#", so "Int. J. Mol. Sci. 2020, 21, 3624  3 of 27" matches on every page.
    def key(line: str) -> str:
        return re.sub(r"\d+", "#", " ".join(line.split()))

    seen = Counter()
    for page in pages:
        for k in {key(line) for line in page.splitlines() if line.strip()}:
            seen[k] += 1
    running = {k for k, n in seen.items() if n >= 3 and len(re.findall(r"[A-Za-z]", k)) >= 3}
    return "\n".join(line for line in source.splitlines() if key(line) not in running)


# Labels the import writes into passages, not source text: a split part's "[Part 2.1]" line and a row's "ROW 3:".
IMPORT_LABELS = re.compile(r"^\[Part [0-9.]+\]$|\bROW \d+:\s*", re.MULTILINE)


def score(source: str, passages: list[str]) -> dict:
    stored = IMPORT_LABELS.sub(" ", "\n".join(passages))
    body = body_text(source)
    body_numbers, body_words = Counter(numbers(body)), Counter(words(body))
    src_numbers, got_numbers = Counter(numbers(source)), Counter(numbers(stored))
    src_words, got_words = Counter(words(source)), Counter(words(stored))
    number_hits = sum(min(n, got_numbers[k]) for k, n in src_numbers.items())
    body_hits = sum(min(n, got_numbers[k]) for k, n in body_numbers.items())
    word_hits = sum(min(n, got_words[k]) for k, n in src_words.items())
    body_word_hits = sum(min(n, got_words[k]) for k, n in body_words.items())
    invented_numbers = [k for k in got_numbers if k not in src_numbers]
    invented_words = [k for k in got_words if k not in src_words and k not in IMPORT_WORDS]
    got_number_total = sum(got_numbers.values()) or 1
    got_word_total = sum(got_words.values()) or 1
    return {
        "number_recall": number_hits / (sum(src_numbers.values()) or 1),
        "body_number_recall": body_hits / (sum(body_numbers.values()) or 1),
        "word_recall": word_hits / (sum(src_words.values()) or 1),
        "body_word_recall": body_word_hits / (sum(body_words.values()) or 1),
        "invented_numbers_per_k": 1000 * sum(got_numbers[k] for k in invented_numbers) / got_number_total,
        "invented_words_per_k": 1000 * sum(got_words[k] for k in invented_words) / got_word_total,
        "invented_number_examples": sorted(invented_numbers, key=lambda k: -got_numbers[k])[:12],
        "invented_word_examples": sorted(invented_words, key=lambda k: -got_words[k])[:12],
        "passages": len(passages),
    }


def run(folder: Path, label: str) -> dict:
    results = {}
    for record_path in sorted((folder / label).glob("*.passages.json")):
        record = json.loads(record_path.read_text())
        name = record_path.name.removesuffix(".passages.json")
        source_path = folder / f"{name}.txt"
        if not source_path.exists():
            continue
        result = score(source_path.read_text(errors="replace"), [p["text"] for p in record["passages"]])
        result["seconds"] = record.get("seconds", 0)
        results[name] = result
    return results


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("folder")
    parser.add_argument("label")
    parser.add_argument("--compare")
    parser.add_argument("--show", type=int, default=0)
    args = parser.parse_args()
    folder = Path(args.folder)
    current = run(folder, args.label)
    other = run(folder, args.compare) if args.compare else {}
    if not current:
        print(f"no records in {folder / args.label}")
        return 1
    keys = ["number_recall", "body_number_recall", "word_recall", "body_word_recall", "invented_numbers_per_k", "invented_words_per_k", "seconds"]
    print(f"{'file':42} {'num rec':>8} {'body num':>8} {'word rec':>8} {'body wrd':>8} {'inv num/k':>9} {'inv word/k':>10} {'s':>6}")
    totals = Counter()
    for name, r in current.items():
        line = f"{name[:42]:42} {r['number_recall']:8.3f} {r['body_number_recall']:8.3f} {r['word_recall']:8.3f} {r['body_word_recall']:8.3f} {r['invented_numbers_per_k']:9.1f} {r['invented_words_per_k']:10.1f} {r['seconds']:6.1f}"
        if name in other:
            o = other[name]
            line += f"   was {o['number_recall']:.3f} {o['body_number_recall']:.3f} {o['word_recall']:.3f} {o['body_word_recall']:.3f} {o['invented_numbers_per_k']:.1f} {o['invented_words_per_k']:.1f}"
        print(line)
        for k in keys:
            totals[k] += r[k]
        if args.show:
            print("    invented numbers:", r["invented_number_examples"][: args.show])
            print("    invented words:  ", r["invented_word_examples"][: args.show])
    n = len(current)
    print(f"{'MEAN':42} {totals['number_recall']/n:8.3f} {totals['body_number_recall']/n:8.3f} {totals['word_recall']/n:8.3f} {totals['body_word_recall']/n:8.3f} {totals['invented_numbers_per_k']/n:9.1f} {totals['invented_words_per_k']/n:10.1f} {totals['seconds']:6.1f}")
    (folder / f"{args.label}.scores.json").write_text(json.dumps(current, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
