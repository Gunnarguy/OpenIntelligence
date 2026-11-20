---
name: measure-answers
description: Use before and after any change meant to make OpenIntelligence's answers better or more accurate (retrieval, ranking, the evidence the model is given, prompts, Fact Check, Standard, Deep Think or Maximum), and before claiming an answer change helped, did nothing, or made things worse. Runs the same questions on the build before the change and the build after it and prints the difference, question by question, saying when the difference is inside the variation between two runs of one build. Triggers on "make the answers better", "more accurate", "it's still wrong", "did that help", "is it any better", "quality", "regression", "baseline", and on any edit under Services/RAG that changes what is retrieved or written.
---

# Measure answers

During 5.8, days of answer-quality work could not be shown to have changed anything, because no baseline was
measured before the change (`Docs/ai/RETRO_5.8.md`, gap 6: "we just did all of this work only for this thing to
basically be just as bad"). And two runs of one build give different answers here, so a one-question gain proves
nothing until that variation is known.

## The number to beat

Measured 2026-11-20 on the code of build 509: two runs of the same build in Standard scored 80% (16 of 20) and 90%
(18 of 20). Two questions flipped with no change at all, both "lost in the middle" ones. So on this set, one run
before and one run after cannot show a change of 2 questions or fewer; use `--repeats 2` or more, and do not count
those two questions as evidence. One pair of runs measured this, so the real spread may be wider.

## The order

1. **Baseline first, before the first edit.** `python3 scripts/paired_run.py pair --before HEAD --after HEAD`
   runs the current build twice and says how many of the 20 questions flip between identical builds. That number is
   the noise. Skip this only when a noise run of the same commit already exists in `BenchmarkRuns/`.
2. **Make the change.**
3. **Measure it against the baseline:**

```bash
python3 scripts/paired_run.py pair --before HEAD --after worktree --repeats 2
```

   It stages both builds outside the repository, runs each in the iOS 27 Simulator with Apple's model, one after the
   other, and prints percent right for each ("90% (18 of 20)"), the questions that went wrong to right and right to
   wrong, the net change, and whether it is larger than the noise. Standard takes minutes a run; `--mode deepThink`
   or `--mode maximum` take hours, so run those in the background or overnight (`overnight` skill).
4. **Record it.** `pair` prints the lines for `BenchmarkRuns/LEDGER.md`; add them, with one or two sentences in your
   own words on what the run shows and what it does not. Never delete a run folder.
5. **Tell him the number.** Percentage first, count beside it, and the word "noise" when the change is inside it.
   "No measurable change" is a result; say it plainly.

`python3 scripts/paired_run.py compare <runA> <runB> [--noise <another run of A's build>]` compares run folders that
already exist. `--dry-run` on `pair` prints every command and runs none.

## When the question is "why do two runs differ", not "did my change help"

`python3 scripts/stability_battery.py` (`--dry-run` first) runs the same questions several times under five sampling
settings and says whether the writing's randomness or something before it varies. Plan and decision rules:
`Docs/ai/plans/consistent-answers.md`. It uses Mac time (about 100 minutes in Standard): ask the owner first.

## What this does not settle

- 20 questions over one small document set. His rule 6 asks for every benchmark set: a gain here still needs the
  retrieval benchmark and the golden harness before it is called universal (`Docs/ai/RUNBOOK.md`, "Retrieval
  benchmark" and "Proving a retrieval change changes nothing").
- Right and wrong are a rule's reading (a value or a file name present, a refusal where one is due), not a judgment of
  how good an answer is.
- The Simulator is not his phone: a device answer still gets one real question on device before a row closes
  (`device-pass`).
- Speed: use `measure-speed`.
- Accuracy comes before speed, and Deep Think and Maximum never get shallower to get quicker (`CLAUDE.md`, rule 3).
