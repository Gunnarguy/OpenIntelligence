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

**Since 2026-11-23 the test itself is corrected** (item 8 of `Docs/ai/plans/consistent-answers.md`): the scoring rule
counts a refusal that goes on to list other values as right and a value named after "not specified" as wrong, the
exact-value fixtures label their values, and each ask starts with conversation memory empty. Under it, on 5.8's app
code, each question asked twice in one library: Standard 20 and 18 of 20, Deep Think 18 and 17, Maximum 20 and 20.
Compare a new run with runs made under the same rules: an old folder is re-scored by `scripts/score_answer_eval.py`,
but its memory and fixtures were the old ones.

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

## Asking each question twice in one library (the default since 2026-11-23)

`scripts/ask_twice.py run --mode <mode> --sampling shipped --repeat 2 --tag <name>` imports the fixtures once and asks
every question twice in that one library, so it measures accuracy and whether an answer repeats in one run. `--tag`
names runs made under other rules so old folders do not count as done; `report --tag <name>` prints the table. For
several runs unattended, in a Terminal tab (it survives the session):

```bash
bash scripts/ask_twice_queue.sh <ref> <tag> "TEST_RUNNER_OI_EVAL_MEMORY=keep" standard:shipped:2 deepThink:shipped:2
```

Knobs the answer test reads (each with `TEST_RUNNER_` in front when set for a run): `OI_EVAL_MEMORY=keep` (asks the
old way, each question after the earlier answers; how a memory change is measured), `OI_EVAL_STEP_TEMPERATURE` (only
the 0.5 a Deep Think or Maximum step takes when it names none), `OI_EVAL_TEMPERATURE`, `OI_EVAL_SAMPLING`,
`OI_EVAL_SEED`, `OI_EVAL_ADAPTIVE`. `ask_twice.py run --fixtures-from a67ae343^` measures on 5.8's unlabelled tables,
where a value's row does not say what it is (how a change to value checks is measured).

Durations measured 2026-11-23, two asks a question: Standard about 15 minutes, Deep Think and Maximum about 50. A run
takes about 6 GiB of disk at its peak; under 10 GiB free the queue waits.

Unit tests before any of this, on a copy outside iCloud and under the build lock:

```bash
bash scripts/unit_on_copy.sh <label> EarlierTurnsAndNamedValuesTests AnswerHeadlineTests
```

Never edit a shell script while it runs: bash reads it as it goes, and a run of 2026-11-23 ended with exit 127.

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
