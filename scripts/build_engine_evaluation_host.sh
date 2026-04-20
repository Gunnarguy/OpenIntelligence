#!/bin/zsh
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SAMPLE_DIR="$REPO_ROOT/Samples/EngineEvaluationHost"
PROJECT_FILE="$SAMPLE_DIR/EngineEvaluationHost.xcodeproj"
XCFRAMEWORK_PATH="$REPO_ROOT/output/OpenIntelligence-SDK-Package/OpenIntelligenceEngine.xcframework"
EVALUATION_BUILD_PRODUCTS="$REPO_ROOT/output/OpenIntelligence-SDK-Package/build/evaluation/DerivedData/Build/Intermediates.noindex/ArchiveIntermediates/OpenIntelligenceEngine/BuildProductsPath/Release-iphonesimulator"

if [[ ! -d "$XCFRAMEWORK_PATH" ]]; then
  echo "error: Evaluation XCFramework not found at $XCFRAMEWORK_PATH" >&2
  echo "Run ./scripts/build_engine_evaluation_xcframework.sh first." >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is required to generate the evaluation host project." >&2
  exit 1
fi

cd "$REPO_ROOT"

if [[ ! -d "$EVALUATION_BUILD_PRODUCTS" ]]; then
  echo "Generating evaluation XCFramework build products..."
  ./scripts/build_engine_evaluation_xcframework.sh
fi

echo "Generating evaluation host project..."
xcodegen generate --spec "$SAMPLE_DIR/project.yml"

echo "Building evaluation host app for simulator..."
xcodebuild \
  -project "$PROJECT_FILE" \
  -scheme EngineEvaluationHost \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build

echo "Evaluation host app build succeeded."
