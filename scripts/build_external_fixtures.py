#!/usr/bin/env python3
"""Build an evaluation fixture pack whose ground truth was authored outside this repository.

Why this exists
---------------
`Benchmarks/ResearchFixtures/tiny_research_suite/` is synthetic: this project wrote the
documents, chose the answers, and then graded itself against them. That measures
self-consistency rather than retrieval quality.

The sharper problem is not authorship, it is corpus construction. `run_quality_matrix.py`
creates a fresh store per (case, mode) and ingests only that case's `input_files`, so every
case has been scored against an index containing nothing but its own relevant documents. On
the 2026-08-11 run the vector stage saw between two and five candidate chunks per case, all
of them from the expected file. `R@5` asks whether the right document is in the top five
when there are at most five candidates and every one is correct, so `MRR@10 1.000` and
`R@5 1.000` were arithmetic rather than a pipeline result. Swapping in real data at n=300
would not have moved those numbers on its own.

So this pack changes three things at once:

  1. **A shared distractor pool.** The manifest carries a top-level `pool`, ingested for
     every case on top of that case's own `input_files`. Retrieval has to rank the right
     paper's chunks above every other paper in the pool. Retrieval can now fail, which is
     the property that makes an improvement measurable.
  2. **External ground truth.** Questions, answers, and supporting evidence come from
     QASPER (Dasigi et al., NAACL 2021): NLP papers with questions written by readers who
     had seen only the title and abstract, answered by separate annotators against the full
     text. Nobody involved has seen this application.
  3. **Evidence at paragraph granularity.** QASPER marks the paragraphs that support each
     answer, so `expected_evidence` records where the answer actually lives rather than only
     which file it is in. Document-level scoring is what the harness consumes today; the
     paragraph data is captured here so chunk-level scoring does not need a second download.

Licensing
---------
QASPER is CC BY 4.0, which permits commercial use with attribution, so the adapted fixtures
are committed and `ATTRIBUTION.md` carries the citation. This is deliberately not true of
every candidate dataset: FinanceBench is CC BY-NC 4.0 and `allenai/scifact` is CC BY-NC 2.0,
and neither may be committed to this repository, which is public and backs a paid
application. `BeIR/scifact` advertises CC BY-SA 4.0 for what is substantially the same data,
and that disagreement is itself a reason to leave it alone.

Reproducibility
---------------
`fixtures.lock.json` pins the dataset revision, the exact papers and questions selected, and
a SHA-256 over the generated corpus. Selection is a deterministic scan of the split in
dataset order, so a rebuild produces byte-identical output or `--check` fails.

Usage
-----
    python3 scripts/build_external_fixtures.py                 # build the pack (network)
    python3 scripts/build_external_fixtures.py --check         # verify on-disk pack (offline)
    python3 scripts/build_external_fixtures.py --papers 25 --cases 100
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_PACK = REPO_ROOT / "Benchmarks/ResearchFixtures/qasper_external_v1"

DATASET = "allenai/qasper"
CONFIG = "qasper"
SPLIT = "test"
ROWS_ENDPOINT = "https://datasets-server.huggingface.co/rows"
INFO_ENDPOINT = f"https://huggingface.co/api/datasets/{DATASET}"

LICENSE_NAME = "CC BY 4.0"
LICENSE_URL = "https://creativecommons.org/licenses/by/4.0/"
LICENSE_NOTE = (
    "QASPER (Dasigi et al., NAACL 2021), CC BY 4.0. Adapted locally: paper full text "
    "rendered to Markdown; questions, answers and evidence taken from the dataset unchanged."
)

# Categories must exist in CATEGORY_MAP in scripts/build_eval_dataset.py, which indexes that
# map directly and raises KeyError on anything else. Do not invent one here without adding it
# there in the same change.
#
# `multi_hop` is deliberately not used. It maps to `multi_document`, and every QASPER question
# is answered inside a single paper, so labelling one that way would claim a second required
# document that does not exist. Questions whose evidence spans several sections are real
# multi-chunk synthesis, which is a different thing; they carry `evidence_sections` and the
# `multi_paragraph` tag instead, so the subset stays selectable without the category lying.
CAT_EXACT = "exact_value"
CAT_FACTUAL = "retrieval_only"
CAT_MISSING = "missing_evidence"

# An answer string longer than this is a sentence rather than a fact, and matching it verbatim
# against generated prose fails for reasons that have nothing to do with retrieval.
MAX_ANSWER_CHARS = 80
MIN_AGREEMENT = 2


def http_json(url: str, params: dict[str, str] | None = None, retries: int = 4) -> dict:
    """GET JSON with backoff. The datasets server rate-limits and occasionally 500s."""
    full = url + ("?" + urllib.parse.urlencode(params) if params else "")
    last: Exception | None = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(full, headers={"User-Agent": "OpenIntelligence-fixtures"})
            with urllib.request.urlopen(req, timeout=60) as response:
                return json.loads(response.read())
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, json.JSONDecodeError) as exc:
            last = exc
            if attempt == retries - 1:
                break
            time.sleep(2 ** attempt)
    raise SystemExit(f"error: could not fetch {full}: {last}")


def dataset_revision() -> str:
    return str(http_json(INFO_ENDPOINT).get("sha") or "unknown")


def slug(value: str) -> str:
    out = re.sub(r"[^A-Za-z0-9._-]+", "-", str(value).strip())
    return re.sub(r"-{2,}", "-", out).strip("-.") or "item"


def answer_pattern(value: str) -> str:
    """Same construction as prepare_rag_research_fixtures.answer_pattern.

    Both packs must be matched by identical rules, or an accuracy difference between them
    would partly measure the matcher rather than the app.
    """
    value = " ".join(str(value).strip().split())
    if not value:
        return r"(?!)"
    if len(value) > MAX_ANSWER_CHARS:
        value = " ".join(value.split()[:10])
    escaped = re.escape(value).replace(r"\ ", r"\s+")
    return f"(?i){escaped}"


def normalise(text: str) -> str:
    return " ".join(str(text or "").strip().lower().split()).strip(" .,;:")


def dedupe(items) -> list[str]:
    """Order-preserving unique. Annotators often cite the same paragraph."""
    seen: set[str] = set()
    out: list[str] = []
    for item in items:
        key = normalise(item)
        if key and key not in seen:
            seen.add(key)
            out.append(" ".join(str(item).split()))
    return out


def rel(path: Path) -> str:
    """Repo-relative when possible; absolute otherwise, so out-of-tree pack dirs still print."""
    try:
        return str(path.relative_to(REPO_ROOT))
    except ValueError:
        return str(path)


def render_paper(record: dict) -> str:
    """Render one QASPER record as Markdown, preserving section structure.

    Section headings are kept because they are what the chunker uses to build the heading
    path, and because `expected_evidence` refers to paragraphs by section.
    """
    title = str(record.get("title") or record.get("id") or "Untitled").strip()
    parts = [f"# {title}", "", "## Abstract", "", str(record.get("abstract") or "").strip()]
    full_text = record.get("full_text") or {}
    names = full_text.get("section_name") or []
    paragraphs = full_text.get("paragraphs") or []
    for name, paras in zip(names, paragraphs):
        heading = str(name).strip() if name else "Section"
        parts += ["", f"## {heading}", ""]
        for para in paras or []:
            text = str(para).strip()
            if text:
                parts += [text, ""]
    return "\n".join(parts).rstrip() + "\n"


def section_of(evidence: str, record: dict) -> str | None:
    """Which section a piece of evidence came from, for multi-hop classification."""
    target = normalise(evidence)
    if not target:
        return None
    full_text = record.get("full_text") or {}
    names = full_text.get("section_name") or []
    paragraphs = full_text.get("paragraphs") or []
    for name, paras in zip(names, paragraphs):
        for para in paras or []:
            if normalise(para) == target:
                return str(name or "Section")
    return None


def choose_answer(annotations: list[dict]) -> dict | None:
    """Pick one expected answer from several independent annotators.

    QASPER gives up to six answers per question from different workers. Taking the first one
    would inherit whichever annotator happened to be listed first, so this requires agreement
    instead: a span, or a yes/no, that at least MIN_AGREEMENT annotators produced. Questions
    where the annotators did not converge are dropped rather than graded on a coin flip.
    """
    if not annotations:
        return None

    unanswerable = sum(1 for a in annotations if a.get("unanswerable"))
    answered = [a for a in annotations if not a.get("unanswerable")]

    # Abstention control: a clear majority saw the full paper and said it does not answer this.
    if unanswerable > len(annotations) / 2 and not answered:
        return {"kind": "unanswerable", "text": None, "agreement": unanswerable, "evidence": []}

    if not answered:
        return None

    # Extractive spans first: they are exact strings from the paper, which is what makes a
    # regex match meaningful. Count agreement on the normalised form.
    counts: Counter[str] = Counter()
    display: dict[str, str] = {}
    for annotation in answered:
        seen: set[str] = set()
        for span in annotation.get("extractive_spans") or []:
            key = normalise(span)
            if not key or key in seen:
                continue
            seen.add(key)
            counts[key] += 1
            # Deterministic representative: shortest, then lexicographic.
            current = display.get(key)
            candidate = " ".join(str(span).split())
            if current is None or (len(candidate), candidate) < (len(current), current):
                display[key] = candidate

    if counts:
        best = max(counts.items(), key=lambda kv: (kv[1], -len(kv[0]), [-ord(c) for c in kv[0]]))
        key, agreement = best
        if agreement >= MIN_AGREEMENT and len(display[key]) <= MAX_ANSWER_CHARS:
            # Evidence from the annotators who actually chose this answer. Taking it from all
            # of them instead pulls in paragraphs supporting answers that were rejected, which
            # inflates the section count and mislabels ordinary questions as multi-hop.
            supporters = [a for a in answered
                          if key in {normalise(s) for s in (a.get("extractive_spans") or [])}]
            return {"kind": "extractive", "text": display[key], "agreement": agreement,
                    "evidence": dedupe(e for a in supporters for e in (a.get("evidence") or []))}

    # Yes/no questions: majority vote, and only when it is not a tie.
    yn = Counter(str(a.get("yes_no")) for a in answered if a.get("yes_no") is not None)
    if yn:
        (value, agreement), = yn.most_common(1)
        if agreement >= MIN_AGREEMENT and list(yn.values()).count(agreement) == 1:
            supporters = [a for a in answered if str(a.get("yes_no")) == value]
            word = "Yes" if value == "True" else "No"
            return {"kind": "yes_no", "text": word, "agreement": agreement,
                    "evidence": dedupe(e for a in supporters for e in (a.get("evidence") or []))}

    return None


def build_cases(record: dict, fixture_name: str, per_paper: int) -> list[dict]:
    """Turn one paper's questions into manifest cases."""
    qas = record.get("qas") or {}
    questions = qas.get("question") or []
    question_ids = qas.get("question_id") or []
    answer_groups = qas.get("answers") or []
    cases: list[dict] = []

    for index, question in enumerate(questions):
        if len(cases) >= per_paper:
            break
        if index >= len(answer_groups):
            break
        question_text = " ".join(str(question or "").split())
        if not question_text:
            continue
        group = answer_groups[index]
        annotations = group.get("answer") or [] if isinstance(group, dict) else []
        chosen = choose_answer(annotations)
        if not chosen:
            continue

        qid = str(question_ids[index]) if index < len(question_ids) else f"q{index}"
        case_id = f"qasper_{slug(record.get('id'))}_{qid[:8]}"
        abstain = chosen["kind"] == "unanswerable"

        sections = []
        for evidence in chosen["evidence"]:
            section = section_of(evidence, record)
            if section and section not in sections:
                sections.append(section)

        if abstain:
            category = CAT_MISSING
        elif chosen["kind"] == "extractive":
            category = CAT_EXACT
        else:
            category = CAT_FACTUAL

        case = {
            "id": case_id,
            "category": category,
            "input_files": [],  # the pool is the corpus; see manifest["pool"]
            "query": question_text,
            # Uniformly standard. `run_quality_matrix.py` passes its own `--modes` sweep to the
            # app and ignores this field, so a per-case mode here would describe a run that
            # never happens, and would confound a retrieval comparison if it ever were read.
            "quality_mode": "standard",
            "expected_behavior": "abstain" if abstain else "answer",
            "expected_answer_patterns": [] if abstain else [answer_pattern(chosen["text"])],
            "expected_source": {"filename": None if abstain else fixture_name, "page": None},
            "expected_sources": [] if abstain else [{"filename": fixture_name, "page": None}],
            # Paragraph-level truth. The harness scores documents today; this is the data a
            # chunk-level scorer needs, recorded now so it does not require a second download.
            "expected_evidence": [
                {"section": section_of(e, record), "excerpt": " ".join(str(e).split())[:160]}
                for e in chosen["evidence"][:4]
            ],
            "annotator_agreement": chosen["agreement"],
            "answer_kind": chosen["kind"],
            "evidence_sections": sections,
            "tags": ["multi_paragraph"] if len(sections) >= 2 else [],
            "source_dataset": "QASPER",
            "license_note": LICENSE_NOTE,
            "paper_id": str(record.get("id")),
            "question_id": qid,
        }
        cases.append(case)
    return cases


def corpus_sha256(fixtures_dir: Path) -> str:
    h = hashlib.sha256()
    for path in sorted(fixtures_dir.rglob("*")):
        if path.is_file():
            h.update(path.name.encode())
            h.update(path.read_bytes())
    return h.hexdigest()


def write_attribution(pack_dir: Path, revision: str, papers: list[str]) -> None:
    lines = [
        "# Attribution and licence",
        "",
        f"The documents in `fixtures/` are adapted from **QASPER**, used under {LICENSE_NAME}.",
        "",
        "> Pradeep Dasigi, Kyle Lo, Iz Beltagy, Arman Cohan, Noah A. Smith, Matt Gardner.",
        "> *A Dataset of Information-Seeking Questions and Answers Anchored in Research Papers.*",
        "> NAACL 2021.",
        "",
        f"- Source: <https://huggingface.co/datasets/{DATASET}>",
        f"- Dataset revision: `{revision}`",
        f"- Licence: [{LICENSE_NAME}]({LICENSE_URL})",
        f"- Split: `{SPLIT}`, config `{CONFIG}`, {len(papers)} papers",
        "",
        "**Changes made.** Each paper's title, abstract and full text were rendered to Markdown",
        "with section headings preserved. Questions, answers and evidence are reproduced from the",
        "dataset without modification. No content was added.",
        "",
        "## Datasets deliberately not used here",
        "",
        "This repository is public and backs a paid application, so a dataset that forbids",
        "commercial use cannot be committed to it.",
        "",
        "| Dataset | Licence | Status |",
        "| :--- | :--- | :--- |",
        "| `allenai/qasper` | CC BY 4.0 | used, attributed above |",
        "| `PatronusAI/financebench` | CC BY-NC 4.0 | excluded, non-commercial |",
        "| `allenai/scifact` | CC BY-NC 2.0 | excluded, non-commercial |",
        "| `BeIR/scifact` | CC BY-SA 4.0 | excluded, conflicts with the line above |",
        "| `BeIR/nfcorpus` | CC BY-SA 4.0 | permitted, share-alike on any derived files |",
        "",
        "Licence values were read from the Hugging Face dataset cards. This is a record of what",
        "the cards said, not legal advice.",
        "",
    ]
    (pack_dir / "ATTRIBUTION.md").write_text("\n".join(lines), encoding="utf-8")


def write_readme(pack_dir: Path, cases: list[dict], pool: list[str], revision: str) -> None:
    by_category = Counter(c["category"] for c in cases)
    n = len(cases)
    floor = f"{6 / n * 100:.0f}" if n >= 6 else "n/a"
    lines = [
        f"# {pack_dir.name}",
        "",
        "Generated by `scripts/build_external_fixtures.py`. Do not edit by hand.",
        "",
        "Ground truth here was authored outside this repository. Questions, answers and evidence",
        "come from QASPER; this project chose none of them. See `ATTRIBUTION.md` for the licence.",
        "",
        "## What it measures that the synthetic suite cannot",
        "",
        f"Every case is scored against the shared pool of {len(pool)} papers declared in",
        "`manifest.json`, so each question carries "
        f"{len(pool) - 1} distractor documents. The synthetic suite ingests only the files a case",
        "names, which left the vector stage ranking two to five candidates that were all correct,",
        "so `R@5` and `MRR@10` were pinned at 1.000 by arithmetic. Retrieval can fail here, which",
        "is the property that lets an improvement show up at all.",
        "",
        "| | |",
        "| :--- | :--- |",
        f"| Cases | {n} |",
        f"| Pool documents | {len(pool)} |",
        f"| Smallest resolvable difference | about {floor} points (`6/n`, exact sign test) |",
        f"| Dataset revision | `{revision}` |",
        "",
        "By category: " + ", ".join(f"`{k}` {v}" for k, v in sorted(by_category.items())) + ".",
        "",
        "## Running it",
        "",
        "```bash",
        "python3 scripts/run_quality_matrix.py --app <path/to/OpenIntelligence.app> \\",
        f"  --manifest Benchmarks/ResearchFixtures/{pack_dir.name}/manifest.json \\",
        "  --modes standard --pcc deny",
        "```",
        "",
        "Verify the corpus matches its lock, offline:",
        "",
        "```bash",
        "python3 scripts/build_external_fixtures.py --check",
        "```",
        "",
        "## Comparability",
        "",
        "**Do not compare any figure here against a `tiny_research_suite` run.** Different corpus,",
        "different ground truth, different difficulty. The two packs answer different questions and",
        "a delta between them measures the fixture, not the app.",
        "",
    ]
    (pack_dir / "README.md").write_text("\n".join(lines), encoding="utf-8")


def build(pack_dir: Path, want_papers: int, want_cases: int, per_paper: int) -> int:
    revision = dataset_revision()
    print(f"{DATASET} revision {revision}")

    fixtures_dir = pack_dir / "fixtures"
    if fixtures_dir.exists():
        for path in sorted(fixtures_dir.rglob("*"), reverse=True):
            path.unlink() if path.is_file() else path.rmdir()
    fixtures_dir.mkdir(parents=True, exist_ok=True)

    pool: list[str] = []
    paper_ids: list[str] = []
    cases: list[dict] = []
    offset = 0
    page = 5

    # Deterministic scan in dataset order. Recorded in the lock, so the selection is
    # reproducible without re-deriving the filter logic.
    while len(paper_ids) < want_papers and len(cases) < want_cases:
        payload = http_json(ROWS_ENDPOINT, {
            "dataset": DATASET, "config": CONFIG, "split": SPLIT,
            "offset": str(offset), "length": str(page),
        })
        rows = payload.get("rows") or []
        if not rows:
            break
        offset += len(rows)

        for row in rows:
            if len(paper_ids) >= want_papers:
                break
            record = row.get("row") or {}
            paper_id = str(record.get("id") or "")
            if not paper_id or not (record.get("full_text") or {}).get("paragraphs"):
                continue
            fixture_name = f"{slug(paper_id)}.md"
            new_cases = build_cases(record, fixture_name, per_paper)
            if not new_cases:
                continue
            (fixtures_dir / fixture_name).write_text(render_paper(record), encoding="utf-8")
            pool.append(rel(fixtures_dir / fixture_name))
            paper_ids.append(paper_id)
            cases.extend(new_cases)
            print(f"  {paper_id:<14} {len(new_cases)} cases", flush=True)

    cases = cases[:want_cases]
    # Every case is scored against the whole pool, so each one carries `len(pool) - 1`
    # distractor papers. That is the number that matters: it is what the old suite had none of.
    print(f"\n{len(cases)} cases over a {len(pool)}-paper pool "
          f"({len(pool) - 1} distractor papers per case)")

    manifest = {
        "version": 1,
        "name": pack_dir.name,
        "description": (
            "Evaluation pack with external ground truth. Questions, answers and evidence come "
            "from QASPER; this project authored none of them. Every case is scored against the "
            "shared `pool`, so retrieval must rank the right paper above the others."
        ),
        "defaults": {"quality_mode": "standard", "timeout_seconds": 420},
        "pool": sorted(pool),
        "fixture_sources": [{
            "name": "QASPER",
            "status": f"downloaded, revision {revision}",
            "license": LICENSE_NAME,
            "url": f"https://huggingface.co/datasets/{DATASET}",
        }],
        "cases": cases,
    }
    manifest_path = pack_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    write_attribution(pack_dir, revision, paper_ids)
    write_readme(pack_dir, cases, pool, revision)

    lock = {
        "dataset": DATASET,
        "config": CONFIG,
        "split": SPLIT,
        "hf_revision": revision,
        "license": LICENSE_NAME,
        "selection": {
            "order": "dataset order, first N papers yielding at least one agreed answer",
            "papers_requested": want_papers,
            "cases_requested": want_cases,
            "max_cases_per_paper": per_paper,
            "min_annotator_agreement": MIN_AGREEMENT,
            "max_answer_chars": MAX_ANSWER_CHARS,
        },
        "paper_ids": paper_ids,
        "case_ids": [c["id"] for c in cases],
        "counts": {
            "papers": len(pool),
            "cases": len(cases),
            "by_category": dict(sorted(Counter(c["category"] for c in cases).items())),
        },
        "fixtures_sha256": corpus_sha256(fixtures_dir),
        "manifest_sha256": hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
    }
    (pack_dir / "fixtures.lock.json").write_text(
        json.dumps(lock, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(f"categories: {lock['counts']['by_category']}")
    print(f"wrote {rel(pack_dir)}")
    return 0


def check(pack_dir: Path) -> int:
    """Verify the committed pack matches its lock. Offline on purpose."""
    lock_path = pack_dir / "fixtures.lock.json"
    manifest_path = pack_dir / "manifest.json"
    if not lock_path.exists():
        print(f"error: {rel(lock_path)} is missing", file=sys.stderr)
        return 1
    lock = json.loads(lock_path.read_text())

    problems: list[str] = []
    actual_fixtures = corpus_sha256(pack_dir / "fixtures")
    if actual_fixtures != lock.get("fixtures_sha256"):
        problems.append(f"fixtures sha mismatch: {actual_fixtures} != {lock.get('fixtures_sha256')}")
    actual_manifest = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
    if actual_manifest != lock.get("manifest_sha256"):
        problems.append(f"manifest sha mismatch: {actual_manifest} != {lock.get('manifest_sha256')}")

    manifest = json.loads(manifest_path.read_text())
    missing = [p for p in manifest.get("pool", []) if not (REPO_ROOT / p).exists()]
    if missing:
        problems.append(f"{len(missing)} pool files missing, first: {missing[0]}")
    ids = [c["id"] for c in manifest.get("cases", [])]
    if ids != lock.get("case_ids"):
        problems.append("case ids differ from the lock")

    if problems:
        for problem in problems:
            print(f"error: {problem}", file=sys.stderr)
        print("       rebuild: python3 scripts/build_external_fixtures.py", file=sys.stderr)
        return 1

    counts = lock.get("counts", {})
    print(f"OK: {pack_dir.name} matches its lock "
          f"({counts.get('cases')} cases, {counts.get('papers')} papers, "
          f"{lock.get('dataset')} @ {str(lock.get('hf_revision'))[:12]}).")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--pack-dir", default=str(DEFAULT_PACK))
    parser.add_argument("--papers", type=int, default=25, help="papers in the shared pool")
    parser.add_argument("--cases", type=int, default=100, help="maximum cases in the pack")
    parser.add_argument("--per-paper", type=int, default=5, help="maximum cases from one paper")
    parser.add_argument("--check", action="store_true", help="verify the on-disk pack, no network")
    args = parser.parse_args()

    pack_dir = Path(args.pack_dir)
    if args.check:
        return check(pack_dir)
    pack_dir.mkdir(parents=True, exist_ok=True)
    return build(pack_dir, args.papers, args.cases, args.per_paper)


if __name__ == "__main__":
    raise SystemExit(main())
