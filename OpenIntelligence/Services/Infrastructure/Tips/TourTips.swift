//
//  TourTips.swift
//  OpenIntelligence
//
//  The tour (5.8): each screen teaches itself the first time it is opened, one arrow at a time, on the control the
//  arrow names. The plan, with every control's file and line, is `Docs/Engineering/ONBOARDING_TOUR_PLAN.md`.
//

import SwiftUI
import TipKit

/// One stop on the tour. Its text is a claim about the control it points at: each was written from that control's
/// own code, and a change to the control's behaviour changes the tip in the same commit.
enum TourStep: String, CaseIterable, Sendable {
    // Chat
    case composer, modePicker, libraryPills, answerBubble, citation, goDeeper, details, routeBadge
    case dictation, attach, sidebar, aiHub, moreMenu, keyboard
    // A cited passage
    case matchBanner, moreContext
    // Documents and the import queue
    case addDocument, paste, newLibrary, librarySettings, semanticSearch, documentMenu, dragAndDrop
    case pauseImport, processingMode
    // Library Settings
    case watchFolder, searchStyle, translation
    // Atlas
    case atlasSettings, insights, allLibraries
    // Database
    case databaseScope, databaseSections, runCheck
    // Settings and Plans
    case howItWorks, privateCloud, glossary, technicalDetails, siri, menuBar
    case redeemCode

    var id: String { "tour.\(rawValue)" }

    var title: String {
        switch self {
        case .composer: "Ask about your documents"
        case .modePicker: "Choose how hard it works"
        case .libraryPills: "Switch libraries here"
        case .answerBubble: "Tap an answer for more"
        case .citation: "Check where it came from"
        case .goDeeper: "Not enough? Go Deeper"
        case .details: "See how it was answered"
        case .routeBadge: "Where it ran"
        case .dictation: "Or just say it"
        case .attach: "Add a file from here"
        case .sidebar: "Your conversations"
        case .aiHub: "Rework an answer"
        case .moreMenu: "New chat and export"
        case .keyboard: "Faster with the keyboard"
        case .matchBanner: "Is it really there?"
        case .moreContext: "Need more context?"
        case .addDocument: "Add your files"
        case .paste: "Paste works too"
        case .newLibrary: "Keep topics apart"
        case .librarySettings: "Tune this library"
        case .semanticSearch: "Search by meaning"
        case .documentMenu: "More on a document"
        case .dragAndDrop: "Drop files here"
        case .pauseImport: "Pause anytime"
        case .processingMode: "Faster or cooler"
        case .watchFolder: "Keep up with a folder"
        case .searchStyle: "How this library searches"
        case .translation: "Documents in another language?"
        case .atlasSettings: "Change the view"
        case .insights: "What the map found"
        case .allLibraries: "All libraries at once"
        case .databaseScope: "One library or all"
        case .databaseSections: "Look inside the index"
        case .runCheck: "Something off?"
        case .howItWorks: "How it really works"
        case .privateCloud: "You decide when it's used"
        case .glossary: "Every term explained"
        case .technicalDetails: "Want to see the work?"
        case .siri: "Ask without opening the app"
        case .menuBar: "Ask from the menu bar"
        case .redeemCode: "Have a code?"
        }
    }

    var message: String {
        switch self {
        case .composer: "Answers come from your own files, with links to where each point came from."
        case .modePicker: "Standard is fastest. Deep Think runs several searches. Maximum goes deepest."
        case .libraryPills: "A question only searches the library that's selected."
        case .answerBubble: "Copy, share, retry, translate, or see exactly how it was answered."
        case .citation:
            "Tap a source to open the passage in your document, highlighted, with whether it was found word for word."
        case .goDeeper: "Asks again with several searches and checks."
        case .details: "Which passages were used, how each claim held up, and where it ran."
        case .routeBadge: "On-device means nothing left your device. Private Cloud Compute runs only if you allow it."
        case .dictation: "Dictate your question."
        case .attach: "A file you attach joins this library and this conversation."
        case .sidebar: "Every conversation is kept, with its sources."
        case .aiHub: "Key facts, step by step, plain English, or what's missing."
        case .moreMenu: "Start fresh, export a conversation, or turn on Technical Details."
        case .keyboard: "⌘1 Chat, ⌘2 Documents, ⌘F search, ⌘[ and ⌘] switch libraries."
        case .matchBanner: "This line says whether the passage was found word for word, in part, or not at all."
        case .moreContext: "Show the text around the passage."
        case .addDocument: "PDFs, Word, spreadsheets, slides, images, recordings and more."
        case .paste: "A copied file, link or text becomes a document."
        case .newLibrary: "Each library has its own documents and settings."
        case .librarySettings: "Search style, chunking, translation, and a watched folder."
        case .semanticSearch: "Find passages by meaning, without asking a question."
        case .documentMenu: "Touch and hold a document to copy its link or delete it."
        case .dragAndDrop: "Drag files or a whole folder in."
        case .pauseImport: "It picks up right where it stopped."
        case .processingMode: "Choose how hard the device works while importing."
        case .watchFolder: "New files in a folder import by themselves. Pro and Lifetime."
        case .searchStyle: "Automatic suits most. Technical Manual favors exact words and part numbers."
        case .translation: "Passages are translated into the language you pick before they're searched."
        case .atlasSettings: "Projection, point size, labels and background."
        case .insights: "Tap one to see that part of your library."
        case .allLibraries: "Compare what each library covers."
        case .databaseScope: "Pick which library these numbers describe."
        case .databaseSections: "Documents, vocabulary, maintenance and search."
        case .runCheck: "Run Check looks for problems in this library's index."
        case .howItWorks: "What runs where, in plain words, and Show Me Around to see these tips again."
        case .privateCloud: "Choose whether Apple's Private Cloud Compute is never used, or when it may be."
        case .glossary: "What each word in the app means."
        case .technicalDetails: "Show the metrics bar and passage counts under answers."
        case .siri: "Siri and Shortcuts can ask, search and add."
        case .menuBar: "A question box that's always one click away."
        case .redeemCode: "Redeem it here."
        }
    }

    var symbol: String {
        switch self {
        case .composer: "bubble.left.and.text.bubble.right"
        case .modePicker: "dial.medium"
        case .libraryPills: "books.vertical"
        case .answerBubble: "hand.tap"
        case .citation: "quote.bubble"
        case .goDeeper: "brain"
        case .details: "info.circle"
        case .routeBadge: "lock.shield"
        case .dictation: "mic"
        case .attach: "paperclip"
        case .sidebar: "sidebar.left"
        case .aiHub: "apple.intelligence"
        case .moreMenu: "ellipsis.circle"
        case .keyboard: "keyboard"
        case .matchBanner: "checkmark.seal"
        case .moreContext: "text.alignleft"
        case .addDocument: "doc.badge.plus"
        case .paste: "doc.on.clipboard"
        case .newLibrary: "folder.badge.plus"
        case .librarySettings: "slider.horizontal.3"
        case .semanticSearch: "sparkle.magnifyingglass"
        case .documentMenu: "hand.point.up.left"
        case .dragAndDrop: "square.and.arrow.down"
        case .pauseImport: "pause.circle"
        case .processingMode: "thermometer.medium"
        case .watchFolder: "folder.badge.gearshape"
        case .searchStyle: "scope"
        case .translation: "translate"
        case .atlasSettings: "slider.horizontal.3"
        case .insights: "lightbulb"
        case .allLibraries: "square.stack.3d.up"
        case .databaseScope: "line.3.horizontal.decrease.circle"
        case .databaseSections: "cylinder.split.1x2"
        case .runCheck: "stethoscope"
        case .howItWorks: "questionmark.circle"
        case .privateCloud: "cloud"
        case .glossary: "character.book.closed"
        case .technicalDetails: "waveform.path.ecg"
        case .siri: "mic.circle"
        case .menuBar: "menubar.rectangle"
        case .redeemCode: "giftcard"
        }
    }
}

/// What the tour knows about the person's progress, for its rules. Set by the app as things happen.
enum TourContext {
    /// The welcome is closed. No tip shows over it.
    @Parameter static var welcomeClosed: Bool = false
    /// Answers finished since install.
    @Parameter static var answers: Int = 0
    @Parameter static var documents: Int = 0
    @Parameter static var libraries: Int = 0
    @Parameter static var isMac: Bool = false
    /// A Mac or an iPad: where dragging files in is the natural way.
    @Parameter static var isLargeScreen: Bool = false
    @Parameter static var privateCloudAvailable: Bool = false

    static let chatOpened = Tips.Event(id: "tour.chatOpened")
    static let settingsOpened = Tips.Event(id: "tour.settingsOpened")
    static let appLaunched = Tips.Event(id: "tour.appLaunched")
}

/// A tour stop as TipKit sees it. Hidden for good once its control is used (`Tour.used`) or its close button is tapped.
struct TourTip: Tip {
    let step: TourStep

    init(_ step: TourStep) { self.step = step }

    var id: String { step.id }
    var title: Text { Text(step.title) }
    var message: Text? { Text(step.message) }
    var image: Image? { Image(systemName: step.symbol) }

    var rules: [Rule] {
        var rules: [Rule] = [#Rule(TourContext.$welcomeClosed) { $0 == true }]
        switch step {
        case .composer:
            rules.append(#Rule(TourContext.$answers) { $0 == 0 })
        case .modePicker, .answerBubble, .citation, .goDeeper, .details, .routeBadge, .aiHub:
            rules.append(#Rule(TourContext.$answers) { $0 >= 1 })
        case .sidebar:
            rules.append(#Rule(TourContext.$answers) { $0 >= 3 })
        case .libraryPills:
            rules.append(#Rule(TourContext.$libraries) { $0 >= 2 })
        case .dictation, .attach:
            rules.append(#Rule(TourContext.chatOpened) { $0.donations.count >= 2 })
        case .moreMenu:
            rules.append(#Rule(TourContext.chatOpened) { $0.donations.count >= 3 })
        case .keyboard:
            rules.append(#Rule(TourContext.$isMac) { $0 == true })
            rules.append(#Rule(TourContext.appLaunched) { $0.donations.count >= 3 })
        case .paste, .librarySettings:
            rules.append(#Rule(TourContext.$documents) { $0 >= 1 })
        case .newLibrary, .semanticSearch, .documentMenu:
            rules.append(#Rule(TourContext.$documents) { $0 >= 3 })
        case .dragAndDrop:
            rules.append(#Rule(TourContext.$isLargeScreen) { $0 == true })
        case .privateCloud:
            rules.append(#Rule(TourContext.$privateCloudAvailable) { $0 == true })
        case .glossary, .siri:
            rules.append(#Rule(TourContext.settingsOpened) { $0.donations.count >= 2 })
        case .menuBar:
            rules.append(#Rule(TourContext.$isMac) { $0 == true })
        case .matchBanner, .moreContext, .addDocument, .pauseImport, .processingMode, .watchFolder, .searchStyle,
            .translation, .atlasSettings, .insights, .allLibraries, .databaseScope, .databaseSections, .runCheck,
            .howItWorks, .technicalDetails, .redeemCode:
            break
        }
        return rules
    }
}

/// The tour's groups, one per screen, and what the app tells it (5.8).
///
/// A group is `.firstAvailable`: of its tips not yet used or closed, the first whose rules pass is the one shown, in
/// the order listed. `.ordered` would wait on a tip whose rules can't pass yet (an answer tip before any answer, a Mac
/// tip on a phone) and show nothing after it.
@MainActor
enum Tour {
    /// Each screen's stops, in the order they show. Every `TourStep` is in exactly one (`TourTipTests`).
    nonisolated static let screens: [(name: String, steps: [TourStep])] = [
        ("chat", [
            .composer, .answerBubble, .citation, .goDeeper, .details, .routeBadge, .modePicker, .libraryPills, .aiHub,
            .dictation, .attach, .sidebar, .moreMenu, .keyboard,
        ]),
        ("source", [.matchBanner, .moreContext]),
        ("documents", [.addDocument, .paste, .librarySettings, .newLibrary, .semanticSearch, .documentMenu, .dragAndDrop]),
        ("importQueue", [.pauseImport, .processingMode]),
        ("librarySettings", [.watchFolder, .searchStyle, .translation]),
        ("atlas", [.atlasSettings, .insights, .allLibraries]),
        ("database", [.databaseScope, .databaseSections, .runCheck]),
        ("settings", [.howItWorks, .privateCloud, .glossary, .siri, .technicalDetails, .menuBar]),
        ("plans", [.redeemCode]),
    ]

    static let chat = group("chat")
    static let source = group("source")
    static let documents = group("documents")
    static let importQueue = group("importQueue")
    static let librarySettings = group("librarySettings")
    static let atlas = group("atlas")
    static let database = group("database")
    static let settings = group("settings")
    static let plans = group("plans")

    private static func group(_ name: String) -> TipGroup {
        let steps = screens.first { $0.name == name }?.steps ?? []
        return TipGroup(.firstAvailable) { steps.map { TourTip($0) as any Tip } }
    }

    /// The control was used: its tip goes for good, and the next in its group can show.
    static func used(_ step: TourStep) {
        TourTip(step).invalidate(reason: .actionPerformed)
    }

    /// Settings › How This Works › Show Me Around: every tip can show again, with no relaunch.
    static func showAgain() async {
        for step in TourStep.allCases { await TourTip(step).resetEligibility() }
        await AtlasTip().resetEligibility()
        await ModelConfigTip().resetEligibility()
        VerificationJournal.record("tour.showAgain")
    }

    /// Writes each tip's changes to the development build's event log: available, then used or closed (5.8), so a
    /// pull from a device shows where people stop.
    static func recordStatusChanges() {
        guard VerificationJournal.isEnabled else { return }
        for step in TourStep.allCases {
            Task.detached(priority: .utility) {
                for await status in TourTip(step).statusUpdates {
                    let name: String
                    switch status {
                    case .pending: name = "pending"
                    case .available: name = "available"
                    case .invalidated(let reason):
                        switch reason {
                        case .actionPerformed: name = "used"
                        case .tipClosed: name = "closed"
                        case .displayCountExceeded: name = "shownEnough"
                        case .displayDurationExceeded: name = "shownLongEnough"
                        @unknown default: name = "invalidated"
                        }
                    @unknown default: name = "unknown"
                    }
                    VerificationJournal.record("tip.status", ["tip": step.rawValue, "status": name])
                }
            }
        }
    }
}

extension EnvironmentValues {
    /// Inside the newest answer's bubble: the views there carry its tour tips (5.8).
    @Entry var tourIsLatestAnswer = false
}

extension View {
    /// Points `step`'s tip at this view when it is the one its group shows now. The screen stays usable under it.
    /// `when` false leaves the view without the tip: one of many alike (every answer bubble) carries it only on one.
    func tour(_ step: TourStep, in group: TipGroup, arrow: Edge? = nil, when active: Bool = true) -> some View {
        modifier(TourTipModifier(step: step, group: group, arrow: arrow, active: active))
    }
}

private struct TourTipModifier: ViewModifier {
    let step: TourStep
    let group: TipGroup
    let arrow: Edge?
    let active: Bool

    func body(content: Content) -> some View {
        let showing = active && group.currentTip?.id == step.id ? group.currentTip : nil
        content
            .popoverTip(showing, arrowEdge: arrow)
            .tipBackgroundInteraction(.enabled)
    }
}
