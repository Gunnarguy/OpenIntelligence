//
//  SearchInAppIntent.swift
//  OpenIntelligence
//

import AppIntents
import Foundation

/// "Search OpenIntelligence for the pet deposit": Siri's search-in-app action (5.7). It opens the
/// library's search with the text and runs it.
///
/// Apple's system search schema for iOS and macOS 27 (`.system.searchInApp`); the older
/// `.system.search` is deprecated in 27, so there is no form of this before 27. It must run in the
/// app, not an extension, which this project does not have.
@available(iOS 27.0, macOS 27.0, *)
@AppIntent(schema: .system.searchInApp)
struct SearchInAppIntent: ShowInAppSearchResultsIntent {
    static var searchScopes: [StringSearchScope] = [.general]

    var criteria: StringSearchCriteria

    func perform() async throws -> some IntentResult {
        let term = criteria.term.trimmingCharacters(in: .whitespacesAndNewlines)
        await MainActor.run {
            AppNavigationRequest.post(term.isEmpty ? .search : .searchFor(term))
        }
        return .result()
    }
}
