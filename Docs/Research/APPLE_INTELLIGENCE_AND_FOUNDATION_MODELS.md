# Apple Intelligence and Foundation Models Research

**Updated**: April 24, 2026
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

## Unsafe Claims

- "We have direct access to Apple's PCC server model."
- "We get 65K context through FoundationModels."
- "Apple Foundation Models provide embeddings for this app."
- "PCC makes this HIPAA compliant."
- "The model is guaranteed correct because it runs on-device."

## Implementation Consequence

The product architecture should stay retrieval-first. Apple's public framework is powerful enough for concise grounded synthesis, tool decisions, and structured output, but the context limit makes chunking, retrieval, compression, and verification mandatory for serious document QA.
