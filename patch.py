import re

with open("OpenIntelligence/Services/Query/Enhancement/ContextualCompressionService.swift", "r") as f:
    content = f.read()

# 1. Add query property to CompressionResult
content = re.sub(
    r"struct CompressionResult: Sendable \{\n    let originalContent: String",
    "struct CompressionResult: Sendable {\n    let query: String\n    let originalContent: String",
    content
)

# 2. Update compressChunk to pass query
content = re.sub(
    r"return CompressionResult\(\n                originalContent: chunk,\n                compressedContent: compressed,\n                originalTokens: originalTokens,\n                compressedTokens: compressedTokens,\n                compressionRatio: ratio\n            \)",
    "return CompressionResult(\n                query: query,\n                originalContent: chunk,\n                compressedContent: compressed,\n                originalTokens: originalTokens,\n                compressedTokens: compressedTokens,\n                compressionRatio: ratio\n            )",
    content
)

# 3. Update passthrough method
content = re.sub(
    r"nonisolated static func passthrough\(_ content: String\) -> CompressionResult \{",
    "nonisolated static func passthrough(_ content: String, forQuery query: String = \"\") -> CompressionResult {",
    content
)

content = re.sub(
    r"return CompressionResult\(\n            originalContent: content,\n            compressedContent: content,\n            originalTokens: tokens,\n            compressedTokens: tokens,\n            compressionRatio: 1.0\n        \)",
    "return CompressionResult(\n            query: query,\n            originalContent: content,\n            compressedContent: content,\n            originalTokens: tokens,\n            compressedTokens: tokens,\n            compressionRatio: 1.0\n        )",
    content
)

# Update all calls to passthrough that pass the chunk
content = re.sub(
    r"CompressionResult\.passthrough\((.*?)\)",
    r"CompressionResult.passthrough(\1)", # Keep as is, they will use default query="" unless changed manually
    content
)

# We need to manually fix passthrough calls that have query available
content = content.replace(
    "return CompressionResult.passthrough(chunk)",
    "return CompressionResult.passthrough(chunk, forQuery: query)"
)

content = content.replace(
    "results.append(CompressionResult.passthrough(chunks[remainIdx]))",
    "results.append(CompressionResult.passthrough(chunks[remainIdx], forQuery: query))"
)

content = content.replace(
    "results.append(CompressionResult.passthrough(chunk))",
    "results.append(CompressionResult.passthrough(chunk, forQuery: query))"
)


# 4. Implement effectiveContent logic
new_effective_content = """    nonisolated var effectiveContent: String {
        if compressedContent.contains("NO_RELEVANT_CONTENT") || compressedContent.isEmpty {
            var extractedSentences = [String]()

            // UNIVERSAL FIX: Extract sentences likely to contain the needle.
            // We use simple substring matching as a fast pass before relying on LLM compression.
            let terms = query.lowercased().split(separator: " ").map { String($0) }

            // Previously took first 400 chars — a needle at char 450 was lost forever.
            // Now: score each sentence by information density (numbers, capitalized terms,
            // colons, units) and take the highest-scoring ones up to 400 chars.
            let sentences = originalContent.components(separatedBy: CharacterSet(charactersIn: ".!?\\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count >= 10 }

            if sentences.count <= 2 {
                // Very short content — return as-is
                return originalContent
            }

            // Score each sentence by information density
            let scored = sentences.map { sentence -> (String, Int) in
                var score = 0
                let lowerSentence = sentence.lowercased()

                // Query matching (highest weight)
                for term in terms {
                    if term.count > 3 && lowerSentence.contains(term) {
                        score += 5
                    }
                }

                // Numbers (specs, measurements, dates, values)
                if sentence.rangeOfCharacter(from: .decimalDigits) != nil { score += 3 }
                // Capitalized words (entities, proper nouns, acronyms)
                let capitalWords = sentence.split(separator: " ").filter { word in
                    guard let first = word.first else { return false }
                    return first.isUppercase && word.count > 1
                }
                score += min(capitalWords.count, 3)
                // Colons (definitions, key-value pairs: "Capacity: 5L")
                if sentence.contains(":") { score += 2 }
                // Technical patterns (units, codes)
                if sentence.range(of: #"[A-Z]{2,}[\\\\s-]?\\\\d+"#, options: .regularExpression) != nil { score += 2 }
                return (sentence, score)
            }
            .sorted { $0.1 > $1.1 }

            // Take top-scoring sentences up to 400 chars
            var fallback = ""
            for (sentence, _) in scored {
                if fallback.count + sentence.count + 2 > 400 { break }
                if !fallback.isEmpty { fallback += ". " }
                fallback += sentence
                extractedSentences.append(sentence)
            }

            if fallback.isEmpty {
                fallback = String(originalContent.prefix(400))
            }

            return fallback.count < originalContent.count ? fallback + "..." : fallback
        }
        return compressedContent
    }"""

# Use replace instead of regex for the big block to avoid escaping issues
old_content = content[content.find("    nonisolated var effectiveContent: String {"):content.find("    /// Returns true if compression marked this chunk as irrelevant")-5]
content = content.replace(old_content, new_effective_content)

with open("OpenIntelligence/Services/Query/Enhancement/ContextualCompressionService.swift", "w") as f:
    f.write(content)

print("Done")
