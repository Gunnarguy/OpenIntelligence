<a href='https://www.sideprojectors.com/project/78816/openintelligence' alt='OpenIntelligence is for sale at @SideProjectors'><img style='position:fixed;z-index:1000;top:-5px; right: 20px; border: 0;' src='https://www.sideprojectors.com/img/badges/badge_2_red.png' alt='OpenIntelligence is sale at @SideProjectors'></a>

# OpenIntelligence Public Product Surface

This repository is the public-facing product and diligence surface for
OpenIntelligence. It exists so someone coming from the App Store,
SideProjectors, or GitHub can understand what the product is, what the
engine does, and what is intentionally kept private.

It is not the private engine source tree.

<p align="center">
	<a href="https://apps.apple.com/us/app/openintelligence/id6756559175">
		<img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" height="50">
	</a>
</p>

## What OpenIntelligence Is

OpenIntelligence is an Apple-native document intelligence app and private
engine for asking grounded questions over user-controlled documents.

The engine is built around a local-first pipeline:

1. Import and normalize documents, images, and technical material.
2. Preserve useful text, layout, table, and visual evidence.
3. Build private per-library indexes for retrieval.
4. Retrieve source-backed evidence before answering.
5. Generate answers that stay tied to inspectable support.
6. Surface uncertainty, citations, and review affordances in the app.

For more detail, start with [ENGINE_OVERVIEW.md](ENGINE_OVERVIEW.md).

## What This Repo Is For

- Explaining the product and engine at a useful public level.
- Giving buyers and evaluators a clean first stop from SideProjectors.
- Linking to the real App Store app without publishing private source.
- Showing public architecture, privacy posture, release history, and roadmap.
- Providing a lightweight SwiftUI demo shell that builds without the private engine.

## What This Repo Is Not

- It is not the private `OpenIntelligence-Engine` repo.
- It is not the App Store submission workspace.
- It is not a buyer-ready SDK package.
- It is not a complete implementation of ingestion, retrieval, verification, or ranking.

Those remain private until there is a real diligence or acquisition process.

## What This Repo Does Not Include

- private ingestion and chunking internals
- retrieval and verification logic
- embedding and vector search implementation
- SDK packaging and buyer packet materials
- commercialization and diligence documents
- App Store submission and release-ops tooling

Those remain in the private `OpenIntelligence-Engine` repo.

## For Buyers And Evaluators

Use this repo to understand the public product, install the App Store app, and
decide whether deeper diligence is worth pursuing. Hands-on review of the
private engine, SDK shape, commercialization material, or internal evaluation
work should happen through the sale process, not through this public repo.

Useful entry points:

- [ENGINE_OVERVIEW.md](ENGINE_OVERVIEW.md) for the engine story
- [HOW_IT_WORKS.md](HOW_IT_WORKS.md) for the public workflow
- [ARCHITECTURE.md](ARCHITECTURE.md) for the public/private boundary
- [PRIVACY.md](PRIVACY.md) for privacy posture
- [WHATS_NEW.md](WHATS_NEW.md) and [CHANGELOG.md](CHANGELOG.md) for shipped product history
- [ROADMAP.md](ROADMAP.md) for public direction
- [Xrays/pipeline-xray/index.html](Xrays/pipeline-xray/index.html) for a static public pipeline visualizer

## Build The Public Demo Shell

```bash
xcodebuild \
  -project OpenIntelligence.xcodeproj \
  -scheme OpenIntelligence \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

This builds the public SwiftUI demo shell. Install the real shipped app from
the App Store link above.

## Boundary

The goal is to keep this repo useful and honest without publishing the private
engine implementation. The public repo is the product-facing surface. The
private engine repo is the source of truth for the proprietary implementation.

## License

See [LICENSE](LICENSE).
