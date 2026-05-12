# Research Fixtures

This directory is for small local fixture packs adapted from public/research
benchmarks. Generated files are ignored by git because public datasets can have
license restrictions and private/local experiments should not be committed by
accident.

Prepare the smallest useful starter pack:

```bash
python3 scripts/prepare_rag_research_fixtures.py --preset tiny
```

Run the generated manifest:

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
