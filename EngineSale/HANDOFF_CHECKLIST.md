# Handoff Checklist

This is the operational checklist for a real transfer, not just a demo call.

Use it after a buyer is serious and scope, price, and paper are moving.

## Scope To Confirm In Writing

Before payment, confirm whether the sale includes any of the following:

- full Git repo
- current app project and app targets
- engine source files under `OpenIntelligence/SDK/` and `OpenIntelligence/Services/`
- benchmark tooling in `scripts/` and `Benchmarks/`
- docs under `Docs/`, `EngineSale/`, and `output/`
- staged evaluation packet under `output/OpenIntelligence-SDK-Package/`
- partner packet under `output/OpenIntelligence-Partner-Packet/`
- App Store metadata and fastlane assets
- domains, websites, screenshots, listing assets, or none of the above
- post-sale support hours

If it is not written down, treat it as excluded.

## Paper Stack Before Transfer

This is not legal advice.

Before transfer, have at minimum:

- NDA if deeper non-public material has been shared
- a simple transfer or asset-purchase agreement that defines scope, exclusions, payment, and timing
- payment method and evidence of cleared payment

NDA alone is not enough for a direct sale.

## What A Buyer Should Receive After Payment

- source code for the agreed repo scope
- the app project and current app targets if included in the deal
- the current SDK facade in `OpenIntelligence/SDK/OpenIntelligenceEngine.swift`
- benchmark harness code in `OpenIntelligence/App/DebugRAGValidationHarness.swift`
- benchmark scripts and dashboard tooling in `scripts/` and `Benchmarks/`
- current docs under `Docs/`
- staged evaluation packet under `output/OpenIntelligence-SDK-Package/`
- partner-packet docs under `output/OpenIntelligence-Partner-Packet/`
- known limitations and claim guardrails

Only include app-only StoreKit, App Store metadata, or release assets if the sale scope explicitly includes the full app business surface.

## Pre-Transfer Prep

Before transfer day, do all of this:

- run `./scripts/prepare_sale_packets.sh`
- run `./scripts/preflight_check.sh`
- confirm `output/OpenIntelligence-SDK-Package/build/OpenIntelligenceEngine-Buyer-Packet.zip` exists
- confirm `output/OpenIntelligence-Partner-Packet/build/OpenIntelligence-Partner-Packet.zip` exists
- note the exact commit SHA being transferred
- confirm there are no API keys, service credentials, signing certificates, or provisioning assets in scope
- decide whether transfer will happen by GitHub repo transfer or repo archive delivery
- decide whether any support window is included after transfer

## Suggested Walkthrough Before Any Serious Transfer Discussion

- review `EngineSale/ENGINE_PITCH.md`
- review `EngineSale/ENGINE_INVENTORY.md`
- review `EngineSale/KNOWN_LIMITATIONS.md`
- review `EngineSale/CLAIMS_GUARDRAILS.md`
- walk through the SDK facade and runtime-path assumptions
- walk through ingestion, storage, retrieval, generation, and verification layers
- inspect a benchmark run and trace artifact
- inspect the staged evaluation packet and sample host materials

## Transfer-Day Sequence

1. Confirm final written scope and exclusions.
2. Confirm payment has cleared.
3. Freeze the handoff to a named commit SHA.
4. Deliver either GitHub repo transfer or repo archive.
5. Deliver both packet zips.
6. Deliver this checklist plus key engine docs.
7. Run a short handoff call.
8. Get written confirmation that the buyer received access and artifacts.

## Closing Rule

If someone is ready to close, keep the process brutally simple:

1. align on scope in writing
2. align on price in writing
3. use NDA if deeper non-public material is being shared before payment
4. keep diligence short and packet-based
5. transfer only after cleared payment

Do not create a custom process in the middle of a live deal unless the buyer's legal or procurement flow forces it.

## Post-Transfer First-Read Set

Tell the buyer to read these first:

- `EngineSale/ENGINE_INVENTORY.md`
- `EngineSale/KNOWN_LIMITATIONS.md`
- `EngineSale/CLAIMS_GUARDRAILS.md`
- `Docs/BUYER_READINESS_AND_EVALUATION.md`
- `SDK_BOUNDARY_AUDIT.md`

## Suggested First Engineering Tasks After Handoff

- separate engine code from app-only UI, billing, and diagnostics surfaces
- harden runtime-path and storage ownership for multi-instance SDK use
- narrow and stabilize the public API boundary
- replace staged evaluation packaging with a reproducible SDK packaging flow
- build a maintained eval set for exact-value, table, procedural, and missing-evidence cases
- validate source-support and abstention behavior on the buyer corpus

## What Should Not Be Shared Publicly Before A Serious Buyer

- raw repo access
- proprietary thresholds or ranking formulas if separately extracted
- private benchmark documents or private customer corpora
- App Store account credentials
- signing certificates or provisioning assets
- API keys or service credentials
- private user data or benchmark traces containing sensitive material

## Practical Rule

The strongest current handoff is a guided technical transfer pinned to a known commit and backed by the packet artifacts.

The weakest current handoff is pretending the repo is already a clean plug-and-play enterprise SDK.
