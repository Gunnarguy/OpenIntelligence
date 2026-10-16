//  LibraryVisualizationEngine.swift
//  OpenIntelligence
//
//  Adaptive visualization intelligence that profiles each library and
//  generates contextually relevant insights and visualization recommendations.
//  Dynamically adjusts when content changes.

import Combine
import Foundation
import SwiftUI

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Library Profile

/// Comprehensive profile of a library's content and usage patterns
struct LibraryProfile: Equatable {
    let containerId: UUID
    let timestamp: Date

    // Content metrics
    let documentCount: Int
    /// The passages this profile was built from.
    let chunkCount: Int
    /// The passages the library holds. More than `chunkCount` when the library is larger than a
    /// map reads at once and the profile was built from an even sample of it.
    let libraryPassageCount: Int
    /// Counted when `chunkCount` is the whole library, and scaled up from the sample otherwise.
    let totalWords: Int
    let avgChunkSize: Int

    // Diversity & structure
    let topicDiversity: Float // 0-1: how varied the content is
    let clusterQuality: Float // Silhouette-like score
    let dominantTopics: [TopicCluster]
    let contentMix: [ContentCategory: Float]

    // Usage patterns
    let retrievalActivity: RetrievalActivity
    let hotChunks: [HotChunk] // Most retrieved
    let coldZones: Int // Chunks never retrieved

    // Temporal
    let recentAdditions: [RecentAddition]
    let libraryAge: TimeInterval

    // Computed properties
    var sizeCategory: LibrarySizeCategory {
        switch documentCount {
        case 0: return .empty
        case 1 ... 3: return .tiny
        case 4 ... 10: return .small
        case 11 ... 50: return .medium
        case 51 ... 200: return .large
        default: return .massive
        }
    }

    var isSampled: Bool {
        libraryPassageCount > chunkCount
    }

    var isHighlyActive: Bool {
        retrievalActivity == .heavy || retrievalActivity == .moderate
    }

    var hasRecentChanges: Bool {
        !recentAdditions.isEmpty
    }

    var isDiverse: Bool {
        topicDiversity > 0.6
    }

    var isFocused: Bool {
        topicDiversity < 0.3 && dominantTopics.count <= 2
    }
}

enum LibrarySizeCategory: String, CaseIterable {
    case empty = "Empty"
    case tiny = "Tiny" // 1-3 docs
    case small = "Small" // 4-10 docs
    case medium = "Medium" // 11-50 docs
    case large = "Large" // 51-200 docs
    case massive = "Massive" // 200+ docs

    var icon: String {
        switch self {
        case .empty: return "folder"
        case .tiny: return "doc.on.doc"
        case .small: return "square.stack"
        case .medium: return "square.stack.3d.up"
        case .large: return "building.columns"
        case .massive: return "globe"
        }
    }
}

enum RetrievalActivity: String, CaseIterable {
    case none = "No queries yet"
    case light = "Light usage"
    case moderate = "Moderate usage"
    case heavy = "Heavy usage"

    var icon: String {
        switch self {
        case .none: return "zzz"
        case .light: return "flame"
        case .moderate: return "flame.fill"
        case .heavy: return "bolt.fill"
        }
    }

    var color: Color {
        switch self {
        case .none: return .secondary
        case .light: return .blue
        case .moderate: return .orange
        case .heavy: return .red
        }
    }
}

nonisolated enum ContentCategory: String, CaseIterable, Identifiable, Sendable {
    case technical = "Technical"
    case legal = "Legal"
    case academic = "Academic"
    case creative = "Creative"
    case business = "Business"
    case reference = "Reference"
    case mixed = "Mixed"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .technical: return "cpu"
        case .legal: return "scale.3d"
        case .academic: return "graduationcap"
        case .creative: return "paintbrush"
        case .business: return "briefcase"
        case .reference: return "books.vertical"
        case .mixed: return "square.stack.3d.down.right"
        }
    }

    var color: Color {
        switch self {
        case .technical: return .blue
        case .legal: return .purple
        case .academic: return .green
        case .creative: return .orange
        case .business: return .indigo
        case .reference: return .teal
        case .mixed: return .gray
        }
    }

    /// A passage's category from its words (`AtlasLabeling.terms(in:)`) and its keywords, tried in this order. Whole
    /// words: through 5.6 each word was searched for inside the passage's text, so "api" matched "capital", "code"
    /// matched "barcode" and "data" matched "metadata", and a passage that held none of the words was searched 29
    /// times, which took 3.5 s for 6,000 such passages on the main thread (a Mac, built -O, 2026-10-15). Because a
    /// whole word no longer matches inside a longer one, the lists carry the plurals and the longer words the old
    /// search caught on purpose ("database", "researchers", "marketing"). A word glued into an identifier, such as
    /// `apiClient`, no longer counts.
    static func of(terms: Set<String>, keywords: [String]) -> ContentCategory {
        let keywordSet = Set(keywords.map { $0.lowercased() })
        if technicalWords.contains(where: { terms.contains($0) || keywordSet.contains($0) }) { return .technical }
        if legalWords.contains(where: { terms.contains($0) }) { return .legal }
        if academicWords.contains(where: { terms.contains($0) }) { return .academic }
        if businessWords.contains(where: { terms.contains($0) }) { return .business }
        return .mixed
    }

    private static let technicalWords = [
        "api", "apis", "function", "functions", "functional", "code", "codes", "codebase", "coding", "algorithm",
        "algorithms", "algorithmic", "implementation", "implementations", "software", "system", "systems", "data",
        "database", "databases", "dataset", "datasets",
    ]
    private static let legalWords = [
        "agreement", "agreements", "contract", "contracts", "contractual", "liability", "liabilities", "terms",
        "hereby", "pursuant", "clause", "clauses",
    ]
    private static let academicWords = [
        "research", "researcher", "researchers", "researched", "study", "studies", "hypothesis", "hypotheses",
        "methodology", "methodologies", "findings", "abstract", "abstracts", "conclusion", "conclusions",
    ]
    private static let businessWords = [
        "revenue", "revenues", "market", "markets", "marketing", "strategy", "strategies", "strategic", "growth",
        "stakeholder", "stakeholders", "roi", "kpi", "kpis",
    ]
}

struct TopicCluster: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let keywords: [String]
    let chunkCount: Int
    let percentage: Float
    let color: Color
    let representativeSnippet: String
    let chunkIds: Set<UUID>

    init(
        name: String,
        keywords: [String],
        chunkCount: Int,
        percentage: Float,
        color: Color,
        representativeSnippet: String,
        chunkIds: Set<UUID> = []
    ) {
        self.name = name
        self.keywords = keywords
        self.chunkCount = chunkCount
        self.percentage = percentage
        self.color = color
        self.representativeSnippet = representativeSnippet
        self.chunkIds = chunkIds
    }
}

struct HotChunk: Identifiable, Equatable {
    let id: UUID
    let documentName: String
    let snippet: String
    let retrievalCount: Int
    let avgSimilarity: Float
    let lastAccessed: Date
}

struct RecentAddition: Identifiable, Equatable {
    let id: UUID
    let documentName: String
    let addedAt: Date
    let chunkCount: Int
    let integrationScore: Float // How well it fits with existing content
    let nearestTopics: [String]
}

// MARK: - Visualization Recommendations

/// A visualization insight card that the engine recommends showing
struct VisualizationInsight: Identifiable, Equatable {
    let id = UUID()
    let type: InsightType
    let priority: InsightPriority
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: InsightAction
    let metrics: [InsightMetric]

    enum InsightType: String, CaseIterable {
        case topicMap // Show topic distribution
        case documentNetwork // Show doc relationships
        case retrievalHotspots // Show retrieval patterns
        case newContentFit // Show how new content integrates
        case clusterHealth // Show clustering quality
        case coverageGaps // Show under-utilized content
        case focusedLibrary // Highlight focused nature
        case diverseLibrary // Highlight diversity
        case anchorDocument // Show most-retrieved doc
        case growthTrend // Show library growth over time
    }

    enum InsightPriority: Int, Comparable {
        case critical = 0
        case high = 1
        case medium = 2
        case low = 3

        static func < (lhs: InsightPriority, rhs: InsightPriority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    enum InsightAction {
        case showTopicMap
        case showDocumentGraph
        case showRetrievalChart
        case showClusterView
        case showEmbedding3D
        case showTimeline
        case showHeatmap
        case expandDetail
    }

    struct InsightMetric: Identifiable, Equatable {
        let id = UUID()
        let label: String
        let value: String
        let trend: Trend?

        enum Trend: Equatable {
            case up(String)
            case down(String)
            case stable
        }
    }
}

// MARK: - Phase 2.15 Interactive Visualization Types

/// Edge between two documents with similarity weight
struct DocumentEdge: Identifiable {
    let id = UUID()
    let sourceIndex: Int
    let targetIndex: Int
    let similarity: Float
}

/// Node for force-directed document graph
struct DocumentNode: Identifiable {
    let id: UUID
    let name: String
    let chunkCount: Int
    var position: CGPoint
    let color: Color
}

/// Result of a chunk similarity matrix computation
struct SimilarityMatrix {
    let labels: [String]
    let values: [[Float]]
    let chunkIDs: [UUID]
}

/// Inspectable chunk detail for tap-to-inspect
struct ChunkDetail: Identifiable {
    let id: UUID
    let documentName: String
    let snippet: String
    let chunkIndex: Int
    let totalChunks: Int
    let wordCount: Int
    let topKeywords: [String]
    let embedding: [Float]?
}

/// Time-series snapshot for animation
struct EmbeddingSnapshot: Identifiable {
    let id = UUID()
    let date: Date
    let pointIndex: Int
    let documentName: String
}

// MARK: - Library Visualization Engine

@MainActor
final class LibraryVisualizationEngine: ObservableObject {
    static let shared = LibraryVisualizationEngine()

    @Published private(set) var currentProfile: LibraryProfile?
    @Published private(set) var insights: [VisualizationInsight] = []
    @Published private(set) var recommendedViews: [RecommendedView] = []
    @Published private(set) var isAnalyzing = false
    @Published private(set) var lastAnalyzed: Date?

    private var analysisTask: Task<Void, Never>?
    private var profileCache: [UUID: LibraryProfile] = [:]

    struct RecommendedView: Identifiable, Equatable {
        let id = UUID()
        let type: ViewType
        let title: String
        let reason: String
        let relevanceScore: Float

        enum ViewType: String, CaseIterable {
            case topicCloud = "Topic Cloud"
            case embedding3D = "3D Embedding Map"
            case documentGraph = "Document Network"
            case retrievalFlow = "Retrieval Flow"
            case clusterView = "Cluster Analysis"
            case timelineView = "Growth Timeline"
            case heatmap = "Similarity Heatmap"
            case contentBreakdown = "Content Breakdown"
        }
    }

    private init() {}

    // MARK: - Cache Management

    /// Invalidate cached profile to force rebuild with latest settings
    func invalidateCache() {
        currentProfile = nil
        profileCache.removeAll()
        insights = []
        recommendedViews = []
        lastAnalyzed = nil
        Log.info("LibraryVisualizationEngine cache invalidated", category: .initialization)
    }

    /// Invalidate cache for specific container
    func invalidateCache(for containerId: UUID) {
        profileCache.removeValue(forKey: containerId)
        if currentProfile?.containerId == containerId {
            currentProfile = nil
        }
    }

    // MARK: - Analysis

    /// Analyze a library and generate profile + insights.
    /// `libraryPassageCount` is how many passages the library holds when `chunks` is a sample of
    /// it (`RAGService.allChunksForActiveContainer()` returns one for a very large library).
    func analyze(
        containerId: UUID,
        documents: [Document],
        chunks: [DocumentChunk],
        retrievalHistory: [RetrievalLogEntry],
        libraryPassageCount: Int? = nil
    ) async {
        analysisTask?.cancel()

        analysisTask = Task {
            await MainActor.run { isAnalyzing = true }

            // Build comprehensive profile
            let profile = await buildProfile(
                containerId: containerId,
                documents: documents,
                chunks: chunks,
                retrievalHistory: retrievalHistory,
                libraryPassageCount: libraryPassageCount
            )

            if Task.isCancelled { return }

            // Generate insights based on profile
            let generatedInsights = generateInsights(from: profile)

            // Recommend visualizations
            let recommended = recommendViews(for: profile)

            await MainActor.run {
                self.currentProfile = profile
                self.insights = generatedInsights
                self.recommendedViews = recommended
                self.profileCache[containerId] = profile
                self.lastAnalyzed = Date()
                self.isAnalyzing = false
            }
        }
    }

    // MARK: - Profile Building

    private func buildProfile(
        containerId: UUID,
        documents: [Document],
        chunks: [DocumentChunk],
        retrievalHistory: [RetrievalLogEntry],
        libraryPassageCount: Int? = nil
    ) async -> LibraryProfile {
        // Basic metrics
        let docCount = documents.count
        let chunkCount = chunks.count
        let libraryCount = max(libraryPassageCount ?? chunkCount, chunkCount)
        let countedWords = chunks.reduce(0) { $0 + $1.metadata.wordCount }
        let avgChunkSize = chunkCount > 0 ? countedWords / chunkCount : 0
        // The same number when every passage was read; an estimate when `chunks` is a sample.
        let totalWords =
            libraryCount > chunkCount
            ? Int(Double(countedWords) * Double(libraryCount) / Double(chunkCount)) : countedWords

        // The work for each passage runs off the main actor: clustering the vectors, splitting each passage into
        // words, naming the clusters and sorting each passage into a content category. Only plain arrays cross.
        let embeddings = chunks.map { $0.embedding }
        let texts = chunks.map { $0.content }
        let keywords = chunks.map { $0.metadata.keywords }
        let passages = await Task.detached(priority: .userInitiated) {
            Self.analyzePassages(embeddings: embeddings, texts: texts, keywords: keywords)
        }.value

        // Topic analysis
        let (topics, diversity) = topicClusters(chunks: chunks, passages: passages)

        // Content categorization
        let contentMix = Self.contentMix(passages.categories)

        // Retrieval analysis
        let (activity, hotChunks, coldZones) = analyzeRetrieval(
            chunks: chunks,
            history: retrievalHistory
        )

        // Recent additions
        let recentAdditions = findRecentAdditions(
            documents: documents,
            chunks: chunks,
            allChunks: chunks
        )

        // Library age
        let oldestDoc = documents.min { $0.addedAt < $1.addedAt }
        let libraryAge = oldestDoc.map { Date().timeIntervalSince($0.addedAt) } ?? 0

        // Cluster quality (simplified silhouette approximation)
        let clusterQuality = estimateClusterQuality(chunks: chunks, topics: topics)

        return LibraryProfile(
            containerId: containerId,
            timestamp: Date(),
            documentCount: docCount,
            chunkCount: chunkCount,
            libraryPassageCount: libraryCount,
            totalWords: totalWords,
            avgChunkSize: avgChunkSize,
            topicDiversity: diversity,
            clusterQuality: clusterQuality,
            dominantTopics: topics,
            contentMix: contentMix,
            retrievalActivity: activity,
            hotChunks: hotChunks,
            coldZones: coldZones,
            recentAdditions: recentAdditions,
            libraryAge: libraryAge
        )
    }

    /// What the Atlas works out for each passage, computed off the main actor (`analyzePassages`).
    nonisolated struct PassageAnalysis: Sendable {
        /// The cluster of each passage, in the order of the passages.
        let clusterMembership: [Int]
        /// For each cluster, the words that set it apart from the others.
        let distinguishingTerms: [[String]]
        let clusterNames: [String]
        /// The content category of each passage, in the order of the passages.
        let categories: [ContentCategory]
    }

    /// Clusters the passages' vectors, splits each passage into words, names the clusters and sorts each passage into a
    /// content category. Pure, and run off the main actor.
    nonisolated private static func analyzePassages(
        embeddings: [[Float]], texts: [String], keywords: [[String]]
    ) -> PassageAnalysis {
        let terms = texts.map { AtlasLabeling.terms(in: $0) }
        let membership = AtlasLabeling.kMeans(embeddings: embeddings)
        let k = (membership.max() ?? -1) + 1
        var groupTerms = Array(repeating: [Set<String>](), count: k)
        for (index, cluster) in membership.enumerated() where cluster >= 0 && cluster < k {
            groupTerms[cluster].append(terms[index])
        }
        let distinguishing = AtlasLabeling.distinguishingTerms(passageTerms: groupTerms, allPassageTerms: terms)
        let names = AtlasLabeling.clusterNames(distinguishingTerms: distinguishing)
        let categories = terms.indices.map { index in
            ContentCategory.of(terms: terms[index], keywords: index < keywords.count ? keywords[index] : [])
        }
        return PassageAnalysis(
            clusterMembership: membership, distinguishingTerms: distinguishing, clusterNames: names,
            categories: categories)
    }

    private func topicClusters(chunks: [DocumentChunk], passages: PassageAnalysis) -> ([TopicCluster], Float) {
        guard !chunks.isEmpty, passages.clusterMembership.count == chunks.count else { return ([], 0) }

        let k = passages.clusterNames.count
        var indicesByCluster = Array(repeating: [Int](), count: k)
        for (index, cluster) in passages.clusterMembership.enumerated() where cluster >= 0 && cluster < k {
            indicesByCluster[cluster].append(index)
        }

        let palette: [Color] = [.blue, .purple, .green, .orange, .pink, .teal]
        var topicClusters: [TopicCluster] = []

        for c in 0 ..< k {
            let chunkIndicesInCluster = indicesByCluster[c]
            guard let firstIdx = chunkIndicesInCluster.first else { continue }
            let clusterChunkIds = Set(chunkIndicesInCluster.map { chunks[$0].id })
            let kw = c < passages.distinguishingTerms.count ? Array(passages.distinguishingTerms[c].prefix(5)) : []
            let snippet = chunks[firstIdx].content.prefix(100).trimmingCharacters(in: .whitespacesAndNewlines)

            topicClusters.append(TopicCluster(
                name: passages.clusterNames[c],
                keywords: kw,
                chunkCount: clusterChunkIds.count,
                percentage: Float(clusterChunkIds.count) / Float(max(chunks.count, 1)),
                color: palette[c % palette.count],
                representativeSnippet: String(snippet),
                chunkIds: clusterChunkIds
            ))
        }

        // Calculate diversity (entropy-based)
        let percentages = topicClusters.map { $0.percentage }
        let diversity = calculateEntropy(percentages)

        return (topicClusters, diversity)
    }

    private func calculateEntropy(_ distribution: [Float]) -> Float {
        guard !distribution.isEmpty else { return 0 }
        let total = distribution.reduce(0, +)
        guard total > 0 else { return 0 }

        var entropy: Float = 0
        for p in distribution {
            let normalized = p / total
            if normalized > 0 {
                entropy -= normalized * log2(normalized)
            }
        }

        // Normalize to 0-1
        let maxEntropy = log2(Float(distribution.count))
        return maxEntropy > 0 ? entropy / maxEntropy : 0
    }

    private static func contentMix(_ categories: [ContentCategory]) -> [ContentCategory: Float] {
        guard !categories.isEmpty else { return [:] }

        var categoryCounts: [ContentCategory: Int] = [:]
        for category in categories {
            categoryCounts[category, default: 0] += 1
        }

        let total = Float(categories.count)
        var mix: [ContentCategory: Float] = [:]
        for (cat, count) in categoryCounts {
            mix[cat] = Float(count) / total
        }

        return mix
    }

    private func analyzeRetrieval(
        chunks: [DocumentChunk],
        history: [RetrievalLogEntry]
    ) -> (RetrievalActivity, [HotChunk], Int) {
        guard !chunks.isEmpty else { return (.none, [], 0) }

        // Count retrievals per chunk
        var chunkRetrievals: [UUID: (count: Int, similarities: [Float], lastAccessed: Date, docName: String)] = [:]

        for entry in history {
            for retrieved in entry.chunks {
                let chunkId = retrieved.chunk.id
                var data = chunkRetrievals[chunkId] ?? (0, [], Date.distantPast, retrieved.sourceDocument)
                data.count += 1
                data.similarities.append(retrieved.similarityScore)
                if entry.timestamp > data.lastAccessed {
                    data.lastAccessed = entry.timestamp
                }
                chunkRetrievals[chunkId] = data
            }
        }

        // Determine activity level
        let totalRetrievals = chunkRetrievals.values.reduce(0) { $0 + $1.count }
        let activity: RetrievalActivity
        switch totalRetrievals {
        case 0: activity = .none
        case 1 ... 20: activity = .light
        case 21 ... 100: activity = .moderate
        default: activity = .heavy
        }

        // Find hot chunks
        let hotChunks = chunkRetrievals
            .sorted { $0.value.count > $1.value.count }
            .prefix(5)
            .compactMap { chunkId, data -> HotChunk? in
                guard let chunk = chunks.first(where: { $0.id == chunkId }) else { return nil }
                let avgSim = data.similarities.isEmpty ? 0 : data.similarities.reduce(0, +) / Float(data.similarities.count)
                return HotChunk(
                    id: chunkId,
                    documentName: data.docName,
                    snippet: String(chunk.content.prefix(80)),
                    retrievalCount: data.count,
                    avgSimilarity: avgSim,
                    lastAccessed: data.lastAccessed
                )
            }

        // Count cold zones
        let retrievedChunkIds = Set(chunkRetrievals.keys)
        let coldZones = chunks.filter { !retrievedChunkIds.contains($0.id) }.count

        return (activity, Array(hotChunks), coldZones)
    }

    private func findRecentAdditions(
        documents: [Document],
        chunks: [DocumentChunk],
        allChunks: [DocumentChunk]
    ) -> [RecentAddition] {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60) // Last 7 days

        let recentDocs = documents.filter { $0.addedAt > cutoff }

        return recentDocs.prefix(5).map { doc in
            let docChunks = chunks.filter { $0.documentId == doc.id }

            // Calculate integration score (how similar to existing content)
            let integrationScore = calculateIntegrationScore(
                newChunks: docChunks,
                existingChunks: allChunks.filter { $0.documentId != doc.id }
            )

            // Find nearest topics
            let nearestTopics = findNearestTopics(for: docChunks, in: allChunks)

            return RecentAddition(
                id: doc.id,
                documentName: doc.filename,
                addedAt: doc.addedAt,
                chunkCount: docChunks.count,
                integrationScore: integrationScore,
                nearestTopics: nearestTopics
            )
        }
    }

    private func calculateIntegrationScore(
        newChunks: [DocumentChunk],
        existingChunks: [DocumentChunk]
    ) -> Float {
        guard !newChunks.isEmpty, !existingChunks.isEmpty else { return 0.5 }

        // Sample similarity between new and existing
        var totalSim: Float = 0
        var count = 0

        for newChunk in newChunks.prefix(10) {
            for existingChunk in existingChunks.prefix(50) {
                let sim = cosineSimilarity(newChunk.embedding, existingChunk.embedding)
                totalSim += sim
                count += 1
            }
        }

        return count > 0 ? totalSim / Float(count) : 0.5
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0 ..< a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }

    private func findNearestTopics(for chunks: [DocumentChunk], in allChunks: [DocumentChunk]) -> [String] {
        // Extract keywords from chunks and find overlapping topics
        let newKeywords = Set(chunks.flatMap { $0.metadata.keywords.map { $0.lowercased() } })

        var topicMatches: [String: Int] = [:]
        for chunk in allChunks {
            for keyword in chunk.metadata.keywords {
                let normalized = keyword.lowercased()
                if newKeywords.contains(normalized) {
                    topicMatches[keyword.capitalized, default: 0] += 1
                }
            }
        }

        return topicMatches
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key }
    }

    private func estimateClusterQuality(chunks: [DocumentChunk], topics: [TopicCluster]) -> Float {
        guard chunks.count > 10, topics.count > 1 else { return 0.5 }

        // Simplified: use topic distribution evenness as proxy
        let percentages = topics.map { $0.percentage }
        let variance = calculateVariance(percentages)

        // Lower variance = more even distribution = higher quality
        return max(0, 1 - variance * 4)
    }

    private func calculateVariance(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Float(values.count)
        let squaredDiffs = values.map { ($0 - mean) * ($0 - mean) }
        return squaredDiffs.reduce(0, +) / Float(values.count)
    }

    // MARK: - Insight Generation

    private func generateInsights(from profile: LibraryProfile) -> [VisualizationInsight] {
        var insights: [VisualizationInsight] = []

        // Empty library
        if profile.documentCount == 0 {
            insights.append(VisualizationInsight(
                type: .coverageGaps,
                priority: .critical,
                title: "Empty Library",
                subtitle: "Add documents to start building your knowledge base",
                icon: "doc.badge.plus",
                color: .secondary,
                action: .expandDetail,
                metrics: []
            ))
            return insights
        }

        // A library larger than a map reads at once is drawn from an even sample. Say so first.
        if profile.isSampled {
            insights.append(VisualizationInsight(
                type: .coverageGaps,
                priority: .critical,
                title: "Mapped from a sample",
                subtitle:
                    "This library holds \(profile.libraryPassageCount.formatted()) passages. The map is drawn from \(profile.chunkCount.formatted()) of them, taken evenly across the library, and its word count is an estimate.",
                icon: "square.stack.3d.up",
                color: .secondary,
                action: .expandDetail,
                metrics: [
                    .init(label: "In the library", value: profile.libraryPassageCount.formatted(), trend: nil),
                    .init(label: "On the map", value: profile.chunkCount.formatted(), trend: nil),
                ]
            ))
        }

        // Recent additions - high priority if present
        if let addition = profile.recentAdditions.first {
            let fitDescription = addition.integrationScore > 0.7 ? "fits well" :
                addition.integrationScore > 0.4 ? "partially related" : "explores new territory"

            insights.append(VisualizationInsight(
                type: .newContentFit,
                priority: .high,
                title: "New Content Integration",
                subtitle: "\(addition.documentName) \(fitDescription) with your library",
                icon: "sparkles",
                color: .yellow,
                action: .showClusterView,
                metrics: [
                    .init(label: "Fit Score", value: String(format: "%.0f%%", addition.integrationScore * 100), trend: nil),
                    .init(label: "Chunks", value: "\(addition.chunkCount)", trend: nil),
                    .init(label: "Near Topics", value: addition.nearestTopics.first ?? "General", trend: nil),
                ]
            ))
        }

        // Topic distribution - for diverse libraries
        if profile.isDiverse && profile.dominantTopics.count >= 2, let topTopic = profile.dominantTopics.first {
            insights.append(VisualizationInsight(
                type: .topicMap,
                priority: .medium,
                title: "Diverse Knowledge Base",
                subtitle: "\(profile.dominantTopics.count) distinct topic clusters detected",
                icon: "circle.hexagongrid.fill",
                color: .purple,
                action: .showTopicMap,
                metrics: [
                    .init(label: "Top Topic", value: topTopic.name, trend: nil),
                    .init(label: "Coverage", value: String(format: "%.0f%%", topTopic.percentage * 100), trend: nil),
                    .init(label: "Diversity", value: String(format: "%.0f%%", profile.topicDiversity * 100), trend: nil),
                ]
            ))
        }

        // Focused library
        if profile.isFocused, let topic = profile.dominantTopics.first {
            insights.append(VisualizationInsight(
                type: .focusedLibrary,
                priority: .medium,
                title: "Focused Library",
                subtitle: "Content centers around \(topic.name)",
                icon: "scope",
                color: .blue,
                action: .showEmbedding3D,
                metrics: [
                    .init(label: "Focus Area", value: topic.name, trend: nil),
                    .init(label: "Concentration", value: String(format: "%.0f%%", topic.percentage * 100), trend: nil),
                ]
            ))
        }

        // Retrieval hotspots - for active libraries
        if profile.isHighlyActive, let topChunk = profile.hotChunks.first {
            insights.append(VisualizationInsight(
                type: .retrievalHotspots,
                priority: .high,
                title: "Retrieval Hotspots",
                subtitle: "\(topChunk.documentName) is your most-referenced source",
                icon: "flame.fill",
                color: .orange,
                action: .showRetrievalChart,
                metrics: [
                    .init(label: "Top Retrievals", value: "\(topChunk.retrievalCount)", trend: nil),
                    .init(label: "Avg Similarity", value: String(format: "%.2f", topChunk.avgSimilarity), trend: nil),
                    .init(label: "Cold Chunks", value: "\(profile.coldZones)", trend: nil),
                ]
            ))
        }

        // Anchor document
        if let topChunk = profile.hotChunks.first, topChunk.retrievalCount > 5 {
            insights.append(VisualizationInsight(
                type: .anchorDocument,
                priority: .medium,
                title: "Anchor Document",
                subtitle: "\(topChunk.documentName) grounds most of your queries",
                icon: "bookmark.fill",
                color: .green,
                action: .showRetrievalChart,
                metrics: [
                    .init(label: "Hit Rate", value: "\(topChunk.retrievalCount)×", trend: nil),
                ]
            ))
        }

        // Coverage gaps
        if profile.coldZones > profile.chunkCount / 2 {
            let unusedPct = Float(profile.coldZones) / Float(max(profile.chunkCount, 1)) * 100
            insights.append(VisualizationInsight(
                type: .coverageGaps,
                priority: .low,
                title: "Untapped Knowledge",
                subtitle: "\(Int(unusedPct))% of your library hasn't been retrieved yet",
                icon: "eye.slash",
                color: .secondary,
                action: .showHeatmap,
                metrics: [
                    .init(label: "Unused Chunks", value: "\(profile.coldZones)", trend: nil),
                    .init(label: "Total Chunks", value: "\(profile.chunkCount)", trend: nil),
                ]
            ))
        }

        // Cluster health for medium+ libraries
        if profile.sizeCategory.rawValue >= LibrarySizeCategory.medium.rawValue {
            let quality = profile.clusterQuality
            let qualityLabel = quality > 0.7 ? "Excellent" : quality > 0.4 ? "Good" : "Mixed"

            insights.append(VisualizationInsight(
                type: .clusterHealth,
                priority: .low,
                title: "Semantic Structure",
                subtitle: "\(qualityLabel) clustering of \(profile.chunkCount) chunks",
                icon: "circle.hexagonpath.fill",
                color: quality > 0.6 ? .green : .orange,
                action: .showClusterView,
                metrics: [
                    .init(label: "Quality", value: qualityLabel, trend: nil),
                    .init(label: "Topics", value: "\(profile.dominantTopics.count)", trend: nil),
                ]
            ))
        }

        // Document network for small libraries
        if profile.sizeCategory == .tiny || profile.sizeCategory == .small {
            insights.append(VisualizationInsight(
                type: .documentNetwork,
                priority: .medium,
                title: "Document Relationships",
                subtitle: "See how your \(profile.documentCount) documents connect",
                icon: "point.3.connected.trianglepath.dotted",
                color: .teal,
                action: .showDocumentGraph,
                metrics: [
                    .init(label: "Documents", value: "\(profile.documentCount)", trend: nil),
                    .init(label: "Chunks", value: "\(profile.chunkCount)", trend: nil),
                ]
            ))
        }

        // Sort by priority
        insights.sort { $0.priority < $1.priority }

        return insights
    }

    // MARK: - View Recommendations

    private func recommendViews(for profile: LibraryProfile) -> [RecommendedView] {
        var views: [RecommendedView] = []

        // Always recommend content breakdown
        views.append(RecommendedView(
            type: .contentBreakdown,
            title: "Content Overview",
            reason: "See what's in your library at a glance",
            relevanceScore: 0.9
        ))

        // Topic cloud for diverse libraries
        if profile.isDiverse {
            views.append(RecommendedView(
                type: .topicCloud,
                title: "Topic Cloud",
                reason: "Your library spans multiple themes",
                relevanceScore: 0.95
            ))
        }

        // 3D embedding for medium+ libraries
        if profile.chunkCount >= 50 {
            views.append(RecommendedView(
                type: .embedding3D,
                title: "3D Semantic Map",
                reason: "Explore \(profile.chunkCount) chunks in 3D space",
                relevanceScore: Float(min(profile.chunkCount, 500)) / 500.0
            ))
        }

        // Document graph for small libraries
        if profile.documentCount > 1, profile.documentCount <= 15 {
            views.append(RecommendedView(
                type: .documentGraph,
                title: "Document Network",
                reason: "See how \(profile.documentCount) documents relate",
                relevanceScore: 0.85
            ))
        }

        // Retrieval flow for active libraries
        if profile.isHighlyActive {
            views.append(RecommendedView(
                type: .retrievalFlow,
                title: "Retrieval Flow",
                reason: "Track your query patterns",
                relevanceScore: 0.9
            ))
        }

        // Cluster view for clustered content
        if profile.dominantTopics.count >= 2 {
            views.append(RecommendedView(
                type: .clusterView,
                title: "Cluster Analysis",
                reason: "\(profile.dominantTopics.count) topic clusters detected",
                relevanceScore: profile.clusterQuality
            ))
        }

        // Heatmap for large libraries
        if profile.chunkCount >= 100 {
            views.append(RecommendedView(
                type: .heatmap,
                title: "Similarity Heatmap",
                reason: "Find content overlaps and gaps",
                relevanceScore: 0.7
            ))
        }

        // Sort by relevance
        views.sort { $0.relevanceScore > $1.relevanceScore }

        return views
    }

    // MARK: - Phase 2.15 Interactive Visualization

    /// Compute document-level similarity graph
    /// Returns nodes positioned in a circle and edges for pairs above threshold
    func computeDocumentGraph(
        documents: [Document],
        chunks: [DocumentChunk],
        threshold: Float = 0.3
    ) -> (nodes: [DocumentNode], edges: [DocumentEdge]) {
        guard documents.count >= 2 else { return ([], []) }

        let allChunks = chunks

        // Compute average embedding per document
        var docEmbeddings: [(id: UUID, name: String, count: Int, embedding: [Float])] = []

        for doc in documents {
            let chunks = allChunks.filter { $0.documentId == doc.id }
            let embeddings = chunks.compactMap { $0.embedding.isEmpty ? nil : $0.embedding }
            guard !embeddings.isEmpty else { continue }

            let dim = embeddings[0].count
            var avg = [Float](repeating: 0, count: dim)
            for emb in embeddings {
                for i in 0..<min(dim, emb.count) {
                    avg[i] += emb[i]
                }
            }
            let scale = 1.0 / Float(embeddings.count)
            for i in 0..<dim { avg[i] *= scale }

            docEmbeddings.append((id: doc.id, name: doc.filename, count: chunks.count, embedding: avg))
        }

        // Build nodes with circular initial positions
        let palette: [Color] = [.blue, .purple, .orange, .green, .red, .cyan, .pink, .yellow, .mint, .teal]
        var nodes: [DocumentNode] = []
        for (i, doc) in docEmbeddings.enumerated() {
            let angle = Double(i) / Double(docEmbeddings.count) * 2.0 * .pi
            let radius = 120.0
            let pos = CGPoint(x: 200 + radius * cos(angle), y: 200 + radius * sin(angle))
            nodes.append(DocumentNode(
                id: doc.id,
                name: doc.name,
                chunkCount: doc.count,
                position: pos,
                color: palette[i % palette.count]
            ))
        }

        // Compute pairwise cosine similarity → edges
        var edges: [DocumentEdge] = []
        for i in 0..<docEmbeddings.count {
            for j in (i + 1)..<docEmbeddings.count {
                let sim = Self.cosineSim(docEmbeddings[i].embedding, docEmbeddings[j].embedding)
                if sim >= threshold {
                    edges.append(DocumentEdge(sourceIndex: i, targetIndex: j, similarity: sim))
                }
            }
        }

        return (nodes, edges)
    }

    /// Compute chunk similarity matrix (sampled for performance)
    func computeSimilarityMatrix(
        chunks: [DocumentChunk],
        sampleSize: Int = 20
    ) -> SimilarityMatrix? {
        let allChunks = chunks
        guard allChunks.count >= 2 else { return nil }

        // Stratified sample: take chunks from different documents
        let sampled: [DocumentChunk]
        if allChunks.count <= sampleSize {
            sampled = allChunks
        } else {
            // Group by document, take proportionally
            var byDoc: [UUID: [DocumentChunk]] = [:]
            for chunk in allChunks {
                byDoc[chunk.documentId, default: []].append(chunk)
            }
            var result: [DocumentChunk] = []
            let perDoc = max(1, sampleSize / max(1, byDoc.count))
            for (_, chunks) in byDoc {
                let take = min(perDoc, chunks.count)
                let step = max(1, chunks.count / take)
                for i in Swift.stride(from: 0, to: chunks.count, by: step) {
                    if result.count < sampleSize {
                        result.append(chunks[i])
                    }
                }
            }
            sampled = Array(result.prefix(sampleSize))
        }

        let n = sampled.count
        let embeddings = sampled.map { $0.embedding }.filter { !$0.isEmpty }
        guard embeddings.count == n else { return nil }

        // Build labels (truncated chunk text)
        let labels = sampled.map { chunk -> String in
            let text = String(chunk.content.prefix(30))
            return text.count < chunk.content.count ? text + "…" : text
        }

        // Compute pairwise similarity matrix
        var matrix = [[Float]](repeating: [Float](repeating: 0, count: n), count: n)
        for i in 0..<n {
            matrix[i][i] = 1.0
            for j in (i + 1)..<n {
                let sim = Self.cosineSim(embeddings[i], embeddings[j])
                matrix[i][j] = sim
                matrix[j][i] = sim
            }
        }

        let ids = sampled.map { $0.id }
        return SimilarityMatrix(labels: labels, values: matrix, chunkIDs: ids)
    }

    /// Get detail for a specific chunk by index in the projected points array
    func chunkDetail(
        at index: Int,
        chunks: [DocumentChunk],
        documents: [Document]
    ) -> ChunkDetail? {
        let allChunks = chunks
        guard index >= 0, index < allChunks.count else { return nil }

        let chunk = allChunks[index]
        let docChunks = allChunks.filter { $0.documentId == chunk.documentId }
        let docName = documents.first(where: { $0.id == chunk.documentId })?.filename ?? "Unknown"

        // Extract top keywords via simple frequency
        let words = chunk.content.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 }
        let stopWords: Set<String> = [
            "this", "that", "with", "from", "have", "been", "were", "they",
            "their", "will", "would", "could", "should", "about", "which",
            "there", "these", "those", "other", "into", "than", "then",
            "when", "what", "some", "more", "also", "just", "over", "such", "only"
        ]
        var freq: [String: Int] = [:]
        for w in words where !stopWords.contains(w) {
            freq[w, default: 0] += 1
        }
        let sorted = freq.sorted { $0.value > $1.value }
        let topKeywords = Array(sorted.prefix(5).map { $0.key })

        let chunkIndex = docChunks.firstIndex(where: { $0.id == chunk.id }).map { $0 + 1 } ?? 0

        return ChunkDetail(
            id: chunk.id,
            documentName: docName,
            snippet: String(chunk.content.prefix(300)),
            chunkIndex: chunkIndex,
            totalChunks: docChunks.count,
            wordCount: chunk.metadata.wordCount,
            topKeywords: topKeywords,
            embedding: chunk.embedding.isEmpty ? nil : chunk.embedding
        )
    }

    /// Build time-series data for animation (chunks sorted by creation date)
    func buildTimeSeries(
        chunks: [DocumentChunk],
        documents: [Document]
    ) -> [EmbeddingSnapshot] {
        let allChunks = chunks

        var snapshots: [EmbeddingSnapshot] = []
        for (index, chunk) in allChunks.enumerated() {
            let docName = documents.first(where: { $0.id == chunk.documentId })?.filename ?? "Unknown"
            snapshots.append(EmbeddingSnapshot(
                date: chunk.metadata.createdAt,
                pointIndex: index,
                documentName: docName
            ))
        }

        return snapshots.sorted { $0.date < $1.date }
    }

    /// Generate cluster labels using Apple Intelligence
    func generateClusterLabelsWithLLM(clusters: [TopicCluster]) async -> [String: String] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            var labels: [String: String] = [:]
            for cluster in clusters.prefix(10) {
                do {
                    // Built with an explicit model and instructions, not the bare `LanguageModelSession()`.
                    // Every service that used the bare initialiser failed deterministically with
                    // ParsingError / "Session ended without producing a response", while every path built
                    // through `FoundationModelSessionFactory` (which supplies `model:` and `instructions:`)
                    // succeeded. Confirmed on an empty library with the one-word query "Test" and zero
                    // retrieved chunks, which rules out content, guardrails, context size and token caps.
                    // An Instruments capture of the Foundation Models template shows `assets: ""` on exactly
                    // these responses, consistent with a session that never received its model assets.
                    let session = LanguageModelSession(
                        model: SystemLanguageModel.default,
                        instructions: Instructions("You label groups of documents. Be concise.")
                    )
                    let prompt = """
                    Name this document cluster in 2-4 words. Keywords: \(cluster.keywords.prefix(8).joined(separator: ", ")). \
                    Snippet: \(cluster.representativeSnippet.prefix(100)). Reply with ONLY the name.
                    """
                    let response = try await session.respond(to: prompt)
                    let name = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty && name.count < 40 {
                        labels[cluster.name] = name
                    }
                } catch {
                    Log.warning("[LibVizEngine] LLM cluster label failed for \(cluster.name): \(error)", category: .pipeline)
                }
            }
            return labels
        }
        #endif
        return [:]
    }

    // MARK: - Math Utilities

    /// Cosine similarity between two vectors
    static func cosineSim(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }

    /// Apply force-directed layout iterations to document nodes
    static func applyForceLayout(nodes: inout [DocumentNode], edges: [DocumentEdge], iterations: Int = 50) {
        let area: CGFloat = 400 * 400
        let k = sqrt(area / CGFloat(max(1, nodes.count)))

        for iteration in 0..<iterations {
            // Repulsive forces
            var displacements = [CGPoint](repeating: .zero, count: nodes.count)
            for i in 0..<nodes.count {
                for j in (i + 1)..<nodes.count {
                    let dx = nodes[i].position.x - nodes[j].position.x
                    let dy = nodes[i].position.y - nodes[j].position.y
                    let dist = max(sqrt(dx * dx + dy * dy), 0.01)
                    let force = (k * k) / dist
                    let fx = (dx / dist) * force
                    let fy = (dy / dist) * force
                    displacements[i].x += fx
                    displacements[i].y += fy
                    displacements[j].x -= fx
                    displacements[j].y -= fy
                }
            }

            // Attractive forces
            for edge in edges {
                let i = edge.sourceIndex
                let j = edge.targetIndex
                guard i < nodes.count, j < nodes.count else { continue }
                let dx = nodes[j].position.x - nodes[i].position.x
                let dy = nodes[j].position.y - nodes[i].position.y
                let dist = max(sqrt(dx * dx + dy * dy), 0.01)
                let force = (dist * dist) / k * CGFloat(edge.similarity)
                let fx = (dx / dist) * force
                let fy = (dy / dist) * force
                displacements[i].x += fx
                displacements[i].y += fy
                displacements[j].x -= fx
                displacements[j].y -= fy
            }

            // Apply with damping
            let temp = max(1.0, 10.0 - Double(iteration) * 0.2)
            for i in 0..<nodes.count {
                let dx = displacements[i].x
                let dy = displacements[i].y
                let dist = max(sqrt(dx * dx + dy * dy), 0.01)
                let cappedDist = min(dist, CGFloat(temp))
                nodes[i].position.x += (dx / dist) * cappedDist
                nodes[i].position.y += (dy / dist) * cappedDist
                // Keep in bounds
                nodes[i].position.x = max(20, min(380, nodes[i].position.x))
                nodes[i].position.y = max(20, min(380, nodes[i].position.y))
            }
        }
    }
}
