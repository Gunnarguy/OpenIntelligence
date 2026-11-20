#!/usr/bin/env python3
"""Tests for scripts/check_claims.py. Every case builds a tiny repository in a temp folder: a register, the five
copy files and an evidence file. Nothing here reads the real register or the real copy.

Run: python3 scripts/test_check_claims.py
"""
import contextlib, io, json, os, sys, tempfile, unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_claims as claims

DESCRIPTION, PROMO, NOTES = claims.COPY_FILES[0], claims.COPY_FILES[1], claims.COPY_FILES[2]
EVIDENCE = "Docs/RESULTS.md"


def entry(**changes):
    base = {"id": "standard-right", "claim": "88% of test questions (15 of 17)", "files": [DESCRIPTION],
            "kind": "measured", "evidence": [{"path": EVIDENCE, "contains": "Standard got 15 right of 17"}],
            "derivation": "15/17 = 88.2%", "status": "verified"}
    base.update(changes)
    return base


class Repo:
    """A temp folder holding a register, the five copy files (empty unless given) and one evidence file."""

    def __init__(self, entries, copy=None, not_claims=(), evidence_text="Standard got 15 right of 17.\n"):
        self.folder = tempfile.TemporaryDirectory()
        self.root = self.folder.name
        for rel in claims.COPY_FILES:
            self.write(rel, (copy or {}).get(rel, ""))
        self.write(EVIDENCE, evidence_text)
        self.write(claims.REGISTER, json.dumps({"not_claims": list(not_claims), "claims": entries}))

    def write(self, rel, text):
        path = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)

    def check(self, **options):
        return claims.check(self.root, **options)

    def run(self, *flags):
        """The command line's exit code and what it printed."""
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = claims.main(["--root", self.root, *flags])
        return code, out.getvalue()

    def close(self):
        self.folder.cleanup()


def checks(rows):
    return [row["check"] for row in rows]


class CheckClaimsTests(unittest.TestCase):
    def repo(self, *args, **kwargs):
        repo = Repo(*args, **kwargs)
        self.addCleanup(repo.close)
        return repo

    def test_a_covered_number_passes(self):
        repo = self.repo([entry()], {DESCRIPTION: "Free to start.\n- Standard is right on 88% of test questions (15 of 17).\n"})
        result = repo.check()
        self.assertEqual(result["failures"], [])
        self.assertEqual(result["warnings"], [])
        self.assertEqual((result["counts"]["numbers"], result["counts"]["covered"], result["counts"]["uncovered"]), (2, 2, 0))
        self.assertEqual(result["counts"]["verified"], 1)
        self.assertEqual(repo.run()[0], 0)

    def test_an_uncovered_number_fails_with_its_line(self):
        repo = self.repo([entry()], {DESCRIPTION: "Intro.\n\n- Right on 88% of test questions (15 of 17), in 12 seconds.\n"})
        result = repo.check()
        self.assertEqual(checks(result["failures"]), ["uncovered number"])
        row = result["failures"][0]
        self.assertEqual((row["file"], row["line"], row["token"]), (DESCRIPTION, 3, "12"))
        self.assertEqual(row["text"], "- Right on 88% of test questions (15 of 17), in 12 seconds.")
        code, printed = repo.run()
        self.assertEqual(code, 1)
        self.assertIn(f"{DESCRIPTION}:3", printed)
        self.assertIn("in 12 seconds", printed)

    def test_an_entry_covers_only_the_files_it_lists(self):
        text = "Right on 88% of test questions (15 of 17).\n"
        repo = self.repo([entry()], {DESCRIPTION: text, NOTES: text})
        failures = repo.check()["failures"]
        self.assertEqual({(row["file"], row["token"]) for row in failures}, {(NOTES, "88%"), (NOTES, "15 of 17")})

    def test_a_number_beside_the_claim_text_is_not_covered_by_it(self):
        repo = self.repo([entry(claim="10 libraries", derivation=None)], {DESCRIPTION: "Pro: 110 libraries and 10 libraries.\n"})
        self.assertEqual([row["token"] for row in repo.check()["failures"]], ["110"])

    def test_tokens_keep_commas_decimals_and_dotted_versions_whole(self):
        found = [m.group(0) for m in claims.TOKEN.finditer("1,000 files, 8,192 tokens, 27.0.1 and 5.8, M3, 9 to 15 of 17, 85% of 515.")]
        self.assertEqual(found, ["1,000", "8,192", "27.0.1", "5.8", "3", "9", "15 of 17", "85% of 515"])

    def test_missing_evidence_file_fails(self):
        repo = self.repo([entry(evidence=[{"path": "Docs/GONE.md", "contains": "anything"}])],
                         {DESCRIPTION: "88% of test questions (15 of 17)\n"})
        failures = repo.check()["failures"]
        self.assertEqual(checks(failures), ["evidence"])
        self.assertIn("Docs/GONE.md does not exist", failures[0]["detail"])
        self.assertEqual(failures[0]["id"], "standard-right")

    def test_a_missing_contains_string_fails(self):
        repo = self.repo([entry()], {DESCRIPTION: "88% of test questions (15 of 17)\n"},
                         evidence_text="Standard got 14 right of 17.\n")
        failures = repo.check()["failures"]
        self.assertEqual(checks(failures), ["evidence"])
        self.assertIn("no longer contains", failures[0]["detail"])

    def test_a_verified_entry_with_no_evidence_fails(self):
        repo = self.repo([entry(evidence=[])], {DESCRIPTION: "88% of test questions (15 of 17)\n"})
        self.assertEqual(checks(repo.check()["failures"]), ["evidence"])

    def test_evidence_outside_the_repository_fails(self):
        for path in ("../memory/note.md", "/Users/someone/.claude/memory/note.md", "~/.claude/memory/note.md"):
            repo = self.repo([entry(evidence=[{"path": path}])], {DESCRIPTION: "88% of test questions (15 of 17)\n"})
            failures = repo.check()["failures"]
            self.assertEqual(checks(failures), ["evidence"], path)
            self.assertIn("not a path inside the repository", failures[0]["detail"])

    def test_an_absent_run_folder_only_warns(self):
        evidence = [{"path": EVIDENCE, "contains": "Standard got 15 right of 17"}, {"path": "BenchmarkRuns/2026-11-14-answer-modes"},
                    {"path": "BenchmarkRuns/2026-11-14-answer-modes/README.md", "contains": "15"}]
        repo = self.repo([entry(evidence=evidence)], {DESCRIPTION: "88% of test questions (15 of 17)\n"})
        result = repo.check()
        self.assertEqual(result["failures"], [])
        self.assertEqual(checks(result["warnings"]), ["run folder not on this machine"] * 2)
        self.assertEqual(result["counts"]["run_folders_absent"], 2)
        self.assertEqual(repo.run()[0], 0)
        self.assertEqual(repo.run("--strict")[0], 0, "a fresh clone has no run folders, so strict must not fail on one")

    def test_a_run_folder_that_is_here_is_checked(self):
        evidence = [{"path": "BenchmarkRuns/run-a"}, {"path": "BenchmarkRuns/run-a/README.md", "contains": "16 right"}]
        repo = self.repo([entry(evidence=evidence)], {DESCRIPTION: "88% of test questions (15 of 17)\n"})
        repo.write("BenchmarkRuns/run-a/README.md", "15 right of 17\n")
        result = repo.check()
        self.assertEqual(checks(result["failures"]), ["evidence"])
        self.assertEqual(result["counts"]["evidence_confirmed"], 1)

    def test_the_ledger_is_tracked_so_its_absence_fails(self):
        repo = self.repo([entry(evidence=[{"path": "BenchmarkRuns/LEDGER.md", "contains": "15"}])],
                         {DESCRIPTION: "88% of test questions (15 of 17)\n"})
        failures = repo.check()["failures"]
        self.assertEqual(checks(failures), ["evidence"])
        self.assertIn("BenchmarkRuns/LEDGER.md does not exist", failures[0]["detail"])

    def test_not_claims_exempts(self):
        copy = {DESCRIPTION: "New in 5.8: your first library is Library 1.\n"}
        self.assertEqual({row["token"] for row in self.repo([], copy).check()["failures"]}, {"5.8", "1"})
        exempt = [{"pattern": r"\b5\.[78]\b", "reason": "the version number as a name"},
                  {"pattern": r"\bLibrary 1\b", "reason": "a library's name"}]
        result = self.repo([], copy, not_claims=exempt).check()
        self.assertEqual(result["failures"], [])
        self.assertEqual((result["counts"]["exempted"], result["counts"]["not_claims"]), (2, 2))

    def test_a_not_claims_pattern_exempts_only_what_it_matches(self):
        exempt = [{"pattern": r"\b5\.[78]\b", "reason": "the version number as a name"}]
        repo = self.repo([], {DESCRIPTION: "New in 5.8, and 5.8 seconds faster than 5.9.\n"}, not_claims=exempt)
        self.assertEqual([row["token"] for row in repo.check()["failures"]], ["5.9"])

    def test_a_not_claims_item_needs_a_reason_and_a_valid_pattern(self):
        repo = self.repo([], not_claims=[{"pattern": r"\d+"}, {"pattern": "(", "reason": "broken"}])
        self.assertEqual(checks(repo.check()["failures"]), ["not_claims", "not_claims"])

    def test_unverified_warns_and_strict_fails(self):
        unverified = entry(status="unverified", evidence=[], derivation=None,
                           note="Looked in BenchmarkRuns/LEDGER.md and Docs/USER_CHANGELOG.md, no count of 17.")
        repo = self.repo([unverified], {DESCRIPTION: "88% of test questions (15 of 17)\n"})
        result = repo.check()
        self.assertEqual(result["failures"], [])
        self.assertEqual(checks(result["warnings"]), ["unverified"])
        self.assertEqual(result["counts"]["unverified"], 1)
        code, printed = repo.run()
        self.assertEqual(code, 0)
        self.assertIn("WARN", printed)
        self.assertEqual(checks(repo.check(strict=True)["failures"]), ["unverified"])
        self.assertEqual(repo.run("--strict")[0], 1)

    def test_an_unverified_entry_needs_a_note(self):
        repo = self.repo([entry(status="unverified", evidence=[], derivation=None)],
                         {DESCRIPTION: "88% of test questions (15 of 17)\n"})
        self.assertEqual(checks(repo.check()["failures"]), ["entry"])

    def test_a_mismatch_entry_fails(self):
        repo = self.repo([entry(status="mismatch", derivation=None, note="copy says 88%, the run gives 14 of 17, 82%")],
                         {DESCRIPTION: "88% of test questions (15 of 17)\n"})
        result = repo.check()
        self.assertEqual(checks(result["failures"]), ["mismatch"])
        self.assertEqual(result["counts"]["mismatch"], 1)

    def test_a_derivation_whose_arithmetic_is_wrong_fails(self):
        repo = self.repo([entry(derivation="15/17 = 90.0%")], {DESCRIPTION: "88% of test questions (15 of 17)\n"})
        failures = repo.check()["failures"]
        self.assertEqual(checks(failures), ["derivation"])
        self.assertIn("15/17 is 88.2%", failures[0]["detail"])

    def test_a_derivation_that_does_not_give_the_claims_percentage_fails(self):
        repo = self.repo([entry(claim="90% of test questions (15 of 17)")], {DESCRIPTION: "90% of test questions (15 of 17)\n"})
        failures = repo.check()["failures"]
        self.assertEqual(checks(failures), ["derivation"])
        self.assertIn("rounds to 88%", failures[0]["detail"])

    def test_a_derivation_reads_commas_and_rounds_a_half_up(self):
        self.assertEqual(claims.check_derivation({"claim": "89% up from 58%", "derivation": "8,920/10,029 = 88.9%; 5,852/10,029 = 58.4%"}), [])
        self.assertEqual(claims.check_derivation({"claim": "13% of them", "derivation": "1/8 = 12.5%"}), [])
        self.assertEqual(claims.check_derivation({"claim": "about 14 seconds", "derivation": "82 s and 68 s: 14 s"}), [])

    def test_claim_text_that_left_the_copy_warns_and_strict_fails(self):
        repo = self.repo([entry()], {DESCRIPTION: "Answers with the passage they came from.\n"})
        result = repo.check()
        self.assertEqual(result["failures"], [])
        self.assertEqual(checks(result["warnings"]), ["claim not in copy"])
        self.assertEqual(checks(repo.check(strict=True)["failures"]), ["claim not in copy"])

    def test_a_malformed_entry_fails(self):
        bad = [entry(id="a", kind="guess"), entry(id="a"), entry(id="b", files=["README.md"]), entry(id="c", status="done")]
        details = " | ".join(row["detail"] for row in self.repo(bad).check(strict=False)["failures"] if row["check"] == "entry")
        for expected in ("kind 'guess'", "the id a is used twice", "README.md is not one of the five copy files", "status 'done'"):
            self.assertIn(expected, details)

    def test_a_missing_register_or_copy_file_fails(self):
        repo = self.repo([])
        os.remove(os.path.join(repo.root, PROMO))
        failures = repo.check()["failures"]
        self.assertEqual([(row["check"], row.get("file")) for row in failures], [("copy file", PROMO)])
        os.remove(os.path.join(repo.root, claims.REGISTER))
        self.assertEqual(checks(repo.check()["failures"]), ["register"])

    def test_json_output_holds_the_three_keys(self):
        repo = self.repo([entry()], {DESCRIPTION: "88% of test questions (15 of 17), 3 times a day\n"})
        code, printed = repo.run("--json")
        result = json.loads(printed)
        self.assertEqual(code, 1)
        self.assertEqual(sorted(result), ["counts", "failures", "warnings"])
        self.assertEqual(result["failures"][0]["token"], "3")


if __name__ == "__main__":
    unittest.main()
