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

#if canImport(FoundationModels)
/// Structured LLM output for Image Playground concept extraction.
/// @Generable guarantees a typed [String] array — no line-splitting or regex parsing needed.
/// Constrained sampling enforces the declared schema at the token level, eliminating
/// malformed output and reducing "try another description" errors from strict guardrails.
@available(iOS 26.0, *)
@Generable
struct ImageConceptList: Sendable {
    /// Simple 1-2 word visual nouns extracted from the text.
    @Guide(description: "1-2 word visible objects or scenes from the text. Concrete nouns only — things a camera could photograph.")
    var concepts: [String]
}
#endif

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
    /// Source text for .extracted() — lets Apple's model pick the best visual interpretation
    @Published var imagePlaygroundSourceText: String?

    private init() {}

    // MARK: - Pipeline Telemetry
    /// Callback to emit ThinkingEvents for live pipeline visualization
    var onThinkingEvent: ((ThinkingEvent) -> Void)?

    /// Emit an Image Playground pipeline event
    private func emit(_ title: String, detail: String? = nil) {
        onThinkingEvent?(ThinkingEvent(kind: .imagePlayground, title: title, detail: detail))
    }

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

    // MARK: - Safe Visual Vocabulary (Whitelist)

    /// Words that Image Playground is KNOWN to accept. Every concept we send
    /// must contain at least one of these anchor words. This is the nuclear
    /// option — if a concept doesn't hit the whitelist, it gets replaced.
    private static let safeVisualWords: Set<String> = [
        // Animals
        "cat", "dog", "bird", "fish", "rabbit", "butterfly", "horse", "owl",
        "dolphin", "turtle", "fox", "bear", "deer", "penguin", "whale",
        "eagle", "parrot", "kitten", "puppy", "duck", "frog", "bee",
        "ladybug", "snail", "squirrel", "mouse", "ant", "dragonfly",
        "hummingbird", "sparrow", "robin", "swan", "goose", "lamb",
        "chick", "caterpillar", "goldfish", "crab", "starfish", "seahorse",
        "jellyfish", "octopus", "coral", "clam", "seashell", "firefly",
        // Nature
        "tree", "flower", "mountain", "ocean", "river", "forest", "garden",
        "sunset", "sunrise", "rainbow", "cloud", "rain", "snow", "leaf",
        "meadow", "hill", "valley", "lake", "waterfall", "beach", "island",
        "sky", "star", "moon", "sun", "field", "grass", "vine", "rose",
        "daisy", "tulip", "sunflower", "cactus", "palm", "pine", "oak",
        "moss", "fern", "mushroom", "acorn", "pinecone", "pebble", "stone",
        "pond", "stream", "brook", "creek", "spring", "autumn", "winter",
        "summer", "breeze", "wind", "wave", "tide", "reef", "dune", "cliff",
        "cave", "trail", "path", "boulder", "petal", "blossom", "bud",
        "seed", "root", "branch", "trunk", "bark", "nest", "hive", "web",
        // Everyday objects
        "book", "lamp", "chair", "table", "cup", "mug", "hat", "umbrella",
        "clock", "bell", "candle", "basket", "blanket", "pillow", "rug",
        "jar", "vase", "bowl", "plate", "spoon", "fork", "pot", "pan",
        "bottle", "box", "bag", "key", "lock", "door", "window", "mirror",
        "shelf", "desk", "bench", "stool", "couch", "bed", "frame",
        "curtain", "rug", "mat", "tray", "pitcher", "kettle", "teapot",
        "thermos", "lunchbox", "toolbox", "chest", "crate", "barrel",
        // School / office / science (Image Playground safe)
        "pen", "pencil", "notebook", "paper", "eraser", "ruler", "globe",
        "chalkboard", "backpack", "laptop", "keyboard", "calculator",
        "folder", "calendar", "letter", "envelope", "stamp", "map",
        "microscope", "flask", "beaker", "prism", "magnet", "scale",
        "thermometer", "chart", "graph", "diagram", "textbook", "journal",
        "scroll", "quill", "inkwell", "bookmark", "diploma", "certificate",
        "trophy", "medal", "ribbon", "badge", "sticker", "poster",
        "whiteboard", "marker", "highlighter", "binder", "clipboard",
        // Art / music
        "paintbrush", "palette", "canvas", "guitar", "piano", "violin",
        "drum", "trumpet", "microphone", "camera", "easel", "crayon",
        "sketch", "painting", "sculpture", "mosaic", "tapestry", "pottery",
        "flute", "harp", "ukulele", "tambourine", "xylophone", "harmonica",
        // Food / kitchen
        "apple", "cake", "pizza", "bread", "cookie", "pie", "cherry",
        "lemon", "orange", "banana", "grape", "strawberry", "cupcake",
        "donut", "pancake", "sandwich", "salad", "soup", "tea", "coffee",
        "chocolate", "honey", "jam", "butter", "cheese",
        "pear", "peach", "plum", "watermelon", "pineapple", "coconut",
        "muffin", "croissant", "waffle", "pretzel", "pasta", "noodle",
        // Clothing
        "shoe", "boot", "scarf", "glove", "coat", "jacket", "sweater",
        "dress", "shirt", "glasses", "crown", "ribbon", "bow",
        "mitten", "slipper", "apron", "vest", "cape", "bonnet",
        // Buildings / places
        "house", "cottage", "castle", "tower", "bridge", "cabin",
        "lighthouse", "barn", "windmill", "tent", "fountain", "gate",
        "shop", "library", "bakery", "cafe", "market", "studio",
        "church", "temple", "museum", "theater", "school", "greenhouse",
        "gazebo", "pier", "dock", "treehouse", "igloo", "pagoda",
        "classroom", "office", "workshop", "attic", "porch", "balcony",
        // Transport
        "car", "bicycle", "boat", "ship", "train", "airplane", "balloon",
        "rocket", "wagon", "bus", "truck", "scooter", "sailboat", "canoe",
        "kayak", "raft", "sled", "sleigh", "carriage", "trolley",
        // Sports / play
        "ball", "kite", "swing", "slide", "skateboard", "surfboard",
        "frisbee", "jump", "rope", "racket", "bat", "glove", "helmet",
        // Tools / misc
        "hammer", "wrench", "shovel", "lantern", "compass", "telescope",
        "magnifying", "hourglass", "typewriter", "radio", "binoculars",
        "anchor", "wheel", "rope", "flag", "trophy", "medal", "gem",
        "crystal", "feather", "shell", "fossil", "coin", "treasure",
        "puzzle", "dice", "chess", "globe", "spinning", "gyroscope",
        // People / roles (Image Playground renders people great)
        "person", "people", "man", "woman", "boy", "girl", "child",
        "children", "baby", "family", "couple", "friends", "crowd",
        "group", "team", "pair", "trio",
        "doctor", "nurse", "scientist", "researcher", "professor",
        "teacher", "student", "chef", "baker", "farmer", "artist",
        "musician", "pilot", "astronaut", "explorer", "detective",
        "firefighter", "athlete", "worker", "builder", "gardener",
        "librarian", "photographer", "writer", "singer", "dancer",
        "wizard", "fairy", "princess", "prince", "king", "queen",
        "knight", "pirate", "robot", "superhero", "cowboy", "ninja",
        // Actions / poses (safe verbs for scene descriptions)
        "reading", "writing", "walking", "sitting", "standing",
        "holding", "smiling", "thinking", "looking", "pointing",
        "running", "jumping", "playing", "cooking", "painting",
        "singing", "studying", "working", "waving", "hugging",
        "laughing", "exploring", "flying", "swimming", "climbing",
        "riding", "carrying", "building", "planting", "picking",
        // Settings / rooms
        "room", "hallway", "kitchen", "bedroom", "bathroom",
        "living", "dining", "garden", "yard", "rooftop", "basement",
        "lobby", "stage", "arena", "stadium", "courtyard",
        "lab", "laboratory", "clinic", "pharmacy", "nursery",
        "playground", "park", "zoo", "aquarium", "planetarium",
        // Descriptors (safe adjectives)
        "cozy", "warm", "bright", "colorful", "golden", "wooden", "tiny",
        "old", "vintage", "rustic", "small", "big", "tall", "round",
        "soft", "fluffy", "shiny", "fresh", "open", "little", "cheerful",
        "sunny", "misty", "peaceful", "quiet", "simple", "gentle",
        "snowy", "rainy", "starry", "moonlit", "autumn", "spring",
        "red", "blue", "green", "yellow", "purple", "pink", "white",
        "silver", "copper", "bronze", "mossy", "sandy", "dusty", "icy",
        "leafy", "blooming", "flowing", "glowing", "twinkling", "dancing",
        "floating", "hanging", "stacked", "winding", "rolling", "steaming",
        "bubbling", "sparkling", "striped", "spotted", "woven", "braided",
        "ancient", "classic", "handmade", "miniature", "giant", "thick",
        "large", "many", "several", "busy", "happy", "young", "elderly",
    ]

    /// Check if a concept is anchored by at least one known-safe visual word.
    /// This is the HARD gate — if it doesn't hit the whitelist, it's swapped out.
    private func conceptIsWhitelisted(_ concept: String) -> Bool {
        let words = concept.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return words.contains { Self.safeVisualWords.contains($0) }
    }

    /// Core text cleaning — strips formatting, validates length/safety basics.
    /// Used by both LLM and fallback concept paths.
    private func cleanConceptBase(_ raw: String) -> String? {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip list formatting
        cleaned = cleaned.replacingOccurrences(of: #"^[\d]+[\.\)]\s*"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"^[-•*]\s*"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"^[\"']|[\"']$"#, with: "", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Tight: up to 3 words, 30 chars — Image Playground likes simple concepts
        guard cleaned.count >= 2, cleaned.count <= 30 else { return nil }
        let wordCount = cleaned.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count
        guard wordCount <= 3 else { return nil }
        // At least half the chars must be letters, digits, or spaces (allows numbers like "155 people")
        guard cleaned.filter({ $0.isLetter || $0.isWhitespace || $0.isNumber }).count >= cleaned.count / 2 else { return nil }

        // No URLs, file paths, code
        if cleaned.contains("://") || cleaned.contains("\\") || cleaned.contains("{") { return nil }
        if cleaned.range(of: #"[<>{}|]"#, options: .regularExpression) != nil { return nil }

        // All concepts must pass the safety blocklist
        guard conceptIsSafe(cleaned) else { return nil }

        return cleaned.lowercased()
    }

    /// Clean an LLM-generated concept — BLOCKLIST ONLY, no whitelist.
    /// The LLM is explicitly prompted to produce safe, literal, visual concepts.
    /// Requiring whitelist kills response-specific terms ("participants", "data", etc.)
    /// which causes generic fallback pools to take over.
    private func cleanConceptFromLLM(_ raw: String) -> String? {
        return cleanConceptBase(raw)
    }

    /// Clean a fallback/pool concept — BLOCKLIST + WHITELIST.
    /// Pool concepts are pre-written so they should always hit the whitelist.
    private func cleanConcept(_ raw: String) -> String? {
        guard let cleaned = cleanConceptBase(raw) else { return nil }
        guard conceptIsWhitelisted(cleaned) else { return nil }
        return cleaned
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

    /// Compute how many concept components to request based on response complexity.
    /// Longer / richer responses get more components (2-8).
    private func conceptCountForResponse(_ text: String) -> Int {
        let charCount = text.count
        let signals = extractContentSignals(from: String(text.prefix(2000)))
        let richness = signals.entities.count + signals.nouns.count

        // Base count from character length
        let lengthBased: Int
        switch charCount {
        case ..<200:   lengthBased = 2
        case ..<500:   lengthBased = 3
        case ..<1000:  lengthBased = 4
        case ..<2000:  lengthBased = 5
        case ..<4000:  lengthBased = 6
        default:       lengthBased = 7
        }

        // Boost if the content has many distinct entities/nouns
        let richnessBoost = richness >= 10 ? 1 : 0
        return min(8, max(2, lengthBased + richnessBoost))
    }

    /// LLM-powered concept extraction — produces LITERAL scene illustrations.
    ///
    /// **Strategy**: Read the ACTUAL response text and describe what someone would
    /// SEE if they were illustrating it as a picture. The concepts should capture
    /// the MEANING of the answer — not generic themed imagery.
    ///
    /// **3-tier cascade, NEVER returns empty:**
    /// 1. LLM reads actual response → produces literal illustration (BLOCKLIST ONLY — no whitelist)
    /// 2. If LLM fails → build concepts from actual response nouns + entities
    /// 3. If nothing works → deterministic hash-based safe pool (last resort)
    func extractConceptsWithLLM(from text: String, maxConcepts: Int = 5) async -> [String] {
        // Step 1: Extract content signals for fallback
        emit("Content analysis", detail: "Scanning \(text.count) chars for illustration components")
        let truncated = String(text.prefix(1500))
        let signals = extractContentSignals(from: truncated)
        emit("NLTagger extraction", detail: "\(signals.entities.count) entities • \(signals.nouns.count) nouns • \(signals.adjectives.count) adjectives")

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                // Step 2: Ask LLM to literally illustrate the response
                let prompt = """
                You are an illustrator. Read the response below and pick \(maxConcepts + 2) \
                concrete, visible objects that capture what it is about. \
                Each object should be 1-2 words — something a camera could photograph. \
                Do NOT reuse the same theme. Focus on the specific subject matter of the response.

                RESPONSE:
                \(truncated)
                """

                emit("LLM illustrate", detail: "Requesting \(maxConcepts) illustration components via Apple Intelligence")
                // permissiveContentTransformations: We're transforming existing document text
                // into visual descriptions — CONTENT TRANSFORMATION, not new generation.
                // Default guardrails over-fire on technical vocabulary (medical terms, specimen
                // names, chemical compounds, product codes) in research/clinical/technical docs,
                // producing "try another description" errors for legitimate content.
                // The downstream blocklist (cleanConceptFromLLM) handles safety post-processing.
                let session = LanguageModelSession(
                    model: SystemLanguageModel(guardrails: .permissiveContentTransformations)
                )
                // @Generable: typed [String] array — no regex/line-splitting/trimming needed.
                // Constrained sampling enforces the declared schema at the token level.
                let response = try await session.respond(to: prompt, generating: ImageConceptList.self)

                // Step 3: Apply blocklist — trust the LLM's literal concept choices.
                var parsed = response.content.concepts
                    .compactMap { cleanConceptFromLLM($0) }  // blocklist only — trust the LLM
                    .filter { !$0.isEmpty }

                // Step 4: If LLM produced enough, use them directly
                if parsed.count >= maxConcepts {
                    var seen = Set<String>()
                    let unique = parsed.filter { seen.insert($0).inserted }
                    let final = Array(unique.prefix(maxConcepts))
                    Log.info("[ImagePlayground] LLM literal: \(final)", category: .pipeline)
                    emit("Illustration ready", detail: "LLM → \(final.joined(separator: ", "))")
                    return final
                }

                // Step 5: LLM gave some but not enough — fill from RESPONSE nouns (not generic pools)
                let responseFallback = buildResponseDerivedFallbacks(
                    signals: signals, maxConcepts: maxConcepts, excluding: Set(parsed)
                )
                parsed.append(contentsOf: responseFallback)

                // Step 5b: Still not enough? Last resort: generic safe pool
                if parsed.count < maxConcepts {
                    let contentHash = abs(text.hashValue) % 1000
                    let pool = guaranteedConceptPool(hash: contentHash, count: maxConcepts)
                    for item in pool where parsed.count < maxConcepts && !parsed.contains(item) {
                        parsed.append(item)
                    }
                }

                var seen = Set<String>()
                let unique = parsed.filter { seen.insert($0).inserted }
                let final = Array(unique.prefix(maxConcepts))
                Log.info("[ImagePlayground] LLM+response: \(final)", category: .pipeline)
                emit("Illustration ready", detail: "LLM+response → \(final.joined(separator: ", "))")
                return final
            } catch {
                Log.info("[ImagePlayground] LLM error: \(error.localizedDescription), using response fallback", category: .pipeline)
                emit("LLM fallback", detail: "Error: \(error.localizedDescription) — using response nouns")
            }
        }
        #endif

        // Tier 2: Build concepts from ACTUAL response nouns/entities (not generic pools)
        let responseFallback = buildResponseDerivedFallbacks(
            signals: signals, maxConcepts: maxConcepts, excluding: []
        )
        if responseFallback.count >= 2 {
            emit("Response-derived fallback", detail: "Nouns → \(responseFallback.joined(separator: ", "))")
            return responseFallback
        }

        // Tier 3: Absolute last resort — generic safe pool
        let contentHash = abs(text.hashValue) % 1000
        let pool = guaranteedConceptPool(hash: contentHash, count: maxConcepts)
        emit("Generic pool fallback", detail: "Pool → \(pool.joined(separator: ", "))")
        return pool
    }

    /// Build fallback concepts from the ACTUAL response content — entities, nouns, adjectives.
    /// This preserves the response's meaning instead of jumping to generic themed pools.
    /// Uses whitelist validation since these aren't LLM-curated.
    private func buildResponseDerivedFallbacks(
        signals: (entities: [String], nouns: [String], adjectives: [String]),
        maxConcepts: Int,
        excluding: Set<String>
    ) -> [String] {
        var concepts: [String] = []

        // Priority 1: Named entities (people, places, orgs) — most content-specific
        for entity in signals.entities {
            guard concepts.count < maxConcepts else { break }
            let lower = entity.lowercased()
            guard !excluding.contains(lower), !concepts.contains(lower) else { continue }
            guard conceptIsSafe(lower) else { continue }
            // Entities are proper nouns — allow them without whitelist (blocklist only)
            if lower.count >= 2, lower.count <= 30 {
                concepts.append(lower)
            }
        }

        // Priority 2: Adjective + noun pairs from actual response
        var adjIdx = 0
        for noun in signals.nouns {
            guard concepts.count < maxConcepts else { break }
            let n = noun.lowercased()
            guard !excluding.contains(n), !concepts.contains(n) else { continue }
            guard conceptIsSafe(n) else { continue }

            // Try pairing with an adjective for richer description
            if adjIdx < signals.adjectives.count {
                let adj = signals.adjectives[adjIdx].lowercased()
                let paired = "\(adj) \(n)"
                if !excluding.contains(paired), !concepts.contains(paired), conceptIsSafe(paired) {
                    concepts.append(paired)
                    adjIdx += 1
                    continue
                }
            }

            // Solo noun
            if n.count >= 3 {
                concepts.append(n)
            }
        }

        return Array(concepts.prefix(maxConcepts))
    }

    /// Build whitelist-safe scene components from NLTagger noun signals.
    /// Only includes nouns that exist in the safe visual vocabulary.
    /// Pairs with safe adjectives when available for richer concepts.
    private func buildSimpleNounFallbacks(
        nouns: [String], maxConcepts: Int, excluding: Set<String>,
        adjectives: [String] = []
    ) -> [String] {
        var concepts: [String] = []
        var adjIdx = 0

        for noun in nouns {
            guard concepts.count < maxConcepts else { break }
            let clean = noun.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard clean.count >= 3, clean.count <= 20 else { continue }
            guard !excluding.contains(clean), !concepts.contains(clean) else { continue }

            // HARD GATE: noun must be in the safe visual vocabulary
            guard Self.safeVisualWords.contains(clean) else { continue }
            guard conceptIsSafe(clean) else { continue }

            // Pair with a safe adjective when available
            if adjIdx < adjectives.count {
                let adj = adjectives[adjIdx].lowercased()
                if Self.safeVisualWords.contains(adj) {
                    let paired = "\(adj) \(clean)"
                    if !excluding.contains(paired) {
                        concepts.append(paired)
                        adjIdx += 1
                        continue
                    }
                }
            }
            concepts.append(clean)
        }

        return concepts
    }

    // MARK: - Themed Safe Pools

    /// Map a set of NLTagger nouns to the safest thematic pool.
    /// Returns a pool of universally-safe concepts tuned to the content domain.
    /// Broad keyword matching — catches domain-specific nouns the LLM response contains.
    private func themedSafePool(for nouns: [String], hash: Int) -> [String] {
        let nounSet = Set(nouns.map { $0.lowercased() })

        // Vehicle / mechanical keywords
        let automotive: Set<String> = ["car", "engine", "oil", "tire", "brake", "wheel", "vehicle",
            "motor", "transmission", "fuel", "exhaust", "battery", "garage", "drive", "road",
            "mileage", "horsepower", "torque", "cylinder", "piston", "valve", "clutch",
            "radiator", "alternator", "carburetor", "axle", "suspension", "chassis",
            "diesel", "gasoline", "hydraulic", "odometer", "rpm", "gear", "throttle"]

        // Biology / medical / life sciences (BROAD)
        let biology: Set<String> = ["diversity", "species", "bacterial", "bacteria", "microbiome",
            "gut", "gene", "genome", "dna", "rna", "protein", "cell", "cells", "tissue",
            "organism", "microbe", "flora", "fauna", "enzyme", "pathogen", "virus",
            "immune", "antibiotic", "medication", "nsaid", "patient", "clinical", "trial",
            "sample", "specimen", "coefficient", "shannon", "simpson", "otu", "abundance",
            "population", "ecology", "habitat", "biome", "phenotype", "genotype",
            "allele", "chromosome", "mutation", "evolution", "phylogenetic", "taxonomy",
            "metabolic", "metabolism", "mitochondria", "ribosome", "membrane",
            "prokaryote", "eukaryote", "fungal", "fungi", "yeast", "mold",
            "probiotic", "prebiotic", "fermentation", "cultivation", "incubation",
            "biofilm", "plasmid", "receptor", "ligand", "substrate", "catalyst",
            "diagnosis", "symptom", "disease", "disorder", "syndrome", "therapy",
            "pharmaceutical", "dosage", "prescription", "vitamin", "nutrient",
            "anatomy", "physiology", "pathology", "epidemiology", "biostatistics",
            "health", "wellness", "fitness", "nutrition", "diet", "exercise"]

        // Science / chemistry / physics
        let science: Set<String> = ["experiment", "molecule", "atom", "chemical", "reaction",
            "formula", "laboratory", "research", "hypothesis", "theory", "physics", "biology",
            "chemistry", "element", "compound", "solution", "acid", "base", "ion",
            "electron", "proton", "neutron", "photon", "quantum", "particle",
            "wavelength", "frequency", "spectrum", "velocity", "acceleration",
            "gravity", "mass", "force", "energy", "entropy", "thermodynamic",
            "equation", "constant", "variable", "measurement", "precision",
            "statistical", "correlation", "regression", "variance", "deviation",
            "probability", "distribution", "hypothesis", "significance", "analysis"]

        // Finance / business
        let finance: Set<String> = ["money", "bank", "profit", "stock", "market", "investment",
            "budget", "revenue", "portfolio", "dividend", "loan", "credit", "tax", "account",
            "interest", "inflation", "equity", "bond", "mortgage", "asset", "liability",
            "balance", "income", "expense", "salary", "wage", "pension", "insurance",
            "audit", "fiscal", "monetary", "capital", "shareholder", "stakeholder",
            "valuation", "depreciation", "amortization", "cash", "debt", "yield"]

        // Cooking / food
        let cooking: Set<String> = ["recipe", "cook", "bake", "ingredient", "oven", "flour",
            "sugar", "cream", "sauce", "grill", "simmer", "dough", "stir", "chop", "meal",
            "roast", "broth", "spice", "herb", "seasoning", "marinade", "garnish",
            "appetizer", "entree", "dessert", "cuisine", "chef", "kitchen", "pantry"]

        // Nature / outdoor
        let nature: Set<String> = ["hike", "trail", "mountain", "forest", "river", "lake",
            "wildlife", "camping", "fishing", "garden", "plant", "soil", "seed", "bloom",
            "ecosystem", "climate", "weather", "geology", "mineral", "volcano", "glacier",
            "canyon", "desert", "tundra", "savanna", "wetland", "marsh", "swamp",
            "tide", "current", "wave", "coral", "reef", "migration", "pollination"]

        // Education / academic / learning
        let education: Set<String> = ["study", "student", "teacher", "professor", "university",
            "college", "school", "lecture", "course", "curriculum", "thesis", "dissertation",
            "textbook", "journal", "paper", "article", "publication", "peer", "review",
            "chapter", "bibliography", "citation", "abstract", "methodology", "framework",
            "assessment", "evaluation", "grading", "semester", "syllabus", "academic"]

        // Technology / computing
        let technology: Set<String> = ["algorithm", "software", "hardware", "database", "server",
            "code", "program", "network", "internet", "api", "cloud", "encryption",
            "authentication", "protocol", "processor", "memory", "storage", "bandwidth",
            "latency", "throughput", "compiler", "runtime", "debug", "deploy", "pipeline",
            "machine", "learning", "neural", "model", "training", "inference", "tensor"]

        // Legal / governance
        let legal: Set<String> = ["law", "court", "judge", "attorney", "lawyer", "contract",
            "clause", "statute", "regulation", "compliance", "liability", "plaintiff",
            "defendant", "verdict", "testimony", "jurisdiction", "amendment", "constitution",
            "legislation", "ordinance", "policy", "governance", "ethics", "rights"]

        // History / humanities
        let history: Set<String> = ["century", "era", "empire", "dynasty", "civilization",
            "revolution", "ancient", "medieval", "renaissance", "colonial", "monarchy",
            "republic", "democracy", "artifact", "archaeology", "heritage", "tradition",
            "chronicle", "manuscript", "inscription", "monument", "relic", "excavation"]

        if !nounSet.isDisjoint(with: biology) {
            return ["scientist with clipboard", "group of people", "bright laboratory",
                    "microscope on desk", "notebook with chart", "glass flask",
                    "researcher reading", "bookshelf with journals", "magnifying glass", "potted plant"]
        } else if !nounSet.isDisjoint(with: automotive) {
            return ["mechanic with wrench", "car in garage", "workshop manual",
                    "toolbox on floor", "person checking car", "bright workshop",
                    "shelf with bottles", "old bicycle", "calendar on wall", "coffee mug"]
        } else if !nounSet.isDisjoint(with: science) {
            return ["scientist in lab", "microscope on desk", "open notebook", "colorful globe",
                    "chalkboard with diagram", "glass flask", "researcher thinking",
                    "bookshelf", "desk lamp glowing", "magnifying glass"]
        } else if !nounSet.isDisjoint(with: finance) {
            return ["office building", "person at laptop", "team meeting",
                    "graph on screen", "coffee cups", "city skyline",
                    "fountain pen", "stack of folders", "clock on wall", "desk plant"]
        } else if !nounSet.isDisjoint(with: cooking) {
            return ["chef in kitchen", "mixing bowl", "wooden spoon",
                    "fresh apple", "warm oven", "bread loaf",
                    "herb garden", "open cookbook", "flour jar", "checkered cloth"]
        } else if !nounSet.isDisjoint(with: nature) {
            return ["hiker on trail", "tall pine tree", "flowing river",
                    "campfire", "wooden cabin", "butterfly on flower",
                    "explorer with compass", "starry sky", "old binoculars", "wildflower meadow"]
        } else if !nounSet.isDisjoint(with: education) {
            return ["student reading book", "teacher at chalkboard", "bright classroom",
                    "desk with notebook", "globe on shelf", "apple on desk",
                    "group studying together", "bookshelf", "pencil cup", "desk lamp"]
        } else if !nounSet.isDisjoint(with: technology) {
            return ["person at laptop", "cozy desk setup", "coffee mug",
                    "bright screen glowing", "notebook open", "potted plant",
                    "headphones on desk", "bookshelf nearby", "clock on wall", "window"]
        } else if !nounSet.isDisjoint(with: legal) {
            return ["person at desk", "stack of books", "fountain pen",
                    "tall building", "leather journal", "brass scale",
                    "coffee mug", "desk lamp", "bookshelf", "clock tower"]
        } else if !nounSet.isDisjoint(with: history) {
            return ["explorer with compass", "leather journal", "ancient map",
                    "stone castle", "ship at sea", "golden hourglass",
                    "writer with quill", "old telescope", "lantern glowing", "worn book"]
        }

        // Generic fallback
        return guaranteedConceptPool(hash: hash, count: 10)
    }

    /// Guaranteed concept pool — universally safe everyday objects.
    /// Uses content hash for deterministic variety.
    private func guaranteedConceptPool(hash: Int, count: Int = 5) -> [String] {
        let pool: [String] = [
            "person reading",
            "desk with lamp",
            "magnifying glass",
            "group of friends",
            "scientist thinking",
            "person writing",
            "colorful globe",
            "golden hourglass",
            "explorer with compass",
            "warm lantern",
            "writer at typewriter",
            "photographer with camera",
            "old map",
            "clock on shelf",
            "tree in park",
            "lighthouse",
            "musician with violin",
            "ship at sunset",
            "sunflower field",
            "student with backpack",
            "coffee mug",
            "potted plant",
            "person reading book",
            "golden key",
            "child on bicycle",
        ]

        let startIdx = hash % pool.count
        var selected: [String] = []
        for i in 0..<count {
            selected.append(pool[(startIdx + i * 3) % pool.count])
        }
        return selected
    }

    /// Synchronous NLTagger-based concept extraction — public sync API.
    /// Returns simple 1-2 word noun concepts suitable for Genmoji / Image Playground.
    func extractConcepts(from text: String, maxConcepts: Int = 3) -> [String] {
        return extractConceptsWithNLTagger(from: text, maxConcepts: maxConcepts)
    }

    /// NLTagger noun extraction — safe-only concepts.
    /// Falls through to themed safe pool if NLTagger nouns aren't in whitelist.
    private func extractConceptsWithNLTagger(from text: String, maxConcepts: Int = 3) -> [String] {
        let signals = extractContentSignals(from: text)

        // Try whitelist-safe nouns first
        let concepts = buildSimpleNounFallbacks(
            nouns: signals.nouns, maxConcepts: maxConcepts, excluding: [],
            adjectives: signals.adjectives
        )

        if concepts.count >= maxConcepts {
            return concepts
        }

        // Fill remainder from themed safe pool
        var result = concepts
        let contentHash = abs(text.hashValue) % 1000
        let themed = themedSafePool(for: signals.nouns, hash: contentHash)
        for c in themed where result.count < maxConcepts && !result.contains(c) {
            result.append(c)
        }
        return Array(result.prefix(maxConcepts))
    }

    // MARK: - Interactive Sheet

    /// Present the Image Playground sheet with pre-filled concepts
    func presentPlayground(withConcepts concepts: [String], sourceText: String? = nil) {
        imagePlaygroundConcepts = concepts
        imagePlaygroundSourceText = sourceText
        showImagePlayground = true
        DSHaptics.medium()
        HardwareTelemetryState.shared.pulse(.imageProcessing, intensity: 0.8, duration: 0.3)
    }

    /// Present Image Playground from RAG response context.
    /// Dynamically scales concept count (2-8) based on response complexity.
    /// All concepts are components of ONE cohesive scene, not competing scenes.
    func presentPlaygroundFromResponse(_ response: String) {
        Task { @MainActor in
            let count = conceptCountForResponse(response)
            emit("Illustrate", detail: "Analyzing response for \(count) scene components (\(response.count) chars)")
            let concepts = await extractConceptsWithLLM(from: response, maxConcepts: count)
            Log.info("[ImagePlayground] Presenting \(concepts.count) scene components: \(concepts)", category: .pipeline)
            emit("Presenting Image Playground", detail: "\(concepts.count) components: \(concepts.joined(separator: ", "))")
            // Pass source text so the sheet can use .extracted() for bulletproof rendering
            presentPlayground(withConcepts: concepts, sourceText: String(response.prefix(500)))
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
                    concepts: buildConcepts()
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

    #if canImport(ImagePlayground)
    @available(iOS 26.0, *)
    private func buildConcepts() -> [ImagePlaygroundConcept] {
        var concepts: [ImagePlaygroundConcept] = []

        // ALL concepts are .text() with universally-safe everyday objects.
        // We do NOT use .extracted() — raw document text triggers Apple's content filter.
        for component in service.imagePlaygroundConcepts {
            concepts.append(.text(component))
        }

        // Guaranteed: if somehow empty, provide safe fallback scene
        if concepts.isEmpty {
            concepts.append(.text("open book"))
            concepts.append(.text("warm desk lamp"))
            concepts.append(.text("cozy reading nook"))
            concepts.append(.text("potted plant"))
            concepts.append(.text("coffee mug"))
        }

        return concepts
    }
    #endif
}

extension View {
    /// Attach Image Playground sheet support
    @MainActor
    func imagePlaygroundSupport() -> some View {
        modifier(ImagePlaygroundSheetModifier(service: .shared))
    }
}
