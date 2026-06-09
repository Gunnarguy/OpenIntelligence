//
//  ViewAnnotations.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import AppIntents
import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
extension View {
    /// Annotates the view with a document entity so Siri/Apple Intelligence can reference it.
    func annotateActiveDocument(_ document: OIDocumentEntity?) -> some View {
        self.modifier(ActiveDocumentAnnotationModifier(document: document))
    }
    
    /// Annotates the view with a library/container entity so Siri/Apple Intelligence can reference it.
    func annotateActiveLibrary(_ library: OILibraryEntity?) -> some View {
        self.modifier(ActiveLibraryAnnotationModifier(library: library))
    }
}

@available(iOS 16.0, macOS 13.0, *)
private struct ActiveDocumentAnnotationModifier: ViewModifier {
    let document: OIDocumentEntity?
    
    func body(content: Content) -> some View {
        if let document = document {
            content
                .userActivity("com.openintelligence.activity.viewing-document", element: document) { docEntity, activity in
                    activity.title = "Viewing \(docEntity.filename)"
                    activity.isEligibleForSearch = true
                    #if os(iOS)
                    activity.isEligibleForPrediction = true
                    #endif
                    #if compiler(>=6.0) || canImport(FoundationModels)
                    if #available(iOS 18.0, macOS 15.0, *) {
                        activity.appEntityIdentifier = EntityIdentifier(for: docEntity)
                    }
                    #endif
                }
        } else {
            content
        }
    }
}

@available(iOS 16.0, macOS 13.0, *)
private struct ActiveLibraryAnnotationModifier: ViewModifier {
    let library: OILibraryEntity?
    
    func body(content: Content) -> some View {
        if let library = library {
            content
                .userActivity("com.openintelligence.activity.viewing-library", element: library) { libEntity, activity in
                    activity.title = "Viewing \(libEntity.name) Library"
                    activity.isEligibleForSearch = true
                    #if os(iOS)
                    activity.isEligibleForPrediction = true
                    #endif
                    #if compiler(>=6.0) || canImport(FoundationModels)
                    if #available(iOS 18.0, macOS 15.0, *) {
                        activity.appEntityIdentifier = EntityIdentifier(for: libEntity)
                    }
                    #endif
                }
        } else {
            content
        }
    }
}
