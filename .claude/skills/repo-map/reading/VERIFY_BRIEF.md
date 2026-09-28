# Brief: try to refute each "this document is wrong" finding

A first reader checked documents against the code and reported claims it believes are wrong. First
readers are sometimes confidently wrong: in this owner's repositories an earlier agent tagged 22 of
31 "verified" code relationships that never existed. Your job is to try to refute each finding.
Keep only what survives.

## Hard rules
- Read-only. Do not edit, create, move or delete anything in the repository; do not build or test.
  The only file you write is your result file.
- Start from the assumption that the finding is wrong, and look for why:
  1. Does the document actually make this claim about the app as it is now? Reread the passage. A
     claim stated as history ("in 2.6", "previously"), as a plan ("will", "planned"), as an example,
     or qualified ("up to", "when available") is not a claim about the current code.
  2. Does the cited line exist and show what the evidence says? Open it.
  3. Is the behavior implemented somewhere else, under another name? Grep the whole repository for
     the feature, not just the one symbol.
  4. Can the code settle it at all? Runtime behavior, Apple's or OpenAI's servers, App Store review
     and device behavior usually cannot be settled from source.
- `confirmed` only when the document states the claim about the current app AND code you have read
  clearly does something different. Cite the line.

## Output
Write one JSON array to your result file, one object per finding, exactly these keys:
{"id": "...", "outcome": "confirmed|refuted|unclear", "reason": "One sentence.",
 "corrected_evidence": "path:line: what the code does (only when the first evidence was imprecise)"}
Then reply with at most four lines: counts per outcome and the most important confirmed findings.
