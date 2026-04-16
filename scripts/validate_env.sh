#!/usr/bin/env bash
set -euo pipefail

# Simple environment validator for CI and local preflight.
# In CI environments (CI=true), API keys are optional since we only build/test.
# For release workflows, all required vars must be present.

# API keys are only required for release builds, not CI test runs.
# IMPORTANT: This script runs with `set -u` in CI; we must avoid patterns that
# can trigger "unbound variable" with empty/unset arrays.
REQUIRED_VARS=()

# All API keys are optional for CI builds (the app works without them)
OPTIONAL_VARS=(
  OPENAI_API_KEY
  APP_STORE_CONNECT_ISSUER
  APP_STORE_CONNECT_KEY_ID
  APP_STORE_CONNECT_PRIVATE_KEY_PATH
  APP_STORE_CONNECT_BUNDLE_ID
  APPLE_API_KEY
)

missing=()
missing_count=0
for var in "${REQUIRED_VARS[@]+"${REQUIRED_VARS[@]}"}"; do
  if [[ -z "${!var:-}" ]]; then
    missing+=("$var")
    missing_count=$((missing_count + 1))
  fi
done

if [[ $missing_count -gt 0 ]]; then
  echo "❌ Missing required environment variables: ${missing[*]}" >&2
  exit 1
fi

for var in "${OPTIONAL_VARS[@]+"${OPTIONAL_VARS[@]}"}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "ℹ️  Optional env not set: $var"
  fi
done

echo "✅ Environment validation passed"
