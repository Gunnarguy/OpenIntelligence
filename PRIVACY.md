# OpenIntelligence privacy

The privacy policy is at **https://gunzino.me/openintelligence/privacy**. It is the one the App Store
listing links to. How the app decides where an answer is written, and what can leave the device, is
documented against the code in [Docs/PRIVACY_AND_ROUTING.md](Docs/PRIVACY_AND_ROUTING.md).

In short:

- Reading, indexing, searching and ranking your documents happen on your device.
- On iOS, iPadOS and macOS 27, Apple's Private Cloud Compute can write the final answer when every
  capability and consent check passes. If you choose Private Cloud Compute in the model picker, Deep Think
  and Maximum can also send their intermediate reasoning passes there, each behind the same consent check.
  Otherwise answers are written on the device, and on iOS and macOS 26 they always are.
- Library sync through your iCloud Drive is available on Pro and Lifetime, and only when you turn it on.
- The app contains no third-party analytics, advertising or tracking code. Its only package dependency is
  swift-tokenizers.

`[evidence_level: artifact_derived, confidence: high, evidence_source: first line: Docs/PRIVACY_AND_ROUTING.md:11-12 and Docs/ai/ARCHITECTURE.md]`
`[evidence_level: code_verified, confidence: exact, evidence_source: second line: FoundationModelSessionFactory.swift:86-110 (PCC only on 27); ModelExecutionPlanner.swift:81-88; AgenticOrchestrator.swift:9000-9014 (a PCC choice lifts the reasoning passes' on-device pin); RAGService.swift:3676-3740 (the consent check). Third line: WorkspaceSyncService.swift:411-413. Fourth line: Package.resolved has one pin, swift-tokenizers; no AdServices, AdSupport, AppTrackingTransparency or analytics SDK import under OpenIntelligence/, searched 2026-09-29]`

The summary this file carried until 2026-09-29 made statements the code contradicts, among them that
Private Cloud Compute ran as a local simulation. It is kept as a record at
`Docs/Archive/PRIVACY_summary_2026-02.md`.
