# Measurements: every open question and what settles it

Started 2026-11-12 at the owner's request: "a corpus of everything that needs to be done to have solid numbers across
the board". One row per question he has asked or a run left open. Each row has the best number there is today, what
would settle it, and where and how long it runs. Results go in `BenchmarkRuns/LEDGER.md` (one entry per run folder);
this file says what is still missing. When a row is settled, move its number into "Now" with the run folder and mark it
**Settled**. Never delete a row.

Status: **Settled** (a controlled run answers it), **Partly** (a number exists but not the one the question asks),
**Open** (nothing measured).

Costs are from runs on this Mac (M3 Pro, iOS 27.0 Simulator, Apple's model on the patched copy from
`scripts/sim_model_copy.py`): about 20 s a Standard answer, 65 to 80 s a Deep Think answer, about 63 s a Maximum answer
(`BenchmarkRuns/2026-11-12-deepthink-source-passages`, `2026-11-12-0223-answer-modes`). One Simulator run at a time.

## Answer accuracy

| # | Question | Status | Now | What settles it | Route, time |
|---|---|---|---|---|---|
| A1 | Is 5.8 more accurate than 5.7, per mode? | Partly | 20 cases, app model path, Simulator, one run each (`2026-11-13-0014-answer-modes-5.8`, `2026-11-13-0142-answer-modes-v5.7.0`): Standard 0.30 to 0.45, Deep Think 0.40 to 0.40, Maximum 0.25 to 0.40. Each case is 0.05. The 158 table questions cannot run on 5.7 (`EvidenceReachBenchmarkTests` is newer) | A larger set, or repeat runs, to separate a three-case change from noise | Mac Simulator, about 1.5 h per build per run |
| A2 | Deep Think's answers got about 23% shorter on the phone; did they get less accurate? | Partly | Paired run 2026-11-12: Deep Think 46 to 45 of 53 right with the change (same-value scorer; 37 to 42 by exact text); shorter or longer was not scored | A1 for Deep Think, plus answer length per question beside right or wrong | Inside A1 |
| A3 | Did today's two changes help on every table question, not one third? | Partly | Slice 0 of 3 (53), same-value scorer (2026-11-13): Deep Think 46 to 45, Standard 46 to 47 (exact-text scorer: 37 to 42, 44 to 45) | `run.sh 1/3` and `2/3` in `BenchmarkRuns/2026-11-12-deepthink-source-passages` | Mac Simulator, about 3 h each |
| A4 | Does the better import give better answers? | Open | Import checks 344 to 433 of 515; when a table cell reached the model it answered 124 of 131 right, 1 of 27 when it did not | Import the 7 table PDFs with build 14d6cc67 (before the 2026-11-08 work) and with 5.8, ask the 158 table questions in Standard against each library | Mac Simulator, about 2 h |
| A5 | Does the Granite embedder give better answers in the app? | Partly | In the app, golden retrieval, Simulator (`2026-11-12-full-suite/golden-score.txt`): top 5 up in every mode (Standard 0.526 to 0.789, Deep Think 0.511 to 0.609 on 92 questions, Maximum 0.500 to 0.667), MRR up in every mode, first place equal or up except Maximum's 36 (0.472 to 0.444); no per-mode change reaches p<0.05. Python, 2026-11-09: top 5 39.0% against 37.0%, p=0.006. The 158 table questions with each embedder were still running on 2026-11-13 at 07:00 | `tables-score.txt` in that folder | Running |
| A6 | Does the Mac's 8,192 window answer better than the iPhone's 4,096? | Partly | Raw model, 2026-10-07: plain lookups 16 of 16 at every size; look-alikes and one-step questions got worse as the prompt filled; citations 16/17 to 13/16 | The paired run with the window held at 8,192 against 4,096, same questions | Mac Simulator, about 3 h per slice |
| A7 | Is Deep Think better than Standard? | Partly | 20 cases on 5.8: Standard 0.45, Deep Think 0.40 (one case apart), median 20 s against 72 s a question. Tables slice 0: Standard 45, Deep Think 42 of 53 | A larger set; the slices | With A3 |
| A8 | Is Maximum worth its time? | Partly | 20 cases on 5.8 (2026-11-13): 0.40, median 80 s a question against Standard's 20 s; the 11-12 run gave 0.50. Same set, one run each, the two runs a 2-case spread | Maximum on the 158 table questions | Mac Simulator, about 3 h |
| A9 | Do citations point at the passage that says it? | Partly | 6 of 6 added labels named a passage holding the value, 2 on the neighbouring sentence; malformed labels ("(S1)", "[2]") in 3 of 4 unlabelled answers | Score every `[S#]` in A1's answers against its passage (number present, words shared) | Script over A1's output, minutes |
| A10 | Does it say "not in your documents" when they don't hold the answer? | Partly | Raw model, 2026-10-07: 4 of 4 declined at every size; no in-app set found in the ledger | A set of questions whose answer is in no fixture, all three modes | Mac Simulator, about 1 h for 30 questions |
| A11 | Does the Simulator answer like the iPhone? | Open | Never compared | 10 questions on the phone's development build and in the Simulator, same library | Phone (his 10 minutes) plus 1 h |

## Retrieval

| # | Question | Status | Now | What settles it | Route, time |
|---|---|---|---|---|---|
| R1 | Which rules after the reranker help? | Settled | 13 rules each off: corrective retrieval helps (p=0.01); Deep Think's spec sniper removed; no other measurable effect (`2026-11-10-rule-audit`) | | |
| R2 | Reranker: Granite against TinyBERT | Settled | Top 5 48.8% against 41.9% (25 better, 8 worse, p=0.005) | | |
| R3 | Does Full Power (Maximum compute profile) improve search? | Open | Import text identical under all three profiles (`2026-11-11-compute-profiles`); search per profile not run | QASPER 246 and tables 158 per profile | Mac Simulator, about 3 h |

## Import

| # | Question | Status | Now | What settles it | Route, time |
|---|---|---|---|---|---|
| I1 | Text and table fidelity on research PDFs | Settled | 515 checks 344 to 433 (`2026-11-08-extraction-fidelity`), then 439 with 5.8's table-region and layout-coverage fixes (`2026-11-12-tables/tab-fin`; fbioe number recall 0.865 to 0.969; 4 oncotarget sentences' lines swapped); numbers in body text 89.8% to 96.6% | | |
| I2 | Old typewritten scans | Partly | 24 to 25 of 85 checks; Apple's model reading the image tied Vision | A larger scan set (olmOCR-Bench old_scans has more pages than the 15 used) | Mac Simulator, about 1 h |
| I3 | Word, PowerPoint, Excel, CSV, web pages | Partly | 35 gaps fixed against string fixtures; no scored set of real files | 20 real files with checks written from the page, as I1 | Mac Simulator, about 2 h plus writing checks |
| I4 | Import speed | Partly | 8 PDFs 594 s to 641 s, one run each, another job compiling during one | Three runs each build, Mac otherwise idle | Mac Simulator, about 2 h |

## Speed on the phone

| # | Question | Status | Now | What settles it | Route, time |
|---|---|---|---|---|---|
| S1 | Deep Think time, same questions before and after | Partly | Phone, different questions: mean 254 s to 157 s | 5 fixed questions on the 5.7 build and on 5.8, same library | Phone, his 30 minutes per build |
| S2 | "Getting search ready" on most launches | Partly | About 30 loads of 20 to 130 s since 2026-11-09, mostly with no install; 1.47 GB of compiled copies; on the Mac the cache is keyed by the model's path | The proposed fixed-path load, then three remote relaunches each under 2 s | Phone, 10 minutes after the fix |
| S3 | Launch got 78 ms slower (392 to 470 ms) | Open | Two periods, different builds | Instruments launch trace on each build | Phone, 30 minutes |
| S4 | Background embedding speed since the Neural Engine entitlement | Open | 11.1 against 47.0 passages a second before the entitlement | One background rebuild on the phone | Phone, 20 minutes |

## Licences (owner's rule 1)

| # | Question | Status | Now | What settles it | Route, time |
|---|---|---|---|---|---|
| L1 | Is every shipped model cleared for commercial use? | Settled | Both models are IBM Granite, Apache 2.0, MS MARCO left out by IBM's model cards (which also name "select proprietary data"); MiniLM is gone from the app since 2859d9a5 (its Core AI folder holds a README) | | |
| L2 | Is every library and asset cleared for commercial use? | Settled | Licence audit 2026-11-12: swift-tokenizers and the vendored swift-transformers Apache 2.0; about 158 Rust crates MIT, Apache 2.0 or other permissive licences, uniffi MPL-2.0 (allowed, needs its notice); no fonts. `THIRD_PARTY_NOTICES.md` updated; the one asset with no licence (`LogicBoard_A18Pro`, unused) removed. Open: the crates' copyright notices are not shown in the app | An acknowledgements screen | Future Backlog |

## Order

Run first what decides a ship: A3 and S2 (today's changes and the launch wait), then A1 (5.7 against 5.8), A4 (import),
A5 and L1 (the embedder), A6 (window). The rest after. Each run gets its folder, its ledger entry the same day, and its
row here updated.
