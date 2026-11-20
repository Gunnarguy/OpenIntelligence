#!/usr/bin/env python3
"""Tests for scripts/asc_submit_gate.py. No network: every case is a hand-built snapshot fed to check().

Run: python3 scripts/test_asc_submit_gate.py
"""
import os, sys, unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asc_submit_gate as gate

TERMS = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
DESCRIPTION = ("A private research librarian for your documents.\n\n"
               "Privacy Policy: example.com/privacy/\n"
               f"Terms of Use (EULA): {TERMS}")


def localization(sets):
    return {"locale": "en-US", "description": DESCRIPTION, "whatsNew": "Citations land on the right passage 89% (17 of 19) of the time.",
            "keywords": "pdf,search", "promotionalText": "", "supportUrl": "https://example.com/support",
            "marketingUrl": None, "screenshotSets": [{"type": t, "count": 3, "states": ["COMPLETE"]} for t in sets]}


def platform(sets):
    return {"state": "PREPARE_FOR_SUBMISSION", "releaseType": "AFTER_APPROVAL", "copyright": True,
            "build": {"version": "600", "processingState": "VALID", "expired": False, "usesNonExemptEncryption": False,
                      "commit": "a" * 40},
            "localizations": [localization(sets)],
            "review": {"contact": True, "notesLength": 900, "demoRequired": False, "demoSet": False, "notesHoldFile": True},
            "submissions": []}


def good():
    return {
        "version": "9.9", "app": "1", "collected": "test",
        "subscription_groups": [{"name": "Plans", "subscriptions": [{"productId": "pro_monthly", "state": "APPROVED"}]}],
        "purchases": [{"productId": "lifetime", "state": "APPROVED"}], "custom_eula": False,
        "app_infos": [{"state": "PREPARE_FOR_SUBMISSION", "ageRating": "FOUR_PLUS", "ageUnanswered": [], "ageOverride": "NONE",
                       "localizations": [{"locale": "en-US", "name": "App", "subtitle": "Sub",
                                          "privacyPolicyUrl": "https://example.com/privacy"}]}],
        "platforms": {"IOS": platform(["APP_IPHONE_67", "APP_IPAD_PRO_3GEN_129"]), "MAC_OS": platform(["APP_DESKTOP"])},
        "urls": {TERMS: 200, "https://example.com/privacy": 200, "https://example.com/support": 200},
        "repo": {"tag": "v9.9.0", "tagCommit": "a" * 40, "description": DESCRIPTION, "keywords": "pdf,search"},
    }


def levels(snap, name):
    return [r["level"] for r in gate.check(snap) if r["check"].split("[")[0] == name]


class SubmitGate(unittest.TestCase):
    def test_a_complete_record_has_no_fail_and_no_warn(self):
        results = gate.check(good())
        self.assertEqual([r for r in results if r["level"] in ("FAIL", "WARN")], [])

    def test_the_rejection_of_2026_11_20_fails(self):
        # 5.8's description on 2026-11-19: subscriptions on sale, a privacy line, and no Terms of Use link.
        snap = good()
        for p in snap["platforms"].values():
            p["localizations"][0]["description"] = DESCRIPTION.split("\nTerms of Use")[0]
        self.assertEqual(levels(snap, "terms-link"), ["FAIL", "FAIL"])

    def test_a_terms_line_with_no_link_fails(self):
        snap = good()
        snap["platforms"]["IOS"]["localizations"][0]["description"] = "Terms of Use apply."
        self.assertIn("FAIL", levels(snap, "terms-link"))

    def test_a_dead_terms_link_fails(self):
        snap = good()
        snap["urls"][TERMS] = 404
        self.assertEqual(levels(snap, "terms-link"), ["FAIL", "FAIL"])

    def test_a_custom_eula_or_no_subscriptions_needs_no_link(self):
        for change in (lambda s: s.update(custom_eula=True), lambda s: s.update(subscription_groups=[])):
            snap = good()
            change(snap)
            for p in snap["platforms"].values():
                p["localizations"][0]["description"] = "No links here."
            self.assertEqual(levels(snap, "terms-link"), ["PASS", "PASS"])

    def test_text_over_its_limit_fails(self):
        snap = good()
        snap["platforms"]["MAC_OS"]["localizations"][0]["description"] = DESCRIPTION + "x" * 4000
        snap["platforms"]["IOS"]["localizations"][0]["keywords"] = "k" * 101
        snap["platforms"]["IOS"]["localizations"][0]["whatsNew"] = ""
        self.assertIn("FAIL", levels(snap, "description-length"))
        self.assertIn("FAIL", levels(snap, "keywords-length"))
        self.assertIn("FAIL", levels(snap, "whatsNew-length"))

    def test_builds_must_match_be_valid_and_come_from_the_tag(self):
        snap = good()
        snap["platforms"]["IOS"]["build"]["version"] = "599"
        self.assertEqual(levels(snap, "same-build"), ["FAIL"])
        snap = good()
        snap["platforms"]["IOS"]["build"]["processingState"] = "PROCESSING"
        snap["platforms"]["MAC_OS"]["build"] = None
        self.assertEqual(levels(snap, "build")[:2], ["FAIL", "FAIL"])
        snap = good()
        snap["repo"]["tagCommit"] = "b" * 40
        self.assertEqual(levels(snap, "build-commit"), ["FAIL"])
        snap = good()
        snap["repo"]["tagCommit"] = None
        self.assertEqual(levels(snap, "build-commit"), ["WARN"])

    def test_missing_screenshots_or_a_failed_upload_fails(self):
        snap = good()
        snap["platforms"]["IOS"]["localizations"][0]["screenshotSets"] = [{"type": "APP_IPHONE_67", "count": 3, "states": ["COMPLETE"]}]
        self.assertEqual(levels(snap, "screenshots-ipad"), ["FAIL"])
        snap = good()
        snap["platforms"]["MAC_OS"]["localizations"][0]["screenshotSets"][0]["states"] = ["COMPLETE", "FAILED"]
        self.assertIn("FAIL", levels(snap, "screenshots"))

    def test_a_missing_platform_an_open_submission_and_unresolved_issues_fail(self):
        snap = good()
        del snap["platforms"]["MAC_OS"]
        self.assertEqual(levels(snap, "version-record"), ["FAIL"])
        snap = good()
        snap["platforms"]["IOS"]["submissions"] = ["UNRESOLVED_ISSUES"]
        self.assertEqual(levels(snap, "open-submission"), ["FAIL"])
        self.assertEqual(levels(snap, "unresolved-issues"), ["FAIL"])

    def test_a_product_missing_metadata_and_a_dead_privacy_link_fail(self):
        snap = good()
        snap["subscription_groups"][0]["subscriptions"][0]["state"] = "MISSING_METADATA"
        snap["urls"]["https://example.com/privacy"] = 0
        self.assertEqual(levels(snap, "product-state"), ["FAIL"])
        self.assertEqual(levels(snap, "privacy-policy-url"), ["FAIL"])

    def test_review_detail(self):
        snap = good()
        snap["platforms"]["IOS"]["review"].update(contact=False, notesLength=4001)
        snap["platforms"]["MAC_OS"]["review"]["notesHoldFile"] = False
        self.assertIn("FAIL", levels(snap, "review-detail"))
        self.assertEqual(levels(snap, "review-notes-file"), ["WARN"])

    def test_house_rules_warn_and_do_not_block(self):
        snap = good()
        loc = snap["platforms"]["IOS"]["localizations"][0]
        loc["whatsNew"] = "Standard answered 15 of 17.\nA dash — here."
        snap["app_infos"][0]["ageUnanswered"] = ["sharedLocation"]
        snap["repo"]["description"] = "something else"
        results = gate.check(snap)
        self.assertEqual([r for r in results if r["level"] == "FAIL"], [])
        warned = {r["check"].split("[")[0] for r in results if r["level"] == "WARN"}
        self.assertEqual(warned, {"percentages", "em-dash", "age-rating-questions", "repo-description"})

    def test_an_already_submitted_version_is_information_not_a_failure(self):
        snap = good()
        for p in snap["platforms"].values():
            p["state"], p["submissions"] = "WAITING_FOR_REVIEW", ["WAITING_FOR_REVIEW"]
        results = gate.check(snap)
        self.assertEqual([r for r in results if r["level"] == "FAIL"], [])
        self.assertEqual(levels(snap, "state"), ["INFO", "INFO"])

    def test_tag_names_and_signature_conversion(self):
        self.assertEqual(gate.tag_for("5.9"), "v5.9.0")
        self.assertEqual(gate.tag_for("5.0.2"), "v5.0.2")
        # DER: SEQUENCE { INTEGER 0x00 ff.. (33 bytes, leading zero), INTEGER 0x01 (1 byte) }
        r, s = b"\x00" + b"\xff" * 32, b"\x01"
        der = bytes([0x30, 2 + len(r) + 2 + len(s), 0x02, len(r)]) + r + bytes([0x02, len(s)]) + s
        raw = gate._raw_signature(der)
        self.assertEqual(raw, b"\xff" * 32 + b"\x00" * 31 + b"\x01")


if __name__ == "__main__":
    unittest.main()
