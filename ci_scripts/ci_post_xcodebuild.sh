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
# The workflow is pinned to Xcode 26.6 for exactly this reason. This script is
# the check that the pin is still doing its job. A pin can be changed in the App
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

# --- Gate 1: Private Cloud Compute must be compiled out ---------------------
#
# The control is load-bearing. If FoundationModels is not linked at all, `nm -u`
# finds no PCC symbols for a reason that has nothing to do with the toolchain,
# and a bare "PCC == 0" check would pass while proving nothing. Requiring a
# non-zero control makes the gate prove it can see what it is looking for.
PCC="$(nm -u "$BIN" 2>/dev/null | grep -c PrivateCloudCompute || true)"
CONTROL="$(nm -u "$BIN" 2>/dev/null | grep -c SystemLanguageModel || true)"

echo "PrivateCloudCompute symbols: $PCC (must be 0)"
echo "SystemLanguageModel symbols: $CONTROL (control, must be > 0)"

if [ "$CONTROL" -eq 0 ]; then
    echo "ERROR: control is 0, so this check proves nothing."
    echo "       FoundationModels is not linked as expected. Investigate before shipping."
    exit 1
fi

if [ "$PCC" -ne 0 ]; then
    echo "ERROR: $PCC PrivateCloudCompute symbols are linked into this binary."
    echo "       This build would ship PCC into a release whose notes say it does not."
    echo "       Almost certainly the workflow's Xcode version is no longer 26.6."
    echo "       Check the pin in App Store Connect before doing anything else."
    exit 1
fi
echo "PASS: PCC compiled out."
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
