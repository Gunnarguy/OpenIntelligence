#!/usr/bin/env python3
"""Run the real Repo Map survey on this repository and re-check its verdicts independently.

    python3 .claude/skills/repo-map/scripts/test_build_map.py

The assertions are properties that hold whatever the code contains, never a count or a file name
from today's tree: a test that asserts the live tree goes red the first time someone cleans up, and a
permanently red test hides real failures. Each one re-derives a verdict by a different route than
build_map.py took. About a minute, most of it the survey.
"""

import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = Path(subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=HERE, capture_output=True, text=True).stdout.strip())
TMP = Path(tempfile.mkdtemp(prefix="oi-repo-map-test."))
STATUSES = {"outdated", "dead-links", "behind", "verified", "current", "unchecked", "history"}


def strip_comments(s: str) -> str:
    s = re.sub(r"/\*.*?\*/", " ", s, flags=re.S)
    return re.sub(r"//[^\n]*", " ", s)


def live_swift() -> dict[str, str]:
    """Source the app, tests and widget compile. Package.swift is left out: its exclude list names
    files by path, which is not a use (it flagged KeychainStorage.swift the first time this ran)."""
    roots = ("OpenIntelligence/", "OpenIntelligenceTests/", "OpenIntelligenceLiveActivities/")
    out = subprocess.run(["git", "ls-files", "*.swift"], cwd=ROOT, capture_output=True, text=True).stdout.split()
    return {p: strip_comments((ROOT / p).read_text(errors="ignore")) for p in out if p.startswith(roots)}


def sdk_declares(names: set[str]) -> set[str]:
    if not names:
        return set()
    dev = subprocess.run(["xcode-select", "-p"], capture_output=True, text=True).stdout.strip()
    files = [str(p) for sdk in ("iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk", "MacOSX.platform/Developer/SDKs/MacOSX.sdk")
             for p in Path(dev, "Platforms", sdk, "System/Library/Frameworks").rglob("*.swiftinterface")]
    pat = r"(class|struct|enum|actor|protocol|typealias) (" + "|".join(sorted(names)) + r")\b"
    found = set()
    for i in range(0, len(files), 400):
        out = subprocess.run(["grep", "-h", "-o", "-E", pat, *files[i:i + 400]], capture_output=True, text=True).stdout
        found.update(m.split()[1] for m in out.splitlines() if " " in m)
    return found


class RepoMapTests(unittest.TestCase):
    survey: dict = {}

    @classmethod
    def setUpClass(cls):
        out = TMP / "data.json"
        r = subprocess.run([sys.executable, str(HERE / "build_map.py"), "--root", str(ROOT), "--out", str(out)],
                           capture_output=True, text=True, timeout=600)
        if r.returncode != 0:
            raise AssertionError(f"build_map.py failed:\n{r.stdout}\n{r.stderr}")
        cls.survey = json.loads(out.read_text())
        cls.swift = live_swift()

    def test_refuses_to_write_inside_the_repository(self):
        r = subprocess.run([sys.executable, str(HERE / "build_map.py"), "--root", str(ROOT),
                            "--out", str(ROOT / "Docs" / "repo-map-test.json")], capture_output=True, text=True)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("outside the repository", r.stderr)
        self.assertFalse((ROOT / "Docs" / "repo-map-test.json").exists())

    def test_every_doc_has_a_known_status_and_a_reason(self):
        for d in self.survey["docs"]:
            self.assertIn(d["status"], STATUSES, d["path"])
            self.assertTrue(d["why"], f"{d['path']} has status {d['status']} and no reason")

    def test_a_removed_type_is_declared_neither_in_live_code_nor_in_the_sdk(self):
        removed = set()
        for d in self.survey["docs"]:
            for b in d["refs_broken"]:
                if b["kind"] == "type":
                    removed.add(b["ref"])
                m = re.match(r"type (\w+) no longer exists", b["why"])
                if m:
                    removed.add(m.group(1))
        declared = {t for s in self.swift.values() for t in re.findall(r"\b(?:class|struct|enum|actor|protocol|typealias)\s+([A-Z]\w*)", s)}
        named = {t for s in self.swift.values() for t in re.findall(r"\b[A-Z]\w*\b", s)}
        self.assertFalse(removed & declared, f"reported removed but declared: {sorted(removed & declared)}")
        self.assertFalse(removed & named, f"reported removed but named by live code: {sorted(removed & named)}")
        in_sdk = sdk_declares(removed)
        self.assertFalse(in_sdk, f"reported removed but Apple's SDK declares them: {sorted(in_sdk)}")

    def test_an_unused_file_has_no_type_named_by_any_other_file(self):
        for f in self.survey["files"]:
            if f.get("use") != "orphan":
                continue
            for t in f["types"]:
                users = [p for p, s in self.swift.items() if p != f["p"] and re.search(r"\b" + re.escape(t) + r"\b", s)]
                self.assertFalse(users, f"{f['p']} is marked unused, but {t} is named in {users[:3]}")

    def test_an_ignored_line_never_produces_a_dead_reference(self):
        for d in self.survey["docs"]:
            if not d["refs_broken"]:
                continue
            lines = (ROOT / d["path"]).read_text(errors="ignore").splitlines()
            for b in d["refs_broken"]:
                token = b["ref"].split(":")[0].split(".")[-1] if b["kind"] == "symbol" else b["ref"].split(":")[0]
                hits = [ln for ln in lines if token in ln]
                if hits and all("verify-doc-claims: ignore" in ln for ln in hits):
                    self.fail(f"{d['path']}: {b['ref']} is reported, but every line naming it is marked ignore")

    def test_render_embeds_the_survey_as_valid_json(self):
        out = TMP / "page.html"
        r = subprocess.run([sys.executable, str(HERE / "render.py"), str(TMP / "data.json"), str(out)],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        page = out.read_text()
        self.assertIn("<title>OpenIntelligence Repo Map</title>", page[:8192])
        m = re.search(r'<script type="application/json" id="data">(.*?)</script>', page, re.S)
        assert m is not None, "the page has no embedded survey"
        self.assertEqual(len(json.loads(m.group(1))["files"]), len(self.survey["files"]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
