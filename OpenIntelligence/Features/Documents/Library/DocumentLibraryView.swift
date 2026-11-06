//
//  DocumentLibraryView.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import AppIntents
import StoreKit
import SwiftUI
import UniformTypeIdentifiers

struct DocumentLibraryView: View {
    @EnvironmentObject var onboardingStore: OnboardingStateStore
    @EnvironmentObject var entitlementStore: EntitlementStore
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var workspaceSyncService: WorkspaceSyncService
    @ObservedObject var ragService: RAGService
    @ObservedObject var containerService: ContainerService
    @State var showingFilePicker = false
    @Environment(\.undoManager) var undoManager
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    /// A document in an iCloud library that a swipe asked to delete, waiting for the answer (5.7).
    @State var swipeDeleteCandidate: Document?
    /// The parts of the library area a Finder drag is over, driving the drop outline (`takingDroppedFiles(as:)`).
    @State var dropTargetedParts: Set<LibraryDropPart> = []
    var isDropTargeted: Bool { !dropTargetedParts.isEmpty }
    @State private var showingProcessingSummary = false
    @State private var lastProcessedSummary: ProcessingSummary?
    @State var showingContainerSettings = false
    @State var showingSemanticSearch = false
    /// The document a request from outside the screen opened: Spotlight, the Open Document action,
    /// Handoff (5.7). Through 5.6 those landed on the document's library.
    @State var openedDocumentID: UUID?
    /// The one wait for documents to load that a document request may start (5.7).
    @State var documentRequestWait: Task<Void, Never>?
    /// What a search from Siri asked for, run as the search screen opens (5.7).
    @State var handedOverSearch = ""
    @State var isImportingSamples = false
    /// Display names of samples just refreshed automatically, driving the explanatory
    /// banner. `nil` once dismissed.
    @State var refreshedSampleNames: [String]?
    @State var sampleImportError: String?
    @State var sampleImportStatusMessage: String?
    @State var showingPlanSheet = false
    @State var activePaywallEntryPoint: PlanUpgradeEntryPoint = .documents

    // New library naming
    @State var showingNewLibraryPrompt = false
    @State var showingNewLibraryStorageChoice = false
    @State var shouldShowStorageChoiceAfterDismissal = false
    @State var newLibraryName = ""
    @State var pendingNewLibraryName = ""

    // Delete library confirmation
    @State var showingDeleteConfirmation = false
    @State var libraryToDelete: KnowledgeContainer?
    @State var showingClearAllConfirmation = false
    /// The library waiting on confirmation to become Local Only.
    ///
    /// That switch is destructive and had no confirmation anywhere on its most reachable path.
    /// `handleSetLibrarySyncMode` calls `reconfigureIfNeeded()`, after which the library is
    /// filtered out of `sharedVisibleContainers` and `cleanupSharedWorkspace` removes its shared
    /// artifacts and files, so a single tap on a segmented control deleted the library's iCloud
    /// copy while the toast said only that it "stays on this device".
    @State var pendingLocalOnlyLibrary: KnowledgeContainer?

    // Vision Capture and Cached Docs
    @State private var showVisionCapture = false
    @State var showCachedDocs = false
    /// How many documents the documentation cache holds.
    ///
    /// Drives whether the Cached Documents entry appears at all. `DocumentationCacheService` is an
    /// `actor`, so this cannot be read synchronously from the menu body and is refreshed instead.
    @State var cachedDocumentCount = 0
    @State var pendingImportURLs: [URL] = []
    /// The library a reviewed import goes to: the one chosen in the Opened File sheet, or nil for the open one.
    @State var pendingImportLibraryId: UUID?
    @State var pendingImportReview: DocumentImportReview?
    @State var showingImportReview = false
    /// Files "Open in" handed over, shown before anything is added (`OpenedFilesSheet`).
    @State var openedFiles: [URL] = []
    @State var showingOpenedFiles = false
    @State var addOpenedFiles = false
    /// The library chosen in the Opened File sheet (5.7).
    @State var openedFilesLibraryId: UUID?
    @State var isRefreshingSharedWorkspace = false
    @State var sharedWorkspaceRefreshMessage: String?
    @State var showingSharedSyncReviewDialog = false

    static let sharedWorkspaceRelativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    let onViewVisualizations: (() -> Void)?

    var documentLimit: Int { entitlementStore.documentLimit }
    /// How many files a dropped or chosen folder may bring in: the room left on the plan, and never
    /// more than 500 (5.7).
    var folderFileRoom: Int { max(0, min(500, documentLimit - ragService.countedDocumentCount)) }
    /// The plan's limit counts the person's own documents, not the app's guides (5.8, `countedDocumentCount`).
    var isAtDocumentLimit: Bool {
        ragService.countedDocumentCount >= documentLimit
    }

    private var libraryLimit: Int { entitlementStore.libraryLimit }
    var shouldShowQuotaBanner: Bool {
        !entitlementStore.hasUnlimitedDocuments
    }

    init(ragService: RAGService, containerService: ContainerService, onViewVisualizations: (() -> Void)? = nil) {
        _ragService = ObservedObject(wrappedValue: ragService)
        _containerService = ObservedObject(wrappedValue: containerService)
        self.onViewVisualizations = onViewVisualizations
    }

    var filteredDocuments: [Document] {
        let activeId = containerService.activeContainerId
        let defaultId = containerService.containers.first?.id
        return ragService.documents.filter { doc in
            if let cid = doc.containerId {
                return cid == activeId
            } else {
                // Legacy docs without containerId appear only in the default container
                return activeId == defaultId
            }
        }
    }

    var filteredTotalChunks: Int {
        filteredDocuments.reduce(0) { $0 + $1.totalChunks }
    }

    var iCloudLibraryCount: Int {
        containerService.containers.filter { $0.syncMode == .iCloudShared }.count
    }

    var hasConfiguredICloudLibraries: Bool {
        iCloudLibraryCount > 0
    }

    var localOnlyLibraryCount: Int {
        max(containerService.containers.count - iCloudLibraryCount, 0)
    }

    var activeLibrary: KnowledgeContainer? {
        containerService.activeContainer
    }

    var hasICloudSyncAccess: Bool {
        entitlementStore.effectiveTier.isAtLeast(.pro)
    }

    var pendingSharedSyncConflict: WorkspaceSyncService.PendingBootstrapConflict? {
        workspaceSyncService.pendingBootstrapConflict
    }

    var isDeletionOnlySharedConflict: Bool {
        guard let conflict = pendingSharedSyncConflict else { return false }
        return !conflict.localOnlyLibraryNames.isEmpty && conflict.sharedOnlyLibraryNames.isEmpty
    }

    var isAdditionOnlySharedConflict: Bool {
        guard let conflict = pendingSharedSyncConflict else { return false }
        return conflict.localOnlyLibraryNames.isEmpty && !conflict.sharedOnlyLibraryNames.isEmpty
    }

    var sharedSyncReviewTitle: String {
        if isDeletionOnlySharedConflict {
            return "Libraries were removed from iCloud"
        }

        if isAdditionOnlySharedConflict {
            return "New iCloud libraries are available"
        }

        return "Review iCloud library changes"
    }

    var sharedSyncReviewMessage: String {
        guard let conflict = pendingSharedSyncConflict else {
            return "Review the latest iCloud library changes for this device."
        }

        if isDeletionOnlySharedConflict {
            let names = conflict.localOnlyLibraryNames.joined(separator: ", ")
            return "These libraries still exist on this device but were removed from iCloud: \(names). Delete them here too, keep them local, or restore them to iCloud."
        }

        if isAdditionOnlySharedConflict {
            let names = conflict.sharedOnlyLibraryNames.joined(separator: ", ")
            return "These libraries are available in iCloud but not on this device yet: \(names)."
        }

        let localNames = conflict.localOnlyLibraryNames.joined(separator: ", ")
        let sharedNames = conflict.sharedOnlyLibraryNames.joined(separator: ", ")
        return "Only on this device: \(localNames). Only in iCloud: \(sharedNames)."
    }

}

    /// The capsule itself, with no button behaviour.
    ///
    /// Split out so the overflow `Menu` can use the same shape as the two real chips beside it.
    /// A `Menu` supplies its own tap handling, so wrapping `DocumentActionChip` inside one would
    /// nest a `Button` in a `Menu` and the chip would swallow the tap.
    struct DocumentActionChipLabel: View {
        let title: String
        let systemImage: String
        var tint: Color = .accentColor
        var isEnabled: Bool = true

        /// Icon-only collapses the chip to a circle. The title is not dropped: it moves to the
        /// accessibility label and the hover/long-press tooltip, so VoiceOver reads exactly what
        /// it read before. Only the visual text goes away.
        var iconOnly: Bool = false

        var body: some View {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: systemImage)
                    .scaledFont(size: iconOnly ? 15 : 11, weight: .bold)

                if !iconOnly {
                    Text(title)
                        .scaledFont(size: 11, weight: .bold)
                        .lineLimit(1)
                }
            }
            // 44pt minimum touch target in icon-only form. An unreliable tap reads as a slow
            // app, so the target stays full size even though the chip looks smaller.
            .frame(minWidth: iconOnly ? DSSpacing.tapTarget : 0, minHeight: iconOnly ? DSSpacing.tapTarget : 0)
            .padding(.horizontal, iconOnly ? 0 : DSSpacing.md)
            .padding(.vertical, iconOnly ? 0 : DSSpacing.sm)
            .background(.ultraThinMaterial)
            .foregroundStyle(isEnabled ? tint : .secondary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isEnabled ? tint.opacity(0.15) : Color.secondary.opacity(0.1), lineWidth: 1)
            )
            .glassEffectHelper(isSelected: false, interactive: isEnabled)
            .opacity(isEnabled ? 1 : 0.6)
        }
    }

    struct DocumentActionChip: View {
        let title: String
        let systemImage: String
        var tint: Color = .accentColor
        var isEnabled: Bool = true
        var iconOnly: Bool = false
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                DocumentActionChipLabel(
                    title: title,
                    systemImage: systemImage,
                    tint: tint,
                    isEnabled: isEnabled,
                    iconOnly: iconOnly
                )
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .accessibilityLabel(title)
            .help(title)
        }
    }

private struct DocumentUtilityChipLabel: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor
    var showsProgress: Bool = false

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: systemImage)
                    .scaledFont(size: 10, weight: .semibold)
            }

            Text(title)
                .scaledFont(size: 11, weight: .semibold)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .background(
            Capsule()
                .fill(tint.opacity(0.1))
                .overlay(
                    Capsule()
                        .stroke(tint.opacity(0.16), lineWidth: 1)
                )
        )
    }
}

struct DocumentImportReview {
    private let transcriptOnlyFiles: [String]
    private let experimentalFiles: [String]
    private let convertFirstFiles: [String]

    init(urls: [URL]) {
        transcriptOnlyFiles = urls
            .filter { DocumentImportReadiness.classify(url: $0) == .transcriptOnly }
            .map(\ .lastPathComponent)
        experimentalFiles = urls
            .filter { DocumentImportReadiness.classify(url: $0) == .experimental }
            .map(\ .lastPathComponent)
        convertFirstFiles = urls
            .filter { DocumentImportReadiness.classify(url: $0) == .convertFirst }
            .map(\ .lastPathComponent)
    }

    var needsReview: Bool {
        !transcriptOnlyFiles.isEmpty || !experimentalFiles.isEmpty || !convertFirstFiles.isEmpty
    }

    var message: String {
        var parts: [String] = [
            "Strongest imports: PDF, DOCX/XLSX/PPTX, TXT/MD, CSV, images, and scans."
        ]

        if !transcriptOnlyFiles.isEmpty {
            parts.append("Transcript only: \(shortList(transcriptOnlyFiles)). Video and audio imports index spoken content, not full visual meaning.")
        }

        if !experimentalFiles.isEmpty {
            parts.append("Reduced-fidelity parsing: \(shortList(experimentalFiles)). These files often lose structure and usually need cleanup first.")
        }

        if !convertFirstFiles.isEmpty {
            parts.append("Convert first for the cleanest results: \(shortList(convertFirstFiles)). Exporting to PDF or modern Office usually gives cleaner retrieval.")
        }

        parts.append("Import anyway?")
        return parts.joined(separator: "\n\n")
    }

    private func shortList(_ files: [String]) -> String {
        let preview = files.prefix(3).joined(separator: ", ")
        if files.count > 3 {
            return "\(preview), +\(files.count - 3) more"
        }
        return preview
    }
}

private enum DocumentImportReadiness {
    case strong
    case transcriptOnly
    case experimental
    case convertFirst

    static func classify(url: URL) -> Self {
        switch url.pathExtension.lowercased() {
        case "pdf", "txt", "md", "markdown", "mdown", "rtf", "csv",
             "json", "jsonl", "ndjson",
             "docx", "xlsx", "pptx",
             "png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp":
            return .strong
        case "m4a", "aac", "mp3", "wav", "wave", "aiff", "aif", "caf", "mp4", "m4v", "mov":
            return .transcriptOnly
        case "doc", "xls", "ppt", "pages", "numbers", "key":
            return .convertFirst
        case "xml", "jsonc", "html", "htm", "yaml", "yml", "css", "scss", "sass", "less",
             "sql", "sh", "bash", "zsh", "fish",
             "swift", "py", "pyw", "pyx", "js", "mjs", "cjs", "ts", "tsx", "java", "class",
             "cpp", "cc", "cxx", "c++", "c", "h", "m", "mm", "go", "rs", "rb", "php",
             "kt", "kts", "scala", "clj", "ex", "exs", "elm", "hs", "lua", "pl", "r", "dart", "vim",
             "avi", "mkv", "webm":
            return .experimental
        default:
            return .experimental
        }
    }
}

#if DEBUG
    #Preview {
        let containerService = ContainerService()
        let billingService = PreviewBillingService()
        let entitlementStore = EntitlementStore(billingService: billingService)
        let ragService = RAGService(containerService: containerService, entitlementStore: entitlementStore)
        let settingsStore = SettingsStore(ragService: ragService)
        DocumentLibraryView(ragService: ragService, containerService: containerService)
            .environmentObject(OnboardingStateStore())
            .environmentObject(entitlementStore)
            .environmentObject(settingsStore)
    }

    @MainActor
    private final class PreviewBillingService: BillingService {
        let events: AsyncStream<BillingEvent>

        init() {
            events = AsyncStream { continuation in
                continuation.finish()
            }
        }

        func refreshProducts() async {}

        func purchase(_: BillingProduct) async throws -> StoreKit.Transaction? { nil }

        func restorePurchases() async {}
    }
#endif

/// Swipe a document to delete it, where a scroll view's rows can carry swipe actions: iOS and macOS 27, with
/// `SwipeActionsContainerOn27` on the list (5.7).
struct DocumentSwipeToDelete: ViewModifier {
    let delete: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 27.0, macOS 27.0, *) {
            content.swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive, action: delete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        } else {
            content
        }
    }
}

/// Lets a scroll view's rows carry swipe actions, one row open at a time, the way a List's rows do
/// (`swipeActionsContainer()`, iOS and macOS 27; developer.apple.com, read 2026-10-15).
struct SwipeActionsContainerOn27: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 27.0, macOS 27.0, *) {
            content.swipeActionsContainer()
        } else {
            content
        }
    }
}
