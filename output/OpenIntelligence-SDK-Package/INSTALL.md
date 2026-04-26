# Install

## Current Status

This document describes how to work with the staged evaluation packet.

It does not turn the current packet into a finished enterprise SDK story.

## Intended Evaluation Path

If the staged XCFramework artifact is present, the current packet can support a same-toolchain evaluation flow:

1. Drag `OpenIntelligenceEngine.xcframework` into the evaluator project.
2. Link required Apple frameworks if needed.
3. Use the sample host materials in this packet as a reference.
4. Test on a physical Apple Intelligence-capable device for live Foundation Models behavior.

## Runtime Prerequisites

- Xcode 26 or later
- Apple Intelligence-capable iPhone, iPad, or Mac for live Apple FM behavior
- physical-device validation for actual generation behavior

## Evaluation Limits

Treat the current packet as:

- guided evaluation collateral
- technical-review support
- same-toolchain testing material

Do not treat it as:

- a full source-code transfer
- a toolchain-agnostic binary SDK
- a finished self-serve enterprise package

## Practical Rule

If the conversation is about serious licensing or code transfer, this packet should support that conversation, not replace the deeper repo and codebase review.
