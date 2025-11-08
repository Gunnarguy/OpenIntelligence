# Project Roadmap – OpenIntelligence AI Modernization (Apple 2025 + MLX)

Last updated: 2025-10-29

## Vision
Deliver a first-class, privacy-forward RAG assistant on Apple platforms that:
- Prioritizes on‑device intelligence (Apple Foundation Models, WritingTools)
- Seamlessly falls back to Private Cloud Compute when beneficial
- Offers local open models via MLX on macOS
- Supports custom Core ML models for enterprises
- Provides transparent telemetry and capability diagnostics

## High-level Goals
- Apple Intelligence-first UX (on-device by default; PCC with zero-retention)
- Pluggable model backends (Apple FM, ChatGPT Extension, OpenAI, MLX Local, Core ML Local, On-Device Analysis)
- Robust, on-device embeddings with provider abstraction (NLEmbedding + Core ML sentence encoders)
- Strong privacy posture and clear execution-location surfacing (On‑Device vs PCC vs Cloud)
- Great performance and responsiveness (background compute off main; warm-ups; caching)

## Milestones and Tasks
- [x] Backend abstraction for embeddings
  - [x] Introduce EmbeddingProvider protocol
  - [x] Implement NLEmbeddingProvider (512-dim word-avg parity)
  - [x] Refactor EmbeddingService to delegate to provider
  - [x] Add Apple FM embedding provider scaffold (awaiting public API; currently unavailable)
  - [ ] Add Core ML sentence encoder provider (implement tokenization/IO)
  - [ ] Add index namespacing + re-embed workflow for dimension changes
- [x] LLM backends and Settings wiring
  - [x] Extend LLMModelType with mlxLocal and coreMLLocal
  - [x] Add MLXLocalLLMService (macOS-only, local server bridge)
  - [x] Wire new backends into SettingsView picker and pipeline stages
  - [ ] CoreMLLLMService: complete tokenization/input-output mapping for one model
  - [x] Add tool-call accounting in AppleFoundationLLMService (agentic RAG metrics)
- [ ] Writing and authoring features
  - [x] Integrate WritingTools into chat composer (query clarify pass; rewrite/summarize/tone TBD)
  - [ ] Provide fallbacks when WritingTools unavailable
- [ ] Speech and multimodal
  - [ ] ASR with SFSpeechRecognizer for voice prompts
  - [ ] TTS with AVSpeechSynthesizer for responses
  - [ ] VisionKit document scanner + upgraded OCR (VNRecognizeTextRequest v3)
- [ ] App Intents and shortcuts
  - [ ] SummarizeClipboardIntent, AskAboutDocumentIntent, QuickAnswerIntent
  - [ ] Polish ChatGPT Extension pathways when entitlements available
- [ ] Telemetry, privacy, diagnostics
  - [ ] TelemetryCenter: backendUsed, executionLocation, TTFT, tokens/sec, toolCallsMade
  - [x] Capability diagnostics surfaces “why unavailable” and actionable tips (initial iOS GGUF gating help + sheet)
  - [ ] UI badge for execution location (📱 On‑Device / ☁️ PCC / 🔑 OpenAI / 🖥️ MLX)

## Completion Criteria
- End users can select among Apple Intelligence, MLX Local (macOS), Core ML Local, OpenAI Direct, and On‑Device Analysis
- Apple FM execution hybrid behavior visible (TTFT-based detection + UI badges)
- Embeddings provider switchable; Core ML sentence encoder option available
- WritingTools available in composer; reasonable fallbacks when not present
- Voice in/out supported; document scan and OCR ingestion work smoothly
- Diagnostics explain unavailability with remediation suggestions
- All processing clearly labeled for privacy: On‑Device vs PCC vs Cloud

## Progress Tracker (Snapshot)
- Embeddings: 3/5
- LLM Backends: 4/5
- Writing/Authoring: 1/2
- Speech/Multimodal: 0/3
- Intents: 0/2
- Telemetry/Diagnostics: 1/3

## Completed Tasks (History)
- 2025-11-04
  - iOS GGUF diagnostics: added Benchmark button and TTFT/tok/s readout
  - Settings: “Why Unavailable?” detail sheet for model gating with remediation (iOS GGUF, Core ML, Apple Intelligence)
  - User guide: userInstructions/ios-gguf-local-setup.md for linking LocalLLMClient and activating GGUF Local
- 2025-10-30
  - Strict Mode enforcement for high-stakes containers:
    - Similarity threshold ≥ 0.52 and minimum supporting chunks ≥ 3
    - MMR λ = 0.75 to slightly favor relevance over diversity
    - Generation temperature capped at 0.2 under strict mode
    - Cautious non-answer path with top source citations when insufficient evidence
  - UI: Added Strict Mode badge in Response Details
- 2025-10-29
  - Platform-gating and DSColors pass across Settings, Model Management, Diagnostics, Telemetry, Documents, and legacy ChatView
  - Fixed ChatView macOS build blockers (iOS-gated navigationBarTitleDisplayMode, macOS .automatic toolbar placement)
  - Verified macOS Debug build via xcodebuild (2025-10-29)
  - ChatV2 live visualization and streaming UX:
    - StageProgressBar per-stage timers + subtle shimmer
    - PipelineOverlayView behind chat with animated flow and stage pulses
    - LiveCountersStrip (TTFT, tokens, tok/s, retrieved chunks)
    - RetrievalSourcesTray with live source chips and details sheet
    - TokenCadenceView integrated alongside TypingIndicator
    - Event ribbon toasts for milestones and TTFT
    - ExecutionBadge indicates On-Device vs PCC via TTFT heuristic
  - iOS Simulator Debug build succeeded (iPhone 16, iOS 26.0.1) via xcodebuild
  - Updated cline_docs/currentTask.md to record status
  - Removed legacy Chat/ChatView.swift and unified on ChatV2 (2025-10-29)
- 2025-10-28
  - Added EmbeddingProvider abstraction and NLEmbeddingProvider
  - Refactored EmbeddingService to provider-based design
  - Scaffolded CoreMLSentenceEmbeddingProvider (IO pending)
  - Implemented MLXLocalLLMService (macOS-only, OpenAI-style bridge)
  - Extended LLMModelType with mlxLocal/coreMLLocal; wired into SettingsView
  - Expanded Settings pipeline stages to show MLX/Core ML status

## Notes
- Apple Foundation Models API requires iOS 26+ and eligible hardware; PCC is zero-retention
- MLX Local runs only on macOS and is designed for private, on-machine inference
- Core ML LLM path requires a known model signature and tokenizer
- Index dimension changes require re-embed or namespacing to avoid cosine mismatch
