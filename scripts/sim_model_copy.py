#!/usr/bin/env python3
"""Patch a scratch copy of OpenIntelligence so the app's own model service answers in the iOS 27 Simulator.

    python3 scripts/sim_model_copy.py /private/tmp/oi-eval-src

Only for a copy outside the repository (`git archive HEAD | tar -x -C <dir>`); it refuses to patch the repository
itself. Apple's model answers in the iOS 27.0 Simulator on this Mac (measured 2026-10-01), but the app switches its
own service off there under `#if targetEnvironment(simulator)`, from August when it did not. A test that brings a
model of its own instead (`AnswerQualityEvaluationTests` until 2026-11-11) takes other paths through the engine: 17
places branch on `llmService is AppleFoundationLLMService` (context budget, compact context, auto-escalation, the
agentic path). With this copy the engine runs the service the phone runs.

Four switches, each found by its content so a moved line still matches, and the script stops if one is not found
exactly once:
  1. `AppleFoundationLLMService.isAvailable` (AppleFoundationLLMService.swift)
  2. RAGService's device capability check (RAGService+Device.swift)
  3. `OIEngine.availability` (SDK/OpenIntelligenceEngine.swift)
  4. the chip the Simulator reports, A14 Bionic, read as the owner's iPhone 16 Pro Max's A18 Pro
The Private Cloud Compute guards stay: PCC cannot be reached from the Simulator. The embedding model already runs on
the CPU in the Simulator (`DeviceCapabilityService.simulatorComputeUnits`, since 5.8), which the PostDesk demo
script (`Tools/demos/oi/patch_sim_switches.py`, 2026-10-08) still patches by hand; this script does not need to.
"""

import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OFF = "#if targetEnvironment(simulator) && OI_SIM_MODEL_COPY_KEEP_SWITCH"


def switch(root: Path, path: str, next_line: str) -> None:
    """Turn off the `#if targetEnvironment(simulator)` whose next line starts with `next_line`."""
    file = root / path
    lines = file.read_text().split("\n")
    hits = [i for i, line in enumerate(lines[:-1])
            if line.strip() == "#if targetEnvironment(simulator)" and lines[i + 1].strip().startswith(next_line)]
    if len(hits) != 1:
        sys.exit(f"{path}: the switch before {next_line!r} was found {len(hits)} times, not once")
    lines[hits[0]] = lines[hits[0]].replace("#if targetEnvironment(simulator)", OFF)
    file.write_text("\n".join(lines))


def replace(root: Path, path: str, old: str, new: str) -> None:
    file = root / path
    text = file.read_text()
    if text.count(old) != 1:
        sys.exit(f"{path}: {old[:60]!r} was found {text.count(old)} times, not once")
    file.write_text(text.replace(old, new))


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    root = Path(sys.argv[1]).resolve()
    if root == REPO or REPO in root.parents or root in REPO.parents:
        sys.exit("Refusing: this patches a scratch copy, never the repository.")
    if not (root / "OpenIntelligence.xcodeproj").exists():
        sys.exit(f"{root} is not a copy of the repository.")
    switch(root, "OpenIntelligence/Services/LLM/AppleFoundationLLMService.swift",
           "// Foundation Models + PCC are not available inside the simulator runtime")
    switch(root, "OpenIntelligence/Services/RAG/Orchestration/RAGService+Device.swift",
           "// Simulator: Foundation Models not available")
    switch(root, "OpenIntelligence/SDK/OpenIntelligenceEngine.swift", "return .simulatorUnsupported")
    replace(root, "OpenIntelligence/Services/RAG/Orchestration/RAGService+Device.swift",
            "return .a14Bionic  // Don't claim Apple Intelligence support in simulator",
            "return .a18Pro  // Model copy (scripts/sim_model_copy.py): the chip of the owner's iPhone 16 Pro Max")
    (root / "SIM_MODEL_COPY").write_text("Patched by scripts/sim_model_copy.py: never commit from this folder.\n")
    print("patched 4")


if __name__ == "__main__":
    main()
