# How OpenIntelligence Works

Version 2.0

This document explains the product workflow at a high level. It is intentionally written for users, reviewers, and collaborators who want to understand what the app does without exposing the full internal retrieval and reasoning design.

For the deeper engineering trace, see [Docs/Engineering/STORAGE_AND_PIPELINE_TRACE.md](./Docs/Engineering/STORAGE_AND_PIPELINE_TRACE.md).

## Workflow Overview

```text
Import documents -> Prepare them locally -> Search the right evidence -> Generate a cited answer
```

## 1. Import

OpenIntelligence accepts common document, text, image, and media formats from the iPhone/Mac file system and supported Apple share surfaces. Content is organized into libraries using a shared SQLite database with column-based `container_id` isolation. Libraries can remain Local Only or sync across Apple devices via iCloud Drive ubiquity sync (`WorkspaceSyncService`).

## 2. Prepare

After import, the app extracts text, tables, and structures, preparing content for search. Binary vector indices are generated locally using Core ML embeddings and written directly to local sandboxed vector databases via `BNNSVectorDatabase`. Clean digital text is processed via a conservative layout extractor, while scanned or noisy sources route through layout-aware Vision OCR.

## 3. Retrieve

When a user asks a question, OpenIntelligence searches the active library for the most relevant evidence, merging FTS5 lexical scores and vector similarity scores.

## 4. Answer

The app turns retrieved evidence into a readable response with citations. Standard RAG queries run locally on the 3B Core model, while escalated queries (Deep Think or Maximum mode) dynamically route to simulated Private Cloud Compute (PCC) enclaves running locally on `SystemLanguageModel.default`. conversational histories are stored durably inside isolated local JSON files (Evidence Threads) scoped to each container, rather than remaining ephemeral.


## 5. Review

Users can inspect the response, jump back to cited material, and evaluate whether the answer is grounded in the imported documents. For shared iCloud libraries, the Documents experience can also surface cross-device library additions or removals so the user can review whether to pull them in, keep local copies, or remove them here too.

## Design Principles

- Privacy-first user experience
- Native Apple platform integration
- Grounded answers over generic chat output
- Clear citations and source review
- Product reliability before public claims

## What Is Not Publicly Documented Here

This public overview does not include internal thresholds, scoring formulas, orchestration policies, evaluation methods, or optimization details for the engine.
