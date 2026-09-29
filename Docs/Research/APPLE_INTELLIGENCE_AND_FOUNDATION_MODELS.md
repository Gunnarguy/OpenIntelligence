> **Documentation status:** Historical reference, re-dated 2026-09-29, when its Private Cloud Compute rows were corrected against the 5.5 tree. Everything else still reflects April 24, 2026 and was not re-checked. For how the app routes to PCC today, [`Docs/PRIVACY_AND_ROUTING.md`](../PRIVACY_AND_ROUTING.md) is authoritative. Until 2026-09-29 this line said only that the file was historical and not the source of truth for OpenIntelligence v4.1.

# Apple Intelligence and Foundation Models Research

**Updated**: April 24, 2026; Private Cloud Compute rows corrected 2026-09-29
**Use in this repo**: Defines what the app can safely claim about Apple Foundation Models, tool calling, structured generation, and Private Cloud Compute.

## Primary Sources

| Area | Source | Why It Matters for OpenIntelligence |
| --- | --- | --- |
| Framework overview | [Foundation Models](https://developer.apple.com/documentation/FoundationModels) | Apple's public framework for on-device language generation, structured output, and tool calling. |
| Session API | [LanguageModelSession](https://developer.apple.com/documentation/foundationmodels/languagemodelsession) | The app's generation path maps to sessions, tools, transcripts, and guided generation. |
| Model availability | [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel) | Availability depends on Apple Intelligence support, Settings state, and model readiness. |
| Context budget | [TN3193: Managing the on-device foundation model's context window](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window) | Hard source for 4096-token budgeting and why tools/schemas consume context. |
| Apple 2025 model report | [Apple Intelligence Foundation Language Models Tech Report 2025](https://machinelearning.apple.com/research/apple-foundation-models-tech-report-2025) | Source for the model family: on-device model, server model, quantization, tool calling, and responsible AI framing. |
| 2024/2025 Apple model research page | [Apple Intelligence Foundation Language Models](https://machinelearning.apple.com/research/apple-intelligence-foundation-language-models) | Background on Apple Intelligence model design and first-party features. |
| PCC architecture | [Private Cloud Compute: A new frontier for AI privacy in the cloud](https://security.apple.com/com/blog/private-cloud-compute/) | Official PCC security architecture and transparency properties. |
| PCC research tools | [Security research on Private Cloud Compute](https://security.apple.com/blog/pcc-security-research/) | Source for public verification tooling and transparency log research workflow. |
| PCC in Foundation Models (added 2026-09-29) | [Adding server-side intelligence with Private Cloud Compute](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute) | `PrivateCloudComputeLanguageModel`, iOS/macOS 27.0 and later. Apple's capability table gives PCC a 32K context against 4K on device, multiple reasoning levels, a daily usage limit, and no offline use. Fetched 2026-09-29. |

## Paper Links

- Apple Intelligence Foundation Language Models Tech Report 2025: https://arxiv.org/pdf/2507.13575

## Repo Mapping

- `LLMService.swift` uses `LanguageModelSession` and keeps `contextWindowSize = 4096`.
- `RAGService.swift` disables tools when retrieved context is already assembled to reclaim tool-schema tokens.
- `RAGStructuredResponse.swift` uses `@Generable` structured output.
- `OpenIntelligenceEngine.swift` exposes availability states for simulator unsupported, unsupported device, Apple Intelligence disabled, model preparing, and unavailable.

## Safe Claims

- The app uses Apple's public Foundation Models framework for on-device generation where available.
- The model supports text generation, summarization, extraction, tool calling, and guided Swift data output through the framework.
- The app is designed around Apple's published 4096-token session budget.
- The app checks Apple Intelligence availability before using the engine.
- PCC is Apple's privacy architecture for Apple Intelligence cloud compute, not an OpenIntelligence-owned backend.
- Since 5.2, on iOS/macOS 27, the app can send the final answer step to Apple's server model through the framework's `PrivateCloudComputeLanguageModel`, after consent and within Apple's daily limit; ingestion, indexing, retrieval and ranking stay on device. Added 2026-09-29. `[evidence_level: code_verified, confidence: exact, evidence_source: FoundationModelSessionFactory.swift:86-102]` `[evidence_level: artifact_derived, confidence: high, evidence_source: Docs/SHIPPED_CAPABILITIES.json:100-108; Docs/PRIVACY_AND_ROUTING.md:7,116]`

## Unsafe Claims

- ~~"We have direct access to Apple's PCC server model."~~ Corrected 2026-09-29: no longer unsafe as a bare statement, because since 5.2 the app calls `PrivateCloudComputeLanguageModel` directly on iOS/macOS 27 (the Safe Claims entry above). What stays unsafe is claiming more control than that API gives:
  - "We choose which Apple server model answers." The FoundationModels SDK declares one server model class, and a response declares no field naming the backend that produced it.
  - "PCC is always available." It needs iOS/macOS 27, the network, the signed entitlement, Apple's availability and daily quota, and the user's consent.

  `[evidence_level: code_verified, confidence: exact, evidence_source: FoundationModelSessionFactory.swift:86-102; FoundationModels.swiftinterface:45,98,260,295 (the only LanguageModel conformances) and 1968-1975 (Response members) in the iPhoneOS SDK of Xcode 27.0 (27A266a)]` `[evidence_level: artifact_derived, confidence: high, evidence_source: Docs/PRIVACY_AND_ROUTING.md:84-107]`
- "We get 65K context through FoundationModels."
- "Apple Foundation Models provide embeddings for this app."
- "PCC makes this HIPAA compliant."
- "The model is guaranteed correct because it runs on-device."

## Implementation Consequence

The product architecture should stay retrieval-first. Apple's public framework is powerful enough for concise grounded synthesis, tool decisions, and structured output, but the context limit makes chunking, retrieval, compression, and verification mandatory for serious document QA.
