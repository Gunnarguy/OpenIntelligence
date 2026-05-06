# Start Here

This packet is the current evaluation slice of the OpenIntelligence engine story.

## What It Is

- a staged evaluation packet
- a technical-review aid
- a same-toolchain testing path when the staged artifact is present

## What It Is Not

- a full source-code handoff
- a finished enterprise SDK
- a regulated-use artifact

## Current Release Alignment

The app target and engine target are currently on the 3.5 release line.

Treat this staged packet as a 3.5-aligned evaluation artifact and rebuild it from current source after every public release before sending it to a buyer or partner.

## Hard Status

- Built from current source and staged into this packet: yes, when generated through `scripts/prepare_engine_buyer_packet.sh`.
- Required engine model and vocabulary assets are expected inside the staged XCFramework, not as separate loose files.
- Same-toolchain technical evaluation path: yes.
- Module-stable commercial binary SDK: no.
- Self-serve no-guidance buyer handoff: no.

The blocking reason is still the same: stable `BUILD_LIBRARY_FOR_DISTRIBUTION=YES` packaging is blocked by upstream `swift-transformers` interface verification.

## Fastest Review Path

1. Read `PACKAGE_SUMMARY.md`.
2. Read `API.md` for the simple explanation of how another app would use the engine.
3. Read `INSTALL.md`.
4. Open `SampleApp/` if you want to inspect the packet-local host path.

## Commercial Framing

Use this packet for design-partner and technical-evaluation conversations.

Do not use it by itself to claim the engine is already a polished, finished SDK product.
