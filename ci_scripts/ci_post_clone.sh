#!/bin/sh
#
# Xcode Cloud post-clone: synchronize the Xcode project version with CHANGELOG.md.
#
# iOS MARKETING_VERSION is derived from the first "## <number>" heading in
# CHANGELOG.md. The "## [Unreleased]" heading is deliberately invisible to that
# grep because "[" is not a digit.
#
# iOS and macOS share one version line as of 2026-07-30. The old
# "MARKETING_VERSION[sdk=macosx*]" override (which tracked macOS separately at
# 2.5/3.0) was removed from project.pbxproj, so the sed below now stamps both
# platforms from the same CHANGELOG heading.
#
# See scripts/build_eval_dataset.py for the other generated-artifact guard, and
# Docs/ROADMAP.md for the release checklist.

set -e

echo "Extracting latest version from CHANGELOG.md..."

CHANGELOG="../CHANGELOG.md"

LATEST_VERSION=$(grep -m 1 "^## [0-9]" "$CHANGELOG" | awk '{print $2}')

if [ -z "$LATEST_VERSION" ]; then
    echo "Error: Could not extract version from CHANGELOG.md"
    exit 1
fi

# ---------------------------------------------------------------------------
# Guard: refuse to stamp an already-shipped version.
#
# On 2026-07-28 a build failed in App Store Connect because iOS 4.6 and macOS
# 2.5 were already released, yet CI kept stamping 4.6. The cause was that
# [Unreleased] had accumulated a release worth of entries while the first
# numbered heading below it was still the shipped 4.6.
#
# The invariant: if [Unreleased] contains entries, then the numbered heading
# beneath it describes a version that has already been cut, so stamping it is
# wrong. Promote [Unreleased] to its own numbered heading instead.
#
# A changelog entry is a line starting with "-" or a "###" subsection. HTML
# comments and blank lines do not count as content.
# ---------------------------------------------------------------------------
UNRELEASED_ENTRIES=$(
    awk '/^## \[Unreleased\]/ {inside=1; next} /^## / {inside=0} inside' "$CHANGELOG" \
        | grep -c -E '^[[:space:]]*(-|###)' || true
)

if [ "$UNRELEASED_ENTRIES" -gt 0 ]; then
    echo "======================================================================"
    echo "BUILD STOPPED: CHANGELOG [Unreleased] has $UNRELEASED_ENTRIES entrie(s)"
    echo "======================================================================"
    echo "The version this build would stamp is '$LATEST_VERSION', taken from the"
    echo "first numbered heading below [Unreleased]. Because [Unreleased] is not"
    echo "empty, that heading describes a version that was already cut — and App"
    echo "Store Connect rejects a build whose version is already released."
    echo ""
    echo "Fix: promote the [Unreleased] entries to their own heading, e.g."
    echo ""
    echo "    ## [Unreleased]"
    echo ""
    echo "    ## <next version> - <YYYY-MM-DD>"
    echo "    ### Added"
    echo "    - ..."
    echo ""
    echo "Then bump \"MARKETING_VERSION[sdk=macosx*]\" in project.pbxproj if the"
    echo "macOS version is also shipping; CI does not touch that override."
    echo "======================================================================"
    exit 1
fi

echo "Latest version found: $LATEST_VERSION"

cd ..

# Update the global MARKETING_VERSION (iOS). Strictly matches
# "MARKETING_VERSION = x.y.z;" so the bracketed macOS override is left alone.
sed -i '' -E "s/MARKETING_VERSION = [0-9.]*;/MARKETING_VERSION = $LATEST_VERSION;/g" OpenIntelligence.xcodeproj/project.pbxproj

# Verify the substitution landed, and report the macOS version alongside it so
# a mismatched pair is visible in the build log rather than discovered at upload.
IOS_COUNT=$(grep -c "MARKETING_VERSION = $LATEST_VERSION;" OpenIntelligence.xcodeproj/project.pbxproj || true)
if [ "$IOS_COUNT" -eq 0 ]; then
    echo "Error: MARKETING_VERSION substitution did not apply to project.pbxproj"
    exit 1
fi

STRAY_OVERRIDE=$(grep -c 'MARKETING_VERSION\[sdk=macosx\*\]' OpenIntelligence.xcodeproj/project.pbxproj || true)
if [ "$STRAY_OVERRIDE" -gt 0 ]; then
    echo "Error: a macOS MARKETING_VERSION override reappeared in project.pbxproj."
    echo "iOS and macOS share one version line; remove it so both stamp $LATEST_VERSION."
    exit 1
fi

echo "Synchronized project version with CHANGELOG.md"
echo "  iOS + macOS MARKETING_VERSION = $LATEST_VERSION  ($IOS_COUNT targets)"

# Informational canary: alert (without failing) the moment Apple's SDK exposes
# developer-selectable AFM 3 Core Advanced. See scripts/probe_afm_advanced_canary.sh
sh ../scripts/probe_afm_advanced_canary.sh || true

# ---------------------------------------------------------------------------
# Capability guard, moved here from .github/workflows/ci.yml on 2026-08-28 when
# GitHub Actions was retired in favour of Xcode Cloud.
#
# verify_capabilities.py checks that the code behind every publicly claimed
# capability still exists, so a claim cannot outlive its implementation. It ran
# on every Actions push; without this it would have run nowhere, and deleting
# Actions would have quietly cost a protection rather than just cost nothing.
#
# It is pure Python plus grep, so it costs a second or two and needs no
# toolchain. Failing here stops the build before xcodebuild starts, which is the
# cheapest place to fail.
# ---------------------------------------------------------------------------
echo "Verifying claimed capabilities still have their implementation..."

# Resolve from this script's own location, not the working directory.
#
# The first version of this used "../scripts/verify_capabilities.py", copying the
# relative style the rest of this file uses for ../CHANGELOG.md. On Xcode Cloud it
# exited 2 -- python3's "cannot open file" -- and failed build 426, because the
# working directory Xcode Cloud runs post-clone scripts from is not guaranteed to
# be ci_scripts. Deriving the path from $0 works from any directory.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# --- 5.2 and later need Swift 6.4 (Xcode 27) --------------------------------
#
# Every Private Cloud Compute path sits behind `#if compiler(>=6.4)`. A 5.2+
# archive built by an older toolchain would pass every step for fourteen
# minutes and then fail ci_post_xcodebuild.sh's Gate 1. Fail here instead, in
# seconds, with the cause named. Added 2026-09-02 when 5.2 was staged ahead of
# the Xcode 27 release, so that every push until then fails fast rather than
# producing a 5.2 build that cannot ship.
SWIFT_VER="$(swift --version 2>/dev/null | sed -nE 's/.*Swift version ([0-9]+\.[0-9]+).*/\1/p' | head -1)"
NEEDS_64="$(printf '%s\n5.2\n' "$LATEST_VERSION" | sort -V | head -1 | { read -r lowest; [ "$lowest" = "5.2" ] && echo 1 || echo 0; })"
if [ "$NEEDS_64" -eq 1 ]; then
    if [ -z "$SWIFT_VER" ] || [ "$(printf '%s\n6.4\n' "$SWIFT_VER" | sort -V | head -1)" != "6.4" ]; then
        echo "ERROR: version $LATEST_VERSION requires Swift 6.4 (Xcode 27) so Private Cloud Compute compiles in."
        echo "       This runner has Swift ${SWIFT_VER:-unknown}. Repoint the workflow's Xcode version:"
        echo "       ruby scripts/xcode_cloud_toolchain.rb --set 'Xcode 27'"
        exit 1
    fi
    echo "Swift $SWIFT_VER satisfies the 5.2+ requirement (>= 6.4)."
fi

GUARD="$SCRIPT_DIR/../scripts/verify_capabilities.py"

if [ ! -f "$GUARD" ]; then
    echo "Error: capability guard not found at $GUARD"
    echo "Refusing to build rather than skipping a check and reporting success."
    exit 1
fi

PY=""
for candidate in python3 /usr/bin/python3; do
    if command -v "$candidate" >/dev/null 2>&1; then PY="$candidate"; break; fi
done
if [ -z "$PY" ]; then
    echo "Error: no python3 found, so the capability guard cannot run."
    echo "Refusing to build rather than skipping a check and reporting success."
    exit 1
fi

"$PY" "$GUARD"
