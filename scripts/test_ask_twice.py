#!/usr/bin/env python3
"""Tests for scripts/ask_twice.py: reading the test's "again" lines and what is counted from them.
No simulator: every line here is invented.

Run: python3 scripts/test_ask_twice.py
"""
import base64, os, sys, tempfile, unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ask_twice as twice


def b(text):
    return base64.b64encode(text.encode()).decode()


def again(number, question, first, later, same=None):
    same = (first == later) if same is None else same
    return (f"[AnswerQualityEvaluation] again pass={number} mode=standard seconds=7 same={'true' if same else 'false'} "
            f"question64={b(question)} first64={b(first)} again64={b(later)}")


CASES = [
    {"id": "exact_payload", "query": "What is the maximum payload?", "category": "exact", "expected_answer_patterns": ["1,240 lb"]},
    {"id": "litm_start", "query": "What is the token?", "category": "lost_in_middle", "expected_answer_patterns": ["LITM-START-1"]},
    {"id": "litm_end", "query": "What is the token?", "category": "lost_in_middle", "expected_answer_patterns": ["LITM-END-9"]},
    {"id": "which_doc", "query": "Which document mentions ALPHA?", "category": "retrieval_only",
     "expected_source": {"filename": "retrieval_alpha.md"}},
]


class AskTwice(unittest.TestCase):
    def test_lines_are_read_whole_and_in_order(self):
        lines = ["noise", again(2, "What is the maximum payload?", "1,240 lb. [S1]\nsecond line", "The payload is 1,240 lb."),
                 again(3, "What is the maximum payload?", "1,240 lb. [S1]\nsecond line", "1,240 lb. [S1]\nsecond line"),
                 "[AnswerQualityEvaluation] answered mode=standard seconds=3 question=x answer=y"]
        asked = twice.parse(lines)
        self.assertEqual(len(asked), 1)
        question, answers, seconds = asked[0]
        self.assertEqual(question, "What is the maximum payload?")
        self.assertEqual(answers, ["1,240 lb. [S1]\nsecond line", "The payload is 1,240 lb.", "1,240 lb. [S1]\nsecond line"])
        self.assertEqual(seconds, [7, 7])

    def test_right_and_same_are_counted_for_each_ask(self):
        asked = twice.parse([
            again(2, "What is the maximum payload?", "1,240 lb.", "About 1,200 lb."),      # right, then wrong
            again(2, "Which document mentions ALPHA?", "retrieval_alpha.md", "retrieval_alpha.md"),  # right twice, same words
        ])
        s = twice.summarize(asked, CASES)
        self.assertEqual((s["questions"], s["passes"]), (2, 2))
        self.assertEqual(s["right"], [2, 1])
        self.assertEqual(s["same_as_first"], [1])
        self.assertEqual(s["all_same"], 1)
        self.assertEqual(s["flipped"], ["exact_payload"])
        self.assertEqual(s["always_right"], 1)

    def test_a_question_three_cases_share_is_scored_against_each_in_turn(self):
        asked = twice.parse([
            again(2, "What is the token?", "LITM-START-1", "LITM-START-1"),
            again(2, "What is the token?", "LITM-END-9", "LITM-START-1"),   # the second case: right, then the other case's token
        ])
        s = twice.summarize(asked, CASES)
        self.assertEqual(s["right"], [2, 1])
        self.assertEqual(s["flipped"], ["litm_end"])

    def test_no_lines_is_none_and_a_row_says_not_run(self):
        self.assertIsNone(twice.summarize([], CASES))
        self.assertIn("not run", twice.row("maximum", "greedy", None, 0))

    def test_a_run_is_found_by_its_name(self):
        with tempfile.TemporaryDirectory() as runs:
            for name in ("2026-01-01-0900-answer-modes-twice-standard-greedy", "2026-01-01-0930-answer-modes-twice-standard-shipped",
                         "2026-01-01-1000-answer-modes-stab-standard-greedy-1"):
                os.makedirs(os.path.join(runs, name))
            found = [os.path.basename(f) for f in twice.folders_for("standard", "greedy", runs)]
            self.assertEqual(found, ["2026-01-01-0900-answer-modes-twice-standard-greedy"])
            self.assertEqual(twice.run_name("deepThink", "shipped"), "twice-deepThink-shipped")


if __name__ == "__main__":
    unittest.main()
