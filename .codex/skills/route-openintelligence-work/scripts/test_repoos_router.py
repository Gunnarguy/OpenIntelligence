#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import tempfile
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

    # --- Release derivation -------------------------------------------------------------------
    #
    # These build a throwaway CHANGELOG instead of asserting a literal version against the live
    # tree. The versions they replace asserted "v4.6" against the real repository, so they broke the
    # moment 4.7 shipped and stayed red through 4.8 and 4.9. Worse, a permanently failing test hid
    # the defect underneath it: the router was reading Docs/ROADMAP.md's outline heading "## 0.5"
    # as the active release and reporting it with confidence "exact".
    #
    # A test that asserts a moving value against the working tree is not a test, it is a calendar.

    def changelog_repo(self, body: str) -> Path:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        repo = Path(tmp.name)
        (repo / "CHANGELOG.md").write_text(body, encoding="utf-8")
        return repo

    def test_empty_unreleased_means_the_numbered_heading_is_the_target(self) -> None:
        repo = self.changelog_repo(
            "# Changelog\n\n## [Unreleased]\n\n<!-- nothing yet -->\n\n## 4.9 - 2026-08-02\n\n- shipped\n"
        )
        release = router.detect_active_release(repo)
        self.assertEqual(release["version"], "v4.9")
        self.assertEqual(release["state"], "shipped")
        self.assertEqual(release["unreleased_entries"], "0")
        self.assertEqual(release["confidence"], "exact")

    def test_non_empty_unreleased_reads_the_next_version_marker(self) -> None:
        repo = self.changelog_repo(
            "# Changelog\n\n## [Unreleased]\n\n<!-- next-version: 5.0 -->\n\n### Added\n"
            "- something\n\n## 4.9 - 2026-08-02\n\n- shipped\n"
        )
        release = router.detect_active_release(repo)
        self.assertEqual(release["version"], "v5.0")
        self.assertEqual(release["last_shipped"], "v4.9")
        self.assertEqual(release["state"], "in_development")
        self.assertEqual(release["confidence"], "exact")

    def test_non_empty_unreleased_without_a_marker_refuses_to_guess(self) -> None:
        """The shipped heading must never be handed back as the target.

        This is the case that got a build rejected by App Store Connect on 2026-07-28: CI kept
        stamping 4.6 while [Unreleased] had accumulated a release worth of entries.
        """
        repo = self.changelog_repo(
            "# Changelog\n\n## [Unreleased]\n\n### Added\n- something\n\n## 4.9 - 2026-08-02\n\n- shipped\n"
        )
        release = router.detect_active_release(repo)
        self.assertEqual(release["version"], "unreleased")
        self.assertEqual(release["last_shipped"], "v4.9")
        self.assertEqual(release["confidence"], "unknown")
        self.assertNotEqual(release["version"], release["last_shipped"])

    def test_a_marker_quoted_in_prose_is_not_a_marker(self) -> None:
        """Regression: the changelog bullet that documents the marker quotes it verbatim.

        A whole-file search read that bullet as the marker, so deleting the real one still produced
        a version at confidence "exact" — the same "prose read as data" defect as the `## 0.5` case.
        """
        repo = self.changelog_repo(
            "# Changelog\n\n## [Unreleased]\n\n### Added\n"
            "- Reads a `<!-- next-version: 9.9 -->` marker beside the heading.\n"
            "\n## 4.9 - 2026-08-02\n\n- shipped\n"
        )
        release = router.detect_active_release(repo)
        self.assertEqual(release["version"], "unreleased")
        self.assertEqual(release["confidence"], "unknown")

    def test_a_marker_below_the_shipped_heading_is_ignored(self) -> None:
        """Cutting a release leaves the old marker inside the now-shipped section."""
        repo = self.changelog_repo(
            "# Changelog\n\n## [Unreleased]\n\n### Added\n- new work\n\n"
            "## 5.0 - 2026-08-07\n\n<!-- next-version: 5.0 -->\n\n- shipped\n"
        )
        release = router.detect_active_release(repo)
        self.assertEqual(release["last_shipped"], "v5.0")
        self.assertEqual(release["version"], "unreleased")

    def test_a_marker_naming_the_shipped_version_is_treated_as_absent(self) -> None:
        repo = self.changelog_repo(
            "# Changelog\n\n## [Unreleased]\n\n<!-- next-version: 4.9 -->\n\n### Added\n- new work\n\n"
            "## 4.9 - 2026-08-02\n\n- shipped\n"
        )
        release = router.detect_active_release(repo)
        self.assertEqual(release["version"], "unreleased")
        self.assertNotEqual(release["version"], release["last_shipped"])

    def test_release_notes_matches_the_dual_platform_heading_style(self) -> None:
        """Docs/RELEASE_NOTES.md uses `## v4.7 (iOS) / v3.0 (macOS) - July 2026`."""
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        repo = Path(tmp.name)
        (repo / "Docs").mkdir()
        (repo / "Docs" / "RELEASE_NOTES.md").write_text(
            "# Release notes\n\n## v4.8 (iOS) - in progress\n\n## v4.7 (iOS) / v3.0 (macOS) - July 2026\n",
            encoding="utf-8",
        )
        self.assertEqual(
            router.release_notes_section(repo, {"version": "v4.8", "state": "in_development"}),
            "v4.8 (iOS) - in progress",
        )

    def test_block_delimiters_match_the_ci_shell_exactly(self) -> None:
        """The router and ci_post_clone.sh must agree on where [Unreleased] ends."""
        self.assertEqual(router.UNRELEASED_HEADING.pattern, r"^## \[Unreleased\]")
        self.assertEqual(router.NEXT_HEADING.pattern, r"^## ")

    def test_an_outline_heading_is_never_read_as_a_version(self) -> None:
        """Regression: Docs/ROADMAP.md numbers its sections, and `## 0.5` is not a release."""
        repo = self.changelog_repo(
            "# Changelog\n\n## [Unreleased]\n\n<!-- nothing -->\n\n## 4.9 - 2026-08-02\n\n- shipped\n"
        )
        (repo / "Docs").mkdir()
        (repo / "Docs" / "ROADMAP.md").write_text(
            "# Roadmap\n\n## 0. Shipped\n\n## 0.5 Instrumentation & Benchmarking\n\n## 2.5 Third-party models\n",
            encoding="utf-8",
        )
        release = router.detect_active_release(repo)
        self.assertEqual(release["version"], "v4.9")
        self.assertEqual(release["source"], "CHANGELOG.md")
        self.assertNotIn("ROADMAP", release["source"])

    def test_release_notes_are_withheld_until_the_version_is_named(self) -> None:
        repo = self.changelog_repo("# Changelog\n")
        section = router.release_notes_section(
            repo, {"version": "unreleased", "state": "in_development"}
        )
        self.assertIn("do not create", section)

    def test_live_repository_derives_its_release_from_the_changelog(self) -> None:
        """Non-brittle live check: compare against the file, never against a literal."""
        release = router.detect_active_release(self.repo)
        self.assertIn("CHANGELOG.md", release["source"])
        self.assertNotEqual(release["version"], "unknown")
        heading = router.SHIPPED_HEADING.search(
            (self.repo / "CHANGELOG.md").read_text(encoding="utf-8")
        )
        self.assertIsNotNone(heading)
        self.assertEqual(release["last_shipped"], f"v{heading.group(1)}")
        if release["state"] == "in_development":
            self.assertNotEqual(release["version"], release["last_shipped"])

    def test_implementation_targets_current_release_docs(self) -> None:
        report = router.build_report(
            self.repo,
            "Fix hybrid retrieval ranking regression",
            ["OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift"],
            preflight=False,
        )
        targets = report["documentation_targets"]
        self.assertEqual(targets["changelog_section"], "[Unreleased]")
        self.assertEqual(
            targets["notion_target_release"], report["active_release"]["version"]
        )
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
        self.assertNotEqual(report["active_release"]["version"], "unknown")
        self.assertEqual(
            report["documentation_targets"]["effective_required_docs"], []
        )


if __name__ == "__main__":
    unittest.main()
