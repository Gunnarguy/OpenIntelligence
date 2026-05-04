# Demo Playbook

## Goal

Show buyers the engine behavior clearly without pretending the current app UI is the final SDK deliverable.

## The Right Demo Framing

Say this up front:

“This is the engine behavior demonstrated through the current host app. In your product, this logic would sit under your own UI.”

That avoids the common confusion that you are selling the consumer app itself.

## What To Demo

Demo these three things:

1. Document ingestion works on real files
2. Answers stay grounded and cite source material
3. Workspaces stay isolated from each other

## Device Setup

Use a real supported iPhone or iPad.

Do not use Simulator for the buyer demo.
Simulator is fine for compile-and-link checks, but not for a clean Apple Intelligence runtime story.

## Demo Assets

Prepare:

- one manual or support PDF
- one policy or reference doc
- one second workspace with clearly different content

Have these files open before the call:

- packet-local demo app:
  - `output/OpenIntelligence-SDK-Package/SampleApp/EngineEvaluationHost.xcodeproj`
- packet-local operator script:
  - `output/OpenIntelligence-SDK-Package/SampleApp/DEMO_SCRIPT.md`
- packet summary:
  - `output/OpenIntelligence-SDK-Package/PACKAGE_SUMMARY.md`
- current engine entry-point code file:
  - `OpenIntelligence/SDK/OpenIntelligenceEngine.swift`
- current packaging note:
  - `output/OpenIntelligence-SDK-Package/Internal/BUILD_NOTES.md`

Pick questions where the answer and the citation are obvious.

## Recommended Demo Flow

### 1. Open With The Problem

Explain in one sentence:

“Most teams want private document intelligence, but they do not want to build ingestion, chunking, retrieval, reranking, and grounded answer logic themselves.”

### 2. Ingest Documents

Show:

- import one or two files
- assign them to a workspace
- confirm they are now queryable

Narrate:

“This is the engine building a workspace-scoped knowledge layer locally.”

### 3. Ask A Precise Question

Use a question where the source passage is easy to verify.

Show:

- answer text
- citations
- confidence or warning behavior if present

Narrate:

“The point is not just answering. The point is answering with evidence you can inspect.”

### 4. Show Workspace Isolation

Switch to another workspace and ask the same or a similar question.

Narrate:

“This is what lets a buyer map the engine to one customer, one matter, one project, or one department without content leaking across boundaries.”

### 5. Close With Integration Framing

Show the small engine entry-point shape from the SDK docs.

Say:

“In your app, this would sit under your UI. The public surface is intentionally small: configure, ingest, query, return answer plus citations.”

## What The Buyer Would Install

Today:

- they would not install a separate end-user app
- they would evaluate the engine behavior through your demo, the buyer-safe packet, and a guided integration path

Current evaluator packet contents:

- `START_HERE.md`
- `OpenIntelligenceEngine.xcframework`
- `EvaluationSupport/`
- `SampleApp/`

Final intended state:

- they would embed `OpenIntelligenceEngine.xcframework` in their own app
- their users would only see the buyer’s branded interface

## How To Record The Demo

1. Record on a real device
2. Start from a clean workspace state
3. Keep the recording under 3 minutes
4. Show import, query, citation, workspace switch, close
5. Add one caption card at the start: “Engine behavior shown through current host app”
6. Add one caption card at the end: “Intended commercial form: embedded engine inside buyer app”

## 3-Minute Recording Script

1. “OpenIntelligence Engine is the private document-intelligence layer behind this workflow.”
2. “I’m importing documents into a workspace.”
3. “Now I’ll ask a question and show the answer plus source evidence.”
4. “Here are the citations and answer-review details.”
5. “Now I switch workspaces to show isolation.”
6. “In a buyer product, this engine would power the same behavior under their own UI.”

## What To Avoid In The Demo

Do not:

- spend time on settings screens
- lead with monetization
- lead with internal pipeline jargon
- promise same-day binary handoff
- present the consumer app UI as the finished SDK product

## Backup Answer If They Ask About Packaging

Use this:

“The engine logic is real and we can send an evaluation XCFramework packet today. The final sealed module-stable SDK packaging path is still being finalized, so the best next step is a technical evaluation or pilot integration.”
