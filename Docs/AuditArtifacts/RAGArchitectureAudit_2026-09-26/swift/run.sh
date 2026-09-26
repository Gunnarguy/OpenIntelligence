#!/bin/bash
# Build the app's extractor from source with the Swift toolchain on PATH and run the lock tests.
#
#   run.sh <label> [git-rev]
#
# With no rev, the source comes from the working tree; with one (b37ab4c is the code before the
# 2026-09-26 fix), every copied source file comes from that commit. The two test files always come
# from the working tree: OpenIntelligenceTests/.../PrecisionLockAnswerTypeTests.swift and
# LockMatrixProbe.swift beside this script. Writes tests_<label>.txt and probe_<label>.txt here.
#
# The package mirrors the OpenIntelligenceEngine target (repository Package.swift and the Xcode
# project): Swift 5 language mode, main-actor default isolation, the same upcoming features, and a
# test target with default settings as OpenIntelligenceTests has. The copied files are real source.
# The only edits: `import NaturalLanguage` is dropped from the extractor, which calls no NL API, and
# `import CoreGraphics` from DocumentChunk.swift; three files are cut to the declarations needed,
# because the rest of them reaches half the app: AnswerIntent with the QueryIntent it maps to,
# RetrievedChunk alone from RAGQuery.swift, and DocumentChunk.swift through ChunkMetadata.
#
# Run on 2026-09-26 with Swift 6.4 (swift-6.4-RELEASE, x86_64 Linux, the toolchain layer of the
# official swift:6.4-noble image). SWIFT_DETERMINISTIC_HASHING fixes Set order, so output repeats.
set -euo pipefail
LABEL="$1"; REV="${2:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/oi-swift-harness.XXXXXX")"
S="$WORK/Sources/OpenIntelligenceEngine"; T="$WORK/Tests/OpenIntelligenceEngineTests"
mkdir -p "$S" "$T"

src() { if [ -n "$REV" ]; then git -C "$REPO" show "$REV:$1"; else cat "$REPO/$1"; fi; }

src OpenIntelligence/Services/Query/Analysis/SpecificationExtractor.swift | sed '/^import NaturalLanguage$/d' > "$S/SpecificationExtractor.swift"
src OpenIntelligence/Services/Document/Analysis/SpecificationDetector.swift > "$S/SpecificationDetector.swift"
src OpenIntelligence/Services/RAG/Tuning/EvidenceScoringPolicyService.swift > "$S/EvidenceScoringPolicyService.swift"
src OpenIntelligence/Services/Infrastructure/Configuration/LoggingConfiguration.swift > "$S/LoggingConfiguration.swift"
src OpenIntelligence/Core/Models/DocumentChunk.swift | sed -n '1,427p' | sed '/^import CoreGraphics$/d' > "$S/DocumentChunk.swift"
{ echo "import Foundation"; echo; src OpenIntelligence/Core/Models/RAGQuery.swift | sed -n '56,71p'; } > "$S/RetrievedChunk.swift"
{ echo "import Foundation"; echo; src OpenIntelligence/Services/Query/Enhancement/QueryEnhancementService.swift | sed -n '24,51p;57,159p'; } > "$S/AnswerIntent.swift"
cp "$REPO/OpenIntelligenceTests/Services/RAG/Tuning/PrecisionLockAnswerTypeTests.swift" "$HERE/LockMatrixProbe.swift" "$T/"

cat > "$WORK/Package.swift" <<'PKG'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OIExtractorHarness",
    targets: [
        .target(
            name: "OpenIntelligenceEngine",
            path: "Sources/OpenIntelligenceEngine",
            swiftSettings: [
                .define("OPENINTELLIGENCE_ENGINE_SDK"),
                .define("DEBUG"),
                .unsafeFlags([
                    "-default-isolation=MainActor",
                    "-enable-bare-slash-regex",
                    "-enable-upcoming-feature", "DisableOutwardActorInference",
                    "-enable-upcoming-feature", "InferSendableFromCaptures",
                    "-enable-upcoming-feature", "GlobalActorIsolatedTypesUsability",
                    "-enable-upcoming-feature", "MemberImportVisibility",
                    "-enable-upcoming-feature", "InferIsolatedConformances",
                    "-enable-upcoming-feature", "NonisolatedNonsendingByDefault",
                ])
            ]
        ),
        .testTarget(
            name: "OpenIntelligenceEngineTests",
            dependencies: ["OpenIntelligenceEngine"],
            path: "Tests/OpenIntelligenceEngineTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
PKG

clean() { sed -e 's/\x1b\[[0-9;]*m//g' -e "s|$WORK|<harness>|g" -e 's/ ([0-9.]* seconds)//' -e 's/ in [0-9.]* ([0-9.]*) seconds//'; }
cd "$WORK"
export SWIFT_DETERMINISTIC_HASHING=1
{ swift build --build-tests 2>&1 || true; } | clean | { grep -E '^<harness>.*(error|warning):' || true; } \
    | { grep -v 'LoggingConfiguration.swift:3[49][0-9]:.*createFile' || true; } > "$WORK/build.txt"
{ echo "# swift $(swift --version 2>/dev/null | head -1)"; echo "# source: ${REV:-working tree}"; echo "# build diagnostics outside LoggingConfiguration's two unused-result warnings: $(wc -l < "$WORK/build.txt")"
  cat "$WORK/build.txt"
  # Failing tests are an expected result for the code before the fix, so a non-zero exit is not fatal.
  { swift test --filter PrecisionLockAnswerTypeTests 2>&1 || true; } | clean \
    | { grep -E 'Test Case .*(passed|failed)|error: |Executed .* tests|\[ExtractiveQA\]' || true; } | awk '!(/Executed/ && seen[$0]++)'
} > "$HERE/tests_$LABEL.txt"
{ echo "# question | documents | locks or goes to the model | span | confidence or failure"; echo "# source: ${REV:-working tree}"
  { swift test --filter LockMatrixProbe 2>&1 || true; } | clean | { grep '^MATRIX|' || true; } | cut -d'|' -f2-
} > "$HERE/probe_$LABEL.txt"
rm -rf "$WORK"
echo "wrote tests_$LABEL.txt and probe_$LABEL.txt"
