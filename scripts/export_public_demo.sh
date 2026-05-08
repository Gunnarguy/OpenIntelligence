#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/export_public_demo.sh [options]

Sync the private engine repo into the existing OpenIntelligence-Public working
copy using the public demo allowlist/denylist boundary.

Default mode is dry-run. Nothing changes unless --apply is passed.

Options:
  --public-repo <path>   Path to the public working copy
                         (default: /Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public)
  --branch <name>        Branch to switch to in the public repo before export
                         (default: public-safe)
  --apply                Perform the sync and delete operations
  --no-branch-switch     Do not change branches in the public repo
  -h, --help             Show this help
EOF
}

PUBLIC_REPO="/Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public"
PUBLIC_BRANCH="public-safe"
DO_APPLY=0
SWITCH_BRANCH=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --public-repo)
      PUBLIC_REPO="$2"
      shift 2
      ;;
    --branch)
      PUBLIC_BRANCH="$2"
      shift 2
      ;;
    --apply)
      DO_APPLY=1
      shift
      ;;
    --no-branch-switch)
      SWITCH_BRANCH=0
      shift
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

source "$REPO_ROOT/scripts/public_demo_manifest.sh"

if [[ ! -d "$PUBLIC_REPO/.git" ]]; then
  echo "Public repo not found at: $PUBLIC_REPO" >&2
  exit 1
fi

print_paths() {
  local label="$1"
  shift

  echo "$label"
  local entry
  for entry in "$@"; do
    echo "  - $entry"
  done
}

apply_overlay() {
  local overlay_root="$REPO_ROOT/$PUBLIC_DEMO_OVERLAY_ROOT"

  if [[ ! -d "$overlay_root" ]]; then
    echo "Public demo overlay not found at: $overlay_root" >&2
    exit 1
  fi

  rsync -a "$overlay_root/" "$PUBLIC_REPO/"
}

sync_path() {
  local rel="$1"
  local src="$REPO_ROOT/$rel"
  local dst="$PUBLIC_REPO/$rel"

  if [[ ! -e "$src" ]]; then
    echo "Missing export source: $rel" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$dst")"

  if [[ -d "$src" ]]; then
    mkdir -p "$dst"
    rsync -a --delete "$src/" "$dst/"
  else
    rsync -a "$src" "$dst"
  fi
}

delete_path() {
  local rel="$1"
  local dst="$PUBLIC_REPO/$rel"

  if [[ -e "$dst" ]]; then
    rm -rf "$dst"
  fi
}

run_audit() {
  "$REPO_ROOT/scripts/audit_public_demo_boundary.sh" --public-repo "$PUBLIC_REPO"
}

prepare_branch() {
  [[ "$SWITCH_BRANCH" -eq 1 ]] || return 0

  git -C "$PUBLIC_REPO" fetch origin

  if git -C "$PUBLIC_REPO" rev-parse --verify "$PUBLIC_BRANCH" >/dev/null 2>&1; then
    git -C "$PUBLIC_REPO" switch "$PUBLIC_BRANCH"
    return 0
  fi

  if git -C "$PUBLIC_REPO" show-ref --verify --quiet "refs/remotes/origin/$PUBLIC_BRANCH"; then
    git -C "$PUBLIC_REPO" switch -c "$PUBLIC_BRANCH" --track "origin/$PUBLIC_BRANCH"
    return 0
  fi

  git -C "$PUBLIC_REPO" switch -c "$PUBLIC_BRANCH"
}

if [[ "$DO_APPLY" -ne 1 ]]; then
  echo "Dry run only. No files will be changed."
  echo
  print_paths "Allowlist export paths:" "${PUBLIC_EXPORT_PATHS[@]}"
  echo
  print_paths "Explicit delete paths:" "${PUBLIC_DELETE_PATHS[@]}"
  echo
  print_paths "Required demo overlay paths after export:" "${PUBLIC_DEMO_REQUIRED_PATHS[@]}"
  echo
  echo "Run with --apply to sync into: $PUBLIC_REPO"
  exit 0
fi

if [[ -n "$(git -C "$PUBLIC_REPO" status --porcelain)" ]]; then
  echo "Public repo has uncommitted changes. Clean it before export." >&2
  exit 1
fi

prepare_branch

echo "Syncing allowlist into $PUBLIC_REPO..."
for rel in "${PUBLIC_EXPORT_PATHS[@]}"; do
  sync_path "$rel"
done

echo "Removing denylist from $PUBLIC_REPO..."
for rel in "${PUBLIC_DELETE_PATHS[@]}"; do
  delete_path "$rel"
done

echo "Applying public demo overlay..."
apply_overlay

echo "Running boundary audit..."
run_audit

echo
print_paths "Required demo overlay paths in the public repo:" "${PUBLIC_DEMO_REQUIRED_PATHS[@]}"
echo
echo "Public repo status after export:"
git -C "$PUBLIC_REPO" status --short
