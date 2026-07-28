#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# iCloud damage check for the OpenIntelligence repository.
#
#   RUN THIS FIRST when a build fails in a way that makes no sense:
#   duplicate symbols, "invalid redeclaration", a type that is somehow declared
#   twice, a codesign "resource fork / Finder information" error, or git
#   complaining about a broken ref name.
#
#   scripts/check_icloud_conflicts.sh          # report; exit 1 if damaged
#   scripts/check_icloud_conflicts.sh --fix    # report, then repair
#   scripts/check_icloud_conflicts.sh --quiet  # silent unless damaged
#
# WHY THIS EXISTS
# This repo lives in iCloud-synced ~/Documents (`brctl status` →
# "Desktop & Documents: current=YES"). When iCloud cannot reconcile two
# versions of a file it silently writes a duplicate beside it named
# "<file> 2.<ext>". Three things make that dangerous here:
#
#   1. The Xcode project uses SYNCHRONIZED FILE GROUPS. A stray
#      "SemanticChunker 2.swift" is picked up as a real source file and
#      compiled, producing duplicate-symbol errors that look nothing like a
#      sync problem.
#   2. It has already corrupted the git object store — four conflict copies of
#      .git/index and a duplicate branch ref were found on 2026-07-28. The git
#      directory is now shielded as .git.nosync/ (see below), but that shield
#      can be undone by anything that recreates a plain .git directory.
#   3. Finder metadata (.DS_Store) inside .git/refs makes `git fsck` fail with
#      "badRefName".
#
# Full write-up: Docs/AUDIT/ROADMAP_RECONCILIATION_2026-07-28.md (finding F-02)
# and .agent/RISK_REGISTER.md (RISK-20).
#
# NOTE: this checks the working tree and git metadata. It does NOT fix build
# products — for those, build with -derivedDataPath outside ~/Documents.
# ==============================================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX=0
QUIET=0

for arg in "$@"; do
    case "$arg" in
        --fix)   FIX=1 ;;
        --quiet) QUIET=1 ;;
        -h|--help)
            sed -n '3,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "unknown option: $arg (try --help)" >&2
            exit 2
            ;;
    esac
done

cd "$ROOT_DIR"
PROBLEMS=0
say() { [[ $QUIET -eq 1 ]] || echo "$@"; }

# ------------------------------------------------------------------ 1. conflicts
# Names ending in " <n>" or " <n>.ext" — iCloud's conflict-copy pattern.
# Build output is excluded: those trees are regenerated and not worth failing on.
#
# Deliberately uses -name globs rather than -regex. `find -regex` has three
# incompatible dialects (BSD find, GNU findutils, bfs) and this repo's shell
# shadows `find` with a bfs wrapper, so a regex that works interactively can
# silently match nothing when the script runs under /usr/bin/find. Globs behave
# identically everywhere.
#
# Results are collected with a while-read loop, not `mapfile`: macOS ships
# bash 3.2 as /bin/bash and mapfile does not exist there.
CONFLICT_LIST="$(
    find . \
        \( -name '* [0-9]' -o -name '* [0-9].*' \
           -o -name '* [0-9][0-9]' -o -name '* [0-9][0-9].*' \) \
        -not -path './.git.nosync/*' \
        -not -path './.git/*' \
        -not -path './.build*' \
        -not -path './build/*' \
        -not -path './*.nosync/*' \
        2>/dev/null | sort
)"

if [[ -n "$CONFLICT_LIST" ]]; then
    PROBLEMS=1
    COUNT="$(printf '%s\n' "$CONFLICT_LIST" | wc -l | tr -d ' ')"
    echo "PROBLEM: $COUNT iCloud conflict copy/copies in the working tree:"
    printf '%s\n' "$CONFLICT_LIST" | sed 's/^/  /'
    if [[ $FIX -eq 1 ]]; then
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            rm -rf -- "$f"
            echo "  removed: $f"
        done <<< "$CONFLICT_LIST"
    else
        echo "  -> inspect with: diff \"<original>\" \"<conflict copy>\""
        echo "  -> or re-run with --fix to delete them"
    fi
fi

# ------------------------------------------------- 2. is the .git shield intact?
if [[ -d .git && ! -f .git ]]; then
    PROBLEMS=1
    echo "PROBLEM: .git is a real directory again — the iCloud shield is gone."
    echo "  The git object store is being synced and can be corrupted."
    echo "  -> restore with:"
    echo "       mv .git .git.nosync && printf 'gitdir: .git.nosync\\n' > .git"
elif [[ -f .git ]]; then
    say "OK: .git is a gitdir pointer ($(tr -d '\n' < .git)) — object store is outside iCloud sync."
fi

# --------------------------------------------------- 3. Finder junk inside gitdir
GITDIR="$(git rev-parse --git-dir 2>/dev/null || echo '')"
if [[ -n "$GITDIR" ]]; then
    DSSTORE_LIST="$(find "$GITDIR" -name '.DS_Store' 2>/dev/null | sort)"
    if [[ -n "$DSSTORE_LIST" ]]; then
        PROBLEMS=1
        DS_COUNT="$(printf '%s\n' "$DSSTORE_LIST" | wc -l | tr -d ' ')"
        echo "PROBLEM: $DS_COUNT .DS_Store file(s) inside the git directory:"
        printf '%s\n' "$DSSTORE_LIST" | sed 's/^/  /'
        echo "  (one inside refs/ makes 'git fsck' report badRefName)"
        if [[ $FIX -eq 1 ]]; then
            find "$GITDIR" -name '.DS_Store' -delete 2>/dev/null || true
            echo "  removed."
        else
            echo "  -> re-run with --fix to delete them"
        fi
    fi
fi

# ------------------------------------------------------------------ 4. git health
if [[ -n "$GITDIR" ]]; then
    FSCK="$(git fsck --no-progress --connectivity-only 2>&1 | grep -vE '^dangling' || true)"
    if [[ -n "$FSCK" ]]; then
        PROBLEMS=1
        echo "PROBLEM: git fsck reported errors:"
        printf '  %s\n' "$FSCK"
        echo "  -> re-run this script with --fix, then check again"
    fi
fi

# ---------------------------------------------------------------------- verdict
if [[ $PROBLEMS -eq 0 ]]; then
    say "OK: no iCloud damage found."
    exit 0
fi

if [[ $FIX -eq 1 ]]; then
    echo
    echo "Repairs applied. Re-run without --fix to confirm clean."
    exit 0
fi

echo
echo "Run 'scripts/check_icloud_conflicts.sh --fix' to repair."
exit 1
