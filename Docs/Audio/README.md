# Audio edition of the study guide

> **Corrected 2026-09-29** against the code, in the five passes, `STUDY_GUIDE_AUDIO_FULL.txt` and
> word bank files 00, 06, 08, 10, 13, 15, 16 and 18. Private Cloud Compute has shipped since 5.2 on 2026-09-10 and
> is no longer called dormant. The fusion weights are 0.50 and 0.50 on a default library's first pass, not 0.7 and 0.3; in
> Standard a weak-retrieval cascade and a keyword retry lean keyword, the retry at 0.3 and 0.7.
> The GPU profile does gate Metal vector search: only Performance and Maximum use it. Citations
> carry a chunk, its page and a quote, not byte or character offsets. The consent sheet shows how
> much would be sent and why, not exactly what, and after Always Allow it stops asking. Embedding concurrency reaches 128 on a Mac, not 64.
> Adaptive generation profiles are opt-in, not dormant, and for lookup answers a source-only check can
> run two more on-device sessions, one drafting claims and one rating them, whose result can replace
> the answer; no pass says there are only two generative stages. Pass 4 no longer says generation always runs: the extractor answers
> value questions whose best span clears the precision lock. Audio rendered before this date says the
> old facts.
> `[evidence_level: code_verified, confidence: high, evidence_source: Docs/STUDY_GUIDE.md header note and the lines it cites]`
>
> **Corrected 2026-10-20 against the working tree (`b868fc0` plus the 5.7 work in progress)**, in passes 1 to 5 and
> `STUDY_GUIDE_AUDIO_FULL.txt`, which is still the five passes joined. The wrong sentences were rewritten in place, in
> the passes' spoken style. Deep Think's chain reads windows cut from one search, at most eight rounds on every device,
> and searches again only in research rounds after the chain. Maximum's own loop never searches again. Planner
> escalation is off while Apple's model writes the answers, and a lookup can be answered by the extractor before any
> round. Deep Think takes its numbers from the device, not from the four named profiles. The gates label the answer,
> leave its words alone (the claims Gate B could not support drop off the fact-check list), and run on no Deep Think
> or Maximum answer in the shipped 5.6. Under the default hybrid setting only
> the write-ups can reach Private Cloud Compute, and with it picked in the model picker the rounds can go too. The
> evidence budget is worked out per question, not fixed at 3,200. MMR's lambda is the library's in every mode. HyDE runs
> in no mode. The agentic step cooldown and minimal mode's limit on agentic steps are read by nothing, and the
> optimizer's own step cooldown delays only Standard's answer. No plan is deterministic in this build, and one would
> still let the model write. A second review that evening added the planning call every question gets, the research
> retries (at most two), the ultra tier's chips, the cloud window the app assumes, the lookup's lead passage and the
> rule that neither loop reads heat, memory, the battery or Low Power Mode. The Speech Analyzer branch, dormant through 5.6, runs first from 5.7. The word count below
> was 12,043 before this pass, and the full file is now 14,837 words by `wc -w`, about 99 minutes at 150 words a
> minute. Audio rendered before this date
> says the old facts. In `Reference_word_bank/`, file 11 had its opening paragraphs rewritten, and files 00 (both),
> 02, 07, 08, 09, 10, 11, 12, 15, 16 and 18 gained a spoken sentence, "Corrected on 20 October 2026", after the lines
> that were wrong. Sentences nine and eleven of the twelve were rewritten in place. Files 01, 03 to 06, 13 and 14 were
> searched for the same claims and not otherwise re-read.
> `[evidence_level: code_verified, confidence: high, evidence_source: Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md section 19 and the file:line tags it cites]`

Plain text written to be read aloud by a text-to-speech app such as ElevenLabs Reader. No tables,
no file paths or line numbers, identifiers spoken as words, abbreviations spelled out, and a pause
cue before every quiz answer.

## The course: five passes, about 75 to 90 minutes

Each pass tells the whole machine end to end, one level deeper than the last. Stop after any pass
and you have a complete picture at that depth.

| Pass | File | Voice | About |
|---|---|---|---|
| 1 | `PASS_1_The_story.txt` | Explained like you're five, one analogy carried all the way through, no technical words | 11 min |
| 2 | `PASS_2_The_beginner_tour.txt` | The same route with the real names of every part and why each exists | 18 min |
| 3 | `PASS_3_The_engineer_to_a_newcomer.txt` | The numbers, the decisions, where it runs, what each stage drops | 24 min |
| 4 | `PASS_4_The_researcher_to_an_expert.txt` | Formulas, exact thresholds, loop internals, dormant paths, corrections to the earlier documents | 18 min |
| 5 | `PASS_5_Tie_it_together.txt` | The thread through all of it, the three spoken versions, a ten-question self-test | 9 min |

`STUDY_GUIDE_AUDIO_FULL.txt` is the five passes in one paste: 12,043 words, about 80 minutes at 150 words a minute.

## The reference: the word bank, not for listening end to end

`Reference_word_bank/` holds the 612-concept word bank read aloud, one file per module (00 to 16),
plus the introduction and the drills from the first audio edition. It is a dictionary. Use it to
look up a term you heard in a pass, not as a listening path; end to end it is three and a half
hours of definitions, which is what the first edition was and why it was replaced.

Every number in the passes was read from source and is cited with its line in
`Docs/Engineering/FULL_SYSTEM_TRACE.md`, except the 2026-09-29 corrections, which were read from the
code; the trace was corrected the same day. `Docs/STUDY_GUIDE.md` is the written course with the
same content plus the full word bank, checklists and quizzes; it wins where the two differ.
