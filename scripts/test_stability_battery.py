#!/usr/bin/env python3
"""Tests for scripts/stability_battery.py: the numbers it draws from runs, and what it says about them.
No simulator: every run here is invented.

Run: python3 scripts/test_stability_battery.py
"""
import os, sys, tempfile, unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stability_battery as battery


def run(right, answers=None, total=20):
    """A run that got the questions in `right` right, with the given answer text per question."""
    results = {f"q{i}": (f"q{i}" in right) for i in range(total)}
    texts = {f"q{i}": (answers or {}).get(f"q{i}", f"answer {i}") for i in range(total)}
    return results, texts


ALL = {f"q{i}" for i in range(20)}


class Stability(unittest.TestCase):
    def test_identical_runs_have_no_spread(self):
        s = battery.summarize([run(ALL - {"q3"}), run(ALL - {"q3"})])
        self.assertEqual((s["runs"], s["rights"], s["spread"], s["unstable"]), (2, [19, 19], 0, []))
        self.assertEqual((s["identical"], s["asked"], s["always_right"]), (20, 20, 19))

    def test_a_question_that_flips_is_named_and_reworded_answers_are_counted(self):
        first = run(ALL - {"q3", "q7"})
        second = run(ALL - {"q3"}, answers={"q1": "the same fact in other words", "q7": "now right"})
        s = battery.summarize([first, second])
        self.assertEqual(s["rights"], [18, 19])
        self.assertEqual(s["unstable"], ["q7"])
        self.assertEqual(s["identical"], 18)  # q1 and q7 read differently; q1 stayed right
        self.assertEqual(s["mean"], 18.5)

    def test_no_runs_is_none_and_one_run_makes_no_claim_about_change(self):
        self.assertIsNone(battery.summarize([]))
        self.assertIn("not run", battery.row("greedy", "always the likeliest word", None))
        line = battery.row("shipped", "as the app ships", battery.summarize([run(ALL)]))
        self.assertIn("100% (20 of 20)", line)
        self.assertEqual(line.count("one run"), 2)

    def test_the_reading_separates_writing_from_everything_else(self):
        shipped = battery.summarize([run(ALL - {"q1"}), run(ALL - {"q2"}, answers={"q5": "reworded"})])
        fixed = battery.summarize([run(ALL - {"q1"}), run(ALL - {"q1"})])
        text = " ".join(battery.reading({"shipped": shipped, "greedy": fixed}))
        self.assertIn("2 of 20 questions changed between right and wrong", text)
        self.assertIn("the variation as shipped is the writing's randomness", text)
        drifting = battery.summarize([run(ALL), run(ALL, answers={"q4": "different passages came back"})])
        text = " ".join(battery.reading({"shipped": shipped, "greedy": drifting}))
        self.assertIn("1 of 20 answers still differed", text)
        self.assertIn("--arms hashed", text)
        self.assertIn("golden harnesses", text)
        text = " ".join(battery.reading({"shipped": shipped, "greedy": drifting, "hashed": fixed}))
        self.assertIn("the order of a set or dictionary reaches the prompt", text)

    def test_a_seed_that_does_not_repeat_is_said_only_against_greedy_runs_that_do(self):
        fixed = battery.summarize([run(ALL), run(ALL)])
        drifting = battery.summarize([run(ALL), run(ALL, answers={"q4": "another wording"})])
        text = " ".join(battery.reading({"greedy": fixed, "seeded": drifting}))
        self.assertIn("the fixed seed does not repeat across launches", text)
        text = " ".join(battery.reading({"greedy": drifting, "seeded": drifting}))
        self.assertNotIn("the fixed seed does not repeat", text)
        self.assertIn("the fixed seed repeats across launches", " ".join(battery.reading({"seeded": fixed})))

    def test_the_default_run_leaves_the_hashing_setting_out(self):
        self.assertNotIn("hashed", battery.DEFAULT_ARMS)
        self.assertIn("hashed", [a[0] for a in battery.ARMS])

    def test_a_setting_is_better_only_beyond_the_spread(self):
        shipped = battery.summarize([run(ALL - {"q1", "q2", "q3", "q4"}), run(ALL - {"q1", "q2"})])  # 16, 18
        greedy = battery.summarize([run(ALL - {"q1"}), run(ALL - {"q1"})])  # 19, 19: +2.0 against a spread of 2
        text = " ".join(battery.reading({"shipped": shipped, "greedy": greedy}))
        self.assertIn("is not distinguishable from as shipped", text)
        better = battery.summarize([run(ALL), run(ALL)])  # 20, 20: +3.0
        self.assertIn("scored higher than as shipped", " ".join(battery.reading({"shipped": shipped, "greedy": better})))
        worse = battery.summarize([run(ALL - {f"q{i}" for i in range(8)}), run(ALL - {f"q{i}" for i in range(8)})])
        self.assertIn("scored lower than as shipped", " ".join(battery.reading({"shipped": shipped, "cool": worse})))
        self.assertIn("With the adaptive-profiles switch on the mean was 20.0 right against 17.0",
                      " ".join(battery.reading({"shipped": shipped, "adaptive": better})))

    def test_runs_are_found_by_name_and_never_made_twice(self):
        with tempfile.TemporaryDirectory() as runs:
            for name in ("2026-01-01-0900-answer-modes-stab-standard-greedy-1", "2026-01-01-0930-answer-modes-stab-standard-greedy-2",
                         "2026-01-01-1000-answer-modes-stab-deepThink-greedy-1", "2026-01-01-1100-answer-modes-other"):
                os.makedirs(os.path.join(runs, name))
            found = [os.path.basename(f) for f in battery.folders_for("standard", "greedy", runs)]
            self.assertEqual(found, ["2026-01-01-0900-answer-modes-stab-standard-greedy-1",
                                     "2026-01-01-0930-answer-modes-stab-standard-greedy-2"])
            self.assertEqual(battery.folders_for("standard", "cool", runs), [])
            self.assertEqual(battery.run_name("standard", "cool", 3), "stab-standard-cool-3")
            whole = lambda folder, mode: True
            todo = battery.planned("standard", ["greedy", "cool"], runs_dir=runs, complete=whole)
            self.assertEqual([(arm, n) for arm, _, n in todo], [("cool", 1), ("cool", 2)])  # greedy has its 2
            self.assertEqual(len(battery.planned("standard", ["greedy", "cool"], 1, runs, whole)), 1)
            self.assertEqual(battery.planned("standard", ["greedy"], runs_dir=runs, complete=whole), [])
            # These folders are empty, as a run that failed leaves them: by the real rule none counts, so both are made again.
            again = battery.planned("standard", ["greedy"], runs_dir=runs)
            self.assertEqual([(arm, n) for arm, _, n in again], [("greedy", 1), ("greedy", 2)])
            self.assertIn("2 run folder(s) were cut short", " ".join(battery.report("standard", runs)[1]))


if __name__ == "__main__":
    unittest.main()
