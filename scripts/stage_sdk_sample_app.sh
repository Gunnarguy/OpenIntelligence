#!/bin/zsh
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

REPO_ROOT="${REPO_ROOT:-$(cd "$(/usr/bin/dirname "$0")/.." && pwd)}"
SOURCE_DIR="$REPO_ROOT/Samples/EngineEvaluationHost"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/output/OpenIntelligence-SDK-Package}"
SAMPLE_DIR="$OUTPUT_DIR/SampleApp"
PROJECT_FILE="$SOURCE_DIR/EngineEvaluationHost.xcodeproj/project.pbxproj"
PROJECT_SPEC="$SOURCE_DIR/project.yml"
STAGED_PROJECT_FILE="$SAMPLE_DIR/EngineEvaluationHost.xcodeproj/project.pbxproj"
STAGED_PROJECT_SPEC="$SAMPLE_DIR/project.yml"

function fail() {
  echo "error: $1" >&2
  exit 1
}

[[ -d "$SOURCE_DIR/EngineEvaluationHost" ]] || fail "Sample source directory not found at $SOURCE_DIR/EngineEvaluationHost"
[[ -f "$PROJECT_SPEC" ]] || fail "Sample project spec not found at $PROJECT_SPEC"

if [[ ! -f "$PROJECT_FILE" ]]; then
  if ! command -v xcodegen >/dev/null 2>&1; then
    fail "Sample Xcode project is missing and xcodegen is unavailable"
  fi

  echo "Generating sample host project before staging..."
  (
    cd "$REPO_ROOT"
    xcodegen generate --spec "$PROJECT_SPEC"
  )
fi

rm -rf "$SAMPLE_DIR"
mkdir -p "$SAMPLE_DIR"

/bin/cp -R "$SOURCE_DIR/EngineEvaluationHost" "$SAMPLE_DIR/"
/bin/cp -R "$SOURCE_DIR/EngineEvaluationHost.xcodeproj" "$SAMPLE_DIR/"
/bin/cp "$PROJECT_SPEC" "$SAMPLE_DIR/"

/usr/bin/perl -0pi -e 's!../../output/OpenIntelligence-SDK-Package/OpenIntelligenceEngine\.xcframework!../OpenIntelligenceEngine.xcframework!g; s!../../output/OpenIntelligence-SDK-Package/EvaluationSupport/iphonesimulator!../EvaluationSupport/iphonesimulator!g; s!../../output/OpenIntelligence-SDK-Package/EvaluationSupport/iphoneos!../EvaluationSupport/iphoneos!g; s!../../output/OpenIntelligence-SDK-Package!..!g; s/DEVELOPMENT_TEAM = Z3E334EXZD;/DEVELOPMENT_TEAM = "";/g; s/DevelopmentTeam = Z3E334EXZD;/DevelopmentTeam = "";/g' "$STAGED_PROJECT_FILE"

/usr/bin/perl -0pi -e 's!../../output/OpenIntelligence-SDK-Package/OpenIntelligenceEngine\.xcframework!../OpenIntelligenceEngine.xcframework!g; s!../../output/OpenIntelligence-SDK-Package/EvaluationSupport/iphonesimulator!../EvaluationSupport/iphonesimulator!g; s!../../output/OpenIntelligence-SDK-Package/EvaluationSupport/iphoneos!../EvaluationSupport/iphoneos!g; s!../../output/OpenIntelligence-SDK-Package!..!g; s/DEVELOPMENT_TEAM: Z3E334EXZD/DEVELOPMENT_TEAM: ""/g' "$STAGED_PROJECT_SPEC"

cat > "$SAMPLE_DIR/README.md" <<'EOF'
# Evaluation Sample App

This folder is a self-contained iOS host app for validating the OpenIntelligence evaluation SDK handoff.

What it proves:

- the XCFramework imports into a separate app
- the evaluation support modules are wired correctly for same-toolchain testing
- the bundled demo documents can be indexed and queried locally

Fastest path:

1. Run `./build_sample_app.sh` for a simulator compile check.
2. Open `EngineEvaluationHost.xcodeproj` in Xcode.
3. Read `DEMO_SCRIPT.md`.
4. For a live runtime demo, select an Apple Intelligence-capable iPhone and your own signing team.

Important:

- This is an evaluation host, not the final buyer UX.
- The project is configured to look for `../OpenIntelligenceEngine.xcframework` and `../EvaluationSupport/` in this packet.
- For device runs, choose your own development team in Xcode if required.
EOF

cat > "$SAMPLE_DIR/DEMO_SCRIPT.md" <<'EOF'
# Evaluation Sample App Demo Script

## Goal

Run a five-minute live demo that proves three things:

- the SDK imports cleanly into a host app
- private documents can be indexed locally
- grounded answers come back with evidence, not just fluent text

## Packet-Local Setup

1. Run `./build_sample_app.sh`.
2. Open `EngineEvaluationHost.xcodeproj` in Xcode.
3. Choose an Apple Intelligence-capable iPhone for the full live flow.
4. If Xcode asks for signing, select your own development team.
5. Press Run.

Simulator is fine for UI and import validation.
Use a real Apple Intelligence-capable device for the live question-answering step.

## In-App Flow

1. Launch the app and let the Room Readiness card settle.
2. In the Pitch Kit section, tap `Load Demo Pack`.
3. In Step 1, tap `Index Library`.
4. Wait for the indexing result strip to appear.
5. In Step 2, use the default risk question first.
6. In Step 3, walk the answer, confidence, warnings, and citations.

## Recommended Questions

- `What are the three biggest risks in this packet, and what evidence supports each one?`
- `Which customer pain points appear most often across the research notes?`
- `What is the commercial wedge, and why would buyers care right now?`
- `Give me a two-minute investor update on traction, risks, and next steps.`

## Talk Track

- "This host app is importing the OpenIntelligence evaluation engine from the packet you received."
- "I can load a private document set, index it locally, and ask a real question."
- "The important part is not just the answer. It is the evidence."
- "If the model is uncertain, we want the system to surface that instead of bluffing."
- "This is the evaluation path today: same-toolchain, founder-guided, and strong enough for a design-partner motion."

## If Something Goes Sideways

- If Apple Intelligence is still preparing, stay in the host app and explain that the device readiness state is surfaced directly in the UI.
- If you need a fallback, use simulator to show the import path, bundled demo pack, and indexing UI.
- If the room wants proof on their own data, move the next step to a scoped evaluation against a small real document set.
EOF

cat > "$SAMPLE_DIR/build_sample_app.sh" <<'EOF'
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
EOF

/bin/chmod +x "$SAMPLE_DIR/build_sample_app.sh"

echo "Staged self-contained buyer sample app at:"
echo "  $SAMPLE_DIR"
