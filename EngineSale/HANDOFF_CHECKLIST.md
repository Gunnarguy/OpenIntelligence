# Handoff Checklist

## What A Buyer Would Receive

- source code for the full repo
- the app project and current app targets
- engine-relevant source files under `OpenIntelligence/SDK/` and `OpenIntelligence/Services/`
- the current SDK facade in `OpenIntelligence/SDK/OpenIntelligenceEngine.swift`
- benchmark harness code in `OpenIntelligence/App/DebugRAGValidationHarness.swift`
- benchmark scripts and dashboard tooling in `scripts/` and `Benchmarks/`
- current docs under `Docs/`
- staged evaluation packet under `output/OpenIntelligence-SDK-Package/`
- partner-packet docs under `output/OpenIntelligence-Partner-Packet/`
- app-only StoreKit and IAP context if the repo handoff includes the full app project
- known limitations and claim guardrails

## Suggested Walkthrough Before Any Serious Transfer Discussion

- review `EngineSale/ENGINE_PITCH.md`
- review `EngineSale/ENGINE_INVENTORY.md`
- review `EngineSale/KNOWN_LIMITATIONS.md`
- walk through the SDK facade and runtime-path assumptions
- walk through ingestion, storage, retrieval, generation, and verification layers
- inspect a benchmark run and trace artifact
- inspect the staged evaluation packet and sample host materials

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

The strongest current handoff is a guided technical transfer or diligence package.

The weakest current handoff is pretending the repo is already a clean plug-and-play enterprise SDK.
