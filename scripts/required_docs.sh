#!/bin/bash
#
# The path-to-documentation table, in one place.
#
# Reads repository-relative paths on stdin, one per line. Writes classified requirements on stdout:
#
#     required<TAB><doc><TAB><the path that requires it>
#     advisory<TAB><doc><TAB><the path that suggests it>
#
# Consumers: scripts/enforce_docs_hook.sh (the pre-commit gate, over the staged set) and
# .claude/hooks/stop-handoff.sh (the end-of-session net, over everything the session touched).
#
# It lives here rather than inside either consumer because a mapping that exists in two places is a
# mapping that will disagree with itself. This file is the ENFORCING COPY of the table in
# .agents/rules/01-docs-and-notion-sync.md; change one and change both.
#
# Two documents are never emitted as `required`, only ever as `advisory`:
# WHATS_NEW.md and Docs/USER_CHANGELOG.md. Whether a source change is user-visible is a judgment a
# path pattern cannot make, and a gate that blocks every commit touching a view gets bypassed within
# a week. A bypassed gate enforces nothing.
#
# Exits 0 even when it can say nothing. Silence here must never fail a commit or a session.

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -n "$REPO_ROOT" ] || exit 0
cd "$REPO_ROOT" || exit 0

ROUTER=".codex/skills/route-openintelligence-work/scripts/repoos_router.py"
NEVER_BLOCKING="WHATS_NEW.md Docs/USER_CHANGELOG.md"

emit() {
  local doc="$1" why="$2" kind="required"
  case " $NEVER_BLOCKING " in *" $doc "*) kind="advisory" ;; esac
  printf '%s\t%s\t%s\n' "$kind" "$doc" "$why"
}

emit_advisory() { printf 'advisory\t%s\t%s\n' "$1" "$2"; }

paths="$(cat)"
[ -n "$paths" ] || exit 0

swift_paths="$(printf '%s\n' "$paths" | grep -E '\.swift$' || true)"
[ -n "$swift_paths" ] || exit 0

# ---------------------------------------------------------------------------
# The table. `case` takes the FIRST matching branch, so narrower patterns come first: a file under
# Features/Billing is billing, not generic UI.
# ---------------------------------------------------------------------------
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in
    OpenIntelligence/Services/RAG/Retrieval/* | OpenIntelligence/Services/Query/* | OpenIntelligence/Services/RAG/Tuning/*)
      emit "Docs/RETRIEVAL_PIPELINE.md" "$f"; emit "CHANGELOG.md" "$f" ;;
    OpenIntelligence/Services/Document/*)
      emit "Docs/INGESTION_PIPELINE.md" "$f"; emit "CHANGELOG.md" "$f" ;;
    OpenIntelligence/Services/Embedding/* | OpenIntelligence/Services/Storage/* | OpenIntelligence/Services/VectorStore/*)
      emit "Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md" "$f"; emit "CHANGELOG.md" "$f" ;;
    OpenIntelligence/Services/AIPlatform/* | OpenIntelligence/Services/LLM/*)
      emit "Docs/PRIVACY_AND_ROUTING.md" "$f"; emit "CHANGELOG.md" "$f" ;;
    OpenIntelligence/Services/RAG/Orchestration/* | OpenIntelligence/Services/Agentic/*)
      emit "Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md" "$f"; emit "CHANGELOG.md" "$f" ;;
    OpenIntelligence/Services/Billing/* | OpenIntelligence/Features/Billing/*)
      emit "Docs/BILLING_AND_LIMITS.md" "$f"; emit "CHANGELOG.md" "$f" ;;
    OpenIntelligence/Features/* | OpenIntelligence/UI/*)
      emit "CHANGELOG.md" "$f"
      emit_advisory "WHATS_NEW.md" "$f"
      emit_advisory "Docs/USER_CHANGELOG.md" "$f" ;;
    OpenIntelligenceTests/*) : ;;
    *) : ;;
  esac

  case "${f##*/}" in
    RAGAppIntents.swift)
      emit "Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md" "$f"; emit "CHANGELOG.md" "$f" ;;
    EvidenceThread* | ThreadSidebarView.swift)
      emit "Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md" "$f"
      emit "Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md" "$f"
      emit "CHANGELOG.md" "$f" ;;
  esac
done <<< "$swift_paths"

# ---------------------------------------------------------------------------
# Second source: the RepoOS router's change-impact matrix.
#
# The table above and the matrix were written separately and neither is a superset of the other, so
# both are consulted. The router is asked once per distinct subsystem prefix rather than once per
# file: it resolves a single route per invocation and costs ~0.3s, so a 40-file change inside two
# subsystems costs two calls, not forty.
#
# Entries carrying a parenthetical ("CHANGELOG.md (if notable)") are conditional by construction and
# become advisories. Entries that are not a concrete .md file in this repository ("new report under
# Docs/AuditArtifacts/") are prose, and are dropped.
#
# Missing tooling is never fatal: the table above still stands on its own.
# ---------------------------------------------------------------------------
command -v python3 >/dev/null 2>&1 || exit 0
[ -f "$ROUTER" ] || exit 0

prefixes="$(printf '%s\n' "$swift_paths" |
  awk -F/ '{ n = (NF > 4 ? 4 : NF); s = $1; for (i = 2; i <= n; i++) s = s "/" $i; print s }' |
  sort -u | head -12)"

while IFS= read -r prefix; do
  [ -n "$prefix" ] || continue
  out="$(python3 "$ROUTER" preflight --task "documentation requirement check" \
    --path "$prefix" --format json 2>/dev/null)" || continue
  [ -n "$out" ] || continue
  docs="$(printf '%s' "$out" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for entry in (d.get("route", {}).get("required_docs_to_update") or []):
    conditional = "(" in entry
    path = entry.split("(")[0].strip()
    if path.endswith(".md"):
        print(("advisory" if conditional else "required") + "\t" + path)
' 2>/dev/null)" || continue
  while IFS=$'\t' read -r kind doc; do
    [ -n "${doc:-}" ] || continue
    [ -f "$doc" ] || continue
    if [ "$kind" = "required" ]; then
      emit "$doc" "$prefix (RepoOS router)"
    else
      emit_advisory "$doc" "$prefix (RepoOS router)"
    fi
  done <<< "$docs"
done <<< "$prefixes"

exit 0
