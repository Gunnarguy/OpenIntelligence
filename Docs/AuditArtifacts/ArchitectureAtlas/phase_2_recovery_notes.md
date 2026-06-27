# Phase 2 Recovery Notes

## 1. Overview
This document logs the technical details, challenges, and solutions implemented during the Phase 2 Swift Entity Recovery pass.

## 2. Issues Discovered in Initial Runs

### The `RAGService` Brace Mismatch Anomaly
During the initial scan, the parser reported that `RAGService` was `NOT FOUND`, despite its physical file `RAGService.swift` containing the definition `class RAGService: ObservableObject {`.
Investigation revealed that the parser's character-by-character brace matching count went out of sync at line 1815 in `RAGService.swift`. The cause was a raw string literal:
```swift
pattern: #"(?:given|found|listed|shown|described|specified|provided|included|explained)\s+(?:in|under|at)\s+['"\x{201C}\x{201D}]([^'"\x{201C}\x{201D}\n]{3,80})['"\x{201C}\x{201D}]"#
```
In Swift, raw strings are enclosed in `#"` and `"#`. The regex engine of the original python scanner failed to identify this as a string literal because it lacked the standard double-quote boundaries without hash symbols. Consequently, the braces inside `\x{201C}` and `\x{201D}` were counted as actual code block braces. This unbalanced brace count caused the scanner to mark `class RAGService` (which begins at line 324 and ends near the end of the file, past line 1815) as unclosed, skipping it entirely.

### Performance Bottlenecks
The character-by-character search for braces across all 270 files took too long because of Python's execution overhead on large files (e.g. `RAGService.swift` is 17k+ lines, `DocumentProcessor.swift` is 9k+ lines). The script consumed near 100% CPU and took minutes, risking task timeout.

## 3. Engineering Solutions and Optimizations

### String and Comment Stripping Upgrades
The string stripper was upgraded to match raw strings (`#+"""..."""#+` and `#+"..."#+`) using non-greedy regex matching. This removed all string contents before brace counting, preventing raw-string braces from interfering with code analysis.

### Precomputed Brace Map (`O(N)`)
Instead of character-by-character loops inside nested regex matches, a single pre-indexing pass was implemented. It scans the stripped code to find all braces and builds a dictionary mapping every opening brace index to its matching closing brace index using a stack. Any brace lookups are now instant `O(1)` dict queries.

### Newline Offset Bisecting (`O(log L)`)
To convert character indices to line numbers efficiently, character offsets of all newlines are precomputed in a list. Translating any index to a line number is now done via binary search (`bisect`), running in `O(log L)` time instead of scanning from the start.

### Line-by-Line Variable Scanner
To prevent catastrophic regex backtracking on large strings (which occurred when scanning stripped class bodies containing hundreds of variables), the variables are now scanned line-by-line using a simpler match pattern.

These changes reduced execution time from several minutes to **under 6 seconds** for all 270 files.

## 4. Verification
All CSV files have been created and verified:
- `swift_entity_inventory.csv`: Successfully lists 1,362 entities, including `class RAGService` (line 324-16190).
- `service_inventory.csv`: Lists 133 services, showing methods and dependencies.
- `view_inventory.csv`: Lists 334 SwiftUI views, extracting their state properties.
- `viewmodel_inventory.csv`: Lists 31 view models/stores.
- `model_inventory.csv`: Lists 502 models.
- `function_inventory.csv`: Lists 3,369 functions.
- `priority_verification.txt`: Lists all 25 priority symbols as successfully resolved.
