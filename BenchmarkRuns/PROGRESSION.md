# Benchmark progression

Generated 2026-08-21 12:29 by `scripts/benchmark_progression.py`. 58 run/mode pairs across 51 runs, of 79 run directories on disk — every one accounted for below.

**† marks 11 run(s) rebuilt from `results.jsonl`** because the harness never wrote a `results.json` — normally a run killed before it finished. The per-case data is real; the aggregates in those rows were recomputed here, not written by the harness, and `min` is unavailable for them.

**25 run(s) predate the current results schema** and are counted here rather than tabulated: all are from 2026-07-03, 1-9 cases each, 80 cases total, and **0 passed**. They are harness bring-up, not measurement, and 25 rows of zeros would bury the runs that mean something. Named so the count reconciles: `20260703-193614`, `20260703-193920`, `20260703-194701`, `20260703-195049`, `20260703-195153`, `20260703-195247`, `20260703-195500`, `20260703-195827`, `20260703-200110`, `20260703-200209`, `20260703-200310`, `20260703-200750`, `20260703-200913`, `20260703-200935`, `20260703-201017`, `20260703-201245`, `20260703-201426`, `20260703-201523`, `20260703-201917`, `20260703-202728`, `20260703-215109`, `20260703-221027`, `20260703-221523`, `20260703-221712`, `20260703-222241`.

**3 run director(ies) hold no results data** and cannot be tabulated (`latest` holds only a dashboard; the other two are empty): `20260809-165839-matrix`, `20260811-144942-matrix`, `latest`. They are listed rather than dropped, because a table that silently omits runs is the exact failure this file exists to prevent.

**Read the config columns before comparing any two rows.** Runs differing in `cases`, `pool`, `seed`, `temp` or `vw` are not comparable on accuracy — a withdrawn "4-7x performance regression" in `LEDGER.md` was exactly this mistake. For a real comparison use `scripts/compare_benchmark_runs.py`, which pairs by `case_id` and prints a control line.

`LEDGER.md` remains authoritative for *what each run settled* and for the analyses that turned out to be wrong. This table is an index, not a replacement.

|  | run | mode | commit | cases | pool | seed | temp | vw | correct | acc | lexical MRR | fusion MRR | rerank MRR | final r@1 | final r@10 | final MRR | min |
| :-- | :-- | :-- | :-- | --: | --: | --: | --: | --: | --: | --: | --: | --: | --: | --: | --: | --: | --: |
|  | qasper-deepthink-20260815 | deep-think | — | 82/83 | 10 | — | — | dflt | 17 | 0.205 | — | — | — | 0.421 | 0.632 | 0.479 | 402 |
|  | fusion-vw030 | standard | 27d2067 | 7/8 | 10 | 42 | 0.7 | 0.30 | 3 | 0.375 | 0.714 | 0.571 | 0.714 | 0.714 | 0.857 | 0.786 | 30 |
|  | rescue-position-fix | standard | f9b5765 | 25/25 | 10 | 42 | 0.7 | dflt | 12 | 0.480 | 0.691 | 0.708 | 0.732 | 0.500 | 0.875 | 0.646 | 92 |
|  | passage-level-1 | standard | ad99b1b | 25/25 | 10 | 42 | 0.7 | dflt | 11 | 0.440 | 0.691 | 0.708 | 0.732 | 0.500 | 0.875 | 0.642 | 78 |
|  | overnight-25case-nodeadlock | standard | 73fff4f | 25/25 | 10 | 42 | 0.7 | dflt | 10 | 0.400 | 0.691 | 0.708 | 0.753 | 0.417 | 0.875 | 0.590 | 209 |
|  | overnight-25case-nodeadlock | deep-think | 73fff4f | 25/25 | 10 | 42 | 0.7 | dflt | 9 | 0.360 | 0.696 | 0.719 | 0.699 | 0.567 | 0.878 | 0.665 | 209 |
|  | lexical-survival-3 | standard | 6790548 | 7/8 | 10 | 42 | 0.7 | dflt | 5 | 0.625 | 0.595 | 0.369 | 0.714 | 0.571 | 0.857 | 0.679 | 55 |
| ⚠ | lexical-survival | standard | c29e513 | 8/8 | 10 | 42 | 0.7 | dflt | 2 | 0.250 | 0.646 | 0.448 | 0.750 | 0.500 | 0.875 | 0.629 | 3 |
|  | fusion-vw050 | standard | c29e513 | 8/8 | 10 | 42 | 0.7 | 0.50 | 6 | 0.750 | 0.646 | 0.490 | 0.750 | 0.750 | 0.875 | 0.812 | 30 |
|  | fusion-vw030-deepthink | deep-think | 61a6a70 | 8/8 | 10 | 42 | 0.7 | 0.30 | 2 | 0.250 | 0.613 | 0.591 | — | 0.435 | 0.739 | 0.530 | 37 |
|  | boostfix-standard | standard | c29e513 | 6/8 | 10 | 42 | 0.7 | dflt | 3 | 0.375 | 0.694 | 0.542 | 0.690 | 0.500 | 0.667 | 0.583 | 83 |
|  | boostfix-deepthink | deep-think | c29e513 | 8/8 | 10 | 42 | 0.7 | dflt | 3 | 0.375 | 0.518 | 0.440 | — | 0.407 | 0.704 | 0.498 | 37 |
|  | postfix-citations | standard | ff24b72 | 8/8 | 10 | 42 | 0.7 | dflt | 5 | 0.625 | 0.646 | 0.448 | 0.750 | 0.750 | 0.875 | 0.812 | 58 |
|  | postfix-citations | deep-think | ff24b72 | 8/8 | 10 | 42 | 0.7 | dflt | 3 | 0.375 | 0.615 | 0.431 | — | 0.619 | 0.857 | 0.688 | 58 |
|  | paired-retry | standard | 1b700ed | 7/8 | 10 | 42 | 0.7 | dflt | 4 | 0.500 | 0.738 | 0.512 | 0.857 | 0.857 | 1.000 | 0.929 | 94 |
|  | paired-retry | deep-think | 1b700ed | 8/8 | 10 | 42 | 0.7 | dflt | 2 | 0.250 | — | — | — | 0.375 | 0.625 | 0.463 | 94 |
| ⚠ | 20260818-170026-matrix | deep-think | 6e2c47f | 3/3 | 10 | — | — | dflt | 3 | 1.000 | — | — | — | 1.000 | 1.000 | 1.000 | 2 |
|  | tokfix | standard | — | 23/25 | 10 | 42 | 0.7 | dflt | 9 | 0.360 | 0.754 | 0.534 | 0.709 | 0.409 | 0.864 | 0.579 | 112 |
|  | det-B | standard | — | 15/20 | 10 | 42 | 0.7 | dflt | 6 | 0.300 | 0.798 | 0.582 | 0.682 | 0.429 | 0.786 | 0.560 | 184 |
|  | coreml-provider | standard | acb86f5 | 24/25 | 10 | 42 | 0.7 | dflt | 13 | 0.520 | 0.710 | 0.728 | 0.763 | 0.565 | 0.913 | 0.690 | 172 |
|  | cmp-standard | standard | — | 27/30 | 10 | 42 | 0.7 | dflt | 9 | 0.300 | 0.662 | 0.460 | 0.621 | 0.400 | 0.760 | 0.508 | 182 |
|  | tiefix-1 | standard | — | 2/2 | 10 | 42 | 0.7 | dflt | 0 | 0.000 | 1.000 | 0.667 | 0.750 | 0.500 | 1.000 | 0.750 | 6 |
|  | smoke-deepthink-886c354 | deep-think | — | 6/6 | 10 | — | — | dflt | 3 | 0.500 | — | — | — | 0.667 | 0.833 | 0.683 | 26 |
|  | seedcheck-2 | standard | — | 2/2 | 10 | 42 | 0.7 | dflt | 0 | 0.000 | 1.000 | 0.625 | 0.750 | 0.500 | 1.000 | 0.750 | 6 |
|  | seedcheck-1 | standard | — | 2/2 | 10 | 42 | 0.7 | dflt | 0 | 0.000 | 1.000 | 0.667 | 0.750 | 0.500 | 1.000 | 0.750 | 6 |
|  | rrfix-1 | standard | — | 2/2 | 10 | 42 | 0.7 | dflt | 0 | 0.000 | 1.000 | 0.625 | 0.750 | 0.500 | 1.000 | 0.750 | 6 |
| ⚠ | fixeduuid-2 | standard | — | 2/2 | 10 | 42 | 0.7 | dflt | 0 | 0.000 | — | — | — | 0.000 | 0.000 | 0.000 | — |
| ⚠ | fixeduuid-1 | standard | — | 2/2 | 10 | 42 | 0.7 | dflt | 0 | 0.000 | — | — | — | 0.000 | 0.000 | 0.000 | — |
|  | det-A | standard | — | 18/20 | 10 | 42 | 0.7 | dflt | 5 | 0.250 | 0.804 | 0.582 | 0.669 | 0.471 | 0.765 | 0.578 | 119 |
|  | smoke-deepthink-f6bb4ca | deep-think | — | 5/6 | 10 | — | — | dflt | 2 | 0.333 | — | — | — | 0.400 | 0.800 | 0.520 | 48 |
|  | smoke-deepthink-cdd87a9 | deep-think | — | 6/6 | 10 | — | — | dflt | 2 | 0.333 | — | — | — | 0.500 | 0.833 | 0.574 | 27 |
|  | smoke-deepthink-ccc0eeb | deep-think | — | 6/6 | 10 | — | — | dflt | 1 | 0.167 | — | — | — | 0.667 | 0.667 | 0.667 | 28 |
|  | smoke-deepthink-184c562 | deep-think | — | 5/6 | 10 | — | — | dflt | 2 | 0.333 | — | — | — | 0.400 | 0.800 | 0.517 | 49 |
|  | qasper-postfix-20260813 | standard | — | 74/83 | 10 | — | — | dflt | 29 | 0.349 | 0.640 | 0.536 | 0.659 | 0.412 | 0.838 | 0.551 | 395 |
|  | qasper-overnight | standard | — | 77/83 | — | — | — | dflt | 34 | 0.410 | 0.649 | 0.509 | 0.626 | 0.431 | 0.806 | 0.549 | 290 |
| ⚠ | 20260811-150328-matrix | standard | — | 20/20 | — | — | — | dflt | 18 | 0.900 | 0.944 | 1.000 | 1.000 | 0.861 | 1.000 | 1.000 | 7 |
| ⚠ | 20260811-133233-matrix | standard | — | 20/20 | — | — | — | dflt | 18 | 0.900 | 0.806 | 1.000 | 0.972 | 0.833 | 1.000 | 0.917 | 7 |
| ⚠ | 20260809-191737-matrix | standard | — | 20/20 | — | — | — | dflt | 17 | 0.850 | 0.806 | 1.000 | 0.972 | 0.889 | 1.000 | 0.935 | 10 |
| ⚠ | 20260809-184737-matrix | standard | — | 20/20 | — | — | — | dflt | 16 | 0.800 | 0.806 | 1.000 | 0.972 | 0.889 | 1.000 | 0.944 | 7 |
|  | 20260809-184205-matrix | standard | — | 0/1 | — | — | — | dflt | 0 | 0.000 | — | — | — | — | — | — | 4 |
| ⚠ | 20260809-172244-matrix | standard | — | 0/20 | — | — | — | dflt | 0 | 0.000 | — | — | — | — | — | — | 3 |
| ⚠ | 20260808-retrieval-stages | standard | — | 20/20 | — | — | — | dflt | 14 | 0.700 | 0.725 | 1.000 | 0.908 | 0.750 | 0.900 | 0.825 | 7 |
|  | 20260730-091821-matrix | standard | — | 20/20 | — | — | — | dflt | 16 | 0.800 | — | — | — | — | — | — | 21 |
|  | 20260730-091821-matrix | maximum | — | 4/20 | — | — | — | dflt | 4 | 1.000 | — | — | — | — | — | — | 21 |
|  | 20260730-091821-matrix | deep-think | — | 5/20 | — | — | — | dflt | 4 | 0.800 | — | — | — | — | — | — | 21 |
| † | tok512 | standard | — | 1/1 | 10 | 42 | 0.7 | dflt | 0 | 0.000 | — | — | — | — | — | — | — |
| † | tiefix-2 | standard | — | 1/1 | 10 | 42 | 0.7 | dflt | 0 | 0.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | — |
| † | rrfix-2 | standard | — | 1/1 | 10 | 42 | 0.7 | dflt | 0 | 0.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | — |
| † | qasper-vw30 | standard | — | 36/36 | — | — | — | dflt | 14 | 0.389 | 0.715 | 0.616 | 0.652 | 0.593 | 0.778 | 0.636 | — |
| † | qasper-topk10 | standard | — | 8/8 | — | — | — | dflt | 4 | 0.500 | 0.646 | 0.542 | 0.625 | 0.500 | 0.750 | 0.588 | — |
| † | qasper-run-1 | standard | — | 2/2 | — | — | — | dflt | 0 | 0.000 | 1.000 | 0.417 | 0.750 | 0.500 | 1.000 | 0.750 | — |
| † | qasper-deepthink-c2477b3 | deep-think | — | 3/3 | 10 | — | — | dflt | 1 | 0.333 | — | — | — | 1.000 | 1.000 | 1.000 | — |
| † | paired-pool10 | standard | 0eb5d96 | 5/5 | 10 | 42 | 0.7 | dflt | 1 | 0.200 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | — |
| † | paired-pool10 | deep-think | 0eb5d96 | 5/5 | 10 | 42 | 0.7 | dflt | 0 | 0.000 | — | — | — | 1.000 | 1.000 | 1.000 | — |
| † | overnight-25case-aborted-deadlock | standard | c64f468 | 5/5 | 10 | 42 | 0.7 | dflt | 2 | 0.400 | 0.800 | 0.467 | 0.900 | 0.800 | 1.000 | 0.900 | — |
| † | overnight-25case-aborted-deadlock | deep-think | c64f468 | 5/5 | 10 | 42 | 0.7 | dflt | 2 | 0.400 | 1.000 | 0.708 | 1.000 | 0.500 | 1.000 | 0.675 | — |
| † | lexical-survival-2 | standard | 79755ea | 1/1 | 10 | 42 | 0.7 | dflt | 1 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | — |
| † | cmp-deepthink | deep-think | — | 16/16 | 10 | 42 | 0.7 | dflt | 2 | 0.125 | — | — | — | 0.438 | 0.625 | 0.485 | — |

**⚠ marks 10 run/mode pair(s) averaging under 60s per case — generation almost certainly did not run.** The known instance is `lexical-survival`, taken while Foundation Models was wedged machine-wide; every answer was fallback text. Treat any flagged row as unmeasured, not as a low score.

**Columns.** `acc` is exact-match against the fixture's `expected_answer_patterns`; it is a floor, not a quality score. `final r@1`/`r@10` are **document-level** — they credit a whole document when any of its chunks appears, which inflated `r@1` to 1.000 on runs where a document summary was injected.

**Do not read a one- or two-case accuracy difference as a result.** Two runs of the same build (`rescue-position-fix` and `passage-level-1`, differing only by debug output printed after generation) scored 11/24 and 10/24 with an identical lexical control. **±1 case at n=24 is the measured noise floor**, so nothing smaller than roughly a 4-case swing resolves in the `correct`/`acc` columns. The stage columns are far more stable — 22 of those 24 cases were identical at every retrieval stage — and are what a change should be judged on. `LEDGER.md` carries the decomposition.