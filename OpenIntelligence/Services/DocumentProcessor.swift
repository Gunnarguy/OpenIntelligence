//
//  DocumentProcessor.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import Foundation
import PDFKit
import UniformTypeIdentifiers
import Vision
import CoreImage
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Service responsible for parsing documents and chunking them for embedding
class DocumentProcessor {
    struct ProcessedChunk: Sendable {
        let text: String
        let metadata: ChunkMetadata
    }
    
    // MARK: - Configuration
    
    /// Optimal chunk size balances context vs. precision (typically 200-500 words)
    let targetChunkSize: Int
    let chunkOverlap: Int
    
    /// Progress callback for real-time UI updates
    var progressHandler: ((String) -> Void)?
    
    init(targetChunkSize: Int = 400, chunkOverlap: Int = 75) {
        self.targetChunkSize = targetChunkSize
        self.chunkOverlap = chunkOverlap
    }
    
    // MARK: - Public API
    
    /// Process a document and extract text chunks
    func processDocument(at url: URL) async throws -> (Document, [ProcessedChunk]) {
        let filename = url.lastPathComponent
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        let fileSizeMB = Double(fileSize) / 1_048_576.0
        
        print("\n📄 [DocumentProcessor] Processing document: \(filename)")
        print("   File size: \(String(format: "%.2f", fileSizeMB)) MB")
        
    let startTime = Date()
    let documentId = UUID()
    var pagesProcessed: Int? = nil
    var ocrPagesCount: Int? = nil
        
        // Determine document type
        let documentType = detectDocumentType(url: url)
        print("   Document type: \(documentType)")
        
        // Extract text based on document type
        progressHandler?("reading file")
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s to show loading (increased for visibility)
        let (extractedText, pageInfo) = try await extractTextWithPageInfo(from: url, type: documentType)
        
        pagesProcessed = pageInfo.totalPages
        ocrPagesCount = pageInfo.ocrPagesUsed > 0 ? pageInfo.ocrPagesUsed : nil
        
        let extractionTime = Date().timeIntervalSince(startTime)
        let charCount = extractedText.count
        let wordCount = extractedText.split(separator: " ").count
        
        print("   ✓ Extracted \(charCount) characters (\(wordCount) words)")
        print("   ⏱️  Extraction took \(String(format: "%.2f", extractionTime))s")
        
        // Chunk the text using semantic chunker
        progressHandler?("chunking text")
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s to show chunking (increased for visibility)
        let chunkingStartTime = Date()
        
        // Create semantic chunker configuration
        let chunkerConfig = SemanticChunker.ChunkingConfig(
            targetSize: self.targetChunkSize,
            minSize: max(100, self.targetChunkSize / 4),
            maxSize: self.targetChunkSize * 2,
            overlap: self.chunkOverlap
        )
        
        let semanticChunker = SemanticChunker()
        
        // Use semantic chunking (synchronous call, no page mapping for now)
        let enhancedChunks = semanticChunker.chunkText(
            extractedText,
            documentId: documentId,
            config: chunkerConfig,
            pageNumbers: nil  // TODO: Map page numbers to text ranges
        )
        
        // Extract text strings and metadata for downstream use
        let processedChunks: [ProcessedChunk] = enhancedChunks.enumerated().map { index, chunk in
            let metadata = ChunkMetadata(
                chunkIndex: index,
                startPosition: chunk.metadata.startOffset,
                endPosition: chunk.metadata.endOffset,
                pageNumber: chunk.metadata.pageNumber,
                sectionTitle: chunk.metadata.sectionTitle,
                keywords: chunk.metadata.topKeywords,
                semanticDensity: chunk.metadata.semanticDensity,
                hasNumericData: chunk.metadata.hasNumericData,
                hasListStructure: chunk.metadata.hasListStructure,
                wordCount: chunk.metadata.wordCount,
                characterCount: chunk.metadata.characterCount
            )
            return ProcessedChunk(text: chunk.content, metadata: metadata)
        }
        
        let chunkingTime = Date().timeIntervalSince(chunkingStartTime)
        
        print("   ✓ Created \(processedChunks.count) semantic chunks")
        print("   ⏱️  Semantic chunking took \(String(format: "%.3f", chunkingTime))s")
        
        // Log semantic features detected
        let chunksWithSections = processedChunks.filter { $0.metadata.sectionTitle != nil }.count
        let chunksWithKeywords = processedChunks.filter { !$0.metadata.keywords.isEmpty }.count
        let chunksWithNumericData = processedChunks.filter { $0.metadata.hasNumericData }.count
        let chunksWithLists = processedChunks.filter { $0.metadata.hasListStructure }.count
        
    print("   📑 Semantic features:")
    print("      - Sections detected: \(chunksWithSections)/\(processedChunks.count)")
    print("      - Keywords extracted: \(chunksWithKeywords)/\(processedChunks.count)")
    print("      - Numeric data: \(chunksWithNumericData)/\(processedChunks.count)")
    print("      - List structures: \(chunksWithLists)/\(processedChunks.count)")
        
        // Calculate average semantic density
        let avgSemanticDensity = processedChunks
            .map { Double($0.metadata.semanticDensity ?? 0) }
            .reduce(0.0, +) / Double(max(1, processedChunks.count))
        print("      - Avg semantic density: \(String(format: "%.3f", avgSemanticDensity))")
        
        // Print chunk statistics
        if !processedChunks.isEmpty {
            let chunkLengths = processedChunks.map { $0.metadata.characterCount }
            let avgChunkSize = chunkLengths.reduce(0, +) / processedChunks.count
            let minChunkSize = chunkLengths.min() ?? 0
            let maxChunkSize = chunkLengths.max() ?? 0
            print("   📊 Chunk stats: avg=\(avgChunkSize), min=\(minChunkSize), max=\(maxChunkSize) chars")
            
            let chunkStats = ChunkStatistics(
                averageChars: avgChunkSize,
                minChars: minChunkSize,
                maxChars: maxChunkSize
            )
            
            let totalTime = Date().timeIntervalSince(startTime)
            print("   ✅ Total processing: \(String(format: "%.2f", totalTime))s")
            
            // Create processing metadata
            let metadata = ProcessingMetadata(
                fileSizeMB: fileSizeMB,
                totalCharacters: charCount,
                totalWords: wordCount,
                extractionTimeSeconds: extractionTime,
                chunkingTimeSeconds: chunkingTime,
                embeddingTimeSeconds: 0, // Will be updated by RAGService after embeddings are generated
                totalProcessingTimeSeconds: totalTime,
                pagesProcessed: pagesProcessed,
                ocrPagesCount: ocrPagesCount,
                chunkStats: chunkStats
            )
            
            // Create document metadata
            let document = Document(
                id: documentId,
                filename: filename,
                fileURL: url,
                contentType: documentType,
                totalChunks: processedChunks.count,
                processingMetadata: metadata
            )
            
            return (document, processedChunks)
        }
        
        let totalTime = Date().timeIntervalSince(startTime)
        print("   ✅ Total processing: \(String(format: "%.2f", totalTime))s")
        
        // Create document metadata (no chunks case)
        let document = Document(
            id: documentId,
            filename: filename,
            fileURL: url,
            contentType: documentType,
            totalChunks: processedChunks.count
        )
        
        return (document, processedChunks)
    }
    
    // MARK: - Text Extraction
    
    /// Holds page information from document extraction
    private struct PageInfo {
        let totalPages: Int
        let ocrPagesUsed: Int
        let pageNumbers: [Int] // Array of page numbers corresponding to text chunks
    }
    
    /// Extract text with page information for semantic chunking
    private func extractTextWithPageInfo(from url: URL, type: DocumentType) async throws -> (text: String, pageInfo: PageInfo) {
        let text: String
        var pageInfo = PageInfo(totalPages: 0, ocrPagesUsed: 0, pageNumbers: [])
        
        switch type {
        case .pdf:
            let (extractedText, pdfPageInfo) = try await extractTextFromPDFWithPages(url: url)
            text = extractedText
            pageInfo = pdfPageInfo
            
        case .text, .markdown:
            do {
                // Try UTF-8 first (most common)
                text = try String(contentsOf: url, encoding: .utf8)
                pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])
                pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])
            } catch {
                // Fallback to other encodings if UTF-8 fails
                print("⚠️  [DocumentProcessor] UTF-8 decode failed, trying other encodings...")
                if let data = try? Data(contentsOf: url) {
                    if let decodedText = String(data: data, encoding: .isoLatin1) ?? String(data: data, encoding: .ascii) {
                        text = decodedText
                        pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])
                        print("   Successfully decoded with fallback encoding")
                    } else {
                        throw DocumentProcessingError.unsupportedEncoding
                    }
                } else {
                    throw error
                }
            }
            
        case .rtf:
            text = try extractTextFromRTF(url: url)
            pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])
            
        // Images - Use OCR
        case .png, .jpeg, .heic, .tiff, .gif, .image:
            print("   🔍 Image detected - applying OCR...")
            text = try await extractTextFromImage(url: url)
            pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 1, pageNumbers: [1])
            
        // Code files - Preserve as-is with syntax
        case .swift, .python, .javascript, .typescript, .java, .cpp, .c, .objc,
             .go, .rust, .ruby, .php, .html, .css, .json, .xml, .yaml, .sql, .shell, .code:
            print("   💻 Code file detected - preserving syntax...")
            text = try extractTextFromCode(url: url)
            pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])
            
        // CSV - Convert to structured text
        case .csv:
            print("   📊 CSV detected - converting to structured text...")
            text = try extractTextFromCSV(url: url)
            pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])
            
        // Office documents - Attempt extraction
        case .word, .excel, .powerpoint, .pages, .numbers, .keynote:
            print("   📄 Office document detected - attempting extraction...")
            text = try await extractTextFromOfficeDocument(url: url, type: type)
            pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])
            
        case .unknown:
            // Last resort: try treating as plain text
            print("⚠️  [DocumentProcessor] Unknown format, attempting plain text extraction...")
            if let attemptedText = try? String(contentsOf: url, encoding: .utf8), !attemptedText.isEmpty {
                text = attemptedText
                pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])
                print("   ✓ Successfully extracted as plain text")
            } else {
                print("❌ [DocumentProcessor] Unsupported format: \(url.pathExtension)")
                throw DocumentProcessingError.unsupportedFormat
            }
        }
        
        // Edge case: Empty or whitespace-only document
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            print("❌ [DocumentProcessor] Document is empty or contains only whitespace")
            throw DocumentProcessingError.emptyDocument
        }
        
        // Edge case: Very short document
        if trimmedText.count < 50 {
            print("⚠️  [DocumentProcessor] Warning: Very short document (\(trimmedText.count) chars)")
        }
        
        // Edge case: Suspiciously long document (possible issue)
        if text.count > 10_000_000 { // 10MB of text
            print("⚠️  [DocumentProcessor] Warning: Very large document (\(text.count) chars)")
        }
        
        return (text, pageInfo)
    }
    
    /// Extract text from PDF with page tracking for semantic chunking
    private func extractTextFromPDFWithPages(url: URL) async throws -> (text: String, pageInfo: PageInfo) {
        guard let pdfDocument = PDFDocument(url: url) else {
            print("❌ [DocumentProcessor] PDF load failed: \(url.lastPathComponent)")
            throw DocumentProcessingError.pdfLoadFailed
        }
        
        let pageCount = pdfDocument.pageCount
        print("   PDF pages: \(pageCount)")
        
        // Edge case: Empty PDF
        guard pageCount > 0 else {
            print("⚠️  [DocumentProcessor] PDF has zero pages")
            throw DocumentProcessingError.emptyDocument
        }
        
        var fullText = ""
        var pagesWithoutText = 0
        var ocrUsedCount = 0
        var totalOCRChars = 0
        
        // Extract text from all pages, with OCR fallback for image-only pages
        for pageIndex in 0..<pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }
            
            let pageStartTime = Date()
            
            // Try standard text extraction first
            if let pageText = page.string, !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                progressHandler?("page \(pageIndex + 1)/\(pageCount)")
                // Delay to ensure UI updates (increased for visibility)
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
                
                fullText += pageText + "\n\n"
                
                let pageTime = Date().timeIntervalSince(pageStartTime)
                print("   ✓ Page \(pageIndex + 1): \(pageText.count) chars (\(String(format: "%.2f", pageTime))s)")
            } else {
                // No extractable text - try OCR on the page image
                pagesWithoutText += 1
                
                // Update progress for OCR
                progressHandler?("page \(pageIndex + 1)/\(pageCount), OCR")
                // Small delay to ensure UI updates
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05s
                
                // Render page as image and apply OCR
                if let pageImage = renderPDFPageAsImage(page: page),
                   let ocrText = try? await performOCR(on: pageImage),
                   !ocrText.isEmpty {
                    fullText += ocrText + "\n\n"
                    ocrUsedCount += 1
                    totalOCRChars += ocrText.count
                    
                    let pageTime = Date().timeIntervalSince(pageStartTime)
                    print("   ✓ Page \(pageIndex + 1): OCR extracted \(ocrText.count) chars (\(String(format: "%.2f", pageTime))s)")
                }
            }
        }
        
        // Report OCR usage
        if ocrUsedCount > 0 {
            print("   📸 OCR applied to \(ocrUsedCount)/\(pageCount) pages (\(totalOCRChars) chars total)")
        }
        
        let pageInfo = PageInfo(
            totalPages: pageCount,
            ocrPagesUsed: ocrUsedCount,
            pageNumbers: Array(1...pageCount) // All pages processed
        )
        
        return (fullText, pageInfo)
    }
    
    /// Extract text from PDF using PDFKit (native iOS framework) - Legacy method
    /// Now with OCR fallback for image-only pages
    private func extractTextFromPDF(url: URL) async throws -> String {
        guard let pdfDocument = PDFDocument(url: url) else {
            print("❌ [DocumentProcessor] PDF load failed: \(url.lastPathComponent)")
            throw DocumentProcessingError.pdfLoadFailed
        }
        
        let pageCount = pdfDocument.pageCount
        print("   PDF pages: \(pageCount)")
        
        // Edge case: Empty PDF
        guard pageCount > 0 else {
            print("⚠️  [DocumentProcessor] PDF has zero pages")
            throw DocumentProcessingError.emptyDocument
        }
        
        var fullText = ""
        var pagesWithoutText = 0
        var ocrUsedCount = 0
        var totalOCRChars = 0
        
        // Extract text from all pages, with OCR fallback for image-only pages
        for pageIndex in 0..<pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }
            
            let pageStartTime = Date()
            
            // Try standard text extraction first
            if let pageText = page.string, !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                progressHandler?("page \(pageIndex + 1)/\(pageCount)")
                // Delay to ensure UI updates (increased for visibility)
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
                
                fullText += pageText + "\n\n"
                
                let pageTime = Date().timeIntervalSince(pageStartTime)
                print("   ✓ Page \(pageIndex + 1): \(pageText.count) chars (\(String(format: "%.2f", pageTime))s)")
            } else {
                // No extractable text - try OCR on the page image
                pagesWithoutText += 1
                
                // Update progress for OCR
                progressHandler?("page \(pageIndex + 1)/\(pageCount), OCR")
                // Small delay to ensure UI updates
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05s
                
                // Render page as image and apply OCR
                if let pageImage = renderPDFPageAsImage(page: page),
                   let ocrText = try? await performOCR(on: pageImage),
                   !ocrText.isEmpty {
                    fullText += ocrText + "\n\n"
                    ocrUsedCount += 1
                    totalOCRChars += ocrText.count
                    
                    let pageTime = Date().timeIntervalSince(pageStartTime)
                    print("   ✓ Page \(pageIndex + 1): OCR extracted \(ocrText.count) chars (\(String(format: "%.2f", pageTime))s)")
                }
            }
        }
        
        // Report OCR usage
        if ocrUsedCount > 0 {
            print("   📸 OCR applied to \(ocrUsedCount)/\(pageCount) pages (\(totalOCRChars) chars total)")
        }
        
        if pagesWithoutText > 0 && ocrUsedCount == 0 {
            print("   ⚠️ \(pagesWithoutText) pages had no extractable text (may be images)")
        }
        
        // Only throw error if NO text was extracted at all
        let trimmedText = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            if pagesWithoutText == pageCount {
                print("❌ [DocumentProcessor] PDF contains no extractable text (all pages are images)")
                print("💡 Hint: OCR attempted but found no text. Image quality may be too low.")
                print("💡 Suggestion: Try a higher quality scan or text-based PDF")
            }
            throw DocumentProcessingError.imageOnlyPDF
        }
        
        return fullText
    }
    
    /// Render a PDF page as an image for OCR processing
    private func renderPDFPageAsImage(page: PDFPage) -> CIImage? {
        let pageBounds = page.bounds(for: .mediaBox)
        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: pageBounds.size)
        let image = renderer.image { context in
            UIColor.white.set()
            context.fill(pageBounds)
            context.cgContext.translateBy(x: 0, y: pageBounds.size.height)
            context.cgContext.scaleBy(x: 1.0, y: -1.0)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        return CIImage(image: image)
        #elseif canImport(AppKit)
        let size = CGSize(width: pageBounds.size.width, height: pageBounds.size.height)
        guard size.width > 0 && size.height > 0 else { return nil }
        
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.set()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1.0, y: -1.0)
            page.draw(with: .mediaBox, to: ctx)
            ctx.restoreGState()
        }
        image.unlockFocus()
        
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cgImage = rep.cgImage else {
            return nil
        }
        return CIImage(cgImage: cgImage)
        #else
        return nil
        #endif
    }
    
    /// Extract text from RTF using native AttributedString
    private func extractTextFromRTF(url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtf
        ]
        
        var documentAttributes: NSDictionary?
        guard let attributedString = try? NSAttributedString(
            data: data,
            options: options,
            documentAttributes: &documentAttributes
        ) else {
            throw DocumentProcessingError.rtfParseFailed
        }
        return attributedString.string
    }
    
    /// Extract text from images using Vision framework OCR
    private func extractTextFromImage(url: URL) async throws -> String {
        progressHandler?("OCR scanning")
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s to show OCR status
        
        let startTime = Date()
        
        guard let image = CIImage(contentsOf: url) else {
            print("❌ [DocumentProcessor] Failed to load image: \(url.lastPathComponent)")
            throw DocumentProcessingError.imageLoadFailed
        }
        
        let imageSize = image.extent.size
        print("   Image dimensions: \(Int(imageSize.width))×\(Int(imageSize.height))px")
        
        let text = try await performOCR(on: image)
        let ocrTime = Date().timeIntervalSince(startTime)
        
        print("   ✓ OCR extracted \(text.count) chars in \(String(format: "%.2f", ocrTime))s")
        
        return text
    }
    
    /// Perform OCR on an image using Vision framework
    private func performOCR(on image: CIImage) async throws -> String {
        let requestHandler = VNImageRequestHandler(ciImage: image, options: [:])
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                
                // Extract text from all observations
                let recognizedText = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")
                
                continuation.resume(returning: recognizedText)
            }
            
            // Configure for maximum accuracy
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            // Support multiple languages
            request.recognitionLanguages = ["en-US", "es-ES", "fr-FR", "de-DE", "it-IT", "pt-BR", "zh-Hans", "ja-JP", "ko-KR", "ar-SA"]
            
            do {
                try requestHandler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// Extract text from code files - preserve syntax and structure
    private func extractTextFromCode(url: URL) throws -> String {
        // Try UTF-8 first (standard for code)
        if let code = try? String(contentsOf: url, encoding: .utf8) {
            return code
        }
        
        // Fallback to other encodings
        if let data = try? Data(contentsOf: url),
           let code = String(data: data, encoding: .isoLatin1) ?? String(data: data, encoding: .ascii) {
            return code
        }
        
        throw DocumentProcessingError.unsupportedEncoding
    }
    
    /// Extract text from CSV - convert to structured readable format
    private func extractTextFromCSV(url: URL) throws -> String {
        let csvContent = try String(contentsOf: url, encoding: .utf8)
        let lines = csvContent.components(separatedBy: .newlines)
        
        guard !lines.isEmpty else {
            throw DocumentProcessingError.emptyDocument
        }
        
        // Parse CSV and convert to readable format
        var structuredText = ""
        
        // Detect delimiter (comma or tab)
        let delimiter = lines.first?.contains("\t") == true ? "\t" : ","
        
        // Process header
        if let header = lines.first {
            let headers = header.components(separatedBy: delimiter)
            structuredText += "Table with columns: " + headers.joined(separator: ", ") + "\n\n"
        }
        
        // Process rows (limit to reasonable size for context)
        let rowsToProcess = min(lines.count - 1, 1000)
        for i in 1..<rowsToProcess {
            let row = lines[i]
            if !row.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let values = row.components(separatedBy: delimiter)
                structuredText += "Row \(i): " + values.joined(separator: " | ") + "\n"
            }
        }
        
        if lines.count > 1001 {
            structuredText += "\n(Note: CSV contains \(lines.count) total rows, showing first 1000 for efficiency)\n"
        }
        
        return structuredText
    }
    
    /// Extract text from Office documents (Word, Excel, PowerPoint, iWork)
    private func extractTextFromOfficeDocument(url: URL, type: DocumentType) async throws -> String {
        // For iWork documents (.pages, .numbers, .keynote), they're actually ZIP packages
        if type == .pages || type == .numbers || type == .keynote {
            return try extractTextFromIWorkDocument(url: url)
        }
        
        // For Microsoft Office formats, attempt extraction
        // .docx, .xlsx, .pptx are also ZIP packages with XML
        if type == .word || type == .excel || type == .powerpoint {
            return try extractTextFromOfficeXML(url: url, type: type)
        }
        
        // Legacy .doc, .xls, .ppt - limited support
        print("⚠️  [DocumentProcessor] Legacy Office format detected")
        print("💡 Suggestion: Convert to .docx, .xlsx, or .pptx for better support")
        throw DocumentProcessingError.legacyOfficeFormat
    }
    
    /// Extract text from iWork documents (Pages, Numbers, Keynote)
    private func extractTextFromIWorkDocument(url: URL) throws -> String {
        // iWork documents are packages - look for index.xml or similar
        // This is a simplified implementation
        print("⚠️  [DocumentProcessor] iWork document support is limited")
        print("💡 Suggestion: Export as PDF or text for full compatibility")
        
        // Try to read as a package
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            // Look for text content in the package
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
            while let file = enumerator?.nextObject() as? URL {
                if file.pathExtension == "xml" || file.pathExtension == "txt" {
                    if let content = try? String(contentsOf: file, encoding: .utf8), !content.isEmpty {
                        // Basic XML stripping for text extraction
                        let text = content.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            return text
                        }
                    }
                }
            }
        }
        
        throw DocumentProcessingError.iWorkExtractionFailed
    }
    
    /// Extract text from modern Office XML formats
    private func extractTextFromOfficeXML(url: URL, type: DocumentType) throws -> String {
        // Modern Office formats (.docx, .xlsx, .pptx) are ZIP files
        // They contain XML files with the actual content
        
        print("⚠️  [DocumentProcessor] Modern Office format detected")
        print("💡 Suggestion: For best results, export as PDF before importing")
        
        // This would require ZIP extraction and XML parsing
        // For now, suggest conversion
        throw DocumentProcessingError.officeFormatNeedsConversion
    }
    
    // MARK: - Chunking Strategy
    
    /// Intelligent text chunking strategy using semantic boundaries
    /// Splits on paragraphs first, then sentences, maintaining context overlap
    private func chunkText(_ text: String) -> [String] {
        var chunks: [String] = []
        
        // First, split by paragraphs (semantic boundaries)
        let paragraphs = text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        var currentChunk = ""
        var wordCount = 0
        
        for paragraph in paragraphs {
            let paragraphWords = paragraph.split(separator: " ")
            let paragraphWordCount = paragraphWords.count
            
            // If adding this paragraph exceeds target size, finalize current chunk
            if wordCount + paragraphWordCount > targetChunkSize && wordCount > 0 {
                chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))
                
                // Implement overlap by keeping last N words
                let overlapWords = currentChunk.split(separator: " ").suffix(chunkOverlap)
                currentChunk = overlapWords.joined(separator: " ") + " "
                wordCount = overlapWords.count
            }
            
            currentChunk += paragraph + "\n\n"
            wordCount += paragraphWordCount
        }
        
        // Add final chunk
        if !currentChunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        return chunks
    }
    
    // MARK: - Utilities
    
    private func detectDocumentType(url: URL) -> DocumentType {
        let pathExtension = url.pathExtension.lowercased()
        
        switch pathExtension {
        // Documents
        case "pdf":
            return .pdf
        case "txt":
            return .text
        case "md", "markdown", "mdown":
            return .markdown
        case "rtf":
            return .rtf
            
        // Images (OCR support)
        case "png":
            return .png
        case "jpg", "jpeg":
            return .jpeg
        case "heic", "heif":
            return .heic
        case "tiff", "tif":
            return .tiff
        case "gif":
            return .gif
        case "bmp", "webp":
            return .image
            
        // Code files
        case "swift":
            return .swift
        case "py", "pyw", "pyx":
            return .python
        case "js", "mjs", "cjs":
            return .javascript
        case "ts", "tsx":
            return .typescript
        case "java", "class":
            return .java
        case "cpp", "cc", "cxx", "c++":
            return .cpp
        case "c", "h":
            return .c
        case "m", "mm":
            return .objc
        case "go":
            return .go
        case "rs":
            return .rust
        case "rb":
            return .ruby
        case "php":
            return .php
        case "html", "htm":
            return .html
        case "css", "scss", "sass", "less":
            return .css
        case "json", "jsonc":
            return .json
        case "xml":
            return .xml
        case "yaml", "yml":
            return .yaml
        case "sql":
            return .sql
        case "sh", "bash", "zsh", "fish":
            return .shell
        case "kt", "kts", "scala", "clj", "ex", "exs", "elm", "hs", "lua", "pl", "r", "dart", "vim":
            return .code
            
        // Office documents
        case "doc", "docx":
            return .word
        case "xls", "xlsx":
            return .excel
        case "ppt", "pptx":
            return .powerpoint
        case "pages":
            return .pages
        case "numbers":
            return .numbers
        case "key":
            return .keynote
            
        // Data formats
        case "csv":
            return .csv
            
        default:
            // Try to detect by content type as fallback
            if let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey]),
               let contentType = resourceValues.contentType {
                
                if contentType.conforms(to: .image) {
                    return .image
                } else if contentType.conforms(to: .plainText) || contentType.conforms(to: .sourceCode) {
                    return .code
                }
            }
            
            return .unknown
        }
    }
}

// MARK: - Errors

enum DocumentProcessingError: LocalizedError {
    case unsupportedFormat
    case pdfLoadFailed
    case emptyDocument
    case imageOnlyPDF
    case rtfParseFailed
    case fileNotFound
    case unsupportedEncoding
    case corruptedFile
    case imageLoadFailed
    case ocrFailed
    case legacyOfficeFormat
    case officeFormatNeedsConversion
    case iWorkExtractionFailed
    
    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Unsupported document format"
        case .pdfLoadFailed:
            return "Failed to load PDF document"
        case .emptyDocument:
            return "Document contains no text"
        case .imageOnlyPDF:
            return "PDF contains only images (no extractable text). OCR attempted but no text found. Try a higher quality scan or text-based PDF."
        case .rtfParseFailed:
            return "Failed to parse RTF document"
        case .fileNotFound:
            return "File not found at specified location"
        case .unsupportedEncoding:
            return "Document encoding not supported"
        case .corruptedFile:
            return "File appears to be corrupted"
        case .imageLoadFailed:
            return "Failed to load image file"
        case .ocrFailed:
            return "OCR text recognition failed"
        case .legacyOfficeFormat:
            return "Legacy Office format detected. Please convert to .docx, .xlsx, or .pptx for better support, or export as PDF."
        case .officeFormatNeedsConversion:
            return "Office document detected. For best results, export as PDF before importing."
        case .iWorkExtractionFailed:
            return "iWork document support is limited. Please export as PDF or text for full compatibility."
        }
    }
}
