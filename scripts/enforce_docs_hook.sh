#!/bin/bash

# A pre-commit hook that ensures WHATS_NEW.md or CHANGELOG.md is updated
# whenever source code (.swift files) are modified, AND enforces
# OpenIntelligence architectural mapping in the changelog.

# Get a list of all staged files
staged_files=$(git diff --cached --name-only)

# Check if any .swift files are staged
swift_changed=false
for file in $staged_files; do
    if [[ "$file" == *".swift" ]]; then
        swift_changed=true
        break
    fi
done

# If swift files changed, check if documentation was updated
if [ "$swift_changed" = true ]; then
    docs_updated=false
    changelog_staged=false

    for file in $staged_files; do
        if [[ "$file" == "WHATS_NEW.md" ]] || [[ "$file" == "CHANGELOG.md" ]] || [[ "$file" == Docs/* ]]; then
            docs_updated=true
            if [[ "$file" == "CHANGELOG.md" ]]; then
                changelog_staged=true
            fi
        fi
    done

    if [ "$docs_updated" = false ]; then
        echo "======================================================================"
        echo "❌ PRE-COMMIT HOOK FAILED: Missing Documentation Update"
        echo "======================================================================"
        echo "You have modified .swift source files but failed to update the"
        echo "project documentation (WHATS_NEW.md, CHANGELOG.md, or Docs/)."
        echo "Antigravity/Jules/Developer Rule: Full Closed Loop Required."
        echo "======================================================================"
        exit 1
    fi

    # Enforce Architectural Tags in CHANGELOG.md
    if [ "$changelog_staged" = true ]; then
        # Check the added lines in CHANGELOG.md for architecture tags
        added_lines=$(git diff --cached CHANGELOG.md | grep "^+")
        
        # Valid tags based on OpenIntelligence architecture
        if ! echo "$added_lines" | grep -qE "\[Ingestion\]|\[Chunking\]|\[Indexing\]|\[Retrieval\]|\[Orchestration\]|\[Shortcuts\]|\[UI\]|\[General\]|\[Infrastructure\]"; then
            echo "======================================================================"
            echo "❌ PRE-COMMIT HOOK FAILED: Missing Architecture Tag"
            echo "======================================================================"
            echo "You updated CHANGELOG.md, but you failed to map the change to a"
            echo "core OpenIntelligence architectural component."
            echo ""
            echo "Valid tags required on new bullet points:"
            echo "  [Ingestion], [Chunking], [Indexing], [Retrieval], [Orchestration],
  [Shortcuts], [UI], [General], [Infrastructure]"
            echo "======================================================================"
            exit 1
        fi
    fi
fi

exit 0
