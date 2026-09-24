#!/bin/bash
#
# Pre-commit: a source change must carry the documentation its subsystem requires.
#
# Installed as .git/hooks/pre-commit (a symlink to this file).
#
# WHAT CHANGED AND WHY, 2026-08-28
#
# The previous version asked one question: "did any .swift file change, and did ANY of
# WHATS_NEW.md, CHANGELOG.md or Docs/* change too?" Any documentation file satisfied any source
# change. Staging Docs/ai/STATE.md was enough to let a retrieval-engine rewrite through with
# Docs/RETRIEVAL_PIPELINE.md untouched -- the exact drift AGENTS.md rule 14 and
# .agents/rules/01-docs-and-notion-sync.md exist to prevent. The rule was real; the check was not.
#
# Now the staged paths go through scripts/required_docs.sh, which resolves each one to the specific
# documents it requires, and this hook fails naming them. The same resolver runs at end of session
# from .claude/hooks/stop-handoff.sh, so the two enforcement points cannot disagree.
#
# There is no environment-variable bypass on purpose. `git commit --no-verify` still works and is a
# visible, deliberate act; a documented skip flag becomes the default within a month.
#
# Tested by scripts/test_enforce_docs_hook.sh, which stages synthetic blobs into a scratch index and
# runs this file for real. Run it after any change here.

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -n "$REPO_ROOT" ] || exit 0
cd "$REPO_ROOT" || exit 0

RESOLVER="$REPO_ROOT/scripts/required_docs.sh"

# --diff-filter=ACMR: a file being DELETED cannot require documentation about its behaviour. The old
# hook used a bare --name-only, so a commit that only removed Swift files demanded a changelog entry
# for code that no longer exists.
staged="$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null)"
[ -n "$staged" ] || exit 0
# Swift source, or the App Store copy: the two kinds of path scripts/required_docs.sh maps.
printf '%s\n' "$staged" | grep -qE '\.swift$|^fastlane/metadata(-ios)?/' || exit 0

is_staged() { printf '%s\n' "$staged" | grep -qxF "$1"; }

if [ ! -x "$RESOLVER" ]; then
  echo "note: scripts/required_docs.sh missing; documentation requirements not checked." >&2
  exit 0
fi

REQUIREMENTS="$(printf '%s\n' "$staged" | bash "$RESOLVER" 2>/dev/null)" || REQUIREMENTS=""

MISSING=()
while IFS= read -r doc; do
  [ -n "$doc" ] || continue
  is_staged "$doc" || MISSING+=("$doc")
done < <(printf '%s\n' "$REQUIREMENTS" | awk -F'\t' '$1 == "required" { print $2 }' | sort -u)

if [ "${#MISSING[@]}" -gt 0 ]; then
  echo "======================================================================"
  echo "PRE-COMMIT FAILED: staged source changed without its required docs"
  echo "======================================================================"
  for doc in "${MISSING[@]}"; do
    echo ""
    echo "  MISSING: $doc"
    printf '%s\n' "$REQUIREMENTS" |
      awk -F'\t' -v d="$doc" '$1 == "required" && $2 == d { print $3 }' |
      sort -u | head -4 | sed 's/^/    required by: /'
  done
  echo ""
  echo "The mapping is .agents/rules/01-docs-and-notion-sync.md, enforced by"
  echo "scripts/required_docs.sh. Stage the documents above, or unstage the"
  echo "source they describe."
  echo "======================================================================"
  exit 1
fi

# ---------------------------------------------------------------------------
# App Store copy, only when fastlane/metadata* is itself staged (added 2026-09-18).
#
# scripts/required_docs.sh already makes the history file required. That proves the file was
# touched, not that the version got an entry or that the copy has the shape every release since
# 5.1 has shipped in. Both are checked here, against STAGED content, so the check describes the
# commit being made. The shape is written down in the template section of the history file.
# ---------------------------------------------------------------------------
staged_metadata="$(printf '%s\n' "$staged" | grep -E '^fastlane/metadata(-ios)?/' || true)"
if [ -n "$staged_metadata" ]; then
  HISTORY="Docs/Release/APP_STORE_METADATA_HISTORY.md"
  metadata_fail() {
    echo "======================================================================"
    echo "PRE-COMMIT FAILED: App Store copy $1"
    echo "======================================================================"
    shift; printf '%s\n' "$@"
    echo "The template and its rules: $HISTORY, section \"Template for the next version\"."
    echo "======================================================================"
    exit 1
  }
  # The version being prepared, from the marker file (staged copy first), never from CHANGELOG.
  marker="$(git show :Docs/SHIPPED_VERSION.json 2>/dev/null || cat Docs/SHIPPED_VERSION.json 2>/dev/null || true)"
  preparing="$(printf '%s' "$marker" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("preparing",""))
except Exception: print("")' 2>/dev/null || true)"
  history="$(git show ":$HISTORY" 2>/dev/null || cat "$HISTORY" 2>/dev/null || true)"
  # A here-string, not `printf | grep -q`: under `set -o pipefail` that pipe fails whenever the input
  # outgrows a pipe buffer, because grep exits at its first match and printf dies of SIGPIPE. The
  # history passed 64 KB on 2026-09-23 and a commit whose history did carry the heading was refused.
  if [ -n "$preparing" ] && ! grep -qE "^### ${preparing//./\\.}( |$)" <<<"$history"; then
    metadata_fail "changed without a history entry for v$preparing" \
      "Docs/SHIPPED_VERSION.json says v$preparing is being prepared, and $HISTORY has no" \
      "'### $preparing' heading. Copy the template into the top of \"Versions, newest first\"," \
      "fill it in with this copy verbatim, and stage the file."
  fi
  for f in $staged_metadata; do
    content="$(git show ":$f" 2>/dev/null || true)"
    [ -n "$content" ] || continue
    chars="$(printf '%s' "$content" | wc -m | tr -d ' ')"
    case "${f##*/}" in
      release_notes.txt)
        [ "$chars" -le 4000 ] || metadata_fail "release notes are $chars characters; the App Store limit is 4,000" "  $f"
        first="$(printf '%s\n' "$content" | grep -m1 -v '^[[:space:]]*$' || true)"
        if printf '%s' "$first" | grep -qE '^[[:upper:][:space:][:punct:]]+$' || printf '%s' "$first" | grep -q '^•'; then
          metadata_fail "release notes do not open with an intro sentence" "  $f begins: ${first:0:80}" "The first line is a sentence of prose, not a heading or a bullet."
        fi
        printf '%s\n' "$content" | grep -qE '^[[:upper:]][[:upper:][:digit:][:space:][:punct:]]{3,}$' ||
          metadata_fail "release notes have no ALL-CAPS section heading" "  $f" "Every release since 5.1 groups its bullets under short capitalised headings."
        if printf '%s\n' "$content" | grep -qE '^[[:space:]]*[-*] '; then
          metadata_fail "release notes use '-' or '*' bullets" "  $f" "Use '• ' (U+2022 and a space)."
        fi
        printf '%s\n' "$content" | grep -q '^• ' ||
          metadata_fail "release notes have no '• ' bullets" "  $f" "Bullets are U+2022 and a space. '-' and '*' are the shapes this file exists to end."
        printf '%s' "$content" | grep -q '—' && metadata_fail "release notes contain an em dash" "  $f" "Store copy carries none; bd70890 stripped them on 2026-07-28."
        ;;
      promotional_text.txt)
        [ "$chars" -le 170 ] || metadata_fail "promotional text is $chars characters; the App Store limit is 170" "  $f"
        printf '%s' "$content" | grep -q '—' && metadata_fail "promotional text contains an em dash" "  $f"
        ;;
      description.txt)
        [ "$chars" -le 4000 ] || metadata_fail "description is $chars characters; the App Store limit is 4,000" "  $f"
        ;;
    esac
  done
fi

# ---------------------------------------------------------------------------
# CHANGELOG hygiene, only when CHANGELOG.md is itself staged.
# ---------------------------------------------------------------------------
if is_staged "CHANGELOG.md"; then
  # 1. Architecture tag on new bullets.
  #
  # Only ADDED BULLET lines are examined. The original hook grepped every line starting with "+",
  # which includes the "+++ b/CHANGELOG.md" header and any unrelated added line anywhere in the
  # diff. While testing this rewrite, a diff whose only new bullet was untagged still passed,
  # because an unrelated "[UI]" line elsewhere in the same diff satisfied the grep. A check that any
  # line can satisfy is not a check.
  #
  # The policy is unchanged: at least one new bullet must carry a tag, not every one. This
  # changelog's history uses tags outside the approved set ([Privacy], [Platform], [Compatibility],
  # [Settings], [Diagnostics]), so demanding the approved set on every bullet would fail commits
  # that follow established practice.
  added_bullets="$(git diff --cached CHANGELOG.md | grep -E '^\+[[:space:]]*-' || true)"
  # Here-string for the same reason as the history check above: a large addition would fail on SIGPIPE.
  if [ -n "$added_bullets" ] && ! grep -qE "\[Ingestion\]|\[Chunking\]|\[Indexing\]|\[Retrieval\]|\[Orchestration\]|\[Shortcuts\]|\[UI\]|\[General\]|\[Infrastructure\]" <<<"$added_bullets"; then
    echo "======================================================================"
    echo "PRE-COMMIT FAILED: CHANGELOG.md entry has no architecture tag"
    echo "======================================================================"
    echo "Every new bullet maps to a component:"
    echo "  [Ingestion] [Chunking] [Indexing] [Retrieval] [Orchestration]"
    echo "  [Shortcuts] [UI] [General] [Infrastructure]"
    echo "======================================================================"
    exit 1
  fi

  # 2. The [Unreleased] block must stay empty while a numbered heading is still open.
  #
  # This is ci_post_clone.sh's guard, run at commit time instead of at build time, with the same awk
  # and the same grep on purpose. On 2026-07-28 [Unreleased] accumulated a release worth of entries
  # above an uncut 4.6 heading, CI stamped 4.6, and App Store Connect rejected the build. Failing
  # here costs a second; failing there costs a build slot and a round trip.
  #
  # Reads the STAGED content, not the working tree, so the check describes the commit being made.
  staged_changelog="$(git show :CHANGELOG.md 2>/dev/null)"
  if [ -n "$staged_changelog" ]; then
    unreleased_entries="$(printf '%s\n' "$staged_changelog" |
      awk '/^## \[Unreleased\]/ {inside=1; next} /^## / {inside=0} inside' |
      grep -c -E '^[[:space:]]*(-|###)' || true)"
    case "$unreleased_entries" in '' | *[!0-9]*) unreleased_entries=0 ;; esac
    if [ "$unreleased_entries" -gt 0 ]; then
      open_heading="$(printf '%s\n' "$staged_changelog" | grep -m1 '^## [0-9]' || true)"
      echo "======================================================================"
      echo "PRE-COMMIT FAILED: CHANGELOG [Unreleased] holds $unreleased_entries entrie(s)"
      echo "======================================================================"
      echo "The first numbered heading is:"
      echo "    ${open_heading:-<none>}"
      echo ""
      echo "ci_post_clone.sh stamps MARKETING_VERSION from that heading and refuses"
      echo "to build while [Unreleased] is non-empty, because entries above an"
      echo "uncut heading mean the heading describes a version already released."
      echo ""
      echo "Put the entries under the open numbered heading instead."
      echo "======================================================================"
      exit 1
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Documentation claims must still match source.
#
# The check above enforces that a document was *touched*. This one enforces that
# what it says is *true*. Added 2026-09-01 after a claim-by-claim re-read found
# two foundational documents asserting a shipped version eight weeks out of date,
# disagreeing with each other about an enum's cases, and citing paths that no
# longer existed -- all mechanically checkable, none caught.
#
# Only runs when a checked document or Swift source is staged, so an unrelated
# commit does not pay for it.
#
# `-f`, not `-x`: git stores the script as 100644 and it is run through python3, so
# until 2026-09-24 an executable-bit test skipped this gate on every fresh clone.
# ---------------------------------------------------------------------------
if [ -f "$REPO_ROOT/scripts/verify_doc_claims.py" ] \
   && git diff --cached --name-only | grep -qE '\.(md|swift|json)$'; then
  if ! CLAIM_OUT="$(python3 "$REPO_ROOT/scripts/verify_doc_claims.py" 2>&1)"; then
    echo "======================================================================"
    echo "Documentation claims no longer match source."
    echo "$CLAIM_OUT"
    echo "======================================================================"
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Advisories. These never block.
# ---------------------------------------------------------------------------
ADVICE=()
while IFS= read -r doc; do
  [ -n "$doc" ] || continue
  is_staged "$doc" || ADVICE+=("$doc")
done < <(printf '%s\n' "$REQUIREMENTS" | awk -F'\t' '$1 == "advisory" { print $2 }' | sort -u)

if [ "${#ADVICE[@]}" -gt 0 ]; then
  echo "note: consider also updating, if this change is user-visible or notable:"
  for doc in "${ADVICE[@]}"; do echo "        $doc"; done
fi

exit 0
