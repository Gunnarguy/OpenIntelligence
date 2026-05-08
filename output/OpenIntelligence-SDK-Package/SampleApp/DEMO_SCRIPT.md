# Evaluation Sample App Demo Script

## Goal

Run a five-minute live demo that proves three things:

- the SDK imports cleanly into a host app
- private documents can be indexed locally
- grounded answers come back with evidence, not just fluent text

## Packet-Local Setup

1. Run `./build_sample_app.sh`.
2. Open `EngineEvaluationHost.xcodeproj` in Xcode.
3. Choose an Apple Intelligence-capable iPhone for the full live flow.
4. If Xcode asks for signing, select your own development team.
5. Press Run.

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

- "This host app is importing the OpenIntelligence evaluation engine from the packet you received."
- "The commercial lane today is the source-distributed SDK in the private repo. This packet-local host is the self-contained evaluation fallback."
- "I can load a private document set, index it locally, and ask a real question."
- "The important part is not just the answer. It is the evidence."
- "If the model is uncertain, we want the system to surface that instead of bluffing."
- "This is the evaluation path today: same-toolchain, founder-guided, and strong enough for a design-partner motion."

## If Something Goes Sideways

- If Apple Intelligence is still preparing, stay in the host app and explain that the device readiness state is surfaced directly in the UI.
- If you need a fallback, use simulator to show the import path, bundled demo pack, and indexing UI.
- If the room wants proof on their own data, move the next step to a scoped evaluation against a small real document set.
