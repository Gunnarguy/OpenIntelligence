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
