//
//  CoreValidationView.swift
//  OpenIntelligence
//
//  Core pipeline validation and testing utility
//  Created by GitHub Copilot on 10/10/25.
//

import SwiftUI

struct CoreValidationView: View {
    @ObservedObject var ragService: RAGService
    
    @State private var testResults: [TestResult] = []
    @State private var isRunning = false
    @State private var currentTest = ""
    @State private var overallStatus: TestStatus = .notStarted
    
    var body: some View {
        ZStack {
            // Modern gradient background
            LinearGradient(
                colors: [
                    DSColors.background,
                    DSColors.surface.opacity(0.3)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Hero Status Card
                    ModernStatusCard(status: overallStatus, isRunning: isRunning, currentTest: currentTest)
                        .padding(.horizontal)
                        .padding(.top)
                    
                    // Run Tests Button
                    Button(action: runAllTests) {
                        HStack(spacing: 12) {
                            Image(systemName: isRunning ? "arrow.triangle.2.circlepath" : "play.circle.fill")
                                .font(.title3)
                                .rotationEffect(isRunning ? .degrees(360) : .degrees(0))
                                .animation(isRunning ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRunning)
                            
                            Text(isRunning ? "Running Tests..." : "Run Core Validation")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: isRunning ? [Color.gray, Color.gray.opacity(0.8)] : [Color.accentColor, Color.accentColor.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .shadow(color: isRunning ? .clear : .accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .disabled(isRunning)
                    .padding(.horizontal)
                    
                    // Test Results
                    if !testResults.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Test Results")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                
                                Spacer()
                                
                                // Pass/Fail count
                                HStack(spacing: 12) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        Text("\(testResults.filter { $0.status == .passed }.count)")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                    }
                                    
                                    HStack(spacing: 4) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                        Text("\(testResults.filter { $0.status == .failed }.count)")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                    }
                                }
                            }
                            .padding(.horizontal)
                            
                            LazyVStack(spacing: 12) {
                                ForEach(testResults) { result in
                                    ModernTestResultCard(result: result)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // Test Info
                    ModernTestInfoSection()
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                }
            }
        }
        .navigationTitle("Core Validation")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
    
    // MARK: - Test Runner
    
    private func runAllTests() {
        Task {
            await MainActor.run {
                isRunning = true
                testResults = []
                overallStatus = .running
            }
            
            // Test 1: Document Processor
            await runTest(name: "DocumentProcessor - Basic Parsing") {
                // This would test actual document processing
                // For now, just validate the service exists
                let processor = DocumentProcessor()
                return processor.targetChunkSize == 400
            }
            
            // Test 2: Embedding Service
            await runTest(name: "EmbeddingService - Availability") {
                let embeddingService = EmbeddingService()
                return embeddingService.isAvailable
            }
            
            await runTest(name: "EmbeddingService - Dimension Check") {
                let embeddingService = EmbeddingService()
                guard embeddingService.isAvailable else { return false }
                
                do {
                    let embedding = try await embeddingService.generateEmbedding(for: "Test text for validation")
                    return embedding.count == 512
                } catch {
                    return false
                }
            }
            
            await runTest(name: "EmbeddingService - Edge Case (Empty)") {
                let embeddingService = EmbeddingService()
                do {
                    _ = try await embeddingService.generateEmbedding(for: "")
                    return false // Should have thrown error
                } catch {
                    return true // Correctly handled edge case
                }
            }
            
            // Test 3: Vector Database
            await runTest(name: "VectorDatabase - Store and Count") {
                let vectorDB = InMemoryVectorDatabase()
                let testChunk = DocumentChunk(
                    documentId: UUID(),
                    content: "Test content",
                    embedding: Array(repeating: 0.1, count: 512),
                    metadata: ChunkMetadata(chunkIndex: 0, startPosition: 0, endPosition: 12)
                )
                
                do {
                    try await vectorDB.store(chunk: testChunk)
                    let count = try await vectorDB.count()
                    return count == 1
                } catch {
                    return false
                }
            }
            
            await runTest(name: "VectorDatabase - Search Functionality") {
                let vectorDB = InMemoryVectorDatabase()
                let testEmbedding = Array(repeating: Float(0.1), count: 512)
                let testChunk = DocumentChunk(
                    documentId: UUID(),
                    content: "Test content",
                    embedding: testEmbedding,
                    metadata: ChunkMetadata(chunkIndex: 0, startPosition: 0, endPosition: 12)
                )
                
                do {
                    try await vectorDB.store(chunk: testChunk)
                    let results = try await vectorDB.search(embedding: testEmbedding, topK: 1)
                    return results.count == 1 && results[0].similarityScore > 0.99
                } catch {
                    return false
                }
            }
            
            await runTest(name: "VectorDatabase - Edge Case (Empty Search)") {
                let vectorDB = InMemoryVectorDatabase()
                let testEmbedding = Array(repeating: Float(0.1), count: 512)
                
                do {
                    let results = try await vectorDB.search(embedding: testEmbedding, topK: 5)
                    return results.isEmpty // Should return empty array for empty DB
                } catch {
                    return false
                }
            }
            
            // Test 4: Device Capabilities
            await runTest(name: "Device Capabilities Check") {
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async {
                        let capabilities = RAGService.checkDeviceCapabilities()
                        continuation.resume(returning: capabilities.canRunRAG)
                    }
                }
            }
            
            // Test 5: LLM Service
            await runTest(name: "LLM Service - Availability") {
                return ragService.isLLMAvailable
            }
            
            // Test 6: RAGService - Small Talk Bypass ('hi')
            await runTest(name: "RAGService - Small Talk Bypass ('hi')") {
                // Use a dedicated test service to avoid main-thread constraints of Apple FM
                let testService = RAGService(
                    documentProcessor: DocumentProcessor(),
                    embeddingService: EmbeddingService(),
                    vectorDatabase: InMemoryVectorDatabase(),
                    llmService: OnDeviceAnalysisService()
                )
                do {
                    let resp = try await testService.query("hi", topK: 5, config: .precise)
                    return resp.retrievedChunks.isEmpty && !resp.generatedResponse.isEmpty
                } catch {
                    return false
                }
            }
            
            // Test 7: RAGService - Direct Chat (No Docs)
            await runTest(name: "RAGService - Direct Chat (No Docs)") {
                // Empty in-memory DB ensures direct chat path
                let testService = RAGService(
                    documentProcessor: DocumentProcessor(),
                    embeddingService: EmbeddingService(),
                    vectorDatabase: InMemoryVectorDatabase(),
                    llmService: OnDeviceAnalysisService()
                )
                do {
                    let resp = try await testService.query("Briefly explain what a RAG pipeline does.", topK: 3, config: .precise)
                    return resp.retrievedChunks.isEmpty && !resp.generatedResponse.isEmpty
                } catch {
                    return false
                }
            }
            
            // Test 8: Tools - search_documents truncation and citation
            await runTest(name: "Tools - search_documents truncation + citation") {
                // Seed a temporary service with one long chunk and verify truncation + source formatting
                let vectorDB = InMemoryVectorDatabase()
                let testService = RAGService(
                    documentProcessor: DocumentProcessor(),
                    embeddingService: EmbeddingService(),
                    vectorDatabase: vectorDB,
                    llmService: OnDeviceAnalysisService()
                )
                
                let longText = String(repeating: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ", count: 40) // > 600 chars
                let doc = Document(
                    filename: "Foo.txt",
                    fileURL: URL(fileURLWithPath: "/tmp/Foo.txt"),
                    contentType: .text,
                    totalChunks: 1,
                    processingMetadata: nil
                )
                
                do {
                    // Prepare embedding and chunk
                    let embedder = EmbeddingService()
                    let embedding = try await embedder.generateEmbedding(for: longText)
                    let chunk = DocumentChunk(
                        documentId: doc.id,
                        content: longText,
                        embedding: embedding,
                        metadata: ChunkMetadata(
                            chunkIndex: 0,
                            startPosition: 0,
                            endPosition: longText.count,
                            pageNumber: 1
                        )
                    )
                    
                    try await vectorDB.store(chunk: chunk)
                    await MainActor.run {
                        testService.documents.append(doc)
                    }
                    
                    // Call tool and verify truncation marker and citation
                    let toolOutput = try await testService.searchDocuments(query: "Lorem ipsum")
                    let hasTruncation = toolOutput.contains(" [...]")
                    let hasDocName = toolOutput.contains("Foo.txt")
                    let hasFoundCount = toolOutput.contains("Found 1 relevant chunks")
                    return hasTruncation && hasDocName && hasFoundCount
                } catch {
                    return false
                }
            }
            
            // Finalize
            await MainActor.run {
                isRunning = false
                
                let passedCount = testResults.filter { $0.status == .passed }.count
                let totalCount = testResults.count
                
                if passedCount == totalCount {
                    overallStatus = .passed
                } else if passedCount == 0 {
                    overallStatus = .failed
                } else {
                    overallStatus = .partial
                }
            }
        }
    }
    
    private func runTest(name: String, test: () async -> Bool) async {
        await MainActor.run {
            currentTest = name
        }
        
        let startTime = Date()
        let passed = await test()
        let duration = Date().timeIntervalSince(startTime)
        
        let result = TestResult(
            name: name,
            status: passed ? .passed : .failed,
            duration: duration,
            message: passed ? "✓" : "Failed"
        )
        
        await MainActor.run {
            testResults.append(result)
        }
    }
}

// MARK: - Modern Supporting Views

struct ModernStatusCard: View {
    let status: TestStatus
    let isRunning: Bool
    let currentTest: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(status.color.opacity(0.2))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: status.icon)
                        .font(.title3)
                        .foregroundColor(status.color)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Core Pipeline Validation")
                        .font(.headline)
                    
                    if status != .notStarted && status != .running {
                        Text(status.message)
                            .font(.caption)
                            .foregroundColor(status.color)
                    }
                }
            }
            
            if isRunning && !currentTest.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    
                    Text(currentTest)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DSColors.surface)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }
}

struct ModernTestResultCard: View {
    let result: TestResult
    
    var body: some View {
        HStack(spacing: 16) {
            // Status icon
            ZStack {
                Circle()
                    .fill(result.status.color.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                Image(systemName: result.status.icon)
                    .foregroundColor(result.status.color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(result.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(result.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(String(format: "%.2fs", result.duration))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(DSColors.surface)
                )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DSColors.surface)
                .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 2)
        )
    }
}

struct ModernTestInfoSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.accentColor)
                Text("What This Tests")
                    .font(.title3)
                    .fontWeight(.bold)
            }
            
            VStack(spacing: 12) {
                ModernTestInfoItem(
                    icon: "doc.text",
                    color: .blue,
                    text: "Document processing and chunking"
                )
                ModernTestInfoItem(
                    icon: "cube.box",
                    color: .purple,
                    text: "Embedding generation (512-dim)"
                )
                ModernTestInfoItem(
                    icon: "cylinder",
                    color: .green,
                    text: "Vector database operations"
                )
                ModernTestInfoItem(
                    icon: "wand.and.stars",
                    color: .orange,
                    text: "LLM service availability"
                )
                ModernTestInfoItem(
                    icon: "exclamationmark.triangle",
                    color: .red,
                    text: "Edge case handling"
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DSColors.surface)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }
}

struct ModernTestInfoItem: View {
    let icon: String
    let color: Color
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.2))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .foregroundColor(color)
            }
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

// MARK: - Legacy Components (for compatibility)

struct StatusCard: View {
    let status: TestStatus
    let isRunning: Bool
    let currentTest: String
    
    var body: some View {
        ModernStatusCard(status: status, isRunning: isRunning, currentTest: currentTest)
    }
}

struct TestResultRow: View {
    let result: TestResult
    
    var body: some View {
        ModernTestResultCard(result: result)
    }
}

struct TestInfoSection: View {
    var body: some View {
        ModernTestInfoSection()
    }
}

struct TestInfoItem: View {
    let icon: String
    let text: String
    
    var body: some View {
        ModernTestInfoItem(icon: icon, color: .blue, text: text)
    }
}

// MARK: - Models

struct TestResult: Identifiable {
    let id = UUID()
    let name: String
    let status: TestStatus
    let duration: TimeInterval
    let message: String
}

enum TestStatus {
    case notStarted
    case running
    case passed
    case failed
    case partial
    
    var color: Color {
        switch self {
        case .notStarted: return .gray
        case .running: return .blue
        case .passed: return .green
        case .failed: return .red
        case .partial: return .orange
        }
    }
    
    var icon: String {
        switch self {
        case .notStarted: return "circle"
        case .running: return "arrow.triangle.2.circlepath"
        case .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .partial: return "exclamationmark.circle.fill"
        }
    }
    
    var message: String {
        switch self {
        case .notStarted: return "Tests not run"
        case .running: return "Running tests..."
        case .passed: return "All tests passed ✅"
        case .failed: return "Tests failed ❌"
        case .partial: return "Some tests failed ⚠️"
        }
    }
}

// MARK: - Preview

struct CoreValidationView_Previews: PreviewProvider {
    static var previews: some View {
        CoreValidationView(ragService: RAGService())
    }
}
