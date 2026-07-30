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
