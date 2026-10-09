//
//  AppNavigationRequest.swift
//  OpenIntelligence
//

import Combine
import Foundation

/// A place in the app that something outside a screen can ask for: an action, a link, a Spotlight
/// result, a notification.
nonisolated enum AppDestination: Equatable, Sendable {
    case chat
    case documents
    case importQueue
    /// The Documents tab with the file picker up.
    case addDocument
    /// The chat with the camera capture up (iPhone and iPad).
    case scanDocument
    /// The chat on a new conversation, in a library when one is named.
    case newConversation(libraryId: UUID?)
    case library(UUID)
    case document(UUID)
    /// The Documents tab, importing files another app handed over ("Open in OpenIntelligence").
    /// The files are already copied into the app. This one has no link form.
    case importFiles([URL])
}

/// Links into the app. One form for every surface, so a link made in one place opens the same
/// thing from any other.
///
/// Through 5.6 the app understood three addresses (`openintelligence://documents`, its
/// `/ingestion` path and `openintelligence://chat`), and a Spotlight result opened the Documents
/// tab of whatever library was active, not the item that was tapped.
nonisolated enum AppLink {
    static let scheme = "openintelligence"

    static func url(for destination: AppDestination) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        switch destination {
        case .chat:
            components.host = "chat"
        case .documents:
            components.host = "documents"
        case .importQueue:
            components.host = "documents"
            components.path = "/ingestion"
        case .addDocument:
            components.host = "documents"
            components.path = "/add"
        case .scanDocument:
            components.host = "chat"
            components.path = "/scan"
        case .newConversation(let libraryId):
            components.host = "chat"
            components.path = "/new"
            if let libraryId {
                components.queryItems = [URLQueryItem(name: "library", value: libraryId.uuidString)]
            }
        case .library(let id):
            components.host = "library"
            components.path = "/\(id.uuidString)"
        case .document(let id):
            components.host = "document"
            components.path = "/\(id.uuidString)"
        case .importFiles:
            // Files are handed over by the system, not by a link; the nearest place is Documents.
            components.host = "documents"
        }
        // Every case sets a host, so the address always forms.
        return components.url ?? URL(string: "\(scheme)://chat")!
    }

    /// The destination an address names, or nil when it is not one of this app's links.
    static func destination(for url: URL) -> AppDestination? {
        guard url.scheme?.lowercased() == scheme, let host = url.host?.lowercased() else { return nil }
        let path = url.path.split(separator: "/").map(String.init)
        switch host {
        case "chat":
            switch path.first {
            case nil: return .chat
            case "scan": return .scanDocument
            case "new":
                let library = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "library" }?.value.flatMap(UUID.init(uuidString:))
                return .newConversation(libraryId: library)
            default: return .chat
            }
        case "documents":
            switch path.first {
            case "ingestion": return .importQueue
            case "add": return .addDocument
            default: return .documents
            }
        case "library":
            return path.first.flatMap(UUID.init(uuidString:)).map(AppDestination.library)
        case "document":
            return path.first.flatMap(UUID.init(uuidString:)).map(AppDestination.document)
        default:
            return nil
        }
    }

    /// The destination for a Spotlight result. `SpotlightIndexService` names a library
    /// `container-<id>` and a document `document-<id>`; a passage (`chunk-<id>`) has no screen of
    /// its own and returns nil.
    static func destination(forSpotlightIdentifier identifier: String) -> AppDestination? {
        let parts = identifier.split(separator: "-", maxSplits: 1)
        guard parts.count == 2, let id = UUID(uuidString: String(parts[1])) else { return nil }
        switch parts[0] {
        case "container": return .library(id)
        case "document": return .document(id)
        default: return nil
        }
    }
}

/// Carries destinations from whoever asked for them to the screens that can show them.
///
/// An action can run before any screen exists, and several files can arrive at once, so requests
/// wait in a queue. The main view reads the first one when it appears and switches tab or library;
/// the screen that owns the last step (the file picker, the camera, a new conversation, an import)
/// takes its request out of the queue. `changes` delivers the queue as it is after each change, so
/// a screen never acts on a value that is about to be replaced.
@MainActor
final class AppNavigationRequest {
    static let shared = AppNavigationRequest()

    private let subject = CurrentValueSubject<[AppDestination], Never>([])

    /// The waiting requests, oldest first: sent at once to a new subscriber and again after every change.
    var changes: AnyPublisher<[AppDestination], Never> { subject.eraseToAnyPublisher() }

    var waiting: [AppDestination] { subject.value }

    static func post(_ destination: AppDestination) {
        shared.subject.value.append(destination)
    }

    /// Hands over the oldest waiting request the caller shows, and removes it.
    func take(where shows: (AppDestination) -> Bool) -> AppDestination? {
        guard let index = subject.value.firstIndex(where: shows) else { return nil }
        var queue = subject.value
        let destination = queue.remove(at: index)
        subject.value = queue
        return destination
    }

    /// Hands over every waiting request the caller shows, oldest first, and removes them.
    func takeAll(where shows: (AppDestination) -> Bool) -> [AppDestination] {
        let taken = subject.value.filter(shows)
        guard !taken.isEmpty else { return [] }
        subject.value = subject.value.filter { !shows($0) }
        return taken
    }
}
