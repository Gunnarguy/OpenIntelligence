# Document Intelligence and OCR Research

**Updated**: April 24, 2026
**Use in this repo**: Supports document parsing, OCR, page structure, and local text understanding claims.

## Primary Sources

| Area | Source | Why It Matters for OpenIntelligence |
| --- | --- | --- |
| Structured document recognition | [RecognizeDocumentsRequest](https://developer.apple.com/documentation/vision/recognizedocumentsrequest) | Apple's newer Vision API for document structure, including words, lines, paragraphs, tables, and lists. |
| OCR | [VNRecognizeTextRequest](https://developer.apple.com/documentation/vision/vnrecognizetextrequest) | Current OCR path used by the repo for text observations and confidence. |
| PDF parsing | [PDFDocument](https://developer.apple.com/documentation/pdfkit/pdfdocument) | Native source for reading PDFs, page counts, selections, and text layers. |
| Natural Language | [Natural Language](https://developer.apple.com/documentation/naturallanguage) | Tokenization, language detection, tagging, named entities, and embeddings. |
| Embeddings | [NLEmbedding](https://developer.apple.com/documentation/naturallanguage/nlembedding) | Apple's local word/sentence embedding API where it meets product needs. |
| Contextual retrieval | [Anthropic: Contextual Retrieval](https://www.anthropic.com/research/contextual-retrieval) | Practical external reference for adding document/section context to chunks before retrieval. |
| Heterogeneous tables | [TableRAG: A RAG Framework for Heterogeneous Document Reasoning](https://arxiv.org/abs/2506.10380) | Shows why flattening tables can lose row/column structure and hurt multi-hop document QA. |

## Repo Mapping

- `DocumentProcessor.swift` uses PDFKit text extraction first when reliable.
- It detects garbled text layers and can force Vision OCR when the PDF text layer is not trustworthy.
- It stores page text separately to support page-level context and exact lookups.
- It reconstructs layout for multi-column and table-heavy OCR pages.
- `OCRConfiguration.swift` centralizes Vision OCR settings and custom vocabulary.
- `SQLiteFullTextService.swift` keeps full document, page, and chunk-level FTS5 indexes.

## Best Current Claim

> OpenIntelligence combines PDFKit text extraction, Vision OCR fallback, layout-aware cleanup, local full-text search, and semantic chunking to make private documents queryable on-device.

## Future Upgrade Path

Evaluate `RecognizeDocumentsRequest` for table/list-heavy documents where deployment target and API availability allow it. The current repo still relies heavily on `VNRecognizeTextRequest`, custom layout reconstruction, and OCR confidence handling, which is defensible but should be tested on the buyer's actual PDFs and scans.

For table-heavy manuals and medical-device documents, the next evaluation should measure whether the current flattened text plus FTS5/BM25 path preserves row/column relationships well enough. If not, add a table-aware representation before claiming robust tabular reasoning.
