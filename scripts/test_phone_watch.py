#!/usr/bin/env python3
"""Tests for scripts/phone_watch.py, on an invented journal. No phone and no network.

Run: python3 scripts/test_phone_watch.py
"""
import json, os, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import phone_watch as watch

# Invented names. None of these may ever reach a printed line.
SECRETS = ["Lease Agreement 2024.pdf", "Tax Return", "what is my deposit", "Medical Library", "/var/mobile/Lease"]


def line(t, e, o="info", f=None, pid=100, v="9.9 (1)", **extra):
    return dict({"t": f"2026-01-01T10:00:{t:06.3f}Z", "e": e, "o": o, "os": "iOS", "v": v, "pid": pid, "f": f or {}}, **extra)


JOURNAL = [
    line(1, "launch.chatUsable", "ok", {"ms": "840", "passages": "1200", "watchdog": "false"}),
    line(2, "answer.start", "started", {"mode": "deepThink", "passages": "12", "first": "true"}),
    line(3, "entity.documents", f={"query": SECRETS[2], "count": "3"}),
    line(4, "import.stage", f={"item": SECRETS[0], "to": "complete", "type": "pdf", "from": "storing"}),
    line(5, "import.stage", f={"item": SECRETS[1], "to": "complete", "type": "pdf", "from": "storing"}),
    line(6, "mainThread.stall", f={"ms": "3200", "phase": "import"}),
    line(7, "mainThread.stall", f={"ms": "300", "phase": "idle"}),
    line(8, "model.failure", f={"kind": "rateLimited", "mode": "standard", "action": "backoffLadder"}),
    line(9, "answer.done", "failed", {"mode": "deepThink", "badge": "partial", "scene": "background", "inFront": "false",
                                      "sources": "5", "error": "could not read " + SECRETS[0], "gating": SECRETS[3],
                                      "library": SECRETS[3]}, ms=41200.0),
    line(10, "bgtask.answer", f={"phase": "expired", "fraction": "0.4", "error": SECRETS[4]}),
    line(11, "bgtask.answer", f={"phase": "completed"}),
    line(12, "sync.waitForFiles", "failed", {"files": SECRETS[0], "roots": SECRETS[4], "error": SECRETS[1]}),
    line(13, "answer.start", "started", {"mode": "standard", "passages": "8", "first": "false"}, pid=222),
    line(14, "answer.done", "ok", {"mode": "standard", "badge": "supported", "scene": "foreground", "inFront": "true",
                                   "sources": "3", "error": "none"}, pid=222, ms=6100.0),
    line(15, "answer.start", "started", {"mode": "standard"}, pid=222, host="uitest"),
]


def write(folder, events, crashes=()):
    with open(os.path.join(folder, watch.JOURNAL), "w") as f:
        f.write("\n".join(json.dumps(e) for e in events) + "\nnot json\n")
    with open(os.path.join(folder, "crash_reports.txt"), "w") as f:
        f.write("\n".join(crashes))


class PhoneWatch(unittest.TestCase):
    def run_pass(self, folder, state):
        return watch.one_pass(folder, state, from_device=False)

    def test_reports_what_happened_and_nothing_private(self):
        with tempfile.TemporaryDirectory() as folder:
            write(folder, JOURNAL)
            out = "\n".join(self.run_pass(folder, {}))
        for secret in SECRETS:
            self.assertNotIn(secret, out)
        for word in ("Lease", "Tax", "deposit", "Medical", "/var"):
            self.assertNotIn(word, out)
        self.assertIn("app launched: build 9.9 (1), ms=840, passages=1200, watchdog=false", out)
        self.assertIn("question asked: mode=deepThink, passages=12, first=true", out)
        self.assertIn("MODEL FAILURE: kind=rateLimited, mode=standard, action=backoffLadder", out)
        self.assertIn("answer done [failed]: mode=deepThink, badge=partial, scene=background, inFront=false, sources=5, "
                      "error=<text>, took 41.2 s", out)
        self.assertIn("background answer: phase=expired, fraction=0.4", out)
        self.assertNotIn("phase=completed", out)
        self.assertIn("FAILED sync.waitForFiles", out)
        self.assertIn("app restarted: build 9.9 (1), pid 222 (was pid 100)", out)
        self.assertIn("answer done: mode=standard, badge=supported, scene=foreground, inFront=true, sources=3, took 6.1 s", out)
        self.assertIn("2 imports complete (pdf)", out)
        self.assertIn("1 main-thread stall of 2 s or more, longest 3.2 s (phase import)", out)
        self.assertEqual(out.count("question asked"), 2)  # the UI-test line is dropped

    def test_a_launch_names_the_commit_from_the_install_record(self):
        installs = [
            {"version": "9.9", "build": "1", "commit": "a1b2c3d4" + "0" * 32, "dirty": True, "installed": True},
            {"version": "9.9", "build": "77.201041", "commit": "ffff0000" + "1" * 32, "dirty": False, "installed": False},
        ]
        with tempfile.TemporaryDirectory() as folder:
            write(folder, JOURNAL[:2])
            path = os.path.join(folder, "installs.jsonl")
            with open(path, "w") as f:
                f.write("\n".join(json.dumps(i) for i in installs) + "\nnot json\n")
            out = "\n".join(watch.one_pass(folder, {}, from_device=False, installs_path=path))
            self.assertIn("app launched: build 9.9 (1) = a1b2c3d4 + uncommitted changes, ms=840", out)
            self.assertNotIn("NOT the newest", out)  # a build that was only built, never installed, is not the newest install
            installs[1]["installed"] = True
            with open(path, "w") as f:
                f.write("\n".join(json.dumps(i) for i in installs))
            out = "\n".join(watch.one_pass(folder, {}, from_device=False, installs_path=path))
            self.assertIn("build 9.9 (1) = a1b2c3d4 + uncommitted changes (NOT the newest install, which is 9.9 (77.201041))", out)
            # No record at all: the line is as before.
            out = "\n".join(watch.one_pass(folder, {}, from_device=False, installs_path=os.path.join(folder, "none")))
            self.assertIn("app launched: build 9.9 (1), ms=840", out)

    def test_the_cursor_moves_and_nothing_is_reported_twice(self):
        with tempfile.TemporaryDirectory() as folder:
            state = {}
            write(folder, JOURNAL[:2])
            self.assertEqual(len(self.run_pass(folder, state)), 2)
            self.assertEqual(self.run_pass(folder, state), [])
            write(folder, JOURNAL[:9])
            later = self.run_pass(folder, state)
            self.assertFalse(any("app launched" in l for l in later))
            self.assertTrue(any("answer done" in l for l in later))

    def test_a_rotated_journal_is_read_from_the_previous_file(self):
        with tempfile.TemporaryDirectory() as folder:
            state = {}
            write(folder, JOURNAL[:2])
            self.run_pass(folder, state)
            with open(os.path.join(folder, watch.PREVIOUS), "w") as f:
                f.write("\n".join(json.dumps(e) for e in JOURNAL[:9]))
            write(folder, JOURNAL[12:14])
            out = "\n".join(self.run_pass(folder, state))
            self.assertIn("MODEL FAILURE", out)
            self.assertIn("mode=standard", out)

    def test_only_a_new_crash_report_is_announced(self):
        with tempfile.TemporaryDirectory() as folder:
            state = {}
            write(folder, [], ["Retired/OpenIntelligence-2026-01-01-090000.ips.synced   27 KB"])
            self.assertEqual(self.run_pass(folder, state), [])  # already there when the watch started
            write(folder, [], ["Retired/OpenIntelligence-2026-01-01-090000.ips.synced   27 KB",
                               "OpenIntelligence-2026-01-01-101500.ips   31 KB"])
            self.assertEqual(self.run_pass(folder, state), ["CRASH report on the phone: OpenIntelligence-2026-01-01-101500.ips"])
            self.assertEqual(self.run_pass(folder, state), [])

    def test_a_flood_is_capped(self):
        with tempfile.TemporaryDirectory() as folder:
            write(folder, [line(i % 60, "model.failure", f={"kind": "rateLimited"}) for i in range(1, 40)])
            out = self.run_pass(folder, {})
            self.assertEqual(len(out), watch.MAX_LINES + 1)
            self.assertIn("more lines", out[-1])

    def test_safe_values(self):
        self.assertEqual(watch.safe("deepThink"), "deepThink")
        self.assertEqual(watch.safe(3.5), "3.5")
        self.assertEqual(watch.safe(True), "true")
        for value in ("two words", "a/b", "x" * 33, "name.pdf and more", None, {"a": 1}, ""):
            self.assertEqual(watch.safe(value), "<text>")

    def test_the_command_line_runs_one_pass_over_a_folder(self):
        with tempfile.TemporaryDirectory() as folder:
            write(folder, JOURNAL)
            r = subprocess.run([sys.executable, os.path.join(HERE, "phone_watch.py"), "--dir", folder,
                                "--state", os.path.join(folder, "state.json")], capture_output=True, text=True, timeout=60)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("question asked", r.stdout)
            self.assertTrue(os.path.exists(os.path.join(folder, "state.json")))


if __name__ == "__main__":
    unittest.main()
