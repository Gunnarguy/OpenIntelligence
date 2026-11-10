#!/usr/bin/env python3
"""Does the passage that answers a question reach the model? Prepare and score EvidenceReachBenchmarkTests runs.

  prepare <qasper dir> <out dir>
      <qasper dir> holds passages.jsonl and queries.jsonl from BenchmarkRuns/2026-11-09-reranker-swap/scripts/
      qasper_prep.py (QASPER, CC BY 4.0: the papers' paragraphs and the annotators' evidence paragraphs). Writes one
      Markdown file per paper to <out dir>/fixtures/ (title, then each section heading and its paragraphs, in order)
      and <out dir>/queries.jsonl (qid, query, gold paragraph texts).

  prepare-tables <checks dir> <pdf dir> <out dir> [extra checks.jsonl ...]
      Table questions from page-image table checks, one per numeric cell under a named column; scored by whether the
      cell's exact text (spacing and dash forms ignored) reached the model, is in Deep Think's passages, and, in a run
      with Apple's model, is in the answer.

  score <out dir> <baseline.json> <other.json> [...]
      For each run, per question: Standard "reached" when a gold paragraph is in the context given to the model,
      Deep Think "hit@1"/"hit@5" when a gold paragraph is in its first one or five passages. A gold paragraph is "in" a
      text when at least half of its distinct words of four or more letters appear there (Standard hands the model
      chosen sentences, and the app splits and prefixes paragraphs its own way); "coverage" is that fraction for the
      best gold paragraph, averaged, compared question by question at a 0.05 margin. Each run after the first is compared with the first, question by question, with
      a two-sided sign test.
"""
import glob, json, re, shutil, sys, unicodedata
from math import comb
from pathlib import Path

WORD = re.compile(r"[a-z0-9]{4,}")
# A gold paragraph counts as present at half its distinct words: Standard hands the model chosen sentences, and the
# app splits long paragraphs, so a whole paragraph rarely appears even when its answer does (2026-11-09 trial).
NEED = 0.50


def words(text):
    return set(WORD.findall(text.lower()))


def covered(gold_words, text_words, need=0.70):
    return bool(gold_words) and len(gold_words & text_words) / len(gold_words) >= need


def sign_p(w, l):
    n = w + l
    return 1.0 if n == 0 else min(1.0, 2 * sum(comb(n, i) for i in range(min(w, l) + 1)) / 2 ** n)


def prepare(src, out):
    src, out = Path(src), Path(out)
    passages = [json.loads(l) for l in (src / "passages.jsonl").read_text().splitlines() if l.strip()]
    by_id = {p["pid"]: p for p in passages}
    papers = {}
    for p in passages:
        papers.setdefault(p["paper"], []).append(p)
    fixtures = out / "fixtures"
    fixtures.mkdir(parents=True, exist_ok=True)
    for paper, ps in papers.items():
        lines = [f"# {ps[0]['title']}", ""]
        last = None
        for p in sorted(ps, key=lambda p: int(p["pid"].split("#")[1])):
            if p["section"] and p["section"] != last:
                lines += [f"## {p['section']}", ""]
                last = p["section"]
            lines += [p["text"], ""]
        (fixtures / f"{paper}.md").write_text("\n".join(lines))
    with open(out / "queries.jsonl", "w") as f:
        for l in (src / "queries.jsonl").read_text().splitlines():
            if not l.strip():
                continue
            q = json.loads(l)
            gold = [by_id[g]["text"] for g in q["gold"] if g in by_id]
            if gold:
                f.write(json.dumps({"qid": q["qid"], "paper": q["paper"], "query": q["query"], "gold": gold}) + "\n")
    print(f"{len(papers)} fixtures, {sum(1 for _ in open(out / 'queries.jsonl'))} questions -> {out}")


def best_cover(gold_words, text_words):
    return max((len(w & text_words) / len(w) for w in gold_words if w), default=0.0)


def fold(text):
    """For matching a table cell: NFKC, dashes and minus signs to '-', lower case, every space removed (cells print
    "15 179" with thin spaces; the app may store them run together or spaced)."""
    t = unicodedata.normalize("NFKC", text).lower()
    t = re.sub(r"[\u2010-\u2015\u2212]", "-", t)
    # Citation markers ("[59]" printed in a cell, "[S2]" in an answer) and Markdown emphasis are not the value: an
    # answer "**14** [48]" gives the cell "14 [48]" (2026-11-10 run).
    t = re.sub(r"\[[^\]]*\]", "", t).replace("*", "").replace("_", "")
    return re.sub(r"\s+", "", t)


def prepare_tables(checks, pdfs, out, extra=()):
    """Questions from the page-image table checks (BenchmarkRuns/2026-11-08-extraction-fidelity/checks): one per
    numeric cell under a named column, "What value is given for <row> under <column>?", answered by the cell."""
    out = Path(out)
    (out / "fixtures").mkdir(parents=True, exist_ok=True)
    n = 0
    with open(out / "queries.jsonl", "w") as f:
        for path in sorted(glob.glob(str(Path(checks) / "*.jsonl"))) + list(extra):
            name = Path(path).stem
            pdf = Path(pdfs) / f"{name}.pdf"
            if not pdf.exists():
                continue
            rows = [json.loads(l) for l in open(path) if l.strip()]
            used = 0
            for c in rows:
                if c["type"] != "table" or not re.search(r"\d", c["cell"]) or re.fullmatch(r"\s*\d+\s*", c["column"]):
                    continue
                q = f"What value is given for {c['row']} under {c['column']}?"
                qid = f"{name}#{c['page']}#{used}"
                f.write(json.dumps({"qid": qid, "paper": name, "query": q, "cell": c["cell"]}) + "\n")
                used += 1
                n += 1
            if used:
                shutil.copy(pdf, out / "fixtures" / pdf.name)
    print(f"{n} table questions, {len(list((out / 'fixtures').iterdir()))} PDFs -> {out}")


def measures(run, gold):
    rows = {}
    for r in run["results"]:
        g = gold.get(r["qid"])
        if not g:
            continue
        if isinstance(g, dict):  # a table question: the cell itself must be there
            cell = fold(g["cell"])
            ctx = r.get("standardContext") or "\n".join(r.get("standardSources", []))
            reached = cell in fold(ctx)
            deep = [cell in fold(t) for t in r.get("deepThink", [])]
            first = next((i for i, hit in enumerate(deep) if hit), None)
            rows[r["qid"]] = {"cover": 1.0 if reached else 0.0, "std": reached, "dt1": first == 0,
                              "dt5": first is not None and first < 5,
                              "answer": ("answer" in r) and cell in fold(r["answer"])}
            continue
        gw = [words(t) for t in g]
        cover = best_cover(gw, words(r.get("standardContext", "")))
        deep = [best_cover(gw, words(t)) for t in r.get("deepThink", [])]
        first = next((i for i, c in enumerate(deep) if c >= NEED), None)
        rows[r["qid"]] = {"cover": cover, "std": cover >= NEED, "dt1": first == 0, "dt5": first is not None and first < 5}
    return rows


def score(out, paths):
    out = Path(out)
    gold = {}
    for l in (out / "queries.jsonl").read_text().splitlines():
        if l.strip():
            q = json.loads(l)
            gold[q["qid"]] = {"cell": q["cell"]} if "cell" in q else q["gold"]
    runs = [(Path(p).stem, json.loads(Path(p).read_text())) for p in paths]
    base_name, base = runs[0]
    b = measures(base, gold)
    print(f"{'run':30s} {'n':>4s}  {'Std coverage':>22s}  {'Std reached':>20s}  {'DT hit@1':>20s}  {'DT hit@5':>20s}  ablated")
    for name, run in runs:
        m = measures(run, gold)
        common = sorted(set(m) & set(b))
        n = len(common)
        if n == 0:
            continue
        mean = sum(m[q]["cover"] for q in common) / n
        if name == base_name:
            cells = [f"{mean:.3f}"]
        else:
            up = sum(1 for q in common if m[q]["cover"] > b[q]["cover"] + 0.05)
            down = sum(1 for q in common if m[q]["cover"] < b[q]["cover"] - 0.05)
            cells = [f"{mean:.3f} +{up}/-{down} p={sign_p(up, down):.2f}"]
        paths = run.get("paths", "sd")
        if "s" not in paths:
            cells = ["-"]
        for key in ("std", "dt1", "dt5"):
            if ("s" if key == "std" else "d") not in paths:
                cells.append("-")
                continue
            rate = sum(m[q][key] for q in common) / n
            if name == base_name:
                cells.append(f"{rate:6.1%}")
            else:
                won = sum(1 for q in common if m[q][key] and not b[q][key])
                lost = sum(1 for q in common if b[q][key] and not m[q][key])
                cells.append(f"{rate:6.1%} +{won}/-{lost} p={sign_p(won, lost):.2f}")
        answered = [q for q in common if "answer" in next((r for r in run["results"] if r["qid"] == q), {})]
        if answered:
            cells[-1] += f"  answers right {sum(m[q].get('answer', False) for q in answered)}/{len(answered)}"
        print(f"{name:30s} {n:4d}  {cells[0]:>22s}  {cells[1]:>20s}  {cells[2]:>20s}  {cells[3]:>20s}  "
              f"{','.join(run.get('ablated', [])) or '-'}")


def merge(out):
    """Join each configuration's slice files (reach-<name>-s<i>.json) into reach-<name>.json."""
    out = Path(out)
    groups = {}
    for p in sorted(out.glob("reach-*-s[0-9]*.json")):
        name = p.stem[len("reach-"):].rsplit("-s", 1)[0]
        groups.setdefault(name, []).append(json.loads(p.read_text()))
    for name, parts in groups.items():
        joined = dict(parts[0])
        joined["results"] = [r for part in parts for r in part["results"]]
        joined["slices"] = len(parts)
        joined["seconds"] = max(part["seconds"] for part in parts)
        (out / f"reach-{name}.json").write_text(json.dumps(joined))
        print(f"{name}: {len(parts)} slices, {len(joined['results'])} questions")


if __name__ == "__main__":
    if len(sys.argv) >= 4 and sys.argv[1] == "prepare":
        prepare(sys.argv[2], sys.argv[3])
    elif len(sys.argv) >= 5 and sys.argv[1] == "prepare-tables":
        prepare_tables(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5:])
    elif len(sys.argv) == 3 and sys.argv[1] == "merge":
        merge(sys.argv[2])
    elif len(sys.argv) >= 4 and sys.argv[1] == "score":
        score(sys.argv[2], sys.argv[3:])
    else:
        sys.exit(__doc__)
