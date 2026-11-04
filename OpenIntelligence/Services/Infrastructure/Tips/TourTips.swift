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
        case .composer: "Ask your documents"
        case .modePicker: "How hard it works"
        case .libraryPills: "Your libraries"
        case .answerBubble: "Do more with an answer"
        case .citation: "Where this came from"
        case .goDeeper: "Not enough? Go Deeper"
        case .details: "How it was answered"
        case .routeBadge: "Where it ran"
        case .dictation: "Say it instead"
        case .attach: "Add a file here"
        case .sidebar: "Your conversations"
        case .aiHub: "Rework an answer"
        case .moreMenu: "New chat and export"
        case .keyboard: "Faster with the keyboard"
        case .matchBanner: "Is it really there?"
        case .moreContext: "Need more context?"
        case .addDocument: "Add your files"
        case .paste: "Paste works too"
        case .newLibrary: "Keep topics apart"
        case .librarySettings: "This library's settings"
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
        case .composer: "Ask anything about the documents in this library. The answer is written from your own files, and each point links to the passage it came from, so you can check it."
        case .modePicker: "Standard runs one search and answers fastest. Deep Think runs several searches and checks, for questions that need more. Maximum goes deepest and takes longest."
        case .libraryPills: "Each pill is a library: a set of documents kept apart from the rest. A question searches only the selected one, so the answer comes from those documents alone. The number is how many it holds."
        case .answerBubble: "Tap an answer to copy it, share it, ask again, translate it, or open how it was answered: the passages it used and where it ran."
        case .citation: "Each source is a passage from your document. Tap one to open the document at that passage, highlighted, with a line saying whether the words were found exactly, in part, or not at all."
        case .goDeeper: "Asks the same question again in Deep Think: several searches and checks instead of one. Use it when an answer is thin or misses something you know is there."
        case .details: "The passages this answer used, how each claim held up against them, and whether it was made on your device or in Private Cloud Compute."
        case .routeBadge: "On-device means the answer was made on this device and nothing left it. Private Cloud Compute is Apple's server for bigger questions, used only if you allow it."
        case .dictation: "Tap the microphone and say your question instead of typing it. It's sent like a typed one."
        case .attach: "Attach a file to ask about it right away. It's imported into this library, so later questions can use it too."
        case .sidebar: "Every conversation in this library is kept here with its sources. Open one to pick up where you left off, or start a new one."
        case .aiHub: "Turn the last answer into key facts, steps, plain English, or what it's missing, or illustrate it with Image Playground where that's available."
        case .moreMenu: "Start a fresh conversation, export this one as a file, or turn on Technical Details to see the numbers behind each answer."
        case .keyboard: "⌘1 Chat, ⌘2 Documents, ⌘F search, ⌘[ and ⌘] switch libraries."
        case .matchBanner: "This line checks the passage against your document: found word for word, in part, or not found. It shows the words are in your file; whether the answer read them right is yours to judge."
        case .moreContext: "Shows the text around the passage, so you can read it the way it sits in the document."
        case .addDocument: "Import PDFs, Word files, spreadsheets, slides, images, recordings and more into this library. The app reads them on your device and makes every passage searchable."
        case .paste: "Copy a file, a link or some text anywhere, then paste it here and it becomes a document in this library."
        case .newLibrary: "A new library is a separate set of documents with its own settings. Questions in one never search another, so work, home and hobbies stay apart."
        case .librarySettings: "How this library searches, how its documents are cut into passages, whether they're translated, and a folder it keeps up with."
        case .semanticSearch: "Find passages that mean what you type, even in different words, without asking a whole question."
        case .documentMenu: "Touch and hold a document to copy its link or delete it."
        case .dragAndDrop: "Drag files, or a whole folder, onto this list to import them into the open library."
        case .pauseImport: "Pause an import and pick it up later. It continues from where it stopped, not from the start."
        case .processingMode: "Choose how hard the device works while importing. Working harder finishes sooner; easing off keeps the device cooler."
        case .watchFolder: "Link this library to a folder in Files. Files you add there import by themselves, and a changed file replaces its old version. Your files are never changed. Pro and Lifetime."
        case .searchStyle: "Automatic suits most libraries. Technical Manual weighs exact words, part numbers and codes more, for manuals and specs."
        case .translation: "Pick a language and passages are translated into it before they're searched, so you can ask in your language about documents written in another."
        case .atlasSettings: "Projection, point size, labels and background for this map of your library."
        case .insights: "Each card is a topic the map found among your passages. Tap one to see that part of your library."
        case .allLibraries: "Every library on one map, so you can see what each covers and where they overlap."
        case .databaseScope: "Choose whether these numbers describe the open library or every library together."
        case .databaseSections: "Each tab is one part of the index: what it found in your library, its documents, the words it knows, upkeep, and a search for exact words."
        case .runCheck: "Run Check looks through this library's index for problems and says what it found, so you know whether a rebuild would help."
        case .howItWorks: "What runs on your device, what can run in Private Cloud Compute, and why, in plain words. Show Me Around brings these tips back."
        case .privateCloud: "Private Cloud Compute is Apple's server for questions too big for the device. Choose never, or when it may be used. Your documents are searched on your device either way."
        case .glossary: "What each word in the app means, in plain words, for when a screen uses one you don't know."
        case .technicalDetails: "Shows the metrics bar, passage counts and badges under each answer, for when you want the numbers."
        case .siri: "Siri and Shortcuts can ask a question, search your documents and add to a library, without opening the app."
        case .menuBar: "A question box in the Mac's menu bar, one click away from any app."
        case .redeemCode: "Redeem an offer or gift code here."
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

    private static var shownThisLaunch: Set<TourStep> = []

    /// A tip was put on its control (5.8 journal): once per tip per launch, with its screen and its place in that
    /// screen's stops. `tip.status` "available" is TipKit's eligibility, not this.
    static func noteShown(_ step: TourStep) {
        guard VerificationJournal.isEnabled, shownThisLaunch.insert(step).inserted else { return }
        let screen = screens.first { $0.steps.contains(step) }
        VerificationJournal.record(
            "tip.shown",
            ["tip": step.rawValue, "screen": screen?.name ?? "none",
                "rank": "\(screen?.steps.firstIndex(of: step) ?? -1)"])
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
        #if DEBUG
            .onChange(of: showing?.id, initial: true) { _, id in
                if id != nil { Tour.noteShown(step) }
            }
        #endif
    }
}
