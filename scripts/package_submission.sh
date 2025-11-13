#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "" ]]; then
  echo "Usage: $0 <output-directory>" >&2
  exit 1
fi

OUTPUT_DIR="$1"
TIMESTAMP="$(date +%Y-%m-%d-%H%M%S)"
PACKAGE_DIR="${OUTPUT_DIR}/appstore-package-${TIMESTAMP}"

mkdir -p "${PACKAGE_DIR}"

# Copy reference docs
cp Docs/reference/APP_REVIEW_CHECKLIST.md "${PACKAGE_DIR}/"
cp Docs/reference/APP_REVIEW_NOTES_TEMPLATE.md "${PACKAGE_DIR}/"
cp Docs/reference/APP_STORE_METADATA.md "${PACKAGE_DIR}/"
cp Docs/reference/APP_STORE_SUBMISSION_PACKAGE.md "${PACKAGE_DIR}/"
cp Docs/reference/PRICING_STRATEGY.md "${PACKAGE_DIR}/"
cp Docs/reference/exportOptions.plist "${PACKAGE_DIR}/"
cp smoke_test.md "${PACKAGE_DIR}/SMOKE_TEST.md"

# Copy sample documents for reviewer testing
mkdir -p "${PACKAGE_DIR}/TestDocuments"
cp TestDocuments/sample_technical.md "${PACKAGE_DIR}/TestDocuments/"
cp TestDocuments/sample_pricing_brief.md "${PACKAGE_DIR}/TestDocuments/" 2>/dev/null || true
cp TestDocuments/sample_1page.txt "${PACKAGE_DIR}/TestDocuments/"

cat <<EOF >"${PACKAGE_DIR}/README.txt"
OpenIntelligence App Store Submission Package
Generated: ${TIMESTAMP}

This folder aggregates the documentation required for App Store Review.

Next steps:
1. Build the release archive using Docs/reference/APP_STORE_SUBMISSION_PACKAGE.md.
2. Update SMOKE_TEST.md with pass/fail results.
3. Attach the copied reference docs to the submission as needed.
EOF

echo "Created submission bundle at ${PACKAGE_DIR}"
