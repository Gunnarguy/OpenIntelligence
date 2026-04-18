#!/bin/zsh
set -euo pipefail

PROJECT="${PROJECT:-OpenIntelligence.xcodeproj}"
TARGET="${TARGET:-OpenIntelligenceEngine}"
OUTPUT_DIR="${OUTPUT_DIR:-output/OpenIntelligence-SDK-Package}"
BUILD_DIR="${BUILD_DIR:-$OUTPUT_DIR/build}"
FRAMEWORK_NAME="${FRAMEWORK_NAME:-$TARGET}"

function fail() {
  echo "error: $1" >&2
  exit 1
}

if [[ ! -d "$PROJECT" ]]; then
  fail "Project not found at $PROJECT"
fi

mkdir -p "$OUTPUT_DIR" "$BUILD_DIR"

LIST_OUTPUT="$(mktemp)"
trap 'rm -f "$LIST_OUTPUT"' EXIT

if ! xcodebuild -list -project "$PROJECT" >"$LIST_OUTPUT" 2>&1; then
  cat "$LIST_OUTPUT" >&2
  fail "Unable to inspect project targets. Resolve local Xcode/package issues first."
fi

if ! grep -q "^[[:space:]]*$TARGET$" "$LIST_OUTPUT"; then
  cat <<EOF >&2
error: Target '$TARGET' does not exist in $PROJECT.

Current project state:
- the repo still contains only the app target
- no dedicated framework target exists yet

Create the framework target first, then rerun:
  TARGET=$TARGET ./scripts/build_engine_xcframework.sh
EOF
  exit 1
fi

DEVICE_ARCHIVE="$BUILD_DIR/${FRAMEWORK_NAME}-iphoneos.xcarchive"
SIM_ARCHIVE="$BUILD_DIR/${FRAMEWORK_NAME}-iphonesimulator.xcarchive"
MAC_ARCHIVE="$BUILD_DIR/${FRAMEWORK_NAME}-macos.xcarchive"
XCFRAMEWORK_PATH="$OUTPUT_DIR/${FRAMEWORK_NAME}.xcframework"

rm -rf "$DEVICE_ARCHIVE" "$SIM_ARCHIVE" "$MAC_ARCHIVE" "$XCFRAMEWORK_PATH"

COMMON_ARGS=(
  -project "$PROJECT"
  -scheme "$TARGET"
  SKIP_INSTALL=NO
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES
  -derivedDataPath "$BUILD_DIR/DerivedData"
)

echo "Archiving iOS device slice..."
xcodebuild archive \
  "${COMMON_ARGS[@]}" \
  -destination "generic/platform=iOS" \
  -archivePath "$DEVICE_ARCHIVE"

echo "Archiving iOS simulator slice..."
xcodebuild archive \
  "${COMMON_ARGS[@]}" \
  -destination "generic/platform=iOS Simulator" \
  -archivePath "$SIM_ARCHIVE"

MAC_ARGS=()
if grep -q "macOS" "$LIST_OUTPUT"; then
  echo "Archiving macOS slice..."
  xcodebuild archive \
    "${COMMON_ARGS[@]}" \
    -destination "generic/platform=macOS" \
    -archivePath "$MAC_ARCHIVE"
  MAC_ARGS=(
    -framework "$MAC_ARCHIVE/Products/Library/Frameworks/${FRAMEWORK_NAME}.framework"
  )
fi

echo "Creating XCFramework..."
xcodebuild -create-xcframework \
  -framework "$DEVICE_ARCHIVE/Products/Library/Frameworks/${FRAMEWORK_NAME}.framework" \
  -framework "$SIM_ARCHIVE/Products/Library/Frameworks/${FRAMEWORK_NAME}.framework" \
  "${MAC_ARGS[@]}" \
  -output "$XCFRAMEWORK_PATH"

echo "Created:"
echo "  $XCFRAMEWORK_PATH"
