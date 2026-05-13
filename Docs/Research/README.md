# Research Index

**Updated**: April 24, 2026

This folder keeps the source links and implementation mapping separate from the main docs. The intent is to keep the public-facing docs readable while preserving evidence for the technical notes and architecture references.

## Files

- [RAG and Retrieval 2024-2026](./RAG_AND_RETRIEVAL_2024_2026.md): hybrid retrieval, RAPTOR, GraphRAG, LightRAG, corrective retrieval, contextual retrieval, and RAG evaluation.
- [CAG and Context Engineering 2024-2026](./CAG_AND_CONTEXT_ENGINEERING_2024_2026.md): Cache-Augmented Generation and why it is a limited fit under Apple FoundationModels' current public context window.
- [Apple Intelligence and Foundation Models](./APPLE_INTELLIGENCE_AND_FOUNDATION_MODELS.md): Apple Foundation Models, `LanguageModelSession`, `SystemLanguageModel`, tool calling, guided output, token budgets, and PCC boundaries.
- [Core ML, Metal, and On-Device AI](./COREML_METAL_ON_DEVICE_AI.md): Core ML compute units, Metal/MPS, Accelerate/BNNS/vDSP, and model compression.
- [Document Intelligence and OCR](./DOCUMENT_INTELLIGENCE_AND_OCR.md): Vision OCR, document recognition, PDFKit, Natural Language, and document parsing.

## Repo Mapping

- Generation: `OpenIntelligence/Services/LLM/LLMService.swift`
- Main orchestration: `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift`
- Verification: `OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift`
- Document processing: `OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift`
- Full-text storage: `OpenIntelligence/Services/Storage/SQLiteFullTextService.swift`
- Vector storage: `OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift`, `VectorStoreRouter.swift`
- Public SDK surface: `OpenIntelligence/SDK/OpenIntelligenceEngine.swift`
