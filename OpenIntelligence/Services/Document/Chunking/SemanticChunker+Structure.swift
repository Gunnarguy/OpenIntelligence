//
//  SemanticChunker+Structure.swift
//  OpenIntelligence
//
//  Part of SemanticChunker, moved from SemanticChunker.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import Foundation
import NaturalLanguage
import Accelerate

nonisolated extension SemanticChunker {
    // MARK: - Table Block Detection (Atomic Preservation)

    /// A contiguous block of table data that should not be split during chunking.
    /// Tables (spec sheets, data grids, markdown tables) lose meaning when split
    /// across chunk boundaries. Detected as a pre-pass and treated as atomic units.
    struct TableBlock {
        let range: Range<String.Index>
        let lineCount: Int
    }

    /// Detect contiguous table blocks in text.
    ///
    /// Scans line-by-line for table patterns:
    /// - **Markdown tables**: Lines with 2+ `|` characters (including separator rows like `|---|---|`)
    /// - **Tab-separated data**: Lines with 2+ tab characters and non-whitespace content
    ///
    /// Requires at least 2 consecutive matching lines to form a table block.
    /// Single matching lines are ignored (likely coincidental pipe usage).
    func detectTableBlocks(_ text: String) -> [TableBlock] {
        var blocks: [TableBlock] = []
        var tableStartLine: String.Index?
        var lastTableLineEnd: String.Index?
        var consecutiveTableLines = 0

        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            // Find line end
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = String(text[lineStart..<lineEnd])

            if isTableLine(line) {
                if tableStartLine == nil {
                    tableStartLine = lineStart
                }
                // Include the newline in the range so the table block covers full lines
                lastTableLineEnd = lineEnd < text.endIndex ? text.index(after: lineEnd) : lineEnd
                consecutiveTableLines += 1
            } else {
                // End of potential table block
                if consecutiveTableLines >= 2, let start = tableStartLine, let end = lastTableLineEnd {
                    blocks.append(TableBlock(range: start..<end, lineCount: consecutiveTableLines))
                }
                tableStartLine = nil
                lastTableLineEnd = nil
                consecutiveTableLines = 0
            }

            // Move to next line
            if lineEnd < text.endIndex {
                lineStart = text.index(after: lineEnd)
            } else {
                break
            }
        }

        // Handle table at end of text
        if consecutiveTableLines >= 2, let start = tableStartLine, let end = lastTableLineEnd {
            blocks.append(TableBlock(range: start..<end, lineCount: consecutiveTableLines))
        }

        if !blocks.isEmpty {
            Log.debug("[SemanticChunker] Detected \(blocks.count) table blocks (\(blocks.map { $0.lineCount }.reduce(0, +)) total lines)", category: .ingestion)
        }
        return blocks
    }

    /// Check if a line matches table patterns (markdown pipes or tab-separated columns).
    private func isTableLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        // Markdown table: line has 2+ pipe characters
        let pipeCount = trimmed.filter { $0 == "|" }.count
        if pipeCount >= 2 { return true }

        // Markdown separator row: |---|---| or +---+---+
        if (trimmed.hasPrefix("|") || trimmed.hasPrefix("+")) &&
            trimmed.contains("-") && pipeCount >= 1 {
            return true
        }

        // Tab-separated data: 2+ tabs with actual content between them
        let tabCount = trimmed.filter { $0 == "\t" }.count
        if tabCount >= 2 {
            // Verify there's actual content (not just whitespace with tabs)
            let segments = trimmed.split(separator: "\t", omittingEmptySubsequences: false)
            let nonEmptySegments = segments.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            if nonEmptySegments.count >= 2 { return true }
        }

        return false
    }

    /// Check if a position falls within any detected table block.
    /// Returns the containing table block, or nil if the position is not inside a table.
    func tableBlockContaining(_ index: String.Index, in tableBlocks: [TableBlock]) -> TableBlock? {
        return tableBlocks.first { $0.range.contains(index) }
    }

    /// Detect section headers and boundaries with hierarchical levels.
    ///
    /// Handles 3 categories of headings:
    /// 1. **Explicit markup**: Markdown `#`, numbered `1.1`, roman numerals
    /// 2. **ALL CAPS**: `SPECIFICATIONS`, `ENGINE OIL`
    /// 3. **Title Case short lines** (PDF-critical): `Engine Oil`, `Coolant System`
    ///    These are the headings that PDFKit extracts as plain text from bold/large PDF fonts.
    ///    Without detecting these, spec tables lose their parent context entirely.
    func detectSections(_ text: String) -> [DetectedSection] {
        var sections: [DetectedSection] = []

        // Patterns with associated hierarchy levels
        // Level 1: Major sections (ALL CAPS, #, single digit like "1.")
        // Level 2: Subsections (##, "1.1", "1.1.", Title Case short lines)
        // Level 3: Sub-subsections (###, "1.1.1")
        let leveledPatterns: [(pattern: String, level: Int)] = [
            // Markdown headers - level determined by # count
            (#"^#{3}\s+(.+)$"#, 3),      // ### Sub-subsection
            (#"^#{2}\s+(.+)$"#, 2),      // ## Subsection
            (#"^#{1}\s+(.+)$"#, 1),      // # Section
            // Numbered sections - level determined by dot count
            (#"^\d+\.\d+\.\d+\.?\s+(.+)$"#, 3),  // 1.1.1 Sub-subsection
            (#"^\d+\.\d+\.?\s+(.+)$"#, 2),       // 1.1 Subsection
            (#"^\d+\.?\s+([A-Z].+)$"#, 1),       // 1. Section or 1 Section
            // Roman numerals (typically top-level)
            (#"^[IVX]+\.\s+(.+)$"#, 1),
            // ALL CAPS (typically top-level) — 4+ uppercase chars
            (#"^([A-Z][A-Z\s]{3,}):?\s*$"#, 1),
        ]

        // Common non-heading short phrases that happen to be Title Case
        // These MUST NOT be mistaken for section headings
        let titleCaseBlacklist: Set<String> = [
            "yes", "no", "n/a", "none", "see above", "see below", "total",
            "note", "notes", "warning", "caution", "important", "tip",
            "page", "figure", "table", "appendix", "index", "contents",
            "rear", "front", "left", "right", "top", "bottom", "inside",
            "outside", "upper", "lower", "other", "manual", "automatic"
        ]

        // Single-word headings that commonly appear in academic papers and technical manuals
        // as standalone lines after PDF extraction.
        let knownSingleWordHeadings: Set<String> = [
            "abstract", "background", "overview", "summary", "objective", "objectives",
            "introduction", "methods", "method", "materials", "results", "discussion",
            "conclusion", "conclusions", "findings", "references", "appendix", "appendices",
            "warning", "warnings", "caution", "cautions", "precautions", "safety",
            "specification", "specifications", "sterilization", "reprocessing", "cleaning",
            "maintenance", "operation", "operations", "troubleshooting", "service",
            "inspection", "storage", "calibration", "indications", "contraindications"
        ]

        // Multi-word headings that should override the generic short-line blacklist.
        let knownMultiWordHeadings: Set<String> = [
            "indications for use",
            "warnings and precautions",
            "materials and methods",
            "technical specifications",
            "operating instructions",
            "troubleshooting guide",
            "maintenance schedule",
            "cleaning instructions",
            "sterilization instructions",
            "reprocessing instructions",
            "high level disinfection",
            "manual high level disinfection",
            "intended use"
        ]

        let lines = text.components(separatedBy: .newlines)
        var currentIndex = text.startIndex

        func contextSupportsHeading(lineAt lineIdx: Int) -> Bool {
            let currentLine = lines[lineIdx]
            let trimmedCurrent = currentLine.trimmingCharacters(in: .whitespaces)
            let currentIndent = currentLine.prefix(while: { $0 == " " || $0 == "\t" }).count

            guard lineIdx + 1 < lines.count else { return true }

            let nextLines = lines[(lineIdx + 1)...].prefix(3)
            for nextLine in nextLines {
                let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
                guard !nextTrimmed.isEmpty else { continue }

                let nextIndent = nextLine.prefix(while: { $0 == " " || $0 == "\t" }).count
                if nextIndent > currentIndent {
                    return true
                }

                let nextHasDigits = nextTrimmed.rangeOfCharacter(from: .decimalDigits) != nil
                let nextHasColon = nextTrimmed.contains(":")
                if nextHasDigits || nextHasColon {
                    return true
                }

                if nextTrimmed.count > trimmedCurrent.count * 2 {
                    return true
                }

                let nextWords = nextTrimmed.split(separator: " ")
                let nextCapRatio = Float(nextWords.filter { $0.first?.isUppercase == true }.count) / Float(max(nextWords.count, 1))
                if nextWords.count <= 8 && nextCapRatio >= 0.6 && !nextHasDigits {
                    return true
                }

                return true
            }

            return true
        }

        for (lineIdx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                // Still advance past empty lines
                if let lineRange = text.range(of: line + "\n", range: currentIndex..<text.endIndex) {
                    currentIndex = lineRange.upperBound
                }
                continue
            }

            var matched = false

            // Pass 1: Try explicit patterns (markdown, numbered, ALL CAPS)
            for (pattern, level) in leveledPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]),
                   let _ = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
                    if let lineRange = text.range(of: line, range: currentIndex..<text.endIndex) {
                        // Clean up the title (remove # markers, normalize spacing)
                        var cleanTitle = trimmed
                        if cleanTitle.hasPrefix("#") {
                            cleanTitle = cleanTitle.drop(while: { $0 == "#" || $0 == " " }).description
                        }
                        cleanTitle = cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)

                        sections.append(DetectedSection(
                            title: cleanTitle,
                            range: lineRange,
                            level: level
                        ))
                        matched = true
                        break
                    }
                }
            }

            // Pass 2: Title Case heuristic for PDF-extracted headings
            // Catches: "Engine Oil", "Coolant System", "Differential Gear Oil", "Brake Fluid"
            // These are the sub-headings that PDFKit extracts as plain text from bold/large fonts.
            // Criteria: short line (2-8 words), most words capitalized, no trailing punctuation,
            //           not a data line (no digits/units), next line exists and is different.
            if !matched {
                let words = trimmed.split(separator: " ")
                let wordCount = words.count
                let normalizedHeading = trimmed
                    .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
                    .lowercased()

                let isKnownSingleWordHeading = wordCount == 1 && knownSingleWordHeadings.contains(normalizedHeading)
                let isKnownMultiWordHeading = knownMultiWordHeadings.contains(normalizedHeading)
                let isGenericShortHeading = wordCount >= 2 && wordCount <= 8 &&
                    (!titleCaseBlacklist.contains(normalizedHeading) || isKnownMultiWordHeading)

                if isKnownSingleWordHeading || isKnownMultiWordHeading || isGenericShortHeading {
                    // Check: most words start with uppercase (Title Case)
                    let capitalizedWords = words.filter { $0.first?.isUppercase == true }
                    let capitalRatio = Float(capitalizedWords.count) / Float(wordCount)

                    // Allow small words like "of", "and", "the" to be lowercase
                    let isTitleCase = capitalRatio >= 0.6 || isKnownSingleWordHeading || isKnownMultiWordHeading

                    // Must NOT contain digits, units, or data-like patterns
                    let hasDigits = trimmed.rangeOfCharacter(from: .decimalDigits) != nil
                    let hasDataPatterns = trimmed.contains(":") && hasDigits  // "Type: SAE 0W-20"
                    let hasUnits = trimmed.range(of: #"\b(mm|cm|in|ft|qt|gal|kg|lb|psi|kPa|°[CF])\b"#,
                                                  options: .regularExpression) != nil

                    // Must NOT end with sentence-ending punctuation (headings don't)
                    let lastChar = trimmed.last
                    let endsWithPunctuation = lastChar == "." || lastChar == "!" || lastChar == "?"
                                              || lastChar == "," || lastChar == ";"

                    // Must NOT look like a table row or key-value pair
                    let hasTabSeparation = trimmed.contains("\t")
                    let colonCount = trimmed.filter { $0 == ":" }.count
                    let isKeyValue = colonCount == 1 && hasDigits

                    if isTitleCase && !hasDigits && !hasDataPatterns && !hasUnits
                       && !endsWithPunctuation && !hasTabSeparation && !isKeyValue
                    {
                        if contextSupportsHeading(lineAt: lineIdx) {
                            if let lineRange = text.range(of: line, range: currentIndex..<text.endIndex) {
                                let inferredLevel = (isKnownSingleWordHeading || isKnownMultiWordHeading) ? 1 : 2
                                sections.append(DetectedSection(
                                    title: trimmed,
                                    range: lineRange,
                                    level: inferredLevel
                                ))
                            }
                        }
                    }
                }
            }

            // Advance index
            if let lineRange = text.range(of: line + "\n", range: currentIndex..<text.endIndex) {
                currentIndex = lineRange.upperBound
            }
        }

        return sections
    }

    /// Build hierarchical section path for a given position in text
    /// Returns path like ["Chapter 5", "5.3 Fluids", "Engine Oil"] based on preceding headers
    func buildSectionPath(
        at position: String.Index,
        sections: [DetectedSection]
    ) -> [String] {
        // Find all sections that precede this position
        let precedingSections = sections.filter { $0.range.lowerBound < position }
        guard !precedingSections.isEmpty else { return [] }

        // Build path by keeping track of current hierarchy
        // When we encounter a section, it replaces everything at its level and below
        var pathStack: [(level: Int, title: String)] = []

        for section in precedingSections {
            // Remove any sections at the same level or deeper
            pathStack.removeAll { $0.level >= section.level }
            // Add this section
            pathStack.append((section.level, section.title))
        }

        // Return just the titles in order
        return pathStack.map { $0.title }
    }

    /// Legacy wrapper for compatibility - returns flat section list
    private func detectSectionsFlat(_ text: String) -> [(title: String, range: Range<String.Index>)] {
        return detectSections(text).map { (title: $0.title, range: $0.range) }
    }

    /// Detect topic boundaries using linguistic cues
    func detectTopicBoundaries(_ text: String) -> [String.Index] {
        var boundaries: [String.Index] = []

        // Transition words that indicate topic changes
        let transitionPhrases = [
            "However,", "Moreover,", "Furthermore,", "In contrast,", "On the other hand,",
            "Additionally,", "Nevertheless,", "Consequently,", "In conclusion,", "To summarize,"
        ]

        for phrase in transitionPhrases {
            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: phrase, range: searchRange) {
                boundaries.append(range.lowerBound)
                searchRange = range.upperBound..<text.endIndex
            }
        }

        return boundaries.sorted()
    }

}
