#!/usr/bin/env python3
"""Tests for the parts of scripts/install_to_phone.py that need no build and no phone.

Run: python3 scripts/test_install_to_phone.py
"""
import datetime, json, os, plistlib, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_to_phone as install


class InstallToPhone(unittest.TestCase):
    def test_build_number_is_two_integers_naming_the_commit_count_and_the_time(self):
        self.assertEqual(install.build_number(1876, datetime.datetime(2026, 11, 20, 10, 41)), "1876.201041")
        self.assertEqual(install.build_number(1876, datetime.datetime(2026, 12, 5, 0, 7)), "1876.50007")
        for moment in (datetime.datetime(2026, 1, 1, 0, 0), datetime.datetime(2026, 12, 31, 23, 59)):
            parts = install.build_number(7, moment).split(".")
            self.assertEqual(len(parts), 2)
            self.assertTrue(all(p.isdigit() and str(int(p)) == p for p in parts))  # no leading zero to be dropped

    def test_the_version_is_the_first_numbered_changelog_heading(self):
        text = "## [Unreleased]\n\n<!-- next-version: 6.0 -->\n\n## 5.9 <!-- unreleased -->\n\n## 5.8 - November 21, 2026\n"
        self.assertEqual(install.marketing_version(text), "5.9")

    def test_the_summary_line(self):
        entry = {"version": "5.8", "build": "1876.201041", "commit": "19c36f86" + "0" * 32, "dirty": False,
                 "installed": True, "launched": False, "why": ""}
        self.assertEqual(install.summary(entry), "installed 5.8 (1876.201041) = 19c36f86, not launched: open it on the phone")
        entry.update(dirty=True, launched=True)
        self.assertEqual(install.summary(entry), "installed 5.8 (1876.201041) = 19c36f86 + uncommitted changes, launched")
        entry.update(installed=False, why="the app is in use on the phone")
        self.assertEqual(install.summary(entry),
                         "built 5.8 (1876.201041) = 19c36f86 + uncommitted changes, NOT installed: the app is in use on the phone")

    def test_the_record_is_one_json_line_per_run(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "sub", "installs.jsonl")
            install.record({"build": "1.1"}, path)
            install.record({"build": "2.2"}, path)
            self.assertEqual([json.loads(l)["build"] for l in open(path)], ["1.1", "2.2"])

    def test_bundle_versions_reads_the_app_and_its_extensions(self):
        with tempfile.TemporaryDirectory() as app:
            for folder, build in ((app, "9.1"), (os.path.join(app, "PlugIns", "Widget.appex"), "150")):
                os.makedirs(folder, exist_ok=True)
                with open(os.path.join(folder, "Info.plist"), "wb") as f:
                    plistlib.dump({"CFBundleShortVersionString": "5.8", "CFBundleVersion": build}, f)
            found = install.bundle_versions(app)
            self.assertEqual(found[os.path.basename(app)], ("5.8", "9.1"))
            self.assertEqual(found["Widget.appex"], ("5.8", "150"))  # a mismatch the script refuses to install

    def test_a_dry_run_prints_the_build_and_changes_nothing(self):
        r = subprocess.run([sys.executable, os.path.join(HERE, "install_to_phone.py"), "--dry-run", "--scratch", "/nonexistent"],
                           capture_output=True, text=True, timeout=120)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertRegex(r.stdout.splitlines()[0], r"^would build [0-9.]+ \(\d+\.\d{5,6}\) = [0-9a-f]{8}")
        self.assertIn("CURRENT_PROJECT_VERSION=", r.stdout)
        self.assertFalse(os.path.exists("/nonexistent"))


if __name__ == "__main__":
    unittest.main()
