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
# Version derivation. CHANGELOG.md is the only authority, because it is the only version marker the
# build actually reads: ci_scripts/ci_post_clone.sh stamps MARKETING_VERSION for both platforms from
# `grep -m 1 "^## [0-9]" CHANGELOG.md`.
#
# Docs/ROADMAP.md was previously first in a list of candidate sources, matched with a loose
# `^##\s+(\d+\.\d+)` pattern. That pattern hit the roadmap's *outline* numbering (`## 0.`, `## 0.5`,
# `## 1.`, `## 2.5`) and the router reported `v0.5` as the active release with `confidence: exact`,
# so every task's changelog and release-notes targets were wrong. A document that numbers its
# sections is not a version marker, and no such fallback is used any more.
CHANGELOG_PATH = "CHANGELOG.md"
SHIPPED_HEADING = re.compile(r"^##\s+(\d[0-9.]*)\b", re.MULTILINE)
# These two deliberately mirror ci_post_clone.sh's awk exactly: `/^## \[Unreleased\]/` and `/^## /`,
# case-sensitive, single space. Loosening either (`\s+`, IGNORECASE) makes the router disagree with
# the build about where the block ends, which is the disagreement this whole function exists to
# prevent.
UNRELEASED_HEADING = re.compile(r"^## \[Unreleased\]", re.MULTILINE)
NEXT_HEADING = re.compile(r"^## ", re.MULTILINE)
# A changelog entry is a bullet or a "###" subsection. Same definition as ci_post_clone.sh's
# `grep -E '^[[:space:]]*(-|###)'`.
#
# Known shared quirk, not fixed here on purpose: a line consisting of just `-->` also starts with
# `-`, so an HTML comment closed on its own line counts as an entry in BOTH implementations. The
# router could strip comment spans, but then it would disagree with the build, which is worse than
# agreeing on a documented quirk. The rule is: close comments in CHANGELOG.md inline, not with a
# bare `-->` on its own line. The placeholder comment beside [Unreleased] already does.
CHANGELOG_ENTRY = re.compile(r"^[ \t]*(?:-|###)", re.MULTILINE)
# Anchored to a whole line, and only ever searched inside the [Unreleased] block.
#
# Both constraints are load-bearing. An unanchored whole-file search matched this repository's own
# changelog bullet describing the marker, so deleting the real marker still produced a version at
# `confidence: exact` — the same "read prose as data" defect this function was written to fix, one
# file over. And when [Unreleased] is promoted to a numbered heading, a marker left below it lands
# inside the shipped section, where it must no longer be read.
NEXT_VERSION_MARKER = re.compile(
    r"^[ \t]*<!--\s*next-version:\s*(v?\d[0-9A-Za-z.\-]*)\s*-->[ \t]*$",
    re.IGNORECASE | re.MULTILINE,
)
# An explicit declaration that the top numbered section has NOT shipped yet.
#
# Nothing else in the repository records this. The heading's own date is written when the section is
# opened, not when the release is cut, and git tags cannot stand in: v4.0 and v4.2 through v4.6 have
# none. Without a declaration the router read `## 5.0 - 2026-08-10` as a shipped release while 28
# roadmap rows were still open against it, and told every session that new work targeted the version
# after it.
#
# Only ever tested against the first numbered heading's own line, never the whole file, for the same
# reason NEXT_VERSION_MARKER is anchored: this file and CHANGELOG.md both contain prose describing
# these markers, and matching that prose is the "read prose as data" defect twice over.
#
# Removing this marker is what cutting a release means. Left on a section that has shipped, the
# router keeps naming that version as the target, which is wrong but bounded: it names a real
# release rather than inventing the next one, and it self-corrects as soon as a newer section is
# opened above it.
OPEN_SECTION_MARKER = re.compile(r"<!--\s*unreleased\s*-->", re.IGNORECASE)
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


def unreleased_block(content: str) -> str:
    """The text under `## [Unreleased]`, up to the next `## ` heading."""
    heading = UNRELEASED_HEADING.search(content)
    if not heading:
        return ""
    rest = content[heading.end() :]
    following = NEXT_HEADING.search(rest)
    return rest[: following.start()] if following else rest


def unreleased_entry_count(content: str) -> int:
    """Count entries under `## [Unreleased]`, matching ci_post_clone.sh's definition."""
    return len(CHANGELOG_ENTRY.findall(unreleased_block(content)))


def detect_active_release(repo: Path) -> dict[str, str]:
    """Derive the release that new work targets, from CHANGELOG.md alone.

    Reporting the first numbered heading is not enough on its own. `ci_post_clone.sh` encodes the
    reason: when `[Unreleased]` holds entries, that heading describes a version already cut, and
    treating it as the target is what made CI stamp an already-released 4.6 and got the build
    rejected by App Store Connect on 2026-07-28. So the two states are reported separately:

      * top heading carries      -> that section is still open, so it IS the target and the section
        `<!-- unreleased -->`        below it is `last_shipped`. Checked first, because it is the
                                     only positive statement available; both other branches infer.
      * `[Unreleased]` empty      -> the numbered heading is the target. state="shipped".
      * `[Unreleased]` non-empty  -> the target is the *next* version, which the numbered heading
                                     does not name. state="in_development", and the number comes
                                     from a `<!-- next-version: X -->` marker beside the
                                     `[Unreleased]` heading. Without that marker the honest answer
                                     is "unreleased" with confidence "unknown", never a guess.

    `last_shipped` is always reported so a caller can tell the two apart without re-parsing.
    """
    path = repo / CHANGELOG_PATH
    if not path.is_file():
        return {
            "version": "unknown",
            "last_shipped": "unknown",
            "state": "unknown",
            "unreleased_entries": "0",
            "open_section": "no",
            "source": "none",
            "matched_text": f"{CHANGELOG_PATH} not found",
            "evidence_level": "artifact_derived",
            "confidence": "unknown",
        }

    content = path.read_text(encoding="utf-8")
    headings = list(SHIPPED_HEADING.finditer(content))
    shipped = headings[0] if headings else None
    last_shipped = f"v{shipped.group(1)}" if shipped else "unknown"
    pending = unreleased_entry_count(content)

    if shipped is not None:
        end = content.find("\n", shipped.start())
        heading_line = content[shipped.start() : end if end != -1 else len(content)]
        if OPEN_SECTION_MARKER.search(heading_line):
            return {
                "version": last_shipped,
                "last_shipped": f"v{headings[1].group(1)}" if len(headings) > 1 else "unknown",
                "state": "in_development",
                "unreleased_entries": str(pending),
                "open_section": "yes",
                "source": f"{CHANGELOG_PATH} unreleased marker",
                "matched_text": heading_line.strip(),
                "evidence_level": "artifact_derived",
                "confidence": "exact",
            }

    if pending == 0:
        return {
            "version": last_shipped,
            "last_shipped": last_shipped,
            "state": "shipped",
            "unreleased_entries": "0",
            "open_section": "no",
            "source": CHANGELOG_PATH,
            "matched_text": shipped.group(0).strip() if shipped else "no numbered heading",
            "evidence_level": "artifact_derived",
            "confidence": "exact" if shipped else "unknown",
        }

    # Searched inside the [Unreleased] block only, never the whole file.
    marker = NEXT_VERSION_MARKER.search(unreleased_block(content))
    if marker:
        version = marker.group(1)
        if not version.lower().startswith("v"):
            version = f"v{version}"
        # A marker naming the version that already shipped is a marker nobody updated when the
        # release was cut. Reporting it would hand back the shipped version as the target, which is
        # exactly the failure this function exists to prevent, so treat it as no marker at all.
        if version.lower() != last_shipped.lower():
            return {
                "version": version,
                "last_shipped": last_shipped,
                "state": "in_development",
                "unreleased_entries": str(pending),
                "open_section": "no",
                "source": f"{CHANGELOG_PATH} next-version marker",
                "matched_text": marker.group(0).strip(),
                "evidence_level": "artifact_derived",
                "confidence": "exact",
            }

    return {
        "version": "unreleased",
        "last_shipped": last_shipped,
        "state": "in_development",
        "unreleased_entries": str(pending),
        "open_section": "no",
        "source": CHANGELOG_PATH,
        "matched_text": (
            f"[Unreleased] has {pending} entrie(s) and no <!-- next-version: X --> marker; "
            f"{last_shipped} is already shipped"
        ),
        "evidence_level": "artifact_derived",
        "confidence": "unknown",
    }


def changelog_section(release: dict[str, str]) -> str:
    """The heading a new entry goes under.

    `[Unreleased]` is right whenever the top numbered section has already shipped. While that
    section is still open it is the target instead, which is what every commit of the v5.0 cycle
    did in practice while this function was hardcoded to say otherwise.
    """
    if release.get("open_section") == "yes":
        return f"## {release['version'].lstrip('v')}"
    return "[Unreleased]"


def release_notes_section(repo: Path, release: dict[str, str]) -> str:
    version = release.get("version", "unknown")
    if version in {"unknown", "unreleased"}:
        return "none — do not create a release-notes section until the next version is named"
    path = repo / "Docs/RELEASE_NOTES.md"
    if path.is_file():
        # Anchor on the version token and take the rest of the heading line. The previous pattern
        # required the heading to be the bare version optionally followed by " - ...", which does
        # not match this file's actual dual-platform style, e.g.
        # `## v4.7 (iOS) / v3.0 (macOS) - July 2026` or `## v4.8 (iOS) - in progress`. It therefore
        # reported existing sections as nonexistent and would have had an agent append a duplicate.
        pattern = re.compile(
            rf"^##\s+({re.escape(version)}\b[^\n]*)$",
            re.IGNORECASE | re.MULTILINE,
        )
        match = pattern.search(path.read_text(encoding="utf-8"))
        if match:
            return match.group(1).strip()
    if release.get("state") == "in_development":
        return f"{version} (section does not exist yet; create it when the release is cut)"
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
            "changelog_section": changelog_section(active_release),
            "release_notes_section": release_notes_section(repo, active_release),
            "notion_target_release": (
                active_release["version"]
                if active_release["version"] not in {"unknown", "unreleased"}
                else "unassigned — name the next version before writing a Notion Target Release"
            ),
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
        f"- Active release: `{report['active_release']['version']}`"
        f" ({report['active_release']['state']}, last shipped"
        f" `{report['active_release']['last_shipped']}`,"
        f" {report['active_release']['unreleased_entries']} unreleased entries)",
        f"- Changelog target: `{report['documentation_targets']['changelog_section']}`",
        f"- Release notes target: `{report['documentation_targets']['release_notes_section']}`",
        f"- Notion Target Release: `{report['documentation_targets']['notion_target_release']}`",
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
