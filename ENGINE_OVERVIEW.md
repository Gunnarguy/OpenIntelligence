# OpenIntelligence Engine Overview

Public snapshot: May 2026

This document explains what the OpenIntelligence engine is without exposing the
private implementation. It is written for people evaluating the product from the
App Store, SideProjectors, or this public GitHub repo.

## Plain-English Summary

OpenIntelligence is a private document intelligence engine wrapped in a native
Apple app. The engine turns a user's documents into an inspectable question and
answer workspace: documents go in, evidence is extracted and indexed, questions
retrieve relevant support, and answers are shown with source-aware review.

The point is not generic chat. The point is grounded answers over material the
user controls.

## Engine Responsibilities

The private engine handles the parts that make the app more than a thin UI:

| Layer | Public description |
| --- | --- |
| Ingestion | Accepts user documents and prepares them for search and reasoning. |
| Document understanding | Preserves useful text, layout, tables, figures, and OCR-derived evidence where supported. |
| Library isolation | Keeps user material organized into app-owned libraries instead of mixing every document into one global space. |
| Indexing | Builds retrieval structures over document evidence so the app can find support later. |
| Retrieval | Selects relevant passages, table rows, figure context, or nearby support for a question. |
| Answer generation | Produces readable answers that are intended to stay tied to retrieved evidence. |
| Verification and review | Helps avoid overconfident unsupported answers and gives users source material to inspect. |
| Apple-platform integration | Uses the native app lifecycle, privacy controls, device capabilities, and Apple intelligence pathways where appropriate. |

## Why It Matters

The engine is valuable because hard document Q&A is not just one model call.
Useful results depend on the full pipeline:

- messy imports need cleanup before they can be searched;
- tables, measurements, counts, dates, and prices need exact-value handling;
- long documents need retrieval before generation;
- generated answers need conservative support checks;
- users need a way to inspect why an answer appeared;
- privacy posture has to be part of the product, not an afterthought.

OpenIntelligence is built around that pipeline.

## What The Public Repo Shows

This public repo shows:

- the product story;
- a lightweight SwiftUI demo shell;
- the public architecture boundary;
- privacy and release notes;
- public reference material;
- a link to the App Store product.

It intentionally does not show private ranking logic, thresholds, prompts,
verification heuristics, indexing details, commercial diligence material, or
the buyer-facing engine package.

## Evaluation Path

The normal public evaluation path is:

1. Install the shipped app from the App Store.
2. Review this repo to understand the product and boundary.
3. Use the SideProjectors listing or maintainer contact path for acquisition or diligence discussion.
4. Move private engine review, SDK packaging, and internal materials into a controlled diligence process.

This keeps the public surface useful while protecting the actual implementation
that would matter in a sale.
