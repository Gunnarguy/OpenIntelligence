# Founder Sales Runbook

This is the step-by-step operator guide for selling OpenIntelligence Engine today.

## The Stupid-Simple Version

If you remember nothing else, remember this:

1. The thing you are selling is the engine, not the consumer app.
2. The main thing you send is the buyer packet zip.
3. The main thing you show live is the demo app.
4. The main thing you point to for proof is the simple "how another app uses the engine" doc, the real code file behind it, and the pipeline doc.
5. The next step is almost never "buy it on the spot". The next step is usually a paid technical evaluation or pilot.

If someone says "What exactly is this?" use this answer:

"It is the engine and logic behind grounded document QA on Apple devices. The main things I can show you today are the buyer packet zip, the demo app, the simple doc that shows how another app would use the engine, the real code file behind it, and the pipeline doc that explains how the system works."

## The 1-2-3 Version

If you want this as easy as possible, think of it like this:

### 1. Show them the package

This is the main thing you can send today:

- `output/OpenIntelligence-SDK-Package/build/OpenIntelligenceEngine-Buyer-Packet.zip`

Plain English:

- this is the evaluation package
- this is the thing you send after a good first call
- this is not the full repo
- this is not proof of a finished self-serve SDK

### 2. Show them the demo

This is the main thing you open on a call:

- `output/OpenIntelligence-SDK-Package/SampleApp/EngineEvaluationHost.xcodeproj`

Plain English:

- this is the demo app
- this proves the engine behavior and import path
- this is not the final buyer UX

### 3. Show them the proof docs

These are the main proof files:

- `output/OpenIntelligence-SDK-Package/API.md`
- `OpenIntelligence/SDK/OpenIntelligenceEngine.swift`
- `Docs/STORAGE_AND_PIPELINE_TRACE.md`
- `EngineSale/ENGINE_INVENTORY.md`
- `output/OpenIntelligence-SDK-Package/Internal/BUILD_NOTES.md`

Plain English:

- `output/OpenIntelligence-SDK-Package/API.md` = the simple explanation of how another app would use the engine
- `OpenIntelligence/SDK/OpenIntelligenceEngine.swift` = the real code file behind that explanation; this proves the engine entry points are not just an idea
- `Docs/STORAGE_AND_PIPELINE_TRACE.md` = the step-by-step pipeline doc; this shows how the engine works
- `EngineSale/ENGINE_INVENTORY.md` = the parts list; this shows what is actually in the engine
- `output/OpenIntelligence-SDK-Package/Internal/BUILD_NOTES.md` = the status note; this shows what is finished and what is not finished

## What This Is Actually Called

Forget the jargon.

You do not have a hosted API here.

What you have is:

- the small set of calls another app would use to talk to the engine
- the code surface a buyer would integrate if they wanted this inside their own product

In plain English, the buyer app needs to do only a few big things:

1. check whether the engine is available on the current device
2. create the engine
3. import documents into the engine
4. ask a question
5. get back an answer plus citations

That is why these two files matter:

- `output/OpenIntelligence-SDK-Package/API.md` = the simple human-readable explanation
- `OpenIntelligence/SDK/OpenIntelligenceEngine.swift` = the real code that shows those calls actually exist

## How The Buyer Would Actually Use It

If a buyer says, "Okay, but what would my engineers literally do with this?" use this answer:

"They would put the engine into their app, create an engine object, import files, ask a question, and then show the returned answer and citations inside their own UI."

Here is the simplest possible mental model:

1. `OIEngine.availability()`
   - ask: can this device run the engine correctly?
2. `OIEngine(...)`
   - create the engine
3. `engine.ingest(...)`
   - give the engine files to import and index
4. `engine.query(...)`
   - ask a question against those imported files
5. result comes back
   - answer text
   - citations
   - confidence / warnings

That is all this means in this context.

## The Easiest Way To Explain This On A Call

Do not say:

- API facade
- SDK surface
- abstraction layer

Say this:

"This file shows the handful of ways another app would talk to the engine: check availability, create the engine, import files, ask questions, and get back answers with citations."

Use this when:

- someone messages you from SideProjectors, LinkedIn, email, or a founder community
- you need to explain what the buyer is actually buying
- you need to know what file, zip, demo, or doc to show next
- you do not want to improvise or oversell

This guide assumes the honest commercial framing:

- you are selling the engine logic and codebase head start
- you are not selling a finished self-serve enterprise SDK
- you are not selling the consumer app UX as the product

## First Principle

The thing for sale is:

- the engine logic
- the SDK-style facade
- the ingestion, retrieval, and verification behavior
- the evaluation packet and sample host app
- founder-guided diligence, pilot, or handoff support

The thing not for sale as the main story is:

- the consumer app shell
- StoreKit and paywall logic
- onboarding and settings UI
- the claim that this is already a polished off-the-shelf SDK

## The Exact Things

When a buyer asks what is real, point to exact artifacts:

1. Actual buyer-safe zip:
   - `output/OpenIntelligence-SDK-Package/build/OpenIntelligenceEngine-Buyer-Packet.zip`
2. Packet root:
   - `output/OpenIntelligence-SDK-Package/`
3. Simple explainer for how another app would use the engine:
   - `output/OpenIntelligence-SDK-Package/API.md`
4. Real engine integration code file:
   - `OpenIntelligence/SDK/OpenIntelligenceEngine.swift`
5. Current pipeline trace:
   - `Docs/STORAGE_AND_PIPELINE_TRACE.md`
6. Current engine inventory:
   - `EngineSale/ENGINE_INVENTORY.md`
7. Current SDK boundary:
   - `SDK_BOUNDARY_AUDIT.md`
8. Packet-local demo app:
   - `output/OpenIntelligence-SDK-Package/SampleApp/EngineEvaluationHost.xcodeproj`
9. Source-of-truth demo app in repo:
   - `Samples/EngineEvaluationHost/EngineEvaluationHost.xcodeproj`
10. Current packaging-status note:

- `output/OpenIntelligence-SDK-Package/Internal/BUILD_NOTES.md`

11. Current honesty sheet:

- `output/OpenIntelligence-Partner-Packet/CURRENT_COMMITMENTS.md`

## Plain-English Translation Of The Files

Use this section whenever the file names start sounding too abstract.

| If they ask...                                       | Show them...                                                                        | What you say in normal English                                                         |
| ---------------------------------------------------- | ----------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| "What is the actual thing?"                          | `output/OpenIntelligence-SDK-Package/build/OpenIntelligenceEngine-Buyer-Packet.zip` | "This is the evaluation package I can send today."                                     |
| "Can you show me the demo?"                          | `output/OpenIntelligence-SDK-Package/SampleApp/EngineEvaluationHost.xcodeproj`      | "This is the demo app that shows the engine behavior."                                 |
| "How would another app use this?"                    | `output/OpenIntelligence-SDK-Package/API.md`                                        | "This is the simple explanation of how another app would use the engine."              |
| "Where is the real code behind that?"                | `OpenIntelligence/SDK/OpenIntelligenceEngine.swift`                                 | "This is the actual code file that proves those engine calls really exist."            |
| "How does the engine actually work?"                 | `Docs/STORAGE_AND_PIPELINE_TRACE.md`                                                | "This is the step-by-step pipeline doc."                                               |
| "What is actually included in the engine?"           | `EngineSale/ENGINE_INVENTORY.md`                                                    | "This is the parts list for what is reusable and what is app-specific."                |
| "How finished is the SDK packaging?"                 | `output/OpenIntelligence-SDK-Package/Internal/BUILD_NOTES.md`                       | "This is the honest status note for what is working and what is still blocked."        |
| "Where do you draw the line between engine and app?" | `SDK_BOUNDARY_AUDIT.md`                                                             | "This is the boundary doc that shows what belongs to the engine versus the app shell." |

## What You Say In One Sentence

Use this when someone asks what it is:

"OpenIntelligence Engine is the Apple-native engine layer behind grounded document QA: it ingests private files, builds local full-text and vector indexes, retrieves evidence, generates answers, and exposes citations and trust behavior, and today I can show it through a real evaluation packet and demo host app."

## What You Say In Two Sentences

Use this if they ask for a little more detail:

"The thing I am selling is the engine logic and codebase head start, not the consumer app shell. The concrete assets are the simple doc that shows how another app would use the engine in `output/OpenIntelligence-SDK-Package/API.md`, the real code file behind it in `OpenIntelligence/SDK/OpenIntelligenceEngine.swift`, the pipeline in `Docs/STORAGE_AND_PIPELINE_TRACE.md`, and the current buyer-safe evaluation packet at `output/OpenIntelligence-SDK-Package/build/OpenIntelligenceEngine-Buyer-Packet.zip`."

## Before You Talk To Anyone

Do this every time before a serious conversation:

1. Confirm the buyer packet exists:
   - `output/OpenIntelligence-SDK-Package/build/OpenIntelligenceEngine-Buyer-Packet.zip`
2. Confirm packet validation still passes:
   - `./scripts/build_sdk_buyer_bundle.sh && ./scripts/validate_sdk_package.sh`
3. Open these files in advance:
   - `output/OpenIntelligence-Partner-Packet/CURRENT_COMMITMENTS.md`
   - `output/OpenIntelligence-SDK-Package/Internal/SELLING_PLAYBOOK.md`
   - `output/OpenIntelligence-SDK-Package/Internal/DEMO_PLAYBOOK.md`
   - `output/OpenIntelligence-SDK-Package/API.md`
   - `OpenIntelligence/SDK/OpenIntelligenceEngine.swift`
   - `Docs/STORAGE_AND_PIPELINE_TRACE.md`
   - `EngineSale/ENGINE_INVENTORY.md`
   - `output/OpenIntelligence-SDK-Package/Internal/BUILD_NOTES.md`
4. Have the demo app ready:
   - `output/OpenIntelligence-SDK-Package/SampleApp/EngineEvaluationHost.xcodeproj`
5. Have the packet-local demo script ready:
   - `output/OpenIntelligence-SDK-Package/SampleApp/DEMO_SCRIPT.md`

## Step 1: Respond To SideProjectors Inbound

If someone contacts you because of the listing, do not pitch the whole sale in chat.

Your goal is to move them to a short qualification call.

Use this reply:

"Thanks for reaching out. The honest framing is that this is not a polished off-the-shelf SDK yet. What I have today is the engine logic, the evaluation packet, the sample host app, and a real Apple-native demo path for ingestion, retrieval, citations, and verification behavior. If useful, I can do a 20-minute call, show the exact demo, and then send the current evaluation packet if it looks like a fit."

## Step 2: Qualify Them Before You Send Real Materials

Ask these five questions:

1. What kind of documents do your users actually upload?
2. Is your target product iPhone, iPad, Apple Silicon Mac, or some combination?
3. Are you looking for a feature inside your app, a licensable engine, or a broader handoff / acquisition discussion?
4. Do citations and trust review matter, or do you mainly want answer text?
5. Are you evaluating this as a paid technical evaluation, a pilot, or a possible buyout / license?

If their answers suggest they need:

- a cross-platform web SDK immediately
- a hosted API instead of embedded Apple-native logic
- a guaranteed-accurate regulated-use product

then say it is likely not the right fit.

## Step 3: Run The First Call Correctly

Keep the first call to 20 minutes.

### Minutes 0 to 3

Say this:

"The thing I am selling is the engine and the logic behind it, not the consumer app shell. The easiest proof points are the simple doc that shows how another app would use the engine in `output/OpenIntelligence-SDK-Package/API.md`, the real code file behind it in `OpenIntelligence/SDK/OpenIntelligenceEngine.swift`, the pipeline trace in `Docs/STORAGE_AND_PIPELINE_TRACE.md`, and the evaluation packet at `output/OpenIntelligence-SDK-Package/build/OpenIntelligenceEngine-Buyer-Packet.zip`."

### Minutes 3 to 10

Run the demo.

Use:

- `output/OpenIntelligence-SDK-Package/SampleApp/EngineEvaluationHost.xcodeproj`
- `output/OpenIntelligence-SDK-Package/SampleApp/DEMO_SCRIPT.md`

Show these exact things:

1. import one or two real files
2. ask one precise question
3. show the answer and citations
4. switch workspaces and show isolation

### Minutes 10 to 15

Translate the engine into their product.

Say this:

"In your product, this logic would sit under your own UI. The buyer value is that you are not starting from zero on ingestion, indexing, retrieval, verification, and trust behavior."

### Minutes 15 to 20

Close to the next paid step.

Use one of these closes:

- "The next step is a paid technical evaluation."
- "The next step is a design-partner pilot."
- "The next step is deeper diligence if you are thinking about a license or a broader handoff."

## Step 4: Answer The Core Buyer Questions

### What exactly am I buying?

"You are buying the engine layer and codebase head start: the file-import path, the indexing path, the retrieval path, the answer-generation path, the verification behavior, and the benchmark/evaluation materials. The cleanest references are `output/OpenIntelligence-SDK-Package/API.md`, `OpenIntelligence/SDK/OpenIntelligenceEngine.swift`, `Docs/STORAGE_AND_PIPELINE_TRACE.md`, and `EngineSale/ENGINE_INVENTORY.md`."

If you want the simplest version, say this instead:

"You are buying the engine code, the engine logic, the demo path, and the evaluation package."

### What is the zip?

"The current buyer-safe artifact is `output/OpenIntelligence-SDK-Package/build/OpenIntelligenceEngine-Buyer-Packet.zip`. It is the evaluation packet, not proof of a finished self-serve SDK."

### What is the demo?

"The demo is the packet-local evaluation host app at `output/OpenIntelligence-SDK-Package/SampleApp/EngineEvaluationHost.xcodeproj`. It proves the import path and engine behavior. It is not the end-user product I am selling as UX."

### Is this a full app?

"No. The thing of value is the engine. The boundary around that is described in `SDK_BOUNDARY_AUDIT.md`."

### Is it ready as a binary SDK today?

"Not fully. The evaluation packet and sample host are real today. The remaining blocker to the final module-stable SDK path is documented in `output/OpenIntelligence-SDK-Package/Internal/BUILD_NOTES.md`."

### Why is this worth money?

"Because the hard part is not drawing UI. The hard part is getting ingestion, storage, retrieval, grounding, verification, and evaluation infrastructure working together on Apple hardware, and that work is already here."

## Step 5: What You Send After A Good First Call

Do not dump the full repo on a stranger.

Send this package:

1. `output/OpenIntelligence-SDK-Package/build/OpenIntelligenceEngine-Buyer-Packet.zip`
2. `output/OpenIntelligence-Partner-Packet/CURRENT_COMMITMENTS.md`
3. `EngineSale/ENGINE_INVENTORY.md`
4. `Docs/STORAGE_AND_PIPELINE_TRACE.md`

If they want a single sentence in the email, use this:

"Attached is the current evaluation packet along with the exact engine inventory and pipeline trace, so you can review what is real today and what is still evaluation-stage."

## Step 6: When To Use NDA And Paper

Use `output/OpenIntelligence-Partner-Packet/EVALUATION_PROCESS.md` as the rulebook.

Simple sequence:

1. Intro message
2. First call
3. High-level live demo
4. Confirm real interest
5. NDA before deeper non-public details or before receiving their sensitive files
6. Evaluation or beta terms before hands-on access beyond light founder review
7. Paid evaluation or pilot agreement for real work

Do not force an NDA for a cold message.

Do not send the full evaluation packet casually to random tire-kickers.

## Step 7: Price It Correctly

Use `output/OpenIntelligence-Partner-Packet/PRICING.md`.

The practical ladder is:

1. Paid technical evaluation:
   - `$5,000 - $10,000`
2. Design-partner pilot:
   - `$12,500 - $25,000`
3. Pilot plus license / handoff discussion:
   - custom after diligence

Do not sell the entire engine/IP transfer like a cheap digital asset listing.

If someone only wants to spend a few thousand dollars total and expects full handoff, they are not a serious fit.

## Step 8: What Not To Say

Do not say:

- it is a finished enterprise SDK today
- it is a polished self-serve install
- it guarantees correctness
- it is HIPAA compliant
- it is ready for clinical, legal, safety, or IFU use
- it is full GraphRAG
- it has Apple Foundation Models embeddings
- it has a public 65K Foundation Models context path

Use `output/OpenIntelligence-Partner-Packet/CURRENT_COMMITMENTS.md` whenever you feel yourself drifting into overclaiming.

## Step 9: Daily Buyer Checklist

Before every serious buyer conversation, do this:

1. confirm the buyer packet zip exists
2. rerun packet validation if needed
3. open the demo app project
4. open the demo script
5. open the simple doc that shows how another app would use the engine
6. open the real code file behind it
7. open the pipeline trace
8. open the engine inventory
9. open the packaging-status note
10. know your next ask before the call starts

## Step 10: The Three End States

Every conversation should end in one of these three buckets:

1. Not a fit
2. Paid technical evaluation or pilot
3. Deeper diligence for license, handoff, or acquisition

If the call ends with vague enthusiasm and no next step, you did not close it properly.

## Copy-Paste Follow-Up Email

Subject: OpenIntelligence Engine evaluation materials

"Good speaking with you. As discussed, the concrete evaluation artifact is `output/OpenIntelligence-SDK-Package/build/OpenIntelligenceEngine-Buyer-Packet.zip`. The most useful companion references are the simple doc that shows how another app would use the engine in `output/OpenIntelligence-SDK-Package/API.md`, the real code file behind it in `OpenIntelligence/SDK/OpenIntelligenceEngine.swift`, the pipeline trace in `Docs/STORAGE_AND_PIPELINE_TRACE.md`, the subsystem inventory in `EngineSale/ENGINE_INVENTORY.md`, and the current packaging-status note in `output/OpenIntelligence-SDK-Package/Internal/BUILD_NOTES.md`.

The honest framing is that this is a substantial Apple-native engine prototype and codebase head start, not yet a finished self-serve enterprise SDK. If the fit looks real after review, the right next step is a paid technical evaluation or a design-partner pilot."

## Final Rule

If you ever feel yourself slipping into vague language, return to concrete nouns:

- this is the file
- this is the zip
- this is the demo
- this is how another app would use the engine
- this is the status note
- this is what is real today
- this is what is not done yet

That is how you stay credible.
