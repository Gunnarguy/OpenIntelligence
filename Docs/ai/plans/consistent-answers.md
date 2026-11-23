# Plan: the same documents and the same question give the same, right answer

Written 2026-11-20 at the owner's request ("any kind of variation in what it actually retrieves and then generates,
if that is inaccurate then it defeats the whole purpose of the app"). Nothing in the app changes until the
measurements below are in; app changes then go into 5.9 with his `PROCEED: IMPLEMENT`.

## What was measured, and what it means

Two runs of one build in Standard, 20 questions, 2026-11-20 (`BenchmarkRuns/LEDGER.md`, "noise"):

| | First run | Second run |
|---|---|---|
| Right, by the scorer's rule | 80% (16 of 20) | 90% (18 of 20) |
| Questions that changed between right and wrong | 2 of 20 | |
| Answers word for word the same (first 300 characters) | 6% (1 of 18) | |

So an answer is almost never worded the same twice, and on 2 of 20 questions the wording change crossed from wrong to
right. `[measured]`

## How the three modes differ today

Declared settings are read from `OpenIntelligence/Core/Models/RAGQualityMode.swift`, and who reads each one was found
by searching the app for every use on 2026-11-20 `[code_verified]`. What each pipeline does at run time is from
`Docs/HOW_IT_WORKS.md` section 07 and `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md` section 20, whose line citations
were not re-read one by one today `[documented, dated 2026-10-20 to 2026-11-10]`.

Two marks in the table:

- **†** the mode declares this value, and the only code that reads the setting is Standard's pipeline
  (`RAGService+QueryPipeline.swift:255-275`). For Deep Think and Maximum the value is on paper only.
- **‡** nothing in the app reads this setting, in any mode.

| | Standard | Deep Think | Maximum |
|---|---|---|---|
| **How it runs** | | | |
| Runs in | `RAGService` (`queryInternal`) | `AgenticOrchestrator` | `AgenticOrchestrator`, its own loop |
| Shape | One search, one prompt, one answer | Several searches, then a chain of reading sessions | Deep Think's searches, a wider gather, then a long loop |
| Who decides to search again | Code rules (weak first search, keyword retry under 0.45, "list all") | Code, by the grade of the merged results | Code, the same way |
| Tools handed to the model | None | None | None |
| **Searching** | | | |
| Rewordings of the question | None | Up to 5 | Up to 5, plus 3 fixed ones in the gather |
| Model rewrites the question (declared) | Off | On † | On † |
| HyDE, a made-up answer used to search (declared) | Off | On † | On † |
| HyDE in the mode's own search routine (documented) | Off | Not used | Not used |
| Query expansion (declared) | Off | On, up to 8 † | On, up to 12 † |
| Passages asked for (declared) | 30 | 35, read only as the size of the first precision lookup (`max(24, 35)`) | 50, the same way |
| Passages asked for (documented) | sized from the library | 15 a rewording, merged to the best 20 | the same, plus a 50-passage gather and 3 searches of 20 |
| Lowest similarity kept (declared; read by `RetrievalPolicyService`) | 0.28 | 0.25 | 0.20 |
| Lowest similarity kept (documented) | adaptive floor | 0.05 a rewording | as Deep Think |
| Search rounds allowed (declared) | 2 ‡ | 5 ‡ | 20 ‡ |
| Reranker | On | On | On |
| Variety among passages, MMR (declared); the library's own value is what runs | 0.60 ‡ | 0.55 ‡ | 0.50 ‡ |
| Neighbouring passages added (read by both search routines) | 2 | 3 | 5 |
| Passages shortened to their relevant sentences (declared) | Off | On † | Off |
| Weight for tables and specifications (declared; read once and thrown away, "reserved") | 1.2 ‡ | 1.3 ‡ | 1.5 ‡ |
| **Reading and writing** | | | |
| How the model reads | Everything in one prompt | About 4 passages a session on a 4K window, up to 7 on 8K | 3 passages a session |
| Reading sessions | Usually 1 | Up to 8 | Up to 50, fewer for a small pile |
| Notes carried between sessions | None | Each session's notes, shortened | A fact bank and a running answer every 5 sessions |
| Final answer written from | The packed passages | The sessions' notes and the passages they cited | The fact bank and the latest notes |
| Extra model calls | Citation retry, one repair, continuations, the source-only check | Title routing, synthesis, research rounds, a Self-RAG check | Synthesis, a refinement, one Self-RAG check |
| May use Private Cloud Compute | The answer, by the route plan | The synthesis only | The synthesis and refinement |
| **Randomness** | | | |
| Temperature, as installed | The saved setting, at most 0.4 (the mode's declared value); 0.2 when the search looked weak or the library is High Precision; retries at 0.2 and 0.15 | 0.5 for every step: 14 of the 15 places that ask the model to write name no temperature and take the default, and the one that does is in Maximum's loop; the mode's declared 0.4 † | In its loop 0.7 for sessions 1 to 3, 0.5 to session 8, 0.3 after; 0.5 for its other steps; the mode's declared 0.3 † |
| Temperature with the Settings switch "adaptive profiles" on (off by default) | By the kind of question: 0.1 lookup, 0.3 procedure, 0.35 comparison, 0.4 summary, then the same caps as above | The same per-kind value, for every step that does not name its own | The same; its loop keeps 0.7, 0.5, 0.3 |
| Sampling | The saved strategy (top 40), no fixed seed | The same | The same |
| **Checking** | | | |
| Verification gates | Can make it abstain or retry | Shown as a label, do not make it abstain | The same as Deep Think |
| Confidence asked for (declared; read by `ConfidencePolicyService`) | 0.50 | 0.60 | 0.80 |
| "Does the answer answer the question" check | Yes, rewrites once | Yes | Yes |
| Fact Check on each claim | Yes | Yes | Yes |
| **Limits** | | | |
| Conversation turns remembered (declared) | 5 | 10 † | 20 † |
| When it stops | After its one answer | From the fifth session, when confident, covered and nothing new | When its findings settle, after at least 5 sessions |
| Free plan | Unlimited | Unlimited | 3 times a day |

`[evidence_level: code_verified for the declared rows, their readers and the temperatures (RAGQualityMode.swift:64-310, RAGService+QueryPipeline.swift:255-275, RAGService+QueryAnswer.swift:598-608, RAGService+Agentic.swift:159-182 and its 15 call sites, AgenticOrchestrator+Maximum.swift:909-925, RAGService+AgenticQuery.swift:307 and 392-406, RAGService+QueryPreparation.swift:803-815, FoundationModelDynamicProfileRegistry.swift:56-110); documented for run-time behaviour; no trace of a Deep Think run's step temperatures was read, confidence: medium]`

Four things in that table are defects or possible defects. Each has a roadmap row (next section).

1. **The careful modes write hotter than the quick one.** As installed, Standard writes at 0.4 or lower, a Deep
   Think step at 0.5 and Maximum's first three sessions at 0.7. A setting that fits the temperature to the question
   (0.1 for a lookup) exists, reaches all three modes since 5.3, and is off by default because its effect was "unmeasured,
   and currently unmeasurable" (the code's own comment, `RAGService+QueryPreparation.swift:786-789`). The battery below
   is what measures it. The app logs each agentic step's temperature (`[Agentic] Step temperature ...`), so one Deep
   Think run's log confirms the 0.5.
2. **Most of what a mode declares is read only by Standard.** Deep Think and Maximum declare HyDE, query rewriting,
   query expansion, their own temperature and their conversation length, and no code on their path reads those
   settings. Seven settings are read by nothing at all: search rounds (`maxRetrievalIterations`,
   `iterativeRetrievalConfig`), the mode's MMR value, the table weight (read once and thrown away), `featureToggles`
   and the two summaries flags. The table in `RAGQualityMode.swift` therefore describes a design, not what runs.
3. **Two search routines.** Standard's `queryInternal` and the orchestrator's `executeFullRetrievalPipeline`
   (`RAGService+ToolHandler.swift:92`) are separate, so a search fix in one does not reach the other.
4. **The 20-question test cannot show a small gain.** Two questions of noise is 10 points.

## Roadmap rows (Notion, all Future Backlog)

| Row | What closes it |
|---|---|
| [Two runs of one build return different evidence for the same question](https://app.notion.com/p/3bf49a74d54f81189046d2f007f68272) (open since 2026-08-16, updated) | Two greedy runs of one build give the same answer to every question, with and without Swift's hashing held fixed |
| [Standard, Deep Think and Maximum each choose the answer's temperature by a different rule, and the careful modes write hotter](https://app.notion.com/p/41e49a74d54f81babdece4a65cd789c9) (new) | One rule in one place, chosen from the battery's numbers, and a before and after paired run that shows no loss |
| [Adaptive profiles cannot reach Deep Think or Maximum](https://app.notion.com/p/3d849a74d54f8195a763f0759e442d32) (open since 2026-09-11; reaches them since 5.3, never observed; updated) | A Deep Think run's log shows the per-kind temperature on its steps |
| [Deep Think and Maximum carry dead paths and limits that never apply](https://app.notion.com/p/40049a74d54f81ad96e4d16a98c9a80d) (open since 2026-10-20, updated with every setting's readers) | Each setting is wired in or deleted, with the golden harnesses unchanged |
| [Standard and Deep Think search through two separate routines, so a search fix reaches only one of them](https://app.notion.com/p/41e49a74d54f819e98cef321c6537fd5) (new) | A decision, with a golden record of both, after the rows above |
| [The answer test is too small to tell a real gain from run-to-run noise](https://app.notion.com/p/41e49a74d54f81db96e9c6cd0c7691da) (new) | A question set and repeat count whose noise is measured and written beside every result |

## The questions, and the command that answers them

```bash
python3 scripts/stability_battery.py
```

About 10 runs of about 10 minutes each in the iOS 27 Simulator, one after the other, with its own scratch copy and
simulator; a stopped run picks up where it was. `--dry-run` prints the runs; `--report` prints the table from the runs
that exist. Nothing in the app is changed: the answer test sets the benchmark-only sampling switches the app already
reads, and its adaptive-profiles setting, for the run and removes them after.

| # | Question | Setting | How the answer reads |
|---|---|---|---|
| Q1 | How far apart do identical runs land today? | `shipped`, 3 runs (2 exist) | The spread of the scores and the questions that flip. This is the noise every later comparison has to beat. |
| Q2 | Is the writing's randomness the whole cause? | `greedy`, 2 runs | No randomness at all. If every answer repeats exactly, each run gave the model the same passages in the same order and the writing is the cause. If answers still differ, something before the writing varies: run `--arms hashed` (greedy with Swift's hashing held fixed), then Q6. |
| Q3 | Does removing the randomness cost right answers? | the same `greedy` runs | Their mean against `shipped`, read against the spread. |
| Q4 | Does a fixed seed repeat across launches? | `seeded`, 2 runs | In August 2026 it did not (the first roadmap row). If it still does not, a seed is not a route to the same answer twice. |
| Q5 | Is a lower temperature, or the app's per-kind switch, better? | `cool` (0.1), 2 runs; `adaptive`, 3 runs | Each mean and its flips against `shipped`. `adaptive` is the app's existing setting, so a good result there is a one-line default change. |
| Q6 | Is the search step itself repeatable across launches? | `DeepThinkRetrievalGoldenTests` and `StandardPipelineGoldenTests`, recorded twice | `python3 scripts/golden_retrieval.py compare`: exit 0 means every search matched. Only needed if Q2 says something before the writing varies. About 70 minutes. |
| Q7 | The same for Deep Think | `--mode deepThink --arms shipped greedy adaptive` | Hours a run; overnight (`overnight` skill). |

What was already known, from the first roadmap row: in August two runs of one build with a fixed seed gave identical
answers on 7 of 25 questions, the prompt differed on 15 of 25 while every search metric matched, and three later
commits removed known causes of that (a reranker race, an undefined sort, eight score sorts with no tie-break). Whether
two runs agree now has not been measured since. Q2 is that measurement.

## What gets built, by what the numbers say

Decided before the runs, so the result cannot bend the rule.

| If | Then (5.9, with his go) | Proven by |
|---|---|---|
| Q2: greedy runs repeat exactly, and `adaptive`, `cool` or `greedy` scores no lower than shipped beyond the spread | One temperature rule for all three modes, in one place. First choice the per-kind rule the app already has, on by default; lookups and exact values at the most repeatable setting that lost nothing | `paired_run.py pair --repeats 2` before and after, on every benchmark set; the battery's `shipped` row shrinks |
| Every lower setting scores lower than shipped beyond the spread | Keep 0.4 for writing in Standard, bring Deep Think and Maximum down to it, and make only exact-value answers repeatable (the source-locked lookup already takes the value from the passage) | The same |
| Q2: greedy runs still differ | Find and remove the variation before the writing (Q6, `hashed`) before any temperature change | Two greedy runs agree on every answer |
| Any | The settings a pipeline does not read are removed or wired in, one mode at a time | The golden harnesses record identical results before and after a removal; a paired run for anything wired in |
| After the above | Decide whether Standard and Deep Think share one search routine | A golden record of both before the move |

Not in this plan: a new model, a new question set, or any speed work. The 20-question set is small (2 questions of
noise is 10 points), so any claim of a gain needs repeats, and the retrieval benchmark and the device stay the final
word (`measure-answers` and `device-pass` skills).

## Findings while the queue runs

### 2026-11-21 02:50, after 3 as-shipped and 2 greedy runs in Standard

| Setting | Runs | Right | Answers word for word the same |
|---|---|---|---|
| As shipped | 3 | 80%, 90%, 90% (16, 18, 18 of 20) | 6% (1 of 18) |
| Greedy (no randomness in the writing) | 2 | 75%, 85% (15, 17 of 20) | 6% (1 of 18) |

`[measured, BenchmarkRuns/2026-11-20-1249…noise-before, …1306…noise-after, 2026-11-21-0211…shipped-3, …0221…greedy-1, …0229…greedy-2]`

**The greedy runs differ as much as the sampled ones, so the writing's randomness is not the whole cause.** Q2's rule
applies: no temperature change is proposed until what varies before the writing is found. Read from the two greedy
runs' logs (`standard-app.log`), for the question "How many gallons of gasoline can the vehicle hold?":

1. **The two runs did not ask the same library.** Each run imports the fixtures again, and the import writes a
   model-made summary for each document. Their lengths differed (6 summaries, 649 words in one greedy run and 610 in
   the other, 673 in the as-shipped run), and the library's word count seen by search differed with them (`totalWords`
   1527 against 1495 for this question). So the battery measures "import, then ask", which is what two people with
   the same file, or one person who imports it again, would meet. It does not yet measure "ask the same library
   twice", which is the commoner case. `[measured from the logs; whether the summary call obeys the greedy switch is
   not checked]`
2. **With the same context the model still wrote differently.** Both runs assembled 1 passage of 244 characters and
   sent 1,018 input tokens, and one wrote 79 output tokens ("14.3 US gal ⏎ ⏎ Sources: [S1]", gates passed, confidence
   0.97) and the other 99 (the citation missing, Gate B failed, the source-only check ran). Either the two prompts
   differed inside the same token count, or greedy structured generation does not repeat across launches of the app.
   `[measured; cause not established]`
3. One greedy run logged the model as "Unavailable" for one call at its start (the Simulator's first minute).

**What this adds to the plan** (after the queue, test code and tooling only):

- A run that imports once and asks every question twice in the same process, as shipped and greedy. That separates
  "the library changed" from "the answer changed", and is the measurement that matches a user asking twice.
- A dump of the exact prompt for one question in two launches, to settle item 2.
- `--arms hashed` stays worth its 20 minutes; the golden harnesses compare searches on one library and do not cover
  item 1.

### 2026-11-21 07:10, Standard finished (10 runs) and Deep Think as shipped and greedy (5 runs)

| Mode | Setting | Runs | Right, each run | Questions that flipped | Answers word for word the same |
|---|---|---|---|---|---|
| Standard | As shipped | 3 | 80%, 90%, 90% (16, 18, 18 of 20) | 2 | 6% (1 of 18) |
| Standard | Greedy | 2 | 75%, 85% (15, 17) | 2 | 6% (1 of 18) |
| Standard | Fixed seed | 2 | 95%, 90% (19, 18) | 1 | 17% (3 of 18) |
| Standard | Temperature 0.1 | 2 | 75%, 85% (15, 17) | 4 | 28% (5 of 18) |
| Standard | Adaptive profiles on | 3 | 90%, 90%, 85% (18, 18, 17) | 3 | 0% (0 of 18) |
| Deep Think | As shipped | 3 | 80%, 65%, 85% (16, 13, 17) | 5 | 6% (1 of 18) |
| Deep Think | Greedy | 2 | 95%, 95% (19, 19) | 0 | 17% (3 of 18) |

`[measured, one build (ce7adeed), iOS 27.0 Simulator, the run folders named stab-standard-* and stab-deepThink-* of 2026-11-21 plus the two noise runs of 2026-11-20; few runs per setting]`

- **Standard: no setting is distinguishable from as shipped, and none makes answers repeat.** Every run landed between
  15 and 19 of 20 with up to 2 questions between two runs of one setting.
- **Deep Think as shipped swings more than Standard**: 13 to 17 right across three runs, 5 questions changing sides.
  Its runs took 26, 40 and 29 minutes against Standard's 7 to 10.
- **Deep Think with no randomness scored 19 and 19**, above all three as-shipped runs, with no question changing
  sides. By the rule in the battery (a gap counts only beyond the largest spread seen, here 4) a gap of 3.7 is not
  yet a result, and two runs are two runs. It is the first number that points at Deep Think's 0.5 as costing right
  answers, and the Deep Think adaptive runs later in this queue test the same idea with the app's own setting.
  The answers still differed in wording (3 of 18 the same), as in Standard.

### 2026-11-21 09:50, Maximum as shipped and greedy (5 runs), and the step temperatures read from the logs

| Mode | Setting | Runs | Right, each run | Questions that flipped | Answers word for word the same | Minutes a run |
|---|---|---|---|---|---|---|
| Maximum | As shipped | 3 | 95%, 85%, 90% (19, 17, 18 of 20) | 2 | 11% (2 of 18) | 28, 38, 31 |
| Maximum | Greedy | 2 | 90%, 95% (18, 19) | 3 | 17% (3 of 18) | 26, 39 |

Maximum as shipped is steadier and higher than Deep Think as shipped (16, 13, 17) on these 20 questions, and greedy
does not move it.

**The temperatures in the table above are now observed, with one correction.** Counted from the line
`[Agentic] Step temperature X from ...` in one as-shipped run of each mode (`deepThink-app.log`, `maximum-app.log`):

| Run | Steps at each temperature |
|---|---|
| Deep Think, as shipped | 85 at 0.5 from the default, 18 at 0.3 named by the step |
| Maximum, as shipped | 33 at 0.7 and 26 at 0.5 named by the step, 30 at 0.5 from the default; none at 0.3 |
| Deep Think, adaptive profiles on (first 2 questions) | 18 at 0.1 from the adaptive profile, 0 from the default |

So Deep Think is 0.5 on 83% of its steps (85 of 103), not on every step: one kind of step names 0.3, which the search
for call sites on 2026-11-20 missed. Maximum never reached its 0.3 sessions on these questions. And the per-kind
setting does reach Deep Think's steps when the switch is on, which is what the row "Adaptive profiles cannot reach
Deep Think or Maximum" has waited to see since September. `[measured from the run logs]`

### 2026-11-21 12:30, the queue is done: 26 runs, none failed

| Mode | Setting | Runs | Right of 20, each run | Mean | Questions that flipped | Answers word for word the same | Minutes a run |
|---|---|---|---|---|---|---|---|
| Standard | As shipped | 3 | 16, 18, 18 | 17.3 | 2 | 6% (1 of 18) | 7 to 10 |
| Standard | Greedy | 2 | 15, 17 | 16.0 | 2 | 6% (1 of 18) | 7 |
| Standard | Fixed seed | 2 | 19, 18 | 18.5 | 1 | 17% (3 of 18) | 7 |
| Standard | Temperature 0.1 | 2 | 15, 17 | 16.0 | 4 | 28% (5 of 18) | 7, 13 |
| Standard | Adaptive on | 3 | 18, 18, 17 | 17.7 | 3 | 0% (0 of 18) | 6 to 10 |
| Deep Think | As shipped | 3 | 16, 13, 17 | 15.3 | 5 | 6% (1 of 18) | 26, 40, 29 |
| Deep Think | Greedy | 2 | 19, 19 | 19.0 | 0 | 17% (3 of 18) | 31, 36 |
| Deep Think | Adaptive on | 3 | 16, 19, 16 | 17.0 | 5 | 6% (1 of 18) | 26, 27, 23 |
| Maximum | As shipped | 3 | 19, 17, 18 | 18.0 | 2 | 11% (2 of 18) | 28, 38, 31 |
| Maximum | Greedy | 2 | 18, 19 | 18.5 | 3 | 17% (3 of 18) | 25, 37 |
| Maximum | Adaptive on | 3 | 18, 19, 19 | 18.7 | 3 | 11% (2 of 18) | 20, 26, 27 |

`[measured; BenchmarkRuns/LEDGER.md, the three "Stability battery" entries of 2026-11-21]`

**What the rules written before the runs lead to.**

- The rule that applies is the third row of "What gets built": greedy runs still differ, so **no temperature change is
  proposed yet**. What varies before the writing comes first. One cause is found (the import's model-made summaries
  make each run's library differ) and one is open (the same context drawing different words under greedy).
- Standard: nothing to change on this evidence. No setting is distinguishable from as shipped.
- Deep Think is the one mode whose numbers ask for a change: lowest as shipped, widest swing, and 19 and 19 with the
  randomness off. It needs more runs before it counts (the gap is 3.7 against a spread of 4).
- Maximum: steady and highest as shipped; nothing to change on this evidence.
- The merge of the two search routines gets no support from these numbers either way. It stays last, and optional.

**Next measurements, all test code and tooling, none run yet:**

1. Import once, ask every question twice in the same process, as shipped and greedy, in all three modes. This is
   "the same library, asked twice", the case a user actually meets, and it removes the import from the comparison.
2. Dump the exact prompt for one question in two launches (settles whether greedy itself repeats).
3. Deep Think, more runs: as shipped against greedy on one imported library, enough to clear the spread.
4. Whether the import's summaries can be made repeatable (greedy at import, or kept from the first import) is the
   first candidate app change, and needs a `## 5.9` heading and the owner's `PROCEED: IMPLEMENT`.


## Ask twice: one imported library, each question asked several times (2026-11-22)

`scripts/ask_twice.py` (commit ba1dcd23): the answer test imports the fixtures once and asks each of the 20 questions
several times in the same process. iOS 27.0 Simulator, 5.8's app code, the app's own model service.

| Mode | Sampling | Asks | Right of 20, each ask | Same words every ask | Questions that changed between right and wrong |
|---|---|---|---|---|---|
| Standard | As shipped | 3 | 16, 16, 16 | 50% (10 of 20) | 0 |
| Standard | Greedy | 3 | 16, 17, 18 | 65% (13 of 20) | 2 (exact_temperature_limit, lost_in_middle_middle) |
| Deep Think | As shipped | 5 | 15, 16, 15, 14, 16 | 5% (1 of 20) | 6 |
| Deep Think | Greedy | 5 | 18, 17, 16, 16, 16 | 25% (5 of 20) | 4 (retrieval_policy_alpha, retrieval_trial_beta, lost_in_middle_end, missing_confidential_price) |
| Maximum | As shipped | 2 | 18, 17 | 25% (5 of 20) | 3 (retrieval_policy_alpha, lost_in_middle_middle, missing_unreleased_battery) |
| Maximum | Greedy | 2 | 18, 18 | 55% (11 of 20) | 0 |

`[measured; folders 2026-11-22-0231-answer-modes-twice-standard-shipped, 2026-11-22-0251-answer-modes-twice-standard-greedy, 2026-11-22-0320-answer-modes-twice-deepThink-shipped, 2026-11-22-1222-answer-modes-twice-deepThink-greedy, 2026-11-23-0021-answer-modes-twice-maximum-shipped, 2026-11-23-0654-answer-modes-twice-maximum-greedy]`

The two Maximum rows were made on 2026-11-23 (00:21 and 06:54) from the same commit, after the disk had stopped the
queue on 2026-11-22; scored by the rule of that date. Re-scored by the corrected rule of item 8 below, every row of
this table is in "Item 8 done" further down.

What the first three runs say, against the 2026-11-21 runs that imported again each time:

- **Standard is steady when nothing is imported in between.** As shipped it scored 16 on all three asks, no question
  changed sides, and half its answers were word for word the same; across separate imports the same setting gave
  16, 18, 18 with 2 questions changing sides and 1 of 18 answers the same. So most of Standard's variation came with
  the import, as the summaries finding suggested.
- **Greedy does not make one sitting repeat.** With no randomness in the writing and the same library, 7 of 20 answers
  still changed wording and 2 questions changed sides. Something other than sampling varies inside one process: the
  search, the prompt, or the model. The prompt dump for one question in two asks is still to do.
- **Deep Think varies by itself.** On one library, as shipped, 6 questions changed sides across five asks and 1 of 20
  answers kept its wording. Its instability does not need a new import.

The first attempt at the Deep Think greedy run (folder `2026-11-22-0536-answer-modes-twice-deepThink-greedy`) was cut
short at 12 of 20 questions when the session that started the queue restarted at about 06:45; it is not counted, and
the run was started again at 12:22 from a Terminal tab.

### Deep Think on one library, as shipped against greedy (2026-11-22 14:25)

| Deep Think, 5 asks of each question | Right of 20, each ask | Mean | Same words every ask | Questions that changed sides |
|---|---|---|---|---|
| As shipped (0.5 on most steps) | 15, 16, 15, 14, 16 | 15.2 | 5% (1 of 20) | 6 |
| Greedy | 18, 17, 16, 16, 16 | 16.6 | 25% (5 of 20) | 4 |

Greedy is 1.4 questions higher on average, and every greedy ask scored at least as high as the best as-shipped ask
(16). Together with the runs that imported again (19, 19 against 16, 13, 17), all 7 greedy Deep Think runs or asks so
far scored 16 or more, and 7 of the 8 as-shipped ones scored 16 or less. It is still one question set. Greedy did not
make Deep Think repeat: 15 of 20 answers changed wording at least once, and its score fell from 18 to 16 over the five
asks, which a later ask seeing the earlier ones (conversation memory) could explain and has not been checked.
`[measured; the conversation-memory reading is a guess]`

### Why the import differs each time: one call with no sampling options

`DocumentSummaryService.generateSummaryWithFoundationModels` (`DocumentSummaryService.swift:331-345`) writes each
document's summary with `session.respond(to: prompt)` and no `GenerationOptions`, on a session of its own. So it uses
the model's default sampling, it does not pass through the app's model service, and the benchmark's greedy switch never
reached it, which is why the summaries differed even in the greedy runs. The older path below it sets temperature 0.3
(`:292-293`) and is used only when the first is unavailable. `[code_verified 2026-11-22]`

## Which questions each mode gets wrong (2026-11-22, from every run so far)

Counted from the 26 stability runs, the two noise runs and the four complete ask-twice runs: 44 tries of each question
(Standard 18, Deep Think 18, Maximum 8), all sampling settings together, right and wrong by the scorer's rule.

| Question | All tries | Standard | Deep Think | Maximum |
|---|---|---|---|---|
| lost_in_middle_middle | 48% (21 of 44) | 10 of 18 | 7 of 18 | 4 of 8 |
| exact_capex | 59% (26 of 44) | 0 of 18 | 18 of 18 | 8 of 8 |
| lost_in_middle_end | 64% (28 of 44) | 9 of 18 | 11 of 18 | 8 of 8 |
| missing_unreleased_battery | 68% (30 of 44) | 13 of 18 | 10 of 18 | 7 of 8 |
| exact_temperature_limit | 70% (31 of 44) | 6 of 18 | 17 of 18 | 8 of 8 |
| missing_confidential_price | 70% (31 of 44) | 18 of 18 | 7 of 18 | 6 of 8 |
| retrieval_covid_gamma | 77% (34 of 44) | 18 of 18 | 9 of 18 | 7 of 8 |
| retrieval_nfcorpus_epsilon | 77% (34 of 44) | 16 of 18 | 10 of 18 | 8 of 8 |
| retrieval_trial_beta | 77% (34 of 44) | 18 of 18 | 9 of 18 | 7 of 8 |
| exact_payload | 93% (41 of 44) | 18 of 18 | 18 of 18 | 5 of 8 |
| the other 10 questions | 98% to 100% | | | |

The modes do not miss at random: each has its own questions. Standard never got `exact_capex` and got
`exact_temperature_limit` a third of the time, both of which Deep Think and Maximum answer. Deep Think named the right
document only about half the time on three "which document" questions that Standard gets, and failed the rule on
`missing_confidential_price` (a question the documents cannot answer) 11 times in 18. A fact in the middle of a long
document is found about half the time in every mode. `[measured by rule; the wrong answers have not been read, and the
rule is known to fail a right refusal that goes on to list a dollar amount, which may be part of Deep Think's
missing_confidential_price figure]`

This is the list to work from: read the wrong answers for these nine questions, find the layer that caused each, and fix
that layer for every document (the owner's rule 6), measuring on every benchmark set.

## What the wrong answers show (2026-11-22)

Read from the answers and app logs of every run so far (840 answers: 360 Deep Think, 160 Maximum, 320 Standard), by
three read-only investigations, each finding checked by the main session against the code or the log line named.

### 1. Earlier answers override the document: conversation memory, and a checker that trusts it

The app keeps a conversation memory per library and puts the last few turns in front of every question. Nothing about a
scoped ask ("Ask About a Document", a Siri or Shortcuts ask on one document) limits it: scope narrows the search, not the
memory. The memory goes to the model and to the "does it answer the question" checker, and that checker is given no
passages, so it treats an earlier answer as the truth.

- Injection: `RAGService+QueryAnswer.swift:693-707`, gated only by the `enableConversationMemory` setting (on by
  default). `RAGQualityMode.usesConversationMemory` is true for every mode. `[code_verified]`
- The checker: `RAGService+AnswerResponsiveness.swift:55-69` passes the earlier turns along "for reference only"; the
  judge sees the question and the answer, never the passages. `[code_verified]`
- Seen happening: in `2026-11-22-0231-answer-modes-twice-standard-shipped/standard-app.log` the model answered the
  middle document's question correctly with LITM-MIDDLE-42, the checker replied "missing: The answer incorrectly states
  the token is LITM-MIDDLE-42 instead of LITM-BEGINNING-42" (line 12500), and the rewrite replaced the right answer with
  the wrong one (line 12546). The passage the model was given held only the right token, intact (1,828 chars, line
  12717). `[measured]`
- Every one of the 34 wrong middle and end answers across all runs names another document's token (in Standard runs 15
  of 32 asks, in Deep Think runs 15 of 36, in Maximum runs 4 of 16). A scoped ask always runs Standard's path
  (`RAGAppIntents.swift:238`), so all of these are Standard-path answers whatever the run's mode; a sweep of all 940
  asks by Antigravity (Gemini 4 Hydrogen, counts checked against two logs) found every token ask logged mode=standard,
  scoped=1, one passage of 1,819 to 1,837 chars; 7 of the 34 were right until the checker rewrote them. Deep Think's "This
  token has been repeatedly confirmed across multiple queries" is the model-written summary of earlier turns, which goes
  into memory. After Standard's invented warranty answer (below), the next question's answers repeat it. `[measured]`
- It is also the likeliest reason answers change between asks with no randomness and no new import: the memory text
  differs ask to ask (737, 838, 900 chars for one question), ranked partly by wall-clock recency, and written by
  background tasks that race the next ask. Not proven sufficient. `[measured, cause inferred]`
- The model session is not reused between asks (`AppleFoundationLLMService.swift:459` sets it to nil); the "Transcript
  history ~N tokens" log line describes the discarded session. That part of the first guess was wrong. `[code_verified]`
- A user meets it: ask about lease A in Chat, then "Ask About a Document" on lease B, or two Siri asks in a row. The
  memory is the same shared store the test used; the test did not create the problem. `[code_verified]`

### 2. Standard invents an answer when a passage holds a number but not the thing asked

"What is the warranty coverage for the unreleased 2032 prototype battery pack?" (no document holds it): Standard
answered "defined by the primary answer in the battery_limits.md document, which states: 45 C [S20]" in 4 of 18 asks
and leaned that way in 2 more; Deep Think and Maximum refused in all 52 of theirs. Every safeguard either did not run
or checked only that the number exists:

| Safeguard | What it did | Where |
|---|---|---|
| Low-relevance prompt (Evidence-First) | Fired, but lacks the normal prompt's "If a specific value is not in the excerpts, state that clearly" | `RAGService+QueryAnswer.swift:578` against `:586-596` `[code_verified]` |
| Source-only re-check | Runs only for extractive or precise-value questions; this one was classed as a definition | `:411` `[code_verified]` |
| Gate B, evidence coverage | Counts a word as found if it is in the question, so "warranty coverage" passed because the user typed it | `VerificationGateService.swift:1900-1902` `[code_verified]` |
| Gate C, numbers | Found "45 C" in a passage and passed | `VerificationGateService.swift:565-628` (read by the investigation) |
| Responsiveness | By design does not look at the passages | `AnswerResponsivenessJudge.swift:82-84` (read by the investigation) |

### 3. Deep Think's "which document" answers: the 5.8 file-name fix has a guard bug

5.8 writes the cited file's name into a "which document" answer, on every mode (`RAGService+AnswerFinishing.swift:347`,
`RAGService+AgenticQuery.swift:813`). But it skips the answer if it names *any* source's file
(`RAGService+AnswerHeadline.swift:193-198`), and Deep Think's 2,000 to 3,700-character answers always mention the
distractor files. So all 26 of Deep Think's failures on these three questions name another file and never the right
one; Standard fails 2 of 48, Maximum 2 of 24. The model is shown `[S1] (retrieval_beta.md)` and chooses the shared title
"Retrieval Fixture". 8 of the 26 also say the target "is not present" when it is. `[code_verified, measured]` The release
note '"which document" gets the file's name' holds for Standard and Maximum, not reliably for Deep Think.

### 4. Deep Think writes long answers to one-line questions, and sometimes its instructions leak

- Its final step asks for "one comprehensive, well-written answer" with ### headers whatever the question
  (`AgenticOrchestrator+ReasoningChain.swift:1263-1266`, `:1485-1489`); intent is detected as lookup and not used.
  Median 2,856 characters on the "which document" questions, against Standard's 246. `[code_verified, measured]`
- 13 of 360 Deep Think answers begin with the instruction's own words: "the exact value, name or finding, written as the
  source writes it, with its label" (`answerFirstInstruction`, `:1520-1521`, sent twice in Deep Think). Maximum and
  Standard: 0. `[measured]`

### 5. The test itself, corrected

- **Refusals:** all 19 of Deep Think's and 3 of Maximum's "wrong" answers to the two missing-evidence questions are
  correct refusals that the scoring rule failed because they later mention an unrelated dollar figure or use wording
  it does not know ("cannot be fulfilled"). None of the 52 invents a value. Standard's 5 failures there are real.
- **The exact-value fixtures never say what their value is** ("| Primary answer | $1,577 million |" for capital
  expenditure). Standard's capex misses are a search miss (it was only ever shown the file's heading), and Deep Think's
  correct-looking "$1,577 million" is a guess; the same move produced "45 C". The comparison of the modes on these
  questions rewards guessing.
- **The test shares one conversation memory across all 20 questions**, so earlier answers contaminate later ones in
  every run. That is the defect in 1; the test should keep it visible in a dedicated case and clear memory elsewhere.

### What this changes about the modes

Corrected for the scorer, on these 20 questions Deep Think refuses correctly where Standard sometimes invents, and loses
mainly on the file-name bug and on memory. Standard's lead was partly the scorer and partly guess-proof table questions.
Maximum is ahead or level everywhere. The temperature finding stands (greedy helps Deep Think), but it is no longer the
largest lever: memory and the checks are.

## Proposal for 5.9 (revised 2026-11-22 after reading the wrong answers)

Nothing here is done. App changes need the owner's `PROCEED: IMPLEMENT` and a `## 5.9` heading in `CHANGELOG.md`.

| # | Change | Kind | Fixes | How it is proven |
|---|---|---|---|---|
| 1 | A scoped ask neither reads nor records conversation memory (`RAGService+QueryAnswer.swift:693-722`, `RAGService+AnswerFinishing.swift:410-421`) | App | Earlier documents' answers in "Ask About a Document" | Unit test: a scoped prompt is the bare question; ask-twice Standard: middle and end right on every ask |
| 2 | The responsiveness checker gets earlier turns only when the question points back to them, or gets the passages (`RAGService+AnswerResponsiveness.swift:55-69`) | App | The checker rewriting a right answer into a wrong one | Replay the logged middle answer with memory holding the other token: verdict "full" |
| 3 | A value counts as supported only when its passage or table row names what the question asks about (Gate B `VerificationGateService.swift:1897-1903`, Gate C `:547`), and the source-only re-check also runs when Evidence-First fired | App | "45 C" as warranty coverage | Unit test both ways (unlabelled table fails, labelled passes); answer test with repeats: 0 invented answers; retrieval benchmark unchanged |
| 4 | The file-name guard looks at the cited source, not any source (`RAGService+AnswerHeadline.swift:193-198`) | App | Deep Think's "which document" answers | Unit case with a distractor file named; Deep Think on the three questions |
| 5 | Deep Think's final step takes its length from the question's intent, and the answer-first instruction loses its copyable lead-in and is sent once | App | 2,900-character lookups; 13 leaked instructions | Leak count 0 of 100; length by intent; every benchmark set no worse (accuracy first) |
| 6 | A document's summary is written with fixed sampling (`DocumentSummaryService.swift:344`) | App | The same file imports differently | Import twice, compare the stored text |
| 7 | Deep Think's default step temperature lowered from 0.5, value chosen by runs at 0.2 and 0.1 first (`RAGService+Agentic.swift:175`) | App | Deep Think's variation | Ask-twice Deep Think before and after |
| 8 | The scoring rule stops failing correct refusals and stops passing a value named only to say it does not apply; the exact-value fixtures label their values; memory is cleared between test questions except in one case that tests it | Test only | Scores that reward guessing and miss real refusals | Re-score the existing runs; rerun the three modes |
| 9 | Remove or wire the mode settings nothing reads; the privacy policy's version line | App | Code that claims what it does not do | Golden harnesses identical before and after |

Order: 8 first (no app change; every later number depends on it), then 1 to 3 (they change what a user sees most and
together cover every invented or overridden answer found), then 4 and 5, then 6 and 7, then 9.


## Item 8 done: the test, corrected (2026-11-23)

Test and tooling only; no app code changed. At the owner's word ("go ahead and start item 8 once greedy finishes").

| Part | What changed | Where |
|---|---|---|
| Scoring rule | A refusal counts when it says, in its first 600 characters, that the documents do not hold it, and offers no number of its own before the end of that sentence; it may go on to list other documents' values, and wordings such as "cannot be fulfilled", "remains undetermined", "no document provides" count. An answer whose first sentence says the documents do not hold the value, and that names the expected value only later as something else, is wrong. Banner, headings, emphasis, citation marks and the leaked answer-first instruction are read past. | `scripts/score_answer_eval.py`, tests `scripts/test_score_answer_eval.py` (11) |
| Fixtures | The five exact-value files label their values ("Fuel tank capacity", "Capital expenditure, FY2018", "Maximum payload", "Normal service interval", "Maximum charging temperature") instead of "Primary answer", made by the generator; nothing else in the pack changed | `scripts/prepare_rag_research_fixtures.py`, `Benchmarks/ResearchFixtures/tiny_research_suite/fixtures/synthetic/exact/` |
| Memory | Each ask starts with the library's conversation memory empty, after waiting up to 10 s for the last ask's turn to land; `OI_EVAL_MEMORY=keep` asks the old way, which is how item 1 is measured. The one case that tests memory is item 1's own unit test rather than a 21st question, because a question that needs memory kept would also need every question before it kept | `AnswerQualityEvaluationTests.swift` (`forgetEarlierAsks`) |
| Runs | `ask_twice.py --tag` names runs made under these rules, so the old folders do not count as done; `OI_TWICE_MIN_FREE_GIB` and `OI_BENCH_MIN_FREE_GB` lower the disk floor when other sessions hold the disk (a run takes about 6 GiB at its peak) | `scripts/ask_twice.py`, `scripts/bench_answer_modes.sh` |

**Re-scored, every answer read where the score changed** (1,360 answers from the 44 stability, noise and ask-twice runs to
2026-11-23 08:06):

| Mode | Answers | Old rule | Corrected rule | What changed |
|---|---|---|---|---|
| Standard | 520 | 82% (425) | 80% (414) | 10 answers said the temperature limit is "not specified in the excerpts" and only then named 45 C as another metric; 1 gave "45 C" as the warranty |
| Deep Think | 480 | 80% (383) | 85% (410) | 27 correct refusals had been failed |
| Maximum | 360 | 87% (312) | 89% (322) | 10 correct refusals had been failed |

The only refusals still wrong are Standard's 6 that state or lean on "45 C" as a warranty, the defect of item 3.
`[measured: scripts/score_answer_eval.py over the saved answers of each run's .xcresult and its "again" lines]`

The ask-twice runs, re-scored (right of 20, each ask):

| Mode | Sampling | Old rule | Corrected rule |
|---|---|---|---|
| Standard | As shipped | 16, 16, 16 | 15, 15, 15 |
| Standard | Greedy | 16, 17, 18 | 16, 17, 17 |
| Deep Think | As shipped | 15, 16, 15, 14, 16 | 17, 18, 16, 15, 18 |
| Deep Think | Greedy | 18, 17, 16, 16, 16 | 18, 17, 17, 17, 16 |
| Maximum | As shipped | 18, 17 | 19, 19 |
| Maximum | Greedy | 18, 18 | 18, 18 |

Maximum greedy's two misses on both asks were "$1,577 million" for the payload (another file's unlabelled "Primary
answer") and LITM-MIDDLE-42 for the end document (an earlier answer's token): one cause the labels remove and one the
memory change removes from the test. Its two other first-ask misses were "which document" questions.

### The three modes under the corrected test (2026-11-23, commit a67ae343)

Each mode as shipped, every question asked twice in one imported library, memory emptied before every ask
(`ask_twice.py --tag item8`). iOS 27.0 Simulator, 5.8's app code, the app's own model service.

| Mode | Right of 20, each ask | Same words both asks | Questions that changed sides | Before, same test re-scored (one library) |
|---|---|---|---|---|
| Standard | 20, 18 | 40% (8 of 20) | 2 (multi_hop_project_m2, m4) | 15, 15, 15 |
| Deep Think | 18, 17 | 15% (3 of 20) | 1 (retrieval_covid_gamma) | 17, 18, 16, 15, 18 |
| Maximum | 20, 20 | 20% (4 of 20) | 0 | 19, 19 |

`[measured; folders 2026-11-23-0836-answer-modes-twice-standard-shipped-item8, 2026-11-23-0852-answer-modes-twice-deepThink-shipped-item8, 2026-11-23-1327-answer-modes-twice-maximum-shipped-item8; one run a mode]`

- **The memory change held.** Every turn the app recorded found the memory empty (116 of 116 log lines "Added turn.
  Recent: 1"); 4 asks recorded no turn (two in Deep Think, two in Maximum, each answered in 4 to 14 s), so the test's
  10 s wait ran out and cleared an empty memory. The middle and end tokens were right on every ask in every mode,
  against about half before.
- **The labels removed Standard's two table misses.** FY2018 capital expenditure ($1,577 million) and the charging
  temperature (45 C) were right on both asks; they had been right 0 and 6 times in 18. The battery warranty, which no
  document holds, was refused on both asks ("not specified in the provided context"), where Standard had stated
  "45 C" in 4 of 18 asks: the label now says what 45 C is.
- **What is left is the app.** Standard's two second-ask misses say a multi-hop deadline is "not specified" when it is
  (a real miss, one ask in two). Deep Think's three misses are all "which document" questions (item 4: its long
  answers mention other files, so the file-name fix does not add the right one). Maximum missed nothing.
- So the gap between the modes on this set was mostly the test: with it corrected, Standard (19 of 20 on average) and
  Maximum (20) are level, and Deep Think (17.5) is behind only on the "which document" questions. One question set,
  one run a mode; greedy and phone runs not made.

Item 8 is done. Items 1 to 3 change the app and wait for the owner's `PROCEED: IMPLEMENT`; item 1 is measured with
`TEST_RUNNER_OI_EVAL_MEMORY=keep` (the old way) before and after the change.
