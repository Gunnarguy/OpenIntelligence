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
    /// Returns (entities, topNouns) — the raw material for LLM concept generation.
    private func extractContentSignals(from text: String) -> (entities: [String], nouns: [String]) {
        let cleaned = text
            .replacingOccurrences(of: #"#{1,6}\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\*{1,3}([^*]+?)\*{1,3}"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\[[^\]]{0,60}\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return ([], []) }

        var entities: [String] = []
        var nouns: [String] = []

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
            return entities.count < 8
        }

        // Concrete nouns — skip ultra-generic filler words
        let skip: Set<String> = [
            "information", "data", "system", "process", "method", "type", "result",
            "value", "level", "step", "point", "case", "thing", "fact", "issue",
            "content", "detail", "feature", "section", "part", "example", "item",
            "number", "time", "way", "use", "need", "order", "form", "rate",
            "state", "area", "line", "note", "text", "page", "word", "mode",
        ]

        tagger.enumerateTags(in: cleaned.startIndex..<cleaned.endIndex, unit: .word, scheme: .lexicalClass, options: opts) { tag, range in
            if tag == .noun {
                let n = String(cleaned[range]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if n.count >= 3, n.count <= 20, !skip.contains(n), !nouns.contains(n) {
                    nouns.append(n)
                }
            }
            return nouns.count < 15
        }

        return (entities, nouns)
    }

    // MARK: - LLM Concept Extraction (Content-Resonant)

    /// LLM-powered concept extraction that produces concepts SPECIFIC to the document content.
    ///
    /// **How it works:**
    /// 1. NLTagger extracts the actual entities and key nouns from the text
    /// 2. Those are fed to the LLM as "topic seeds" so it knows what the document is about
    /// 3. LLM generates visual metaphors/scenes that visually represent those specific topics
    /// 4. Blocklist filtering removes only genuinely unsafe concepts
    /// 5. Result: concepts that actually resonate with the document content
    ///
    /// A car manual gets car/road/garage scenes. A cooking recipe gets kitchen/food scenes.
    /// A financial report gets city/office/chart scenes. Every document gets DIFFERENT concepts.
    func extractConceptsWithLLM(from text: String, maxConcepts: Int = 5) async -> [String] {
        // Step 1: Extract what the document is actually about
        let truncated = String(text.prefix(2000))
        let signals = extractContentSignals(from: truncated)
        let topEntities = signals.entities.prefix(5).joined(separator: ", ")
        let topNouns = signals.nouns.prefix(8).joined(separator: ", ")

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                // Step 2: Ask LLM for content-specific visual concepts
                let topicContext = [
                    topEntities.isEmpty ? nil : "Key entities: \(topEntities)",
                    topNouns.isEmpty ? nil : "Key topics: \(topNouns)"
                ].compactMap { $0 }.joined(separator: "\n")

                let prompt = """
                You are creating visual concepts for Apple Image Playground (Genmoji/sticker generator).

                The user's document is about:
                \(topicContext.isEmpty ? String(truncated.prefix(500)) : topicContext)

                Generate 8 short visual descriptions (2-6 words each) that VISUALLY REPRESENT the specific topics above.
                Make each one a concrete, drawable scene or object that someone would instantly connect to this content.

                RULES:
                - Each concept must be a PHYSICAL scene, object, or character that can be drawn
                - Make concepts SPECIFIC to this document's topic — not generic
                - Use vivid, concrete imagery (colors, materials, settings)
                - NO abstract ideas, emotions, or technical diagrams
                - NO medical instruments, weapons, or graphic imagery
                - Keep each concept 2-6 words

                Examples of GOOD content-specific concepts:
                - For a car manual: "red sports car on highway", "engine under open hood", "mechanic with wrench"
                - For a recipe book: "steaming bowl of pasta", "chef tossing pizza dough", "herbs in rustic kitchen"
                - For a travel guide: "gondola on Venice canal", "backpacker on mountain trail", "colorful market stall"
                - For a finance report: "bull statue on Wall Street", "coins stacked on desk", "city skyline at dawn"

                Output ONLY the 8 descriptions, one per line. Nothing else.
                """

                let session = LanguageModelSession()
                let response = try await session.respond(to: prompt)
                let raw = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

                // Step 3: Parse and safety-filter (blocklist only — not whitelist)
                let concepts = raw.components(separatedBy: .newlines)
                    .compactMap { cleanConcept($0) }
                    .filter { !$0.isEmpty }

                if concepts.count >= 2 {
                    let unique = Array(NSOrderedSet(array: concepts)) as? [String] ?? concepts
                    Log.info("[ImagePlayground] LLM generated \(unique.count) content-specific concepts: \(unique.prefix(5))", category: .pipeline)
                    return Array(unique.prefix(maxConcepts))
                }

                Log.info("[ImagePlayground] LLM returned \(concepts.count) usable concepts, building content-aware fallbacks", category: .pipeline)
            } catch {
                Log.info("[ImagePlayground] LLM failed: \(error.localizedDescription), using NLTagger fallback", category: .pipeline)
            }
        }
        #endif

        // Step 4: Fallback — build concepts from NLTagger signals (no LLM needed)
        return buildContentAwareFallbacks(entities: signals.entities, nouns: signals.nouns, maxConcepts: maxConcepts)
    }

    /// Build visual concepts from NLTagger-extracted signals when LLM is unavailable.
    /// Uses templates to turn raw nouns/entities into drawable scene descriptions.
    private func buildContentAwareFallbacks(entities: [String], nouns: [String], maxConcepts: Int) -> [String] {
        var concepts: [String] = []

        // Scene templates that work with any noun
        let sceneTemplates = [
            "colorful illustration of %@",
            "%@ in bright sunshine",
            "detailed drawing of %@",
            "%@ with golden light",
            "whimsical %@ scene",
        ]

        // Entity-based concepts (most specific)
        for entity in entities.prefix(2) {
            let safe = entity.filter { $0.isLetter || $0.isWhitespace }
            guard safe.count >= 2, conceptIsSafe(safe) else { continue }
            let template = sceneTemplates[concepts.count % sceneTemplates.count]
            let concept = String(format: template, safe.lowercased())
            if concept.count <= 60 {
                concepts.append(concept)
            }
        }

        // Noun-based concepts (concrete topics)
        for noun in nouns.prefix(4) {
            guard concepts.count < maxConcepts else { break }
            guard conceptIsSafe(noun) else { continue }
            let template = sceneTemplates[concepts.count % sceneTemplates.count]
            let concept = String(format: template, noun)
            if concept.count <= 60, !concepts.contains(concept) {
                concepts.append(concept)
            }
        }

        // If still too few, add some universal but varied fallbacks
        if concepts.count < maxConcepts {
            let universalFallbacks = [
                "open book with golden pages", "compass on vintage map",
                "magnifying glass over document", "lightbulb with sparkles",
                "telescope pointing at stars", "paintbrush creating art",
                "globe with highlighted path", "scroll with flowing text",
                "desk with scattered papers", "library with tall shelves",
            ].shuffled()

            for fb in universalFallbacks where concepts.count < maxConcepts {
                if !concepts.contains(fb) { concepts.append(fb) }
            }
        }

        return Array(concepts.prefix(maxConcepts))
    }

    /// Synchronous NLTagger-based fallback for when FoundationModels is unavailable.
    /// Extracts concrete nouns and named entities, frames them as short visual phrases.
    func extractConcepts(from text: String, maxConcepts: Int = 10) -> [String] {
        return extractConceptsWithNLTagger(from: text, maxConcepts: maxConcepts)
    }

    /// NLTagger noun/entity extraction — used as fallback when LLM is unavailable
    private func extractConceptsWithNLTagger(from text: String, maxConcepts: Int = 10) -> [String] {
        // 1. Strip markdown/citation artifacts
        var cleaned = text
        cleaned = cleaned.replacingOccurrences(of: #"#{1,6}\s*"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\*{1,3}([^*]+?)\*{1,3}"#, with: "$1", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\[[^\]]{0,60}\]"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #""[^"]{0,200}""#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\"[^\"]{0,200}\""#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"(?i)(excerpt|source|confidence|document)\s*:?\s*"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else {
            return ["a colorful knowledge illustration"]
        }

        // 2. Extract named entities and concrete nouns via NLTagger
        var entities: [String] = []
        var concreteNouns: [String] = []

        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        tagger.string = cleaned
        let opts: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]

        // Named entities (people, places, orgs) → best visual anchors
        tagger.enumerateTags(in: cleaned.startIndex..<cleaned.endIndex, unit: .word, scheme: .nameType, options: opts) { tag, range in
            if let tag, [.personalName, .placeName, .organizationName].contains(tag) {
                let e = String(cleaned[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if e.count >= 2, e.count <= 30, !entities.contains(e) {
                    entities.append(e)
                }
            }
            return true
        }

        // Concrete nouns (skip abstract/technical words)
        let skipNouns: Set<String> = [
            "information", "data", "system", "process", "method", "type", "result",
            "value", "level", "step", "point", "case", "thing", "fact", "issue",
            "content", "detail", "feature", "section", "part", "example", "item",
            "number", "time", "way", "use", "need", "order", "form", "rate",
            "state", "area", "line", "note", "text", "page", "word", "mode",
            "base", "code", "name", "list", "term", "unit", "spec", "docs"
        ]

        tagger.enumerateTags(in: cleaned.startIndex..<cleaned.endIndex, unit: .word, scheme: .lexicalClass, options: opts) { tag, range in
            if tag == .noun {
                let n = String(cleaned[range]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if n.count >= 3, n.count <= 20, !skipNouns.contains(n), !concreteNouns.contains(n) {
                    concreteNouns.append(n)
                }
            }
            return true
        }

        // 3. Build SHORT visual concepts (< 40 chars each)
        var concepts: [String] = []

        // A: Top entity as a scene (e.g. "Toyota" → "a Toyota vehicle")
        if let topEntity = entities.first {
            let scene = "a scene with \(topEntity)"
            if scene.count <= 40 {
                concepts.append(scene)
            } else {
                concepts.append(String(topEntity.prefix(35)))
            }
        }

        // B: Top 2-3 concrete nouns as a visual grouping
        let topNouns = Array(concreteNouns.prefix(3))
        if topNouns.count >= 2 {
            let phrase = topNouns.joined(separator: " and ")
            let concept = phrase.count <= 38 ? phrase : topNouns.prefix(2).joined(separator: " and ")
            concepts.append(concept)
        } else if let single = topNouns.first {
            concepts.append("a detailed \(single)")
        }

        // C: If we have a second entity, add it
        if entities.count >= 2 {
            let e = entities[1]
            concepts.append(e.count <= 35 ? e : String(e.prefix(35)))
        }

        // D: Pull one more noun cluster if available
        if concreteNouns.count > 3 {
            let extras = concreteNouns.dropFirst(3).prefix(2)
            let phrase = extras.joined(separator: " and ")
            if phrase.count <= 38 && !concepts.contains(phrase) {
                concepts.append(phrase)
            }
        }

        // Fallback: always return at least one usable concept
        if concepts.isEmpty {
            // Use the first 35 chars of cleaned text as a concept
            let fallback = String(cleaned.prefix(35)).trimmingCharacters(in: .whitespacesAndNewlines)
            concepts.append(fallback.isEmpty ? "a colorful knowledge illustration" : fallback)
        }

        return Array(concepts.prefix(maxConcepts))
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
