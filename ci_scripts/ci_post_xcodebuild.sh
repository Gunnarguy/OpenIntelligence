#!/bin/sh
#
# Xcode Cloud post-xcodebuild: refuse to ship a binary that contradicts the
# release notes.
#
# WHY THIS EXISTS
#
# Every Private Cloud Compute path in this app sits behind `#if compiler(>=6.4)`,
# in 12 places. Which way that resolves is decided entirely by the toolchain:
#
#     Xcode 26.6  ->  Swift 6.3.3  ->  false  ->  PCC compiled OUT   (correct)
#     Xcode 27    ->  Swift 6.4    ->  true   ->  PCC compiled IN    (wrong)
#
# Measured on 2026-08-28, not inferred. The App Store description, the README and
# the in-app copy all state that shipped builds do not contain PCC. A build made
# with the wrong toolchain contradicts all three, and it does so silently: it
# compiles, it archives, it validates, it uploads. Nothing fails.
#
# Until 5.1 the workflow was pinned to Xcode 26.6 for exactly this reason, and
# this script was the check that the pin was still doing its job. From 5.2 the
# same script checks the opposite: see Gate 1. A pin can be changed in the App
# Store Connect UI by anyone, including by accident, and "Latest Release" will
# become Xcode 27 the day Apple ships it. The pin is the intent; this is the
# proof.
#
# The equivalent gate ran in .github/workflows/app-store-upload.yml and is kept
# byte-for-byte in spirit here so that moving releases to Xcode Cloud does not
# quietly drop a protection that has already stopped a bad binary twice.
#
# FAILING LOUDLY IS THE POINT
#
# If this script cannot locate the binary, it exits non-zero rather than passing.
# A gate that silently finds nothing to check is worse than no gate: it reports
# success and teaches you to trust it. That is the same failure shape as the
# padding bug that caused 5.0, and it is not repeated here.

set -eu

echo "=== ci_post_xcodebuild: release gates ==="
echo "action:  ${CI_XCODEBUILD_ACTION:-<unset>}"
echo "archive: ${CI_ARCHIVE_PATH:-<unset>}"

# Only archives ship. Builds and tests have no artifact to police, so skip
# without failing -- but say so, so a silent skip is never mistaken for a pass.
if [ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]; then
    echo "Not an archive action. Gates do not apply. Skipping."
    exit 0
fi

if [ -z "${CI_ARCHIVE_PATH:-}" ] || [ ! -d "${CI_ARCHIVE_PATH}" ]; then
    echo "ERROR: this is an archive action but CI_ARCHIVE_PATH is unset or not a directory."
    echo "       Refusing to report success without having checked anything."
    exit 1
fi

APP="$(find "${CI_ARCHIVE_PATH}/Products/Applications" -maxdepth 1 -name '*.app' -print 2>/dev/null | head -1)"
if [ -z "$APP" ]; then
    echo "ERROR: no .app found under ${CI_ARCHIVE_PATH}/Products/Applications"
    exit 1
fi
NAME="$(basename "$APP" .app)"
echo "app:     $APP"

# macOS nests the executable, iOS does not. Detect rather than depend on a
# platform variable, so this keeps working if the workflow's actions change.
if [ -f "$APP/Contents/MacOS/$NAME" ]; then
    BIN="$APP/Contents/MacOS/$NAME"
    PLIST="$APP/Contents/Info.plist"
elif [ -f "$APP/$NAME" ]; then
    BIN="$APP/$NAME"
    PLIST="$APP/Info.plist"
else
    echo "ERROR: no executable at either macOS or iOS layout inside $APP"
    exit 1
fi
echo "binary:  $BIN"
echo

# --- Gate 1: the binary must agree with the version it is stamped with -----
#
# The control is load-bearing. If FoundationModels is not linked at all, `nm -u`
# finds no PCC symbols for a reason that has nothing to do with the toolchain,
# and a bare count check would pass while proving nothing. Requiring a non-zero
# control makes the gate prove it can see what it is looking for.
#
# Which direction the gate points is decided by the version, not by hand.
# Until 5.1 the release notes said PCC is compiled out, so any PCC symbol was a
# contradiction. From 5.2 the notes say it is on, so ZERO PCC symbols is the
# contradiction: a toolchain regression that quietly compiled it back out would
# ship against copy that promises it. Same gate, both directions, one switch:
# the first numbered heading in CHANGELOG.md, which ci_post_clone.sh stamps
# into CFBundleShortVersionString. Written 2026-09-02, when 5.2 was staged.
PCC="$(nm -u "$BIN" 2>/dev/null | grep -c PrivateCloudCompute || true)"
CONTROL="$(nm -u "$BIN" 2>/dev/null | grep -c SystemLanguageModel || true)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null || echo '')"
echo "version:                     ${VERSION:-<absent>}"
echo "SystemLanguageModel symbols: $CONTROL (control, must be > 0)"
if [ "$CONTROL" -eq 0 ]; then
    echo "ERROR: control is 0, so this check proves nothing."
    echo "       FoundationModels is not linked as expected. Investigate before shipping."
    exit 1
fi
if [ -z "$VERSION" ]; then
    echo "ERROR: no CFBundleShortVersionString, so the gate cannot know which way to point."
    exit 1
fi
# Semantic compare: PCC_EXPECTED=1 when version >= 5.2
PCC_EXPECTED="$(printf '%s\n5.2\n' "$VERSION" | sort -V | head -1 | { read -r lowest; [ "$lowest" = "5.2" ] && echo 1 || echo 0; })"
if [ "$PCC_EXPECTED" -eq 1 ]; then
    echo "PrivateCloudCompute symbols: $PCC (version $VERSION: must be > 0)"
    if [ "$PCC" -eq 0 ]; then
        echo "ERROR: version $VERSION promises Private Cloud Compute and this binary has none."
        echo "       The toolchain compiled the #if compiler(>=6.4) sites out. Almost certainly"
        echo "       the workflow's Xcode version is still 26.6; 5.2 needs Xcode 27."
        echo "       ruby scripts/xcode_cloud_toolchain.rb   lists and sets it."
        exit 1
    fi
    echo "PASS: PCC compiled in, as $VERSION requires."
else
    echo "PrivateCloudCompute symbols: $PCC (version $VERSION: must be 0)"
    if [ "$PCC" -ne 0 ]; then
        echo "ERROR: $PCC PrivateCloudCompute symbols are linked into this binary."
        echo "       This build would ship PCC into a release whose notes say it does not."
        echo "       Almost certainly the workflow's Xcode version is no longer 26.6."
        echo "       Check the pin in App Store Connect before doing anything else."
        exit 1
    fi
    echo "PASS: PCC compiled out, as $VERSION requires."
fi
echo

# --- Gate 2: the build machine stamp must not be prerelease -----------------
#
# App Store ingestion rejects a prerelease BuildMachineOSBuild with ITMS-90111,
# regardless of which Xcode produced the binary. Builds 376 and 377 were rejected
# this way after `altool --validate-app` had returned VERIFY SUCCEEDED for both:
# validation is not ingestion. Apple's runners use released OS builds so this
# should always pass here, which is precisely why it is worth asserting -- if it
# ever fails, something about the runner image changed.
STAMP="$(/usr/libexec/PlistBuddy -c 'Print :BuildMachineOSBuild' "$PLIST" 2>/dev/null || echo '')"
echo "BuildMachineOSBuild: ${STAMP:-<absent>}"
if [ -z "$STAMP" ]; then
    echo "WARNING: no BuildMachineOSBuild in Info.plist. Not failing, but unexpected."
else
    # Apple's prerelease build numbers carry a lowercase letter suffix after the
    # trailing digits, e.g. 26A5406e. Released builds do not, e.g. 25G83.
    if printf '%s' "$STAMP" | grep -qE '[0-9][a-z]$'; then
        echo "ERROR: '$STAMP' looks like a prerelease OS build."
        echo "       App Store ingestion will reject this with ITMS-90111."
        exit 1
    fi
    echo "PASS: released OS build stamp."
fi
echo

# --- Gate 3: bundle hygiene -------------------------------------------------
#
# Extended attributes stamped by iCloud/FileProvider make codesign fail with
# "resource fork, Finder information, or similar detritus not allowed". That is a
# local-Mac problem rather than a runner one, but it costs nothing to assert and
# names the cause immediately if it ever appears.
if xattr -lr "$APP" 2>/dev/null | grep -qE 'com\.apple\.(FinderInfo|fileprovider)'; then
    echo "ERROR: iCloud/FileProvider extended attributes present in the app bundle."
    echo "       These break codesign. Run scripts/check_icloud_conflicts.sh --fix."
    exit 1
fi
echo "PASS: no FinderInfo/fileprovider xattrs in the bundle."
echo

echo "=== all release gates passed ==="
