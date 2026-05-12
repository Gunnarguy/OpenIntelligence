# Roadmap

This roadmap describes technical directions for the prototype. It is not a product commitment.

## Near Term

- Keep the public repository focused on the cleaned app and document intelligence engine.
- Improve build reliability for the app target and experimental package boundary.
- Keep README and docs aligned with proof-of-concept positioning.
- Add more generic demo documents that show retrieval, citations, and abstention behavior.
- Expand diagnostics around chunk quality, retrieval quality, and answer grounding.

## Retrieval And Answer Quality

- Improve chunking for mixed-format documents.
- Improve library scoping and source filtering.
- Make citation and evidence-review behavior easier to inspect.
- Continue tightening unsupported-claim handling and abstention behavior.

## Apple-Native Experience

- Continue refining SwiftUI document, chat, settings, and diagnostics surfaces.
- Explore platform-native import, extraction, and background-processing workflows.
- Keep local-first behavior and user-controlled files central to the UX.

## Packaging

- Maintain `Package.swift` as an experimental source package boundary.
- Avoid describing the package as a finished SDK until the API surface, setup path, tests, and compatibility story are mature enough to support that claim.
