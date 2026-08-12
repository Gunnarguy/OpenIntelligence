# Research Fixtures

Small fixture packs adapted from public research benchmarks.

## Which pack to use

| Pack | Ground truth | Corpus per case | Use it for |
| :--- | :--- | :--- | :--- |
| `qasper_external_v1/` | QASPER, CC BY 4.0 | shared 40-paper pool | **measuring anything** |
| `tiny_research_suite/` | authored in this repo | only the files a case names | fast smoke checks |

`tiny_research_suite` ingests only the documents each case names, so its index contains nothing
that is not the answer, and its retrieval stages sit at 1.000 by construction rather than by
merit. It can catch a regression. It cannot show an improvement. `qasper_external_v1` declares a
shared `pool` that is ingested for every case, so retrieval has to beat 39 distractor papers.

Build or verify the external pack with `scripts/build_external_fixtures.py`; `--check` is offline
and validates the corpus against `fixtures.lock.json`. Full rationale is in that script's header
and in `Docs/EVALS.md`.

## Licensing

This repository is public and backs a paid application, so a non-commercial dataset cannot be
committed to it. `prepare_rag_research_fixtures.py` refuses `financebench` (CC BY-NC 4.0) and
`docvqa` unless `--accept-non-commercial` is passed, and output from those runs must stay out of
git. Note that `allenai/scifact` is CC BY-NC 2.0 while `BeIR/scifact` advertises CC BY-SA 4.0 for
substantially the same data; that disagreement is a reason to avoid it rather than to pick the
convenient answer.

Generated files from local experiments are ignored by git, because public datasets can have
license restrictions and private experiments should not be committed by accident.

Prepare the smallest useful starter pack:

```bash
python3 scripts/prepare_rag_research_fixtures.py --preset tiny
```

Run the generated manifest:


> Note: `scripts/run_rag_benchmarks.py` was removed in `abd1e3b`. Use
> `python3 scripts/run_quality_matrix.py --app <path>` or the in-app validation
> dashboard. The command below is retained for reference only.

```bash
python3 scripts/run_rag_benchmarks.py Benchmarks/ResearchFixtures/tiny_research_suite/manifest.json --open-dashboard
```

The starter pack is synthetic and research-style. It is useful for exercising
the benchmark harness immediately, but it is not an official reproduction of
Vectara Open RAGBench, FinanceBench, BEIR, MultiHop-RAG, QASPER, DocVQA, or
RAGTruth.

## Dataset Adapters

The prep script can also adapt small local/public subsets into fixture files:

- `financebench`: can download the small open-source sample when `--download`
  is passed, or read a local JSONL file.
- `beir`: can download a small BEIR subset such as `nfcorpus` when
  `--download` is passed, or read a local BEIR directory.
- `open-ragbench`: reads a local JSON/JSONL export. The main public datasets
  are larger, so the script does not download them by default.
- `multihop-rag`: reads a local JSON/JSONL export.
- `qasper`: reads a local JSON/JSONL export.
- `docvqa`: manual local import only; download requires accepting the official
  challenge/RRC terms.
- `ragtruth`: manual local import only; best used later for hallucination and
  faithfulness scoring rather than first-pass ingestion fixtures.

These adapters intentionally select tiny subsets. The benchmark app only ingests
files listed in the generated manifest.

## Why Adapted Fixtures?

Many public RAG benchmarks are JSON/corpus/qrels datasets rather than raw PDF
or image folders. This app benchmarks document ingestion and retrieval, so the
adapter writes small `.md` or `.txt` fixture files that preserve the relevant
context, source IDs, and expected answers without requiring a giant dataset
checkout.
