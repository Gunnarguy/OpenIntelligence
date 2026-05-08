<a href='https://www.sideprojectors.com/project/78816/openintelligence' alt='OpenIntelligence is for sale at @SideProjectors'><img style='position:fixed;z-index:1000;top:-5px; right: 20px; border: 0;' src='https://www.sideprojectors.com/img/badges/badge_2_red.png' alt='OpenIntelligence is sale at @SideProjectors'></a>

# OpenIntelligence Public Demo Snapshot

This repository is the public-facing demo snapshot for OpenIntelligence.

It is meant to show:

- the product story
- the trust posture
- the app-facing experience
- the public architecture and documentation
- public release notes, privacy posture, and marketing materials

It is not the full private engine repository.

## What This Repo Includes

- a lightweight SwiftUI demo app shell
- public docs and reference material
- release notes and roadmap context
- marketing materials
- public-safe build automation

## What This Repo Does Not Include

- private ingestion and chunking internals
- retrieval and verification logic
- embedding and vector search implementation
- SDK packaging and buyer packet materials
- commercialization and diligence documents
- App Store submission and release-ops tooling

Those remain in the private `OpenIntelligence-Engine` repo.

## Why This Exists

The goal is to keep the public repo useful and honest without publishing the private engine moat.

This repo is the demo/publish surface.
The private engine repo is the real source of truth.

## Build

```bash
xcodebuild -scheme OpenIntelligence -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Public Materials

- [WHATS_NEW.md](WHATS_NEW.md)
- [HOW_IT_WORKS.md](HOW_IT_WORKS.md)
- [ARCHITECTURE.md](ARCHITECTURE.md)
- [PRIVACY.md](PRIVACY.md)
- [ROADMAP.md](ROADMAP.md)

## License

See [LICENSE](LICENSE).
