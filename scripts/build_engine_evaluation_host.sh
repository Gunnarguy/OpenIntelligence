#!/bin/zsh
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SAMPLE_DIR="$REPO_ROOT/Samples/EngineEvaluationHost"
PROJECT_FILE="$SAMPLE_DIR/EngineEvaluationHost.xcodeproj"
XCFRAMEWORK_PATH="$REPO_ROOT/output/OpenIntelligence-SDK-Package/OpenIntelligenceEngine.xcframework"
EVALUATION_SUPPORT_SIMULATOR_DIR="$REPO_ROOT/output/OpenIntelligence-SDK-Package/EvaluationSupport/iphonesimulator"
EVALUATION_SUPPORT_DEVICE_DIR="$REPO_ROOT/output/OpenIntelligence-SDK-Package/EvaluationSupport/iphoneos"
DEMO_SCRIPT_PATH="$SAMPLE_DIR/DEMO_SCRIPT.md"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/EngineEvaluationHost-DerivedData}"

if [[ ! -d "$XCFRAMEWORK_PATH" ]]; then
  echo "error: Evaluation XCFramework not found at $XCFRAMEWORK_PATH" >&2
  echo "Run ./scripts/build_engine_evaluation_xcframework.sh first to stage or restore it." >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is required to generate the evaluation host project." >&2
  exit 1
fi

cd "$REPO_ROOT"

if [[ ! -d "$EVALUATION_SUPPORT_SIMULATOR_DIR" || ! -d "$EVALUATION_SUPPORT_DEVICE_DIR" ]]; then
  echo "Staging evaluation XCFramework and support artifacts..."
  ./scripts/build_engine_evaluation_xcframework.sh
fi

echo "Generating evaluation host project..."
xcodegen generate --spec "$SAMPLE_DIR/project.yml"

echo "Building evaluation host app for simulator..."
xcodebuild \
  -quiet \
  -project "$PROJECT_FILE" \
  -scheme EngineEvaluationHost \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build

cat <<EOF
Evaluation host app simulator build succeeded.

Next:
- Open $PROJECT_FILE in Xcode
- Read $DEMO_SCRIPT_PATH for the five-minute room-demo flow
- In the app, tap Load Demo Pack before indexing
- Choose an Apple Intelligence-capable iPhone for the live grounded-answer demo
EOF
