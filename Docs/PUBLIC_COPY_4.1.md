# Docs/PUBLIC_COPY_4.1.md — OpenIntelligence v4.1

> **Documentation status:** Verified for OpenIntelligence v4.1 on 2026-06-13.
> **Source of truth:** Codebase audit in `Docs/AUDIT/`.

This document contains approved marketing, social, and developer copy for OpenIntelligence v4.1. I compiled these templates to ensure all public communications remain accurate and aligned with the codebase reality.

---

## 1. App Store Copy

### Short Description (Up to 170 characters)
> Private, on-device document assistant. Import PDFs and text documents to search, analyze, and query locally using hybrid vector search and on-device Core ML rerankers.

### Long Description
> OpenIntelligence is a local-first, privacy-respecting document assistant built for macOS and iOS. I designed the app to keep your data entirely on your device. It processes documents, extracts text, runs OCR, and handles queries without sharing information with third-party servers.
>
> KEY FEATURES:
> - **Local OCR & Ingestion:** Uses system Vision frameworks to extract text from PDFs and documents on your device.
> - **Hybrid Vector Search:** Combines vector embeddings and BM25 full-text indexing locally.
> - **On-Device Reranking:** Leverages Core ML cross-encoder models to improve search accuracy, with dynamic heuristics fallback.
> - **Verification Layer:** Calibrates answer confidence using contradiction filters and negation sweeps to prevent unsupported claims.
> - **StoreKit 2 Quotas:** Free users can import up to 5 documents. Upgrade to Pro (1,000 documents) or Lifetime (unlimited documents) directly.
>
> PRIVACY POLICIES:
> All text extraction, vector databases, and query generations execute locally.

---

## 2. GitHub & Developer Platforms

### Repository Description (GitHub About Section)
> Private, on-device document search and chat assistant for macOS/iOS using local Core ML embeddings, hybrid BM25 full-text search, on-device reranking, and verification gates.

### README Intro
> OpenIntelligence is a private, on-device document analysis tool for Apple platforms. By leveraging local Core ML embeddings, hybrid search via SQLite FTS, and on-device reranking, I built this app to let you query personal document libraries without uploading data to third-party APIs.

### Reddit - r/Swift or r/iOSProgramming Post
> **Title:** Show r/Swift: OpenIntelligence — A local-first, on-device document assistant using Core ML and SQLite FTS
>
> I built OpenIntelligence, a private document assistant for macOS and iOS. It runs the entire retrieval-augmented generation (RAG) pipeline locally on your device.
>
> **Under the Hood:**
> - **Retrieval:** Combines Cosine Similarity vector search with BM25 full-text queries in SQLite, merged using Reciprocal Rank Fusion (RRF).
> - **On-Device Reranking:** Uses local Core ML cross-encoder models for scoring, with a proximity-based fallback if the model isn't bundled.
> - **Verification:** Employs negation checks and overlap sweeps to calibrate answer confidence and trigger refusals when evidence is insufficient.
> - **StoreKit 2 Integration:** Enforces local tier limits (5 docs for Free, 1,000 for Pro, unlimited for Lifetime) via active receipt verification.
>
> I’ve disabled future Core AI scaffolding behind `#if false` compiler checks and simulated remote PCC routes locally using system language models to ensure the current App Store build compiles and runs entirely on-device.

---

## 3. Social Media & Outreach

### X / Bluesky Post
> I built OpenIntelligence, a private document assistant for macOS/iOS. Features:
> - Local Vision-based OCR & Ingestion
> - Hybrid vector + BM25 search
> - On-device Core ML reranker with heuristic fallback
> - Negation-based verification gates
> 
> Try it out: [Link]

### LinkedIn Comment Template (Factual Verification Reply)
> I run on-device Core ML cross-encoder reranking by default, but I’ve built in heuristic fallback scoring (using term proximity and BM25 metadata boosts) for cases where the weights are omitted to control bundle size. The contradiction sweeps and negation checks calibrate confidence before displaying cited answers.

### DM Reply Template (Vik or other developers)
> Hi Vik, thanks for the feedback on the verification layers. The contradiction sweeps currently use a lexical negation search and word-overlap check to adjust the final confidence score, which runs in parallel with the on-device Core ML reranking. If the reranker model is missing, it falls back to a term-proximity algorithm. Let me know if you want to swap notes on on-device RAG parameters!
