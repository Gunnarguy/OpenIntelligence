#!/usr/bin/env bash
# Minimal release preflight: secret scan + Info.plist privacy checks.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PBXPROJ="$ROOT_DIR/OpenIntelligence.xcodeproj/project.pbxproj"

if [[ ! -f "$PROJECT_PBXPROJ" ]]; then
  echo "error: expected project file at $PROJECT_PBXPROJ" >&2
  exit 1
fi

echo "🔍 Running secret scan..."
python3 "$ROOT_DIR/scripts/secret_scan.py" "$ROOT_DIR"

echo "🔒 Verifying Info.plist privacy keys..."
missing=0
required_keys=(
  "INFOPLIST_KEY_NSCameraUsageDescription"
  "INFOPLIST_KEY_NSPhotoLibraryUsageDescription"
  "INFOPLIST_KEY_NSMicrophoneUsageDescription"
  "INFOPLIST_KEY_NSSpeechRecognitionUsageDescription"
  "INFOPLIST_KEY_NSLocalNetworkUsageDescription"
  "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption"
)
for key in "${required_keys[@]}"; do
  if ! grep -q "$key" "$PROJECT_PBXPROJ"; then
    echo "  • missing $key" >&2
    missing=1
  fi
done

if [[ $missing -ne 0 ]]; then
  echo "❌ preflight: add the missing Info.plist keys before shipping" >&2
  exit 1
fi

echo "✅ preflight: secrets clean and privacy keys present"
