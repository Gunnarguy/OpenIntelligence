# OpenIntelligence privacy

The privacy policy is at **https://gunzino.me/openintelligence/privacy**. It is the one the App Store
listing links to, and from 5.7 (in preparation, not yet on the App Store) the same text is in the app, in Settings,
About, Privacy Policy. How the app decides where an answer is written, and what can leave the device, is
documented against the code in [Docs/PRIVACY_AND_ROUTING.md](Docs/PRIVACY_AND_ROUTING.md).

In short:

- Reading, indexing, searching and ranking your documents happen on your device.
- On iOS, iPadOS and macOS 27, Apple's Private Cloud Compute can write the final answer when every
  capability and consent check passes: with Hybrid in the model picker, an answer whose passages don't fit
  in the on-device model, and a Deep Think or Maximum answer drawn from more than one document; with Private
  Cloud Compute chosen, every answer, and Deep Think and Maximum can also send their intermediate reasoning
  passes there, each behind the same consent check. Otherwise answers are written on the device, and on iOS
  and macOS 26 they always are. Settings, Private Cloud Compute decides whether the app asks first: Never use,
  Ask when needed, or Allow without asking (shown as "Allow for Deep Think and Maximum" before 5.7, though
  it was never limited to those modes).
- Library sync through your iCloud Drive is available on Pro and Lifetime, and only when you turn it on.
- From 5.7 (in preparation, not yet on the App Store) the app downloads a web page when you give it the
  address, with "Save a Web Page", the Link field of "Add to Library" or a web address you paste on the
  Documents screen. The request goes to that site and carries nothing from your library.
- From 5.7, a question you ask with Siri or Shortcuts that would use Private Cloud Compute brings the app
  forward to ask first, with the same consent screen as the chat, unless you've already said yes or no;
  if the app can't come forward, the question is answered on the device.
- From 5.7 on iOS and macOS 27, when the app closes unexpectedly it can offer to email a crash report. The
  report holds the app and system versions, the device model and the part of the app's code that was
  running, and none of your documents, questions or answers. It leaves the device only if you send it, or share it
  from Settings, About.
- The app contains no third-party analytics, advertising or tracking code. Its only package dependency is
  swift-tokenizers.

`[evidence_level: artifact_derived, confidence: high, evidence_source: first line: Docs/PRIVACY_AND_ROUTING.md:11-12 and Docs/ai/ARCHITECTURE.md]`
`[evidence_level: code_verified, confidence: exact, evidence_source: second line: FoundationModelSessionFactory.swift:86-110 (PCC only on 27); ModelExecutionPlanner.swift:78-90 (the Hybrid cases: `!localBudget.fits` and `complexityRequestsPCC`, corrected 2026-10-15); AgenticOrchestrator.swift:9105 (`budgetPin`: a PCC choice lifts the reasoning passes' on-device pin; line corrected 2026-10-14); RAGService.swift:3676-3740 (the consent check). Third line: WorkspaceSyncService.swift:411-413. Fourth line: Package.resolved has one pin, swift-tokenizers; no AdServices, AdSupport, AppTrackingTransparency or analytics SDK import under OpenIntelligence/, searched 2026-09-29. The web page line, added 2026-10-12: WebPageFetchService.swift, and Docs/PRIVACY_AND_ROUTING.md, "A web page the person asks for is downloaded"]`

The summary this file carried until 2026-09-29 made statements the code contradicts, among them that
Private Cloud Compute ran as a local simulation. It is kept as a record at
`Docs/Archive/PRIVACY_summary_2026-02.md`.
