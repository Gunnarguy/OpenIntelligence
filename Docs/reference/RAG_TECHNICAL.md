# OpenIntelligence Technical Overview

> Archived reference snapshot. For current repo-grounded guidance, use [../RagTechnical.md](../RagTechnical.md).

This is the public technical overview for OpenIntelligence. It describes the product shape and engineering goals at a high level without exposing proprietary retrieval or reasoning details.

## Product Goals

- Keep document Q&A private and Apple-platform native
- Ground answers in user-provided material rather than generic chat behavior
- Support common work documents, notes, and media in one app experience
- Ship a product that stays understandable to users, not just engineers

## Public Workflow

1. Import documents into the app
2. Prepare them for local search and retrieval
3. Find relevant evidence when the user asks a question
4. Generate a readable answer with citations
5. Let the user inspect sources and decide whether the answer is trustworthy

## Public Stack Categories

| Area                   | Examples                                                     |
| ---------------------- | ------------------------------------------------------------ |
| UI and app experience  | SwiftUI, app navigation, onboarding, diagnostics             |
| Document understanding | Apple parsing, OCR, and media handling capabilities          |
| Local storage          | App-owned document libraries and supporting indexes          |
| Answer generation      | Apple platform intelligence features and answer presentation |
| Platform commerce      | StoreKit and app entitlement handling                        |

## What This Public Document Does Not Include

- Engine formulas and ranking logic
- Thresholds, weights, and confidence rules
- Multi-pass orchestration strategies
- Internal evaluation or benchmarking methods
- Hardware-specific optimization details

For a product-level overview, see [HOW_IT_WORKS.md](../../HOW_IT_WORKS.md) and [ARCHITECTURE.md](../../ARCHITECTURE.md).
