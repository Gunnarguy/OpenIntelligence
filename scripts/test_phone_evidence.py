#!/usr/bin/env python3
"""Tests for the checking half of scripts/phone_evidence.py (5.8).

    python3 scripts/test_phone_evidence.py

The checker turns a development build's journal into PASS, FAIL or NOT SEEN per roadmap row, so a wrong operator
or a rule it cannot read closes a row that should stay open. These pin the field operators (>=, <=, !=), a field read
from the line itself (`os`, `ms`), a rule's `absent` events, where `--mac` reads the Mac app's files, and that every
rule in scripts/phone_evidence_rules.json parses and runs.

Pulling from the iPhone is not covered: it needs `devicectl` and the phone.
"""

import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

spec = importlib.util.spec_from_file_location("phone_evidence", ROOT / "scripts/phone_evidence.py")
pe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pe)


def event(name, outcome="info", fields=None, **line):
    e = {"t": "2026-11-04T08:00:00.000Z", "e": name, "o": outcome, "v": "5.8 (151)", "pid": 1}
    if fields:
        e["f"] = fields
    e.update(line)
    return e


class FieldOperatorTests(unittest.TestCase):
    def test_at_least_and_at_most_compare_numbers(self):
        self.assertTrue(pe.field_ok("12", ">=12"))
        self.assertFalse(pe.field_ok("11", ">=12"))
        self.assertTrue(pe.field_ok("250", "<=250"))
        self.assertFalse(pe.field_ok("251", "<=250"))
        self.assertFalse(pe.field_ok("many", "<=250"))

    def test_not_equal_matches_any_other_value(self):
        self.assertTrue(pe.field_ok("fallback", "!=shrinkPrompt"))
        self.assertFalse(pe.field_ok("shrinkPrompt", "!=shrinkPrompt"))

    def test_a_missing_field_never_matches(self):
        self.assertFalse(pe.field_ok(None, "!=x"))
        self.assertFalse(pe.matches(event("a.b"), {"e": "a.b", "f": {"count": "<=3"}}))

    def test_plain_values_still_compare_as_text(self):
        self.assertTrue(pe.matches(event("nav.post", fields={"to": "chat"}), {"e": "nav.post", "f": {"to": "chat"}}))
        self.assertTrue(pe.matches(event("nav.post", fields={"to": "chat"}), {"e": "nav.*"}))

    def test_os_and_ms_are_read_from_the_line_itself(self):
        mac = event("sync.waitForFiles", "ok", {"files": "3"}, os="macOS", ms=812.5)
        self.assertTrue(pe.matches(mac, {"e": "sync.waitForFiles", "f": {"os": "macOS", "ms": ">=500"}}))
        self.assertFalse(pe.matches(mac, {"e": "sync.waitForFiles", "f": {"os": "iOS"}}))
        # A field in `f` wins over the line's own value of the same name.
        self.assertTrue(pe.matches(event("x", fields={"os": "iOS"}, os="macOS"), {"e": "x", "f": {"os": "iOS"}}))


class AbsentTests(unittest.TestCase):
    RULE = {"row": "r", "all": [{"e": "sync.waitForFiles", "o": "ok"}],
            "absent": [{"e": "mainThread.stall", "f": {"phase": "launch"}}]}

    def test_passes_when_the_unwanted_event_is_not_there(self):
        events = [event("sync.waitForFiles", "ok"), event("mainThread.stall", fields={"phase": "other", "ms": "400"})]
        status, _, _ = pe.check(self.RULE, events, "")
        self.assertEqual(status, "PASS")

    def test_fails_when_the_unwanted_event_is_there(self):
        events = [event("sync.waitForFiles", "ok"), event("mainThread.stall", fields={"phase": "launch", "ms": "900"})]
        status, _, problems = pe.check(self.RULE, events, "")
        self.assertEqual(status, "FAIL")
        self.assertEqual(problems[0]["unwanted"]["e"], "mainThread.stall")

    def test_a_rule_without_absent_behaves_as_before(self):
        rule = {"row": "r", "all": [{"e": "a.b", "min": 2}]}
        self.assertEqual(pe.check(rule, [event("a.b")], "")[0], "NOT SEEN")
        self.assertEqual(pe.check(rule, [event("a.b"), event("a.b")], "")[0], "PASS")


class MacPathTests(unittest.TestCase):
    def test_the_container_is_the_bundle_ids_data_folder(self):
        self.assertEqual(
            pe.mac_container("/Users/someone"),
            "/Users/someone/Library/Containers/Gunndamental.OpenIntelligence/Data")

    def test_pull_mac_copies_what_exists_and_lists_crash_reports(self):
        with tempfile.TemporaryDirectory() as home, tempfile.TemporaryDirectory() as out:
            documents = os.path.join(pe.mac_container(home), "Documents")
            os.makedirs(documents)
            with open(os.path.join(documents, "verification_events.jsonl"), "w") as f:
                f.write(json.dumps(event("app.phase", os="macOS")) + "\n")
            reports = os.path.join(home, "Library", "Logs", "DiagnosticReports")
            os.makedirs(reports)
            open(os.path.join(reports, "OpenIntelligence-2026-11-04-080000.ips"), "w").close()
            open(os.path.join(reports, "Other-2026-11-04.ips"), "w").close()

            got = pe.pull_mac(out, home=home)

            self.assertEqual(got, ["verification_events.jsonl"])
            self.assertEqual(len(pe.load_events(out, None)), 1)
            with open(os.path.join(out, "crash_reports.txt")) as f:
                self.assertEqual(f.read(), "OpenIntelligence-2026-11-04-080000.ips")


class SinceTests(unittest.TestCase):
    def test_a_time_with_z_or_an_offset_is_taken_as_given(self):
        self.assertEqual(pe.normalize_since("2026-11-04T08:00:00Z"), "2026-11-04T08:00:00.000Z")
        self.assertEqual(pe.normalize_since("2026-11-04T01:00:00-07:00"), "2026-11-04T08:00:00.000Z")

    def test_a_time_with_no_zone_is_local_and_becomes_utc(self):
        old = os.environ.get("TZ")
        os.environ["TZ"] = "America/Los_Angeles"
        try:
            import time
            time.tzset()
            # 2026-11-04 is after the change back to standard time, so Pacific is UTC-8.
            self.assertEqual(pe.normalize_since("2026-11-04T08:00"), "2026-11-04T16:00:00.000Z")
        finally:
            if old is None:
                os.environ.pop("TZ", None)
            else:
                os.environ["TZ"] = old
            time.tzset()

    def test_the_normalized_time_compares_with_journal_lines(self):
        with tempfile.TemporaryDirectory() as out:
            with open(os.path.join(out, "verification_events.jsonl"), "w") as f:
                for t in ("2026-11-04T07:59:59.999Z", "2026-11-04T08:00:00.000Z", "2026-11-04T08:30:12.345Z"):
                    f.write(json.dumps(dict(event("a.b"), t=t)) + "\n")
            kept = pe.load_events(out, pe.normalize_since("2026-11-04T08:00:00Z"))
            self.assertEqual([e["t"] for e in kept], ["2026-11-04T08:00:00.000Z", "2026-11-04T08:30:12.345Z"])

    def test_lines_from_a_ui_test_launch_are_dropped(self):
        with tempfile.TemporaryDirectory() as out:
            with open(os.path.join(out, "verification_events.jsonl"), "w") as f:
                f.write(json.dumps(event("nav.post")) + "\n")
                f.write(json.dumps(event("nav.post", host="uitest")) + "\n")
            self.assertEqual(len(pe.load_events(out, None)), 1)


class RulesFileTests(unittest.TestCase):
    def test_every_rule_event_is_recorded_somewhere_in_the_app(self):
        import re
        literal = re.compile(r'\b(?:record|Span|run)\(\s*"([^"\\]+)"')
        recorded = set()
        for path in (ROOT / "OpenIntelligence").rglob("*.swift"):
            recorded.update(literal.findall(path.read_text(encoding="utf-8", errors="replace")))
        with open(ROOT / "scripts/phone_evidence_rules.json") as f:
            rules = json.load(f)["rules"]
        missing = []
        for rule in rules:
            if "Needs the owner to name" in rule.get("needs", ""):
                continue
            for cond in rule.get("all", []) + rule.get("absent", []):
                name = cond["e"]
                if not name.endswith("*") and name not in recorded:
                    missing.append((rule["row"], name))
        self.assertEqual(missing, [])

    def test_every_rule_parses_and_runs_on_an_empty_journal(self):
        with open(ROOT / "scripts/phone_evidence_rules.json") as f:
            rules = json.load(f)["rules"]
        self.assertGreater(len(rules), 34)
        self.assertEqual(len({r["row"] for r in rules}), len(rules), "two rules name the same row")
        allowed = {"row", "url", "needs", "all", "trace", "absent", "absent_trace"}
        for rule in rules:
            self.assertLessEqual(set(rule), allowed, rule["row"])
            self.assertTrue(rule.get("all") or rule.get("trace"), rule["row"])
            for cond in rule.get("all", []) + rule.get("absent", []):
                self.assertIn("e", cond, rule["row"])
                self.assertLessEqual(set(cond), {"e", "o", "f", "min"}, rule["row"])
            status, _, _ = pe.check(rule, [], "")
            self.assertIn(status, ("NOT SEEN", "FAIL"), rule["row"])


if __name__ == "__main__":
    unittest.main()
