//
//  ImagePlaygroundService.swift
//  OpenIntelligence
//
//  Image Playground integration for generating concept illustrations
//  from document content. Uses Apple's on-device image generation
//  to create visual representations of RAG query results.
//

import Combine
import Foundation
import NaturalLanguage
import SwiftUI

#if canImport(ImagePlayground)
import ImagePlayground
#endif

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Configuration for image generation from document context
struct ImageGenerationRequest: Sendable {
    let prompt: String
    let sourceText: String?         // Document context used to derive the prompt
    let style: ImageGenerationStyle
    let containerId: UUID?

    enum ImageGenerationStyle: String, Sendable {
        case illustration = "illustration"
        case conceptDiagram = "concept"
        case summary = "summary"
    }
}

/// Result of an image generation request
struct ImageGenerationResult: Sendable {
    let imageURL: URL?
    let prompt: String
    let wasGenerated: Bool
    let error: String?
}

/// Service for generating images using Apple Image Playground
/// Provides interactive (imagePlaygroundSheet) generation from document content
@MainActor
final class ImagePlaygroundService: ObservableObject {
    static let shared = ImagePlaygroundService()

    @Published var isGenerating = false
    @Published var lastGeneratedImageURL: URL?

    // Image Playground sheet state (driven from UI)
    @Published var showImagePlayground = false
    @Published var imagePlaygroundConcepts: [String] = []

    private init() {}

    // MARK: - Availability

    /// Check if Image Playground is available on this device
    var isAvailable: Bool {
        #if canImport(ImagePlayground)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Document Context → Image Concepts

    // MARK: - Content-Resonant Concept Generation
    //
    // Strategy: Extract REAL topics/entities from the document, then ask the LLM
    // to create visual scenes that specifically represent THOSE topics.
    // Use a blocklist (not whitelist) — block only genuinely unsafe words,
    // and let content-specific concepts through.

    // MARK: - Safety Blocklist (Narrow)

    /// Words that Image Playground will reject or that are inappropriate.
    /// We use a NARROW blocklist instead of a whitelist — this lets content-specific
    /// concepts through while blocking only genuinely problematic terms.
    private static let blockedWords: Set<String> = [
        // Violence / weapons
        "gun", "guns", "rifle", "pistol", "weapon", "weapons", "sword", "knife",
        "bomb", "explosive", "grenade", "missile", "ammunition", "ammo", "bullet",
        "bullets", "shooting", "shot", "kill", "killing", "murder", "stab",
        "attack", "assault", "combat", "warfare", "war", "blood", "bloody",
        "wound", "gore", "torture", "execute", "execution", "decapitate",
        // NSFW / sexual
        "naked", "nude", "nudity", "sex", "sexual", "porn", "pornography",
        "erotic", "lingerie", "fetish", "orgasm", "genital", "genitals",
        "breasts", "penis", "vagina", "intercourse", "masturbat",
        // Drugs (recreational) / substance abuse
        "cocaine", "heroin", "meth", "methamphetamine", "marijuana", "weed",
        "cannabis", "lsd", "ecstasy", "mdma", "fentanyl", "opium", "opioid",
        "overdose", "druggie", "junkie", "crack", "ketamine", "psychedelic",
        // Hate / discrimination
        "nazi", "hitler", "holocaust", "racist", "racism", "bigot", "bigotry",
        "supremacist", "supremacy", "genocide", "ethnic", "slur",
        // Self-harm
        "suicide", "suicidal", "selfharm", "cutting", "anorexia", "bulimia",
        // Medical (Image Playground rejects these)
        "surgery", "surgical", "scalpel", "syringe", "injection", "needle",
        "tumor", "tumour", "cancer", "autopsy", "corpse", "cadaver",
        "dissection", "amputation", "hemorrhage", "laceration",
        // Other rejected by Image Playground
        "death", "dead", "dying", "funeral", "coffin", "grave", "cemetery",
        "demon", "devil", "satan", "hell", "zombie", "skeleton", "skull",
        "horror", "terrifying", "nightmare", "scary", "creepy",
        "prison", "jail", "inmate", "criminal", "arrest",
    ]

    /// Quick check: does this concept contain any blocked words?
    private func conceptIsSafe(_ concept: String) -> Bool {
        let lower = concept.lowercased()
        let words = Set(lower.components(separatedBy: .alphanumerics.inverted).filter { !$0.isEmpty })
        return words.isDisjoint(with: Self.blockedWords)
    }

    /// Clean and validate a single concept string for Image Playground.
    /// Returns nil only if the concept is unsafe, empty, or too long.
    private func cleanConcept(_ raw: String) -> String? {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip list formatting
        cleaned = cleaned.replacingOccurrences(of: #"^[\d]+[\.\)]\s*"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"^[-•*]\s*"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"^[\"']|[\"']$"#, with: "", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Basic sanity
        guard cleaned.count >= 3, cleaned.count <= 60 else { return nil }
        guard cleaned.filter({ $0.isLetter || $0.isWhitespace }).count >= cleaned.count / 2 else { return nil }

        // No URLs, file paths, code
        if cleaned.contains("://") || cleaned.contains("\\") || cleaned.contains("{") { return nil }
        if cleaned.range(of: #"[<>{}|]"#, options: .regularExpression) != nil { return nil }

        // Safety check
        guard conceptIsSafe(cleaned) else { return nil }

        return cleaned.lowercased()
    }

    // MARK: - Content Analysis (NLTagger)

    /// Extract the most distinctive, concrete topics from document text.
    /// Returns (entities, topNouns, adjectives) — the raw material for concept generation.
    private func extractContentSignals(from text: String) -> (entities: [String], nouns: [String], adjectives: [String]) {
        let cleaned = text
            .replacingOccurrences(of: #"#{1,6}\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\*{1,3}([^*]+?)\*{1,3}"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\[[^\]]{0,60}\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return ([], [], []) }

        var entities: [String] = []
        var nouns: [String] = []
        var adjectives: [String] = []

        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        tagger.string = cleaned
        let opts: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]

        // Named entities — places, organizations, people
        tagger.enumerateTags(in: cleaned.startIndex..<cleaned.endIndex, unit: .word, scheme: .nameType, options: opts) { tag, range in
            if let tag, [.personalName, .placeName, .organizationName].contains(tag) {
                let e = String(cleaned[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if e.count >= 2, e.count <= 25, !entities.contains(e) {
                    entities.append(e)
                }
            }
            return entities.count < 10
        }

        // Concrete nouns and adjectives — skip ultra-generic filler words
        let skip: Set<String> = [
            "information", "data", "system", "process", "method", "type", "result",
            "value", "level", "step", "point", "case", "thing", "fact", "issue",
            "content", "detail", "feature", "section", "part", "example", "item",
            "number", "time", "way", "use", "need", "order", "form", "rate",
            "state", "area", "line", "note", "text", "page", "word", "mode",
            "ability", "approach", "aspect", "basis", "category", "concept",
        ]

        tagger.enumerateTags(in: cleaned.startIndex..<cleaned.endIndex, unit: .word, scheme: .lexicalClass, options: opts) { tag, range in
            if tag == .noun {
                let n = String(cleaned[range]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if n.count >= 3, n.count <= 20, !skip.contains(n), !nouns.contains(n) {
                    nouns.append(n)
                }
            } else if tag == .adjective {
                let a = String(cleaned[range]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if a.count >= 3, a.count <= 15, !adjectives.contains(a) {
                    adjectives.append(a)
                }
            }
            return nouns.count < 20 && adjectives.count < 10
        }

        return (entities, nouns, adjectives)
    }

    // MARK: - LLM Concept Extraction (Content-Resonant)

    /// LLM-powered concept extraction that produces concepts SPECIFIC to the document content.
    ///
    /// **Reliability strategy — 3-tier cascade, NEVER returns empty:**
    /// 1. LLM generates content-specific visual scenes (best quality)
    /// 2. If LLM fails → NLTagger builds concepts from extracted entities + nouns + adjectives
    /// 3. If NLTagger finds nothing → deterministic hash-based selection from curated concept pool
    ///
    /// Each tier guarantees `maxConcepts` results. Every call produces unique, valid concepts.
    func extractConceptsWithLLM(from text: String, maxConcepts: Int = 5) async -> [String] {
        // Step 1: Extract what the document is actually about
        let truncated = String(text.prefix(2500))
        let signals = extractContentSignals(from: truncated)
        let topEntities = signals.entities.prefix(5).joined(separator: ", ")
        let topNouns = signals.nouns.prefix(10).joined(separator: ", ")
        let topAdj = signals.adjectives.prefix(5).joined(separator: ", ")

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                // Step 2: Ask LLM for content-specific visual concepts
                let topicParts = [
                    topEntities.isEmpty ? nil : "Named entities: \(topEntities)",
                    topNouns.isEmpty ? nil : "Key topics: \(topNouns)",
                    topAdj.isEmpty ? nil : "Descriptors: \(topAdj)"
                ].compactMap { $0 }.joined(separator: "\n")

                let topicContext = topicParts.isEmpty ? String(truncated.prefix(600)) : topicParts

                // Use a unique seed from the text content to encourage variety
                let contentHash = abs(text.hashValue) % 1000

                let prompt = """
                Create \(maxConcepts + 3) short visual descriptions for Apple Image Playground.

                Document topics:
                \(topicContext)

                Seed: \(contentHash)

                RULES (follow exactly):
                - Each description: 2-5 words, a PHYSICAL object or scene
                - Must be something an artist can DRAW — no abstractions
                - Make each one DIFFERENT from the others
                - Relate each one to the document topics above
                - NO weapons, medical tools, violence, nudity, death
                - NO emotions, feelings, or abstract concepts
                - GOOD examples: "red bicycle on cobblestone", "steaming coffee mug", "lighthouse at sunset"
                - BAD examples: "knowledge concept", "data flow", "the feeling of discovery"

                Output ONLY the descriptions, one per line, no numbering or bullets.
                """

                let session = LanguageModelSession()
                let response = try await session.respond(to: prompt)
                let raw = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

                // Step 3: Parse and safety-filter (blocklist only)
                let concepts = raw.components(separatedBy: .newlines)
                    .compactMap { cleanConcept($0) }
                    .filter { !$0.isEmpty }

                if concepts.count >= maxConcepts {
                    // Deduplicate while preserving order
                    var seen = Set<String>()
                    let unique = concepts.filter { seen.insert($0).inserted }
                    Log.info("[ImagePlayground] LLM generated \(unique.count) concepts: \(unique.prefix(5))", category: .pipeline)
                    return Array(unique.prefix(maxConcepts))
                }

                // LLM gave us some but not enough — supplement with NLTagger concepts
                if !concepts.isEmpty {
                    let remaining = maxConcepts - concepts.count
                    let supplement = buildContentAwareFallbacks(
                        entities: signals.entities, nouns: signals.nouns,
                        adjectives: signals.adjectives, contentHash: contentHash,
                        maxConcepts: remaining, excluding: Set(concepts)
                    )
                    let combined = concepts + supplement
                    Log.info("[ImagePlayground] LLM+NLTagger hybrid: \(combined.count) concepts", category: .pipeline)
                    return Array(combined.prefix(maxConcepts))
                }

                Log.info("[ImagePlayground] LLM returned 0 usable concepts, using NLTagger fallback", category: .pipeline)
            } catch {
                Log.info("[ImagePlayground] LLM error: \(error.localizedDescription), using NLTagger fallback", category: .pipeline)
            }
        }
        #endif

        // Tier 2: NLTagger-based concepts (no LLM needed)
        let contentHash = abs(text.hashValue) % 1000
        let result = buildContentAwareFallbacks(
            entities: signals.entities, nouns: signals.nouns,
            adjectives: signals.adjectives, contentHash: contentHash,
            maxConcepts: maxConcepts, excluding: []
        )

        // Tier 3: If NLTagger also found nothing, guaranteed pool selection
        if result.count < maxConcepts {
            let pool = guaranteedConceptPool(hash: contentHash)
            var combined = result
            for c in pool where combined.count < maxConcepts && !combined.contains(c) {
                combined.append(c)
            }
            return combined
        }

        return result
    }

    /// Build visual concepts from NLTagger-extracted signals when LLM is unavailable.
    /// Combines adjectives + nouns into concrete, drawable scene descriptions.
    /// Uses content hash for deterministic but varied template selection.
    private func buildContentAwareFallbacks(
        entities: [String], nouns: [String], adjectives: [String],
        contentHash: Int, maxConcepts: Int, excluding: Set<String>
    ) -> [String] {
        var concepts: [String] = []

        // Adjective+noun combos produce vivid, drawable concepts
        // e.g. "golden bridge", "towering mountain", "rustic kitchen"
        let visualAdjectives = adjectives.isEmpty
            ? ["golden", "colorful", "vintage", "glowing", "crystal"]
            : adjectives

        // Scene templates — each produces a concrete, drawable image
        let templates: [(String) -> String] = [
            { "\($0) in warm sunlight" },
            { "\($0) on a wooden table" },
            { "\($0) surrounded by flowers" },
            { "watercolor painting of \($0)" },
            { "\($0) with morning dew" },
            { "cozy scene with \($0)" },
            { "\($0) under starry sky" },
            { "miniature \($0) on a shelf" },
            { "\($0) in a glass jar" },
            { "\($0) floating on water" },
        ]

        // Pick a starting template index based on content hash for variety
        let templateOffset = contentHash % templates.count

        // A: Entity-based concepts (most specific to the document)
        for (i, entity) in entities.prefix(3).enumerated() {
            guard concepts.count < maxConcepts else { break }
            let safe = entity.filter { $0.isLetter || $0.isWhitespace || $0.isNumber }
            guard safe.count >= 2, conceptIsSafe(safe) else { continue }

            // Combine with an adjective if available
            let adj = visualAdjectives[i % visualAdjectives.count]
            let concept = "\(adj) \(safe.lowercased())"
            if concept.count <= 50, !excluding.contains(concept), !concepts.contains(concept) {
                concepts.append(concept)
            }
        }

        // B: Noun-based concepts with templates for variety
        for (i, noun) in nouns.prefix(8).enumerated() {
            guard concepts.count < maxConcepts else { break }
            guard conceptIsSafe(noun) else { continue }

            let templateIdx = (templateOffset + i) % templates.count
            let concept = templates[templateIdx](noun)
            if concept.count <= 55, !excluding.contains(concept), !concepts.contains(concept) {
                concepts.append(concept)
            }
        }

        // C: Adjective+noun pairings for extra variety
        if concepts.count < maxConcepts && nouns.count >= 2 {
            for i in 0..<min(3, nouns.count) {
                guard concepts.count < maxConcepts else { break }
                let adj = visualAdjectives[(contentHash + i) % visualAdjectives.count]
                let noun = nouns[(contentHash + i) % nouns.count]
                guard conceptIsSafe(noun) else { continue }
                let concept = "\(adj) \(noun)"
                if concept.count <= 40, !excluding.contains(concept), !concepts.contains(concept) {
                    concepts.append(concept)
                }
            }
        }

        return Array(concepts.prefix(maxConcepts))
    }

    /// Guaranteed concept pool — always returns at least `count` valid concepts.
    /// Uses content hash for deterministic variety so the same text gets the same
    /// (but still visually interesting) concepts every time.
    private func guaranteedConceptPool(hash: Int, count: Int = 8) -> [String] {
        let pool: [String] = [
            "open book with golden pages",
            "compass on vintage map",
            "magnifying glass over parchment",
            "lightbulb glowing warmly",
            "telescope under night sky",
            "paintbrush with rainbow colors",
            "globe with paper airplanes",
            "hourglass with golden sand",
            "quill pen and inkwell",
            "crystal ball on velvet",
            "lantern in foggy garden",
            "typewriter with fresh paper",
            "treasure chest with gems",
            "hot air balloon over hills",
            "pocket watch on oak desk",
            "stained glass window",
            "windmill in tulip field",
            "bonsai tree with blossoms",
            "violin on silk cloth",
            "lighthouse beam at dusk",
            "old camera with photos",
            "music box with dancer",
            "sundial in rose garden",
            "sailing ship on calm sea",
        ]

        // Deterministic shuffle based on content hash
        let startIdx = hash % pool.count
        var selected: [String] = []
        for i in 0..<count {
            selected.append(pool[(startIdx + i * 3) % pool.count])
        }
        return selected
    }

    /// Synchronous NLTagger-based concept extraction — used as the public sync API
    /// and as the fallback when FoundationModels is unavailable.
    /// Always returns at least `maxConcepts` results.
    func extractConcepts(from text: String, maxConcepts: Int = 10) -> [String] {
        return extractConceptsWithNLTagger(from: text, maxConcepts: maxConcepts)
    }

    /// NLTagger noun/entity extraction with guaranteed results.
    /// Uses the same 3-tier strategy as the async version.
    private func extractConceptsWithNLTagger(from text: String, maxConcepts: Int = 10) -> [String] {
        let signals = extractContentSignals(from: text)
        let contentHash = abs(text.hashValue) % 1000

        let concepts = buildContentAwareFallbacks(
            entities: signals.entities, nouns: signals.nouns,
            adjectives: signals.adjectives, contentHash: contentHash,
            maxConcepts: maxConcepts, excluding: []
        )

        // Guarantee we always return enough concepts
        if concepts.count >= maxConcepts {
            return concepts
        }

        var result = concepts
        let pool = guaranteedConceptPool(hash: contentHash, count: maxConcepts)
        for c in pool where result.count < maxConcepts && !result.contains(c) {
            result.append(c)
        }
        return Array(result.prefix(maxConcepts))
    }

    // MARK: - Interactive Sheet

    /// Present the Image Playground sheet with pre-filled concepts
    func presentPlayground(withConcepts concepts: [String]) {
        imagePlaygroundConcepts = concepts
        showImagePlayground = true
        DSHaptics.medium()
        HardwareTelemetryState.shared.pulse(.imageProcessing, intensity: 0.8, duration: 0.3)
    }

    /// Present Image Playground from RAG response context.
    /// Uses the LLM to translate domain-specific content into safe visual concepts.
    func presentPlaygroundFromResponse(_ response: String) {
        Task { @MainActor in
            let concepts = await extractConceptsWithLLM(from: response)
            Log.info("[ImagePlayground] Presenting with concepts: \(concepts)", category: .pipeline)
            presentPlayground(withConcepts: concepts)
        }
    }

    /// Handle the result from Image Playground sheet
    func handlePlaygroundResult(_ url: URL) {
        lastGeneratedImageURL = url
        DSHaptics.success()
        HardwareTelemetryState.shared.reportGPUCompute(operation: .imageProcessing)
        Log.info("[ImagePlayground] User created image via sheet", category: .initialization)
    }

    /// Generate an image from a request (uses interactive sheet internally)
    /// Returns a result indicating the sheet was presented for user interaction
    func generateImage(from request: ImageGenerationRequest) async -> ImageGenerationResult {
        let concepts = await extractConceptsWithLLM(from: request.prompt)
        presentPlayground(withConcepts: concepts)
        return ImageGenerationResult(
            imageURL: nil,
            prompt: request.prompt,
            wasGenerated: false,
            error: nil
        )
    }
}

// MARK: - SwiftUI Image Playground Integration

/// View modifier that adds Image Playground sheet support
struct ImagePlaygroundSheetModifier: ViewModifier {
    @ObservedObject var service: ImagePlaygroundService

    func body(content: Content) -> some View {
        #if canImport(ImagePlayground)
        if #available(iOS 26.0, *) {
            content
                .imagePlaygroundSheet(
                    isPresented: $service.showImagePlayground,
                    concepts: service.imagePlaygroundConcepts.map { .text($0) }
                ) { url in
                    service.handlePlaygroundResult(url)
                }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    /// Attach Image Playground sheet support
    @MainActor
    func imagePlaygroundSupport() -> some View {
        modifier(ImagePlaygroundSheetModifier(service: .shared))
    }
}
