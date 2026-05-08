#!/bin/zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DESTINATION_FILE="$REPO_ROOT/build/openintelligence-ios-sim-destination.json"
SWIFT_BIN="$(xcrun --find swift)"
TOOLCHAIN_BIN_DIR="$(dirname "$SWIFT_BIN")"
IOS_SIM_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"

mkdir -p "$(dirname "$DESTINATION_FILE")"

cat > "$DESTINATION_FILE" <<EOF
{
  "version": 1,
  "sdk": "$IOS_SIM_SDK",
  "toolchain-bin-dir": "$TOOLCHAIN_BIN_DIR",
  "target": "arm64-apple-ios26.0-simulator",
  "dynamic-library-extension": "dylib",
  "extra-cc-flags": [],
  "extra-cpp-flags": [],
  "extra-swiftc-flags": [],
  "extra-linker-flags": []
}
EOF

cd "$REPO_ROOT"

echo "Validating root Swift package manifest..."
swift package describe > /dev/null

echo "Building source SDK package for iOS Simulator..."
swift build --destination "$DESTINATION_FILE"

rm -f "$REPO_ROOT/Package.resolved"

echo
echo "Source SDK package validation passed."
echo "Destination file: $DESTINATION_FILE"
