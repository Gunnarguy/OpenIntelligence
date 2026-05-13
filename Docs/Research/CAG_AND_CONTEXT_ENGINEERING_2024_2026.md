# CAG and Context Engineering Research 2024-2026

**Updated**: April 24, 2026
**Use in this repo**: CAG is useful as a narrow optimization, not the core architecture.

## Primary Sources

| Area | Source | Why It Matters for OpenIntelligence |
| --- | --- | --- |
| Cache-Augmented Generation | [Don't Do RAG: When Cache-Augmented Generation is All You Need for Knowledge Tasks](https://arxiv.org/abs/2412.15605) | Shows CAG can beat or complement RAG when the knowledge base is limited and can fit in an extended context. |
| Apple context limit | [TN3193: Managing the on-device foundation model's context window](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window) | Apple documents a 4096-token context window for each on-device FoundationModels session. |
| FoundationModels sessions | [LanguageModelSession](https://developer.apple.com/documentation/foundationmodels/languagemodelsession) | Session state, transcript reuse, tools, and guided generation all consume context. |
| Contextual retrieval | [Anthropic: Contextual Retrieval](https://www.anthropic.com/research/contextual-retrieval) | Better fit for this app than whole-corpus CAG: add concise context to chunks, retrieve dynamically, rerank, then generate. |

## PDF Links

- Cache-Augmented Generation: https://arxiv.org/pdf/2412.15605

## Practical Reading

CAG is compelling when:

- The whole knowledge base is small.
- The model has a long context window.
- The cached prompt/runtime state can be reused across many related questions.
- Avoiding retrieval latency matters more than dynamic corpus scale.

OpenIntelligence's public Apple FoundationModels path is different:

- The session budget is 4096 tokens.
- Tool schemas, prompts, retrieved context, responses, and `@Generable` schemas all consume the same budget.
- User libraries can contain many documents and pages.
- The product requirement is cited source inspection, not just fast recall.

## Repo-Appropriate CAG Uses

Good uses:

- Tiny "library memo" summaries for active-container starter questions.
- Session handoff summaries when continuing a conversation.
- Cached document summaries for overview routing.
- Precomputed glossary/abbreviation tables for technical manuals.

Bad uses:

- Loading an entire customer library into one FoundationModels session.
- Claiming CAG replaces retrieval for large PDFs/manuals.
- Using cached summaries as evidence without source-span citations.

## Repository Position

In public-facing docs, say:

> OpenIntelligence uses retrieval for the evidence path and cache-like summaries for routing and continuity. It does not depend on a long-context cloud model to hold private documents in memory.
