# Audio edition of the study guide

Plain text written to be read aloud by a text-to-speech app such as ElevenLabs Reader. No tables,
no file paths or line numbers, identifiers spoken as words, abbreviations spelled out, and a pause
cue before every quiz answer.

## The course: five passes, about two hours

Each pass tells the whole machine end to end, one level deeper than the last. Stop after any pass
and you have a complete picture at that depth.

| Pass | File | Voice | About |
|---|---|---|---|
| 1 | `PASS_1_The_story.txt` | Explained like you're five, one analogy carried all the way through, no technical words | 15 min |
| 2 | `PASS_2_The_beginner_tour.txt` | The same route with the real names of every part and why each exists | 30 min |
| 3 | `PASS_3_The_engineer_to_a_newcomer.txt` | The numbers, the decisions, where it runs, what each stage drops | 40 min |
| 4 | `PASS_4_The_researcher_to_an_expert.txt` | Formulas, exact thresholds, loop internals, dormant paths, corrections to the earlier documents | 25 min |
| 5 | `PASS_5_Tie_it_together.txt` | The thread through all of it, the three spoken versions, a ten-question self-test | 10 min |

`STUDY_GUIDE_AUDIO_FULL.txt` is the five passes in one paste.

## The reference: the word bank, not for listening end to end

`Reference_word_bank/` holds the 612-concept word bank read aloud, one file per module (00 to 16),
plus the introduction and the drills from the first audio edition. It is a dictionary. Use it to
look up a term you heard in a pass, not as a listening path; end to end it is three and a half
hours of definitions, which is what the first edition was and why it was replaced.

Every number in the passes was read from source and is cited with its line in
`Docs/Engineering/FULL_SYSTEM_TRACE.md`. `Docs/STUDY_GUIDE.md` is the written course with the
same content plus the full word bank, checklists and quizzes; it wins where the two differ.
