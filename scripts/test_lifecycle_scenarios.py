#!/usr/bin/env python3
"""Tests for the judges in scripts/lifecycle_scenarios.py, on invented journals. No simulator.

Run: python3 scripts/test_lifecycle_scenarios.py
"""
import json, os, sys, tempfile, unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lifecycle_scenarios as life


def e(second, name, o="info", pid=1, **fields):
    return {"t": f"2026-01-01T10:{second // 60:02d}:{second % 60:02d}.000Z", "e": name, "o": o, "pid": pid, "f": fields}


START, DONE = e(10, "answer.start", "started", passages="120"), e(70, "answer.done", "ok")
AWAY, BACK = e(15, "app.phase", **{"from": "inactive", "to": "background"}), e(60, "app.phase", **{"from": "inactive", "to": "active"})


class Judges(unittest.TestCase):
    def test_an_answer_that_survives_leaving_passes(self):
        self.assertEqual(life.judge("leave", [START, AWAY, BACK, DONE], [])[0], "PASS")
        self.assertIn("answered in 60 s", life.judge("leave", [START, AWAY, BACK, DONE], [])[1])

    def test_an_answer_that_never_finishes_fails(self):
        self.assertEqual(life.judge("leave", [START, AWAY, BACK], [])[0], "FAIL")
        failed = e(70, "answer.done", "failed")
        verdict, why = life.judge("lock", [START, AWAY, BACK, failed], [])
        self.assertEqual(verdict, "FAIL")
        self.assertIn("ended failed", why)

    def test_a_run_that_missed_the_condition_is_not_a_pass(self):
        self.assertEqual(life.judge("leave", [START, DONE], [])[0], "NOT TESTED")  # finished before the app left
        self.assertEqual(life.judge("leave", [AWAY, BACK], [])[0], "NOT TESTED")  # nothing was asked
        self.assertEqual(life.judge("in-front", [START, AWAY, BACK, DONE], [])[0], "NOT TESTED")  # the baseline left

    def test_a_restart_during_the_answer_fails_leave_and_lock(self):
        restarted = [START, AWAY, e(40, "launch.chatUsable", "ok", pid=2), e(70, "answer.done", "ok", pid=2)]
        self.assertEqual(life.judge("leave", restarted, [])[0], "FAIL")

    def test_a_crash_report_or_a_long_freeze_fails_anything(self):
        self.assertEqual(life.judge("in-front", [START, DONE], ["OpenIntelligence-2026-01-01-100100.ips"])[0], "FAIL")
        frozen = [START, e(30, "mainThread.stall", ms="12200", phase="answer"), DONE]
        verdict, why = life.judge("in-front", frozen, [])
        self.assertEqual(verdict, "FAIL")  # a phone would have ended the app at about 10 s
        self.assertIn("12.2 s", why)
        verdict, why = life.judge("in-front", [START, e(30, "mainThread.stall", ms="8700"), DONE], [])
        self.assertEqual(verdict, "PASS")  # printed, not failed
        self.assertIn("longest main-thread stall 8.7 s", why)
        self.assertNotIn("stall", life.judge("in-front", [START, e(30, "mainThread.stall", ms="400"), DONE], [])[1])

    def test_the_verdict_says_where_the_work_finished(self):
        away_done = e(40, "answer.done", "ok", scene="background")
        self.assertIn("while away", life.judge("leave", [START, AWAY, away_done, BACK], [])[1])
        self.assertIn("after coming back", life.judge("leave", [START, AWAY, BACK, DONE], [])[1])
        begin = e(5, "import.stage", **{"from": "queued", "to": "extracting"})
        back = e(60, "app.phase", **{"from": "inactive", "to": "active"})
        self.assertIn("finishing after coming back",
                      life.judge("import", [begin, AWAY, back, e(90, "import.stage", to="complete")], [])[1])
        self.assertIn("finishing while away", life.judge("import", [begin, AWAY, e(40, "import.stage", to="complete"), back], [])[1])

    def test_ending_the_app(self):
        reopened = e(30, "launch.chatUsable", "ok", pid=2)
        self.assertEqual(life.judge("end-app", [START, reopened, e(80, "answer.done", "ok", pid=2)], [])[0], "PASS")
        self.assertEqual(life.judge("end-app", [START, reopened], [])[0], "FAIL")  # neither answered nor asked again
        self.assertEqual(life.judge("end-app", [START, reopened, e(32, "answer.restoredWritten", pid=2)], [])[0], "PASS")
        asked_again = [START, reopened, e(35, "answer.start", "started", pid=2)]
        self.assertIn("asked again", life.judge("end-app", asked_again, [])[1])
        self.assertEqual(life.judge("end-app", [START, DONE, reopened], [])[0], "NOT TESTED")  # finished before the end
        self.assertEqual(life.judge("end-app", [START, DONE], [])[0], "NOT TESTED")  # never ended

    def test_first_launch(self):
        two = [e(5, "launch.chatUsable", "ok", pid=1, ms="840"), e(50, "launch.chatUsable", "ok", pid=2, ms="150")]
        verdict, why = life.judge("first-launch", two, [])
        self.assertEqual((verdict, why), ("PASS", "Chat usable after 0.8 s, 0.1 s; search setup ran once"))
        self.assertEqual(life.judge("first-launch", two[:1], [])[0], "FAIL")
        first_setup = e(8, "reranker.load", "ok", pid=1, newInstall="true")
        self.assertEqual(life.judge("first-launch", two + [first_setup], [])[0], "PASS")
        again = e(55, "embedding.load", "ok", pid=2, newInstall="true")
        verdict, why = life.judge("first-launch", two + [first_setup, again], [])
        self.assertEqual(verdict, "FAIL")
        self.assertIn("set search up again", why)

    def test_an_answer_from_an_empty_library_is_not_a_test(self):
        empty = e(10, "answer.start", "started", passages="0")
        self.assertEqual(life.judge("leave", [empty, AWAY, BACK, DONE], [])[0], "NOT TESTED")

    def test_scenarios_are_cut_by_the_lines_the_tests_print(self):
        log = ("    [Lifecycle] 2026-01-01T10:00:00.000Z BEGIN -[OpenIntelligenceUITests.LifecycleScenarioUITests test4LeaveDuringAnAnswer]\n"
               "[Lifecycle] 2026-01-01T10:00:30.000Z asked\n"
               "[Lifecycle] 2026-01-01T10:02:00.000Z END -[OpenIntelligenceUITests.LifecycleScenarioUITests test4LeaveDuringAnAnswer]\n"
               "[Lifecycle] 2026-01-01T10:03:00.000Z BEGIN -[OpenIntelligenceUITests.LifecycleScenarioUITests test5LockDuringAnAnswer]\n")
        self.assertEqual(life.windows(log), {
            "test4LeaveDuringAnAnswer": ("2026-01-01T10:00:00.000Z", "2026-01-01T10:02:00.000Z"),
            "test5LockDuringAnAnswer": ("2026-01-01T10:03:00.000Z", None)})
        self.assertEqual({s[1] for s in life.SCENARIOS} >= set(life.windows(log)), True)

    def test_import(self):
        begin = e(5, "import.stage", **{"from": "queued", "to": "extracting"})
        complete = e(90, "import.stage", **{"from": "storing", "to": "complete"})
        self.assertEqual(life.judge("import", [begin, AWAY, BACK, complete], [])[0], "PASS")
        self.assertEqual(life.judge("import", [begin, AWAY, BACK], [])[0], "FAIL")
        self.assertEqual(life.judge("import", [begin, complete], [])[0], "NOT TESTED")
        twice = [begin, AWAY, BACK, complete, e(95, "import.stage", **{"from": "storing", "to": "complete"})]
        self.assertIn("2 times", life.judge("import", twice, [])[1])
        self.assertEqual(life.judge("import", [begin, AWAY, e(40, "import.stage", to="failed")], [])[0], "FAIL")

    def test_real_use_sorts_answers_by_what_happened_to_the_app(self):
        events = [
            e(10, "answer.start", "started", mode="standard"), e(40, "answer.done", "ok"),            # stayed, ok
            e(100, "answer.start", "started", mode="deepThink"), e(105, "app.phase", to="background"),
            e(160, "answer.done", "ok"),                                                             # left, ok
            e(200, "answer.start", "started"), e(205, "app.phase", to="background"),                 # left, never
            e(300, "answer.start", "started"), e(310, "launch.chatUsable", "ok", pid=2),
            e(360, "answer.done", "failed", pid=2),                                                  # restarted, failed
            e(400, "answer.start", "started", pid=2), e(410, "launch.chatUsable", "ok", pid=3),      # restarted...
            e(415, "answer.start", "started", pid=3), e(450, "answer.done", "ok", pid=3),            # ...asked again, ok
        ]
        rows = life.real_use(events)
        self.assertEqual([(r["kind"], r["end"]) for r in rows],
                         [("stayed", "ok"), ("left", "ok"), ("left", "never"), ("restarted", "failed"), ("restarted", "ok")])
        text = life.render_real_use(rows)
        self.assertIn("5 answers", text)
        self.assertIn("app left the front during the answer: 50% finished (1 of 2); 1 never", text)
        self.assertIn("50% finished (1 of 2); 1 failed", text)

    def test_a_run_folder_is_judged_again_from_its_files(self):
        with tempfile.TemporaryDirectory() as folder:
            with open(os.path.join(folder, "leave.jsonl"), "w") as f:
                f.write("\n".join(json.dumps(x) for x in [START, AWAY, BACK, DONE]) + "\nnot json\n")
            with open(os.path.join(folder, "lock.jsonl"), "w") as f:
                f.write(json.dumps(START))
            results = life.check_folder(folder)
            self.assertEqual([(r["name"], r["verdict"]) for r in results], [("leave", "PASS"), ("lock", "FAIL")])
            self.assertIn("1 of 2 scenarios passed", life.render(results))


if __name__ == "__main__":
    unittest.main()
