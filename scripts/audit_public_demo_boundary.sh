#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/audit_public_demo_boundary.sh [options]

Audit the OpenIntelligence-Public working copy against the private-to-public
 demo boundary. Fails if blocked paths still exist or if the public repo still
 exposes known implementation-heavy service areas.

Options:
  --public-repo <path>   Path to the public working copy
                         (default: /Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public)
  -h, --help             Show this help
EOF
}

PUBLIC_REPO="/Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --public-repo)
      PUBLIC_REPO="$2"
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
source "$REPO_ROOT/scripts/public_demo_manifest.sh"

if [[ ! -d "$PUBLIC_REPO/.git" ]]; then
  echo "Public repo not found at: $PUBLIC_REPO" >&2
  exit 1
fi

failures=0

check_missing_allowlist() {
  local rel="$1"
  local dst="$PUBLIC_REPO/$rel"

  if [[ ! -e "$dst" ]]; then
    echo "MISSING expected public path: $rel" >&2
    failures=1
  fi
}

check_blocked_path_absent() {
  local rel="$1"
  local dst="$PUBLIC_REPO/$rel"

  if [[ -e "$dst" ]]; then
    echo "BLOCKED path still present in public repo: $rel" >&2
    failures=1
  fi
}

check_required_demo_path() {
  local rel="$1"
  local dst="$PUBLIC_REPO/$rel"

  if [[ ! -e "$dst" ]]; then
    echo "MISSING required demo overlay path: $rel" >&2
    failures=1
  fi
}

check_file_contains() {
  local rel="$1"
  local needle="$2"
  local dst="$PUBLIC_REPO/$rel"

  if [[ ! -f "$dst" ]] || ! grep -Fq "$needle" "$dst"; then
    echo "PUBLIC file missing required content: $rel :: $needle" >&2
    failures=1
  fi
}

check_file_not_contains() {
  local rel="$1"
  local needle="$2"
  local dst="$PUBLIC_REPO/$rel"

  if [[ -f "$dst" ]] && grep -Fq "$needle" "$dst"; then
    echo "PUBLIC file still contains blocked content: $rel :: $needle" >&2
    failures=1
  fi
}

for rel in "${PUBLIC_EXPORT_PATHS[@]}"; do
  check_missing_allowlist "$rel"
done

for rel in "${PUBLIC_DELETE_PATHS[@]}"; do
  check_blocked_path_absent "$rel"
done

for rel in "${PUBLIC_DEMO_REQUIRED_PATHS[@]}"; do
  check_required_demo_path "$rel"
done

check_file_contains ".env.example" "YOUR_ASC_ISSUER_ID"
check_file_contains ".env.example" "YOUR_ASC_KEY_ID"

check_file_contains "fastlane/Fastfile" 'require_relative "../scripts/app_store_connect_env"'
check_file_contains "fastlane/Fastfile" "AppStoreConnectEnv.app_store_connect_key_id"
check_file_contains "fastlane/Fastfile" "AppStoreConnectEnv.app_store_connect_issuer"
check_file_contains "fastlane/Fastfile" "AppStoreConnectEnv.app_store_connect_key_path"
check_file_not_contains "fastlane/Fastfile" 'ASC_KEY_ID = "'
check_file_not_contains "fastlane/Fastfile" 'ASC_ISSUER_ID = "'
check_file_not_contains "fastlane/Fastfile" 'File.expand_path("~/AuthKey_'

check_file_contains "fastlane/keys/.gitignore" "!.gitignore"

check_file_contains "scripts/app_store_connect_env.rb" "AppStoreConnectEnv.load_local_env!"

check_file_contains "scripts/create_version.rb" 'require_relative "app_store_connect_env"'
check_file_contains "scripts/create_version.rb" "AppStoreConnectEnv.required_app_store_connect_key_path"
check_file_not_contains "scripts/create_version.rb" 'File.expand_path("~/AuthKey_'

check_file_contains "scripts/push_draft_metadata.rb" 'require_relative "app_store_connect_env"'
check_file_contains "scripts/push_draft_metadata.rb" "AppStoreConnectEnv.required_app_store_connect_key_path"
check_file_not_contains "scripts/push_draft_metadata.rb" 'File.expand_path("~/AuthKey_'

check_file_contains "scripts/push_metadata.rb" 'require_relative "app_store_connect_env"'
check_file_contains "scripts/push_metadata.rb" "AppStoreConnectEnv.required_app_store_connect_key_path"
check_file_not_contains "scripts/push_metadata.rb" 'File.expand_path("~/AuthKey_'

check_file_contains "scripts/push_promo_draft.rb" 'require_relative "app_store_connect_env"'
check_file_contains "scripts/push_promo_draft.rb" "AppStoreConnectEnv.required_app_store_connect_key_path"
check_file_not_contains "scripts/push_promo_draft.rb" 'File.expand_path("~/AuthKey_'

check_file_contains "scripts/verify_asc_products.rb" "app_store_connect_env"
check_file_contains "scripts/verify_asc_products.rb" "AppStoreConnectEnv.required_app_store_connect_key_id"
check_file_not_contains "scripts/verify_asc_products.rb" "ENV['APP_STORE_CONNECT_API_KEY_ID']"

implementation_markers=(
  "OpenIntelligence/Services/RAG/Orchestration/RAGEngine.swift"
  "OpenIntelligence/Services/RAG/Orchestration/RAGService+KnowledgeRetrievalEngine.swift"
  "OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift"
  "OpenIntelligence/Services/Embedding/EmbeddingService.swift"
  "OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift"
  "OpenIntelligence/Services/Query/Routing/QueryRouterService.swift"
  "OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift"
  "OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift"
)

for rel in "${implementation_markers[@]}"; do
  if [[ -e "$PUBLIC_REPO/$rel" ]]; then
    echo "PRIVATE implementation still exposed publicly: $rel" >&2
    failures=1
  fi
done

if [[ "$failures" -ne 0 ]]; then
  echo
  echo "Public demo boundary audit FAILED." >&2
  exit 1
fi

echo "Public demo boundary audit passed for: $PUBLIC_REPO"
