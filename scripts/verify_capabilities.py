#!/usr/bin/env python3
"""Verify that the code behind every publicly claimed capability still exists.

Companion to Docs/SHIPPED_VERSION.json's role for version numbers. That marker
was written after gunzino.me advertised a version nobody could install. This one
exists because on 2026-08-26 the same failure was found in the other axis:
nineteen places across three websites and the App Store listing described
Private Cloud Compute as a live capability, and one stated that "native PCC
shipped in v4.6". It never shipped in any App Store build.

What this can and cannot do, stated plainly so nobody mistakes it for more:

  It CAN catch an implementation being deleted or renamed while the public claim
  stays up. That is the drift that actually happened here -- Settings advertised
  eight agentic tools when four were wired up.

  It CANNOT prove a capability works. A symbol existing is not the same as a
  feature functioning, and no grep will tell you otherwise. Device verification
  is still the only thing that closes a behavioural claim.

Exit codes: 0 all anchors present, 1 an anchor is missing or under its minimum.
"""

import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MARKER = ROOT / "Docs" / "SHIPPED_CAPABILITIES.json"
SOURCE = ROOT / "OpenIntelligence"

# Only first-party Swift. Without this the scan walks swift-transformers/.build,
# which holds a libTokenizers.a and precompiled module caches, and the ML model
# bundles -- hundreds of megabytes of binaries that no capability anchor lives in
# and that push a run past two minutes. That same .build directory is what got an
# upload rejected with 90171 when it was not excluded from the ipa.
EXCLUDES = ["--exclude-dir=.build", "--exclude-dir=DerivedData", "--exclude-dir=.git"]


def occurrences(needle: str) -> int:
    """Count files containing `needle`. Fixed-string, so Swift syntax needs no escaping."""
    result = subprocess.run(
        ["grep", "-rlF", "--include=*.swift", *EXCLUDES, needle, str(SOURCE)],
        capture_output=True,
        text=True,
    )
    return len([line for line in result.stdout.splitlines() if line.strip()])


def total_matches(needle: str) -> int:
    """Count total matches, not files. Used where a claim is a number."""
    result = subprocess.run(
        ["grep", "-rhoF", "--include=*.swift", *EXCLUDES, needle, str(SOURCE)],
        capture_output=True,
        text=True,
    )
    return len([line for line in result.stdout.splitlines() if line.strip()])


def main() -> int:
    if not MARKER.exists():
        print(f"::error::{MARKER} is missing.")
        return 1

    data = json.loads(MARKER.read_text(encoding="utf-8"))
    capabilities = data.get("capabilities", {})
    if not capabilities:
        print("::error::No capabilities declared.")
        return 1

    failures = []
    print(f"Verifying {len(capabilities)} declared capabilities against {SOURCE.name}/\n")

    for name, spec in sorted(capabilities.items()):
        status = spec.get("status", "unknown")
        anchors = spec.get("anchors", [])
        minimum = spec.get("min_count")
        missing = [a for a in anchors if occurrences(a) == 0]

        line = f"  {name:<24} {status:<18}"

        if missing:
            failures.append(
                f"{name}: anchor(s) not found in the source tree: {', '.join(missing)}. "
                f"The public claim is {spec.get('public_claim', '(none recorded)')!r}. "
                f"Either the implementation moved and this marker needs updating, or the "
                f"claim is no longer true and the public copy needs correcting."
            )
            print(line + "MISSING: " + ", ".join(missing))
            continue

        if minimum is not None:
            found = max(total_matches(a) for a in anchors)
            if found < minimum:
                failures.append(
                    f"{name}: expected at least {minimum} occurrences of "
                    f"{anchors[0]!r}, found {found}. The public claim states a number; "
                    f"correct the claim or the marker, and do not round."
                )
                print(line + f"COUNT {found} < {minimum}")
                continue
            print(line + f"ok ({found} occurrences)")
            continue

        print(line + "ok")

    if failures:
        print("\n" + "=" * 70)
        for f in failures:
            print(f"::error::{f}")
        print("=" * 70)
        return 1

    print("\nAll declared capabilities still have their implementation.")
    print("This does NOT prove they work. Behavioural claims still close on device.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
