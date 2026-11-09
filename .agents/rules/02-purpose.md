# Rule: the app's purpose and the owner's rules (always on)

Generated from `Docs/ai/PURPOSE.md` by `scripts/sync_purpose.py`. Edit that file, not this one.

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
