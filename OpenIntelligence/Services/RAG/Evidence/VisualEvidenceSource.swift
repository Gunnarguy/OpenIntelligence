//
//  VisualEvidenceSource.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import Foundation
import CoreGraphics

/// Metadata for a visual evidence source captured from camera/photos
struct VisualEvidenceMetadata: Codable, Sendable {
    let timestamp: Date
    let ocrWordCount: Int
    let barcodeCount: Int
    let detectedObjects: [String]
    let boundingBoxes: [CGRect]?
}

/// A wrapper for visual evidence gathered during Vision OCR or layout analysis
struct VisualEvidenceSource: Codable, Sendable {
    let ocrText: String
    let barcodeResults: [String]?
    let boundingBoxes: [CGRect]?
    let sourceImageData: Data?
    let metadata: VisualEvidenceMetadata
    
    init(
        ocrText: String,
        barcodeResults: [String]? = nil,
        boundingBoxes: [CGRect]? = nil,
        sourceImageData: Data? = nil,
        metadata: VisualEvidenceMetadata
    ) {
        self.ocrText = ocrText
        self.barcodeResults = barcodeResults
        self.boundingBoxes = boundingBoxes
        self.sourceImageData = sourceImageData
        self.metadata = metadata
    }
}
