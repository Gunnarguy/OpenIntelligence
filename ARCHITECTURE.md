# OpenIntelligence Public Architecture

Public snapshot: May 2026

This repository is structured as a public product surface, not as the private
engine source tree.

## High-Level Layout

```text
App Store product
    -> Private OpenIntelligence engine
        -> Controlled privately in OpenIntelligence-Engine

Public GitHub repo
    -> SwiftUI demo shell
    -> Public docs, privacy notes, release history, roadmap
    -> Engine overview without proprietary implementation
```

## What Lives Here

| Layer            | Purpose                                                         |
| ---------------- | --------------------------------------------------------------- |
| Demo app shell   | A lightweight SwiftUI app that communicates the product story   |
| Public docs      | README, architecture, workflow, privacy, and release materials  |
| Build support    | Public-safe build workflows and helper scripts                  |

The Xcode project in this repo is intentionally scoped to the public demo app.
It should open cleanly for visitors without implying that the private engine
framework is available here.

## Public Engine Model

At a public level, OpenIntelligence is organized around these responsibilities:

```text
Import
    -> document understanding
        -> library-scoped indexing
            -> retrieval
                -> grounded answer generation
                    -> source review and uncertainty handling
```

The private repo owns the implementation details behind those boxes.

## What Does Not Live Here

The following remain private in `OpenIntelligence-Engine`:

- ingestion internals
- chunking and extraction strategy
- retrieval and reranking logic
- verification and trust heuristics
- embedding and vector search implementation
- SDK packaging and buyer packet material
- App Store submission and release-ops tooling

## Repository Boundary

This repo is intentionally generated from a private source-of-truth workflow.

The private repo is authoritative.
The public repo is a curated export target.

That boundary is part of the product strategy: the public repo should create
confidence and explain the engine, while the private repo preserves the
implementation that matters in an acquisition or licensing discussion.
