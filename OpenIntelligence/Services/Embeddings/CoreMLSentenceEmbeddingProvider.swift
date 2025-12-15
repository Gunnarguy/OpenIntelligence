//
//  CoreMLSentenceEmbeddingProvider.swift
//  OpenIntelligence
//
//  Scaffold for a local sentence-embedding backend powered by Core ML.
//  This enables higher-quality, multilingual sentence embeddings (e.g., 384/768 dims)
//  as an alternative to NLEmbedding's word-avg 512-dim vectors.
//
//  Notes:
//  - Tokenization is implemented using WordPiece-style BPE (common for sentence transformers).
//  - Plan: support popular sentence encoders (e.g., E5, MiniLM, GTE) converted to CoreML.
//  - Dimension should be read from the model's metadata or output tensor shape.
//

import Foundation
#if canImport(CoreML)
import CoreML
#endif

// MARK: - Tokenizer Protocol

/// Protocol for text tokenizers compatible with sentence transformer models
protocol SentenceTokenizer: Sendable {
    /// Encode text into token IDs
    func encode(_ text: String) -> [Int]
    
    /// Decode token IDs back to text
    func decode(_ tokens: [Int]) -> String
    
    /// Vocabulary size
    var vocabSize: Int { get }
    
    /// Special token IDs
    var clsTokenId: Int { get }
    var sepTokenId: Int { get }
    var padTokenId: Int { get }
    var unkTokenId: Int { get }
}

// MARK: - WordPiece Tokenizer

/// Basic WordPiece tokenizer implementation for BERT-style models
/// This is a minimal implementation suitable for sentence-transformers
final class WordPieceTokenizer: SentenceTokenizer, @unchecked Sendable {
    
    private let vocabulary: [String: Int]
    private let inverseVocabulary: [Int: String]
    private let maxTokenLength: Int
    private let lowercased: Bool
    
    // Special tokens (standard BERT-style)
    let clsTokenId: Int
    let sepTokenId: Int
    let padTokenId: Int
    let unkTokenId: Int
    
    var vocabSize: Int { vocabulary.count }
    
    /// Initialize with vocabulary file (JSON format: {"token": id, ...})
    init?(vocabURL: URL, maxTokenLength: Int = 512, lowercased: Bool = true) {
        guard let data = try? Data(contentsOf: vocabURL),
              let vocab = try? JSONDecoder().decode([String: Int].self, from: data) else {
            Log.error("[WordPieceTokenizer] Failed to load vocabulary from \(vocabURL.lastPathComponent)", category: .embedding)
            return nil
        }
        
        self.vocabulary = vocab
        self.inverseVocabulary = Dictionary(uniqueKeysWithValues: vocab.map { ($1, $0) })
        self.maxTokenLength = maxTokenLength
        self.lowercased = lowercased
        
        // Resolve special token IDs (with defaults for BERT)
        self.clsTokenId = vocab["[CLS]"] ?? 101
        self.sepTokenId = vocab["[SEP]"] ?? 102
        self.padTokenId = vocab["[PAD]"] ?? 0
        self.unkTokenId = vocab["[UNK]"] ?? 100
        
        Log.debug("[WordPieceTokenizer] Loaded vocabulary with \(vocab.count) tokens", category: .embedding)
    }
    
    /// Initialize with inline vocabulary dictionary (for testing or embedded models)
    init(vocabulary: [String: Int], maxTokenLength: Int = 512, lowercased: Bool = true) {
        self.vocabulary = vocabulary
        self.inverseVocabulary = Dictionary(uniqueKeysWithValues: vocabulary.map { ($1, $0) })
        self.maxTokenLength = maxTokenLength
        self.lowercased = lowercased
        self.clsTokenId = vocabulary["[CLS]"] ?? 101
        self.sepTokenId = vocabulary["[SEP]"] ?? 102
        self.padTokenId = vocabulary["[PAD]"] ?? 0
        self.unkTokenId = vocabulary["[UNK]"] ?? 100
    }
    
    func encode(_ text: String) -> [Int] {
        let processedText = lowercased ? text.lowercased() : text
        
        // Basic whitespace tokenization first
        let words = processedText.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        var tokenIds: [Int] = [clsTokenId]  // Start with [CLS]
        
        for word in words {
            let subTokens = wordPieceTokenize(word)
            for subToken in subTokens {
                if tokenIds.count >= maxTokenLength - 1 { break }  // Reserve space for [SEP]
                tokenIds.append(subToken)
            }
            if tokenIds.count >= maxTokenLength - 1 { break }
        }
        
        tokenIds.append(sepTokenId)  // End with [SEP]
        
        return tokenIds
    }
    
    /// WordPiece sub-word tokenization
    private func wordPieceTokenize(_ word: String) -> [Int] {
        var tokens: [Int] = []
        var start = word.startIndex
        
        while start < word.endIndex {
            var end = word.endIndex
            var foundSubword = false
            
            while start < end {
                let subword = start == word.startIndex
                    ? String(word[start..<end])
                    : "##" + String(word[start..<end])
                
                if let tokenId = vocabulary[subword] {
                    tokens.append(tokenId)
                    start = end
                    foundSubword = true
                    break
                }
                
                // Shorten the substring
                end = word.index(before: end)
            }
            
            if !foundSubword {
                // Character not in vocab - use [UNK]
                tokens.append(unkTokenId)
                start = word.index(after: start)
            }
        }
        
        return tokens
    }
    
    func decode(_ tokens: [Int]) -> String {
        var result = ""
        for tokenId in tokens {
            guard let token = inverseVocabulary[tokenId] else { continue }
            if token.hasPrefix("##") {
                result += String(token.dropFirst(2))
            } else if token == "[CLS]" || token == "[SEP]" || token == "[PAD]" {
                continue
            } else {
                if !result.isEmpty { result += " " }
                result += token
            }
        }
        return result
    }
}

// MARK: - CoreML Sentence Embedding Provider

final class CoreMLSentenceEmbeddingProvider: EmbeddingProvider {
    #if canImport(CoreML)
    private let model: MLModel?
    #endif
    private let tokenizer: SentenceTokenizer?
    private let maxSequenceLength: Int
    
    let dimension: Int
    
    init(dimension: Int = 384, maxSequenceLength: Int = 512) {
        // Placeholder init when a model isn't loaded yet (keeps UI selectable but unavailable)
        self.dimension = dimension
        self.maxSequenceLength = maxSequenceLength
        self.tokenizer = nil
        #if canImport(CoreML)
        self.model = nil
        #endif
    }
    
    #if canImport(CoreML)
    /// Initialize with a Core ML model package URL (.mlmodelc/.mlpackage) and vocabulary
    convenience init(modelURL: URL, vocabURL: URL, expectedDimension: Int, maxSequenceLength: Int = 512) {
        do {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .all
            let loaded = try MLModel(contentsOf: modelURL, configuration: cfg)
            let tokenizer = WordPieceTokenizer(vocabURL: vocabURL)
            self.init(model: loaded, tokenizer: tokenizer, dimension: expectedDimension, maxSequenceLength: maxSequenceLength)
        } catch {
            Log.error("[CoreMLSentenceEmbeddingProvider] Failed to load model: \(error.localizedDescription)", category: .embedding)
            self.init(dimension: expectedDimension, maxSequenceLength: maxSequenceLength)
        }
    }
    
    /// Initialize with an already-loaded MLModel and tokenizer
    init(model: MLModel?, tokenizer: SentenceTokenizer?, dimension: Int, maxSequenceLength: Int = 512) {
        self.dimension = dimension
        self.maxSequenceLength = maxSequenceLength
        self.model = model
        self.tokenizer = tokenizer
    }
    #endif
    
    var isAvailable: Bool {
        #if canImport(CoreML)
        return model != nil && tokenizer != nil
        #else
        return false
        #endif
    }
    
    func embed(text: String) async throws -> [Float] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EmbeddingError.emptyInput
        }
        
        #if canImport(CoreML)
        guard let model = model, let tokenizer = tokenizer else {
            throw EmbeddingError.modelUnavailable
        }
        
        // Step 1: Tokenize input text
        let tokenIds = tokenizer.encode(text)
        
        // Step 2: Create attention mask (1 for real tokens, 0 for padding)
        let attentionMask = Array(repeating: 1, count: tokenIds.count)
        
        // Step 3: Pad sequences to maxSequenceLength
        let paddedTokenIds = padSequence(tokenIds, to: maxSequenceLength, padValue: tokenizer.padTokenId)
        let paddedAttentionMask = padSequence(attentionMask, to: maxSequenceLength, padValue: 0)
        
        // Step 4: Create MLMultiArray inputs for the model
        let inputIds = try createMLMultiArray(from: paddedTokenIds)
        let attentionMaskArray = try createMLMultiArray(from: paddedAttentionMask)
        
        // Step 5: Run inference
        let features = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIds),
            "attention_mask": MLFeatureValue(multiArray: attentionMaskArray)
        ])
        
        let output = try await model.prediction(from: features)
        
        // Step 6: Extract embedding from output (model-specific key)
        // Common keys: "sentence_embedding", "pooler_output", "last_hidden_state"
        if let embeddingValue = output.featureValue(for: "sentence_embedding"),
           let embeddingArray = embeddingValue.multiArrayValue {
            return extractFloatArray(from: embeddingArray, expectedDimension: dimension)
        } else if let poolerValue = output.featureValue(for: "pooler_output"),
                  let poolerArray = poolerValue.multiArrayValue {
            return extractFloatArray(from: poolerArray, expectedDimension: dimension)
        } else {
            // Try to find any suitable output
            Log.warning("[CoreMLSentenceEmbeddingProvider] Could not find standard embedding output key", category: .embedding)
            throw EmbeddingError.outputParsingFailed
        }
        
        #else
        throw EmbeddingError.modelUnavailable
        #endif
    }
    
    func embedBatch(texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        // Sequential processing for now; future: batch inputs where model supports it
        var results: [[Float]] = []
        results.reserveCapacity(texts.count)
        for text in texts {
            let embedding = try await embed(text: text)
            results.append(embedding)
        }
        return results
    }
    
    // MARK: - Helper Methods
    
    private func padSequence(_ sequence: [Int], to length: Int, padValue: Int) -> [Int] {
        if sequence.count >= length {
            return Array(sequence.prefix(length))
        }
        return sequence + Array(repeating: padValue, count: length - sequence.count)
    }
    
    #if canImport(CoreML)
    private func createMLMultiArray(from ints: [Int]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, NSNumber(value: ints.count)], dataType: .int32)
        for (i, value) in ints.enumerated() {
            array[[0, i] as [NSNumber]] = NSNumber(value: value)
        }
        return array
    }
    
    private func extractFloatArray(from multiArray: MLMultiArray, expectedDimension: Int) -> [Float] {
        let count = multiArray.count
        var result: [Float] = []
        result.reserveCapacity(min(count, expectedDimension))
        
        // Handle different shapes: [1, dim] or [dim]
        for i in 0..<min(count, expectedDimension) {
            result.append(multiArray[i].floatValue)
        }
        
        // Pad with zeros if output is smaller than expected
        while result.count < expectedDimension {
            result.append(0.0)
        }
        
        return result
    }
    #endif
}
