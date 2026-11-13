#!/usr/bin/env python3
"""Score `AnswerQualityEvaluationTests` answers by rule, beside the model judge's verdict (2026-11-13).

    python3 scripts/score_answer_eval.py <run.xcresult | report.xcevalresult> [...]

The judge (Apple's on-device model through the Evaluations framework) failed answers that gave the reference word for
word ("Owner-2A ... Q2 review gate", "LITM-END-42") and passed one that gave another token: on 5.8's Deep Think run of
2026-11-13 it agreed with a plain reading on 8 of 20. This scores each answer from the case's own patterns in
`Benchmarks/ResearchFixtures/tiny_research_suite/manifest.json`:

  answer cases (exact values, multi-hop, lost in the middle): every `expected_answer_patterns` regex matches, and for a
      lost-in-the-middle case no other case's token is given;
  retrieval_only cases ("Which document mentions ..."): their reference is the phrase in the question, so the answer
      must name the expected document (its file name or its name with spaces for underscores);
  abstain cases: the answer says in its opening that the documents don't hold it, and states no amount of money or
      term it could have made up.

Prints one line per case (rule, judge) and the totals. The judge's verdict stays as a second column, not the score.
"""

import glob
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
MANIFEST = REPO / "Benchmarks/ResearchFixtures/tiny_research_suite/manifest.json"
DECLINES = re.compile(
    r"(not (contain|include|provide|mention|specif|list|stat|available|found|present|establish|determin)\w*"
    r"|no (information|data|mention|record|detail|figure|value|evidence)"
    r"|absence of|cannot be (found|determined|established)|could ?n.t find|unable to find|isn.t (in|available))",
    re.I,
)


def reports(paths):
    for p in paths:
        p = Path(p)
        if p.suffix == ".xcevalresult":
            yield p, json.loads(p.read_text())
            continue
        out = Path(tempfile.mkdtemp(prefix="evals."))
        subprocess.run(
            ["xcrun", "xcresulttool", "export", "attachments", "--path", str(p), "--output-path", str(out)],
            capture_output=True, check=False)
        for f in sorted(glob.glob(str(out / "*.xcevalresult"))):
            yield p, json.loads(Path(f).read_text())


def case_for(prompt, expected, cases):
    same = [c for c in cases if c["query"] == prompt]
    if len(same) <= 1:
        return same[0] if same else None
    for c in same:
        if any(re.search(pat, expected or "") for pat in c.get("expected_answer_patterns", [])):
            return c
    return same[0]


def rule(case, answer, cases):
    if case.get("expected_behavior") == "abstain":
        # Declines in its opening, and states no amount of money or warranty term it could have made up (an answer
        # that declines and then lists unrelated values from other documents still declined).
        bare = re.sub(r"\[(S\d+|\d+)(,\s*S?\d+)*\]", "", answer)
        made_up = re.search(r"(\$\s?\d|\d[\d,.]*\s*(dollars|usd|years?|months?)\b)", bare, re.I)
        return bool(DECLINES.search(bare[:500])) and not made_up
    if case["category"] == "retrieval_only":
        name = case["expected_source"]["filename"]
        stem = Path(name).stem
        text = answer.lower()
        return name.lower() in text or stem.lower() in text or stem.replace("_", " ").lower() in text
    if not all(re.search(p, answer) for p in case.get("expected_answer_patterns", [])):
        return False
    if case["category"] == "lost_in_middle":
        others = [p for c in cases if c["category"] == "lost_in_middle" and c["id"] != case["id"]
                  for p in c.get("expected_answer_patterns", [])]
        return not any(re.search(p, answer) for p in others)
    return True


def main(paths):
    cases = json.loads(MANIFEST.read_text())["cases"]
    for source, report in reports(paths):
        rows = report.get("results", [])
        print(f"== {source.name}  ({len(rows)} cases)")
        n_rule = n_judge = agree = 0
        for r in rows:
            prompt = json.loads(r["Input"])["input"]["prompt"]
            answer = r["Response"]["value"]
            case = case_for(prompt, r.get("Expected"), cases)
            ok = bool(case) and rule(case, answer, cases)
            judge = r.get("Correct", {}).get("value") == 1
            n_rule += ok
            n_judge += judge
            agree += ok == judge
            banner = "  [Needs Verification]" if "Needs Verification" in answer else ""
            print(f"  {'PASS' if ok else 'fail'} judge={'pass' if judge else 'fail'}  {case['id'] if case else '?':28s}"
                  f" {len(answer):5d} chars{banner}")
        print(f"  rule {n_rule}/{len(rows)}  judge {n_judge}/{len(rows)}  agree {agree}/{len(rows)}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1:])
