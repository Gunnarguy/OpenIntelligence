#!/usr/bin/env bash
#
# Prove verify_doc_claims.py fails when a claim breaks.
#
# A gate that passes is not evidence it works; it is equally consistent with a
# gate that can never fire. Each case below breaks exactly one kind of claim in a
# scratch copy of a real document, asserts a non-zero exit, and restores.
#
# Every mutation is applied to a backup-and-restore of a tracked file. The trap
# restores on any exit path, including a failed assertion, so an interrupted run
# cannot leave a document corrupted.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PASS=0
FAIL=0
BACKUPS=()

restore_all() {
  for entry in "${BACKUPS[@]:-}"; do
    [ -n "$entry" ] || continue
    src="${entry%%::*}"; dst="${entry##*::}"
    [ -f "$src" ] && mv "$src" "$dst"
  done
}
trap restore_all EXIT

mutate() {   # mutate <file> <python-replacement-expression>
  local f="$1" expr="$2" bak
  bak="$(mktemp)"
  cp "$f" "$bak"
  BACKUPS+=("$bak::$f")
  python3 - "$f" "$expr" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); t = p.read_text()
old, new = sys.argv[2].split("||", 1)
assert old in t, f"fixture text not found in {sys.argv[1]}: {old[:60]}"
p.write_text(t.replace(old, new, 1))
PY
}

expect_fail() {  # expect_fail <name>
  local name="$1"
  if python3 scripts/verify_doc_claims.py >/dev/null 2>&1; then
    echo "  FAIL  $name — verifier passed on a broken claim"
    FAIL=$((FAIL + 1))
  else
    echo "  ok    $name"
    PASS=$((PASS + 1))
  fi
  restore_all
  BACKUPS=()
}

echo "verify_doc_claims: does it actually fire?"

# Baseline. If this is already failing the rest of the run means nothing.
if python3 scripts/verify_doc_claims.py >/dev/null 2>&1; then
  echo "  ok    baseline is clean"
  PASS=$((PASS + 1))
else
  echo "  FAIL  baseline is already failing; fix that before trusting these cases"
  FAIL=$((FAIL + 1))
fi

mutate Docs/INGESTION_PIPELINE.md \
  '**iOS 5.0** (approved 2026-08-27)||**iOS 4.2** (approved 2026-08-27)'
expect_fail "a wrong shipped version is caught"

mutate Docs/RETRIEVAL_PIPELINE.md \
  '`vector`, `lexical`, `fusion`, `boosted`, `candidates`, `rerank`, `final`||`vector`, `lexical`, `fusion`, `boosted`, `rerank`, `final`'
expect_fail "an enum case missing from a doc is caught"

mutate Docs/ai/ARCHITECTURE.md \
  'Docs/INGESTION_PIPELINE.md||Docs/INGESTION_PIPELINE_THAT_DOES_NOT_EXIST.md'
expect_fail "a reference to a missing path is caught"

mutate Docs/RETRIEVAL_PIPELINE.md \
  'RAGEngine.swift:82||RAGEngine.swift:9999999'
expect_fail "a line anchor past end of file is caught"

# The floor guard: a pattern that stops matching must not read as a pass.
mutate scripts/verify_doc_claims.py \
  'r"\b(is the shipped version|are the shipped versions||r"\b(NEVER_MATCHES_ANYTHING|'
expect_fail "a rule that stops matching trips its floor instead of passing"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
