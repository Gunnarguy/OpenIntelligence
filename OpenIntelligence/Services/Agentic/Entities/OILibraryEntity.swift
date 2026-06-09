//
//  OILibraryEntity.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import AppIntents
import Foundation

@available(iOS 16.0, macOS 13.0, *)
struct OILibraryEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Library")
    
    var id: UUID
    var name: String
    var totalDocuments: Int
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(totalDocuments) documents"
        )
    }
    
    static var defaultQuery = OILibraryEntityQuery()
}
