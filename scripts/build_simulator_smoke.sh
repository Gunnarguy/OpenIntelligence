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
  build | tee "$BUILD_LOG"

echo "Simulator smoke build succeeded"
echo "Build log: $BUILD_LOG"
