#!/bin/zsh
set -euo pipefail
setopt extended_glob
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
QUIET=0
DRY_RUN=0

function usage() {
  cat <<'EOF'
Usage: ./scripts/clean_duplicate_output_artifacts.sh [--quiet] [--dry-run]

Removes macOS-style numbered duplicate artifacts (" 2", " 3", ...) from the
sale-packet output trees when the canonical sibling already exists.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet)
      QUIET=1
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

typeset -a ROOTS
ROOTS=(
  "$REPO_ROOT/output/OpenIntelligence-SDK-Package"
  "$REPO_ROOT/output/OpenIntelligence-Partner-Packet"
)

function duplicate_original_path() {
  local candidate="$1"
  local dir="${candidate:h}"
  local name="${candidate:t}"
  local suffix=""
  local stem="$name"
  local ext=""

  if [[ "$name" == *\ <->.* ]]; then
    ext=".${name##*.}"
    stem="${name%$ext}"
  fi

  if [[ "$stem" != *\ <-> ]]; then
    return 1
  fi

  suffix="${stem##* }"
  [[ "$suffix" == <-> ]] || return 1

  stem="${stem% $suffix}"
  [[ -n "$stem" ]] || return 1

  printf '%s/%s%s\n' "$dir" "$stem" "$ext"
}

function maybe_log() {
  [[ $QUIET -eq 1 ]] && return 0
  echo "$1"
}

removed_count=0
typeset -a removed_paths

for root in "$ROOTS[@]"; do
  [[ -d "$root" ]] || continue

  while IFS= read -r -d '' candidate; do
    local_original="$(duplicate_original_path "$candidate")" || continue
    [[ -e "$local_original" ]] || continue

    removed_paths+=("$candidate")
    removed_count=$((removed_count + 1))

    if [[ $DRY_RUN -eq 0 ]]; then
      /bin/rm -rf "$candidate"
    fi
  done < <(/usr/bin/find "$root" -depth \( -name '* [0-9]*' -o -name '* [0-9]*.*' \) -print0)
done

if [[ $removed_count -eq 0 ]]; then
  maybe_log "No duplicate-numbered output artifacts found."
  exit 0
fi

if [[ $QUIET -eq 0 ]]; then
  for removed_path in "$removed_paths[@]"; do
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "would remove $removed_path"
    else
      echo "removed $removed_path"
    fi
  done
fi

if [[ $DRY_RUN -eq 1 ]]; then
  maybe_log "Found $removed_count duplicate-numbered output artifact(s)."
else
  maybe_log "Removed $removed_count duplicate-numbered output artifact(s)."
fi
