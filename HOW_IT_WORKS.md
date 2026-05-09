# How This Public Demo Repo Works

Public snapshot: May 2026

This repo is the public surface for OpenIntelligence. It is designed to answer
the first question a visitor has after seeing the App Store listing or
SideProjectors page: "What is this, and what is private?"

## Public Evaluation Flow

```text
Install the app
    -> understand the engine at a public level
        -> inspect privacy, roadmap, and release history
            -> request private diligence only if there is real buyer interest
```

## What You Can Learn Here

1. What the product is trying to do.
2. How the public trust model is framed.
3. What the user-facing experience looks like.
4. What the private engine does at a high level.
5. Why the full source is not published in this repo.

## Public Product Workflow

The shipped product is organized around a grounded document Q&A loop:

1. Users import documents or document-like material.
2. The private engine prepares that material for retrieval.
3. Questions retrieve source-backed evidence before answer generation.
4. Answers are presented with review affordances instead of behaving like generic chat.
5. Users inspect sources, uncertainty, and supporting context when trust matters.

## What Is Intentionally Not Shipped Here

This repo does not expose the private engine implementation.

That includes:

- ingestion internals
- retrieval internals
- verification heuristics
- embedding and vector search code
- SDK packaging and commercialization materials
- App Store submission and release-ops tooling

Those stay in `OpenIntelligence-Engine`.

## Public Repo Role

This repository is a product-facing demo and documentation surface. The SwiftUI
app in this repo is a public shell for communication and build verification.

It is not the full private working tree.
It is also not the repo used for App Store submission.

## Where To Go Next

- Read [ENGINE_OVERVIEW.md](ENGINE_OVERVIEW.md) for the engine story.
- Read [ARCHITECTURE.md](ARCHITECTURE.md) for the public/private boundary.
- Install the real app from the App Store link in [README.md](README.md).
- Use the SideProjectors listing or maintainer contact path for serious diligence.
