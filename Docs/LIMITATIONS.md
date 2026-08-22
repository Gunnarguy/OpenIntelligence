# Limitations

OpenIntelligence ships on the App Store for iPhone, iPad, and Mac, with paid subscription tiers. It is a real product, and the limits below are the honest boundaries of what it does well — not a disclaimer that it is a prototype.

> **Corrected 2026-08-05.** This document previously opened by calling the app "experimental software... a proof-of-work repository and prototype" and listed "It is not production-ready" and "It is not a commercial product offering" as limits. Both were false: the app has been selling `pro_monthly`, `pro_annual`, and `lifetime_cohort` through StoreKit since v4.4, and `README.md` states it is shipping. A limitations document that understates what the product is undermines the limits that actually matter, which are the safety and technical ones below.

## Product Limits

- It is not a finished enterprise SDK, and `OIEngine` still routes through app-owned services rather than standing alone.
- It is not a sealed binary SDK or a buyer-ready handoff.
- Building from source requires Xcode and Apple-platform development familiarity. Using the shipped app does not.
- Quality modes are not equally proven. Standard has a measured accuracy baseline; Deep Think and Maximum do not. See the Technical Limits below.

## Safety Limits

- It is not validated for regulated workflows.
- It is not intended for clinical, legal, financial, or safety-critical decision-making.
- It is not a clinical decision-support system.
- It is not a diagnostic tool.
- It does not guarantee complete, correct, or exhaustive answers.

## Technical Limits

- Retrieval quality depends on document quality, extraction quality, and query scope.
- OCR, layout parsing, chunking, and entity extraction can fail or lose context.
- Citations indicate supporting sources, not formal proof.
- Confidence signals are engineering aids, not certified reliability metrics.
- **Only Standard mode has a measured accuracy baseline:** 0.410 exact-match across 83 cases from 40 real research papers (QASPER), local-only. **Corrected 2026-08-21:** this read "80% across 20 ground-truthed cases with zero hallucinations" until that figure was withdrawn, because the run behind it averaged 7 seconds per case, under the 60-second threshold at which `BenchmarkRuns/PROGRESSION.md` flags generation as almost certainly not having run, and the corpus was synthetic and authored alongside its own questions. Exact-match is a floor, not a quality score. Deep Think and Maximum still have no valid figure; the one Deep Think run attempted scored 1 of 5 with a timeout at 1800s.
- **The repository cannot currently reproduce its own quality numbers.** `Docs/TestDocuments/` holds six small ingestion edge cases that test no answer quality, and `rag_validation_sample.json` points at a gitignored PDF. Building committed fixtures with external ground truth is tracked on the roadmap.
- Some Apple Intelligence or on-device model paths may depend on device, OS, and regional availability.
- Native PCC execution is owner-confirmed on a physical iOS 27 device running v4.6. Quota exhaustion, mid-stream network-transition fallback, background/App Intent consent behavior, and Archive/TestFlight distribution signatures were not part of that confirmation and remain unverified; source and simulator evidence cannot prove Apple's production route for them. `[evidence_level: user_confirmed+code_verified, confidence: high_for_execution_path_unverified_for_edge_scenarios, evidence_source: owner device testing 2026-07-28, ModelExecutionPlanner.swift, FoundationModelSessionFactory.swift, MessageBubbleV2.swift]`
- AFM 3 Core Advanced — Apple's 20B sparse on-device model announced at WWDC26 — is real, but it is OS-managed. Apple's public Foundation Models SDK exposes no way for an app to select it or to observe whether it (rather than the 3B Core model) served a request: the full public interface of `FoundationModels` in Xcode 27.0 beta (27A5194q) contains no advanced/tier selector, and `SystemLanguageModel` construction accepts only `.default`, a `UseCase` (`.general`/`.contentTagging` — a task selector, not a size selector), or a LoRA adapter. The app therefore labels the local route as On-Device rather than asserting a parameter count it cannot verify. `scripts/probe_afm_advanced_canary.sh` runs in CI and alerts the moment Apple exposes developer selection. `[evidence_level: sdk_verified+code_verified+externally_corroborated, confidence: exact_for_installed_sdk, evidence_source: full FoundationModels.swiftinterface enumeration 2026-07-28, Apple ML Research AFM-3 announcement, FoundationModelSessionFactory.swift, LLMModel.swift]`

## Demo Limits

Demo flows should use generic sample documents. Do not use private credentials, employer material, hospital-specific material, patient data, or sensitive personal data in public examples.
