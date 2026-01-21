//
//  LibraryIconSuggestionService.swift
//  OpenIntelligence
//
//  Analyzes library content to suggest contextually relevant SF Symbols.
//  Uses document names, file types, and content keywords to infer domain.
//

import Foundation

/// Suggests SF Symbols based on library content analysis
enum LibraryIconSuggestionService {
    // MARK: - Domain Detection

    enum ContentDomain: String, CaseIterable {
        case medical
        case legal
        case financial
        case technical
        case automotive
        case education
        case science
        case cooking
        case travel
        case fitness
        case music
        case photography
        case gaming
        case nature
        case business
        case engineering
        case aviation
        case maritime
        case military
        case fashion
        case art
        case architecture
        case agriculture
        case pets
        case general

        /// Keywords that indicate this domain
        var keywords: [String] {
            switch self {
            case .medical:
                return ["medical", "health", "patient", "diagnosis", "treatment", "surgery", "hospital",
                        "doctor", "nurse", "medication", "prescription", "clinical", "therapy", "disease",
                        "symptom", "ifu", "reprocessing", "sterilization", "disinfect", "endoscope",
                        "surgical", "implant", "prosthetic", "anatomy", "pharma", "drug", "dosage"]
            case .legal:
                return ["legal", "law", "contract", "agreement", "court", "attorney", "lawyer",
                        "litigation", "plaintiff", "defendant", "statute", "regulation", "compliance",
                        "liability", "tort", "patent", "trademark", "copyright", "intellectual property"]
            case .financial:
                return ["financial", "finance", "investment", "stock", "bond", "portfolio", "dividend",
                        "interest", "loan", "mortgage", "credit", "debit", "banking", "tax", "audit",
                        "accounting", "revenue", "expense", "profit", "loss", "budget", "forecast"]
            case .technical:
                return ["technical", "software", "hardware", "programming", "code", "api", "database",
                        "server", "network", "cloud", "deployment", "docker", "kubernetes", "git",
                        "algorithm", "debug", "compile", "runtime", "framework", "library", "sdk"]
            case .automotive:
                return ["car", "vehicle", "automotive", "engine", "transmission", "brake", "tire",
                        "suspension", "steering", "fuel", "oil", "maintenance", "repair", "model",
                        "sedan", "suv", "truck", "sportage", "toyota", "honda", "ford", "bmw", "audi"]
            case .education:
                return ["education", "school", "university", "college", "course", "curriculum", "student",
                        "teacher", "professor", "lecture", "exam", "grade", "homework", "assignment",
                        "textbook", "syllabus", "semester", "degree", "diploma", "certification"]
            case .science:
                return ["science", "research", "experiment", "hypothesis", "theory", "laboratory", "data",
                        "analysis", "study", "publication", "peer review", "methodology", "sample",
                        "control", "variable", "observation", "conclusion", "physics", "chemistry", "biology"]
            case .cooking:
                return ["recipe", "cooking", "ingredient", "cuisine", "meal", "dish", "kitchen",
                        "bake", "roast", "fry", "grill", "simmer", "chef", "restaurant", "menu",
                        "flavor", "seasoning", "spice", "herb", "nutrition", "calorie", "serving"]
            case .travel:
                return ["travel", "trip", "vacation", "destination", "hotel", "flight", "airport",
                        "passport", "visa", "itinerary", "tour", "guide", "landmark", "attraction",
                        "beach", "mountain", "city", "country", "sightseeing", "adventure"]
            case .fitness:
                return ["fitness", "exercise", "workout", "gym", "training", "muscle", "cardio",
                        "strength", "endurance", "flexibility", "yoga", "pilates", "running", "cycling",
                        "swimming", "weight", "repetition", "set", "routine", "personal trainer"]
            case .music:
                return ["music", "song", "album", "artist", "band", "concert", "instrument", "guitar",
                        "piano", "drums", "vocal", "melody", "rhythm", "chord", "note", "composition",
                        "producer", "studio", "recording", "playlist", "genre", "classical", "jazz"]
            case .photography:
                return ["photography", "photo", "camera", "lens", "exposure", "aperture", "shutter",
                        "iso", "lighting", "composition", "portrait", "landscape", "macro", "editing",
                        "lightroom", "photoshop", "raw", "jpeg", "resolution", "pixel"]
            case .gaming:
                return ["game", "gaming", "player", "level", "score", "quest", "character", "weapon",
                        "inventory", "multiplayer", "online", "console", "pc", "controller", "strategy",
                        "rpg", "fps", "mmorpg", "esports", "streaming", "twitch"]
            case .nature:
                return ["nature", "wildlife", "animal", "plant", "tree", "flower", "forest", "ocean",
                        "river", "lake", "mountain", "desert", "climate", "weather", "ecosystem",
                        "conservation", "endangered", "habitat", "species", "biodiversity"]
            case .business:
                return ["business", "company", "corporation", "startup", "entrepreneur", "ceo", "manager",
                        "employee", "meeting", "presentation", "proposal", "strategy", "marketing",
                        "sales", "customer", "client", "partnership", "acquisition", "merger"]
            case .engineering:
                return ["engineering", "engineer", "design", "blueprint", "cad", "specification",
                        "tolerance", "material", "structure", "load", "stress", "thermal", "electrical",
                        "mechanical", "civil", "aerospace", "manufacturing", "prototype", "testing"]
            case .aviation:
                return ["aviation", "aircraft", "airplane", "pilot", "flight", "cockpit", "runway",
                        "takeoff", "landing", "altitude", "airspace", "navigation", "atc", "faa",
                        "boeing", "airbus", "helicopter", "drone", "aerospace"]
            case .maritime:
                return ["maritime", "ship", "boat", "vessel", "port", "harbor", "cargo", "container",
                        "captain", "crew", "navigation", "anchor", "dock", "sailing", "yacht",
                        "cruise", "ferry", "submarine", "navy", "coast guard"]
            case .military:
                return ["military", "army", "navy", "air force", "marine", "soldier", "officer",
                        "mission", "operation", "strategy", "tactics", "weapon", "defense", "security",
                        "intelligence", "reconnaissance", "deployment", "veteran", "combat"]
            case .fashion:
                return ["fashion", "clothing", "apparel", "designer", "collection", "runway", "model",
                        "fabric", "textile", "pattern", "style", "trend", "accessory", "jewelry",
                        "shoes", "handbag", "boutique", "couture", "ready-to-wear"]
            case .art:
                return ["art", "artist", "painting", "sculpture", "gallery", "museum", "exhibition",
                        "canvas", "brush", "color", "palette", "portrait", "abstract", "contemporary",
                        "modern", "impressionist", "renaissance", "masterpiece", "collection"]
            case .architecture:
                return ["architecture", "architect", "building", "structure", "design", "floor plan",
                        "elevation", "facade", "interior", "exterior", "construction", "renovation",
                        "blueprint", "zoning", "permit", "residential", "commercial", "sustainable"]
            case .agriculture:
                return ["agriculture", "farm", "crop", "harvest", "soil", "irrigation", "fertilizer",
                        "pesticide", "livestock", "cattle", "poultry", "dairy", "organic", "sustainable",
                        "tractor", "seed", "grain", "vegetable", "fruit", "orchard"]
            case .pets:
                return ["pet", "dog", "cat", "puppy", "kitten", "veterinary", "vet", "breed", "adoption",
                        "shelter", "grooming", "training", "leash", "collar", "food", "treat", "toy",
                        "aquarium", "fish", "bird", "hamster", "rabbit"]
            case .general:
                return []
            }
        }

        /// Suggested SF Symbols for this domain (in order of preference)
        var suggestedIcons: [String] {
            switch self {
            case .medical:
                return ["cross.case.fill", "stethoscope", "heart.text.square.fill", "pills.fill",
                        "syringe.fill", "bandage.fill", "waveform.path.ecg", "medical.thermometer.fill"]
            case .legal:
                return ["scale.3d", "building.columns.fill", "text.book.closed.fill", "doc.text.fill",
                        "signature", "checkmark.seal.fill", "hammer.fill", "briefcase.fill"]
            case .financial:
                return ["chart.line.uptrend.xyaxis", "dollarsign.circle.fill", "banknote.fill",
                        "creditcard.fill", "chart.pie.fill", "building.2.fill", "percent"]
            case .technical:
                return ["terminal.fill", "chevron.left.forwardslash.chevron.right", "cpu.fill",
                        "server.rack", "externaldrive.connected.to.line.below.fill", "gear.badge.checkmark"]
            case .automotive:
                return ["car.fill", "car.side.fill", "engine.combustion.fill", "fuelpump.fill",
                        "wrench.and.screwdriver.fill", "gauge.with.dots.needle.67percent"]
            case .education:
                return ["graduationcap.fill", "book.fill", "text.book.closed.fill", "pencil.and.ruler.fill",
                        "backpack.fill", "studentdesk", "person.crop.rectangle.stack.fill"]
            case .science:
                return ["atom", "testtube.2", "flask.fill", "microscope", "function", "waveform",
                        "chart.xyaxis.line", "brain.head.profile"]
            case .cooking:
                return ["frying.pan.fill", "fork.knife", "flame.fill", "birthday.cake.fill",
                        "carrot.fill", "cup.and.saucer.fill", "takeoutbag.and.cup.and.straw.fill"]
            case .travel:
                return ["airplane", "globe.americas.fill", "map.fill", "suitcase.fill", "tent.fill",
                        "figure.hiking", "camera.fill", "binoculars.fill"]
            case .fitness:
                return ["figure.run", "dumbbell.fill", "heart.circle.fill", "figure.strengthtraining.traditional",
                        "figure.yoga", "figure.cooldown", "sportscourt.fill"]
            case .music:
                return ["music.note.list", "guitars.fill", "pianokeys", "music.mic", "waveform.and.mic",
                        "headphones", "hifispeaker.2.fill", "music.quarternote.3"]
            case .photography:
                return ["camera.fill", "photo.stack.fill", "camera.aperture", "photo.artframe",
                        "camera.filters", "sun.max.fill", "sparkles.rectangle.stack.fill"]
            case .gaming:
                return ["gamecontroller.fill", "dice.fill", "trophy.fill", "flag.checkered",
                        "puzzlepiece.extension.fill", "target", "bolt.shield.fill"]
            case .nature:
                return ["leaf.fill", "tree.fill", "mountain.2.fill", "drop.fill", "sun.max.fill",
                        "cloud.sun.fill", "hare.fill", "bird.fill"]
            case .business:
                return ["briefcase.fill", "chart.bar.fill", "person.3.fill", "building.2.fill",
                        "chart.line.uptrend.xyaxis", "doc.richtext.fill", "calendar"]
            case .engineering:
                return ["gearshape.2.fill", "ruler.fill", "wrench.adjustable.fill", "hammer.fill",
                        "screwdriver.fill", "level.fill", "measuring.tape"]
            case .aviation:
                return ["airplane", "airplane.circle.fill", "airplane.departure", "paperplane.fill",
                        "cloud.fill", "location.north.fill", "gauge.with.needle.fill"]
            case .maritime:
                return ["ferry.fill", "sailboat.fill", "water.waves", "anchor.circle.fill",
                        "scope", "compass.drawing", "wave.3.right"]
            case .military:
                return ["shield.fill", "target", "flag.fill", "star.circle.fill", "medal.fill",
                        "person.badge.shield.checkmark.fill", "map.fill"]
            case .fashion:
                return ["tshirt.fill", "handbag.fill", "shoe.fill", "eyeglasses", "crown.fill",
                        "sparkles", "scissors", "hanger"]
            case .art:
                return ["paintpalette.fill", "paintbrush.fill", "photo.artframe", "theatermasks.fill",
                        "photo.on.rectangle.angled", "square.3.layers.3d", "pencil.tip.crop.circle.fill"]
            case .architecture:
                return ["building.2.fill", "house.fill", "building.columns.fill", "triangle.fill",
                        "square.grid.3x3.fill", "ruler.fill", "viewfinder"]
            case .agriculture:
                return ["leaf.fill", "carrot.fill", "tree.fill", "sun.max.fill", "drop.fill",
                        "hare.fill", "pawprint.fill", "bird.fill"]
            case .pets:
                return ["pawprint.fill", "dog.fill", "cat.fill", "hare.fill", "bird.fill",
                        "fish.fill", "tortoise.fill", "lizard.fill"]
            case .general:
                return ["folder.fill", "doc.fill", "square.stack.3d.up.fill", "archivebox.fill",
                        "tray.full.fill", "books.vertical.fill"]
            }
        }
    }

    // MARK: - Public API

    /// Analyzes document names and content to suggest the best icon for a library
    /// - Parameters:
    ///   - documentNames: Names of documents in the library
    ///   - sampleContent: Optional sample text from documents (first ~1000 chars)
    /// - Returns: Suggested SF Symbol name
    static func suggestIcon(
        documentNames: [String],
        sampleContent: String? = nil
    ) -> String {
        let detectedDomain = detectDomain(documentNames: documentNames, sampleContent: sampleContent)
        return detectedDomain.suggestedIcons.first ?? "folder.fill"
    }

    /// Returns ranked icon suggestions based on library content
    /// - Parameters:
    ///   - documentNames: Names of documents in the library
    ///   - sampleContent: Optional sample text from documents
    ///   - limit: Maximum number of suggestions to return
    /// - Returns: Array of SF Symbol names, best match first
    static func suggestIcons(
        documentNames: [String],
        sampleContent: String? = nil,
        limit: Int = 6
    ) -> [String] {
        let detectedDomain = detectDomain(documentNames: documentNames, sampleContent: sampleContent)
        return Array(detectedDomain.suggestedIcons.prefix(limit))
    }

    /// Detects the content domain from document names and content
    static func detectDomain(
        documentNames: [String],
        sampleContent: String? = nil
    ) -> ContentDomain {
        // Combine all text for analysis
        let combinedText = (documentNames.joined(separator: " ") + " " + (sampleContent ?? "")).lowercased()

        // Score each domain by keyword matches
        var domainScores: [(domain: ContentDomain, score: Int)] = []

        for domain in ContentDomain.allCases where domain != .general {
            var score = 0
            for keyword in domain.keywords {
                if combinedText.contains(keyword.lowercased()) {
                    // Weight longer keywords higher (more specific)
                    score += keyword.count > 6 ? 3 : (keyword.count > 4 ? 2 : 1)
                }
            }
            if score > 0 {
                domainScores.append((domain, score))
            }
        }

        // Return highest scoring domain, or general if no matches
        domainScores.sort { $0.score > $1.score }
        return domainScores.first?.domain ?? .general
    }

    /// Get all available icons for a detected domain (for picker pre-selection)
    static func iconsForDomain(_ domain: ContentDomain) -> [String] {
        return domain.suggestedIcons
    }
}

// MARK: - Integration Extension

extension LibraryIconSuggestionService {
    /// Convenience method for RAGService integration
    /// Analyzes a container's documents and returns the best icon suggestion
    static func suggestIconForContainer(
        documents: [Document]
    ) -> String {
        let names = documents.map { $0.filename }
        // Use content tags if available for better domain detection
        let tagContent = documents.compactMap { $0.contentTags?.joined(separator: " ") }.joined(separator: " ")
        let sampleContent = tagContent.isEmpty ? nil : tagContent

        return suggestIcon(documentNames: names, sampleContent: sampleContent)
    }
}
