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
    case settings
    case importQueue
    /// The Documents tab with the file picker up.
    case addDocument
    /// The Documents tab with the library's search up.
    case search
    /// The chat with the camera capture up (iPhone and iPad).
    case scanDocument
    /// The chat on a new conversation, in a library when one is named.
    case newConversation(libraryId: UUID?)
    case library(UUID)
    case document(UUID)
    /// The Documents tab, importing files: the Mac's Services menu ("Add to OpenIntelligence") and
    /// the document scanner. The files are already copied into the app. This one has no link form.
    case importFiles([URL])
    /// The Documents tab, showing files another app handed over ("Open in OpenIntelligence") before
    /// anything is added (`OpenedFilesSheet`, 5.7). Already copied into the app; no link form.
    case openedFiles([URL])
    /// The chat with this text in the composer: not sent, so it can be read and changed first (the
    /// Mac's Services menu), or sent at once when the person typed it to ask (the Mac's menu bar).
    /// With `inDeepThink` the chat is switched to Deep Think first, as its own "Switch to Deep
    /// Think" does, and with `libraryId` that library is made the active one (the Think Deeper
    /// button on Siri's answer card). 5.7. No link form, so no address carries the text.
    case ask(String, sendsAtOnce: Bool = false, inDeepThink: Bool = false, libraryId: UUID? = nil)
    /// The library's search, run for this text: "Search OpenIntelligence for ..." from Siri (5.7).
    /// No link form either.
    case searchFor(String)
    /// The chat, in a new conversation that starts with this question and the answer Siri showed
    /// for it, so the next question is asked as a follow-up: Ask a Follow-up on Siri's answer card
    /// (5.7). With `libraryId` that library is made the active one first. No link form.
    case continueAnswer(question: String, answer: String, libraryId: UUID? = nil)
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
        case .settings:
            components.host = "settings"
        case .importQueue:
            components.host = "documents"
            components.path = "/ingestion"
        case .addDocument:
            components.host = "documents"
            components.path = "/add"
        case .search:
            components.host = "documents"
            components.path = "/search"
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
        case .importFiles, .openedFiles:
            // Files are handed over by the system, not by a link; the nearest place is Documents.
            components.host = "documents"
        case .ask, .continueAnswer:
            components.host = "chat"
        case .searchFor:
            components.host = "documents"
            components.path = "/search"
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
            case "search": return .search
            default: return .documents
            }
        case "settings":
            return .settings
        case "library":
            return path.first.flatMap(UUID.init(uuidString:)).map(AppDestination.library)
        case "document":
            return path.first.flatMap(UUID.init(uuidString:)).map(AppDestination.document)
        default:
            return nil
        }
    }

    /// The destination for a Spotlight result. `SpotlightIndexService` names a library
    /// `container-<id>`, a document `document-<id>`, and from 5.7 a passage
    /// `passage-<document id>-<passage id>`, which opens its document. A passage indexed before 5.7
    /// (`chunk-<id>`) does not name its document and returns nil.
    static func destination(forSpotlightIdentifier identifier: String) -> AppDestination? {
        if identifier.hasPrefix("passage-") {
            let rest = identifier.dropFirst("passage-".count)
            return UUID(uuidString: String(rest.prefix(36))).map(AppDestination.document)
        }
        let parts = identifier.split(separator: "-", maxSplits: 1)
        guard parts.count == 2, let id = UUID(uuidString: String(parts[1])) else { return nil }
        switch parts[0] {
        case "container": return .library(id)
        case "document": return .document(id)
        default: return nil
        }
    }
}

/// The activities the app advertises, for Handoff, Spotlight and Siri, and where each one lands
/// when another device continues it (5.7).
///
/// Through 5.6 the chat and the Documents screen advertised an activity that no device could
/// continue: the types were not declared in Info.plist (`NSUserActivityTypes`) and nothing in the
/// app received them. 5.6 put the library in `userInfo` as a `UUID`, which `NSUserActivity` allows
/// (its header lists `NSUUID`); 5.7 writes strings and reads either, so an activity from a device
/// still on 5.6 lands in its library too.
nonisolated enum AppActivity {
    static let chat = "com.openintelligence.chat"
    static let documents = "com.openintelligence.documents"
    static let viewingDocument = "com.openintelligence.activity.viewing-document"

    /// Every type, as Info.plist's `NSUserActivityTypes` lists them.
    static let all = [chat, documents, viewingDocument]

    static let libraryKey = "containerId"
    static let documentKey = "documentId"

    /// Whether what the person opens may be offered to Spotlight and Siri's suggestions: the
    /// Settings switch "Spotlight Indexing" (System-wide search integration), on unless turned off.
    /// The document activity's title names the file, so it follows the switch as the Spotlight
    /// entries do (5.7).
    static var mayShareWithSystemSearch: Bool {
        UserDefaults.standard.object(forKey: "enableSpotlightIndexing") as? Bool ?? true
    }

    /// What an activity carries: identifiers as strings.
    static func userInfo(library: UUID?, document: UUID? = nil) -> [AnyHashable: Any] {
        var info: [AnyHashable: Any] = [:]
        if let library { info[libraryKey] = library.uuidString }
        if let document { info[documentKey] = document.uuidString }
        return info
    }

    /// Where a continued activity lands, in order: the library first when the activity names one,
    /// then the screen. Empty for a type that is not this app's.
    static func destinations(type: String, userInfo: [AnyHashable: Any]?) -> [AppDestination] {
        func identifier(_ key: String) -> UUID? {
            switch userInfo?[key] {
            case let text as String: return UUID(uuidString: text)
            case let uuid as UUID: return uuid  // as 5.6 sent it
            default: return nil
            }
        }
        switch type {
        case chat:
            return (identifier(libraryKey).map { [AppDestination.library($0)] } ?? []) + [.chat]
        case documents:
            return [identifier(libraryKey).map(AppDestination.library) ?? .documents]
        case viewingDocument:
            return [identifier(documentKey).map(AppDestination.document) ?? .documents]
        default:
            return []
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

    /// Called as a request is posted, before any screen can take it. The main view sets it to show
    /// the tab and the library the request is for (5.7): a screen subscribed to `changes` can take a
    /// request before the main view has seen it, because a subject does not order its subscribers,
    /// and a request taken that way never switched the tab.
    var onPost: ((AppDestination) -> Void)?

    static func post(_ destination: AppDestination) {
        shared.onPost?(destination)
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
