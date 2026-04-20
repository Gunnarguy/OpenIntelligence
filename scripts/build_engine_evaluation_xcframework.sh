#!/bin/zsh
set -euo pipefail

PROJECT="${PROJECT:-OpenIntelligence.xcodeproj}"
TARGET="${TARGET:-OpenIntelligenceEngine}"
OUTPUT_DIR="${OUTPUT_DIR:-output/OpenIntelligence-SDK-Package}"
BUILD_DIR="${BUILD_DIR:-$OUTPUT_DIR/build/evaluation}"
FRAMEWORK_NAME="${FRAMEWORK_NAME:-$TARGET}"

function fail() {
  echo "error: $1" >&2
  exit 1
}

[[ -d "$PROJECT" ]] || fail "Project not found at $PROJECT"

mkdir -p "$OUTPUT_DIR" "$BUILD_DIR"

DEVICE_ARCHIVE="$BUILD_DIR/${FRAMEWORK_NAME}-iphoneos.xcarchive"
SIM_ARCHIVE="$BUILD_DIR/${FRAMEWORK_NAME}-iphonesimulator.xcarchive"
XCFRAMEWORK_PATH="$OUTPUT_DIR/${FRAMEWORK_NAME}.xcframework"
CLEAN_DIR="$BUILD_DIR/clean-xcframework-inputs"

rm -rf "$DEVICE_ARCHIVE" "$SIM_ARCHIVE" "$XCFRAMEWORK_PATH" "$CLEAN_DIR"

COMMON_ARGS=(
  -project "$PROJECT"
  -scheme "$TARGET"
  SKIP_INSTALL=NO
  BUILD_LIBRARY_FOR_DISTRIBUTION=NO
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
  -derivedDataPath "$BUILD_DIR/DerivedData"
)

echo "Archiving evaluation iOS device slice..."
xcodebuild archive \
  "${COMMON_ARGS[@]}" \
  -destination "generic/platform=iOS" \
  -archivePath "$DEVICE_ARCHIVE"

echo "Archiving evaluation iOS simulator slice..."
xcodebuild archive \
  "${COMMON_ARGS[@]}" \
  -destination "generic/platform=iOS Simulator" \
  -archivePath "$SIM_ARCHIVE"

mkdir -p "$CLEAN_DIR/device" "$CLEAN_DIR/sim"

echo "Preparing clean XCFramework inputs..."
/usr/bin/ditto --noextattr --noqtn \
  "$DEVICE_ARCHIVE/Products/Library/Frameworks/${FRAMEWORK_NAME}.framework" \
  "$CLEAN_DIR/device/${FRAMEWORK_NAME}.framework"
/usr/bin/ditto --noextattr --noqtn \
  "$SIM_ARCHIVE/Products/Library/Frameworks/${FRAMEWORK_NAME}.framework" \
  "$CLEAN_DIR/sim/${FRAMEWORK_NAME}.framework"

/bin/rm -rf \
  "$CLEAN_DIR/device/${FRAMEWORK_NAME}.framework/swift-transformers" \
  "$CLEAN_DIR/sim/${FRAMEWORK_NAME}.framework/swift-transformers" \
  "$CLEAN_DIR/device/${FRAMEWORK_NAME}.framework/.gitignore" \
  "$CLEAN_DIR/sim/${FRAMEWORK_NAME}.framework/.gitignore"

echo "Creating evaluation XCFramework..."
xcodebuild -create-xcframework \
  -allow-internal-distribution \
  -framework "$CLEAN_DIR/device/${FRAMEWORK_NAME}.framework" \
  -framework "$CLEAN_DIR/sim/${FRAMEWORK_NAME}.framework" \
  -output "$XCFRAMEWORK_PATH"

cat <<EOF
Created evaluation XCFramework:
  $XCFRAMEWORK_PATH

Important:
- This build uses BUILD_LIBRARY_FOR_DISTRIBUTION=NO
- Treat it as a founder/design-partner evaluation artifact
- Consumers should use a matching Xcode and Swift toolchain generation
EOF
