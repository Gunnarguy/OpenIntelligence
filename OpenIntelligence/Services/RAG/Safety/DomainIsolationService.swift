import Foundation

enum DomainIsolationService {
    enum ScientificDomain: String, CaseIterable, Sendable {
        case inVitro = "IN VITRO"
        case inVitroControl = "IN VITRO CONTROL"
        case inVivo = "IN VIVO"
        case inVivoControl = "IN VIVO CONTROL"
        case clinical = "CLINICAL"
        case clinicalControl = "CLINICAL CONTROL"
        case inSilico = "IN SILICO"
        case generalReference = "GENERAL / UNKNOWN"

        nonisolated var family: ScientificDomain {
            switch self {
            case .inVitro, .inVitroControl:
                return .inVitro
            case .inVivo, .inVivoControl:
                return .inVivo
            case .clinical, .clinicalControl:
                return .clinical
            case .inSilico:
                return .inSilico
            case .generalReference:
                return .generalReference
            }
        }

        nonisolated var isControl: Bool {
            switch self {
            case .inVitroControl, .inVivoControl, .clinicalControl:
                return true
            default:
                return false
            }
        }

        nonisolated var keywords: [String] {
            switch self {
            case .inVitro:
                return [
                    "cell", "cells", "cell line", "primary culture", "organoid", "slice", "tissue slice",
                    "incubation", "culture media", "well plate", "confluence", "passage", "mtt assay",
                    "qpcr", "od reading", "absorbance", "micromolar", "um", "ug/ml", "mg/ml",
                    "neuro 2a", "hela", "293t", "fibroblast", "immunofluorescence"
                ]
            case .inVitroControl:
                return [
                    "vehicle", "untreated", "media only", "control well", "negative control",
                    "positive control", "mock treated", "baseline culture"
                ]
            case .inVivo:
                return [
                    "rat", "rats", "mouse", "mice", "murine", "sprague dawley", "c57bl/6", "zebrafish",
                    "bccao", "xenograft", "mg/kg", "intraperitoneal", "ip", "oral gavage", "po",
                    "iv", "tumor volume", "survival curve", "latency", "probe test", "morris water maze",
                    "novel object recognition", "open field", "sham operated", "animal cohort"
                ]
            case .inVivoControl:
                return [
                    "vehicle group", "sham", "untreated animals", "saline", "control rats", "control mice",
                    "placebo gavage", "parallel cohort"
                ]
            case .clinical:
                return [
                    "participant", "participants", "subjects", "human", "volunteer", "phase i", "phase ii",
                    "phase iii", "trial", "double blind", "randomized", "adverse event", "recist",
                    "progression free survival", "pfs", "orr", "bid", "mg/day", "oral tablet",
                    "iv infusion", "subcutaneous", "case study", "cohort"
                ]
            case .clinicalControl:
                return [
                    "placebo", "standard of care", "soc", "control arm", "comparator arm",
                    "parallel group", "usual care"
                ]
            case .inSilico:
                return [
                    "in silico", "simulation", "molecular dynamics", "docking", "alphafold",
                    "binding affinity", "kcal/mol", "rmse", "auc roc", "auc", "trajectory",
                    "dft", "finite element", "computational model", "prediction", "cross validation"
                ]
            case .generalReference:
                return []
            }
        }
    }

    struct Classification: Sendable {
        let domain: ScientificDomain
        let confidence: Float
        let matchedKeywords: [String]
        let score: Int
    }

    struct ClassifiedChunk: Sendable {
        let chunk: RetrievedChunk
        let classification: Classification
    }

    struct Assessment: Sendable {
        let queryClassification: Classification
        let dominantDomain: ScientificDomain
        let allowedDomain: ScientificDomain
        let classifiedChunks: [ClassifiedChunk]
        let rejectedChunks: [ClassifiedChunk]
        let allowedCoverage: Float
        let strictModeEnabled: Bool
        let permitsCrossDomainSynthesis: Bool
        let crossDomainRisk: String
        let shouldAbstain: Bool
        let reason: String?
        let details: String
    }

    nonisolated static func classifyQuery(_ query: String) -> Classification {
        classify(text: query, sourceDocument: nil, sectionHints: [])
    }

    nonisolated static func classifyChunk(_ chunk: RetrievedChunk) -> Classification {
        classify(
            text: buildChunkEvidenceText(chunk),
            sourceDocument: chunk.sourceDocument,
            sectionHints: [chunk.chunk.metadata.sectionTitle].compactMap { $0 } + (chunk.chunk.metadata.sectionPath ?? [])
        )
    }

    nonisolated static func assess(query: String, chunks: [RetrievedChunk], answerIntent: AnswerIntent?) -> Assessment {
        let queryClassification = classifyQuery(query)
        let classifiedChunks = chunks.map { ClassifiedChunk(chunk: $0, classification: classifyChunk($0)) }
        let strongChunkCount = classifiedChunks.filter {
            $0.classification.domain.family != .generalReference && $0.classification.score >= 2
        }.count
        let strictModeEnabled = queryClassification.score >= 2 || strongChunkCount >= 2
        let permitsCrossDomainSynthesis = allowsCrossDomainSynthesis(query: query, answerIntent: answerIntent)

        let weightedScores = classifiedChunks.reduce(into: [ScientificDomain: Float]()) { partialResult, item in
            let weight = max(0.12, item.chunk.similarityScore) * max(0.25, item.classification.confidence)
            partialResult[item.classification.domain.family, default: 0] += weight
        }

        let dominantDomain = weightedScores.max(by: { $0.value < $1.value })?.key
            ?? queryClassification.domain.family

        let allowedDomain: ScientificDomain = queryClassification.domain.family == .generalReference
            ? dominantDomain
            : queryClassification.domain.family

        let rejectedChunks = classifiedChunks.filter { $0.classification.domain.family != allowedDomain }
        let totalWeight = max(0.001, weightedScores.values.reduce(0, +))
        let allowedWeight = weightedScores[allowedDomain] ?? 0
        let allowedCoverage = allowedWeight / totalWeight

        let topDomains = Set(classifiedChunks.prefix(3).map(\.classification.domain.family).filter { $0 != .generalReference })
        let crossDomainRisk: String
        switch topDomains.count {
        case 0, 1:
            crossDomainRisk = "LOW"
        case 2:
            crossDomainRisk = "MEDIUM"
        default:
            crossDomainRisk = "HIGH"
        }

        if !strictModeEnabled {
            return Assessment(
                queryClassification: queryClassification,
                dominantDomain: dominantDomain,
                allowedDomain: .generalReference,
                classifiedChunks: classifiedChunks,
                rejectedChunks: [],
                allowedCoverage: 1.0,
                strictModeEnabled: false,
                permitsCrossDomainSynthesis: permitsCrossDomainSynthesis,
                crossDomainRisk: crossDomainRisk,
                shouldAbstain: false,
                reason: nil,
                details: "Experimental domain isolation not activated"
            )
        }

        let topChunkMismatch = classifiedChunks.first.map {
            $0.classification.domain.family != allowedDomain && $0.classification.confidence >= 0.55
        } ?? false

        let queryMismatch = queryClassification.domain.family != .generalReference
            && dominantDomain != .generalReference
            && dominantDomain != queryClassification.domain.family
            && (weightedScores[dominantDomain] ?? 0) >= max(allowedWeight, 0.3)

        // Cross-domain mixing is a claim about combining *sources*. When every
        // chunk comes from one document, there are no sources to mix: the domain
        // terms are the author's own, in one voice, in one document the user
        // deliberately imported.
        //
        // Device evidence 2026-08-03: a query about cleaning a laparoscope was
        // blocked with "mixed evidence across incompatible domains: IN VITRO vs
        // IN VIVO" when all three chunks were `[S1/S2/S3: Autoclavable
        // Laparoscopes IFU.pdf]`. A surgical IFU naturally uses both phrases. The
        // answer was discarded and the user got raw chunk text instead.
        //
        // Only the mixing clause is relaxed. Query mismatch, top-chunk mismatch,
        // and coverage are relevance judgements that stay meaningful for a single
        // document.
        let distinctSourceDocuments = Set(classifiedChunks.map(\.chunk.chunk.documentId))
        let isSingleSourceDocument = distinctSourceDocuments.count <= 1

        let blocksMixedDomains = !permitsCrossDomainSynthesis
            && topDomains.count >= 2
            && !isSingleSourceDocument

        let shouldAbstain = classifiedChunks.isEmpty
            || allowedCoverage < 0.55
            || topChunkMismatch
            || queryMismatch
            || blocksMixedDomains

        let reason: String?
        if classifiedChunks.isEmpty {
            reason = "Domain isolation could not evaluate any retrieved evidence."
        } else if blocksMixedDomains {
            let mixed = topDomains.map(\.rawValue).sorted().joined(separator: " vs ")
            reason = "Domain isolation blocked mixed evidence across incompatible domains: \(mixed)."
        } else if queryMismatch {
            reason = "Domain isolation found retrieved evidence in \(dominantDomain.rawValue) while the query targets \(allowedDomain.rawValue)."
        } else if topChunkMismatch {
            reason = "Domain isolation rejected the highest-ranked chunk because it belongs to \(classifiedChunks.first?.classification.domain.rawValue ?? "another domain"), not the \(allowedDomain.rawValue) family."
        } else if allowedCoverage < 0.55 {
            reason = "Domain isolation kept only \(Int((allowedCoverage * 100).rounded()))% of retrieval weight inside \(allowedDomain.rawValue)."
        } else {
            reason = nil
        }

        let keptCount = classifiedChunks.count - rejectedChunks.count
        let details = "query=\(queryClassification.domain.rawValue); allowed=\(allowedDomain.rawValue); dominant=\(dominantDomain.rawValue); kept=\(keptCount)/\(classifiedChunks.count); coverage=\(Int((allowedCoverage * 100).rounded()))%; cross_domain=\(permitsCrossDomainSynthesis ? "permitted" : crossDomainRisk.lowercased())"

        return Assessment(
            queryClassification: queryClassification,
            dominantDomain: dominantDomain,
            allowedDomain: allowedDomain,
            classifiedChunks: classifiedChunks,
            rejectedChunks: rejectedChunks,
            allowedCoverage: allowedCoverage,
            strictModeEnabled: true,
            permitsCrossDomainSynthesis: permitsCrossDomainSynthesis,
            crossDomainRisk: crossDomainRisk,
            shouldAbstain: shouldAbstain,
            reason: reason,
            details: details
        )
    }

    private nonisolated static func allowsCrossDomainSynthesis(query: String, answerIntent: AnswerIntent?) -> Bool {
        if let answerIntent {
            if answerIntent == .summarize || answerIntent.benefitsFromMultiHop {
                return true
            }
            if answerIntent == .compare || answerIntent == .findings {
                return true
            }
        }

        let lower = query.lowercased()
        let comparisonSignals = [
            "compare", "comparison", "versus", " vs ", "difference between",
            "across", "both", "in vitro and in vivo", "clinical and preclinical"
        ]
        return comparisonSignals.contains { lower.contains($0) }
    }

    private nonisolated static func classify(text: String, sourceDocument: String?, sectionHints: [String]) -> Classification {
        let normalized = normalize(text + " " + (sourceDocument ?? "") + " " + sectionHints.joined(separator: " "))
        let baseDomains: [ScientificDomain] = [.inVitro, .inVivo, .clinical, .inSilico]
        var scoredDomains: [(domain: ScientificDomain, score: Int, matches: [String])] = []

        for domain in baseDomains {
            let matches = domain.keywords.filter { normalized.contains($0) }
            let score = matches.count
            if score > 0 {
                scoredDomains.append((domain, score, Array(matches.prefix(6))))
            }
        }

        scoredDomains.sort {
            if $0.score == $1.score {
                return $0.domain.rawValue < $1.domain.rawValue
            }
            return $0.score > $1.score
        }

        guard let best = scoredDomains.first else {
            return Classification(domain: .generalReference, confidence: 0.2, matchedKeywords: [], score: 0)
        }

        let secondScore = scoredDomains.dropFirst().first?.score ?? 0
        let margin = max(0, best.score - secondScore)
        let confidence = min(1.0, 0.30 + Float(best.score) * 0.10 + Float(margin) * 0.08)
        let classifiedDomain = controlVariant(for: best.domain, normalized: normalized)

        return Classification(
            domain: classifiedDomain,
            confidence: confidence,
            matchedKeywords: best.matches,
            score: best.score
        )
    }

    private nonisolated static func controlVariant(for baseDomain: ScientificDomain, normalized: String) -> ScientificDomain {
        let controlTerms = [
            "vehicle", "untreated", "placebo", "standard of care", "sham", "control group",
            "control arm", "comparator", "usual care", "saline"
        ]
        let looksLikeControl = controlTerms.contains { normalized.contains($0) }
        guard looksLikeControl else { return baseDomain }

        switch baseDomain {
        case .inVitro:
            return .inVitroControl
        case .inVivo:
            return .inVivoControl
        case .clinical:
            return .clinicalControl
        default:
            return baseDomain
        }
    }

    private nonisolated static func buildChunkEvidenceText(_ chunk: RetrievedChunk) -> String {
        var parts: [String] = [chunk.chunk.parentContent ?? chunk.chunk.content]
        if let title = chunk.chunk.metadata.sectionTitle {
            parts.append(title)
        }
        if let path = chunk.chunk.metadata.sectionPath, !path.isEmpty {
            parts.append(path.joined(separator: " "))
        }
        if !chunk.chunk.metadata.entities.isEmpty {
            parts.append(chunk.chunk.metadata.entities.joined(separator: " "))
        }
        if !chunk.chunk.metadata.keywords.isEmpty {
            parts.append(chunk.chunk.metadata.keywords.joined(separator: " "))
        }
        return parts.joined(separator: " ")
    }

    private nonisolated static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }
}
