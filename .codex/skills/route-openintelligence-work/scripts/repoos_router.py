#!/usr/bin/env python3
"""Deterministic RepoOS task routing and workspace preflight."""

from __future__ import annotations

import argparse
import csv
import fnmatch
import json
import re
import subprocess
from pathlib import Path
from typing import Any


MATRIX_PATH = Path("Docs/AuditArtifacts/RepoOS/change_impact_matrix.csv")
UNIVERSAL_DOCS = [
    "AGENTS.md",
    "Docs/AgentPlaybooks/00_SUPERSEDING_EVIDENCE_PROTOCOL.md",
    "Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md",
    "Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md",
    "Docs/RepoOS/00_REPO_COMMAND_CENTER.md",
    "Docs/AppleIntelligenceTransitionPlan.md",
    "Docs/RepoOS/01_TASK_ROUTER.md",
    "Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md",
]
RULE_14_DOCS = [
    "README.md",
    "Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md",
    "Docs/AppleIntelligenceTransitionPlan.md",
    "CHANGELOG.md",
    "Docs/RELEASE_NOTES.md",
    "Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md",
    "Docs/ROADMAP.md",
]
RELEASE_SOURCE_DOCS = [
    "Docs/ROADMAP.md",
    "README.md",
    "Docs/RELEASE_NOTES.md",
    "CHANGELOG.md",
]
HARD_BOUNDARY_NAMES = {
    "project.pbxproj",
    "storekitconfiguration.storekit",
    "openintelligence.entitlements",
    "info.plist",
    "package.swift",
    "package.resolved",
    "chatmessage.swift",
    "workspacesyncservice.swift",
    "sqlitefulltextservice.swift",
    "bnnsvectordatabase.swift",
    "entitlementstore.swift",
    "quotapolicy.swift",
    "ragappintents.swift",
    "foundationmodelroutepolicy.swift",
    "foundationmodelsessionfactory.swift",
    "enginesdkcompatibility.swift",
}
SYNONYMS = {
    "retrieval_tuning_change": "retrieval search ranking context packing hybrid bm25 mmr",
    "reranking_fusion_change": "rerank reranking fusion rrf scoring",
    "embedding_provider_change": "embedding provider tokenizer core ml vector dimension",
    "core_ai_ios27_change": "core ai ios 27 foundation models language model",
    "pcc_routing_consent_change": "pcc private cloud consent routing enclave",
    "evidence_threads_change": "evidence thread chat persistence conversation history",
    "icloud_sync_change": "icloud sync ubiquity workspace file coordinator",
    "storekit_billing_change": "storekit purchase restore subscription billing",
    "app_intents_change": "app intent siri shortcut entity",
    "ingestion_ocr_change": "ingestion import document ocr extraction pdf",
    "semantic_chunking_change": "semantic chunk chunking document chunk",
    "vector_storage_change": "vector storage bnns mmap index",
    "sqlite_fts_change": "sqlite fts fts5 database keyword storage",
    "chat_ui_change": "chat ui citation source rendering view",
    "documentation_governance_change": "documentation docs audit governance reconcile",
    "release_readiness_check": "release readiness ship checklist verification",
    "app_store_copy_update": "app store copy metadata marketing privacy",
    "build_project_config_change": "build project config xcode package plist entitlement",
    "tests_only_change": "test tests fixture coverage",
    "diagnostics_telemetry_change": "diagnostic telemetry trace monitoring",
    "repoos_workspace_automation": "repoos codex skill agent workflow routing notion automation governance",
}
PHRASE_HINTS = {
    "documentation_governance_change": ("documentation", "docs only", "doc reconciliation"),
    "release_readiness_check": ("release readiness", "release check"),
    "app_store_copy_update": ("app store", "product copy", "store metadata"),
    "build_project_config_change": ("project config", "build config"),
    "repoos_workspace_automation": ("repoos", "codex skill", "agent workflow"),
}
TOKEN_STOPWORDS = {
    "add",
    "build",
    "change",
    "create",
    "edit",
    "fix",
    "implement",
    "make",
    "only",
    "update",
}


def find_repo_root(start: Path) -> Path:
    current = start.resolve()
    for candidate in (current, *current.parents):
        if (candidate / "AGENTS.md").is_file() and (candidate / MATRIX_PATH).is_file():
            return candidate
    raise SystemExit("Could not find the OpenIntelligence repository root.")


def split_field(value: str) -> list[str]:
    return [part.strip() for part in value.split(";") if part.strip()]


def normalize_pattern(pattern: str) -> str:
    pattern = pattern.strip().replace(" (selection logic only)", "")
    pattern = pattern.replace(" (UI only, with approval)", "")
    return pattern.replace("/**", "/*")


def path_matches(path: str, pattern: str) -> bool:
    pattern = normalize_pattern(pattern)
    if not pattern or pattern.startswith(("none_", "all ", "anything ")):
        return False
    path = path.lstrip("./")
    if fnmatch.fnmatch(path, pattern):
        return True
    if "*" not in pattern and path == pattern:
        return True
    return pattern.endswith("/*") and path.startswith(pattern[:-1])


def tokenize(value: str) -> set[str]:
    return {
        token
        for token in re.findall(r"[a-z0-9]+", value.lower().replace("ios", "ios "))
        if len(token) > 2 and token not in TOKEN_STOPWORDS
    }


def load_rows(repo: Path) -> list[dict[str, str]]:
    with (repo / MATRIX_PATH).open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def score_row(row: dict[str, str], task: str, paths: list[str]) -> tuple[int, list[str]]:
    score = 0
    reasons: list[str] = []
    likely = split_field(row.get("likely_files", ""))
    allowed = split_field(row.get("allowed_edit_paths", ""))
    likely_matches: list[str] = []
    allowed_matches: list[str] = []
    for path in paths:
        if any(path_matches(path, pattern) for pattern in likely):
            likely_matches.append(path)
        if any(path_matches(path, pattern) for pattern in allowed):
            allowed_matches.append(path)
    if likely_matches:
        score += 30
        reasons.append("likely path match: " + ", ".join(likely_matches[:3]))
    if allowed_matches:
        score += 20
        reasons.append("allowed path match: " + ", ".join(allowed_matches[:3]))

    task_tokens = tokenize(task)
    haystack = " ".join(
        [
            row.get("task_type", ""),
            row.get("subsystem", ""),
            row.get("likely_files", ""),
            SYNONYMS.get(row.get("task_type", ""), ""),
        ]
    )
    overlap = task_tokens & tokenize(haystack)
    if overlap:
        score += len(overlap) * 4
        reasons.append("keyword match: " + ", ".join(sorted(overlap)))
    phrase = row.get("task_type", "").replace("_", " ")
    if phrase and phrase in task.lower():
        score += 20
        reasons.append(f"task type phrase: {phrase}")
    for hint in PHRASE_HINTS.get(row.get("task_type", ""), ()):
        if hint in task.lower():
            score += 25
            reasons.append(f"route phrase: {hint}")
    return score, reasons


def hard_boundaries(paths: list[str]) -> list[str]:
    return sorted(
        {
            path
            for path in paths
            if Path(path).name.lower() in HARD_BOUNDARY_NAMES
            or path.lower().endswith((".storekit", ".entitlements"))
        }
    )


def classify_intent(task: str) -> str:
    lowered = task.lower()
    write_words = r"\b(implement|fix|change|create|add|remove|update|refactor|build|make|edit)\b"
    diagnose_words = r"\b(diagnose|why|root cause|debug|investigate)\b"
    read_words = r"\b(explain|review|report|status|audit|inspect|check|what|how)\b"
    if re.search(write_words, lowered):
        return "implementation"
    if re.search(diagnose_words, lowered):
        return "diagnosis_read_only"
    if re.search(read_words, lowered):
        return "read_only"
    return "planning_or_unknown"


def notion_relevance(task: str, intent: str, task_type: str | None) -> str:
    lowered = task.lower()
    if "notion" in lowered or re.search(r"\b(roadmap|backlog|milestone|release)\b", lowered):
        return "required"
    if intent == "implementation" and task_type not in {
        "documentation_governance_change",
        "tests_only_change",
    }:
        return "required"
    if task_type == "repoos_workspace_automation":
        return "required"
    return "usually_not_required"


def detect_active_release(repo: Path) -> dict[str, str]:
    """Derive the active release from current repository documentation."""
    patterns = (
        re.compile(r"working on\s+(v\d+\.\d+(?:\.\d+)?)", re.IGNORECASE),
        re.compile(r"documentation status:.*?\b(v\d+\.\d+(?:\.\d+)?)\b", re.IGNORECASE),
        re.compile(r"^##\s+(v\d+\.\d+(?:\.\d+)?)\b", re.IGNORECASE | re.MULTILINE),
        re.compile(r"^##\s+(\d+\.\d+(?:\.\d+)?)\b", re.MULTILINE),
    )
    for relative_path in RELEASE_SOURCE_DOCS:
        path = repo / relative_path
        if not path.is_file():
            continue
        content = path.read_text(encoding="utf-8")
        for pattern in patterns:
            match = pattern.search(content)
            if match:
                version = match.group(1)
                if not version.lower().startswith("v"):
                    version = f"v{version}"
                return {
                    "version": version,
                    "source": relative_path,
                    "matched_text": match.group(0).strip(),
                    "evidence_level": "artifact_derived",
                    "confidence": "exact",
                }
    return {
        "version": "unknown",
        "source": "none",
        "matched_text": "none",
        "evidence_level": "artifact_derived",
        "confidence": "unknown",
    }


def release_notes_section(repo: Path, version: str) -> str:
    if version == "unknown":
        return "unknown"
    path = repo / "Docs/RELEASE_NOTES.md"
    if path.is_file():
        pattern = re.compile(
            rf"^##\s+({re.escape(version)}(?:\s+-[^\n]*)?)$",
            re.IGNORECASE | re.MULTILINE,
        )
        match = pattern.search(path.read_text(encoding="utf-8"))
        if match:
            return match.group(1).strip()
    return version


def effective_required_docs(route: dict[str, Any], intent: str) -> list[str]:
    if intent != "implementation":
        return []
    required = list(route.get("required_docs_to_update", []))
    durable_implementation = route.get("task_type") not in {
        "documentation_governance_change",
        "tests_only_change",
    }
    if durable_implementation:
        required.extend(RULE_14_DOCS)
    return list(dict.fromkeys(required))


def select_route(rows: list[dict[str, str]], task: str, paths: list[str]) -> dict[str, Any]:
    scored = []
    for row in rows:
        score, reasons = score_row(row, task, paths)
        scored.append((score, row, reasons))
    scored.sort(key=lambda item: (-item[0], item[1].get("task_type", "")))
    best_score, best, reasons = scored[0]
    no_match = best_score == 0
    if no_match:
        return {
            "matched": False,
            "task_type": None,
            "fallback": "Docs/RepoOS/01_TASK_ROUTER.md route 13 config-risk stop",
            "score": 0,
            "reasons": [],
            "alternatives": [],
        }
    alternatives = [
        {"task_type": row["task_type"], "score": score}
        for score, row, _ in scored[1:4]
        if score > 0
    ]
    result: dict[str, Any] = dict(best)
    result.update(
        {
            "matched": True,
            "score": best_score,
            "reasons": reasons,
            "alternatives": alternatives,
            "read_first_docs": split_field(best.get("read_first_docs", "")),
            "allowed_edit_paths": split_field(best.get("allowed_edit_paths", "")),
            "forbidden_edit_paths": split_field(best.get("forbidden_edit_paths", "")),
            "required_tests": split_field(best.get("required_tests", "")),
            "required_docs_to_update": split_field(best.get("required_docs_to_update", "")),
        }
    )
    return result


def git_output(repo: Path, *args: str) -> str:
    process = subprocess.run(
        ["git", *args], cwd=repo, text=True, capture_output=True, check=False
    )
    return process.stdout.strip()


def build_report(repo: Path, task: str, paths: list[str], preflight: bool) -> dict[str, Any]:
    route = select_route(load_rows(repo), task, paths)
    intent = classify_intent(task)
    active_release = detect_active_release(repo)
    gate_exemptions = {"no_for_pure_docs", "no_for_pure_tests"}
    gate_required = (
        intent == "implementation"
        and route.get("approval_required") not in gate_exemptions
    )
    report: dict[str, Any] = {
        "repository": str(repo),
        "task": task,
        "paths": paths,
        "intent": intent,
        "route": route,
        "hard_boundary_paths": hard_boundaries(paths),
        "universal_read_first": UNIVERSAL_DOCS,
        "implementation_gate": gate_required,
        "notion_relevance": notion_relevance(task, intent, route.get("task_type")),
        "active_release": active_release,
        "documentation_targets": {
            "effective_required_docs": effective_required_docs(route, intent),
            "changelog_section": "[Unreleased]",
            "release_notes_section": release_notes_section(
                repo, active_release["version"]
            ),
            "notion_target_release": active_release["version"],
        },
        "evidence": {
            "evidence_level": "artifact_derived",
            "confidence": "exact" if route.get("matched") else "unknown",
            "source": str(MATRIX_PATH),
        },
    }
    if preflight:
        status = git_output(repo, "status", "--short")
        report["workspace"] = {
            "branch": git_output(repo, "branch", "--show-current"),
            "dirty_paths": status.splitlines() if status else [],
        }
    return report


def markdown_report(report: dict[str, Any]) -> str:
    route = report["route"]
    lines = [
        "# RepoOS Preflight",
        "",
        f"- Intent: `{report['intent']}`",
        f"- Route: `{route.get('task_type') or 'NO MATCH'}`",
        f"- Risk: `{route.get('risk_level', 'unknown')}`",
        f"- Approval: `{route.get('approval_required', 'config-risk stop')}`",
        f"- Notion: `{report['notion_relevance']}`",
        f"- Active release: `{report['active_release']['version']}`",
        f"- Changelog target: `{report['documentation_targets']['changelog_section']}`",
        f"- Release notes target: `{report['documentation_targets']['release_notes_section']}`",
        f"- Implementation gate: `{'required' if report['implementation_gate'] else 'not triggered'}`",
    ]
    if report.get("hard_boundary_paths"):
        lines.append("- Hard-boundary paths: " + ", ".join(report["hard_boundary_paths"]))
    if "workspace" in report:
        lines.extend(
            [
                f"- Branch: `{report['workspace']['branch'] or '(detached)'}`",
                f"- Dirty entries: `{len(report['workspace']['dirty_paths'])}`",
            ]
        )
    for title, key in [
        ("Read first", "read_first_docs"),
        ("Allowed edits", "allowed_edit_paths"),
        ("Forbidden edits", "forbidden_edit_paths"),
        ("Required tests", "required_tests"),
        ("Required docs from route", "required_docs_to_update"),
    ]:
        values = route.get(key, [])
        if values:
            lines.extend(["", f"## {title}"])
            lines.extend(f"- {value}" for value in values)
    effective_docs = report["documentation_targets"]["effective_required_docs"]
    if effective_docs:
        lines.extend(["", "## Effective required docs"])
        lines.extend(f"- {value}" for value in effective_docs)
    if not route.get("matched"):
        lines.extend(["", f"Stop: {route['fallback']}"])
    return "\n".join(lines) + "\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("route", "preflight"))
    parser.add_argument("--task", required=True)
    parser.add_argument("--path", action="append", default=[])
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--format", choices=("markdown", "json"), default="markdown")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    repo = find_repo_root(args.repo)
    report = build_report(repo, args.task, args.path, args.command == "preflight")
    if args.format == "json":
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print(markdown_report(report), end="")


if __name__ == "__main__":
    main()
