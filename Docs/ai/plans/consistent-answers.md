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
