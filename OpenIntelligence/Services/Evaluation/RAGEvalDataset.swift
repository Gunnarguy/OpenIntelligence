//
//  RAGEvalDataset.swift
//  OpenIntelligence
//
//  Loads evaluation datasets from JSONL files.
//

import Foundation

// MARK: - Eval Dataset

/// A collection of evaluation test cases loaded from a JSONL file.
struct RAGEvalDataset: Sendable {
    /// Human-readable name of this dataset
    let name: String

    /// The loaded test cases
    let cases: [RAGEvalCase]

    /// Total number of cases
    var count: Int { cases.count }

    /// Filter cases by category
    func cases(for category: EvalCategory) -> [RAGEvalCase] {
        cases.filter { $0.category == category }
    }

    /// Filter cases by tag
    func cases(tagged tag: String) -> [RAGEvalCase] {
        cases.filter { $0.tags?.contains(tag) ?? false }
    }

    /// Category distribution summary
    var categoryCounts: [EvalCategory: Int] {
        Dictionary(grouping: cases, by: \.category).mapValues(\.count)
    }
}

// MARK: - Dataset Loader

extension RAGEvalDataset {

    /// Load a dataset from a JSONL file.
    ///
    /// Each line in the file should be a valid JSON object conforming to `RAGEvalCase`.
    /// Blank lines and lines starting with `//` are skipped.
    ///
    /// - Parameters:
    ///   - url: The file URL to load from
    ///   - name: Optional dataset name (defaults to filename)
    /// - Returns: A loaded dataset
    /// - Throws: If the file cannot be read or contains invalid JSON
    static func load(from url: URL, name: String? = nil) throws -> RAGEvalDataset {
        let content = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()

        let cases: [RAGEvalCase] = content
            .components(separatedBy: .newlines)
            .enumerated()
            .compactMap { lineNumber, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Skip blank lines and comments
                guard !trimmed.isEmpty, !trimmed.hasPrefix("//") else { return nil }

                guard let data = trimmed.data(using: .utf8) else {
                    Log.warning("[Eval] Line \(lineNumber + 1): Could not encode to UTF-8, skipping", category: .pipeline)
                    return nil
                }

                do {
                    return try decoder.decode(RAGEvalCase.self, from: data)
                } catch {
                    Log.warning("[Eval] Line \(lineNumber + 1): Failed to decode: \(error.localizedDescription)", category: .pipeline)
                    return nil
                }
            }

        let datasetName = name ?? url.deletingPathExtension().lastPathComponent
        Log.info("[Eval] Loaded dataset '\(datasetName)': \(cases.count) cases", category: .pipeline)

        return RAGEvalDataset(name: datasetName, cases: cases)
    }

    /// Load a dataset from a bundle resource.
    ///
    /// - Parameters:
    ///   - resourceName: The resource filename (without extension)
    ///   - bundle: The bundle to search (defaults to main)
    /// - Returns: A loaded dataset
    /// - Throws: If the resource cannot be found or contains invalid JSON
    static func loadFromBundle(
        resourceName: String,
        bundle: Bundle = .main
    ) throws -> RAGEvalDataset {
        guard let url = bundle.url(forResource: resourceName, withExtension: "jsonl") else {
            throw EvalError.datasetNotFound(resourceName)
        }
        return try load(from: url, name: resourceName)
    }
}

// MARK: - Eval Errors

enum EvalError: LocalizedError {
    case datasetNotFound(String)
    case noTestCases
    case evaluationFailed(String)

    var errorDescription: String? {
        switch self {
        case .datasetNotFound(let name):
            return "Evaluation dataset '\(name)' not found"
        case .noTestCases:
            return "Dataset contains no test cases"
        case .evaluationFailed(let reason):
            return "Evaluation failed: \(reason)"
        }
    }
}
