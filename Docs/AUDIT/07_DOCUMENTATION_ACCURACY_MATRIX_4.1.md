# Phase 7: Documentation Accuracy Matrix — OpenIntelligence v4.1

This matrix details the accuracy and status of all existing documentation files in the OpenIntelligence repository. Verified for OpenIntelligence v4.1.

| Document | Purpose | Current Accuracy | Status | Required Action | Notes |
|---|---|---|---|---|---|
| `README.md` | Core landing page, onboarding, and build guide. | Contains inflated claims about Core AI and out-of-date billing limits. | `NEEDS_MAJOR_REWRITE` | Rewrite to be accurate and reflect current reality. | Must label Core AI as scaffolding and sync tier limits with StoreKit files. |
| `WHATS_NEW.md` | High-level summary of features added in v4.1. | Historical representation. | `HISTORICAL_REFERENCE` | Add historical header. | Retain for version context. |
| `CHANGELOG.md` | Historical log of development. | Historical representation. | `HISTORICAL_REFERENCE` | Add historical header. | Retain for history. |
| `Docs/ARCHITECTURE.md` | Software architecture overview. | Over-claims Core AI integration and lists some features as active which are stubs. | `NEEDS_MINOR_UPDATE` | Update to clarify stubs and add verification header. | Update Core AI descriptions to match literal code. |
| `Docs/RETRIEVAL_PIPELINE.md` | Details standard query, hybrid search, and ranking. | Factual description of search pipeline. | `VERIFIED_CURRENT_4.1` | Add standard verification header. | Solid description of vector + BM25 search. |
| `Docs/EVALS.md` | Benchmarks and evaluation results. | Factual details of testing harnesses. | `VERIFIED_CURRENT_4.1` | Add standard verification header. | Reference for RAG validation runs. |
| `Docs/AI_AGENT_MAP.md` | Details agentic modes (Deep Think, Maximum). | Accurate explanation of agent orchestration. | `VERIFIED_CURRENT_4.1` | Add standard verification header. | Details prompt compile flow and routing. |
| `Docs/DEMO.md` | Simple user demonstration walkthrough. | Outdated flow. | `HISTORICAL_REFERENCE` | Add historical header. | Bypassed by modern test harnesses. |
| `Docs/LIMITATIONS.md` | Initial list of model boundaries. | Superseded by modern analysis. | `SHOULD_ARCHIVE` | Archive. | Replaced by `Docs/KNOWN_LIMITATIONS_4.1.md`. |
| `Docs/RELEASE_NOTES.md` | Release history log. | Historical representation. | `HISTORICAL_REFERENCE` | Add historical header. | Retain for context. |
| `Docs/ROADMAP.md` | Future development direction. | Needs alignment with current stubs. | `NEEDS_MINOR_UPDATE` | Update to sync future plans. | Retain as future direction. |
| `Docs/SOCIAL_POST_TEMPLATES.md` | Draft marketing copy. | Outdated and contains overclaims. | `HISTORICAL_REFERENCE` | Add warning header. | Retain as reference only. |
| `Docs/TECHNICAL_CHANGELOG.md` | Engineering change logs. | Historical representation. | `HISTORICAL_REFERENCE` | Add historical header. | Retain for reference. |
| `Docs/USER_CHANGELOG.md` | User-facing changelog history. | Historical representation. | `HISTORICAL_REFERENCE` | Add historical header. | Retain for reference. |
| `Docs/AppleIntelligenceTransitionPlan.md` | Transition to system frameworks. | Historical architecture planning document. | `HISTORICAL_REFERENCE` | Add historical header. | Planning reference. |
| `Docs/Engineering/APPLE_DOCUMENT_INTELLIGENCE.md` | Technical notes on Apple Doc Intelligence. | Reference on framework APIs. | `HISTORICAL_REFERENCE` | Add historical header. | For reference. |
| `Docs/Engineering/APPLE_FM_TECH_REPORT_2025.md` | Analysis of Apple Foundation Models. | Reference on model capabilities. | `HISTORICAL_REFERENCE` | Add historical header. | For reference. |
| `Docs/Engineering/APPLE_MODELS.md` | Reference on system LLMs. | Reference on system LLMs. | `HISTORICAL_REFERENCE` | Add historical header. | For reference. |
| `Docs/Engineering/HARD_LIMITS.md` | Limits and billing rules. | Superseded by modern billing. | `SHOULD_ARCHIVE` | Archive. | Replaced by `Docs/BILLING_AND_LIMITS.md`. |
| `Docs/Engineering/PRIVATE_CLOUD_COMPUTE.md` | Private Cloud Compute Reference. | PCC framework API reference. | `HISTORICAL_REFERENCE` | Add historical header. | For reference. |
| `Docs/Engineering/RAG_TECHNICAL.md` | Technical RAG implementation. | Factual description of hybrid vector store. | `VERIFIED_CURRENT_4.1` | Add standard verification header. | Accurate technical detail. |
| `Docs/Engineering/STORAGE_AND_PIPELINE_TRACE.md` | SQLite schema and pipeline trace formats. | Factual description of trace structure. | `VERIFIED_CURRENT_4.1` | Add standard verification header. | Accurate technical detail. |
| `Docs/Research/` (all files) | Original research on on-device LLMs. | Theoretical/conceptual research from 2024–2026. | `HISTORICAL_REFERENCE` | Add historical headers to all files. | Retain for conceptual tracing. |
| `fastlane/metadata/en-US/release_notes.txt` | App Store release notes. | Marketing text. | `HISTORICAL_REFERENCE` | Review for compliance. | Check for overclaims. |
