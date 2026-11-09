# What OpenIntelligence is for

This file is the single home of the app's purpose and the owner's standing rules. Every agent loads
the block below at session start: `scripts/sync_purpose.py` copies it, word for word, into
`CLAUDE.md` (Claude Code, which re-reads that file from disk after every compaction), `AGENTS.md`
(Codex, Antigravity, Gemini CLI) and `.agents/rules/02-purpose.md` (Antigravity's always-on rules).
Edit it here only, then run `python3 scripts/sync_purpose.py --write`; the pre-commit hook refuses
a commit whose copies have drifted. Added 2026-11-09 at the owner's request, after agents kept
losing the purpose under the detail.

<!-- purpose:begin -->
## Purpose: what this app is, and the owner's rules

OpenIntelligence is a private research librarian for the documents people own. You import any
document, of any size, quality or file type, from a one-page text file to a 1,000-page research
paper full of tables and figures. The app reads it as carefully as a person would, organizes,
imports and embeds it correctly, and then answers questions about it: one document or a library of
50 documents of 50 pages each. Answers come only from what the documents say, extracted
surgically, with the exact passage each one came from. It works offline: in airplane mode
everything works. The network is used only to import a file that is not on the device and, when
the user consents, to send the final answer's generation to Apple Private Cloud Compute. It exists
because most document AI makes people upload their files first, which is the whole problem when the
files are medical, legal, financial, or simply theirs. It is a paid App Store app with a Pro tier,
and its repository is public under MIT, so people can check it.

The owner's rules, in his words (dated quotes in `Docs/ai/PURPOSE.md`). When two conflict, the
earlier one wins. Check every plan against them, and say so when a request or a plan breaks one.

1. **Commercial use only.** Bundle nothing that is not cleared for commercial use: check a model's
   weights licence and the terms of the data it was trained on, and every library and asset. The
   app earns money, so a non-commercial dependency is a defect, whatever its weights tag says.
2. **Offline and private by construction.** Ingestion, indexing, retrieval, ranking and on-device
   answers work with no network at all. Nothing else may need one; routing changes go through the
   hard-boundary files and the owner's approval.
3. **Accuracy first, speed second.** Take a measured accuracy gain even when it costs time. Make
   things faster only through changes that leave answers as accurate, as complete and as well cited;
   Deep Think and Maximum never get shallower to get quicker.
4. **Fidelity on any document.** A 1950s typewritten scan and a table-rich research paper with
   figures must both be read, organized and understood. Losing text, a table cell or a number at
   import is the worst kind of defect, because nothing later can recover it.
5. **Honest answers.** Cite the passage. When the documents do not hold the answer, say so instead
   of guessing. Name defects plainly in release notes and copy; the honesty is the product.
6. **Universal fixes.** This is a general RAG engine. A bad answer is a probe for a general defect:
   fix the layer that caused it and measure on every benchmark set, never patch one file or one
   question type.
7. **Make it work.** A clear refusal of the owner's own file is still a failure. Build the
   capability, using Apple's frameworks.
8. **Apple's models and hardware, used fully.** Generation uses Apple's Foundation Models. Use the
   Neural Engine, GPU, Vision and the system surfaces (Share Sheet, Siri, Shortcuts, App Intents)
   to their full extent. Third-party models are limited to the embedder and the reranker.
9. **Find the better way yourself.** Research current published methods and measure them here
   before guessing. The owner should not have to be the one who suspects there is a better way.
<!-- purpose:end -->

## The owner's words, dated

| Rule | Quote | Date |
|---|---|---|
| purpose | "upload a document of any size any fidelity any quality literally any file type ... anything ranging from a one page text document all the way to a 1000 page table Rich figure Rich research paper"; "a library of even 50 different documents each document having 50 pages and then being able to ask a question and get an accurate response"; "being able to surgically extract information show you where it came from and it all working off-line" | 2026-11-09 |
| 2 | "when I put my phone on airplane mode. It works. The only thing that's [cloud] related is obviously importing from sources that are not directly on my phone as well as my private cloud compute" | 2026-11-09 |
| 1 | "absolutely don't use anything that's not approved for commercial use because I'm literally making money off of this app" | 2026-11-09 |
| 3 | "the main core absolute purpose of this app is to be accurate number one and then fast as number two"; "I don't mind if it has to take longer" | 2026-11-08 |
| 3 | "I also don't want deep think or maximum to get dumber or less verbose. It needs to, if anything, become even more accurate" | 2026-11-07 |
| 4 | "absolute, ridiculous level of fidelity. like if i upload a document from the 1950s hand scanned back then vs a HIIIIGHYL complex, table rich with figures research paper, it should be able to organize it all and understand it all" | 2026-11-08 |
| 5 | "I'm trying to be fully transparent and I feel like these people all deserve that" | 2026-09-22 |
| 6 | "its imperative that this is a universal rag engine ... not specific to anything xyz" | 2026-11-08 |
| 7 | "make it work, dont just make it not work lol, it has to. employ the absolute best methods to do this using apples frameworks please" | 2026-10-09 |
| 8 | "yes I'm sticking to apple models for this app"; "full unlocking and utilization of the hardware and Apple frameworks" | 2026-10-06, 2026-10-10 |
| 9 | "There has to be some stuff we're missing go deep into the apple foundations and other frameworks" | 2026-10-10 |
| all | "I can't rely on an agent ever guessing or ever steering away from the actual core purpose" | 2026-11-09 |

Rule 2 restates the product's privacy promise (`Docs/PRIVACY_AND_ROUTING.md`,
`Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md`) rather than a single quote.

`[evidence_level: owner_statement, confidence: exact quotes, evidence_source: the dated Claude Code sessions in this repository, recorded in its auto memory; 2026-09-22 is the date of the writing-voice note]`
