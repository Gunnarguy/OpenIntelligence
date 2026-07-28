#!/bin/sh
#
# Canary: does the installed SDK expose a developer-selectable AFM 3 Core
# Advanced model yet?
#
# Background (2026-07-28): WWDC26 announced AFM 3 Core Advanced — a real 20B
# sparse on-device model, "unlocked by and optimized for our most capable
# Apple silicon systems." As of Xcode 27.0 beta (27A5194q) it is OS-managed
# only: the FoundationModels public surface has no way for an app to select
# it or observe whether it served a request (full-interface enumeration:
# zero matches for advanced/tier/20B; UseCase = {general, contentTagging}).
#
# This probe INVERTS the repo's TE-02 check: instead of proving the API is
# absent, it alerts the moment Apple ships it, so the app can adopt
# Core Advanced selection the day it becomes real. Non-fatal by design.

PROBE_DIR="$(mktemp -d)"
trap 'rm -rf "$PROBE_DIR"' EXIT

cat > "$PROBE_DIR/probe.swift" <<'SWIFT'
import FoundationModels
@available(iOS 27.0, macOS 27.0, *)
func probe() { _ = SystemLanguageModel.advanced }
SWIFT

SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null)
if [ -z "$SDK_PATH" ]; then
    echo "[afm-canary] no iphonesimulator SDK available; skipping"
    exit 0
fi

if xcrun swiftc -typecheck -sdk "$SDK_PATH" \
    -target arm64-apple-ios27.0-simulator \
    "$PROBE_DIR/probe.swift" >/dev/null 2>&1; then
    echo "=================================================================="
    echo "[afm-canary] ALERT: SystemLanguageModel.advanced NOW COMPILES."
    echo "Apple has exposed AFM 3 Core Advanced to developers in this SDK."
    echo "Revisit: FoundationModelSessionFactory routes, LLMModel labels,"
    echo "Docs/LIMITATIONS.md, and the capability card copy."
    echo "=================================================================="
else
    echo "[afm-canary] SystemLanguageModel.advanced still absent from this SDK (expected)."
fi
exit 0
