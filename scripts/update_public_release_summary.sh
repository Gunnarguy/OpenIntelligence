#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/update_public_release_summary.sh [options]

Generate public-safe release messaging from recent private repo activity without
exposing internal implementation details.

Options:
  --from <commit>        Start summarizing from this commit
  --for-current-version  Summarize from the previous tagged app version
  --write                Write generated files to disk
  --update-state         Advance the local release-summary baseline to HEAD
  --no-app-store         Skip updating fastlane/metadata/en-US/release_notes.txt
  --no-state-update      Backward-compatible alias for not updating baseline
  -h, --help             Show this help

Notes:
  - By default, the script reads its baseline from:
      .release/public_summary_base
  - If no baseline exists, it falls back to a recent lookback window.
  - Without --write, the script prints the generated WHATS_NEW.md content.
EOF
}

WRITE=0
UPDATE_STATE=0
WRITE_APP_STORE=1
FROM_COMMIT=""
FOR_CURRENT_VERSION=0
DEFAULT_LOOKBACK=18

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)
      FROM_COMMIT="${2:-}"
      shift 2
      ;;
    --for-current-version)
      FOR_CURRENT_VERSION=1
      shift
      ;;
    --write)
      WRITE=1
      shift
      ;;
    --update-state)
      UPDATE_STATE=1
      shift
      ;;
    --no-app-store)
      WRITE_APP_STORE=0
      shift
      ;;
    --no-state-update)
      UPDATE_STATE=0
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
STATE_DIR="$REPO_ROOT/.release"
STATE_FILE="$STATE_DIR/public_summary_base"
SUMMARY_FILE="$REPO_ROOT/WHATS_NEW.md"
APP_STORE_FILE="$REPO_ROOT/fastlane/metadata/en-US/release_notes.txt"
PROJECT_FILE="$REPO_ROOT/OpenIntelligence.xcodeproj/project.pbxproj"
HEAD_COMMIT="$(git rev-parse HEAD)"

resolve_default_from_commit() {
  local candidate

  if [[ -n "$FROM_COMMIT" ]]; then
    echo "$FROM_COMMIT"
    return
  fi

  if [[ -f "$STATE_FILE" ]]; then
    candidate="$(tr -d '[:space:]' < "$STATE_FILE")"
    if [[ -n "$candidate" ]]; then
      echo "$candidate"
      return
    fi
  fi

  candidate="$(git rev-list --max-count=1 --skip="$DEFAULT_LOOKBACK" HEAD 2>/dev/null || true)"
  if [[ -n "$candidate" ]]; then
    echo "$candidate"
    return
  fi

  git rev-list --max-parents=0 --max-count=1 HEAD
}

resolve_release_version() {
  local version

  version="$(sed -nE 's/.*MARKETING_VERSION = ([^;]+);/\1/p' "$PROJECT_FILE" | head -n 1)"
  if [[ -n "$version" ]]; then
    echo "$version"
  else
    echo "Current Release"
  fi
}

RELEASE_VERSION="$(resolve_release_version)"

resolve_previous_version_commit() {
  local previous_version=""
  local tag
  local candidate

  while IFS= read -r tag; do
    candidate="${tag#v}"
    if [[ "$candidate" == "$RELEASE_VERSION" ]]; then
      continue
    fi

    if [[ "$(printf '%s\n%s\n' "$candidate" "$RELEASE_VERSION" | sort -V | head -n 1)" == "$candidate" ]]; then
      previous_version="$candidate"
    fi
  done < <(git tag --list 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V)

  if [[ -n "$previous_version" ]]; then
    git rev-list --max-count=1 "v${previous_version}"
  fi
}

resolve_base_commit() {
  local candidate=""

  if [[ -n "$FROM_COMMIT" ]]; then
    echo "$FROM_COMMIT"
    return
  fi

  if [[ "$FOR_CURRENT_VERSION" -eq 1 ]]; then
    candidate="$(resolve_previous_version_commit)"
    if [[ -n "$candidate" ]]; then
      echo "$candidate"
      return
    fi
  fi

  resolve_default_from_commit
}

BASE_COMMIT="$(resolve_base_commit)"

if ! git rev-parse --verify "${BASE_COMMIT}^{commit}" >/dev/null 2>&1; then
  echo "Invalid baseline commit: $BASE_COMMIT" >&2
  exit 1
fi

RANGE="${BASE_COMMIT}..${HEAD_COMMIT}"

mapfile -t CHANGED_FILES < <(git diff --name-only "$RANGE")

if [[ ${#CHANGED_FILES[@]} -eq 0 ]]; then
  if [[ "$WRITE" -eq 1 ]]; then
    echo "No new private changes since baseline. Public release files left unchanged."
    exit 0
  fi

  if [[ -f "$SUMMARY_FILE" ]]; then
    cat "$SUMMARY_FILE"
    exit 0
  fi
fi

contains_key() {
  local needle="$1"
  shift || true
  local entry

  for entry in "$@"; do
    if [[ "$entry" == "$needle" ]]; then
      return 0
    fi
  done

  return 1
}

KEY_PRIORITY=(
  source_verification
  smarter_suggestions
  messy_files
  plan_limits
  library_experience
  grounded_answers
  ui_polish
  public_messaging
  internal_engine_work
)

sort_keys_by_priority() {
  local -a input_keys=("$@")
  local key

  for key in "${KEY_PRIORITY[@]}"; do
    if contains_key "$key" "${input_keys[@]}"; then
      echo "$key"
    fi
  done

  for key in "${input_keys[@]}"; do
    if ! contains_key "$key" "${KEY_PRIORITY[@]}"; then
      echo "$key"
    fi
  done
}

LATEST_KEYS=()
RECENT_KEYS=()

add_latest() {
  local key="$1"
  if ! contains_key "$key" "${LATEST_KEYS[@]}"; then
    LATEST_KEYS+=("$key")
  fi
  add_recent "$key"
}

add_recent() {
  local key="$1"
  if ! contains_key "$key" "${RECENT_KEYS[@]}"; then
    RECENT_KEYS+=("$key")
  fi
}

for file in "${CHANGED_FILES[@]}"; do
  case "$file" in
    OpenIntelligence/Services/Billing/*|\
    OpenIntelligence/Features/Billing/*|\
    OpenIntelligence/Resources/StoreKit/*|\
    fastlane/subscriptions.json|\
    fastlane/review_notes.txt)
      add_latest "plan_limits"
      ;;
    OpenIntelligence/Services/Query/UX/SuggestedQuestionsService.swift|\
    OpenIntelligence/Features/Chat/Conversation/ChatScreen.swift)
      add_latest "smarter_suggestions"
      ;;
    OpenIntelligence/Services/Document/*)
      add_latest "messy_files"
      ;;
    OpenIntelligence/Services/RAG/Safety/*|\
    OpenIntelligence/Services/Query/Analysis/GroundedAnswerPolicy.swift|\
    OpenIntelligence/Services/RAG/Safety/SourceOnlyAnswerService.swift|\
    OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift)
      add_latest "source_verification"
      ;;
    OpenIntelligence/Services/RAG/*|\
    OpenIntelligence/Services/Query/*|\
    OpenIntelligence/Services/Storage/*)
      add_recent "grounded_answers"
      ;;
    OpenIntelligence/Features/Documents/*|\
    OpenIntelligence/Services/Infrastructure/Presentation/*)
      add_recent "library_experience"
      ;;
    OpenIntelligence/Features/Settings/*|\
    OpenIntelligence/Features/Chat/Response/*|\
    OpenIntelligence/UI/*|\
    OpenIntelligence/App/*)
      add_recent "ui_polish"
      ;;
    fastlane/metadata/*|README.md|WHATS_NEW.md)
      add_recent "public_messaging"
      ;;
    OpenIntelligence/SDK/*|\
    scripts/build_engine_xcframework.sh|\
    scripts/validate_sdk_package.sh)
      add_recent "internal_engine_work"
      ;;
    *)
      ;;
  esac
done

if [[ ${#LATEST_KEYS[@]} -eq 0 ]]; then
  add_latest "grounded_answers"
fi

if [[ ${#RECENT_KEYS[@]} -eq 0 ]]; then
  add_recent "grounded_answers"
fi

mapfile -t LATEST_KEYS < <(sort_keys_by_priority "${LATEST_KEYS[@]}")
mapfile -t RECENT_KEYS < <(sort_keys_by_priority "${RECENT_KEYS[@]}")

summary_bullet_for_key() {
  case "$1" in
    smarter_suggestions)
      echo "Suggested questions now pull from a clearer slice of your actual library, so larger collections feel more specific and easier to explore"
      ;;
    plan_limits)
      echo "Lifetime Cohort now unlocks unlimited documents, and lifetime owners no longer see document-pack prompts"
      ;;
    messy_files)
      echo "Imports are more resilient on difficult manuals and messy PDFs, with better cleanup of noisy extracted text"
      ;;
    source_verification)
      echo "Answers are stricter about what your documents actually support, with clearer fallback behavior when evidence is weak"
      ;;
    grounded_answers)
      echo "Document scoping and evidence handling are more reliable across questions that pull from multiple files"
      ;;
    library_experience)
      echo "Importing, browsing, and getting to a strong first question feel smoother across larger libraries"
      ;;
    ui_polish)
      echo "Chat, answer review, and settings surfaces were tightened up to make results easier to trust and inspect"
      ;;
    public_messaging)
      echo "Release messaging and product copy were refreshed to better match what the app actually does"
      ;;
    internal_engine_work)
      echo "Behind-the-scenes engine and release workflow work landed to make future updates steadier"
      ;;
    *)
      ;;
  esac
}

app_store_bullet_for_key() {
  case "$1" in
    smarter_suggestions)
      echo "Suggested questions now stay closer to the uploaded documents in large libraries"
      ;;
    plan_limits)
      echo "Lifetime Cohort now unlocks unlimited documents without document-pack prompts"
      ;;
    messy_files)
      echo "Better cleanup for messy PDFs and noisy manual imports"
      ;;
    source_verification)
      echo "Answers are more grounded in what your documents actually support"
      ;;
    grounded_answers)
      echo "Tighter document scoping across multi-document questions"
      ;;
    library_experience)
      echo "Smoother import, browsing, and first-question flow in the library"
      ;;
    ui_polish)
      echo "Cleaner chat, answer review, and settings flow"
      ;;
    public_messaging)
      echo "Sharper in-app and release messaging"
      ;;
    internal_engine_work)
      echo "Under-the-hood reliability work supporting this release"
      ;;
    *)
      ;;
  esac
}

append_bullets() {
  local renderer="$1"
  shift
  local key

  for key in "$@"; do
    local bullet
    bullet="$("$renderer" "$key")"
    if [[ -n "$bullet" ]]; then
      printf -- "- %s\n" "$bullet"
    fi
  done
}

filter_out_existing_keys() {
  local -a source_keys=("$@")
  local key
  local filtered=()

  for key in "${source_keys[@]}"; do
    if ! contains_key "$key" "${LATEST_KEYS[@]}"; then
      filtered+=("$key")
    fi
  done

  if [[ ${#filtered[@]} -eq 0 ]]; then
    filtered=("${source_keys[@]}")
  fi

  printf '%s\n' "${filtered[@]}"
}

build_app_store_keys() {
  local desired_limit=6
  local key
  local selected=()

  for key in "${LATEST_KEYS[@]}" "${RECENT_RENDER_KEYS[@]}"; do
    if [[ -z "$key" ]]; then
      continue
    fi
    case "$key" in
      public_messaging|internal_engine_work)
        continue
        ;;
      *)
        ;;
    esac
    if ! contains_key "$key" "${selected[@]}"; then
      selected+=("$key")
    fi
    if [[ ${#selected[@]} -ge $desired_limit ]]; then
      break
    fi
  done

  if [[ ${#selected[@]} -eq 0 ]]; then
    selected=("grounded_answers")
  fi

  printf '%s\n' "${selected[@]}"
}

app_store_intro() {
  local -a selected_keys=("$@")

  if contains_key "source_verification" "${selected_keys[@]}" && \
     contains_key "smarter_suggestions" "${selected_keys[@]}" && \
     contains_key "messy_files" "${selected_keys[@]}"; then
    echo "This release makes answers more trustworthy, libraries easier to explore, and imports more resilient."
    return
  fi

  if contains_key "plan_limits" "${selected_keys[@]}"; then
    echo "This release improves everyday document work and cleans up the ownership experience for lifetime users."
    return
  fi

  echo "This release sharpens document-grounded answers and smooths the library experience."
}

mapfile -t RECENT_RENDER_KEYS < <(filter_out_existing_keys "${RECENT_KEYS[@]}")
mapfile -t APP_STORE_KEYS < <(build_app_store_keys)

SUMMARY_CONTENT="$(cat <<EOF
# What's New

Public release highlights for OpenIntelligence.

## In This Release

$(append_bullets summary_bullet_for_key "${LATEST_KEYS[@]}")

## Also Improved

$(append_bullets summary_bullet_for_key "${RECENT_RENDER_KEYS[@]}")

## Product Snapshot

- Private document Q&A on iPhone and iPad
- Source-backed answers with reviewable evidence
- Built for growing personal and professional document libraries

## Notes

This summary stays feature-facing on purpose. It tells users what improved
without publishing internal pipeline details, tuning rules, or private roadmap
work.
EOF
)"

APP_STORE_CONTENT="$(cat <<EOF
Version $RELEASE_VERSION

$(app_store_intro "${APP_STORE_KEYS[@]}")

$(append_bullets app_store_bullet_for_key "${APP_STORE_KEYS[@]}")
EOF
)"

if [[ "$WRITE" -eq 1 ]]; then
  printf '%s\n' "$SUMMARY_CONTENT" > "$SUMMARY_FILE"

  if [[ "$WRITE_APP_STORE" -eq 1 ]]; then
    printf '%s\n' "$APP_STORE_CONTENT" > "$APP_STORE_FILE"
  fi

  if [[ "$UPDATE_STATE" -eq 1 ]]; then
    mkdir -p "$STATE_DIR"
    printf '%s\n' "$HEAD_COMMIT" > "$STATE_FILE"
  fi

  echo "Updated $SUMMARY_FILE"
  if [[ "$WRITE_APP_STORE" -eq 1 ]]; then
    echo "Updated $APP_STORE_FILE"
  fi
  echo "Baseline: $BASE_COMMIT"
  echo "Head: $HEAD_COMMIT"
else
  printf '%s\n' "$SUMMARY_CONTENT"
fi
