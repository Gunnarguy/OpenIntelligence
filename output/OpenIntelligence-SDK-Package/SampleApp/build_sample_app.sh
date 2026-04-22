#!/bin/zsh
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

ROOT_DIR="${ROOT_DIR:-$(cd "$(/usr/bin/dirname "$0")" && pwd)}"
PROJECT_FILE="$ROOT_DIR/EngineEvaluationHost.xcodeproj"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/OpenIntelligenceEngine-EvaluationHost}"

/usr/bin/xcodebuild \
  -quiet \
  -project "$PROJECT_FILE" \
  -scheme EngineEvaluationHost \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

echo "Evaluation sample app build succeeded."
echo "Open $PROJECT_FILE in Xcode for live device testing."
