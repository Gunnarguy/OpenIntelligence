# How OpenIntelligence Works

Public snapshot: May 2026

This document explains the product workflow at a high level. It is intentionally written for users, reviewers, and collaborators who want to understand what the app does without exposing the full internal retrieval and reasoning design.

## Workflow Overview

```text
Import documents -> Prepare them locally -> Search the right evidence -> Generate a cited answer or refuse cleanly when support is weak
```

## 1. Import

OpenIntelligence accepts common document, text, image, and media formats from the iPhone file system and supported Apple share surfaces. The app organizes content into user-owned libraries so work stays scoped and manageable.

## 2. Prepare

After import, the app extracts text and structure, prepares content for search, and stores the resulting artifacts locally so future questions can be answered quickly. Preparation behavior adapts to the content type and document quality.

## 3. Retrieve

When a user asks a question, OpenIntelligence searches the imported material for the most relevant evidence and tries to surface supporting passages from the right documents before generating an answer.

## 4. Answer

The app turns retrieved evidence into a readable response with citations. Depending on device state and Apple platform availability, answer generation may stay fully on-device or use Apple-managed capabilities exposed by the platform. The product is designed to prefer grounded answers over polished guessing, so unsupported claims can be dropped before the final answer is shown.

## 5. Review

Users can inspect the response, jump back to cited material, and evaluate whether the answer is grounded in the imported documents. The review surface is part of the product, not an afterthought.

## Design Principles

- Privacy-first user experience
- Native Apple platform integration
- Grounded answers over generic chat output
- Clear citations and source review
- Explicit uncertainty when the evidence is not strong enough
- Product reliability before public claims

## What Is Not Publicly Documented Here

This public overview does not include internal thresholds, scoring formulas, orchestration policies, evaluation methods, or optimization details for the engine.
