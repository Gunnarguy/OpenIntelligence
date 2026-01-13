//  LibraryVisualizationEngine.swift
//  OpenIntelligence
//
//  Adaptive visualization intelligence that profiles each library and
//  generates contextually relevant insights and visualization recommendations.
//  Dynamically adjusts when content changes.

import Combine
import Foundation
import SwiftUI

// MARK: - Library Profile

/// Comprehensive profile of a library's content and usage patterns
struct LibraryProfile: Equatable {
    let containerId: UUID
    let timestamp: Date

    // Content metrics
    let documentCount: Int
    let chunkCount: Int
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

enum ContentCategory: String, CaseIterable, Identifiable {
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
}

struct TopicCluster: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let keywords: [String]
    let chunkCount: Int
    let percentage: Float
    let color: Color
    let representativeSnippet: String
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

    // MARK: - Analysis

    /// Analyze a library and generate profile + insights
    func analyze(
        containerId: UUID,
        documents: [Document],
        chunks: [DocumentChunk],
        retrievalHistory: [RetrievalLogEntry]
    ) async {
        analysisTask?.cancel()

        analysisTask = Task {
            await MainActor.run { isAnalyzing = true }

            // Build comprehensive profile
            let profile = await buildProfile(
                containerId: containerId,
                documents: documents,
                chunks: chunks,
                retrievalHistory: retrievalHistory
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
        retrievalHistory: [RetrievalLogEntry]
    ) async -> LibraryProfile {
        // Basic metrics
        let docCount = documents.count
        let chunkCount = chunks.count
        let totalWords = chunks.reduce(0) { $0 + $1.metadata.wordCount }
        let avgChunkSize = chunkCount > 0 ? totalWords / chunkCount : 0

        // Topic analysis
        let (topics, diversity) = await analyzeTopics(chunks: chunks)

        // Content categorization
        let contentMix = categorizeContent(chunks: chunks)

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

    private func analyzeTopics(chunks: [DocumentChunk]) async -> ([TopicCluster], Float) {
        guard !chunks.isEmpty else { return ([], 0) }

        // Extract keywords from all chunks
        var keywordCounts: [String: Int] = [:]
        var keywordChunks: [String: Set<UUID>] = [:]

        for chunk in chunks {
            for keyword in chunk.metadata.keywords {
                let normalized = keyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                guard normalized.count > 2 else { continue }
                keywordCounts[normalized, default: 0] += 1
                keywordChunks[normalized, default: []].insert(chunk.id)
            }
        }

        // Group into topic clusters using keyword co-occurrence
        let topKeywords = keywordCounts
            .sorted { $0.value > $1.value }
            .prefix(30)
            .map { $0.key }

        // Simple clustering: group keywords that appear in same chunks
        var clusters: [[String]] = []
        var assigned: Set<String> = []

        for keyword in topKeywords where !assigned.contains(keyword) {
            var cluster = [keyword]
            assigned.insert(keyword)

            let keywordChunkSet = keywordChunks[keyword] ?? []

            for otherKeyword in topKeywords where !assigned.contains(otherKeyword) {
                let otherChunkSet = keywordChunks[otherKeyword] ?? []
                let overlap = Float(keywordChunkSet.intersection(otherChunkSet).count)
                let union = Float(keywordChunkSet.union(otherChunkSet).count)
                let jaccard = union > 0 ? overlap / union : 0

                if jaccard > 0.3 {
                    cluster.append(otherKeyword)
                    assigned.insert(otherKeyword)
                }
            }

            clusters.append(cluster)
        }

        // Limit to top 5 clusters
        let topClusters = clusters.sorted { $0.count > $1.count }.prefix(5)

        // Build TopicCluster objects
        let palette: [Color] = [.blue, .purple, .green, .orange, .pink]
        var topicClusters: [TopicCluster] = []

        for (index, clusterKeywords) in topClusters.enumerated() {
            guard !clusterKeywords.isEmpty else { continue }

            // Count chunks in this cluster
            var clusterChunkIds: Set<UUID> = []
            for kw in clusterKeywords {
                clusterChunkIds.formUnion(keywordChunks[kw] ?? [])
            }

            // Find representative snippet
            let representativeChunk = chunks.first { clusterChunkIds.contains($0.id) }
            let snippet = representativeChunk?.content.prefix(100).trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // Generate topic name from top keywords
            let topicName = generateTopicName(from: clusterKeywords)

            topicClusters.append(TopicCluster(
                name: topicName,
                keywords: Array(clusterKeywords.prefix(5)),
                chunkCount: clusterChunkIds.count,
                percentage: Float(clusterChunkIds.count) / Float(max(chunks.count, 1)),
                color: palette[index % palette.count],
                representativeSnippet: String(snippet)
            ))
        }

        // Calculate diversity (entropy-based)
        let percentages = topicClusters.map { $0.percentage }
        let diversity = calculateEntropy(percentages)

        return (topicClusters, diversity)
    }

    private func generateTopicName(from keywords: [String]) -> String {
        guard !keywords.isEmpty else { return "General" }

        // Take top 2-3 keywords and make a readable name
        let top = keywords.prefix(2)
        return top.map { $0.capitalized }.joined(separator: " & ")
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

    private func categorizeContent(chunks: [DocumentChunk]) -> [ContentCategory: Float] {
        guard !chunks.isEmpty else { return [:] }

        var categoryCounts: [ContentCategory: Int] = [:]

        for chunk in chunks {
            let category = detectCategory(chunk: chunk)
            categoryCounts[category, default: 0] += 1
        }

        let total = Float(chunks.count)
        var mix: [ContentCategory: Float] = [:]
        for (cat, count) in categoryCounts {
            mix[cat] = Float(count) / total
        }

        return mix
    }

    private func detectCategory(chunk: DocumentChunk) -> ContentCategory {
        let content = chunk.content.lowercased()
        let keywords = Set(chunk.metadata.keywords.map { $0.lowercased() })

        // Technical indicators
        let techTerms = ["api", "function", "code", "algorithm", "implementation", "software", "system", "data"]
        if techTerms.contains(where: { content.contains($0) || keywords.contains($0) }) {
            return .technical
        }

        // Legal indicators
        let legalTerms = ["agreement", "contract", "liability", "terms", "hereby", "pursuant", "clause"]
        if legalTerms.contains(where: { content.contains($0) }) {
            return .legal
        }

        // Academic indicators
        let academicTerms = ["research", "study", "hypothesis", "methodology", "findings", "abstract", "conclusion"]
        if academicTerms.contains(where: { content.contains($0) }) {
            return .academic
        }

        // Business indicators
        let businessTerms = ["revenue", "market", "strategy", "growth", "stakeholder", "roi", "kpi"]
        if businessTerms.contains(where: { content.contains($0) }) {
            return .business
        }

        return .mixed
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

        // Recent additions - high priority if present
        if !profile.recentAdditions.isEmpty {
            let addition = profile.recentAdditions.first!
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
        if profile.isDiverse && profile.dominantTopics.count >= 2 {
            let topTopic = profile.dominantTopics.first!
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
        if profile.isFocused && !profile.dominantTopics.isEmpty {
            let topic = profile.dominantTopics.first!
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
        if profile.isHighlyActive && !profile.hotChunks.isEmpty {
            let topChunk = profile.hotChunks.first!
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
}
