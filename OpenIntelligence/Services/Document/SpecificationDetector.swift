//
//  SpecificationDetector.swift
//  OpenIntelligence
//
//  Detects specification blocks, definition lists, and key-value patterns in text.
//  Used to identify structured data that may be misclassified as paragraphs by OCR.
//
//  DESIGN PRINCIPLE: Domain-agnostic structure detection.
//  We detect the SHAPE of specifications (alphanumeric codes, measurements, key-value pairs)
//  NOT the content. The embedding model handles semantic matching.
//
//  Universal patterns that work across:
//  - Technical manuals (specs, tolerances, part numbers)
//  - Medical documents (dosages, lab values, drug codes)
//  - Engineering specs (tolerances, material grades, standards)
//  - Legal documents (statute references, case citations)
//  - Any technical documentation with structured data
//

import Foundation

/// Result of specification detection
struct SpecificationBlock: Sendable {
    /// Category of specification (structural type, not domain)
    let category: String

    /// Extracted value (e.g., "ISO-9001", "500mg", "A2-70")
    let value: String

    /// Original text range where found
    let range: Range<String.Index>
}

/// Detects structured specification data within plain text
/// Uses UNIVERSAL patterns based on structure, not domain-specific content
/// All methods are nonisolated for use from any actor context
enum SpecificationDetector: Sendable {

    // MARK: - Universal Pattern Definitions (Domain-Agnostic)

    /// Patterns based on STRUCTURE, not content
    /// These work across ANY domain (automotive, medical, legal, engineering)
    static let universalPatterns: [(category: String, pattern: String)] = [
        // ALPHANUMERIC CODES: 2+ uppercase letters followed by numbers/dashes
        // Matches: SAE 0W-20, API SN, ISO 9001, ICD-10, ASTM D-975, NDC 12345-678
        ("Code", #"[A-Z]{2,}[-\s]?\d+[A-Z0-9-]*"#),

        // STANDARD REFERENCES: Known standard body prefixes
        // Matches: ISO 9001, ASTM D-975, IEEE 802.11, ANSI Z87.1, EN 1090
        ("Standard", #"(?:ISO|ASTM|SAE|DIN|EN|ANSI|IEEE|IEC|BS|JIS|NF|UL)\s*[-:]?\s*\d+(?:[A-Z])?(?:[-.:]\d+)*"#),

        // MEASUREMENTS WITH UNITS: Number + unit abbreviation
        // Matches: 4.5L, 500mg, 32psi, 25Nm, 120V, 15A, 98.6°F, 37°C
        ("Measurement", #"\d+(?:[.,]\d+)?\s*(?:L|mL|ml|gal|qt|oz|fl\.?\s*oz|kg|g|mg|µg|lb|lbs|psi|bar|kPa|MPa|Pa|Nm|N·m|ft-?lb|lb-?ft|in-?lb|V|kV|mV|A|mA|W|kW|MW|HP|hp|Hz|kHz|MHz|GHz|Ω|ohm|°[CF]|deg(?:rees?)?\s*[CF]|mm|cm|m|km|in|ft|yd|mi)"#),

        // VISCOSITY/GRADE PATTERNS: Alphanumeric grade codes
        // Matches: 0W-20, 5W-30, 10W-40, 20W-50
        // OPTIMIZED: Split from old Grade pattern. The old \b[A-Z]\d+ matched ANY
        // single letter + digit: G2, E85, C3, A3 — all section refs/fuse labels.
        ("Grade", #"\d+W-\d+"#),

        // PART/MODEL NUMBERS: Alphanumeric with dash/dot delimiter
        // Matches: ABC-12345, 1688-020-122, XYZ.123.456, DOT-4
        // REQUIRES at least one digit to avoid matching plain English hyphenated words
        // like "three-quarters", "over-revving", "Long-press".
        // DESIGN: Cast a WIDE net here. Detection = RECALL.
        // The SpecificationExtractor's entity-centric SCORING handles precision.
        ("PartNumber", #"(?=[A-Z0-9.-]*\d)[A-Z0-9]{2,}[-\.][A-Z0-9]{2,}(?:[-\.][A-Z0-9]{2,})*"#),

        // PERCENTAGE VALUES: Number followed by %
        // Matches: 95%, 0.5%, 99.9%
        ("Percentage", #"\d+(?:[.,]\d+)?\s*%"#),

        // RANGE VALUES: Number-to-number patterns
        // Matches: 10-15, 100-200, 1.5-2.0
        ("Range", #"\d+(?:[.,]\d+)?\s*[-–—to]\s*\d+(?:[.,]\d+)?"#),

        // CONCENTRATION/RATIO: X:Y or X/Y patterns
        // Matches: 1:100, 50/50, 3:1
        ("Ratio", #"\d+\s*[:/]\s*\d+"#),
    ]

    /// Structural indicators of specification sections (domain-agnostic)
    /// These are words that introduce spec blocks in ANY domain
    /// Note: nonisolated(unsafe) needed because this is accessed from nonisolated static functions
    nonisolated(unsafe) static var specHeadings: [String] = [
        // Universal spec indicators
        "specification", "specifications", "specs", "spec",
        "requirement", "requirements", "required",
        "recommended", "recommendation",
        "capacity", "capacities",
        "rating", "ratings", "rated",
        "value", "values",
        "limit", "limits", "limitation",
        "tolerance", "tolerances",
        "range", "ranges",
        "type", "types",
        "grade", "grades",
        "standard", "standards",
        "parameter", "parameters",
        "characteristic", "characteristics",
        "property", "properties",
        "data", "technical data",
        "info", "information",
        // Action-oriented (what to use/do)
        "use", "using",
        "approved", "acceptable", "alternative",
        "compatible", "compatibility",
    ]

    // MARK: - Compiled Patterns (lazy initialization)

    nonisolated(unsafe) private static var compiledPatterns: [(category: String, regex: NSRegularExpression)] = {
        return universalPatterns.compactMap { category, pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                return nil
            }
            return (category, regex)
        }
    }()

    // MARK: - Public API

    /// Detect all specification values in the given text
    /// Uses universal structural patterns, not domain-specific matching
    /// - Parameter text: The text to scan
    /// - Returns: Array of detected specifications with categories and values
    nonisolated static func detectSpecifications(in text: String) -> [SpecificationBlock] {
        var results: [SpecificationBlock] = []
        var seenRanges: Set<String> = []  // Deduplicate overlapping matches

        for (category, regex) in compiledPatterns {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: range)

            for match in matches {
                if let swiftRange = Range(match.range, in: text) {
                    let value = String(text[swiftRange])
                    // Deduplicate by range string (some patterns overlap)
                    let rangeKey = "\(swiftRange.lowerBound)-\(swiftRange.upperBound)"
                    guard !seenRanges.contains(rangeKey) else { continue }
                    seenRanges.insert(rangeKey)

                    results.append(SpecificationBlock(
                        category: category,
                        value: value,
                        range: swiftRange
                    ))
                }
            }
        }

        return results
    }

    /// Check if text appears to be a specification block header
    /// Uses structural indicators, not domain-specific keywords
    /// - Parameter text: The text to check (typically a heading or first line)
    /// - Returns: True if text appears to be a spec heading
    nonisolated static func isSpecificationHeading(_ text: String) -> Bool {
        let lower = text.lowercased()
        // Check for common spec headings
        return specHeadings.contains { lower.contains($0) }
    }

    /// Convert specification blocks to key-value pairs suitable for embedding
    /// Groups related specs and creates a structured representation
    /// - Parameters:
    ///   - specs: Detected specifications
    ///   - originalText: The source text (for context extraction)
    /// - Returns: Array of (key, value) pairs
    static func toKeyValuePairs(
        _ specs: [SpecificationBlock],
        from originalText: String
    ) -> [(key: String, value: String)] {
        // Group by category
        var grouped: [String: [String]] = [:]

        for spec in specs {
            let normalizedValue = spec.value.trimmingCharacters(in: .whitespaces)
            if grouped[spec.category] == nil {
                grouped[spec.category] = []
            }
            if !grouped[spec.category, default: []].contains(normalizedValue) {
                grouped[spec.category, default: []].append(normalizedValue)
            }
        }

        // Convert to key-value pairs
        var pairs: [(key: String, value: String)] = []

        for (category, values) in grouped.sorted(by: { $0.key < $1.key }) {
            if values.count == 1 {
                pairs.append((category, values[0]))
            } else {
                // Multiple values: list them
                pairs.append((category, values.joined(separator: ", ")))
            }
        }

        return pairs
    }

    /// Create a formatted text block from specifications
    /// Suitable for embedding and retrieval
    /// - Parameters:
    ///   - specs: Detected specifications
    ///   - heading: Optional heading for the block
    /// - Returns: Formatted text representation
    static func formatForEmbedding(
        _ specs: [SpecificationBlock],
        heading: String? = nil
    ) -> String {
        guard !specs.isEmpty else { return "" }

        var lines: [String] = []

        if let heading = heading {
            lines.append("Specifications: \(heading)")
        } else {
            lines.append("Specifications:")
        }

        // Group by category
        var grouped: [String: [String]] = [:]
        for spec in specs {
            if grouped[spec.category] == nil {
                grouped[spec.category] = []
            }
            let normalized = spec.value.trimmingCharacters(in: .whitespaces)
            if !grouped[spec.category, default: []].contains(normalized) {
                grouped[spec.category, default: []].append(normalized)
            }
        }

        // Format as key-value pairs
        for (category, values) in grouped.sorted(by: { $0.key < $1.key }) {
            for value in values {
                lines.append("• \(category): \(value)")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Check if text contains enough specifications to be considered a spec block
    /// Uses CONSERVATIVE thresholds to avoid over-fragmenting prose content
    /// - Parameter text: Text to analyze
    /// - Returns: True if text appears to be a genuine specification block
    static func isSpecificationBlock(_ text: String) -> Bool {
        let specs = detectSpecifications(in: text)

        // Check for spec heading which provides context
        let hasHeading = text.split(separator: "\n").prefix(3).contains { line in
            isSpecificationHeading(String(line))
        }

        // Calculate spec density (specs per 100 words)
        let wordCount = text.split(separator: " ").count
        let specDensity = wordCount > 0 ? Double(specs.count) / Double(wordCount) * 100 : 0

        // CONSERVATIVE THRESHOLDS:
        // - With heading: 3+ specs
        // - Without heading: 5+ specs AND 5%+ density
        if hasHeading {
            return specs.count >= 3
        } else {
            return specs.count >= 5 && specDensity >= 5.0
        }
    }
}
