//
//  OIDocumentEntity.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import AppIntents
import Foundation

@available(iOS 16.0, macOS 13.0, *)
struct OIDocumentEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Document")
    
    var id: UUID
    var filename: String
    var totalChunks: Int
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(filename)",
            subtitle: "\(totalChunks) chunks"
        )
    }
    
    static var defaultQuery = OIDocumentEntityQuery()
}
