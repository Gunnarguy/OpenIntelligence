# RAGMLCore – App Review Notes

Last updated: November 2025

## Reviewer Checklist

1. **Launch & Reviewer Mode**
   - Open the app → Settings → toggle **Reviewer Mode**.
   - Reviewer Mode exposes pathway switches, consent state, and the most recent payload preview.
2. **Exercise Each Pathway**
   - **On-Device Analysis**: Default configuration. Import `TestDocuments/sample_1page.txt` from the in-app picker and ask “What does the sample document cover?”. Expect an extractive answer citing the document name.
   - **Apple Foundation Models**: In Settings enable *Allow Private Cloud Compute* and choose “Apple Foundation Model”. Ask a multi-step question (e.g., “Summarize the document and identify three action items”). The consent alert explains what will be transmitted. Accept to continue. An execution badge shows `☁️ PCC` when triggered.
   - **On-Device Only**: Switch Execution Strategy to **On-Device Only**. Ask the same question to verify that the response stays local (badge shows `📱 On-Device`).
   - **OpenAI Direct (optional)**: Provide your own OpenAI API key under Settings → Reviewer Mode → OpenAI Direct. The consent prompt appears before the first request; accept to observe direct OpenAI routing. Execution badge shows `🔑 OpenAI`.
3. **Force Fallbacks**
   - In Settings → Fallback Strategy enable both fallbacks and set the primary to Apple FM, first fallback to On-Device Analysis, second fallback to OpenAI Direct.
   - Put the device in Airplane Mode and reiterate a query. Primary fails → On-Device fallback engages (badge `📱 On-Device`). Disable Airplane Mode, remove the OpenAI key, and repeat to watch the second fallback fail gracefully with an inline warning.
4. **Payload Transparency**
   - With Reviewer Mode enabled, initiate a cloud pathway. Tap “View Last Payload” to see the exact prompt, context chunk hashes, and provider metadata that were transmitted.
5. **Data Removal**
   - In Settings → Privacy & Data tap “Clear Knowledge Containers” to delete documents, embeddings, caches, and stored keys. The action log in Reviewer Mode records the purge.

## Device & OS Expectations

- Optimized for iOS 26 on A17 Pro (or newer) hardware. Older devices fall back to On-Device Analysis.
- Apple Intelligence must be enabled in Settings to exercise Apple FM / Private Cloud Compute.

## Credentials & Secrets

- No secrets ship with the build. `secret_scan.py` verifies this during CI.
- Reviewers must bring their own OpenAI API key if they want to test the OpenAI pathway.

## Contact

For questions during review contact [release@openintelligence.app](mailto:release@openintelligence.app).
