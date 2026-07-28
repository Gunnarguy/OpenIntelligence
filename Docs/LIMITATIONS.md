# Limitations

OpenIntelligence is experimental software. It is useful as a proof-of-work repository and prototype, but it should be evaluated with clear limits.

## Product Limits

- It is not production-ready.
- It is not a commercial product offering.
- It is not a finished enterprise SDK.
- It is not a sealed binary SDK.
- It is not a buyer-ready handoff.
- Setup may require Xcode and Apple-platform development familiarity.

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
- Some Apple Intelligence or on-device model paths may depend on device, OS, and regional availability.
- Native PCC execution is owner-confirmed on a physical iOS 27 device running v4.6. Quota exhaustion, mid-stream network-transition fallback, background/App Intent consent behavior, and Archive/TestFlight distribution signatures were not part of that confirmation and remain unverified; source and simulator evidence cannot prove Apple's production route for them. `[evidence_level: user_confirmed+code_verified, confidence: high_for_execution_path_unverified_for_edge_scenarios, evidence_source: owner device testing 2026-07-28, ModelExecutionPlanner.swift, FoundationModelSessionFactory.swift, MessageBubbleV2.swift]`
- Apple's public Foundation Models SDK does not expose separately selectable 3B or 20B on-device identities. The app therefore labels the local route as On-Device rather than asserting a parameter count. `[evidence_level: sdk_verified+code_verified, confidence: exact, evidence_source: FoundationModelSessionFactory.swift, LLMModel.swift]`

## Demo Limits

Demo flows should use generic sample documents. Do not use private credentials, employer material, hospital-specific material, patient data, or sensitive personal data in public examples.
