# Engine Evaluation Host Demo Script

## Goal

Run a five-minute live demo that proves three things:

- the SDK imports cleanly into a host app
- private documents can be indexed locally
- grounded answers come back with evidence, not just fluent text

## Setup

If you are working inside the private repo:

1. Run `./scripts/build_engine_evaluation_host.sh`.
2. Open `Samples/EngineEvaluationHost/EngineEvaluationHost.xcodeproj`.

If you are working from the buyer packet:

1. Open `SampleApp/`.
2. Run `./build_sample_app.sh`.
3. Open `SampleApp/EngineEvaluationHost.xcodeproj`.

Then:

1. Choose an Apple Intelligence-capable iPhone for the full live flow.
2. Press Run.

Simulator is fine for UI and import validation.
Use a real Apple Intelligence-capable device for the live question-answering step.

## In-App Flow

1. Launch the app and let the Room Readiness card settle.
2. In the Pitch Kit section, tap `Load Demo Pack`.
3. In Step 1, tap `Index Library`.
4. Wait for the indexing result strip to appear.
5. In Step 2, use the default risk question first.
6. In Step 3, walk the answer, confidence, warnings, and citations.

## Recommended Questions

- `What are the three biggest risks in this packet, and what evidence supports each one?`
- `Which customer pain points appear most often across the research notes?`
- `What is the commercial wedge, and why would buyers care right now?`
- `Give me a two-minute investor update on traction, risks, and next steps.`

## Talk Track

- "This is an Apple-native host app importing the evaluation engine."
- "I can load a private document set, index it locally, and ask a real question."
- "The important part is not just the answer. It is the evidence."
- "If the model is uncertain, we want the system to surface that instead of bluffing."
- "This is the evaluation path today: founder-guided, same-toolchain, and strong enough for a design-partner motion."

## Room Discipline

- Start with the risk question because it proves synthesis across multiple docs.
- Follow with the customer-pain prompt to show repeated signal across research notes.
- End with the investor-update prompt because it sounds executive and concise.
- Do not oversell the current package as a finished toolchain-agnostic SDK.

## If Something Goes Sideways

- If Apple Intelligence is still preparing, stay in the host app and explain that the device readiness state is surfaced directly in the UI.
- If you need a fallback, use simulator to show the import path, bundled demo pack, and indexing UI.
- If the room wants proof on their own data, move the next step to a scoped evaluation against a small real document set.
