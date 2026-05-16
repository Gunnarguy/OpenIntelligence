# How OpenIntelligence Works

Version 2.0

This document explains the product workflow at a high level. It is intentionally written for users, reviewers, and collaborators who want to understand what the app does without exposing the full internal retrieval and reasoning design.

For the deeper engineering trace, see [Docs/Engineering/STORAGE_AND_PIPELINE_TRACE.md](./Docs/Engineering/STORAGE_AND_PIPELINE_TRACE.md).

## Workflow Overview

```text
Import documents -> Prepare them locally -> Search the right evidence -> Generate a cited answer
```

## 1. Import

OpenIntelligence accepts common document, text, image, and media formats from the iPhone file system and supported Apple share surfaces. The app organizes content into user-owned libraries so work stays scoped and manageable. Each library can stay Local Only or be marked iCloud Drive, so shared libraries can move across the user's Apple devices without forcing everything into one global cloud mode.

## 2. Prepare

After import, the app extracts text, tables, figures, and other structure, prepares content for search, and stores the resulting artifacts locally so future questions can be answered quickly. Preparation behavior adapts to the content type, document quality, and visual complexity instead of relying on a user-selected ingestion mode. Clean digital text such as text files, markdown, code, CSV, transcripts, and native office-style documents is preserved more conservatively, while OCR-heavy, scanned, or visually noisy sources still use stronger cleanup and recovery.

## 3. Retrieve

When a user asks a question, OpenIntelligence searches the imported material for the most relevant evidence and tries to surface supporting passages from the right documents before generating an answer.

## 4. Answer

The app turns retrieved evidence into a readable response with citations. The engine is designed around Apple's public Foundation Models path where available and a small public session context, so it retrieves, compresses, and verifies evidence instead of trying to place an entire library into one prompt.

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
