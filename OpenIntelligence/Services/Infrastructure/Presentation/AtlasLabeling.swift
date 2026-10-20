//
//  AtlasLabeling.swift
//  OpenIntelligence
//
//  Pure static functions for extracting distinct, deterministic, data-derived
//  labels for Knowledge Atlas clusters and semantic projection axes.
//

import Foundation
import NaturalLanguage

public nonisolated enum AtlasLabeling {

    // MARK: - Axis Ends Result

    public struct AxisEnds: Equatable {
        public let low: [String]
        public let high: [String]

        public init(low: [String], high: [String]) {
            self.low = low
            self.high = high
        }

        public var lowLabel: String {
            AtlasLabeling.formatTerms(low)
        }

        public var highLabel: String {
            AtlasLabeling.formatTerms(high)
        }
    }

    // MARK: - Built-in Stop Words

    public static let stopWords: Set<String> = [
        "a", "about", "above", "across", "after", "again", "against", "all",
        "almost", "along", "already", "also", "although", "always", "am",
        "among", "an", "and", "another", "any", "anyone", "anything", "anyway",
        "are", "aren", "around", "as", "at", "be", "became", "because",
        "become", "becomes", "been", "before", "behind", "being", "below",
        "beside", "besides", "between", "beyond", "both", "but", "by", "can",
        "cannot", "could", "couldn", "did", "didn", "do", "does", "doesn",
        "doing", "don", "done", "down", "during", "each", "either", "else",
        "even", "ever", "every", "everyone", "everything", "everywhere", "few",
        "for", "from", "further", "get", "gets", "getting", "give", "given",
        "gives", "go", "goes", "going", "gone", "got", "had", "hadn",
        "has", "hasn", "have", "haven", "having", "he", "hed", "hell",
        "her", "here", "hers", "herself", "hes", "him", "himself", "his",
        "how", "however", "i", "id", "if", "ill", "im", "in",
        "into", "is", "isn", "it", "its", "itself", "ive", "just",
        "let", "lets", "like", "likely", "made", "make", "makes", "making",
        "many", "may", "maybe", "me", "might", "mightn", "more", "most",
        "mostly", "much", "must", "mustn", "my", "myself", "neither", "never",
        "no", "nobody", "none", "noone", "nor", "not", "nothing", "now",
        "nowhere", "of", "off", "often", "on", "once", "one", "ones",
        "only", "onto", "or", "other", "others", "otherwise", "our", "ours",
        "ourselves", "out", "over", "own", "per", "perhaps", "quite", "rather",
        "really", "same", "say", "said", "says", "see", "seem", "seemed",
        "seeming", "seems", "seen", "several", "shall", "shan", "she", "shed",
        "shell", "shes", "should", "shouldn", "since", "so", "some", "someone",
        "something", "somewhere", "still", "such", "than", "that", "thats",
        "the", "their", "theirs", "them", "themselves", "then", "thence",
        "there", "thereafter", "thereby", "therefore", "therein", "theres",
        "these", "they", "theyd", "theyll", "theyre", "theyve", "this",
        "those", "though", "through", "throughout", "thru", "thus", "to",
        "together", "too", "toward", "towards", "under", "until", "unto",
        "up", "upon", "us", "use", "used", "uses", "using", "very",
        "via", "was", "wasn", "we", "wed", "well", "went", "were",
        "weren", "weve", "what", "whatever", "whats", "when", "whence",
        "whenever", "where", "whereafter", "whereas", "whereby", "wherein",
        "whereupon", "wherever", "which", "while", "whither", "who", "whoever",
        "whole", "whom", "whose", "why", "will", "with", "within", "without",
        "won", "wont", "would", "wouldn", "yes", "yet", "you", "youd",
        "youll", "your", "youre", "yours", "yourself", "yourselves", "youve",
    ]

    // MARK: - Tokenization

    /// Extracts distinct, lowercased terms from text using NLTokenizer.
    /// Works universally across languages and scripts (including languages written without spaces).
    /// Drops tokens that contain digits or are longer than 24 characters.
    /// Keeps a word when every character is a letter in any script (Character.isLetter),
    /// requiring at least 2 characters for scripts without case and at least 3 characters otherwise.
    /// Lowercases with the locale-independent lowercased().
    /// English stop words are filtered as an extra filter.
    public static func terms(in text: String) -> Set<String> {
        guard !text.isEmpty else { return [] }
        var result = Set<String>()

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            let raw = text[tokenRange]

            // Drop tokens that look like identifiers or encodings:
            // contain digits or are longer than 24 characters
            guard raw.count <= 24, !raw.contains(where: { $0.isNumber }) else {
                return true
            }

            // Keep a word when every character is a letter in any script
            guard raw.allSatisfy({ $0.isLetter }) else {
                return true
            }

            // Lowercase with the locale-independent lowercased()
            let lower = String(raw).lowercased()

            // Keep word with at least 2 characters for scripts without case and at least 3 otherwise
            let hasCase = lower.contains(where: { $0.isUppercase || $0.isLowercase }) || lower.uppercased() != lower
            let minLength = hasCase ? 3 : 2
            guard lower.count >= minLength else {
                return true
            }

            // English stop list stays as an extra filter
            if !stopWords.contains(lower) {
                result.insert(lower)
            }

            return true
        }

        return result
    }

    // MARK: - Words That Can Name Passages

    /// Word classes that cannot name a group of passages: adverbs and function words (5.7). An axis end of the
    /// owner's library of instructions for use read "Blade & Gently" on his iPhone (2026-10-16).
    private static let classesThatNameNothing: Set<String> = [
        NLTag.adverb.rawValue, NLTag.pronoun.rawValue, NLTag.determiner.rawValue, NLTag.particle.rawValue,
        NLTag.preposition.rawValue, NLTag.conjunction.rawValue,
    ]

    /// The terms of `ranked`, in order, that can name passages: at most `limit` of them, none of `excluding`, and none
    /// that the passages carrying it use as an adverb or a function word (5.7). Each word is looked at where it stands
    /// in the first three of `passages` that carry it (`terms` holds each passage's words), each passage tagged in its
    /// own language (`NLLanguageRecognizer`), because a library of instructions for use is often written in several,
    /// and a word most of them tag that way is left out. Tagged on its own a word is often misread: on macOS 27
    /// (2026-10-16) "tray" alone came back an adverb and "detergent" an interjection, and in a sentence both came back
    /// nouns, while "gently", "carefully", "thoroughly", Spanish "suavemente" and German "vorsichtig" came back
    /// adverbs either way. A passage of 1,600 characters took about 1 ms to tag. A passage in a language the tagger has
    /// no word classes for (Japanese, Greek) has no say, and a word none of its passages has a say on is kept.
    public static func namingTerms(
        _ ranked: [String], passages: [String], terms: [Set<String>], limit: Int, excluding: Set<String> = []
    ) -> [String] {
        guard passages.count == terms.count else {
            return Array(ranked.lazy.filter { !excluding.contains($0) }.prefix(limit))
        }
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        var languages: [Int: NLLanguage?] = [:]
        func language(of index: Int) -> NLLanguage? {
            if let known = languages[index] { return known }
            let found = NLLanguageRecognizer.dominantLanguage(for: passages[index]).flatMap { language in
                NLTagger.availableTagSchemes(for: .word, language: language).contains(.lexicalClass) ? language : nil
            }
            languages[index] = found
            return found
        }
        var kept: [String] = []
        for term in ranked where !excluding.contains(term) {
            var looked = 0
            var uses = 0
            var namingNothing = 0
            for index in passages.indices where terms[index].contains(term) {
                looked += 1
                if let language = language(of: index) {
                    let text = passages[index]
                    tagger.string = text
                    tagger.setLanguage(language, range: text.startIndex..<text.endIndex)
                    var found: NLTag?
                    tagger.enumerateTags(
                        in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass,
                        options: [.omitWhitespace, .omitPunctuation]
                    ) { tag, range in
                        guard text[range].lowercased() == term else { return true }
                        found = tag
                        return false
                    }
                    if let found {
                        uses += 1
                        if classesThatNameNothing.contains(found.rawValue) { namingNothing += 1 }
                    }
                }
                if looked == 3 { break }
            }
            if namingNothing * 2 > uses { continue }
            kept.append(term)
            if kept.count == limit { break }
        }
        return kept
    }

    // MARK: - Word Classes the System Can Load

    /// The languages NaturalLanguage has word classes for (`NLTagger`'s lexical class), by code: on macOS 27
    /// (2026-10-17) these eight had them and 49 others had none, and a request for one of those (Japanese, Greek,
    /// Swedish) went unanswered for the three seconds it was given.
    static let languagesWithWordClasses: Set<String> = ["en", "fr", "de", "it", "pt", "zh-Hans", "es", "tr"]

    /// Asks the system to load the word classes of each language among `texts` that can have them and that the device
    /// does not have yet, and waits for the answers up to `timeout` (5.7, at the owner's word on 2026-10-16: "yes add
    /// the requestAssets"). In the iOS 27 Simulator Spanish and German had none, so their adverbs could name the
    /// Atlas's axes; macOS 27 has them. The languages are read from about 200 passages spread across `texts`. Each is
    /// asked for once a launch: one still loading when the wait ends goes on loading, and a later map uses it. The
    /// request names the language and the tag scheme, nothing from the passages (`NLTagger.requestAssets`). Returns the
    /// codes of the passages' languages that have word classes afterwards.
    @discardableResult
    public static func loadWordClasses(for texts: [String], timeout: Duration = .seconds(3)) async -> Set<String> {
        var languages = Set<String>()
        if !texts.isEmpty {
            for index in stride(from: 0, to: texts.count, by: max(1, texts.count / 200)) {
                if let language = NLLanguageRecognizer.dominantLanguage(for: texts[index]) {
                    languages.insert(language.rawValue)
                }
            }
        }
        func hasWordClasses(_ code: String) -> Bool {
            NLTagger.availableTagSchemes(for: .word, language: NLLanguage(rawValue: code)).contains(.lexicalClass)
        }
        let missing = languages.filter { code in
            languagesWithWordClasses.contains(code) && !hasWordClasses(code) && WordClassRequests.shared.claim(code)
        }
        if !missing.isEmpty {
            await withTaskGroup(of: Void.self) { group in
                for code in missing {
                    group.addTask { _ = await requestWordClasses(code, timeout: timeout) }
                }
            }
        }
        return languages.filter(hasWordClasses)
    }

    /// One language's word classes, asked of the system and waited for up to `timeout`; nil when the wait ended first.
    /// The system's answer can come after that, or never: the wait does not depend on it.
    private static func requestWordClasses(_ code: String, timeout: Duration) async -> NLTagger.AssetsResult? {
        await withCheckedContinuation { (continuation: CheckedContinuation<NLTagger.AssetsResult?, Never>) in
            let once = ResumeOnce(continuation)
            NLTagger.requestAssets(for: NLLanguage(rawValue: code), tagScheme: .lexicalClass) { result, error in
                once.resume(error == nil ? result : .error)
            }
            Task {
                try? await Task.sleep(for: timeout)
                once.resume(nil)
            }
        }
    }

    // MARK: - Title Case & Formatting

    /// Formats a single lowercased word as Title Case.
    public static func titleCase(_ word: String) -> String {
        guard let first = word.first else { return "" }
        return first.uppercased() + word.dropFirst().lowercased()
    }

    /// Formats top one or two terms joined with " & " in Title Case.
    public static func formatTerms(_ terms: [String]) -> String {
        let top = terms.prefix(2)
        return top.map { titleCase($0) }.joined(separator: " & ")
    }

    // MARK: - Distinguishing Terms

    /// How strongly a word marks one set of passages against another: its share of the set's passages times the
    /// log of how many times more often it is found there than in the other set, both shares smoothed by half a
    /// passage so that a word absent from the other set still has a finite score. Zero when the word is no more
    /// common in the set than in the other.
    ///
    /// Until 2026-10-15 the score was the bare ratio of the two shares. Every word found in only one set then had
    /// the same score however many of its passages carried it, ties went in alphabetical order, and the owner's
    /// three-document library was named "Agent & Alert", "Activation & Addition" and "Annual & App" on his
    /// iPhone. On passages cut from the same three documents this score names the paper's cluster "Dopamine &
    /// Serotonin" (scratch probe, 2026-10-15).
    static func contrast(_ count: Int, of size: Int, against otherCount: Int, of otherSize: Int) -> Double {
        let share = (Double(count) + 0.5) / (Double(size) + 1)
        let otherShare = (Double(otherCount) + 0.5) / (Double(otherSize) + 1)
        guard share > otherShare else { return 0 }
        return share * log(share / otherShare)
    }

    /// Candidates by score, then by the number of passages carrying them, then alphabetically.
    private static func ranked(_ candidates: [(term: String, score: Double, count: Int)]) -> [String] {
        candidates.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.count != b.count { return a.count > b.count }
            return a.term < b.term
        }.map(\.term)
    }

    /// Given groups of passages, for each group returns the terms most over-represented in it
    /// against the passages outside it.
    /// Score = `contrast` of the group's passages carrying the term against the other passages carrying it.
    /// Below 40 passages, requires term in at least 2 passages of the group (1 when group has fewer than 4).
    /// At 40 or more passages, requires term in at least 5% of group passages and at least 3 passages.
    /// Drop any term in more than 40% of all passages.
    /// Ties go to the term in more of the group's passages, then alphabetically. Iterates dictionaries in
    /// sorted key order for determinism.
    public static func distinguishingTerms(
        groups: [[String]],
        allPassages: [String]? = nil
    ) -> [[String]] {
        let all = allPassages ?? groups.flatMap { $0 }
        let allPassageTerms = all.map { terms(in: $0) }
        let groupTerms = groups.map { $0.map { terms(in: $0) } }
        return distinguishingTerms(passageTerms: groupTerms, allPassageTerms: allPassageTerms)
    }

    /// The words found in the most passages, most first, ties in alphabetical order. A word has to
    /// be in two passages when there are four or more.
    public static func commonTerms(passageTerms: [Set<String>], limit: Int = 4) -> [String] {
        var counts: [String: Int] = [:]
        for terms in passageTerms {
            for term in terms { counts[term, default: 0] += 1 }
        }
        let needed = passageTerms.count >= 4 ? 2 : 1
        return counts.filter { $0.value >= needed }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map(\.key)
    }

    /// Distinguishing terms over pre-tokenized sets. Bounded cost: each passage is tokenized once.
    public static func distinguishingTerms(
        passageTerms: [[Set<String>]],
        allPassageTerms: [Set<String>]? = nil
    ) -> [[String]] {
        let background = allPassageTerms ?? passageTerms.flatMap { $0 }
        let totalPassages = background.count
        guard totalPassages > 0 else {
            return passageTerms.map { _ in [] }
        }

        // A library that is all one group has nothing to be set against, and the rule below
        // would turn away its best words for being common to it. It is named by the words found
        // in the most of its passages.
        let occupied = passageTerms.indices.filter { !passageTerms[$0].isEmpty }
        if occupied.count == 1, let only = occupied.first, passageTerms[only].count == totalPassages {
            var result = passageTerms.map { _ in [String]() }
            result[only] = commonTerms(passageTerms: passageTerms[only])
            return result
        }

        // Background term frequencies across all passages
        var allFreq = [String: Int]()
        for s in background {
            for term in s {
                allFreq[term, default: 0] += 1
            }
        }

        var result = [[String]]()
        result.reserveCapacity(passageTerms.count)

        for group in passageTerms {
            let groupCount = group.count
            guard groupCount > 0 else {
                result.append([])
                continue
            }

            var groupFreq = [String: Int]()
            for s in group {
                for term in s {
                    groupFreq[term, default: 0] += 1
                }
            }

            let minGroupCount: Int
            let minGroupShare: Double
            if totalPassages < 40 {
                minGroupCount = groupCount < 4 ? 1 : 2
                minGroupShare = 0.0
            } else {
                minGroupCount = 3
                minGroupShare = 0.05
            }

            var candidates: [(term: String, score: Double, count: Int)] = []

            // Deterministic iteration: sort dictionary keys before iterating
            for term in groupFreq.keys.sorted() {
                let gCount = groupFreq[term]!

                guard gCount >= minGroupCount else { continue }
                let shareGroup = Double(gCount) / Double(groupCount)
                guard shareGroup >= minGroupShare else { continue }

                // Drop any term found in more than 40% of all passages
                let aCount = allFreq[term] ?? gCount
                let shareAll = Double(aCount) / Double(totalPassages)
                guard shareAll <= 0.40 else { continue }

                let score = contrast(
                    gCount, of: groupCount,
                    against: max(0, aCount - gCount), of: max(0, totalPassages - groupCount))
                guard score > 0 else { continue }

                candidates.append((term: term, score: score, count: gCount))
            }

            result.append(ranked(candidates))
        }

        return result
    }

    /// Distinguishing terms given flat texts and cluster membership indices.
    public static func distinguishingTerms(
        texts: [String],
        clusterMembership: [Int]
    ) -> [[String]] {
        guard !texts.isEmpty, texts.count == clusterMembership.count else { return [] }
        let maxCluster = clusterMembership.max() ?? -1
        guard maxCluster >= 0 else { return [] }
        let k = maxCluster + 1

        let allTerms = texts.map { terms(in: $0) }
        var groupTerms = Array(repeating: [Set<String>](), count: k)
        for (i, c) in clusterMembership.enumerated() {
            if c >= 0 && c < k {
                groupTerms[c].append(allTerms[i])
            }
        }

        return distinguishingTerms(passageTerms: groupTerms, allPassageTerms: allTerms)
    }

    // MARK: - Cluster Names

    /// Generates one distinct Title Case name per cluster from its distinguishing terms.
    /// Top one or two distinguishing terms joined with " & ".
    /// No two clusters share a name: if taken, uses the next distinguishing term;
    /// if none remaining, falls back to "Group 1", "Group 2", etc.
    public static func clusterNames(
        distinguishingTerms: [[String]]
    ) -> [String] {
        var usedNames = Set<String>()
        var names = [String]()
        names.reserveCapacity(distinguishingTerms.count)

        for (index, terms) in distinguishingTerms.enumerated() {
            var chosenName: String?

            if terms.isEmpty {
                chosenName = "Group \(index + 1)"
            } else if terms.count == 1 {
                let candidate = titleCase(terms[0])
                if !usedNames.contains(candidate) {
                    chosenName = candidate
                }
            } else {
                let topTwo = formatTerms(Array(terms.prefix(2)))
                if !usedNames.contains(topTwo) {
                    chosenName = topTwo
                } else {
                    // Try next distinguishing terms with terms[0]: terms[0] & terms[j] for j >= 2
                    for nextIdx in 2..<terms.count {
                        let candidate = titleCase(terms[0]) + " & " + titleCase(terms[nextIdx])
                        if !usedNames.contains(candidate) {
                            chosenName = candidate
                            break
                        }
                    }
                    // Try single term terms[0]
                    if chosenName == nil {
                        let single0 = titleCase(terms[0])
                        if !usedNames.contains(single0) {
                            chosenName = single0
                        }
                    }
                    // Try terms[1] & terms[j]
                    if chosenName == nil {
                        for nextIdx in 2..<terms.count {
                            let candidate = titleCase(terms[1]) + " & " + titleCase(terms[nextIdx])
                            if !usedNames.contains(candidate) {
                                chosenName = candidate
                                break
                            }
                        }
                    }
                    // Try single term terms[1]
                    if chosenName == nil {
                        let single1 = titleCase(terms[1])
                        if !usedNames.contains(single1) {
                            chosenName = single1
                        }
                    }
                }
            }

            let finalName: String
            if let chosen = chosenName, !usedNames.contains(chosen) {
                finalName = chosen
            } else {
                var fallback = "Group \(index + 1)"
                var counter = 1
                while usedNames.contains(fallback) {
                    counter += 1
                    fallback = "Group \(index + counter)"
                }
                finalName = fallback
            }

            usedNames.insert(finalName)
            names.append(finalName)
        }

        return names
    }

    /// Convenience cluster names over passage groups.
    public static func clusterNames(
        groups: [[String]],
        allPassages: [String]? = nil
    ) -> [String] {
        let dist = distinguishingTerms(groups: groups, allPassages: allPassages)
        return clusterNames(distinguishingTerms: dist)
    }

    /// Convenience cluster names over flat texts and cluster membership.
    public static func clusterNames(
        texts: [String],
        clusterMembership: [Int],
        precomputedTerms: [Set<String>]? = nil,
        sources: PassageSources? = nil
    ) -> [String] {
        guard !texts.isEmpty, texts.count == clusterMembership.count else { return [] }
        let allTerms = precomputedTerms ?? texts.map { terms(in: $0) }
        let dist = namingDistinguishingTerms(texts: texts, clusterMembership: clusterMembership, passageTerms: allTerms)
        return clusterNames(distinguishingTerms: dist, membership: clusterMembership, sources: sources)
    }

    /// Each cluster's distinguishing terms, at most 12, with the words its own passages use as adverbs or function
    /// words left out (`namingTerms`, 5.7). The map's names and the library's topic chips both read these, so they
    /// agree.
    public static func namingDistinguishingTerms(
        texts: [String], clusterMembership: [Int], passageTerms: [Set<String>]
    ) -> [[String]] {
        guard !texts.isEmpty, texts.count == clusterMembership.count, texts.count == passageTerms.count else {
            return []
        }
        let k = (clusterMembership.max() ?? -1) + 1
        guard k > 0 else { return [] }
        var groupTerms = Array(repeating: [Set<String>](), count: k)
        var groupTexts = Array(repeating: [String](), count: k)
        for (i, c) in clusterMembership.enumerated() where c >= 0 && c < k {
            groupTerms[c].append(passageTerms[i])
            groupTexts[c].append(texts[i])
        }
        let ranked = distinguishingTerms(passageTerms: groupTerms, allPassageTerms: passageTerms)
        return ranked.indices.map { c in
            namingTerms(ranked[c], passages: groupTexts[c], terms: groupTerms[c], limit: 12)
        }
    }

    // MARK: - Axis Ends Analysis

    /// For one projection axis, takes the tenth of passages with the lowest value and the tenth with
    /// the highest, and returns the distinguishing terms of each end against the other end (one or two per end),
    /// scored with `contrast` and ranked like a cluster's, leaving out `excluding` and the words those passages use as
    /// adverbs or function words (`namingTerms`).
    /// For fewer than 20 passages, uses the lowest and highest two.
    /// Below 4 passages, returns nil.
    /// If neither end has a distinguishing term, returns nil.
    /// An end with none at the usual thresholds takes one found in two of its passages that is more common there than
    /// at the other end (5.7); an end that still has none is empty, and `axisLabels` shows it as "Component N".
    /// Through 5.6 the second try did not exist, and an empty end drew nothing on the map.
    public static func axisEnds(
        values: [Float],
        texts: [String],
        passageTerms: [Set<String>]? = nil,
        excluding: Set<String> = []
    ) -> AxisEnds? {
        guard values.count == texts.count, !values.isEmpty else { return nil }
        let totalCount = values.count
        guard totalCount >= 4 else { return nil }

        let endCount = totalCount < 20 ? 2 : max(2, totalCount / 10)
        guard endCount >= 2, endCount * 2 <= totalCount else { return nil }

        // Tokenize once if not provided
        let allTerms = passageTerms ?? texts.map { terms(in: $0) }

        // Background frequencies across the whole library
        var allFreq = [String: Int]()
        for s in allTerms {
            for term in s {
                allFreq[term, default: 0] += 1
            }
        }

        guard let ends = endIndices(values: values) else { return nil }
        let lowIndices = ends.low
        let highIndices = ends.high

        let lowTerms = lowIndices.map { allTerms[$0] }
        let highTerms = highIndices.map { allTerms[$0] }

        var lowFreq = [String: Int]()
        for s in lowTerms {
            for term in s {
                lowFreq[term, default: 0] += 1
            }
        }

        var highFreq = [String: Int]()
        for s in highTerms {
            for term in s {
                highFreq[term, default: 0] += 1
            }
        }

        let lowCount = lowIndices.count
        let highCount = highIndices.count
        let bothCount = lowCount + highCount

        let minEndCount: Int
        let minEndShare: Double
        if totalCount < 40 {
            minEndCount = endCount < 4 ? 1 : 2
            minEndShare = 0.0
        } else {
            minEndCount = 3
            minEndShare = 0.05
        }

        let lowTexts = lowIndices.map { texts[$0] }
        let highTexts = highIndices.map { texts[$0] }

        func distinguishing(
            freq: [String: Int],
            otherFreq: [String: Int],
            count: Int,
            otherCount: Int,
            minCount: Int,
            minShare: Double,
            excluded: Set<String>,
            passages: [String],
            passageTerms: [Set<String>]
        ) -> [String] {
            guard count > 0, bothCount > 0, totalCount > 0 else { return [] }
            var candidates: [(term: String, score: Double, count: Int)] = []

            for term in freq.keys.sorted() {
                let f = freq[term]!
                guard f >= minCount else { continue }
                let shareEnd = Double(f) / Double(count)
                guard shareEnd >= minShare else { continue }

                // Term common to > 40% of the entire library names nothing
                let aCount = allFreq[term] ?? f
                let shareAll = Double(aCount) / Double(totalCount)
                guard shareAll <= 0.40 else { continue }

                let score = contrast(f, of: count, against: otherFreq[term] ?? 0, of: otherCount)
                guard score > 0 else { continue }

                candidates.append((term: term, score: score, count: f))
            }

            return namingTerms(
                ranked(candidates), passages: passages, terms: passageTerms, limit: 2, excluding: excluded)
        }

        // The second try differs only where the usual thresholds are stricter than a word in two passages.
        let relaxedCount = min(minEndCount, 2)
        let canRelax = relaxedCount < minEndCount || minEndShare > 0

        var lowDist = distinguishing(
            freq: lowFreq, otherFreq: highFreq, count: lowCount, otherCount: highCount,
            minCount: minEndCount, minShare: minEndShare, excluded: excluding,
            passages: lowTexts, passageTerms: lowTerms)
        var highDist = distinguishing(
            freq: highFreq, otherFreq: lowFreq, count: highCount, otherCount: lowCount,
            minCount: minEndCount, minShare: minEndShare, excluded: excluding,
            passages: highTexts, passageTerms: highTerms)
        if lowDist.isEmpty, canRelax {
            lowDist = distinguishing(
                freq: lowFreq, otherFreq: highFreq, count: lowCount, otherCount: highCount,
                minCount: relaxedCount, minShare: 0, excluded: excluding.union(highDist),
                passages: lowTexts, passageTerms: lowTerms)
        }
        if highDist.isEmpty, canRelax {
            highDist = distinguishing(
                freq: highFreq, otherFreq: lowFreq, count: highCount, otherCount: lowCount,
                minCount: relaxedCount, minShare: 0, excluded: excluding.union(lowDist),
                passages: highTexts, passageTerms: highTerms)
        }

        if lowDist.isEmpty && highDist.isEmpty {
            return nil
        }

        return AxisEnds(low: lowDist, high: highDist)
    }

    /// The passages at each end of one axis: the tenth with the lowest values and the tenth with the highest, two
    /// each below 20 passages, ties broken by position so the ends are the same on every launch. Nil below 4 passages.
    static func endIndices(values: [Float]) -> (low: [Int], high: [Int])? {
        let totalCount = values.count
        guard totalCount >= 4 else { return nil }
        let endCount = totalCount < 20 ? 2 : max(2, totalCount / 10)
        guard endCount * 2 <= totalCount else { return nil }
        let sortedIndices = (0..<totalCount).sorted {
            values[$0] != values[$1] ? values[$0] < values[$1] : $0 < $1
        }
        return (Array(sortedIndices.prefix(endCount)), Array(sortedIndices.suffix(endCount)))
    }

    // MARK: - Names From the Library's Structure (5.7)

    /// What each sampled passage belongs to, for naming a map's ends and its clusters by more than their words (5.7):
    /// the document it comes from, by a short name (`shortDocumentName`); its library, when the map holds several; and
    /// its section heading, cleaned by `sectionName`. Each list is as long as the passages (`libraries` may be empty).
    ///
    /// The owner, 2026-10-20, of an axis named "Air & Fryer": an axis should be named for the part of the library it
    /// runs toward, an instruction manual's sterilization or settings, not two words from one product name.
    public struct PassageSources: Sendable, Equatable {
        /// Each passage's document.
        public let groups: [String?]
        public let sections: [String?]
        /// Each passage's library, in a map of several; empty otherwise.
        public let libraries: [String?]

        public init(groups: [String?], sections: [String?], libraries: [String?] = []) {
            self.groups = groups.map { $0.flatMap { $0.isEmpty ? nil : $0 } }
            self.sections = sections.map { $0.flatMap(AtlasLabeling.sectionName) }
            self.libraries = libraries.map { $0.flatMap { $0.isEmpty ? nil : $0 } }
        }

        /// How many different documents the passages come from.
        var groupCount: Int { Set(groups.compactMap { $0 }).count }
        var libraryCount: Int { Set(libraries.compactMap { $0 }).count }

        func fits(_ count: Int) -> Bool {
            groups.count == count && sections.count == count && (libraries.isEmpty || libraries.count == count)
        }
    }

    /// A document's file name as a short name for the map: no extension, the part before " - " ("Juniper Flats Lease -
    /// Unit 4B.pdf" is "Juniper Flats Lease"), no word with a digit in it ("Kestrel AF-620 Air Fryer Manual" is "Kestrel
    /// Air Fryer Manual", "Home Insurance Declarations 2026" is "Home Insurance Declarations"), at most 28 characters in
    /// whole words. A name that would be left empty keeps its words as written.
    public static func shortDocumentName(_ filename: String) -> String {
        var name = (filename as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [" - ", " – ", " — "] {
            if let range = name.range(of: separator), name.distance(from: name.startIndex, to: range.lowerBound) >= 4 {
                name = String(name[..<range.lowerBound])
            }
        }
        let words = name.split(whereSeparator: \.isWhitespace).map(String.init)
        let kept = words.filter { !$0.contains(where: \.isNumber) }
        var result = ""
        for word in (kept.isEmpty ? words : kept) {
            let next = result.isEmpty ? word : result + " " + word
            if next.count > 28, !result.isEmpty { break }
            result = next
        }
        return result
    }

    /// A section heading as a name, or nil when it isn't one (5.7): no leading number or letter ("5. Late Charges" is
    /// "Late Charges"), title case for a heading set in capitals ("TROUBLESHOOTING" is "Troubleshooting", "HOW TO
    /// CANCEL" is "How to Cancel"), and nil for a heading of more than six words or 40 characters, one with a digit in
    /// it, or one ending in a full stop: a sentence or an address the chunker took for a heading ("418 Mercer Plaza",
    /// "2. Stir the melted butter into the mashed bananas.").
    public static func sectionName(_ heading: String) -> String? {
        var text = heading.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: #"^(?:\d+(?:\.\d+)*|[A-Za-z]|[IVXLC]+)[.)]\s+"#, options: .regularExpression) {
            text.removeSubrange(range)
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " :–—-").union(.whitespacesAndNewlines))
        let words = text.split(whereSeparator: \.isWhitespace)
        guard !text.isEmpty, text.count <= 40, words.count <= 6, !text.contains(where: \.isNumber), !text.hasSuffix("."),
            text.contains(where: \.isLetter)
        else { return nil }
        let letters = text.filter(\.isLetter)
        guard letters == letters.uppercased(), letters != letters.lowercased() else { return text }
        let small: Set<String> = ["a", "an", "and", "as", "at", "by", "for", "in", "of", "on", "or", "the", "to", "with"]
        return words.enumerated().map { index, word in
            let lower = word.lowercased()
            return index > 0 && small.contains(lower) ? lower : titleCase(lower)
        }.joined(separator: " ")
    }

    /// The name `sources` give the passages at `indices` against those at `otherIndices` (5.7), the first of:
    /// - the document at least half of them come from, when the map holds more than one and at most a third of the other
    ///   passages come from it;
    /// - when that document already names another end, it with the section at least two of its passages here share
    ///   ("Juniper Flats Lease: Late Charges");
    /// - the library at least half of them come from, on the same terms, in a map of several libraries;
    /// - the section heading at least two of them and 30% share, more often than the other passages do.
    /// Never a name in `used`. Nil when none stands out, and the caller keeps its words.
    static func sourceName(
        indices: [Int], otherIndices: [Int], sources: PassageSources, used: Set<String>, minimumShare: Double = 0.5
    ) -> String? {
        guard !indices.isEmpty else { return nil }
        func counts(_ values: [String?], at positions: [Int]) -> [String: Int] {
            var result: [String: Int] = [:]
            for position in positions { if let value = values[position] { result[value, default: 0] += 1 } }
            return result
        }
        func ranked(_ counts: [String: Int]) -> [(name: String, count: Int)] {
            counts.map { ($0.key, $0.value) }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
        }
        let size = Double(indices.count), otherSize = Double(max(otherIndices.count, 1))
        // The group most of these passages come from, when few of the others do. Below half (a cluster's
        // `minimumShare`), it also has to hold at least twice as many of them as the next group.
        func standout(_ values: [String?]) -> String? {
            let groups = ranked(counts(values, at: indices))
            guard let top = groups.first, Double(top.count) / size >= minimumShare,
                Double(counts(values, at: otherIndices)[top.name] ?? 0) / otherSize <= 0.34,
                Double(top.count) / size >= 0.5 || groups.count < 2 || top.count >= 2 * groups[1].count
            else { return nil }
            return top.name
        }
        if sources.groupCount >= 2, let document = standout(sources.groups) {
            if !used.contains(document) { return document }
            let mine = indices.filter { sources.groups[$0] == document }
            for (section, count) in ranked(counts(sources.sections, at: mine)) where count >= 2 {
                let name = "\(document): \(section)"
                if !used.contains(name) { return name }
            }
        }
        if sources.libraryCount >= 2, let library = standout(sources.libraries), !used.contains(library) {
            return library
        }
        let elsewhere = counts(sources.sections, at: otherIndices)
        for (name, count) in ranked(counts(sources.sections, at: indices)) where !used.contains(name) {
            guard count >= 2, Double(count) / size >= 0.3 else { break }
            if Double(count) / size > Double(elsewhere[name] ?? 0) / otherSize { return name }
        }
        return nil
    }

    /// Cluster names from the library's structure where it speaks (5.7): a cluster 40% of whose passages come from one
    /// document (or library), with twice the passages of the next and few of the rest, is named by it; one whose
    /// passages share a section heading, by that heading (`sourceName`). The others keep their names from `clusterNames(distinguishingTerms:)`. No two
    /// clusters share a name.
    public static func clusterNames(
        distinguishingTerms: [[String]], membership: [Int], sources: PassageSources?
    ) -> [String] {
        let wordNames = clusterNames(distinguishingTerms: distinguishingTerms)
        guard let sources, sources.fits(membership.count) else { return wordNames }
        var used = Set<String>()
        var named = [String?](repeating: nil, count: wordNames.count)
        for cluster in wordNames.indices {
            let mine = membership.indices.filter { membership[$0] == cluster }
            let rest = membership.indices.filter { membership[$0] != cluster }
            // A cluster is named by the document 40% of it comes from, with twice the passages of the next (5.7): k-means
            // splits a household library of ten documents into two clusters, neither of them half one document.
            if let name = sourceName(indices: mine, otherIndices: rest, sources: sources, used: used, minimumShare: 0.4) {
                named[cluster] = name
                used.insert(name)
            }
        }
        return wordNames.indices.map { cluster in
            if let name = named[cluster] { return name }
            var name = wordNames[cluster]
            var counter = 2
            while used.contains(name) {
                name = "\(wordNames[cluster]) \(counter)"
                counter += 1
            }
            used.insert(name)
            return name
        }
    }

    // MARK: - A Map's Axis Labels

    /// The six axis-end labels of a three-dimensional map, in the order x low, x high, y low, y high, z low and z
    /// high (5.7). An end is named by `sources` where the library's structure sets it apart (`sourceName`): the
    /// document, or library, most of its passages come from, else the section heading most of them share. Otherwise it
    /// is named by `axisEnds`, with the words already given to an earlier end left out. No name or word names two ends,
    /// and an axis whose ends do not differ, or an end with nothing that sets it apart, reads "Component N". A library
    /// under four passages has no labels.
    /// Through 5.6 an end with no word of its own drew nothing, and the owner's iPhone showed a map with one axis
    /// blank at one end (2026-10-16). Until 2026-10-20 every end was named by two words, so a household library's axis
    /// ran from "Air & Fryer", two words of one product's name. Pure, for use off the main actor.
    public static func axisLabels(
        coords: [SIMD3<Float>], texts: [String], passageTerms: [Set<String>]? = nil, sources: PassageSources? = nil
    ) -> [String] {
        guard coords.count == texts.count, !coords.isEmpty else { return Array(repeating: "", count: 6) }
        let allTerms = passageTerms ?? texts.map { terms(in: $0) }
        let structure = sources.flatMap { $0.fits(texts.count) ? $0 : nil }
        var usedWords = Set<String>()
        var usedNames = Set<String>()
        var labels: [String] = []
        for (axis, values) in [coords.map(\.x), coords.map(\.y), coords.map(\.z)].enumerated() {
            let fallback = "Component \(axis + 1)"
            let ends = axisEnds(values: values, texts: texts, passageTerms: allTerms, excluding: usedWords)
            let indices = endIndices(values: values)
            var pair: [String] = []
            for side in 0..<2 {
                var name: String?
                if let structure, let indices {
                    name = sourceName(
                        indices: side == 0 ? indices.low : indices.high,
                        otherIndices: side == 0 ? indices.high : indices.low,
                        sources: structure, used: usedNames.union(pair))
                }
                let words = (side == 0 ? ends?.low : ends?.high) ?? []
                if name == nil, !words.isEmpty {
                    let label = formatTerms(words)
                    if !usedNames.contains(label), !pair.contains(label) { name = label }
                }
                pair.append(name ?? fallback)
            }
            usedWords.formUnion(ends?.low ?? [])
            usedWords.formUnion(ends?.high ?? [])
            usedNames.formUnion(pair)
            labels += pair
        }
        return labels
    }

    // MARK: - Embedding Clustering (Deterministic K-Means)

    /// Computes default cluster count k from sample size:
    /// 1 below 12 passages, otherwise between 2 and 6, about one cluster per 1,000 sampled passages.
    public static func defaultK(for sampleSize: Int) -> Int {
        guard sampleSize >= 12 else { return 1 }
        let perThousand = Int(round(Double(sampleSize) / 1000.0))
        return max(2, min(6, perThousand))
    }

    /// Deterministic k-means clustering over passage embeddings.
    /// Initial centres are chosen deterministically (evenly spaced passages in sample order).
    /// Uses Euclidean distance with deterministic tie-breaking (lowest cluster index wins).
    /// Fixed iteration cap prevents infinite looping.
    public static func kMeans(
        embeddings: [[Float]],
        k requestedK: Int? = nil,
        maxIterations: Int = 30
    ) -> [Int] {
        guard !embeddings.isEmpty else { return [] }
        if embeddings.count == 1 { return [0] }

        let targetK = requestedK ?? defaultK(for: embeddings.count)
        let k = max(1, min(targetK, embeddings.count))
        if k == 1 {
            return [Int](repeating: 0, count: embeddings.count)
        }

        let dim = embeddings.first?.count ?? 0
        guard dim > 0 else {
            return [Int](repeating: 0, count: embeddings.count)
        }

        // Evenly spaced passages in sample's order as initial centres
        var centroids = [[Float]]()
        centroids.reserveCapacity(k)
        for c in 0..<k {
            let index = (c * embeddings.count) / k
            centroids.append(embeddings[index])
        }

        var assignments = [Int](repeating: 0, count: embeddings.count)

        func squaredDistance(_ a: [Float], _ b: [Float]) -> Float {
            let count = min(a.count, b.count)
            var sum: Float = 0
            for i in 0..<count {
                let diff = a[i] - b[i]
                sum += diff * diff
            }
            return sum
        }

        for _ in 0..<maxIterations {
            var changed = false

            // 1. Assign each embedding to nearest centroid
            for i in 0..<embeddings.count {
                let vec = embeddings[i]
                var bestCluster = 0
                var bestDistance = Float.greatestFiniteMagnitude

                for c in 0..<k {
                    let dist = squaredDistance(vec, centroids[c])
                    if dist < bestDistance {
                        bestDistance = dist
                        bestCluster = c
                    }
                }

                if assignments[i] != bestCluster {
                    assignments[i] = bestCluster
                    changed = true
                }
            }

            if !changed {
                break
            }

            // 2. Recompute centroids
            var counts = [Int](repeating: 0, count: k)
            var sums = [[Float]](repeating: [Float](repeating: 0, count: dim), count: k)

            for i in 0..<embeddings.count {
                let c = assignments[i]
                counts[c] += 1
                let vec = embeddings[i]
                let vecDim = min(vec.count, dim)
                for d in 0..<vecDim {
                    sums[c][d] += vec[d]
                }
            }

            for c in 0..<k {
                if counts[c] > 0 {
                    let countF = Float(counts[c])
                    for d in 0..<dim {
                        centroids[c][d] = sums[c][d] / countF
                    }
                }
            }
        }

        return assignments
    }
}

/// The languages whose word classes this launch has asked the system for (5.7), so each is waited for once.
nonisolated private final class WordClassRequests: @unchecked Sendable {
    static let shared = WordClassRequests()
    private let lock = NSLock()
    private var asked = Set<String>()

    /// True the first time a language is claimed in this launch.
    func claim(_ code: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return asked.insert(code).inserted
    }
}

/// Resumes a continuation once: from the system's answer or from the end of the wait, whichever comes first.
nonisolated private final class ResumeOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Value) {
        lock.lock()
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume(returning: value)
    }
}
