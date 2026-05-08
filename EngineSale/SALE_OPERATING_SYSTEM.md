# Sale Operating System

This is the single operator doc for SideProjectors inbound, buyer diligence, and direct handoff.

If you only remember three things, remember these:

1. Run `./scripts/prepare_sale_packets.sh` before any serious conversation.
2. Do not send the full repo casually. Send the packet zips first.
3. Do not transfer repo access or any credentials until scope is written down and payment has cleared.

## Live Buyer Fast Path

If the goal is to be sale-ready for a live buyer conversation, do exactly this and nothing fancier:

1. Run `./scripts/prepare_sale_packets.sh`.
2. Reply with the short inbound template from `EngineSale/INBOUND_MESSAGE_TEMPLATES.md`.
3. Book a 20-minute call.
4. On the call, decide whether this is `evaluation first` or `direct buyout`.
5. If they are serious, get NDA in place.
6. After NDA, send both packet zips.
7. If they want the whole project, use the direct-buyout language and handoff checklist.

That is the whole operating path for a live sale conversation. Do not improvise a bigger process unless the buyer gives you a reason.

## What You Can Honestly Sell Now

You can honestly sell any of these now:

- a short paid evaluation or pilot conversation around the engine
- a design-partner style diligence process using the current packets
- a direct asset buyout of the repo and sale materials at the current asking price

You cannot honestly sell this as:

- a finished self-serve enterprise SDK
- a toolchain-agnostic commercial binary SDK
- a regulated-use or compliance-ready AI system

## Public Asking Price

Use the currently published SideProjectors listing price as the public asking price reference.

If a buyer accepts that range and wants the whole project instead of a pilot, use the direct-buyout lane below.

If they want to evaluate capability first, use the evaluation lane below.

## Recommended Send Order

Use this order. It keeps the conversation moving without oversharing.

### Cold inbound

Send:

- the first-reply template
- `EngineSale/ENGINE_PITCH.md` if they want more color

Do not send packet zips yet.

### Serious pre-NDA buyer

Show live on a call:

- the demo host app
- `EngineSale/ENGINE_INVENTORY.md`
- `EngineSale/KNOWN_LIMITATIONS.md`

Still do not send the full repo.

### Post-NDA serious buyer

Send:

- `output/OpenIntelligence-SDK-Package/build/OpenIntelligenceEngine-Buyer-Packet.zip`
- `output/OpenIntelligence-Partner-Packet/build/OpenIntelligence-Partner-Packet.zip`

### Direct buyout after price alignment

Send or walk through:

- `EngineSale/HANDOFF_CHECKLIST.md`
- `EngineSale/CLAIMS_GUARDRAILS.md`
- `EngineSale/KNOWN_LIMITATIONS.md`

## One-Command Prep

Run:

`./scripts/prepare_sale_packets.sh`

That gives you two sendable artifacts:

- `output/OpenIntelligence-SDK-Package/build/OpenIntelligenceEngine-Buyer-Packet.zip`
- `output/OpenIntelligence-Partner-Packet/build/OpenIntelligence-Partner-Packet.zip`

It also refreshes the real current-source evaluation packet so you are not sending stale material.

## The Two Lanes

### Lane 1: Evaluation First

Use this when the buyer says any of the following:

- "Can I see how it works?"
- "Can my engineers evaluate it?"
- "Can we try it on our documents?"
- "We may want a pilot or license."

Goal:

- qualify fit
- run a short call
- send the packet zips after seriousness is confirmed
- convert into a paid evaluation, pilot, or deeper diligence

### Lane 2: Direct Buyout

Use this when the buyer says any of the following:

- "I want to buy the whole thing."
- "Can I acquire the codebase?"
- "If the price is right, I will take it as-is."
- "I am not looking for a pilot, I want the asset transfer."

Goal:

- confirm scope and price
- run a short diligence window
- get paper and payment done
- transfer repo and sale materials cleanly

## Inquiry To Handoff Sequence

### 1. First Reply

Use the copy in `EngineSale/INBOUND_MESSAGE_TEMPLATES.md`.

Do not send the full repo.

Do not send the buyer packet zip yet unless the conversation is clearly serious.

Safe first-send material:

- `EngineSale/ENGINE_PITCH.md`

Goal:

- move them to a 15-20 minute call or a short qualification exchange

### 2. Qualify Fast

Ask these five questions:

1. What kind of documents does your product or team actually work with?
2. Is your target iPhone, iPad, Apple Silicon Mac, or a full repo acquisition?
3. Are you evaluating a feature, a pilot, a license, or a full buyout?
4. Do citations and trust review matter, or do you mostly want answer text?
5. If this is a buyout, what exactly do you expect to receive besides the repo?

Bad-fit signals:

- they want a hosted cloud API immediately
- they need a polished self-serve SDK right now
- they need regulated-use claims

### 3. First Call

Open these before the call:

- `output/OpenIntelligence-SDK-Package/SampleApp/EngineEvaluationHost.xcodeproj`
- `output/OpenIntelligence-SDK-Package/SampleApp/DEMO_SCRIPT.md`
- `output/OpenIntelligence-Partner-Packet/CURRENT_COMMITMENTS.md`
- `EngineSale/ENGINE_INVENTORY.md`
- `EngineSale/KNOWN_LIMITATIONS.md`

In the call, do this in order:

1. explain that the thing for sale is the engine and codebase head start, not the consumer app shell
2. show the demo app
3. show the engine inventory and current limitations
4. decide whether this is evaluation-first or direct-buyout

### 4. Paper Stack

Use this order:

1. no paper for cold inbound or a basic intro
2. NDA before non-public technical sharing or buyer documents
3. evaluation terms before hands-on evaluation access
4. asset purchase or transfer agreement before direct sale

Read:

- `output/OpenIntelligence-Partner-Packet/EVALUATION_PROCESS.md`

### 5. What To Send At Each Stage

#### Stage A: Early Interest

Send:

- `EngineSale/ENGINE_PITCH.md`

Optional live-only references:

- `output/OpenIntelligence-SDK-Package/SampleApp/EngineEvaluationHost.xcodeproj`

#### Stage B: Serious, Pre-NDA

Show live, but do not dump the repo.

Use:

- demo app
- `EngineSale/ENGINE_INVENTORY.md`
- `output/OpenIntelligence-Partner-Packet/CURRENT_COMMITMENTS.md`

#### Stage C: Post-NDA

Send both packet zips:

- `output/OpenIntelligence-SDK-Package/build/OpenIntelligenceEngine-Buyer-Packet.zip`
- `output/OpenIntelligence-Partner-Packet/build/OpenIntelligence-Partner-Packet.zip`

If they want exact proof files, point them to:

- `OpenIntelligence/SDK/OpenIntelligenceEngine.swift`
- `Docs/STORAGE_AND_PIPELINE_TRACE.md`
- `EngineSale/ENGINE_INVENTORY.md`
- `SDK_BOUNDARY_AUDIT.md`

#### Stage D: Direct Sale, Post-Price Alignment

Send:

- `EngineSale/HANDOFF_CHECKLIST.md`
- `EngineSale/KNOWN_LIMITATIONS.md`
- `EngineSale/CLAIMS_GUARDRAILS.md`

Only send repo access after agreement and cleared payment.

## Direct-Buyout Lane

Use this if someone wants to buy the whole project at or near the listing price.

### Step 1: Confirm Scope In Writing

Confirm whether the sale includes:

- full Git repo
- current docs and output packets
- benchmark scripts and artifacts
- app project and app-only code
- App Store metadata and fastlane files
- domain, website, brand assets, screenshots, or none of the above
- any support window after transfer

If it is not written down, treat it as not included.

### Step 2: Confirm Price And Process

Use a simple written line like this:

`Price is the currently published SideProjectors asking price for the agreed asset scope, subject to short diligence, signed transfer paper, and cleared payment before repo transfer.`

### Step 3: NDA

Use NDA before sharing non-public packet detail or opening deeper repo-level diligence.

### Step 4: Diligence Window

Keep it short.

Suggested founder-safe window:

- `3-5 business days`

What they get during diligence:

- the two packet zips
- live walkthrough answers
- exact proof-file references

What they do not get during diligence:

- full repo admin access
- credentials
- signing assets
- App Store account access

### Step 5: Transaction Paper

This is not legal advice.

Before transfer, have a simple asset-transfer document that states:

- what is being sold
- what is excluded
- payment amount and payment method
- when transfer occurs
- whether any post-sale support is included
- warranty disclaimer and as-is language

### Step 6: Payment Before Transfer

Do not transfer the repo on promise.

Transfer only after:

- wire clears
- escrow releases
- SideProjectors payment is actually settled
- or whatever payment method you use is irreversible enough for you to proceed

### Step 7: Handoff

Use:

- `EngineSale/HANDOFF_CHECKLIST.md`

Deliver either:

- GitHub repo transfer
- or a full repo archive plus a shared private handoff channel

## Evaluation Lane

Use this if the buyer wants to see value before buying.

### What You Are Selling In This Lane

- technical evaluation
- pilot
- design-partner work
- diligence support

Use:

- `output/OpenIntelligence-Partner-Packet/PRICING.md`
- `output/OpenIntelligence-Partner-Packet/DESIGN_PARTNER_OFFER.md`

### Default Close

The most natural close is not "buy it now."

The natural close is:

- paid technical evaluation
- pilot
- or deeper diligence toward license or acquisition

## The Exact Files To Keep Open

Keep these ready during live conversations:

- `EngineSale/ENGINE_PITCH.md`
- `EngineSale/ENGINE_INVENTORY.md`
- `EngineSale/KNOWN_LIMITATIONS.md`
- `EngineSale/CLAIMS_GUARDRAILS.md`
- `EngineSale/HANDOFF_CHECKLIST.md`
- `EngineSale/INBOUND_MESSAGE_TEMPLATES.md`
- `output/OpenIntelligence-Partner-Packet/CURRENT_COMMITMENTS.md`
- `output/OpenIntelligence-SDK-Package/build/OpenIntelligenceEngine-Buyer-Packet.zip`
- `output/OpenIntelligence-Partner-Packet/build/OpenIntelligence-Partner-Packet.zip`
- `output/OpenIntelligence-SDK-Package/SampleApp/EngineEvaluationHost.xcodeproj`

## Hard Rules

- Do not claim the repo is a finished enterprise SDK.
- Do not claim regulated-use readiness.
- Do not send the full repo to casual inbound leads.
- Do not transfer anything before payment clears.
- Do not include App Store accounts, certificates, or credentials unless you explicitly decide they are part of scope and remove risk first.

## Daily Practical Rule

If someone messages from SideProjectors today, your default move is:

1. use the first-reply template
2. run a short qualification call
3. pick the lane
4. send the right zip only after seriousness is confirmed
5. use the handoff checklist if it becomes a real sale
