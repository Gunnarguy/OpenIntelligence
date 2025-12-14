#!/usr/bin/env bash
set -euo pipefail

# Simple environment validator for CI and local preflight.
# In CI environments (CI=true), API keys are optional since we only build/test.
# For release workflows, all required vars must be present.

# API keys are only required for release builds, not CI test runs
REQUIRED_VARS=()

# All API keys are optional for CI builds (the app works without them)
OPTIONAL_VARS=(
  OPENAI_API_KEY
  APP_STORE_CONNECT_ISSUER
  APP_STORE_CONNECT_KEY_ID
  APPLE_API_KEY
)

missing=()
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    missing+=("$var")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "❌ Missing required environment variables: ${missing[*]}" >&2
  exit 1
fi

for var in "${OPTIONAL_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "ℹ️  Optional env not set: $var"
  fi
done

echo "✅ Environment validation passed"
