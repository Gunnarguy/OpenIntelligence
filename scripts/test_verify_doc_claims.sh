#!/usr/bin/env bash
#
# Prove verify_doc_claims.py fails when a claim breaks.
#
# A gate that passes is not evidence it works; it is equally consistent with a
# gate that can never fire. Each case below breaks exactly one kind of claim and
# asserts that the verifier reports that break by name. A non-zero exit alone is
# not enough, because it cannot tell the break under test from any other failure.
#
# Nothing in the checkout is written. The verifier finds its root from its own
# location, so every run happens in a scratch replica under $TMPDIR: Docs/,
# scripts/, OpenIntelligence/ and the top-level files are copied (APFS clones
# where the filesystem allows), and every other top-level directory is a symlink
# back, which is all the path-existence check needs. The trap deletes the replica
# on any exit.
#
# Rewritten 2026-09-21, after two of the five cases were found to control nothing:
#
#   - "a wrong shipped version" edited literal status-line text that the 5.1
#     release rewrote on 2026-09-02 (a375fc8). The missing-fixture error was
#     swallowed, so the verifier ran on an unbroken document and the report blamed
#     the verifier. The case now writes its own claim, so no document edit can
#     remove it.
#   - The floor case split "old||new" on the first "||", which left an empty
#     alternative in SHIPPED_PHRASE. That pattern matched at every word boundary,
#     so the run failed on lines such as the iOS 26.0 deployment target and the
#     floor was never reached: the mutated pattern still matched 17 claims at
#     845c7b9, where this test was written, and 28 at 3cce8b3.
#
# Until the same date the cases edited tracked files in place and restored them
# from a mktemp backup with mv. That restore overwrites any edit made to the file
# while a case runs, and it left all four files at mode 0600.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/test_verify_doc_claims.XXXXXX")" || exit 1
trap 'rm -rf "$SCRATCH"' EXIT
REPLICA="$SCRATCH/repo"
mkdir "$REPLICA" || exit 1

clone() {  # clone <src> <dst>: an APFS clone where the filesystem allows, a plain copy otherwise
  cp -cR "$1" "$2" 2>/dev/null && return 0
  rm -rf "$2"
  cp -R "$1" "$2"
}

# Copied: the directories a case edits, and OpenIntelligence/, which the verifier
# walks with find and grep. find never descends a symlinked directory, and the
# macOS grep (BSD) does not either. Top-level files are copied too, so no case can
# ever write through a link into the checkout.
shopt -s nullglob dotglob
for entry in "$ROOT"/*; do
  name="${entry##*/}"
  case "$name" in
    .git | .git.nosync) continue ;;   # the verifier never reads git
    Docs | scripts | OpenIntelligence) clone "$entry" "$REPLICA/$name" ;;
    *) if [ -d "$entry" ]; then ln -s "$entry" "$REPLICA/$name"; else clone "$entry" "$REPLICA/$name"; fi ;;
  esac || { echo "cannot build the replica: $name" >&2; exit 1; }
done
shopt -u nullglob dotglob

verify() { (cd "$REPLICA" && python3 scripts/verify_doc_claims.py 2>&1); }

KEPT=()             # "saved::replica file" pairs that restore_all puts back
FIXTURE_MISSING=""  # set when a case could not be staged; reported as that, never as a verifier miss

keep() {  # keep <replica file>: save it so restore_all can put it back
  local k="$SCRATCH/kept.${#KEPT[@]}"
  cp "$1" "$k" && KEPT+=("$k::$1")
}

restore_all() {
  local entry
  for entry in ${KEPT[@]+"${KEPT[@]}"}; do cp "${entry%%::*}" "${entry##*::}"; done
  KEPT=()
  FIXTURE_MISSING=""
}

stageable() {  # stageable <file>: a real copied file in the replica, never a link into the checkout
  [ -f "$REPLICA/$1" ] && [ ! -L "$REPLICA/$1" ] && return 0
  FIXTURE_MISSING="$1 is not a copied file in the replica"
  return 1
}

mutate() {  # mutate <file> <old> <new>: replace the first <old> in the replica's copy of <file>
  stageable "$1" || return 0
  keep "$REPLICA/$1"
  if ! python3 - "$REPLICA/$1" "$2" "$3" <<'PY'
import pathlib, sys
p, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
t = p.read_text()
if old not in t:
    sys.exit(1)
p.write_text(t.replace(old, new, 1))
PY
  then
    FIXTURE_MISSING="fixture text not found in $1: ${2:0:60}"
  fi
}

append() {  # append <file> <line>: add a line of this test's own making to the replica's copy
  stageable "$1" || return 0
  keep "$REPLICA/$1"
  printf '\n%s\n' "$2" >> "$REPLICA/$1"
}

expect_fail() {  # expect_fail <name> <text the verifier must print>
  local name="$1" must="$2" out
  if [ -n "$FIXTURE_MISSING" ]; then
    echo "  FAIL  $name: the case did not run, $FIXTURE_MISSING"
    FAIL=$((FAIL + 1))
  elif out="$(verify)"; then
    echo "  FAIL  $name: verifier passed on a broken claim"
    FAIL=$((FAIL + 1))
  elif printf '%s\n' "$out" | grep -qF -- "$must"; then
    echo "  ok    $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL  $name: verifier failed, but never said: $must"
    printf '%s\n' "$out" | sed 's/^/          /'
    FAIL=$((FAIL + 1))
  fi
  restore_all
}

echo "verify_doc_claims: does it actually fire?"

# Baseline: the checkout's documents as they are now, read through the replica.
# This is the one result here that depends on the checkout, by design. The cases
# below do not lean on it, because each asserts its own failure line.
if out="$(verify)"; then
  echo "  ok    baseline is clean"
  PASS=$((PASS + 1))
else
  echo "  FAIL  baseline is already failing; fix that before trusting these cases"
  printf '%s\n' "$out" | sed 's/^/          /'
  FAIL=$((FAIL + 1))
fi

# Synthesized, not found: a claim this test writes itself, naming a version no
# build of this app has carried, next to the phrase the verifier anchors on.
append Docs/INGESTION_PIPELINE.md '**iOS 0.0.1** is the shipped version.'
expect_fail "a wrong shipped version is caught" "claims iOS 0.0.1 is shipped"

mutate Docs/RETRIEVAL_PIPELINE.md \
  '`vector`, `lexical`, `fusion`, `boosted`, `candidates`, `rerank`, `final`' \
  '`vector`, `lexical`, `fusion`, `boosted`, `rerank`, `final`'
expect_fail "an enum case missing from a doc is caught" "doc omits case(s) ['candidates']"

mutate Docs/ai/ARCHITECTURE.md \
  'Docs/INGESTION_PIPELINE.md' \
  'Docs/INGESTION_PIPELINE_THAT_DOES_NOT_EXIST.md'
expect_fail "a reference to a missing path is caught" \
  'references missing path `Docs/INGESTION_PIPELINE_THAT_DOES_NOT_EXIST.md`'

mutate Docs/RETRIEVAL_PIPELINE.md 'RAGEngine.swift:82' 'RAGEngine.swift:9999999'
expect_fail "a line anchor past end of file is caught" \
  'anchor `RAGEngine.swift:9999999` is past end of file'

# The floor guard: a pattern that stops matching must not read as a pass.
# Rebinding the pattern to one that matches nothing, just before main() runs,
# takes the version count to zero whatever the documents say.
mutate scripts/verify_doc_claims.py \
  'if __name__ == "__main__":' \
  $'SHIPPED_PHRASE = re.compile(r"(?!)")  # test_verify_doc_claims.sh: match nothing\n\nif __name__ == "__main__":'
expect_fail "a rule that stops matching trips its floor instead of passing" \
  "the 'version' rule matched 0 claims, below its floor"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
