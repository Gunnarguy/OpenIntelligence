#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/refresh_public_signal.sh [options]

Refresh the public-facing release signal from the private repo, commit it, and
optionally promote that safe summary commit to the public-safe branch.

This updates:
  - WHATS_NEW.md
  - fastlane/metadata/en-US/release_notes.txt

Options:
  --push-private         Push the private repo after committing
  --promote             Cherry-pick the summary commit into the public-safe repo
  --push-public         Push the public-safe branch after promotion
  --from <commit>       Pass an explicit baseline commit through to the generator
  -h, --help            Show this help
EOF
}

PUSH_PRIVATE=0
PROMOTE=0
PUSH_PUBLIC=0
FROM_COMMIT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push-private)
      PUSH_PRIVATE=1
      shift
      ;;
    --promote)
      PROMOTE=1
      shift
      ;;
    --push-public)
      PROMOTE=1
      PUSH_PUBLIC=1
      shift
      ;;
    --from)
      FROM_COMMIT="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"
STATE_DIR="$REPO_ROOT/.release"
STATE_FILE="$STATE_DIR/public_summary_base"

GENERATOR_ARGS=(--write)
if [[ -n "$FROM_COMMIT" ]]; then
  GENERATOR_ARGS+=(--from "$FROM_COMMIT")
fi

"$REPO_ROOT/scripts/update_public_release_summary.sh" "${GENERATOR_ARGS[@]}"

if git diff --quiet -- WHATS_NEW.md fastlane/metadata/en-US/release_notes.txt; then
  echo "Public release files are already up to date."
  exit 0
fi

git add WHATS_NEW.md fastlane/metadata/en-US/release_notes.txt
git commit -m "Refresh public release signal"

mkdir -p "$STATE_DIR"
git rev-parse HEAD > "$STATE_FILE"

SUMMARY_COMMIT="$(git rev-parse --short HEAD)"
echo "Created summary commit $SUMMARY_COMMIT"

if [[ "$PUSH_PRIVATE" -eq 1 ]]; then
  git push
fi

if [[ "$PROMOTE" -eq 1 ]]; then
  PROMOTE_ARGS=("$SUMMARY_COMMIT")
  if [[ "$PUSH_PUBLIC" -eq 1 ]]; then
    PROMOTE_ARGS=(--push "$SUMMARY_COMMIT")
  fi
  "$REPO_ROOT/scripts/promote_public_safe.sh" "${PROMOTE_ARGS[@]}"
fi
