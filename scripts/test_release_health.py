#!/usr/bin/env python3
"""Tests for scripts/release_health.py: what counts as new since the last run. No network.

Run: python3 scripts/test_release_health.py
"""
import os, sys, unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import release_health as health


def snap(**over):
    base = {"read": "2026-01-01T09:15:00-08:00", "live": {"IOS": {"version": "5.7", "build": "487", "buildId": "b1"}},
            "reviews": [{"id": "r1", "rating": 5, "date": "2026-01-01", "country": "USA", "title": "Good", "body": "Works."}],
            "rating": {"average": 4, "count": 5, "storeVersion": "5.7"}, "regressions": [], "metrics": [],
            "signatures": {"IOS": []}}
    base.update(over)
    return base


class ReleaseHealth(unittest.TestCase):
    def test_nothing_changed_is_nothing_new(self):
        self.assertEqual(health.changes(snap(), snap()), [])
        self.assertIn("Nothing new.", health.render(snap(), []))

    def test_a_new_version_review_rating_regression_and_signature_are_each_one_line(self):
        new = snap(
            live={"IOS": {"version": "5.8", "build": "509", "buildId": "b2"}},
            reviews=[{"id": "r2", "rating": 1, "date": "2026-01-08", "country": "GBR", "title": "Broke", "body": "It crashes\non   launch."},
                     {"id": "r1", "rating": 5, "date": "2026-01-01", "country": "USA", "title": "Good", "body": "Works."}],
            rating={"average": 3.5, "count": 6, "storeVersion": "5.8"},
            regressions=["Launch Time trended up between app versions 5.7 to 5.8"],
            signatures={"IOS": [{"id": "s1", "kind": "HANGS", "weight": 42.5, "signature": "RAGService.search"}]},
            metrics=[{"metric": "launchTime", "unit": "ms", "device": "All iPhones", "percentile": "fifty",
                      "latest": {"value": 1100, "version": "5.8"}, "previous": {"value": 1000, "version": "5.7"}}])
        lines = health.changes(snap(), new)
        self.assertEqual(len(lines), 6)
        self.assertIn("IOS: version 5.8 (build 509) is live, was 5.7", lines)
        self.assertIn("new review: 1 stars, 2026-01-08, GBR: Broke. It crashes on launch.", lines)
        self.assertIn("US rating: 3.5 from 6 ratings, was 4 from 5", lines)
        self.assertTrue(any(l.startswith("Apple flags a regression: Launch Time") for l in lines))
        self.assertTrue(any("1 new hangs signature(s), heaviest 42.5%: RAGService.search" in l for l in lines))
        self.assertTrue(any("now reports 1 performance figures" in l for l in lines))
        report = health.render(new, lines)
        self.assertIn("launchTime (All iPhones, fifty): 1100 ms in 5.8, +10% against 5.7", report)
        self.assertIn("- new review: 1 stars", report)
        self.assertEqual(health.changes(new, new), [])  # reported once

    def test_a_report_with_no_apple_figures_says_why(self):
        report = health.render(snap(), [])
        self.assertIn("None reported: Apple shows them only once enough people", report)
        self.assertIn("crash reports", report)


if __name__ == "__main__":
    unittest.main()
