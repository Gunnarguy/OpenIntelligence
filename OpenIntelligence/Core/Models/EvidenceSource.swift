//
//  EvidenceSource.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import Foundation
import CoreGraphics

/// Represents a source of evidence used to ground a query's response.
/// Evidences can come from standard documents (chunks) or camera/vision capture (OCR, barcodes).
enum EvidenceSource: Codable, Sendable {
    case documentChunk(UUID)
    case imageOCR(String, VisualEvidenceMetadata)
    case imageRegion(CGRect, String)
    case barcode(String)
}
