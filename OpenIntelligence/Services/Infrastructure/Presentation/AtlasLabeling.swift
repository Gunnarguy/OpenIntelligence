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
        precomputedTerms: [Set<String>]? = nil
    ) -> [String] {
        guard !texts.isEmpty, texts.count == clusterMembership.count else { return [] }
        let maxCluster = clusterMembership.max() ?? -1
        guard maxCluster >= 0 else { return [] }
        let k = maxCluster + 1

        let allTerms = precomputedTerms ?? texts.map { terms(in: $0) }
        var groupTerms = Array(repeating: [Set<String>](), count: k)
        for (i, c) in clusterMembership.enumerated() {
            if c >= 0 && c < k {
                groupTerms[c].append(allTerms[i])
            }
        }

        let dist = distinguishingTerms(passageTerms: groupTerms, allPassageTerms: allTerms)
        return clusterNames(distinguishingTerms: dist)
    }

    // MARK: - Axis Ends Analysis

    /// For one projection axis, takes the tenth of passages with the lowest value and the tenth with
    /// the highest, and returns the distinguishing terms of each end against the other end (one or two per end),
    /// scored with `contrast` and ranked like a cluster's.
    /// For fewer than 20 passages, uses the lowest and highest two.
    /// Below 4 passages, returns nil.
    /// If neither end has a distinguishing term, returns nil.
    public static func axisEnds(
        values: [Float],
        texts: [String],
        passageTerms: [Set<String>]? = nil
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

        // Sort indices by value ascending, tie-breaking by index for determinism
        let sortedIndices = (0..<totalCount).sorted {
            if values[$0] != values[$1] {
                return values[$0] < values[$1]
            }
            return $0 < $1
        }

        let lowIndices = Array(sortedIndices.prefix(endCount))
        let highIndices = Array(sortedIndices.suffix(endCount))

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

        func distinguishing(
            freq: [String: Int],
            otherFreq: [String: Int],
            count: Int,
            otherCount: Int
        ) -> [String] {
            guard count > 0, bothCount > 0, totalCount > 0 else { return [] }
            var candidates: [(term: String, score: Double, count: Int)] = []

            for term in freq.keys.sorted() {
                let f = freq[term]!
                guard f >= minEndCount else { continue }
                let shareEnd = Double(f) / Double(count)
                guard shareEnd >= minEndShare else { continue }

                // Term common to > 40% of the entire library names nothing
                let aCount = allFreq[term] ?? f
                let shareAll = Double(aCount) / Double(totalCount)
                guard shareAll <= 0.40 else { continue }

                let score = contrast(f, of: count, against: otherFreq[term] ?? 0, of: otherCount)
                guard score > 0 else { continue }

                candidates.append((term: term, score: score, count: f))
            }

            return Array(ranked(candidates).prefix(2))
        }

        let lowDist = distinguishing(freq: lowFreq, otherFreq: highFreq, count: lowCount, otherCount: highCount)
        let highDist = distinguishing(freq: highFreq, otherFreq: lowFreq, count: highCount, otherCount: lowCount)

        if lowDist.isEmpty && highDist.isEmpty {
            return nil
        }

        return AxisEnds(low: lowDist, high: highDist)
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
