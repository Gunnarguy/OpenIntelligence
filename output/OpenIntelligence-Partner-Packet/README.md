# OpenIntelligence Partner Packet

This folder is the operator packet for live buyer conversations.

Use these every time:

1. `FOUNDER_SALES_RUNBOOK.md`
2. `CURRENT_COMMITMENTS.md`
3. `DATA_BOUNDARIES.md`

Use these only when the conversation deepens:

1. `EVALUATION_PROCESS.md`
2. `PRICING.md`
3. `DESIGN_PARTNER_OFFER.md`
4. `TARGET_ACCOUNT_FRAMEWORK.md`

The two concrete assets behind this folder are:

1. `../OpenIntelligence-SDK-Package/build/OpenIntelligenceEngine-Buyer-Packet.zip`
2. `../OpenIntelligence-SDK-Package/SampleApp/EngineEvaluationHost.xcodeproj`

If you want a sendable doc packet from this folder, build:

3. `build/OpenIntelligence-Partner-Packet.zip`

Create it with:

- `./scripts/build_partner_packet_bundle.sh`

This packet currently assumes the repo is on the 3.5 release line.

If the public release line changes, rebuild `../OpenIntelligence-SDK-Package/` from current source first.

Use this folder to qualify, demo, and scope a pilot.

Do not use it to pretend the repo is already a polished self-serve SDK.
