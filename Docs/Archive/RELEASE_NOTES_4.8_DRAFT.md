# v4.8 release notes

Matched to `Docs/USER_CHANGELOG.md`: bulleted, bold label, colon, then the
change in product voice. Short items, several of them, like v4.6's thirteen.
No first person, no em dashes, no apologies, nothing about unmeasured work.

Two forms below. The first is paste-ready for App Store Connect (4,000
character limit) using real bullet characters, since ASC renders plain text.
The second is the same content in your USER_CHANGELOG markdown style.

---

## For App Store Connect (~2,600 characters)

Deep Think and Maximum were not wired up correctly in previous releases. This release connects them.

• Deep Think and Maximum Now Reason Over Retrieved Evidence: Both modes run several reasoning passes across your documents, each building on the one before it. The handoff between retrieval and the reasoning step was never connected, so every pass concluded there was nothing to work with.

• Retrieval Was Never the Problem: Documents were being found, ranked, and prepared correctly the entire time. The evidence simply never reached the step that decides how to answer.

• Reasoning Passes Now Build on Each Other: With evidence connected, later passes can challenge and refine what earlier passes concluded, checked against your sources.

• Resolved "The selected model isn't available right now": That message appeared when the reasoning step found nothing to plan against. It was never a model or hardware problem.

• Model Picker Now Governs Deep Think and Maximum: The On-Device, Hybrid, and Private Cloud Compute selection reached Standard correctly but was dropped in the two agentic modes, which fell back to the default policy instead.

• On-Device Now Covers the Entire Query: If Private Cloud Compute had been allowed previously and the picker was later set to On-Device, Deep Think could still send evidence to Apple's Private Cloud Compute. No data reached a third party, an explicit denial always blocked cloud execution, and Standard always honored the selection. On-Device now applies through final synthesis.

• Document Import on Mac: The macOS file picker was a placeholder reading "Document picker is unavailable on this platform." It is now a native picker supporting the same formats as iOS, including PDFs, Office and iWork files, text, code, images, audio, and video.

• Deep Think Stops When Finished: Its internal confidence target could not be reached mathematically, so every query ran the maximum number of passes regardless of whether further passes surfaced anything new. Queries that resolve early now end early.

• Resilient Reasoning Passes: A single transient generation failure no longer discards an entire query. Failed passes retry, and the chain continues across its remaining evidence windows.

• Grounded Answers Are No Longer Discarded: An answer that correctly noted a gap in your documents was being treated as a retrieval failure and replaced with raw source excerpts. Answers that cite their sources are now preserved.

---

## For Docs/USER_CHANGELOG.md

## v4.8 - July 30, 2026

*   **Deep Think and Maximum Now Reason Over Retrieved Evidence:** Both modes run several reasoning passes across your documents, each building on the one before it. The handoff between retrieval and the reasoning step was never connected, so every pass concluded there was nothing to work with. (Correction to earlier releases: Deep Think and Maximum did not perform multi-pass reasoning as described; queries returned Standard quality answers after a longer wait.)
*   **Retrieval Was Never the Problem:** Documents were being found, ranked, and prepared correctly the entire time. The evidence simply never reached the step that decides how to answer.
*   **Reasoning Passes Now Build on Each Other:** With evidence connected, later passes can challenge and refine what earlier passes concluded, checked against your sources.
*   **Resolved "The selected model isn't available right now":** That message appeared when the reasoning step found nothing to plan against. It was never a model or hardware problem.
*   **Model Picker Now Governs Deep Think and Maximum:** The On-Device, Hybrid, and Private Cloud Compute selection reached Standard correctly but was dropped in the two agentic modes, which fell back to the default policy instead.
*   **On-Device Now Covers the Entire Query:** If Private Cloud Compute had been allowed previously and the picker was later set to On-Device, Deep Think could still send evidence to Apple's Private Cloud Compute. No data reached a third party, an explicit denial always blocked cloud execution, and Standard always honored the selection. On-Device now applies through final synthesis.
*   **Document Import on Mac:** The macOS file picker was a placeholder reading "Document picker is unavailable on this platform." It is now a native picker supporting the same formats as iOS.
*   **Deep Think Stops When Finished:** Its internal confidence target could not be reached mathematically, so every query ran the maximum number of passes regardless of whether further passes surfaced anything new.
*   **Resilient Reasoning Passes:** A single transient generation failure no longer discards an entire query. Failed passes retry, and the chain continues across its remaining evidence windows.
*   **Grounded Answers Are No Longer Discarded:** An answer that correctly noted a gap in your documents was being treated as a retrieval failure and replaced with raw source excerpts. Answers that cite their sources are now preserved.

---

## Notes for you, not for users

- Ten bullets, matching v4.6's density rather than a few long paragraphs.
- The ASC version uses "•" because App Store Connect renders plain text, so
  markdown asterisks would show up literally.
- The USER_CHANGELOG version adds a parenthetical correction in the first
  item, the same way v4.6 handled the 20B model claim.
- Accountability sits in the opening line only. Everything after it is the
  work.
- Don't paste this section.
