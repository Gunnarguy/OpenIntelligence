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
  answers <out dir> <baseline.json> <other.json> [...]
      Table runs with Deep Think answers (path "a", 2026-11-12): per run, how many answers hold the question's cell,
      how many errored, the median seconds, and, against the first run, the questions won and lost with a sign test,
      counted only where both runs answered (an error is not a wrong answer).
      A cell counts as in the answer by `fold` (spacing, dash forms, emphasis and citation markers ignored).
"""
import glob, json, os, re, shutil, sys, unicodedata
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


_NUM = re.compile(r"\d+(?:[.,]\d+)*")


def _numbers(text):
    """The numbers in `text`, in order: a thousands separator joined ("6,259", "184 315" with a thin or plain space),
    a decimal point kept, an en dash or "to" between two numbers left out (a range is its two ends)."""
    t = unicodedata.normalize("NFKC", text)
    t = re.sub(r"(?<=\d)[ \u2009\u202f](?=\d{3}\b)", "", t)
    out = []
    for m in _NUM.finditer(t):
        v = m.group(0)
        if re.fullmatch(r"\d{1,3}(,\d{3})+", v):
            v = v.replace(",", "")
        out.append(v.replace(",", "."))
    return out


def holds(cell, answer):
    """Whether `answer` gives `cell` (2026-11-13). First the exact rule, `fold(cell)` inside `fold(answer)`. Then, for a
    cell of two or more numbers ("993 (32.8)", "4.1-24.7", "2.48 (1.11-5.55)"), the same numbers in the same order in
    the answer with at most one other number between two of them, so "6,259 (3.4%)", "4.1 to 24.7" and "2.48 with a
    95% CI of 1.11-5.55" count and "3646 (9.7)" does not. A one-number cell keeps the exact rule."""
    if fold(cell) in fold(answer):
        return True
    want = _numbers(cell)
    if len(want) < 2:
        return False
    have = _numbers(answer)
    for start in range(len(have)):
        if have[start] != want[0]:
            continue
        i, j, gaps = 1, start + 1, 0
        while i < len(want) and j < len(have) and gaps <= 1:
            if have[j] == want[i]:
                i += 1
            else:
                gaps += 1
            j += 1
        if i == len(want):
            return True
    return False


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


def answers(out, paths):
    out = Path(out)
    gold = {}
    for l in (out / "queries.jsonl").read_text().splitlines():
        if l.strip():
            q = json.loads(l)
            if "cell" in q and fold(q["cell"]).strip():
                gold[q["qid"]] = fold(q["cell"])
    runs = []
    for p in paths:
        run = json.loads(Path(p).read_text())
        rows = {r["qid"]: r for r in run["results"] if r["qid"] in gold and ("deepAnswer" in r or "deepAnswerError" in r)}
        runs.append((Path(p).stem, rows))
    runs = [(name, rows) for name, rows in runs if rows]
    common = sorted(set.intersection(*(set(rows) for _, rows in runs))) if runs else []
    cells = {}
    for l in (out / "queries.jsonl").read_text().splitlines():
        if l.strip():
            q = json.loads(l)
            if "cell" in q and fold(q["cell"]).strip():
                cells[q["qid"]] = q["cell"]
    # `OI_STRICT=1` scores with the exact rule alone, as through 2026-11-12.
    strict = os.environ.get("OI_STRICT") == "1"
    def holds_q(text, q):
        return gold[q] in fold(text) if strict else holds(cells[q], text)
    right = lambda r, q: "deepAnswer" in r and holds_q(r["deepAnswer"], q)
    base_name, base = runs[0] if runs else ("", {})
    if runs:
        print(f"{len(common)} table questions answered in every run")
    for name, rows in runs:
        n_right = sum(right(rows[q], q) for q in common)
        errors = sum("deepAnswerError" in rows[q] for q in common)
        secs = sorted(rows[q].get("deepAnswerSeconds", 0) for q in common)
        median = secs[len(secs) // 2] if secs else 0
        line = f"{name:28s} right {n_right}/{len(common)}  errors {errors}  median {median} s"
        if name != base_name:
            # Compared only where both runs answered: a model error is not a wrong answer.
            both = [q for q in common if "deepAnswer" in rows[q] and "deepAnswer" in base[q]]
            won = sum(1 for q in both if right(rows[q], q) and not right(base[q], q))
            lost = sum(1 for q in both if right(base[q], q) and not right(rows[q], q))
            line += f"  on the {len(both)} both answered: +{won}/-{lost} p={sign_p(won, lost):.2f}"
        print(line)
    # Standard answers (path "s" with the real model): right, and how many carry an inline [S#] label.
    cite = re.compile(r"\[S\d+\]")
    std = [(name, rows) for name, rows in
           ((Path(p).stem, {r["qid"]: r for r in json.loads(Path(p).read_text())["results"]
                            if r["qid"] in gold and "answer" in r}) for p in paths) if rows]
    if std:
        shared = sorted(set.intersection(*(set(rows) for _, rows in std)))
        print(f"{len(shared)} Standard answers in every run")
        b_name, b_rows = std[0]
        for name, rows in std:
            n_right = sum(holds_q(rows[q]["answer"], q) for q in shared)
            cited = sum(bool(cite.search(rows[q]["answer"])) for q in shared)
            line = f"{name:28s} Standard right {n_right}/{len(shared)}  with a citation {cited}/{len(shared)}"
            if name != b_name:
                won = sum(1 for q in shared if holds_q(rows[q]["answer"], q) and not holds_q(b_rows[q]["answer"], q))
                lost = sum(1 for q in shared if holds_q(b_rows[q]["answer"], q) and not holds_q(rows[q]["answer"], q))
                same = sum(1 for q in shared if cite.sub("", rows[q]["answer"]).split() == cite.sub("", b_rows[q]["answer"]).split())
                line += f"  right +{won}/-{lost} p={sign_p(won, lost):.2f}  same words {same}/{len(shared)}"
            print(line)
    # Maximum answers (path "m" with the real model, 2026-11-13), scored the same way.
    mx = [(name, rows) for name, rows in
          ((Path(p).stem, {r["qid"]: r for r in json.loads(Path(p).read_text())["results"]
                           if r["qid"] in gold and ("maxAnswer" in r or "maxAnswerError" in r)}) for p in paths) if rows]
    if mx:
        shared = sorted(set.intersection(*(set(rows) for _, rows in mx)))
        print(f"{len(shared)} Maximum answers in every run")
        m_name, m_rows = mx[0]
        m_right = lambda r, q: "maxAnswer" in r and holds_q(r["maxAnswer"], q)
        for name, rows in mx:
            n_right = sum(m_right(rows[q], q) for q in shared)
            errors = sum("maxAnswerError" in rows[q] for q in shared)
            secs = sorted(rows[q].get("maxAnswerSeconds", 0) for q in shared)
            line = (f"{name:28s} Maximum right {n_right}/{len(shared)}  errors {errors}"
                    f"  median {secs[len(secs) // 2] if secs else 0} s")
            if name != m_name:
                won = sum(1 for q in shared if m_right(rows[q], q) and not m_right(m_rows[q], q))
                lost = sum(1 for q in shared if m_right(m_rows[q], q) and not m_right(rows[q], q))
                line += f"  right +{won}/-{lost} p={sign_p(won, lost):.2f}"
            print(line)


if __name__ == "__main__":
    if len(sys.argv) >= 4 and sys.argv[1] == "prepare":
        prepare(sys.argv[2], sys.argv[3])
    elif len(sys.argv) >= 5 and sys.argv[1] == "prepare-tables":
        prepare_tables(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5:])
    elif len(sys.argv) == 3 and sys.argv[1] == "merge":
        merge(sys.argv[2])
    elif len(sys.argv) >= 4 and sys.argv[1] == "answers":
        answers(sys.argv[2], sys.argv[3:])
    elif len(sys.argv) >= 4 and sys.argv[1] == "score":
        score(sys.argv[2], sys.argv[3:])
    else:
        sys.exit(__doc__)
