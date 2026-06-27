# Documentation Reconciliation Workflow

This playbook dictates how agents should update, merge, or deprecate stale documentation without losing critical technical specificity.

## Core Rules
1. **Preserve Technical Specificity**: Do not remove technical details merely because they are complex or dense.
2. **Label Claims Clearly**: Use explicit prefixes or tags for architectural claims:
   - `[Current]` / `[Shipped]`: Actively running in production.
   - `[Experimental]`: Behind a feature flag or developer toggle.
   - `[Planned]`: Roadmap items not yet implemented.
   - `[Superseded]` / `[Deprecated]`: Replaced by a newer system.
   - `[Unsafe wording]`: Claims that violate the evidence protocol.
   - `[Unknown]`: Status cannot be verified via code.
3. **Replace Unsafe Claims**: Replace absolute, unverified claims (e.g., "The system ALWAYS encrypts via X") with precise, qualified claims backed by code (e.g., "AES-GCM encryption is applied in `KeychainService.swift`").

## Document Classification
During audits, classify every existing document into one of these states:
- **KEEP**: Accurate and up to date.
- **UPDATE**: Requires minor corrections or state labels.
- **MERGE**: Contents should be absorbed into a canonical source of truth.
- **SUPERSEDE**: Replaced entirely by a new document.
- **ARCHIVE**: Moved to a historical archive folder.
- **DELETE-CANDIDATE**: Completely obsolete and misleading.
