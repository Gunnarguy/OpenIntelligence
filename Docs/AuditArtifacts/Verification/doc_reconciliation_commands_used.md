# Documentation Reconciliation and Correction Commands Used

This document records the exact shell commands, custom scripts, and search terms used to discover repository documentation, extract claims, analyze contradictions, and verify them against the codebase during the reconciliation and correction pass.

---

## 1. Documentation File Discovery
To locate all Markdown and configuration files in the workspace (excluding local build and git caches), the following discovery methods were executed:

*   **Discovery Script:**
    ```bash
    python3 /Users/gunnarhostetler/.gemini/antigravity-ide/brain/e9eacc47-2c8a-49c2-bd44-bf4e392291fd/scratch/discover_docs.py
    ```
    This script traverses all subdirectories recursively, ignores build caches, and compiles the list of all files matching `.md`, `.txt`, `.storekit`, `.entitlements`, `.plist`, and `.json`.

---

## 2. Claim Extraction and Verification
A custom compiler script was run to construct the inventory, claim matrix, and decision register:

*   **Compiler Script:**
    ```bash
    python3 /Users/gunnarhostetler/.gemini/antigravity-ide/brain/e9eacc47-2c8a-49c2-bd44-bf4e392291fd/scratch/generate_doc_artifacts.py
    ```
    This outputted:
    *   `document_inventory.csv`
    *   `document_claim_matrix.csv`
    *   `document_contradictions.csv`
    *   `canonical_decision_register.csv`

---

## 3. Code-to-Document Verification Searches
Ripgrep and search tools were run to verify whether document claims matched code realities:

*   **Verify UserDefaults Consent Keys:**
    ```bash
    grep -rn "cloudConsent.applePCC" OpenIntelligence/
    grep -rn "applePCCConsent" OpenIntelligence/
    ```
    This confirmed that settings use the key `"cloudConsent.applePCC"`, exposing the key mismatch in the previous audit reports.

*   **Verify Workspace Sync Sweeping Rules:**
    ```bash
    grep -rn "localOnlyEntryNames" OpenIntelligence/
    ```
    This confirmed that subdirectories of the base directory are recursively copied unless excluded via `"LocalCache"` or `"FTS5"`.

*   **Verify App Shortcut Count and Limits:**
    ```bash
    grep -rn "AppShortcut(" OpenIntelligence/
    ```
    This confirmed exactly 9 shortcuts are active in `RAGAppShortcutsProvider`.

*   **Verify Pro Tier Quota Constants:**
    ```bash
    grep -rn "proDocumentLimit" OpenIntelligence/
    ```
    This verified that the Pro tier document limit is capped at 1,000, exposing the discrepancy in the root `README.md` (which claimed Pro supports unlimited documents).
