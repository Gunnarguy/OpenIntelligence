#!/usr/bin/env python3
"""Prepare small local RAG benchmark fixture packs.

The generated manifests are consumed by scripts/run_rag_benchmarks.py. This
script does not execute app code and does not change RAG behavior.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import textwrap
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT_ROOT = REPO_ROOT / "Benchmarks" / "ResearchFixtures"
DEFAULT_PACK_NAME = "tiny_research_suite"

FINANCEBENCH_JSONL_URL = (
    "https://raw.githubusercontent.com/patronus-ai/financebench/main/"
    "data/financebench_open_source.jsonl"
)
BEIR_DOWNLOADS = {
    "nfcorpus": "https://public.ukp.informatik.tu-darmstadt.de/thakur/BEIR/datasets/nfcorpus.zip",
    "scifact": "https://public.ukp.informatik.tu-darmstadt.de/thakur/BEIR/datasets/scifact.zip",
}


class FixturePrepError(Exception):
    """Raised for fixture prep problems."""


@dataclass
class PreparedCase:
    case: dict[str, Any]


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(REPO_ROOT))
    except ValueError:
        return str(path)


def slug(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9_.-]+", "-", value.strip())
    return cleaned.strip("-") or "case"


def ensure_clean_pack(pack_dir: Path, overwrite: bool) -> None:
    if pack_dir.exists() and overwrite:
        shutil.rmtree(pack_dir)
    pack_dir.mkdir(parents=True, exist_ok=True)
    (pack_dir / "fixtures").mkdir(parents=True, exist_ok=True)
    (pack_dir / "downloads").mkdir(parents=True, exist_ok=True)


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content.strip() + "\n", encoding="utf-8")


def answer_pattern(value: str) -> str:
    value = " ".join(str(value).strip().split())
    if not value:
        return r"(?!)"
    if len(value) > 80:
        value = " ".join(value.split()[:10])
    escaped = re.escape(value)
    escaped = escaped.replace(r"\ ", r"\s+")
    return f"(?i){escaped}"


def make_case(
    *,
    case_id: str,
    category: str,
    input_files: list[Path],
    query: str,
    expected_behavior: str,
    expected_patterns: list[str] | None = None,
    expected_source: Path | None = None,
    quality_mode: str = "standard",
    source_dataset: str,
    license_note: str,
) -> PreparedCase:
    return PreparedCase(
        {
            "id": case_id,
            "category": category,
            "input_files": [rel(path) for path in input_files],
            "query": query,
            "quality_mode": quality_mode,
            "expected_behavior": expected_behavior,
            "expected_answer_patterns": expected_patterns or [],
            "expected_source": {
                "filename": expected_source.name if expected_source else None,
                "page": None,
            },
            "source_dataset": source_dataset,
            "license_note": license_note,
        }
    )


def load_json_or_jsonl(path: Path) -> list[dict[str, Any]]:
    text = path.read_text(encoding="utf-8")
    if path.suffix.lower() == ".jsonl":
        return [json.loads(line) for line in text.splitlines() if line.strip()]
    data = json.loads(text)
    if isinstance(data, list):
        return [item for item in data if isinstance(item, dict)]
    if isinstance(data, dict):
        for key in ("data", "train", "examples", "records", "cases"):
            value = data.get(key)
            if isinstance(value, list):
                return [item for item in value if isinstance(item, dict)]
        return [data]
    raise FixturePrepError(f"Unsupported JSON shape in {path}")


def download_file(url: str, destination: Path) -> Path:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url, timeout=60) as response:
        destination.write_bytes(response.read())
    return destination


def write_manifest(pack_dir: Path, cases: list[PreparedCase], sources: list[dict[str, str]]) -> Path:
    manifest = {
        "version": 1,
        "name": pack_dir.name,
        "description": (
            "Small adapted research fixture pack. This is not a full official "
            "benchmark reproduction."
        ),
        "defaults": {
            "quality_mode": "standard",
            "timeout_seconds": 420,
        },
        "fixture_sources": sources,
        "cases": [item.case for item in cases],
    }
    path = pack_dir / "manifest.json"
    path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


class SyntheticTinyAdapter:
    source_name = "synthetic_research_starter"
    license_note = "Generated locally by OpenIntelligence fixture script; no external dataset content."

    def prepare(self, pack_dir: Path) -> list[PreparedCase]:
        fixtures = pack_dir / "fixtures" / "synthetic"
        cases: list[PreparedCase] = []

        exact_specs = [
            ("exact_fuel_capacity", "vehicle_specs.md", "14.3 US gal", "How many gallons of gasoline can the vehicle hold?"),
            ("exact_capex", "finance_cash_flow.md", "$1,577 million", "What was the FY2018 capital expenditure amount?"),
            ("exact_payload", "equipment_table.md", "1,240 lb", "What is the maximum payload in the specification table?"),
            ("exact_service_interval", "service_schedule.md", "7,500 miles", "What is the normal service interval?"),
            ("exact_temperature_limit", "battery_limits.md", "45 C", "What is the maximum charging temperature limit?"),
        ]
        for case_id, filename, answer, query in exact_specs:
            path = fixtures / "exact" / filename
            write_text(
                path,
                f"""
                # Local Exact-Value Fixture

                Source style: finance/specification QA.

                | Field | Value |
                | --- | --- |
                | Primary answer | {answer} |
                | Control value | 88 units |

                The primary answer is intentionally explicit for exact-value retrieval.
                """,
            )
            cases.append(
                make_case(
                    case_id=case_id,
                    category="exact_value",
                    input_files=[path],
                    query=query,
                    expected_behavior="answer",
                    expected_patterns=[answer_pattern(answer)],
                    expected_source=path,
                    source_dataset="synthetic_financebench_style",
                    license_note=self.license_note,
                )
            )

        retrieval_specs = [
            ("retrieval_policy_alpha", "retrieval_alpha.md", "ALPHA-17", "Which document mentions the ALPHA-17 review control?"),
            ("retrieval_trial_beta", "retrieval_beta.md", "BETA trial cohort", "Which fixture describes the BETA trial cohort?"),
            ("retrieval_covid_gamma", "retrieval_gamma.md", "GAMMA neutralization assay", "Find the source about the GAMMA neutralization assay."),
            ("retrieval_scifact_delta", "retrieval_delta.md", "DELTA citation screen", "Which file discusses the DELTA citation screen?"),
            ("retrieval_nfcorpus_epsilon", "retrieval_epsilon.md", "EPSILON nutrition endpoint", "Find the EPSILON nutrition endpoint note."),
        ]
        for case_id, filename, answer, query in retrieval_specs:
            path = fixtures / "retrieval" / filename
            write_text(
                path,
                f"""
                # Retrieval Fixture

                This document is designed for source retrieval. The target phrase is:

                {answer}

                It includes distractor text about unrelated protocols, tables, and dates.
                """,
            )
            cases.append(
                make_case(
                    case_id=case_id,
                    category="retrieval_only",
                    input_files=[path],
                    query=query,
                    expected_behavior="answer",
                    expected_patterns=[answer_pattern(answer)],
                    expected_source=path,
                    source_dataset="synthetic_beir_style",
                    license_note=self.license_note,
                )
            )

        for idx in range(1, 6):
            a_path = fixtures / "multi_hop" / f"case_{idx}_part_a.md"
            b_path = fixtures / "multi_hop" / f"case_{idx}_part_b.md"
            project = f"Project M{idx}"
            owner = f"Owner-{idx}A"
            deadline = f"Q{idx if idx < 5 else 4} review gate"
            write_text(
                a_path,
                f"""
                # {project} Ownership Memo

                The accountable owner for {project} is {owner}. This memo does
                not include the review deadline.
                """,
            )
            write_text(
                b_path,
                f"""
                # {project} Compliance Memo

                The reporting deadline for {project} is the {deadline}. This
                memo does not list the owner.
                """,
            )
            cases.append(
                make_case(
                    case_id=f"multi_hop_project_m{idx}",
                    category="multi_hop",
                    input_files=[a_path, b_path],
                    query=f"Who owns {project} and what is its reporting deadline?",
                    quality_mode="deep-think",
                    expected_behavior="answer",
                    expected_patterns=[answer_pattern(owner), answer_pattern(deadline)],
                    expected_source=a_path,
                    source_dataset="synthetic_multihop_rag_style",
                    license_note=self.license_note,
                )
            )

        for position in ("beginning", "middle", "end"):
            path = fixtures / "lost_in_middle" / f"answer_at_{position}.md"
            answer = f"LITM-{position.upper()}-42"
            filler = "\n\n".join(
                f"Filler paragraph {i}: unrelated operational notes about calibration, routing, and glossary terms."
                for i in range(1, 18)
            )
            answer_block = f"Answer-bearing passage: the required validation token is {answer}."
            if position == "beginning":
                content = f"{answer_block}\n\n{filler}"
            elif position == "middle":
                parts = filler.split("\n\n")
                content = "\n\n".join(parts[:8] + [answer_block] + parts[8:])
            else:
                content = f"{filler}\n\n{answer_block}"
            write_text(path, f"# Lost-in-the-Middle Fixture\n\n{content}")
            cases.append(
                make_case(
                    case_id=f"lost_in_middle_{position}",
                    category="lost_in_middle",
                    input_files=[path],
                    query="What is the required validation token?",
                    quality_mode="maximum",
                    expected_behavior="answer",
                    expected_patterns=[answer_pattern(answer)],
                    expected_source=path,
                    source_dataset="synthetic_lost_in_the_middle",
                    license_note=self.license_note,
                )
            )

        missing_specs = [
            ("missing_unreleased_battery", "missing_battery_policy.md", "What is the warranty coverage for the unreleased 2032 prototype battery pack?"),
            ("missing_confidential_price", "missing_price_policy.md", "What is the confidential wholesale price for the unannounced Omega device?"),
        ]
        for case_id, filename, query in missing_specs:
            path = fixtures / "missing" / filename
            write_text(
                path,
                """
                # Missing Evidence Fixture

                This document contains public support policy, safety, and
                troubleshooting information. It intentionally does not contain
                the answer requested by the benchmark query.
                """,
            )
            cases.append(
                make_case(
                    case_id=case_id,
                    category="missing_evidence",
                    input_files=[path],
                    query=query,
                    expected_behavior="abstain",
                    expected_patterns=[],
                    expected_source=path,
                    source_dataset="synthetic_negative_control",
                    license_note=self.license_note,
                )
            )

        return cases


class FinanceBenchAdapter:
    source_name = "financebench"
    license_note = "FinanceBench open-source sample is CC BY-NC 4.0; generated local fixtures are adapted excerpts."

    def prepare(self, pack_dir: Path, input_path: Path | None, download: bool, limit: int) -> list[PreparedCase]:
        if input_path is None:
            if not download:
                return []
            input_path = download_file(FINANCEBENCH_JSONL_URL, pack_dir / "downloads" / "financebench_open_source.jsonl")
        records = load_json_or_jsonl(input_path)
        cases: list[PreparedCase] = []
        for record in records:
            if len(cases) >= limit:
                break
            evidence = record.get("evidence") or []
            if not evidence:
                continue
            first = evidence[0]
            doc_name = str(first.get("evidence_doc_name") or record.get("doc_name") or f"financebench_{len(cases)}")
            page = first.get("evidence_page_num")
            evidence_text = first.get("evidence_text_full_page") or first.get("evidence_text") or record.get("justification") or ""
            answer = str(record.get("answer") or "").strip()
            question = str(record.get("question") or "").strip()
            if not question or not answer or not evidence_text:
                continue
            path = pack_dir / "fixtures" / "financebench" / f"{slug(doc_name)}_page_{page if page is not None else 'x'}.md"
            write_text(
                path,
                f"""
                # FinanceBench Adapted Evidence

                Document: {doc_name}
                Page: {page}
                Company: {record.get("company")}

                ## Evidence

                {evidence_text}
                """,
            )
            cases.append(
                make_case(
                    case_id=f"financebench_{record.get('financebench_id', len(cases))}",
                    category="exact_value",
                    input_files=[path],
                    query=question,
                    expected_behavior="answer",
                    expected_patterns=[answer_pattern(answer)],
                    expected_source=path,
                    source_dataset="FinanceBench",
                    license_note=self.license_note,
                )
            )
        return cases


class OpenRAGBenchAdapter:
    source_name = "open-ragbench"
    license_note = "Vectara Open RAGBench terms depend on the selected source/export; verify before sharing generated fixtures."

    def prepare(self, pack_dir: Path, input_path: Path | None, limit: int) -> list[PreparedCase]:
        if input_path is None:
            return []
        records = load_json_or_jsonl(input_path)
        cases: list[PreparedCase] = []
        for record in records:
            if len(cases) >= limit:
                break
            query = record.get("question") or record.get("query")
            answer = record.get("answer")
            context = record.get("context") or record.get("text") or record.get("section") or ""
            tables = record.get("tables")
            doc_id = str(record.get("doc_id") or record.get("context_id") or f"open_ragbench_{len(cases)}")
            if not query or not answer or not context:
                continue
            table_text = f"\n\n## Tables\n\n{tables}" if tables else ""
            path = pack_dir / "fixtures" / "open_ragbench" / f"{slug(doc_id)}.md"
            write_text(path, f"# Vectara Open RAGBench Adapted Context\n\n{context}{table_text}")
            source = str(record.get("source") or "")
            category = "table_spec" if "table" in source.lower() or tables else "summary"
            cases.append(
                make_case(
                    case_id=f"open_ragbench_{slug(str(record.get('id') or len(cases)))}",
                    category=category,
                    input_files=[path],
                    query=str(query),
                    expected_behavior="answer",
                    expected_patterns=[answer_pattern(str(answer))],
                    expected_source=path,
                    source_dataset="Vectara Open RAGBench",
                    license_note=self.license_note,
                )
            )
        return cases


class BeirAdapter:
    source_name = "beir"
    license_note = "BEIR subsets have dataset-specific licenses; generated fixtures are tiny local adaptations."

    def prepare(
        self,
        pack_dir: Path,
        input_path: Path | None,
        download: bool,
        beir_name: str,
        limit: int,
    ) -> list[PreparedCase]:
        if input_path is None:
            if not download:
                return []
            url = BEIR_DOWNLOADS.get(beir_name)
            if not url:
                raise FixturePrepError(f"No built-in BEIR download URL for {beir_name}")
            archive_path = download_file(url, pack_dir / "downloads" / f"{beir_name}.zip")
            extract_dir = pack_dir / "downloads" / beir_name
            extract_dir.mkdir(parents=True, exist_ok=True)
            with zipfile.ZipFile(archive_path) as zf:
                zf.extractall(extract_dir)
            input_path = extract_dir / beir_name
            if not input_path.exists():
                nested = list(extract_dir.glob("*/corpus.jsonl"))
                if nested:
                    input_path = nested[0].parent

        corpus_path = input_path / "corpus.jsonl"
        queries_path = input_path / "queries.jsonl"
        qrels_path = input_path / "qrels" / "test.tsv"
        if not corpus_path.exists() or not queries_path.exists() or not qrels_path.exists():
            return []

        corpus = {row.get("_id"): row for row in load_json_or_jsonl(corpus_path)}
        queries = {row.get("_id"): row for row in load_json_or_jsonl(queries_path)}
        cases: list[PreparedCase] = []
        with qrels_path.open("r", encoding="utf-8") as fh:
            for line in fh:
                if len(cases) >= limit:
                    break
                parts = line.strip().split()
                if len(parts) < 3 or parts[0].lower() == "query-id":
                    continue
                query_id, doc_id = parts[0], parts[1]
                query = queries.get(query_id)
                doc = corpus.get(doc_id)
                if not query or not doc:
                    continue
                title = doc.get("title") or doc_id
                text = doc.get("text") or ""
                if not text:
                    continue
                path = pack_dir / "fixtures" / "beir" / beir_name / f"{slug(str(doc_id))}.md"
                write_text(path, f"# {title}\n\n{text}")
                title_pattern = answer_pattern(str(title).split(":")[0])
                cases.append(
                    make_case(
                        case_id=f"beir_{beir_name}_{slug(str(query_id))}",
                        category="retrieval_only",
                        input_files=[path],
                        query=str(query.get("text") or query.get("title") or query_id),
                        expected_behavior="answer",
                        expected_patterns=[title_pattern] if title else [],
                        expected_source=path,
                        source_dataset=f"BEIR/{beir_name}",
                        license_note=self.license_note,
                    )
                )
        return cases


class MultiHopRAGAdapter:
    source_name = "multihop-rag"
    license_note = "MultiHop-RAG is licensed under ODC-BY; generated fixtures are local adaptations."

    def prepare(self, pack_dir: Path, input_path: Path | None, limit: int) -> list[PreparedCase]:
        if input_path is None:
            return []
        records = load_json_or_jsonl(input_path)
        cases: list[PreparedCase] = []
        for record in records:
            if len(cases) >= limit:
                break
            query = record.get("query") or record.get("question")
            answer = record.get("answer")
            evidence = record.get("evidence") or record.get("supporting_facts") or record.get("documents") or []
            if not query or not answer or not isinstance(evidence, list):
                continue
            paths: list[Path] = []
            for index, item in enumerate(evidence[:4]):
                text = item.get("text") if isinstance(item, dict) else str(item)
                title = item.get("title") if isinstance(item, dict) else f"evidence_{index + 1}"
                if not text:
                    continue
                path = pack_dir / "fixtures" / "multihop_rag" / f"{slug(str(record.get('id') or len(cases)))}_{index + 1}.md"
                write_text(path, f"# {title}\n\n{text}")
                paths.append(path)
            if not paths:
                continue
            cases.append(
                make_case(
                    case_id=f"multihop_rag_{slug(str(record.get('id') or len(cases)))}",
                    category="multi_hop",
                    input_files=paths,
                    query=str(query),
                    quality_mode="deep-think",
                    expected_behavior="answer",
                    expected_patterns=[answer_pattern(str(answer))],
                    expected_source=paths[0],
                    source_dataset="MultiHop-RAG",
                    license_note=self.license_note,
                )
            )
        return cases


class QasperAdapter:
    source_name = "qasper"
    license_note = "QASPER is CC BY 4.0; generated fixtures are local adaptations."

    def prepare(self, pack_dir: Path, input_path: Path | None, limit: int) -> list[PreparedCase]:
        if input_path is None:
            return []
        records = load_json_or_jsonl(input_path)
        cases: list[PreparedCase] = []
        for record in records:
            if len(cases) >= limit:
                break
            title = record.get("title") or record.get("id") or f"qasper_{len(cases)}"
            abstract = record.get("abstract") or ""
            text_parts = [f"# {title}", "## Abstract", str(abstract)]
            full_text = record.get("full_text") or {}
            if isinstance(full_text, dict):
                sections = full_text.get("section_name") or []
                paragraphs = full_text.get("paragraphs") or []
                for section, paras in zip(sections, paragraphs):
                    text_parts.append(f"## {section}")
                    if isinstance(paras, list):
                        text_parts.extend(str(p) for p in paras)
            qas = record.get("qas") or {}
            questions = qas.get("question") if isinstance(qas, dict) else []
            answers = qas.get("answers") if isinstance(qas, dict) else []
            if not questions or not answers:
                continue
            answer_text = None
            for annotation in answers[0].get("answer", []) if isinstance(answers[0], dict) else []:
                if annotation.get("unanswerable"):
                    continue
                spans = annotation.get("extractive_spans") or []
                answer_text = annotation.get("free_form_answer") or (spans[0] if spans else None)
                if answer_text:
                    break
            if not answer_text:
                continue
            path = pack_dir / "fixtures" / "qasper" / f"{slug(str(record.get('id') or len(cases)))}.md"
            write_text(path, "\n\n".join(text_parts))
            cases.append(
                make_case(
                    case_id=f"qasper_{slug(str(record.get('id') or len(cases)))}",
                    category="summary",
                    input_files=[path],
                    query=str(questions[0]),
                    expected_behavior="answer",
                    expected_patterns=[answer_pattern(str(answer_text))],
                    expected_source=path,
                    source_dataset="QASPER",
                    license_note=self.license_note,
                )
            )
        return cases


class DocVQAAdapter:
    source_name = "docvqa"
    license_note = "DocVQA requires manual download and terms acceptance through the official challenge/RRC portal."

    def prepare(self, pack_dir: Path, input_path: Path | None, limit: int) -> list[PreparedCase]:
        if input_path is None:
            return []
        records = load_json_or_jsonl(input_path)
        cases: list[PreparedCase] = []
        for record in records[:limit]:
            question = record.get("question") or record.get("query")
            answers = record.get("answers") or record.get("answer")
            ocr = record.get("ocr_text") or record.get("text") or record.get("document_text")
            if isinstance(answers, list):
                answer = answers[0] if answers else None
            else:
                answer = answers
            if not question or not answer or not ocr:
                continue
            path = pack_dir / "fixtures" / "docvqa" / f"{slug(str(record.get('questionId') or record.get('id') or len(cases)))}.txt"
            write_text(path, str(ocr))
            cases.append(
                make_case(
                    case_id=f"docvqa_{slug(str(record.get('questionId') or record.get('id') or len(cases)))}",
                    category="exact_value",
                    input_files=[path],
                    query=str(question),
                    expected_behavior="answer",
                    expected_patterns=[answer_pattern(str(answer))],
                    expected_source=path,
                    source_dataset="DocVQA",
                    license_note=self.license_note,
                )
            )
        return cases


class RAGTruthAdapter:
    source_name = "ragtruth"
    license_note = "RAGTruth-processed is MIT; best suited for later faithfulness/hallucination scoring."

    def prepare(self, pack_dir: Path, input_path: Path | None, limit: int) -> list[PreparedCase]:
        if input_path is None:
            return []
        records = load_json_or_jsonl(input_path)
        cases: list[PreparedCase] = []
        for record in records:
            if len(cases) >= limit:
                break
            source_text = record.get("source_info") or record.get("source") or record.get("context")
            prompt = record.get("prompt")
            response = record.get("response") or record.get("answer")
            if not source_text or not prompt or not response:
                continue
            path = pack_dir / "fixtures" / "ragtruth" / f"{slug(str(record.get('id') or len(cases)))}.md"
            write_text(path, f"# RAGTruth Adapted Source\n\n{source_text}")
            cases.append(
                make_case(
                    case_id=f"ragtruth_{slug(str(record.get('id') or len(cases)))}",
                    category="summary",
                    input_files=[path],
                    query=str(prompt),
                    expected_behavior="answer",
                    expected_patterns=[],
                    expected_source=path,
                    source_dataset="RAGTruth",
                    license_note=self.license_note,
                )
            )
        return cases


SOURCE_NOTES = [
    {
        "name": "Vectara Open RAGBench",
        "status": "manual local import or explicit small export",
        "license": "official HF dataset card currently lists CC BY-NC 4.0; G4KMU mirror lists Apache-2.0",
        "url": "https://huggingface.co/datasets/vectara/open_ragbench",
    },
    {
        "name": "FinanceBench",
        "status": "small optional download supported",
        "license": "CC BY-NC 4.0",
        "url": "https://huggingface.co/datasets/PatronusAI/financebench",
    },
    {
        "name": "MultiHop-RAG",
        "status": "manual local import supported",
        "license": "ODC-BY",
        "url": "https://github.com/yixuantt/MultiHop-RAG",
    },
    {
        "name": "BEIR",
        "status": "small nfcorpus/scifact download supported",
        "license": "dataset-specific",
        "url": "https://beir.ai/",
    },
    {
        "name": "QASPER",
        "status": "manual local import supported",
        "license": "CC BY 4.0",
        "url": "https://huggingface.co/datasets/allenai/qasper",
    },
    {
        "name": "DocVQA",
        "status": "manual local import only",
        "license": "requires official portal terms",
        "url": "https://www.docvqa.org/datasets/docvqa",
    },
    {
        "name": "Synthetic Lost-in-the-Middle",
        "status": "generated locally by default",
        "license": "local generated fixtures",
        "url": "",
    },
    {
        "name": "RAGTruth",
        "status": "manual local import; later faithfulness scoring",
        "license": "MIT for wandb/RAGTruth-processed",
        "url": "https://huggingface.co/datasets/wandb/RAGTruth-processed",
    },
]


def prepare_requested_sources(args: argparse.Namespace, pack_dir: Path) -> list[PreparedCase]:
    input_map = {}
    for item in args.input or []:
        if "=" not in item:
            raise FixturePrepError("--input values must be source=/path/to/file_or_dir")
        source, path = item.split("=", 1)
        input_map[source.strip()] = Path(path).expanduser()

    # This repository is public and backs a paid application, so a non-commercial dataset cannot
    # be committed to it. These sources stay reachable for local experiments and are refused as a
    # silent side effect of `--download`, which is how NC content would otherwise land in the tree.
    NON_COMMERCIAL = {
        "financebench": "CC BY-NC 4.0",
        "docvqa": "official portal terms, redistribution not granted",
    }

    cases: list[PreparedCase] = []
    for source in args.source:
        licence = NON_COMMERCIAL.get(source)
        if licence and not args.accept_non_commercial:
            raise FixturePrepError(
                f"'{source}' is {licence} and must not be committed to this repository. "
                f"For a local-only experiment, pass --accept-non-commercial and keep the output "
                f"out of git. For a committed pack use scripts/build_external_fixtures.py, which "
                f"draws on QASPER (CC BY 4.0)."
            )
        if source == "financebench":
            cases.extend(FinanceBenchAdapter().prepare(pack_dir, input_map.get(source), args.download, args.limit))
        elif source == "open-ragbench":
            cases.extend(OpenRAGBenchAdapter().prepare(pack_dir, input_map.get(source), args.limit))
        elif source == "beir":
            cases.extend(BeirAdapter().prepare(pack_dir, input_map.get(source), args.download, args.beir_name, args.limit))
        elif source == "multihop-rag":
            cases.extend(MultiHopRAGAdapter().prepare(pack_dir, input_map.get(source), args.limit))
        elif source == "qasper":
            cases.extend(QasperAdapter().prepare(pack_dir, input_map.get(source), args.limit))
        elif source == "docvqa":
            cases.extend(DocVQAAdapter().prepare(pack_dir, input_map.get(source), args.limit))
        elif source == "ragtruth":
            cases.extend(RAGTruthAdapter().prepare(pack_dir, input_map.get(source), args.limit))
        elif source == "synthetic":
            cases.extend(SyntheticTinyAdapter().prepare(pack_dir))
        else:
            raise FixturePrepError(f"Unsupported source '{source}'")
    return cases


def write_pack_readme(pack_dir: Path, manifest_path: Path, cases: list[PreparedCase]) -> None:
    category_counts: dict[str, int] = {}
    for item in cases:
        category = item.case["category"]
        category_counts[category] = category_counts.get(category, 0) + 1
    counts = "\n".join(f"- {name}: {count}" for name, count in sorted(category_counts.items()))
    write_text(
        pack_dir / "README.md",
        f"""
        # {pack_dir.name}

        Generated small RAG fixture pack.

        Manifest:

        ```bash
        {rel(manifest_path)}
        ```

        Run:

        ```bash
        python3 scripts/run_rag_benchmarks.py {rel(manifest_path)} --open-dashboard
        ```

        Case counts:

        {counts}

        This pack is an adapted local fixture set, not a full official benchmark
        reproduction. Check each case's `source_dataset` and `license_note` in
        the manifest before sharing generated files.
        """,
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preset", choices=["tiny"], default="tiny")
    parser.add_argument("--output-root", default=str(DEFAULT_OUTPUT_ROOT))
    parser.add_argument("--pack-name", default=DEFAULT_PACK_NAME)
    parser.add_argument("--overwrite", action="store_true", default=True)
    parser.add_argument(
        "--source",
        action="append",
        choices=[
            "synthetic",
            "financebench",
            "open-ragbench",
            "beir",
            "multihop-rag",
            "qasper",
            "docvqa",
            "ragtruth",
        ],
        help="Prepare a specific adapter source. Defaults to synthetic tiny starter pack.",
    )
    parser.add_argument("--input", action="append", help="Local source input as source=/path/to/file_or_dir")
    parser.add_argument("--download", action="store_true", help="Allow small built-in downloads for supported sources")
    parser.add_argument(
        "--accept-non-commercial",
        action="store_true",
        help="Permit non-commercial sources (financebench, docvqa) for a local-only run. Their "
             "output must not be committed to this repository.",
    )
    parser.add_argument("--limit", type=int, default=5, help="Max cases per non-synthetic source")
    parser.add_argument("--beir-name", default="nfcorpus", choices=sorted(BEIR_DOWNLOADS))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output_root = Path(args.output_root).expanduser()
    if not output_root.is_absolute():
        output_root = REPO_ROOT / output_root
    pack_dir = output_root / args.pack_name
    ensure_clean_pack(pack_dir, args.overwrite)

    sources = args.source or ["synthetic"]
    args.source = sources
    cases = prepare_requested_sources(args, pack_dir)
    if not cases:
        raise FixturePrepError("No cases were prepared. Provide --download or --input source=/path for dataset adapters.")

    manifest_path = write_manifest(pack_dir, cases, SOURCE_NOTES)
    write_pack_readme(pack_dir, manifest_path, cases)

    print(f"Fixture pack: {pack_dir}")
    print(f"Manifest: {manifest_path}")
    print(f"Cases: {len(cases)}")
    print(f"Run: python3 scripts/run_rag_benchmarks.py {rel(manifest_path)} --open-dashboard")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except FixturePrepError as exc:
        print(f"fixture prep error: {exc}")
        raise SystemExit(2)
