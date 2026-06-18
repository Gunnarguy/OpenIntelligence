#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="OpenIntelligence"
DESTINATION="${OPENINTELLIGENCE_SIMULATOR_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}"
ARTIFACT_DIR="${OPENINTELLIGENCE_SIMULATOR_ARTIFACT_DIR:-$ROOT_DIR/.simulator-smoke}"
DERIVED_DATA_PATH="${OPENINTELLIGENCE_SIMULATOR_DERIVED_DATA:-$ARTIFACT_DIR/DerivedData}"
BUILD_LOG="$ARTIFACT_DIR/xcodebuild.log"

mkdir -p "$ARTIFACT_DIR"

echo "Building simulator smoke target"
echo "Scheme: $SCHEME"
echo "Destination: $DESTINATION"

xcodebuild \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build | tee "$BUILD_LOG"

echo "Stripping extended attributes and codesigning in /tmp to bypass iCloud/FileProvider file locking detritus..."
TMP_APP_PATH="/tmp/OpenIntelligence_build_smoke.app"
rm -rf "$TMP_APP_PATH"
cp -R "$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/OpenIntelligence.app" "$TMP_APP_PATH"
/usr/bin/xattr -cr "$TMP_APP_PATH"
if [ -d "$TMP_APP_PATH/PlugIns/OpenIntelligenceLiveActivities.appex" ]; then
    /usr/bin/codesign --force --sign - --timestamp=none "$TMP_APP_PATH/PlugIns/OpenIntelligenceLiveActivities.appex"
fi
/usr/bin/codesign --force --sign - --timestamp=none "$TMP_APP_PATH"
rm -rf "$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/OpenIntelligence.app"
cp -R "$TMP_APP_PATH" "$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/OpenIntelligence.app"
rm -rf "$TMP_APP_PATH"

echo "Simulator smoke build succeeded"
echo "Build log: $BUILD_LOG"
