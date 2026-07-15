#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("repoos_router.py")
SPEC = importlib.util.spec_from_file_location("repoos_router", SCRIPT)
assert SPEC and SPEC.loader
router = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(router)


class RepoOSRouterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.repo = router.find_repo_root(Path(__file__))
        cls.rows = router.load_rows(cls.repo)

    def route(self, task: str, paths: list[str] | None = None):
        return router.select_route(self.rows, task, paths or [])

    def test_retrieval_task_routes_to_retrieval(self) -> None:
        self.assertEqual(
            self.route("Tune hybrid retrieval ranking")["task_type"],
            "retrieval_tuning_change",
        )

    def test_chat_path_routes_to_chat_ui(self) -> None:
        result = self.route(
            "Update the chat screen",
            ["OpenIntelligence/Features/Chat/ChatScreen.swift"],
        )
        self.assertEqual(result["task_type"], "chat_ui_change")

    def test_repoos_skill_routes_to_workspace_automation(self) -> None:
        self.assertEqual(
            self.route("Create a RepoOS Codex routing skill")["task_type"],
            "repoos_workspace_automation",
        )

    def test_repoos_source_path_wins_over_synced_docs(self) -> None:
        result = self.route(
            "Implement the RepoOS Codex routing skill",
            [
                ".codex/skills/route-openintelligence-work/SKILL.md",
                "Docs/ROADMAP.md",
                "Docs/RELEASE_NOTES.md",
                "README.md",
            ],
        )
        self.assertEqual(result["task_type"], "repoos_workspace_automation")

    def test_documentation_only_routes_to_governance(self) -> None:
        self.assertEqual(
            self.route("Update the documentation only")["task_type"],
            "documentation_governance_change",
        )

    def test_app_store_phrase_routes_to_product_copy(self) -> None:
        self.assertEqual(
            self.route("Update the App Store product copy")["task_type"],
            "app_store_copy_update",
        )

    def test_unknown_task_stops_as_config_risk(self) -> None:
        result = self.route("flibbertigibbet quux")
        self.assertFalse(result["matched"])
        self.assertIn("config-risk", result["fallback"])

    def test_hard_boundary_detection(self) -> None:
        self.assertEqual(
            router.hard_boundaries(["OpenIntelligence.xcodeproj/project.pbxproj"]),
            ["OpenIntelligence.xcodeproj/project.pbxproj"],
        )

    def test_feature_implementation_requires_notion(self) -> None:
        self.assertEqual(
            router.notion_relevance(
                "Implement a retrieval feature", "implementation", "retrieval_tuning_change"
            ),
            "required",
        )

    def test_pure_docs_route_is_gate_exempt(self) -> None:
        report = router.build_report(
            self.repo, "Update the documentation only", [], preflight=False
        )
        self.assertFalse(report["implementation_gate"])

    def test_active_release_is_derived_from_roadmap(self) -> None:
        release = router.detect_active_release(self.repo)
        self.assertEqual(release["version"], "v4.6")
        self.assertEqual(release["source"], "Docs/ROADMAP.md")
        self.assertEqual(release["confidence"], "exact")

    def test_implementation_targets_current_release_docs(self) -> None:
        report = router.build_report(
            self.repo,
            "Fix hybrid retrieval ranking regression",
            ["OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift"],
            preflight=False,
        )
        targets = report["documentation_targets"]
        self.assertEqual(targets["changelog_section"], "[Unreleased]")
        self.assertEqual(targets["release_notes_section"], "v4.6 - July 2026")
        self.assertEqual(targets["notion_target_release"], "v4.6")
        self.assertIn("CHANGELOG.md", targets["effective_required_docs"])
        self.assertIn("Docs/RELEASE_NOTES.md", targets["effective_required_docs"])

    def test_pure_docs_does_not_expand_to_full_rule_14_set(self) -> None:
        report = router.build_report(
            self.repo, "Update the documentation only", [], preflight=False
        )
        effective = report["documentation_targets"]["effective_required_docs"]
        self.assertNotEqual(set(effective), set(router.RULE_14_DOCS))

    def test_read_only_reports_release_without_requiring_doc_edits(self) -> None:
        report = router.build_report(
            self.repo, "Explain the current retrieval architecture", [], preflight=False
        )
        self.assertEqual(report["active_release"]["version"], "v4.6")
        self.assertEqual(
            report["documentation_targets"]["effective_required_docs"], []
        )


if __name__ == "__main__":
    unittest.main()
