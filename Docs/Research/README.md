> **Documentation status, 2026-09-29:** An index of research notes, not a description of the shipped app. The code is the source of truth, and `Docs/SHIPPED_VERSION.json` records which version is live. The file list below was completed on this date against `git ls-files Docs/Research`; it had listed five of the ten files besides this one. This line replaces a banner written for v4.1 on 2026-06-13.

# Research Index

**Updated**: 2026-09-29 (file list); first written April 24, 2026

This folder keeps the source links and implementation mapping separate from the main docs. The intent is to keep the public-facing docs readable while preserving evidence for the technical notes and architecture references.

## Files

- [RAG and Retrieval 2024-2026](./RAG_AND_RETRIEVAL_2024_2026.md): hybrid retrieval, RAPTOR, GraphRAG, LightRAG, corrective retrieval, contextual retrieval, and RAG evaluation.
- [CAG and Context Engineering 2024-2026](./CAG_AND_CONTEXT_ENGINEERING_2024_2026.md): Cache-Augmented Generation and why it is a limited fit under Apple FoundationModels' current public context window.
- [Apple Intelligence and Foundation Models](./APPLE_INTELLIGENCE_AND_FOUNDATION_MODELS.md): Apple Foundation Models, `LanguageModelSession`, `SystemLanguageModel`, tool calling, guided output, token budgets, and PCC boundaries.
- [Core ML, Metal, and On-Device AI](./COREML_METAL_ON_DEVICE_AI.md): Core ML compute units, Metal/MPS, Accelerate/BNNS/vDSP, and model compression.
- [Document Intelligence and OCR](./DOCUMENT_INTELLIGENCE_AND_OCR.md): Vision OCR, document recognition, PDFKit, Natural Language, and document parsing.
- [Research Papers Reference Sheet](./RESEARCH_PAPERS_REFERENCE_SHEET.md): the bibliography. Maps each retrieval, extraction, sampling and Apple-silicon feature to its paper or Apple document and to the Swift files that implement it.
- [Embedding and Ingestion Upgrade Assessment, August 2026](./EMBEDDING_AND_INGESTION_UPGRADE_2026-08.md): the research basis for `Docs/Engineering/RETRIEVAL_UPGRADE_PLAN_2026-08.md`. Surveys the ingestion, embedding and SQLite stack as shipped in v4.9 and lists the upgrades worth doing, with sources.
- [Audio Study Guide, Version 2](./AUDIO_STUDY_GUIDE_V2_TERRA_2026-08-27.md): a long-form listening guide to the 612-concept word bank, checked 2026-08-27. `Docs/STUDY_GUIDE.md` takes its definitions from it.
- [Audio Study Guide text-to-speech pack](./AUDIO_STUDY_GUIDE_V2_TTS_PACK_2026-08-27.zip): the same guide split into numbered text files for text-to-speech apps.
- [How OpenIntelligence Works, Opus walkthrough](./HOW_OPENINTELLIGENCE_WORKS_OPUS_2026-08-22.txt): a plain-text export of the 2026-08-22 walkthrough. `Docs/STUDY_GUIDE.md` takes its reasons from it.

## Repo Mapping

- Generation: `OpenIntelligence/Services/LLM/LLMService.swift`
- Main orchestration: `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift`
- Verification: `OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift`
- Document processing: `OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift`
- Full-text storage: `OpenIntelligence/Services/Storage/SQLiteFullTextService.swift`
- Vector storage: `OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift`, `VectorStoreRouter.swift`
- Public SDK surface: `OpenIntelligence/SDK/OpenIntelligenceEngine.swift`
