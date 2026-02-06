# Apple Document Intelligence Reference

> **Comprehensive reference for Apple's document processing, OCR, NLP, and ML frameworks.**
> Last updated: 2025 | iOS 26.0+ APIs included

---

## Table of Contents

1. [Vision Framework](#1-vision-framework)
2. [VisionKit Framework](#2-visionkit-framework)
3. [Natural Language Framework](#3-natural-language-framework)
4. [PDFKit Framework](#4-pdfkit-framework)
5. [Speech Framework](#5-speech-framework)
6. [Core ML Framework](#6-core-ml-framework)
7. [Create ML Framework](#7-create-ml-framework)
8. [Foundation Models Framework (iOS 26+)](#8-foundation-models-framework-ios-26)
9. [CoreML Tools (Python)](#9-coreml-tools-python)
10. [Framework Comparison Matrix](#10-framework-comparison-matrix)

---

## 1. Vision Framework

**Import:** `import Vision`
**Availability:** iOS 11.0+, macOS 10.13+, tvOS 11.0+, visionOS 1.0+

The Vision framework applies computer vision algorithms to perform tasks on input images and video. Use Vision for face detection, text recognition, barcode recognition, image registration, object tracking, and more.

### 1.1 Text Recognition (OCR)

#### VNRecognizeTextRequest

The primary API for optical character recognition.

```swift
import Vision

let request = VNRecognizeTextRequest { request, error in
    guard let observations = request.results as? [VNRecognizedTextObservation] else { return }

    for observation in observations {
        // Get the top candidate
        guard let topCandidate = observation.topCandidates(1).first else { continue }
        print("Text: \(topCandidate.string)")
        print("Confidence: \(topCandidate.confidence)")
        print("Bounding Box: \(observation.boundingBox)")
    }
}

// Configure recognition
request.recognitionLevel = .accurate  // or .fast
request.usesLanguageCorrection = true
request.recognitionLanguages = ["en-US", "de-DE", "fr-FR"]
request.customWords = ["OpenIntelligence", "RAG"]  // Domain-specific vocabulary
request.minimumTextHeight = 0.0  // 0.0-1.0, filter small text

// Execute
let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
try handler.perform([request])
```

**Recognition Levels:**
| Level | Description | Speed | Accuracy |
|-------|-------------|-------|----------|
| `.fast` | Character-based, optimized for speed | ⚡⚡⚡ | ⭐⭐ |
| `.accurate` | Neural network-based, higher quality | ⚡ | ⭐⭐⭐⭐⭐ |

**Supported Languages (18 total):**

- English, French, Italian, German, Spanish, Portuguese (Brazilian)
- Chinese (Simplified/Traditional), Japanese, Korean
- Ukrainian, Russian, Polish, Czech, Romanian
- Thai, Vietnamese, Arabic, Hebrew

**Revision History:**

- Revision 1: iOS 13 (initial)
- Revision 2: iOS 14 (improved accuracy)
- Revision 3: iOS 16+ (current, best quality)

#### VNRecognizedTextObservation Properties

```swift
observation.boundingBox        // CGRect in normalized coordinates (0-1)
observation.topCandidates(10)  // Up to 10 alternative transcriptions
observation.confidence         // Float 0.0-1.0

// Get bounding box for specific text range
let range = text.startIndex..<text.endIndex
let boundingBox = try observation.boundingBox(for: range)
```

### 1.2 Document Detection

#### VNDetectDocumentSegmentationRequest (iOS 15+)

Detects document boundaries with pixel-precise masks.

```swift
let documentRequest = VNDetectDocumentSegmentationRequest { request, error in
    guard let observation = request.results?.first as? VNRectangleObservation else { return }

    // Document corners
    let topLeft = observation.topLeft
    let topRight = observation.topRight
    let bottomLeft = observation.bottomLeft
    let bottomRight = observation.bottomRight

    // Pixel mask for document region
    if let pixelBuffer = observation.pixelBuffer {
        // Use for precise document extraction
    }
}
```

### 1.3 RecognizeDocumentsRequest (iOS 26.0+ - NEW!)

**The most advanced document analysis API**, extracting structured content including text, tables, lists, and barcodes.

```swift
import Vision

// Create the request
let request = RecognizeDocumentsRequest()

// Process an image
let handler = ImageRequestHandler(cgImage: cgImage)
let observations = try await handler.perform(request)

for observation in observations {
    // Access structured text
    for word in observation.words {
        print("Word: \(word.transcript)")
        print("Bounds: \(word.boundingBox)")
    }

    for line in observation.lines {
        print("Line: \(line.transcript)")
    }

    for paragraph in observation.paragraphs {
        print("Paragraph: \(paragraph.transcript)")
    }

    // Access tables
    for table in observation.tables {
        for row in table.rows {
            for cell in row.cells {
                print("Cell content: \(cell.transcript)")
                print("Cell bounds: \(cell.boundingBox)")

                // Data detection within cells
                for dataItem in cell.dataDetectorTypes {
                    // Phone numbers, emails, addresses, etc.
                }
            }
        }
    }

    // Access lists
    for list in observation.lists {
        for item in list.items {
            print("List item: \(item.transcript)")
        }
    }

    // Access barcodes
    for barcode in observation.barcodes {
        print("Barcode: \(barcode.payloadString)")
    }
}
```

**DocumentObservation Structure:**

- `words`: Individual word observations with bounding boxes
- `lines`: Line-level groupings
- `paragraphs`: Paragraph-level groupings
- `tables`: Detected tables with rows and cells
- `lists`: Detected lists with items
- `barcodes`: Machine-readable codes

### 1.4 Barcode Detection

```swift
let barcodeRequest = VNDetectBarcodesRequest { request, error in
    guard let observations = request.results as? [VNBarcodeObservation] else { return }

    for observation in observations {
        print("Symbology: \(observation.symbology)")
        print("Payload: \(observation.payloadStringValue ?? "N/A")")
        print("Bounds: \(observation.boundingBox)")
    }
}

// Supported symbologies
barcodeRequest.symbologies = [.qr, .ean13, .code128, .pdf417, .aztec, .dataMatrix]
```

**Supported Barcode Types:**

- 1D: Code 39, Code 93, Code 128, EAN-8, EAN-13, UPC-E, ITF-14, Codabar, I2of5
- 2D: QR Code, Data Matrix, Aztec, PDF417, MicroQR, MicroPDF417

### 1.5 Best Practices for Vision OCR

```swift
// Optimal image preprocessing
func prepareImageForOCR(image: UIImage) -> CGImage? {
    // 1. Scale to optimal DPI (300-360 DPI recommended)
    let scaleFactor: CGFloat = 5.0  // For 72 DPI source → 360 DPI
    let scaledSize = CGSize(
        width: image.size.width * scaleFactor,
        height: image.size.height * scaleFactor
    )

    UIGraphicsBeginImageContextWithOptions(scaledSize, true, 1.0)
    image.draw(in: CGRect(origin: .zero, size: scaledSize))
    let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    return scaledImage?.cgImage
}

// Batch processing for multi-page documents
func processMultiplePages(_ images: [CGImage]) async throws -> [String] {
    try await withThrowingTaskGroup(of: (Int, String).self) { group in
        for (index, image) in images.enumerated() {
            group.addTask {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate

                let handler = VNImageRequestHandler(cgImage: image)
                try handler.perform([request])

                let text = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n") ?? ""

                return (index, text)
            }
        }

        var results = [(Int, String)]()
        for try await result in group {
            results.append(result)
        }
        return results.sorted { $0.0 < $1.0 }.map { $0.1 }
    }
}
```

---

## 2. VisionKit Framework

**Import:** `import VisionKit`
**Availability:** iOS 13.0+ (varies by feature)

VisionKit provides high-level UI components for document scanning, Live Text, and data scanning.

### 2.1 VNDocumentCameraViewController (iOS 13+)

Built-in document scanner with auto-capture, edge detection, and perspective correction.

```swift
import VisionKit

class DocumentScannerViewController: UIViewController, VNDocumentCameraViewControllerDelegate {

    func presentScanner() {
        guard VNDocumentCameraViewController.isSupported else {
            print("Document scanning not supported")
            return
        }

        let scanner = VNDocumentCameraViewController()
        scanner.delegate = self
        present(scanner, animated: true)
    }

    // MARK: - Delegate Methods

    func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                       didFinishWith scan: VNDocumentCameraScan) {
        controller.dismiss(animated: true)

        // Process scanned pages
        for pageIndex in 0..<scan.pageCount {
            let image = scan.imageOfPage(at: pageIndex)
            // Process each page image
            processPage(image)
        }
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                       didFailWithError error: Error) {
        controller.dismiss(animated: true)
        print("Scanner failed: \(error)")
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true)
    }
}
```

### 2.2 DataScannerViewController (iOS 16+)

Live camera scanning for text and machine-readable codes with real-time recognition.

**Requirements:**

- iOS 16.0+
- A12 Bionic chip or later
- Device with camera

```swift
import VisionKit

class LiveScannerViewController: UIViewController {

    var dataScannerVC: DataScannerViewController?

    func startScanning() async {
        // Check availability
        guard DataScannerViewController.isSupported else {
            print("Data scanning not supported")
            return
        }

        guard DataScannerViewController.isAvailable else {
            print("Data scanning not available (check camera permissions)")
            return
        }

        // Configure recognized data types
        let recognizedDataTypes: Set<DataScannerViewController.RecognizedDataType> = [
            .text(languages: ["en", "de", "fr"]),
            .barcode(symbologies: [.qr, .ean13, .code128])
        ]

        // Create scanner
        dataScannerVC = DataScannerViewController(
            recognizedDataTypes: recognizedDataTypes,
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )

        dataScannerVC?.delegate = self

        if let scanner = dataScannerVC {
            present(scanner, animated: true) {
                try? scanner.startScanning()
            }
        }
    }
}

extension LiveScannerViewController: DataScannerViewControllerDelegate {

    func dataScanner(_ dataScanner: DataScannerViewController,
                     didTapOn item: RecognizedItem) {
        switch item {
        case .text(let text):
            print("Tapped text: \(text.transcript)")
        case .barcode(let barcode):
            print("Tapped barcode: \(barcode.payloadStringValue ?? "N/A")")
        @unknown default:
            break
        }
    }

    func dataScanner(_ dataScanner: DataScannerViewController,
                     didAdd addedItems: [RecognizedItem],
                     allItems: [RecognizedItem]) {
        for item in addedItems {
            switch item {
            case .text(let text):
                print("Found text: \(text.transcript)")
                print("Bounds: \(text.bounds)")
            case .barcode(let barcode):
                print("Found barcode: \(barcode.payloadStringValue ?? "N/A")")
            @unknown default:
                break
            }
        }
    }
}
```

### 2.3 ImageAnalyzer & Live Text (iOS 16+)

Analyze images for text and enable Live Text interactions.

```swift
import VisionKit

class LiveTextViewController: UIViewController {

    let imageView = UIImageView()
    let analyzer = ImageAnalyzer()
    var interaction: ImageAnalysisInteraction!

    override func viewDidLoad() {
        super.viewDidLoad()

        // Setup interaction
        interaction = ImageAnalysisInteraction()
        interaction.preferredInteractionTypes = [.textSelection, .dataDetectors]
        imageView.addInteraction(interaction)

        // Analyze image
        analyzeImage()
    }

    func analyzeImage() {
        guard let image = imageView.image else { return }

        Task {
            let configuration = ImageAnalyzer.Configuration([
                .text,
                .machineReadableCode
            ])

            do {
                let analysis = try await analyzer.analyze(image, configuration: configuration)

                // Apply analysis to interaction
                interaction.analysis = analysis

                // Check what was found
                if analysis.hasResults(for: .text) {
                    print("Text found in image")
                }

                if analysis.hasResults(for: .machineReadableCode) {
                    print("Barcodes found in image")
                }

            } catch {
                print("Analysis failed: \(error)")
            }
        }
    }
}
```

**ImageAnalysisInteraction Types:**
| Type | Description |
|------|-------------|
| `.textSelection` | Enable text selection/copy |
| `.dataDetectors` | Enable phone/email/address/link detection |
| `.imageSubject` | Enable subject lifting (iOS 17+) |

### 2.4 Subject Lifting (iOS 17+)

Extract foreground subjects from images.

```swift
let interaction = ImageAnalysisInteraction()
interaction.preferredInteractionTypes = [.imageSubject]

// Programmatic subject extraction
if interaction.analysis?.hasResults(for: .imageSubject) == true {
    let subject = try await interaction.subject
    // subject is a UIImage of the extracted foreground
}
```

---

## 3. Natural Language Framework

**Import:** `import NaturalLanguage`
**Availability:** iOS 12.0+, macOS 10.14+

Analyze natural language text for language identification, tokenization, lemmatization, parts of speech, and named entity recognition.

### 3.1 NLTagger - Linguistic Analysis

```swift
import NaturalLanguage

let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass, .lemma])
tagger.string = "Apple announced the new iPhone at WWDC in San Francisco."

// Named Entity Recognition
tagger.enumerateTags(in: tagger.string!.startIndex..<tagger.string!.endIndex,
                      unit: .word,
                      scheme: .nameType,
                      options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, tokenRange in
    if let tag = tag {
        let entity = String(tagger.string![tokenRange])
        switch tag {
        case .personalName:
            print("Person: \(entity)")
        case .placeName:
            print("Place: \(entity)")
        case .organizationName:
            print("Organization: \(entity)")
        default:
            break
        }
    }
    return true
}

// Parts of Speech
tagger.enumerateTags(in: tagger.string!.startIndex..<tagger.string!.endIndex,
                      unit: .word,
                      scheme: .lexicalClass,
                      options: [.omitWhitespace, .omitPunctuation]) { tag, tokenRange in
    if let tag = tag {
        let word = String(tagger.string![tokenRange])
        print("\(word): \(tag.rawValue)")
        // noun, verb, adjective, adverb, etc.
    }
    return true
}
```

**NLTagScheme Options:**
| Scheme | Description |
|--------|-------------|
| `.tokenType` | Token classification (word, punctuation, whitespace) |
| `.lexicalClass` | Parts of speech (noun, verb, adjective, etc.) |
| `.nameType` | Named entity type (person, place, organization) |
| `.nameTypeOrLexicalClass` | Combined scheme |
| `.lemma` | Base form of word |
| `.language` | Detected language |
| `.script` | Writing script |
| `.sentimentScore` | Sentiment analysis |

### 3.2 NLTokenizer - Text Segmentation

```swift
let tokenizer = NLTokenizer(unit: .word)
tokenizer.string = "Hello, world! How are you?"

tokenizer.enumerateTokens(in: tokenizer.string!.startIndex..<tokenizer.string!.endIndex) { range, _ in
    let token = String(tokenizer.string![range])
    print("Token: \(token)")
    return true
}

// Units: .word, .sentence, .paragraph, .document
```

### 3.3 NLLanguageRecognizer

```swift
let recognizer = NLLanguageRecognizer()
recognizer.processString("Bonjour, comment allez-vous?")

if let language = recognizer.dominantLanguage {
    print("Language: \(language.rawValue)")  // "fr"
}

// Get confidence for multiple languages
let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
for (language, confidence) in hypotheses {
    print("\(language.rawValue): \(confidence)")
}
```

### 3.4 NLEmbedding - Text Similarity

Find similar strings using vector embeddings.

```swift
// Built-in word embeddings
if let embedding = NLEmbedding.wordEmbedding(for: .english) {
    // Find similar words
    let neighbors = embedding.neighbors(for: "computer", maximumCount: 5, distanceType: .cosine)
    for (word, distance) in neighbors {
        print("\(word): \(distance)")
    }

    // Calculate distance between words
    let distance = embedding.distance(between: "king", and: "queen", distanceType: .cosine)
    print("Distance: \(distance)")

    // Get vector for word
    if let vector = embedding.vector(for: "apple") {
        print("Dimensions: \(vector.count)")  // Typically 300-512
    }
}

// Sentence embeddings
if let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english) {
    let distance = sentenceEmbedding.distance(
        between: "How are you?",
        and: "How's it going?",
        distanceType: .cosine
    )
    print("Sentence similarity: \(1 - distance)")
}
```

### 3.5 NLContextualEmbedding (iOS 17+)

Contextual embeddings that understand word meaning in context.

```swift
if let embedding = NLContextualEmbedding(language: .english) {
    let result = embedding.embeddingResult(for: "The bank is by the river.")

    // "bank" here means riverbank, not financial institution
    for tokenRange in result.tokenRanges {
        let vector = result.vector(at: tokenRange.lowerBound)
        print("Vector: \(vector)")
    }
}
```

### 3.6 Custom NLModel

Use models trained with Create ML.

```swift
// Load custom model
let modelURL = Bundle.main.url(forResource: "MyTextClassifier", withExtension: "mlmodelc")!
let customModel = try NLModel(contentsOf: modelURL)

// Use with tagger
let tagger = NLTagger(tagSchemes: [.nameType])
tagger.setModels([customModel], forTagScheme: .nameType)

// Or direct prediction
let prediction = customModel.predictedLabel(for: "This is a sample text")
print("Predicted: \(prediction ?? "unknown")")
```

### 3.7 NLGazetteer - Custom Vocabulary

Prioritize specific terms in recognition.

```swift
// Create gazetteer from dictionary
let terms = [
    "OpenIntelligence": "product",
    "RAG": "technology",
    "embeddings": "technology"
]

let gazetteerURL = try NLGazetteer.write(terms, language: .english, to: tempURL)
let gazetteer = try NLGazetteer(contentsOf: gazetteerURL)

// Attach to tagger
tagger.setGazetteers([gazetteer], for: .nameType)
```

---

## 4. PDFKit Framework

**Import:** `import PDFKit`
**Availability:** iOS 11.0+, macOS 10.4+

Display, navigate, and extract content from PDF documents.

### 4.1 PDFDocument - Core Document Operations

```swift
import PDFKit

// Load PDF
let pdfURL = Bundle.main.url(forResource: "document", withExtension: "pdf")!
guard let document = PDFDocument(url: pdfURL) else { return }

// Or from data
let document = PDFDocument(data: pdfData)

// Document properties
print("Page count: \(document.pageCount)")
print("Is encrypted: \(document.isEncrypted)")
print("Is locked: \(document.isLocked)")

// Unlock protected PDF
if document.isLocked {
    document.unlock(withPassword: "password")
}

// Search
let selections = document.findString("search term", withOptions: .caseInsensitive)
for selection in selections {
    print("Found on page: \(selection.pages.first?.label ?? "?")")
    print("Bounds: \(selection.bounds(for: selection.pages.first!))")
}

// Document attributes
if let attributes = document.documentAttributes {
    print("Title: \(attributes[.titleAttribute] ?? "N/A")")
    print("Author: \(attributes[.authorAttribute] ?? "N/A")")
    print("Subject: \(attributes[.subjectAttribute] ?? "N/A")")
    print("Creator: \(attributes[.creatorAttribute] ?? "N/A")")
}
```

### 4.2 PDFPage - Page Operations

```swift
// Access pages
for pageIndex in 0..<document.pageCount {
    guard let page = document.page(at: pageIndex) else { continue }

    // Extract text
    if let text = page.string {
        print("Page \(pageIndex + 1) text: \(text)")
    }

    // Attributed text (preserves formatting)
    if let attributedText = page.attributedString {
        print("Attributed: \(attributedText)")
    }

    // Character count
    print("Characters: \(page.numberOfCharacters)")

    // Page bounds
    let mediaBox = page.bounds(for: .mediaBox)
    let cropBox = page.bounds(for: .cropBox)

    // Rotation
    print("Rotation: \(page.rotation)°")

    // Render to image
    let thumbnail = page.thumbnail(of: CGSize(width: 200, height: 280), for: .mediaBox)

    // Annotations
    for annotation in page.annotations {
        print("Annotation: \(annotation.type ?? "unknown")")
    }
}
```

### 4.3 PDFView - Display PDF

```swift
import PDFKit
import SwiftUI

struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = PDFDocument(url: url)
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
```

### 4.4 PDFSelection - Text Selection

```swift
// Get text in a region
let page = document.page(at: 0)!
let rect = CGRect(x: 100, y: 100, width: 200, height: 50)
if let selection = page.selection(for: rect) {
    print("Selected text: \(selection.string ?? "N/A")")
}

// Select word at point
let point = CGPoint(x: 150, y: 150)
if let wordSelection = page.selectionForWord(at: point) {
    print("Word: \(wordSelection.string ?? "N/A")")
}

// Select line at point
if let lineSelection = page.selectionForLine(at: point) {
    print("Line: \(lineSelection.string ?? "N/A")")
}
```

### 4.5 Creating PDFs

```swift
// Create PDF from images
let pdfDocument = PDFDocument()

for (index, image) in images.enumerated() {
    if let page = PDFPage(image: image) {
        pdfDocument.insert(page, at: index)
    }
}

// Save
let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("output.pdf")
pdfDocument.write(to: outputURL)
```

---

## 5. Speech Framework

**Import:** `import Speech`
**Availability:** iOS 10.0+, macOS 10.15+

Perform speech recognition on live or recorded audio.

### 5.1 SFSpeechRecognizer - Speech to Text

```swift
import Speech

class SpeechRecognitionService {

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private var recognitionTask: SFSpeechRecognitionTask?

    // Check authorization
    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { status in
            switch status {
            case .authorized:
                print("Speech recognition authorized")
            case .denied:
                print("User denied access")
            case .restricted:
                print("Speech recognition restricted")
            case .notDetermined:
                print("Not yet determined")
            @unknown default:
                break
            }
        }
    }

    // Recognize from audio file
    func recognizeAudioFile(url: URL) {
        let request = SFSpeechURLRecognitionRequest(url: url)

        // Configure
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true  // Offline mode
        request.addsPunctuation = true
        request.contextualStrings = ["OpenIntelligence", "RAG", "embedding"]

        recognitionTask = speechRecognizer.recognitionTask(with: request) { result, error in
            if let result = result {
                let text = result.bestTranscription.formattedString
                print("Transcription: \(text)")

                if result.isFinal {
                    print("Final result received")
                }
            }

            if let error = error {
                print("Error: \(error)")
            }
        }
    }

    // Check on-device support
    func checkOnDeviceSupport() -> Bool {
        return speechRecognizer.supportsOnDeviceRecognition
    }
}
```

### 5.2 Live Audio Recognition

```swift
import Speech
import AVFoundation

class LiveSpeechRecognizer {

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer()!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func startListening() throws {
        // Cancel previous task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Create request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true
        recognitionRequest?.requiresOnDeviceRecognition = speechRecognizer.supportsOnDeviceRecognition

        // Get audio input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }

        // Start recognition
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest!) { result, error in
            if let result = result {
                let text = result.bestTranscription.formattedString
                print("Live: \(text)")
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
    }
}
```

### 5.3 SpeechAnalyzer (iOS 26+ - NEW!)

Advanced speech analysis with the new Speech framework architecture.

```swift
import Speech

actor SpeechAnalysisService {

    private var analyzer: SpeechAnalyzer?

    func transcribe(audioURL: URL) async throws -> String {
        // Ensure assets are available
        let inventory = AssetInventory.shared
        let transcriber = SpeechTranscriber(locale: .current)

        try await inventory.ensureAssets(for: transcriber)

        // Create analyzer
        analyzer = try await SpeechAnalyzer(modules: [transcriber])

        // Process audio
        var fullTranscript = ""

        for try await input in AnalyzerInput.audioFile(url: audioURL) {
            let results = try await analyzer?.analyze(input)

            if let transcription = results?.first(where: { $0 is SpeechTranscriber.Result })
                as? SpeechTranscriber.Result {
                fullTranscript += transcription.text
            }
        }

        return fullTranscript
    }
}
```

**New Speech Framework Classes (iOS 26+):**
| Class | Description |
|-------|-------------|
| `SpeechAnalyzer` | Main analysis session manager |
| `SpeechTranscriber` | General-purpose transcription |
| `DictationTranscriber` | Dictation-optimized transcription |
| `SpeechDetector` | Voice activity detection (VAD) |
| `AssetInventory` | Asset management for offline use |
| `AnalysisContext` | Shared context between analyzers |

### 5.4 Custom Language Model

Train domain-specific speech recognition.

```swift
// Prepare training data
let customData = SFCustomLanguageModelData(
    locale: Locale(identifier: "en-US"),
    identifier: "com.myapp.custommodel",
    version: "1.0"
)

// Add phrases
customData.insert("OpenIntelligence", count: 100)
customData.insert("retrieval augmented generation", count: 50)
customData.insert("vector embeddings", count: 50)

// Export for training
let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("training_data")
try customData.export(to: outputURL)

// Train model (done externally with Create ML or Apple tools)
// Then load and use:
let modelConfig = SFSpeechLanguageModel.Configuration(
    languageModel: trainedModelURL,
    vocabulary: vocabularyURL
)
recognitionRequest.customizedLanguageModel = modelConfig
```

---

## 6. Core ML Framework

**Import:** `import CoreML`
**Availability:** iOS 11.0+, macOS 10.13+, watchOS 4.0+

Integrate machine learning models into your app with on-device inference.

### 6.1 MLModel - Model Loading and Inference

```swift
import CoreML

// Load model (generated wrapper class)
let model = try MyImageClassifier(configuration: MLModelConfiguration())

// Or load dynamically
let modelURL = Bundle.main.url(forResource: "MyModel", withExtension: "mlmodelc")!
let mlModel = try MLModel(contentsOf: modelURL)

// With configuration
let config = MLModelConfiguration()
config.computeUnits = .all  // .cpuOnly, .cpuAndGPU, .cpuAndNeuralEngine, .all
config.allowLowPrecisionAccumulationOnGPU = true

let configuredModel = try MLModel(contentsOf: modelURL, configuration: config)

// Make prediction
let input = MyModelInput(feature1: value1, feature2: value2)
let output = try model.prediction(input: input)
print("Result: \(output.label)")
print("Confidence: \(output.labelProbability)")
```

### 6.2 MLModelConfiguration - Compute Units

```swift
let config = MLModelConfiguration()

// Compute unit options
config.computeUnits = .cpuOnly           // CPU only
config.computeUnits = .cpuAndGPU         // CPU + GPU
config.computeUnits = .cpuAndNeuralEngine // CPU + Neural Engine
config.computeUnits = .all               // All available (default)

// GPU optimization
config.allowLowPrecisionAccumulationOnGPU = true
config.preferredMetalDevice = MTLCreateSystemDefaultDevice()

// Model parameters
config.parameters = [
    MLParameterKey.learningRate: 0.001,
    MLParameterKey.epochs: 10
]
```

### 6.3 Batch Predictions

```swift
// Batch provider for multiple inputs
let batchInputs: [MLFeatureProvider] = inputs.map { input in
    try! MLDictionaryFeatureProvider(dictionary: [
        "input": MLFeatureValue(string: input)
    ])
}

let batchProvider = MLArrayBatchProvider(array: batchInputs)
let batchResults = try model.predictions(fromBatch: batchProvider)

for i in 0..<batchResults.count {
    let result = batchResults.features(at: i)
    print("Result \(i): \(result.featureValue(for: "output")!)")
}
```

### 6.4 MLComputeDevice - Device Selection

```swift
// List available compute devices
let devices = MLModel.availableComputeDevices

for device in devices {
    switch device {
    case .cpu(let cpuDevice):
        print("CPU: available")
    case .gpu(let gpuDevice):
        print("GPU: \(gpuDevice.name)")
    case .neuralEngine(let neDevice):
        print("Neural Engine: available")
    @unknown default:
        break
    }
}
```

### 6.5 Async Model Loading (iOS 16+)

```swift
// Async loading
Task {
    let model = try await MLModel.load(contentsOf: modelURL, configuration: config)
    let output = try model.prediction(from: inputProvider)
}

// Compile model at runtime
let compiledURL = try await MLModel.compileModel(at: sourceModelURL)
```

### 6.6 On-Device Model Updates

```swift
import CoreML

// Create update task
let updateTask = try MLUpdateTask(
    forModelAt: modelURL,
    trainingData: trainingBatchProvider,
    configuration: config,
    completionHandler: { context in
        if context.task.state == .completed {
            // Save updated model
            try? context.model.write(to: updatedModelURL)
        }
    }
)

// Track progress
updateTask.progressHandler = { context in
    let progress = context.metrics[.epochProgress] as? Double ?? 0
    print("Training progress: \(progress * 100)%")
}

// Start training
updateTask.resume()
```

### 6.7 MLTensor (iOS 18+)

New tensor operations for ML workloads.

```swift
import CoreML

// Create tensor
let tensor = MLTensor([1.0, 2.0, 3.0, 4.0], shape: [2, 2])

// Operations
let result = tensor.matmul(otherTensor)
let softmax = tensor.softmax()
let normalized = tensor.layerNorm()

// Compute policy
withMLTensorComputePolicy(.cpuAndNeuralEngine) {
    let output = tensor.matmul(weights)
}
```

---

## 7. Create ML Framework

**Import:** `import CreateML`
**Availability:** iOS 15.0+, macOS 10.14+

Train custom machine learning models with Swift.

### 7.1 MLTextClassifier

Train text classification models.

```swift
import CreateML

// Prepare training data
let trainingData = try MLDataTable(contentsOf: trainingDataURL)

// Create and train classifier
let classifier = try MLTextClassifier(
    trainingData: trainingData,
    textColumn: "text",
    labelColumn: "label",
    parameters: MLTextClassifier.ModelParameters(
        algorithm: .maxEnt,  // or .crf, .transferLearning
        language: .english,
        validationData: validationData
    )
)

// Evaluate
print("Training accuracy: \(classifier.trainingMetrics.classificationError)")
print("Validation accuracy: \(classifier.validationMetrics.classificationError)")

// Test
let prediction = try classifier.prediction(from: "This is a test sentence")
print("Predicted: \(prediction)")

// Save model
try classifier.write(to: outputURL, metadata: MLModelMetadata(
    author: "MyApp",
    shortDescription: "Custom text classifier",
    version: "1.0"
))
```

### 7.2 MLWordTagger

Train word-level tagging models.

```swift
let tagger = try MLWordTagger(
    trainingData: trainingData,
    textColumn: "text",
    tokensColumn: "tokens",
    labelColumn: "labels",
    parameters: MLWordTagger.ModelParameters(
        algorithm: .crf,
        language: .english
    )
)

// Predict tags for words
let tagged = try tagger.prediction(from: "Apple is a technology company")
// Returns: [("Apple", "ORG"), ("is", "O"), ("a", "O"), ...]
```

### 7.3 MLWordEmbedding

Create custom word embeddings.

```swift
// Create embedding from dictionary
let embedding = try MLWordEmbedding(dictionary: [
    "king": [0.1, 0.2, 0.3, 0.4, 0.5],
    "queen": [0.11, 0.21, 0.31, 0.41, 0.51],
    "man": [0.5, 0.4, 0.3, 0.2, 0.1],
    "woman": [0.51, 0.41, 0.31, 0.21, 0.11]
])

// Find similar words
let neighbors = try embedding.prediction(
    from: "king",
    maxCount: 5,
    maxDistance: 1.0,
    distanceType: .cosine
)

// Save as CoreML model
try embedding.write(to: embeddingModelURL)
```

### 7.4 MLGazetteer

Create custom term dictionaries.

```swift
let gazetteer = try MLGazetteer(dictionary: [
    "California": "STATE",
    "New York": "STATE",
    "Apple": "COMPANY",
    "Microsoft": "COMPANY"
])

try gazetteer.write(to: gazetteerURL)
```

### 7.5 MLImageClassifier

Train image classification models.

```swift
let classifier = try MLImageClassifier(
    trainingData: .labeledDirectories(at: trainingImagesURL),
    parameters: MLImageClassifier.ModelParameters(
        featureExtractor: .scenePrint(revision: 1),
        validationData: .labeledDirectories(at: validationImagesURL),
        maxIterations: 100
    )
)

print("Training accuracy: \(classifier.trainingMetrics.classificationError)")
try classifier.write(to: modelOutputURL)
```

### 7.6 MLSoundClassifier

Train audio classification models.

```swift
let soundClassifier = try MLSoundClassifier(
    trainingData: .labeledDirectories(at: audioFilesURL),
    parameters: MLSoundClassifier.ModelParameters(
        validationData: .labeledDirectories(at: validationAudioURL)
    )
)

try soundClassifier.write(to: soundModelURL)
```

---

## 8. Foundation Models Framework (iOS 26+)

**Import:** `import FoundationModels`
**Availability:** iOS 26.0+, macOS 26.0+

Access Apple's on-device large language model for text generation, summarization, and tool calling.

### 8.1 SystemLanguageModel - Basic Usage

```swift
import FoundationModels

// Check availability
guard SystemLanguageModel.isAvailable else {
    print("Apple Intelligence not available")
    return
}

// Create session
let session = LanguageModelSession()

// Simple prompt
let response = try await session.respond(to: "Summarize this document: \(text)")
print(response.content)

// With instructions
let session2 = LanguageModelSession(instructions: Instructions(
    """
    You are a helpful assistant that answers questions about documents.
    Be concise and accurate. If you don't know, say so.
    """
))
```

### 8.2 Guided Generation with @Generable

Generate structured Swift data types.

```swift
import FoundationModels

@Generable
struct DocumentSummary {
    let title: String
    let keyPoints: [String]
    let sentiment: String
    let confidence: Double
}

// Generate structured output
let session = LanguageModelSession()
let summary: DocumentSummary = try await session.respond(
    to: "Analyze this document and extract key information: \(documentText)",
    generating: DocumentSummary.self
)

print("Title: \(summary.title)")
print("Key Points: \(summary.keyPoints)")
print("Sentiment: \(summary.sentiment)")
```

### 8.3 Tool Calling

Enable the model to call your code.

```swift
import FoundationModels

@Tool
struct SearchDocuments {
    static let description = "Search the document database for relevant information"

    @Parameter(description: "The search query")
    var query: String

    @Parameter(description: "Maximum number of results")
    var limit: Int = 10

    func call() async throws -> String {
        // Your search implementation
        let results = await documentStore.search(query: query, limit: limit)
        return results.map { $0.title }.joined(separator: "\n")
    }
}

// Use tool in session
let session = LanguageModelSession(tools: [SearchDocuments.self])
let response = try await session.respond(to: "Find documents about machine learning")
```

### 8.4 Generation Options

```swift
let options = GenerationOptions(
    temperature: 0.7,
    maxTokens: 1000,
    topP: 0.95,
    topK: 40,
    repetitionPenalty: 1.1
)

let response = try await session.respond(
    to: prompt,
    options: options
)
```

### 8.5 Streaming Responses

```swift
let stream = session.streamResponse(to: "Write a detailed analysis...")

for try await partial in stream {
    print(partial.content, terminator: "")
}
```

### 8.6 Transcript Management

```swift
// Access conversation history
let transcript = session.transcript

for entry in transcript.entries {
    switch entry {
    case .prompt(let prompt):
        print("User: \(prompt.content)")
    case .response(let response):
        print("Assistant: \(response.content)")
    case .toolCall(let call):
        print("Tool: \(call.toolName)")
    case .toolResult(let result):
        print("Result: \(result.content)")
    }
}

// Continue conversation
let followUp = try await session.respond(to: "Tell me more about the second point")
```

### 8.7 Safety and Error Handling

```swift
do {
    let response = try await session.respond(to: prompt)
    print(response.content)
} catch LanguageModelError.contentFiltered {
    print("Content was filtered for safety")
} catch LanguageModelError.contextLengthExceeded {
    print("Input too long")
} catch LanguageModelError.modelUnavailable {
    print("Model not available")
} catch {
    print("Error: \(error)")
}
```

---

## 9. CoreML Tools (Python)

Python library for converting and optimizing models for CoreML.

### 9.1 Installation

```bash
pip install coremltools
```

### 9.2 PyTorch Conversion

```python
import coremltools as ct
import torch

# Load PyTorch model
pytorch_model = MyModel()
pytorch_model.load_state_dict(torch.load("model.pth"))
pytorch_model.eval()

# Trace model
example_input = torch.randn(1, 3, 224, 224)
traced_model = torch.jit.trace(pytorch_model, example_input)

# Convert to CoreML
mlmodel = ct.convert(
    traced_model,
    inputs=[ct.TensorType(shape=example_input.shape, name="input")],
    outputs=[ct.TensorType(name="output")],
    minimum_deployment_target=ct.target.iOS16,
    convert_to="mlprogram"  # or "neuralnetwork"
)

# Save
mlmodel.save("MyModel.mlpackage")
```

### 9.3 TensorFlow/Keras Conversion

```python
import coremltools as ct
import tensorflow as tf

# Load TensorFlow model
tf_model = tf.keras.models.load_model("model.h5")

# Convert
mlmodel = ct.convert(
    tf_model,
    inputs=[ct.ImageType(shape=(1, 224, 224, 3), name="image")],
    minimum_deployment_target=ct.target.iOS15
)

mlmodel.save("TFModel.mlpackage")
```

### 9.4 Model Optimization

```python
import coremltools.optimize.coreml as cto

# Quantization (reduce model size)
config = cto.OptimizationConfig(
    global_config=cto.OpLinearQuantizerConfig(mode="linear_symmetric", weight_threshold=1000)
)

quantized_model = cto.linear_quantize_weights(mlmodel, config=config)

# Palettization (weight clustering)
config = cto.OptimizationConfig(
    global_config=cto.OpPalettizerConfig(nbits=4, mode="kmeans")
)

palettized_model = cto.palettize_weights(mlmodel, config=config)

# Pruning (remove small weights)
config = cto.OptimizationConfig(
    global_config=cto.OpMagnitudePrunerConfig(target_sparsity=0.5)
)

pruned_model = cto.prune_weights(mlmodel, config=config)
```

### 9.5 Embedding Model Conversion

```python
import coremltools as ct
from transformers import AutoTokenizer, AutoModel
import torch

# Load sentence transformer
tokenizer = AutoTokenizer.from_pretrained("sentence-transformers/all-MiniLM-L6-v2")
model = AutoModel.from_pretrained("sentence-transformers/all-MiniLM-L6-v2")
model.eval()

# Create wrapper for tracing
class EmbeddingModel(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, input_ids, attention_mask):
        outputs = self.model(input_ids=input_ids, attention_mask=attention_mask)
        # Mean pooling
        embeddings = outputs.last_hidden_state.mean(dim=1)
        return embeddings

wrapper = EmbeddingModel(model)

# Trace
example_input_ids = torch.randint(0, 30522, (1, 128))
example_attention = torch.ones(1, 128, dtype=torch.int64)

traced = torch.jit.trace(wrapper, (example_input_ids, example_attention))

# Convert
mlmodel = ct.convert(
    traced,
    inputs=[
        ct.TensorType(shape=(1, 128), dtype=np.int32, name="input_ids"),
        ct.TensorType(shape=(1, 128), dtype=np.int32, name="attention_mask")
    ],
    outputs=[ct.TensorType(name="embeddings")],
    minimum_deployment_target=ct.target.iOS16,
    convert_to="mlprogram"
)

mlmodel.save("MiniLM-L6-v2.mlpackage")
```

### 9.6 Model Metadata

```python
mlmodel.author = "Your Name"
mlmodel.short_description = "Sentence embeddings for semantic search"
mlmodel.version = "1.0.0"
mlmodel.license = "MIT"

# Input/output descriptions
spec = mlmodel.get_spec()
spec.description.input[0].shortDescription = "Tokenized input text"
spec.description.output[0].shortDescription = "384-dimensional embedding vector"

mlmodel.save("Model.mlpackage")
```

---

## 10. Framework Comparison Matrix

### OCR Capabilities

| Feature             | Vision VNRecognizeTextRequest | VisionKit DataScanner | RecognizeDocumentsRequest (iOS 26) |
| ------------------- | ----------------------------- | --------------------- | ---------------------------------- |
| **Min iOS**         | 13.0                          | 16.0                  | 26.0                               |
| **Live Camera**     | ❌                            | ✅                    | ✅                                 |
| **Offline**         | ✅                            | ✅                    | ✅                                 |
| **Table Detection** | ❌                            | ❌                    | ✅                                 |
| **List Detection**  | ❌                            | ❌                    | ✅                                 |
| **Barcode**         | Separate request              | ✅                    | ✅                                 |
| **Languages**       | 18                            | Configurable          | 18+                                |
| **Accuracy**        | High                          | Real-time optimized   | Highest                            |
| **Data Detection**  | ❌                            | ✅                    | ✅                                 |

### NLP Capabilities

| Feature             | Natural Language | Foundation Models  |
| ------------------- | ---------------- | ------------------ |
| **Min iOS**         | 12.0             | 26.0               |
| **NER**             | ✅               | ✅ (via prompting) |
| **POS Tagging**     | ✅               | ✅ (via prompting) |
| **Embeddings**      | Word/Sentence    | N/A (use own)      |
| **Text Generation** | ❌               | ✅                 |
| **Summarization**   | ❌               | ✅                 |
| **Custom Models**   | ✅ (Create ML)   | ❌                 |
| **Offline**         | ✅               | ✅                 |

### Speech Recognition

| Feature               | SFSpeechRecognizer | SpeechAnalyzer (iOS 26) |
| --------------------- | ------------------ | ----------------------- |
| **Min iOS**           | 10.0               | 26.0                    |
| **On-Device**         | ✅ (iOS 13+)       | ✅                      |
| **Live Audio**        | ✅                 | ✅                      |
| **Custom Vocabulary** | ✅                 | ✅                      |
| **Streaming**         | ✅                 | ✅                      |
| **VAD**               | ❌                 | ✅                      |
| **Languages**         | 60+                | TBD                     |

### ML Model Execution

| Feature                | Core ML         | Foundation Models |
| ---------------------- | --------------- | ----------------- |
| **Min iOS**            | 11.0            | 26.0              |
| **Custom Models**      | ✅              | ❌                |
| **Neural Engine**      | ✅              | ✅                |
| **GPU**                | ✅              | ✅                |
| **On-Device Training** | ✅              | ❌                |
| **Model Types**        | All             | LLM only          |
| **Context Length**     | Model-dependent | ~4096 tokens      |

---

## Quick Reference: Best Practices

### OCR Best Practices

1. **Scale images to 300-360 DPI** for optimal accuracy
2. **Use `.accurate` recognition level** for documents (not `.fast`)
3. **Set `recognitionLanguages`** in priority order
4. **Add `customWords`** for domain-specific terminology
5. **For iOS 26+, prefer `RecognizeDocumentsRequest`** for structured documents

### NLP Best Practices

1. **Use `NLTagger` with `.joinNames`** for better entity recognition
2. **Combine `NLEmbedding` with custom gazetteers** for domain vocabulary
3. **Pre-load models** for responsive UI
4. **Use `NLContextualEmbedding`** (iOS 17+) for context-aware similarity

### Speech Best Practices

1. **Check `supportsOnDeviceRecognition`** before requiring offline
2. **Use `contextualStrings`** for expected vocabulary
3. **Set `requiresOnDeviceRecognition = true`** for privacy-sensitive apps
4. **Limit recordings to 1 minute** per recognition session

### Core ML Best Practices

1. **Use `.all` compute units** unless specific hardware targeting needed
2. **Compile models at build time**, not runtime
3. **Use batch predictions** for multiple inputs
4. **Quantize models** to reduce size and improve speed
5. **Profile with Instruments** to identify bottlenecks

---

## Document Revision History

| Date | Changes                                                                         |
| ---- | ------------------------------------------------------------------------------- |
| 2025 | Initial comprehensive reference                                                 |
| —    | Added iOS 26 APIs: RecognizeDocumentsRequest, Foundation Models, SpeechAnalyzer |
| —    | Added CoreML Tools Python conversion guide                                      |
| —    | Added framework comparison matrices                                             |
