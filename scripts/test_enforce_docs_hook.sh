#!/bin/bash
#
# Tests for scripts/enforce_docs_hook.sh.
#
# Runs the real hook against synthetic staging sets, without touching the working tree, the real
# index, or making a commit. GIT_INDEX_FILE points git at a scratch index; blobs are written with
# `git hash-object -w` and placed with `git update-index --cacheinfo`, so `git diff --cached` and
# `git show :path` inside the hook see exactly what a real commit would present.
#
# Run: bash scripts/test_enforce_docs_hook.sh

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)" || exit 1
cd "$REPO_ROOT" || exit 1
HOOK="$REPO_ROOT/scripts/enforce_docs_hook.sh"

PASS=0
FAIL=0
SCRATCH="$(mktemp -d -t oi_hook_tests)"
trap 'rm -rf "$SCRATCH"' EXIT

# stage <path> <content>  -- put a synthetic blob at <path> in the scratch index.
#
# The content is written through a file with a trailing newline rather than piped with
# `printf %s`. Command substitution strips trailing newlines, so the piped version produced a blob
# whose last line differed from HEAD's, and git rendered that as an ADDED line at end of file. The
# changelog's last line happens to carry a "[UI]" tag, so every architecture-tag test passed on an
# artefact of the harness rather than on the fixture under test.
stage() {
  local path="$1" content="$2" blob tmp
  tmp="$SCRATCH/blob.$RANDOM"
  printf '%s\n' "$content" > "$tmp" || return 1
  blob="$(git hash-object -w -- "$tmp")" || return 1
  git update-index --add --cacheinfo "100644,$blob,$path" || return 1
}

# stage_real <path> -- stage the working-tree copy, marked changed so it appears in diff --cached.
stage_real() {
  local path="$1"
  stage "$path" "$(cat "$path")
<!-- test marker -->"
}

new_index() {
  GIT_INDEX_FILE="$SCRATCH/index.$RANDOM"
  export GIT_INDEX_FILE
  rm -f "$GIT_INDEX_FILE"
  git read-tree HEAD
}

# check <expected exit: pass|fail> <name> [<substring that must appear in output>]
check() {
  local expect="$1" name="$2" must="${3:-}" out status
  out="$(bash "$HOOK" 2>&1)"
  status=$?
  local ok=1
  if [ "$expect" = "pass" ] && [ "$status" -ne 0 ]; then ok=0; fi
  if [ "$expect" = "fail" ] && [ "$status" -eq 0 ]; then ok=0; fi
  if [ -n "$must" ] && ! printf '%s' "$out" | grep -qF "$must"; then ok=0; fi
  if [ "$ok" -eq 1 ]; then
    PASS=$((PASS + 1))
    printf '  ok    %s\n' "$name"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL  %s (expected %s, exit %s)\n' "$name" "$expect" "$status"
    printf '%s\n' "$out" | sed 's/^/          /'
  fi
}

# CHANGELOG fixtures.
#
# Fully synthetic, not derived from the real CHANGELOG.md. Two reasons, both learned here:
#
#   1. A fixture built by ${var/pat/rep} silently matched nothing when the pattern contained `<!--`,
#      so the first version of these tests staged an IDENTICAL changelog and two guards appeared to
#      pass while never running.
#   2. A fixture built from the working tree carries every other pending changelog edit into the
#      diff. The moment this session added its own tagged entries, the untagged-bullet test started
#      passing on those, because the hook's policy is "at least one added bullet carries a tag" and
#      any tagged line anywhere in the diff satisfies it. A test whose result depends on unrelated
#      pending edits is not a test.
#
# The synthetic file mirrors the real structure: an empty [Unreleased], then an open numbered
# heading carrying the marker, then a shipped section.
CL_GOOD='## [Unreleased]

<!-- next-version: 9.10 -->

## 9.9 <!-- unreleased -->

### Fixed
- **[Retrieval]** synthetic test entry.

## 9.8 - 2026-01-01

### Fixed
- **[General]** an older synthetic entry.
'
CL_UNTAGGED='## [Unreleased]

<!-- next-version: 9.10 -->

## 9.9 <!-- unreleased -->

### Fixed
- synthetic test entry with no tag.

## 9.8 - 2026-01-01

### Fixed
- an older synthetic entry, also untagged.
'
CL_UNRELEASED='## [Unreleased]

### Fixed
- **[Retrieval]** synthetic entry in the wrong section.

## 9.9 <!-- unreleased -->

## 9.8 - 2026-01-01

### Fixed
- **[General]** an older synthetic entry.
'

echo "enforce_docs_hook.sh"

new_index
stage "Docs/ai/STATE.md" "docs only, no source"
check pass "docs-only commit is not blocked"

new_index
stage "OpenIntelligence/Services/RAG/Retrieval/Synthetic.swift" "// changed"
check fail "retrieval source alone is blocked" "Docs/RETRIEVAL_PIPELINE.md"

new_index
stage "OpenIntelligence/Services/RAG/Retrieval/Synthetic.swift" "// changed"
stage "Docs/ai/STATE.md" "an unrelated doc"
check fail "REGRESSION: unrelated Docs/ file no longer satisfies a retrieval change" "Docs/RETRIEVAL_PIPELINE.md"

new_index
stage "OpenIntelligence/Services/RAG/Retrieval/Synthetic.swift" "// changed"
stage_real "Docs/RETRIEVAL_PIPELINE.md"
stage "CHANGELOG.md" "$CL_GOOD"
check pass "retrieval source with its pipeline doc and a tagged changelog passes"

new_index
stage "OpenIntelligence/Services/Storage/Synthetic.swift" "// changed"
stage "CHANGELOG.md" "$CL_GOOD"
check fail "storage change requires the Atlas, which the router alone does not cover" "Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md"

new_index
stage "OpenIntelligence/Services/AIPlatform/Synthetic.swift" "// changed"
stage "CHANGELOG.md" "$CL_GOOD"
check fail "AIPlatform change requires the privacy and routing doc" "Docs/PRIVACY_AND_ROUTING.md"

new_index
stage "OpenIntelligence/Features/Chat/Synthetic.swift" "// changed"
stage "CHANGELOG.md" "$CL_GOOD"
check pass "a Features change needs the changelog, and only advises WHATS_NEW" "WHATS_NEW.md"

new_index
stage "OpenIntelligence/Services/RAG/Retrieval/Synthetic.swift" "// changed"
stage_real "Docs/RETRIEVAL_PIPELINE.md"
stage "CHANGELOG.md" "$CL_UNRELEASED"
check fail "entries under [Unreleased] above an open heading are rejected" "[Unreleased] holds"

new_index
stage "OpenIntelligence/Services/RAG/Retrieval/Synthetic.swift" "// changed"
stage_real "Docs/RETRIEVAL_PIPELINE.md"
stage "CHANGELOG.md" "$CL_UNTAGGED"
check fail "a changelog bullet with no architecture tag is rejected" "no architecture tag"

new_index
git update-index --force-remove "OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift"
check pass "a commit that only deletes source needs no documentation"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
