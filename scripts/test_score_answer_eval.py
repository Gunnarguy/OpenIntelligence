#!/usr/bin/env python3
"""Tests for scripts/score_answer_eval.py's rule. The answers are shortened copies of real ones from the runs of
2026-11-21 to 11-23, one per shape the rule has to tell apart.

Run: python3 scripts/test_score_answer_eval.py
"""
import os, sys, unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import score_answer_eval as s

BATTERY = {"id": "missing_unreleased_battery", "category": "missing_evidence", "expected_behavior": "abstain",
           "query": "What is the warranty coverage for the unreleased 2032 prototype battery pack?",
           "expected_answer_patterns": []}
TEMPERATURE = {"id": "exact_temperature_limit", "category": "exact_value", "expected_behavior": "answer",
               "query": "What is the maximum charging temperature limit?", "expected_answer_patterns": [r"(?i)45\s+C"]}
OWNER = {"id": "multi_hop_project_m5", "category": "multi_hop", "expected_behavior": "answer",
         "query": "Who owns Project M5 and what is its reporting deadline?",
         "expected_answer_patterns": [r"Owner-5A", r"Q4 review gate"]}
MIDDLE = {"id": "lost_in_middle_middle", "category": "lost_in_middle", "expected_behavior": "answer",
          "query": "What is the required validation token?", "expected_answer_patterns": [r"LITM-MIDDLE-42"]}
START = {"id": "lost_in_middle_beginning", "category": "lost_in_middle", "expected_behavior": "answer",
         "query": "What is the required validation token?", "expected_answer_patterns": [r"LITM-BEGINNING-42"]}
CASES = [BATTERY, TEMPERATURE, OWNER, MIDDLE, START]


def right(case, answer):
    return s.rule(case, answer, CASES)


class Refusals(unittest.TestCase):
    def test_a_refusal_that_then_lists_other_documents_values_is_right(self):
        self.assertTrue(right(BATTERY, "Warranty coverage for the unreleased 2032 prototype battery pack is not stated "
                              "in the documents.\n\nRelevant findings:\n- The only explicit values found are 45 C [S6], "
                              "1,240 lb [S2] and $1,577 million [S29]."))

    def test_refusals_in_words_the_old_rule_did_not_know_are_right(self):
        for answer in (
            "### Warranty Coverage\n**The document explicitly states that the answer requested by the benchmark query "
            "cannot be fulfilled**, focusing instead on procedural steps [S10].",
            "The confidential wholesale price remains undetermined, as no document provides specific pricing data.",
            "**No definitive warranty coverage information is found** in the documents for the 2032 prototype pack.",
            "The warranty coverage for the unreleased 2032 prototype battery pack is not covered in the provided context.",
        ):
            self.assertTrue(right(BATTERY, answer), answer)

    def test_the_banner_and_the_leaked_instruction_are_read_past(self):
        self.assertTrue(right(BATTERY, "⚠️ **[Needs Verification]** This answer was drafted but could not be strictly "
                              "verified against the retrieved evidence: The warranty coverage is not specified in the "
                              "provided documents [S19]."))
        self.assertTrue(right(BATTERY, "The exact value, name or finding, written as the source writes it, with its "
                              "label: **no warranty coverage is mentioned for the unreleased 2032 prototype battery "
                              "pack** [S15]."))

    def test_an_answer_that_offers_a_value_before_declining_is_wrong(self):
        self.assertFalse(right(BATTERY, "The warranty coverage for the unreleased 2032 prototype battery pack is "
                               "defined by the **primary answer** in the battery_limits.md document, which states: "
                               "**45 C** [S20]."))
        self.assertFalse(right(BATTERY, "The warranty coverage for the unreleased 2032 prototype battery pack is not "
                               "specified beyond the primary value of 45 C [S20]."))

    def test_the_questions_own_year_is_not_a_made_up_value(self):
        self.assertTrue(right(BATTERY, "Nothing about the 2032 prototype battery pack's warranty is stated in the sources."))

    def test_an_answer_that_never_declines_is_wrong(self):
        self.assertFalse(right(BATTERY, "The document outlines public support, safety, and troubleshooting policies."))


class Values(unittest.TestCase):
    def test_the_value_given_as_the_answer_is_right(self):
        self.assertTrue(right(TEMPERATURE, "The maximum charging temperature limit is **45 C** [S1]."))

    def test_a_value_named_only_after_saying_the_documents_do_not_hold_it_is_wrong(self):
        self.assertFalse(right(TEMPERATURE, "The maximum charging temperature limit is not specified in the excerpts "
                               "[S1]. The table in [S1] includes values such as 45 C and 88 units, but these pertain "
                               "to other metrics."))

    def test_a_first_sentence_with_the_value_and_a_caveat_is_right(self):
        self.assertTrue(right(OWNER, "The reporting deadline for Project M5 is the Q4 review gate [S1], and the owner "
                              "is not listed [S2]. Elsewhere the accountable owner is named as Owner-5A [S3]."))

    def test_a_later_caveat_does_not_undo_an_answer(self):
        self.assertTrue(right(OWNER, "The accountable owner for Project M5 is Owner-5A [S2]. The reporting deadline is "
                              "the Q4 review gate [S1]. The memo does not list the owner [S1]."))

    def test_lost_in_the_middle_still_fails_another_documents_token(self):
        self.assertTrue(right(MIDDLE, "The required validation token is **LITM-MIDDLE-42** [S1]."))
        self.assertFalse(right(MIDDLE, "The required validation token is **LITM-BEGINNING-42** [S1]."))
        self.assertFalse(right(MIDDLE, "The token is LITM-MIDDLE-42. LITM-BEGINNING-42 is also referenced."))


if __name__ == "__main__":
    unittest.main()
