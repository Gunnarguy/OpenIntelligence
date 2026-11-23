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
  abstain cases: the answer says, in its first 600 characters, that the documents don't hold it, and states no
      number of its own (one the question does not contain) before the end of that sentence.

Two corrections of 2026-11-23 (item 8 of the 5.9 proposal in `Docs/ai/plans/consistent-answers.md`), checked by
reading every answer whose score they change across the 1,360 answers of the runs to that date:
  - a refusal that goes on to list other documents' values, or says it as "cannot be fulfilled", "remains
    undetermined" or "no document provides", is a refusal (27 of Deep Think's, 10 of Maximum's were failed);
  - an answer whose first sentence says the documents do not hold the value, and then names the expected value as
    something else ("not specified in the excerpts ... 45 C, but these pertain to other metrics"), did not answer
    (10 of Standard's were passed).
The text is read without the verification banner, headings, emphasis, citation marks or the leaked answer-first
instruction ("The exact value, name or finding, written as the source writes it, with its label:").

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
    r"(not (fully |explicitly |directly )?(contain|include|provide|mention|specif|list|stat|available|found|present"
    r"|establish|determin|disclos|given|detail|cover|address)\w*"
    r"|no (information|data|mention|record|detail|figure|value|evidence)"
    r"|\b(no|nothing)\b[^.]{0,80}\b(is|are) (provided|mentioned|present|given|available|stated|listed|specified|included|found)"
    r"|\bno (document|source|passage|excerpt)s? (provides|contains|mentions|states|lists|includes|gives)"
    r"|\b(undetermined|omitted|unavailable)\b"
    r"|absence of|cannot be (found|determined|established|fulfilled|answered|provided|identified)"
    r"|could ?n.t find|unable to (find|determine|locate)|isn.t (in|available|stated|given|listed))",
    re.I,
)
BANNER = re.compile(r"^\W*\[?needs verification\]?.*?evidence:\s*", re.I | re.S)
LEAD = re.compile(r"^the exact value, name or finding, written as the source writes it, with its label(, is)?\s*:\s*", re.I)
CITES = re.compile(r"\[(S?\d+)(,\s*S?\d+)*\]")
SENTENCE_END = re.compile(r"(?<!\d)[.!?](\s|$)")


def cleaned(answer):
    """The answer as a reader takes it in: no verification banner, headings, emphasis, citation marks or leaked
    answer-first instruction (13 of 360 Deep Think answers began with it, 2026-11-22)."""
    text = answer.replace("\u26a0\ufe0f", "")
    if "needs verification" in text[:80].lower():
        text = BANNER.sub("", text.strip())
    lines = [line for line in text.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    text = re.sub(r"\*+|`|__", "", " ".join(lines))
    return LEAD.sub("", CITES.sub("", text).strip())


def sentence_end(text, at):
    m = SENTENCE_END.search(text, at)
    return m.start() + 1 if m else len(text)


def opening(answer):
    """The answer's first sentence, cleaned."""
    text = cleaned(answer)
    return text[: sentence_end(text, 0)]


def declined_part(answer):
    """The cleaned answer up to the end of the sentence that first says the documents do not hold it, when that is
    in its first 600 characters; None when it never says so there."""
    text = cleaned(answer)
    m = DECLINES.search(text[:600])
    return text[: sentence_end(text, m.end())] if m else None


def numbers(text):
    return set(re.findall(r"\d[\d,.]*", text))


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
    first = opening(answer)
    if case.get("expected_behavior") == "abstain":
        # Says the documents don't hold it, and offers no number of its own before saying so: an answer that declines
        # and then lists other documents' values still declined; one that gives "45 C" first did not.
        part = declined_part(answer)
        return part is not None and not (numbers(part) - numbers(case["query"]))
    if case["category"] == "retrieval_only":
        name = case["expected_source"]["filename"]
        stem = Path(name).stem
        text = answer.lower()
        return name.lower() in text or stem.lower() in text or stem.replace("_", " ").lower() in text
    if not all(re.search(p, answer) for p in case.get("expected_answer_patterns", [])):
        return False
    # A value named only after the answer said the documents do not hold it is not an answer to the question.
    if DECLINES.search(first) and not any(re.search(p, first) for p in case.get("expected_answer_patterns", [])):
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
