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
3. **Replace Unsafe Claims**: Replace absolute, unverified claims (e.g., "The system ALWAYS encrypts via X") with precise, qualified claims backed by code (e.g., "`KeychainStorage.setString` stores the value as a `kSecClassGenericPassword` item with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, in `OpenIntelligence/Core/Extensions/KeychainStorage.swift`"; a claim about what the app does would also have to say that nothing in the app calls it, as of 2026-09-29). 2026-09-29: this example used to read "AES-GCM encryption is applied in `KeychainService.swift`". No `KeychainService.swift` exists in any commit, and no Swift file in the app uses `AES.GCM`, so the example itself was the kind of claim this rule forbids. `[evidence_level: code_verified, confidence: exact, evidence_source: KeychainStorage.swift:9-14; git log --all -- '*KeychainService.swift' (empty); grep for AES.GCM under OpenIntelligence/ (no match)]`

## Document Classification
During audits, classify every existing document into one of these states:
- **KEEP**: Accurate and up to date.
- **UPDATE**: Requires minor corrections or state labels.
- **MERGE**: Contents should be absorbed into a canonical source of truth.
- **SUPERSEDE**: Replaced entirely by a new document.
- **ARCHIVE**: Moved to a historical archive folder.
- **DELETE-CANDIDATE**: Completely obsolete and misleading. Archive it rather than delete it: `CLAUDE.md` says "Never delete docs", so a document in this state is moved with `git mv` into `Docs/Archive/` unless the owner lifts that rule in so many words (2026-09-29; the same rule is restated under Active Constraints in `Docs/ai/STATE.md`).
