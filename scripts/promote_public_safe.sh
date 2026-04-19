#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/promote_public_safe.sh [options] <commit> [<commit> ...]

Promote one or more public-safe commits from the private repo into the public
working copy's public-safe branch.

Options:
  --public-repo <path>   Path to the public working copy
                         (default: /Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public)
  --branch <name>        Public branch to cherry-pick onto (default: public-safe)
  --push                 Push the updated branch to the public remote after cherry-picking
  --force                Allow commits that touch blocked private/commercial paths
  -h, --help             Show this help

Examples:
  ./scripts/promote_public_safe.sh 23d9b2d 9ddccfd
  ./scripts/promote_public_safe.sh --push 9ddccfd
EOF
}

PUBLIC_REPO="/Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public"
PUBLIC_BRANCH="public-safe"
DO_PUSH=0
FORCE=0
COMMITS=()

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
    --push)
      DO_PUSH=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      COMMITS+=("$1")
      shift
      ;;
  esac
done

if [[ $# -gt 0 ]]; then
  COMMITS+=("$@")
fi

if [[ ${#COMMITS[@]} -eq 0 ]]; then
  echo "No commits provided." >&2
  usage >&2
  exit 1
fi

PRIVATE_REPO="$(git rev-parse --show-toplevel)"

if [[ ! -d "$PUBLIC_REPO/.git" ]]; then
  echo "Public repo not found at: $PUBLIC_REPO" >&2
  exit 1
fi

if [[ -n "$(git -C "$PUBLIC_REPO" status --porcelain)" ]]; then
  echo "Public repo has uncommitted changes. Clean it before promotion." >&2
  exit 1
fi

blocked_patterns=(
  "INTERNAL_LOGIC_AUDIT.md"
  "SDK_BOUNDARY_AUDIT.md"
  "REGRESSION_PLAN.md"
  "ENGINE_CAPABILITIES.md"
  "output/OpenIntelligence-Partner-Packet/"
  "output/OpenIntelligence-SDK-Package/"
  ".github/copilot-instructions.md"
  ".github/instructions/"
  "OpenIntelligence/SDK/"
  "OpenIntelligence/Core/Support/"
  "scripts/build_engine_xcframework.sh"
  "scripts/validate_sdk_package.sh"
)

is_blocked_file() {
  local file="$1"
  local pattern

  for pattern in "${blocked_patterns[@]}"; do
    if [[ "$pattern" == */ ]]; then
      [[ "$file" == "$pattern"* ]] && return 0
    else
      [[ "$file" == "$pattern" ]] && return 0
    fi
  done

  return 1
}

for commit in "${COMMITS[@]}"; do
  git rev-parse --verify "${commit}^{commit}" >/dev/null

  mapfile -t files < <(git diff-tree --no-commit-id --name-only -r "$commit")
  blocked_files=()

  for file in "${files[@]}"; do
    if is_blocked_file "$file"; then
      blocked_files+=("$file")
    fi
  done

  if [[ ${#blocked_files[@]} -gt 0 && $FORCE -ne 1 ]]; then
    echo "Commit $commit touches blocked private/commercial paths:" >&2
    printf '  - %s\n' "${blocked_files[@]}" >&2
    echo "Review it carefully or rerun with --force if you intentionally want to promote it." >&2
    exit 1
  fi
done

git -C "$PUBLIC_REPO" fetch origin

if git -C "$PUBLIC_REPO" rev-parse --verify "$PUBLIC_BRANCH" >/dev/null 2>&1; then
  git -C "$PUBLIC_REPO" switch "$PUBLIC_BRANCH"
else
  git -C "$PUBLIC_REPO" switch -c "$PUBLIC_BRANCH" --track origin/main
fi

git -C "$PUBLIC_REPO" fetch "$PRIVATE_REPO" main:private-main

for commit in "${COMMITS[@]}"; do
  echo "Cherry-picking $commit onto $PUBLIC_BRANCH..."
  git -C "$PUBLIC_REPO" cherry-pick "$commit"
done

if [[ $DO_PUSH -eq 1 ]]; then
  git -C "$PUBLIC_REPO" push -u origin "$PUBLIC_BRANCH"
fi

echo
echo "Promotion complete."
echo "Public repo: $PUBLIC_REPO"
echo "Branch: $PUBLIC_BRANCH"
if [[ $DO_PUSH -eq 1 ]]; then
  echo "Pushed to origin/$PUBLIC_BRANCH"
else
  echo "Not pushed. Review and push manually when ready."
fi
