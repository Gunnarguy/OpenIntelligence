//
//  TourTips.swift
//  OpenIntelligence
//
//  The tour (5.8, rebuilt 2026-11-13): a small tip with an arrow on each control a newcomer could miss or misread, set
//  off by what the person just did or the first time its screen opens, one at a time and at most one new one every
//  minute and a half. Settings › How This Works › Where Things Are describes every screen. The plan, with
//  every control's file and why each tip is there, is `Docs/Engineering/ONBOARDING_TOUR_PLAN.md`.
//

import SwiftUI
import TipKit

/// One tip of the tour. Its text is a claim about the control it points at: each was written from that control's own
/// code, and a change to the control's behaviour changes the tip in the same commit. The raw values are the ids of the
/// first 5.8 tips where the meaning is the same, so a tip someone already closed or used stays gone.
enum TourStep: String, CaseIterable, Sendable {
    // Chat
    case composer, notFound, citation, factCheck, modePicker, modelPill, answerBubble, goDeeper, details, routeBadge
    case verdictBadge, aiHub, libraryPills, attach, dictation, moreMenu, sidebar, keyboard
    // The conversation list
    case threadSwipe
    // A cited passage
    case matchBanner, moreContext
    // Documents and the import queue
    case addDocument, librarySettings, paste, semanticSearch, newLibrary, libraryMenu, documentMenu, dragAndDrop
    case removeAll, deleteLibrary
    case pauseImport, processingMode, importStop
    // Library Settings
    case watchFolder, searchStyle, translation
    // Atlas
    case insights, atlasSettings, atlasMode, allLibraries
    // Database
    case databaseSections, runCheck
    // Database
    case databaseScope
    // Settings and Plans
    case howItWorks, privateCloud, glossary, siri, technicalDetails, xray, menuBar, redeemCode

    var id: String { "tour.\(rawValue)" }

    /// At most four words.
    var title: String {
        switch self {
        case .composer: "Ask your documents"
        case .notFound: "Not in your documents"
        case .citation: "Check the source"
        case .modePicker: "Standard or Deep Think"
        case .answerBubble: "Tap an answer"
        case .goDeeper: "Not enough? Go Deeper"
        case .details: "How it was answered"
        case .factCheck: "Checked against your files"
        case .modelPill: "Where answers are written"
        case .verdictBadge: "How it held up"
        case .threadSwipe: "Swipe to delete"
        case .libraryMenu: "Hold a library"
        case .removeAll: "Empty this library"
        case .deleteLibrary: "Delete this library"
        case .importStop: "Stop or hide"
        case .atlasMode: "Map size"
        case .aiHub: "Rework an answer"
        case .attach: "Add a file here"
        case .dictation: "Say it instead"
        case .moreMenu: "New chat and export"
        case .sidebar: "Your conversations"
        case .moreContext: "Need more context?"
        case .addDocument: "Add your files"
        case .databaseScope: "One library or all"
        case .howItWorks: "How it really works"
        case .glossary: "Every term explained"
        case .siri: "Ask with Siri"
        case .redeemCode: "Have a code?"
        case .routeBadge: "Where it ran"
        case .libraryPills: "Questions search one library"
        case .keyboard: "Keyboard shortcuts"
        case .matchBanner: "Is it really there?"
        case .librarySettings: "This library's settings"
        case .paste: "Paste works too"
        case .semanticSearch: "Search by meaning"
        case .newLibrary: "Keep topics apart"
        case .documentMenu: "Touch and hold"
        case .dragAndDrop: "Drop files here"
        case .pauseImport: "Pause anytime"
        case .processingMode: "Faster or cooler"
        case .watchFolder: "Watch a folder"
        case .searchStyle: "How this library searches"
        case .translation: "Documents in another language?"
        case .insights: "What the map found"
        case .atlasSettings: "Change the view"
        case .allLibraries: "All libraries at once"
        case .databaseSections: "Look inside the index"
        case .runCheck: "Something off?"
        case .privateCloud: "Cloud use is optional"
        case .technicalDetails: "See the work"
        case .xray: "Where your chip is"
        case .menuBar: "Menu bar questions"
        }
    }

    /// One short sentence.
    var message: String {
        switch self {
        case .composer:
            "Answers come only from this library's files, and each one names the passage it came from."
        case .notFound:
            "Nothing found here supports an answer, so it says so instead of guessing; Go Deeper searches harder."
        case .citation:
            "Tap a source in the answer, or a quote under Fact Check, to open that passage in your document, highlighted."
        case .modePicker:
            "Standard runs one search and is fastest, Deep Think runs several and checks them, Maximum goes deepest."
        case .answerBubble:
            "Tap it for copy, share, retry, Details and more."
        case .goDeeper:
            "Asks again in Deep Think, with several searches and checks instead of one."
        case .details:
            "The passages this answer used, how each claim held up against them, and where it ran."
        case .factCheck:
            "Each claim in the answer is checked against your documents; tap one to see the quotes that back it."
        case .modelPill:
            "On-Device writes every answer here, Hybrid uses Private Cloud Compute when an answer needs more room, PCC always does."
        case .verdictBadge:
            "This badge says how well the answer's claims matched your documents, from Verified to Not Checked."
        case .threadSwipe:
            "Swipe a conversation to delete it; each library keeps its own conversations."
        case .libraryMenu:
            "Touch and hold a library to copy its link, keep it on this device or in iCloud, or delete it."
        case .removeAll:
            "Removes every document from this library after you confirm; the library itself stays."
        case .deleteLibrary:
            "Deletes the open library after you confirm; it's there when you have more than one."
        case .importStop:
            "The X stops this import; the button beside it only hides the details."
        case .atlasMode:
            "These two buttons make the map here smaller or larger; the next one opens it full screen."
        case .aiHub:
            "Turns the last answer into key facts, steps, plain English or what it's missing, or illustrates it."
        case .attach:
            "A file you attach is imported into this library, so later questions can use it too."
        case .dictation:
            "Tap the microphone and speak; your words fill the question box, and nothing is sent until you send it."
        case .moreMenu:
            "Start a new conversation, export or clear this one, or turn on Technical Details."
        case .sidebar:
            "Every conversation in this library is kept here with its sources, so you can pick one up again."
        case .moreContext:
            "Shows the text around the passage, so you can read it as it sits in the document."
        case .addDocument:
            "Import PDFs, Word files, spreadsheets, slides, images, recordings and more into this library."
        case .databaseScope:
            "Choose whether these numbers describe the open library or every library together."
        case .howItWorks:
            "What runs on your device, what can run in Private Cloud Compute, and why, in plain words."
        case .glossary:
            "What each word in the app means, in plain words, for when a screen uses one you don't know."
        case .siri:
            "Siri and Shortcuts can ask a question, search your documents and add to a library."
        case .redeemCode:
            "Redeem an offer or gift code here."
        case .routeBadge:
            "On-device means nothing left this device; Private Cloud Compute runs only if you allow it."
        case .libraryPills:
            "Only the selected library is searched, so the answer comes from its documents alone."
        case .keyboard:
            "⌘1 Chat, ⌘2 Documents, ⌘F search, ⌘[ and ⌘] switch libraries."
        case .matchBanner:
            "This line says whether the passage was found in your file word for word, in part, or not at all."
        case .librarySettings:
            "How this library searches, how its documents are split, translation, and a folder it keeps up with."
        case .paste:
            "A file, link or text you copied becomes a document in this library when you paste it here."
        case .semanticSearch:
            "Finds passages that mean what you type, even in other words, without asking a whole question."
        case .newLibrary:
            "Each library has its own documents and settings, and a question in one never searches another."
        case .documentMenu:
            "Touch and hold a document to copy a link to it or delete it."
        case .dragAndDrop:
            "Drag files, or a whole folder, onto this list to import them into the open library."
        case .pauseImport:
            "Continue it later; a large file goes on from where it stopped, not from the start."
        case .processingMode:
            "Each tap picks the next mode: working harder finishes sooner, easing off keeps the device cooler."
        case .watchFolder:
            "Files you add to a linked folder in Files import by themselves, and your files are never changed (Pro and Lifetime)."
        case .searchStyle:
            "Automatic suits most libraries; Technical Manual weighs exact words, part numbers and codes more."
        case .translation:
            "Pick a language and passages are translated into it before they're searched."
        case .insights:
            "Each card is a topic the map found among your passages; tap one to see that part of your library."
        case .atlasSettings:
            "Projection, point size, labels and background for this map of your library."
        case .allLibraries:
            "Every library on one map, so you can see what each covers and where they overlap."
        case .databaseSections:
            "Each tab is one part of the index: what it found, its documents, the words it knows, upkeep and exact search."
        case .runCheck:
            "Looks through this library's index for problems and says whether a rebuild would help."
        case .privateCloud:
            "Documents are always searched on this device; here you choose whether an answer may be written on Private Cloud Compute."
        case .technicalDetails:
            "Shows the metrics bar, passage counts and badges under each answer."
        case .xray:
            "The outline is your chip, in the color of the part at work: purple Neural Engine, cyan GPU, orange CPU."
        case .menuBar:
            "A question box in the Mac's menu bar, one click away from any app."
        }
    }

    var symbol: String {
        switch self {
        case .composer: "bubble.left.and.text.bubble.right"
        case .notFound: "text.magnifyingglass"
        case .citation: "quote.bubble"
        case .modePicker: "dial.medium"
        case .answerBubble: "hand.tap"
        case .goDeeper: "brain"
        case .details: "info.circle"
        case .factCheck: "shield.checkered"
        case .modelPill: "iphone"
        case .verdictBadge: "checkmark.shield"
        case .threadSwipe: "hand.draw"
        case .libraryMenu: "folder"
        case .removeAll: "doc.badge.ellipsis"
        case .deleteLibrary: "folder.badge.minus"
        case .importStop: "xmark.circle"
        case .atlasMode: "rectangle.arrowtriangle.2.outward"
        case .aiHub: "apple.intelligence"
        case .attach: "paperclip"
        case .dictation: "mic"
        case .moreMenu: "ellipsis.circle"
        case .sidebar: "sidebar.left"
        case .moreContext: "text.alignleft"
        case .addDocument: "doc.badge.plus"
        case .databaseScope: "line.3.horizontal.decrease.circle"
        case .howItWorks: "questionmark.circle"
        case .glossary: "character.book.closed"
        case .siri: "mic.circle"
        case .redeemCode: "giftcard"
        case .routeBadge: "lock.shield"
        case .libraryPills: "books.vertical"
        case .keyboard: "keyboard"
        case .matchBanner: "checkmark.seal"
        case .librarySettings: "slider.horizontal.3"
        case .paste: "doc.on.clipboard"
        case .semanticSearch: "sparkle.magnifyingglass"
        case .newLibrary: "folder.badge.plus"
        case .documentMenu: "hand.point.up.left"
        case .dragAndDrop: "square.and.arrow.down"
        case .pauseImport: "pause.circle"
        case .processingMode: "thermometer.medium"
        case .watchFolder: "folder.badge.gearshape"
        case .searchStyle: "scope"
        case .translation: "translate"
        case .insights: "lightbulb"
        case .atlasSettings: "slider.horizontal.3"
        case .allLibraries: "square.stack.3d.up"
        case .databaseSections: "cylinder.split.1x2"
        case .runCheck: "stethoscope"
        case .privateCloud: "cloud"
        case .technicalDetails: "waveform.path.ecg"
        case .xray: "cpu"
        case .menuBar: "menubar.rectangle"
        }
    }

    /// The button the tip offers when it can do the thing for the person; the view that shows the tip performs it.
    var actionTitle: String? {
        switch self {
        case .composer: "Try a question"
        case .notFound: "Go Deeper"
        case .citation, .answerBubble: "Show me"
        case .newLibrary: "New Library"
        default: nil
        }
    }

    /// The lessons a new person needs from the first question on, each at the moment it applies. These skip the
    /// pacing; every other tip waits its turn.
    var isEssential: Bool {
        switch self {
        case .composer, .notFound, .citation, .matchBanner, .modePicker, .addDocument: true
        default: false
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
    /// The X-Ray has a place to draw on this device (`DeviceComponentLayout.current.socPlacement`, 5.8).
    @Parameter static var xrayDrawsHere: Bool = false
    /// The newest answer found nothing in the documents that supports it (`StructuredAnswer.refuse`).
    @Parameter(.transient) static var lastAnswerNotFound: Bool = false
    /// An import of three or more files, or of a file of 50 pages or 10 MB, is running (`IngestionQueueOverlay`).
    @Parameter(.transient) static var largeImportRunning: Bool = false
    /// The pacing (`Tour.pace`): "launch" for the first minute after launch, "open" when a paced tip may show, or the
    /// step name of the one paced tip that has the turn. Not kept between launches.
    @Parameter(.transient) static var pace: String = "launch"

    static let settingsOpened = Tips.Event(id: "tour.settingsOpened")
    static let appLaunched = Tips.Event(id: "tour.appLaunched")
}

/// A tour tip as TipKit sees it. Gone for good once its control is used (`Tour.used`), its close button is tapped, it
/// has been shown three times, or it has been on screen a minute in all.
struct TourTip: Tip {
    let step: TourStep

    init(_ step: TourStep) { self.step = step }

    var id: String { step.id }
    // Smaller than TipKit's own (headline and body, 17 points): set on the tip's text, which TipKit keeps, so it reaches
    // the popover too, and still scales with the person's text size. The cards' style sets the same sizes.
    var title: Text { Text(step.title).font(.subheadline.weight(.semibold)) }
    var message: Text? { Text(step.message).font(.footnote) }
    var image: Image? { Image(systemName: step.symbol) }

    var actions: [Action] {
        step.actionTitle.map { [Action(id: Tour.actionID, title: $0)] } ?? []
    }

    var options: [any TipOption] {
        MaxDisplayCount(Tour.maxShowings)
        MaxDisplayDuration(Tour.maxSecondsOnScreen)
    }

    var rules: [Rule] {
        var rules: [Rule] = [#Rule(TourContext.$welcomeClosed) { $0 == true }]
        if !step.isEssential {
            // One new tip every few minutes, never in the first minute after launch (`Tour.claimTurn`).
            let name = step.rawValue
            rules.append(#Rule(TourContext.$pace) { $0 == "open" || $0 == name })
        }
        switch step {
        case .composer:
            rules.append(#Rule(TourContext.$answers) { $0 == 0 })
        case .notFound:
            rules.append(#Rule(TourContext.$lastAnswerNotFound) { $0 == true })
        case .citation, .factCheck, .modePicker, .modelPill, .goDeeper, .details, .routeBadge, .verdictBadge, .aiHub,
            .attach, .dictation:
            rules.append(#Rule(TourContext.$answers) { $0 >= 1 })
        case .moreMenu:
            rules.append(#Rule(TourContext.$answers) { $0 >= 2 })
        case .sidebar:
            rules.append(#Rule(TourContext.$answers) { $0 >= 3 })
        case .glossary, .siri:
            rules.append(#Rule(TourContext.settingsOpened) { $0.donations.count >= 2 })
        case .answerBubble:
            rules.append(#Rule(TourContext.$answers) { $0 >= 2 })
        case .libraryPills:
            rules.append(#Rule(TourContext.$libraries) { $0 >= 2 })
            rules.append(#Rule(TourContext.$answers) { $0 >= 1 })
        case .keyboard:
            rules.append(#Rule(TourContext.$isMac) { $0 == true })
            rules.append(#Rule(TourContext.appLaunched) { $0.donations.count >= 2 })
        case .paste, .librarySettings:
            rules.append(#Rule(TourContext.$documents) { $0 >= 1 })
        case .newLibrary, .semanticSearch:
            rules.append(#Rule(TourContext.$documents) { $0 >= 3 })
        case .documentMenu:
            rules.append(#Rule(TourContext.$documents) { $0 >= 3 })
            rules.append(#Rule(TourContext.$isMac) { $0 == false })
        case .dragAndDrop:
            rules.append(#Rule(TourContext.$isLargeScreen) { $0 == true })
        case .pauseImport:
            rules.append(#Rule(TourContext.$largeImportRunning) { $0 == true })
        case .allLibraries, .deleteLibrary:
            rules.append(#Rule(TourContext.$libraries) { $0 >= 2 })
        case .removeAll:
            rules.append(#Rule(TourContext.$documents) { $0 >= 1 })
        case .libraryMenu:
            rules.append(#Rule(TourContext.$documents) { $0 >= 1 })
            rules.append(#Rule(TourContext.$isMac) { $0 == false })
        case .privateCloud:
            rules.append(#Rule(TourContext.$privateCloudAvailable) { $0 == true })
        case .xray:
            // The X-Ray draws nothing on a Mac or on a device with no sourced place (`HardwareXRayOverlay`).
            rules.append(#Rule(TourContext.$isMac) { $0 == false })
            rules.append(#Rule(TourContext.$xrayDrawsHere) { $0 == true })
        case .menuBar:
            rules.append(#Rule(TourContext.$isMac) { $0 == true })
        case .threadSwipe, .importStop, .atlasMode, .matchBanner, .moreContext, .addDocument, .databaseScope, .howItWorks, .redeemCode, .processingMode, .watchFolder, .searchStyle, .translation, .insights, .atlasSettings,
            .databaseSections, .runCheck, .technicalDetails:
            break
        }
        return rules
    }
}

/// The tour's groups, one per screen, its pacing, and what the app tells it.
///
/// A group is `.firstAvailable`: of its tips not yet used or closed, the first whose rules pass is the one shown, in
/// the order listed. `.ordered` would wait on a tip whose rules can't pass yet and show nothing after it.
@MainActor
enum Tour {
    /// Each screen's tips, in the order they show. Every `TourStep` is in exactly one (`TourTipTests`).
    nonisolated static let screens: [(name: String, steps: [TourStep])] = [
        ("chat", [
            .composer, .notFound, .citation, .factCheck, .modePicker, .modelPill, .answerBubble, .goDeeper, .details,
            .routeBadge, .verdictBadge, .aiHub, .libraryPills, .attach, .dictation, .moreMenu, .sidebar, .keyboard,
        ]),
        ("threads", [.threadSwipe]),
        ("source", [.matchBanner, .moreContext]),
        ("documents", [
            .addDocument, .librarySettings, .paste, .semanticSearch, .newLibrary, .libraryMenu, .documentMenu,
            .dragAndDrop, .removeAll, .deleteLibrary,
        ]),
        ("importQueue", [.pauseImport, .importStop, .processingMode]),
        ("librarySettings", [.watchFolder, .searchStyle, .translation]),
        ("atlas", [.insights, .atlasSettings, .atlasMode, .allLibraries]),
        ("database", [.databaseScope, .databaseSections, .runCheck]),
        ("settings", [.howItWorks, .privateCloud, .glossary, .siri, .technicalDetails, .xray, .menuBar]),
        ("plans", [.redeemCode]),
    ]

    static let chat = group("chat")
    static let threads = group("threads")
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

    // MARK: Limits

    /// A tip gives up after this many showings (`MaxDisplayCount`).
    nonisolated static let maxShowings = 3
    /// ... or after this long on screen in all (`MaxDisplayDuration`). 60 s is TipKit's floor: "Tip views have a minimum
    /// display duration of 60 seconds before they can be automatically invalidated by MaxDisplayDuration"
    /// (developer.apple.com/documentation/tipkit/tips/maxdisplayduration, fetched 2026-11-13); 20 s was asked for and
    /// TipKit's own log showed a 60 s monitor.
    nonisolated static let maxSecondsOnScreen: TimeInterval = 60
    /// No paced tip in the first minute after launch.
    nonisolated static let launchQuietSeconds: Double = 60
    /// After a paced tip shows, the next one waits this long. TipKit's own display frequency goes no lower than
    /// hourly (`Tips.ConfigurationOption.DisplayFrequency`, iOS 27 SDK), so the pacing is a rule (`TourContext.pace`).
    nonisolated static let secondsBetweenTips: Double = 90
    nonisolated static let paceAtLaunch = "launch"
    /// The tip's icon. TipKit's own is about 40 points, a third of a tip on a 6.3-inch iPhone (2026-11-13).
    nonisolated static let imageSize = CGSize(width: 24, height: 24)
    nonisolated static let actionID = "tour.do"

    /// Opens the pacing a minute after launch (`AppTipConfiguration.configure`).
    static func startPacing() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(launchQuietSeconds))
            if TourContext.pace == paceAtLaunch { TourContext.pace = "open" }
        }
    }

    /// A paced tip is on screen: it takes the turn, which hides any other paced tip, and the next may show only
    /// `secondsBetweenTips` later. An essential tip takes no turn.
    static func claimTurn(_ step: TourStep) {
        guard !step.isEssential, TourContext.pace == "open" else { return }
        TourContext.pace = step.rawValue
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(secondsBetweenTips))
            if TourContext.pace == step.rawValue { TourContext.pace = "open" }
        }
    }

    /// The control was used: its tip goes for good, and the next in its group can show.
    static func used(_ step: TourStep) {
        TourTip(step).invalidate(reason: .actionPerformed)
    }

    /// Settings › How This Works › Show Me Around: every tip can show again, with no relaunch, still one at a time.
    static func showAgain() async {
        for step in TourStep.allCases { await TourTip(step).resetEligibility() }
        if TourContext.pace == paceAtLaunch { TourContext.pace = "open" }
        VerificationJournal.record("tour.showAgain")
    }

    private static var shownThisLaunch: Set<TourStep> = []

    /// A tip was put on screen: it takes the pacing turn, and the development journal records it once per launch
    /// with its screen and its place in that screen's order. `tip.status` "available" is TipKit's eligibility, not this.
    static func noteShown(_ step: TourStep) {
        claimTurn(step)
        guard VerificationJournal.isEnabled, shownThisLaunch.insert(step).inserted else { return }
        let screen = screens.first { $0.steps.contains(step) }
        VerificationJournal.record(
            "tip.shown",
            ["tip": step.rawValue, "screen": screen?.name ?? "none",
                "rank": "\(screen?.steps.firstIndex(of: step) ?? -1)"])
    }

    /// Writes each tip's changes to the development build's event log: available, then used, closed or given up
    /// (5.8), so a pull from a device shows where people stop.
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
    /// Points `step`'s tip at this in-content control when it is the one its group shows now. The screen stays usable
    /// under it. `when` false leaves the view without the tip: one of many alike (every answer bubble) carries it only
    /// on one. `perform` does the tip's action ("Show me") for the person. Never on a toolbar item (see the modifier).
    func tour(
        _ step: TourStep, in group: TipGroup, arrow: Edge? = nil, when active: Bool = true,
        perform: (@MainActor () -> Void)? = nil
    ) -> some View {
        modifier(TourTipModifier(step: step, group: group, arrow: arrow, active: active, perform: perform))
    }
}

private struct TourTipModifier: ViewModifier {
    let step: TourStep
    let group: TipGroup
    let arrow: Edge?
    let active: Bool
    let perform: (@MainActor () -> Void)?

    func body(content: Content) -> some View {
        let showing = active && group.currentTip?.id == step.id ? group.currentTip : nil
        // The popover only while this control's tip is the one showing (5.8, 2026-11-13). Attached with a nil tip, as
        // through the first 5.8 builds, TipKit still put a `UIAppearanceMonitor` controller into the navigation stack
        // for each control in a toolbar: Chat's stack read 4 deep with one on top (the owner's iPhone, 2026-11-07 to
        // 11-13), and tapping the Chat tab again popped it to its root, the monitors were pushed back, and Chat went
        // white (`chat.disappear` and `chat.appear` ten times in eight seconds, `chat.blankRebuildSkipped`). Since the
        // tour's rebuild no tip is on a toolbar item at all.
        // Anchored to a clear layer behind the control, not to the control: on a control drawn with interactive Liquid
        // Glass (Documents' action chips) the popover attached to the control itself showed its text with no
        // background over the chips (the iOS 27 Simulator, 2026-11-13).
        content
            .background {
                if let showing {
                    Color.clear
                        .popoverTip(showing, arrowEdge: arrow) { action in
                            guard action.id == Tour.actionID, let perform else { return }
                            TourTip(step).invalidate(reason: .actionPerformed)
                            perform()
                        }
                        .tipBackgroundInteraction(.enabled)
                        .tourTipSize()
                }
            }
        .onChange(of: showing?.id, initial: true) { _, id in
            if id != nil { Tour.noteShown(step) }
        }
    }
}

extension View {
    /// The system tip's icon size for the tour (`Tour.imageSize`). Set outside `popoverTip`, so the popover reads it
    /// (seen in the iOS 27 Simulator). The text's size is set on the tip's own `Text` (`TourTip.title`), because a
    /// `dynamicTypeSize` set here reached an inline tip but not the popover.
    func tourTipSize() -> some View {
        tipImageSize(Tour.imageSize)
    }

    /// Marks a toolbar button as the place a tip's arrow points (iOS 26 `tipAnchor`). The tip itself is drawn in the
    /// content by `TourToolbarTips`, never as a popover on the toolbar item (see `TourTipModifier`).
    func tourAnchor(_ step: TourStep) -> some View {
        tipAnchor(step.rawValue)
    }
}

/// A screen's toolbar tips: the one its group shows now, drawn under the toolbar with its arrow pointing up at the
/// button that carries `tourAnchor` (`TipView(_:arrowEdge:anchorID:)`, iOS 26).
struct TourToolbarTips: View {
    let steps: [TourStep]
    let group: TipGroup

    var body: some View {
        let step = steps.first { group.currentTip?.id == $0.id }
        Group {
            if let step {
                TipView(TourTip(step), arrowEdge: .top, anchorID: step.rawValue)
                    .tipBackgroundInteraction(.enabled)
                    .tourTipSize()
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.top, DSSpacing.xs)
                    .frame(maxWidth: 480)
                    .transition(.opacity)
            }
        }
        .animation(DSAnimations.snappySpring, value: step)
        .onChange(of: step, initial: true) { _, shown in
            if let shown { Tour.noteShown(shown) }
        }
    }
}

/// A tour tip as a card in the content where it belongs: the empty chat, under an answer. Shown only while it is the
/// one its group shows now. The button does the thing; the X closes it for good.
struct TourCard: View {
    let step: TourStep
    let group: TipGroup
    var active = true
    var perform: (@MainActor () -> Void)? = nil

    var body: some View {
        let showing = active && group.currentTip?.id == step.id
        Group {
            if showing {
                TipView(TourTip(step))
                    .tipViewStyle(
                        TourCardStyle(
                            perform: perform.map { perform in
                                {
                                    TourTip(step).invalidate(reason: .actionPerformed)
                                    perform()
                                }
                            },
                            close: { TourTip(step).invalidate(reason: .tipClosed) })
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(DSAnimations.snappySpring, value: showing)
        .onChange(of: showing, initial: true) { _, isUp in
            if isUp { Tour.noteShown(step) }
        }
    }
}

/// The tour card's look: the app's Liquid Glass card, its accent, its type sizes, a labelled action and a close
/// button with Apple's 44-point tap target.
struct TourCardStyle: TipViewStyle {
    var perform: (@MainActor () -> Void)?
    var close: @MainActor () -> Void

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            configuration.image?
                .font(.system(size: 20))
                .foregroundStyle(DSColors.accent)
                .frame(width: 24, height: 24)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                configuration.title
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DSColors.primaryText)
                // The readable gray for every tip (5.7): `.secondary` "failed" Apple's contrast audit in Settings.
                configuration.message?
                    .font(.footnote)
                    .foregroundStyle(DSColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let perform, let action = configuration.actions.first {
                    Button {
                        DSHaptics.selection()
                        perform()
                    } label: {
                        action.label()
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DSColors.accent)
                            .padding(.horizontal, DSSpacing.md)
                            .padding(.vertical, DSSpacing.xs)
                            .background(Capsule().fill(DSColors.accent.opacity(0.12)))
                            .frame(minHeight: DSSpacing.tapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DSColors.secondaryText)
                    .frame(width: DSSpacing.tapTarget, height: DSSpacing.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .padding(.top, -DSSpacing.sm)
            .padding(.trailing, -DSSpacing.sm)
        }
        .padding(.leading, DSSpacing.md)
        .padding(.trailing, DSSpacing.sm)
        .padding(.vertical, DSSpacing.sm)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
