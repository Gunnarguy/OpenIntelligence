# Audit Commands Used

This document records the exact shell commands, repository queries, and custom scripts utilized during the full repository audit of OpenIntelligence.

---

## 1. File Inventory and Exclusions Manifest
The file inventory and exclusion tracking were generated using a combination of Git utilities and a custom Python script:

*   **Tracked Files Discovery:**
    ```bash
    git ls-files
    ```
*   **Untracked Files Discovery:**
    ```bash
    git status --porcelain
    ```
*   **Run Custom Inventory Compiler:**
    ```bash
    python3 /Users/gunnarhostetler/.gemini/antigravity-ide/brain/e9eacc47-2c8a-49c2-bd44-bf4e392291fd/scratch/generate_audit_artifacts.py
    ```
    This script traverses all tracked files, filters them by category, calculates line counts, generates SHA-256 checksums, and outputs:
    *   `full_file_inventory.csv`
    *   `excluded_files_manifest.csv`
    *   `line_coverage_manifest.csv`

---

## 2. Line Counts Verification
For manual corroboration of Python line counts, the following commands were run:

*   **Count Swift source lines in App target:**
    ```bash
    find OpenIntelligence -name "*.swift" -not -path "*/swift-transformers/*" | xargs wc -l
    ```
*   **Count Swift source lines in Test target:**
    ```bash
    find OpenIntelligenceTests -name "*.swift" | xargs wc -l
    ```

---

## 3. Swift Symbol Inventory
The symbol inventory was parsed via a multi-line regular expression inside `generate_audit_artifacts.py`:

*   **Regular Expression Pattern:**
    ```regex
    ^\s*(struct|class|enum|protocol|actor|extension)\s+([A-Za-z0-9_<>:\s,\.]+?)(?=\s*\{|\s*$)
    ```
    This compiles the catalog of classes, structs, enums, protocols, actors, and extensions into `swift_symbol_inventory.csv`.

---

## 4. Codebase Grep Queries
To investigate persistence, routing, and synchronization boundaries, standard ripgrep (`rg`) or grep queries were performed:

*   **Verify ChatV2 Persistence Calls:**
    ```bash
    grep -rn "persistChatHistory" OpenIntelligence/
    ```
*   **Search for Private Cloud Compute Consent Preferences:**
    ```bash
    grep -rn "applePCCConsent" OpenIntelligence/
    grep -rn "cloudConsent.applePCC" OpenIntelligence/
    ```
*   **Verify iCloud Sync Exclusion Keys:**
    ```bash
    grep -rn "localOnlyEntryNames" OpenIntelligence/
    ```
*   **Verify App Shortcut Capacity limits:**
    ```bash
    grep -rn "AppShortcut(" OpenIntelligence/
    ```
*   **Search for hardcoded prices in the UI:**
    ```bash
    grep -rn "\$[0-9]\+\.[0-9]\{2\}" OpenIntelligence/
    ```
