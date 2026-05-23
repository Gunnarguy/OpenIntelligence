//
//  DocumentLibraryView.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import StoreKit
import SwiftUI
import UniformTypeIdentifiers

struct DocumentLibraryView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStateStore
    @EnvironmentObject private var entitlementStore: EntitlementStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var workspaceSyncService: WorkspaceSyncService
    @ObservedObject var ragService: RAGService
    @ObservedObject var containerService: ContainerService
    @State private var showingFilePicker = false
    @State private var showingProcessingSummary = false
    @State private var lastProcessedSummary: ProcessingSummary?
    @State private var showingContainerSettings = false
    @State private var showingSemanticSearch = false
    @State private var isImportingSamples = false
    @State private var sampleImportError: String?
    @State private var sampleImportStatusMessage: String?
    @State private var showingPlanSheet = false
    @State private var activePaywallEntryPoint: PlanUpgradeEntryPoint = .documents

    // New library naming
    @State private var showingNewLibraryPrompt = false
    @State private var showingNewLibraryStorageChoice = false
    @State private var newLibraryName = ""
    @State private var pendingNewLibraryName = ""

    // Delete library confirmation
    @State private var showingDeleteConfirmation = false
    @State private var libraryToDelete: KnowledgeContainer?
    @State private var showingClearAllConfirmation = false

    // Vision Capture and Cached Docs
    @State private var showVisionCapture = false
    @State private var showCachedDocs = false
    @State private var pendingImportURLs: [URL] = []
    @State private var pendingImportReview: DocumentImportReview?
    @State private var showingImportReview = false
    @State private var isRefreshingSharedWorkspace = false
    @State private var sharedWorkspaceRefreshMessage: String?
    @State private var showingSharedSyncReviewDialog = false

    private static let sharedWorkspaceRelativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    let onViewVisualizations: (() -> Void)?

    private var documentLimit: Int { entitlementStore.documentLimit }
    private var isAtDocumentLimit: Bool {
        ragService.documents.count >= documentLimit
    }

    private var libraryLimit: Int { entitlementStore.libraryLimit }
    private var shouldShowQuotaBanner: Bool {
        !entitlementStore.hasUnlimitedDocuments
    }

    init(ragService: RAGService, containerService: ContainerService, onViewVisualizations: (() -> Void)? = nil) {
        _ragService = ObservedObject(wrappedValue: ragService)
        _containerService = ObservedObject(wrappedValue: containerService)
        self.onViewVisualizations = onViewVisualizations
    }

    private var filteredDocuments: [Document] {
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

    private var filteredTotalChunks: Int {
        filteredDocuments.reduce(0) { $0 + $1.totalChunks }
    }

    private var iCloudLibraryCount: Int {
        containerService.containers.filter { $0.syncMode == .iCloudShared }.count
    }

    private var hasConfiguredICloudLibraries: Bool {
        iCloudLibraryCount > 0
    }

    private var localOnlyLibraryCount: Int {
        max(containerService.containers.count - iCloudLibraryCount, 0)
    }

    private var activeLibrary: KnowledgeContainer? {
        containerService.activeContainer
    }

    private var hasICloudSyncAccess: Bool {
        entitlementStore.effectiveTier.isAtLeast(.pro)
    }

    private var pendingSharedSyncConflict: WorkspaceSyncService.PendingBootstrapConflict? {
        workspaceSyncService.pendingBootstrapConflict
    }

    private var isDeletionOnlySharedConflict: Bool {
        guard let conflict = pendingSharedSyncConflict else { return false }
        return !conflict.localOnlyLibraryNames.isEmpty && conflict.sharedOnlyLibraryNames.isEmpty
    }

    private var isAdditionOnlySharedConflict: Bool {
        guard let conflict = pendingSharedSyncConflict else { return false }
        return conflict.localOnlyLibraryNames.isEmpty && !conflict.sharedOnlyLibraryNames.isEmpty
    }

    private var sharedSyncReviewTitle: String {
        if isDeletionOnlySharedConflict {
            return "Libraries were removed from iCloud"
        }

        if isAdditionOnlySharedConflict {
            return "New iCloud libraries are available"
        }

        return "Review iCloud library changes"
    }

    private var sharedSyncReviewMessage: String {
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

    private var emptyStateView: some View {
        VStack(spacing: 0) {
            // Fixed header section
            VStack(spacing: 12) {
                documentHeader
            }

            // Expandable content section
            EmptyDocumentsView(
                isImportingSamples: isImportingSamples,
                hasImportedSamples: onboardingStore.hasImportedSamples,
                isAtDocumentLimit: isAtDocumentLimit,
                documentLimit: documentLimit,
                statusMessage: sampleImportStatusMessage,
                onImportSamples: importSampleWorkspace,
                onPickFiles: presentDocumentPickerOrUpgrade
            )
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var documentListView: some View {
        VStack(spacing: 12) {
            documentHeader

            // Document list with modern styling
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredDocuments) { document in
                        NavigationLink(destination: DocumentDetailsView(
                            document: document,
                            embeddingProviderId: containerService.activeContainer?.embeddingProviderId
                        )) {
                            ModernDocumentCard(document: document, ragService: ragService)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()

                // Stats footer with Auto Intelligence indicator
                StatsFooter(
                    totalDocuments: filteredDocuments.count,
                    totalChunks: filteredTotalChunks,
                    autoIntelligenceEnabled: containerService.activeContainer?.autoAdaptDimension ?? true
                )
                    .padding(.horizontal)
                    .padding(.bottom, 20)
            }
        }
    }

    private var documentHeader: some View {
        VStack(spacing: 12) {
            documentSectionHeader
                .padding(.horizontal)

            documentActionStrip

            ContainerPickerStrip(
                containerService: containerService,
                allowsCreation: true,
                onCreateLibrary: handleNewLibraryTapped,
                onDeleteLibrary: handleDeleteLibrary,
                onSetLibraryStorage: handleSetLibrarySyncMode
            )

            sharedWorkspaceBanner
                .padding(.horizontal)

            if shouldShowQuotaBanner {
                DocumentQuotaBanner(
                    currentCount: ragService.documents.count,
                    limit: documentLimit,
                    tierName: entitlementStore.currentPlanDisplayName,
                    addOnPacks: entitlementStore.addOnPacks,
                    onUpgrade: { presentPlanSheet(for: .quotaBanner) }
                )
                .padding(.horizontal)
            }
        }
    }

    private var syncModeBinding: Binding<LibrarySyncMode> {
        Binding(
            get: {
                activeLibrary?.syncMode ?? .localOnly
            },
            set: { newMode in
                if let activeLibrary {
                    handleSetLibrarySyncMode(activeLibrary, newMode)
                }
            }
        )
    }

    private var documentSectionHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Documents")
                    .font(.headline.weight(.semibold))

                Text(documentSectionSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                if activeLibrary != nil {
                    Picker("Sync Mode", selection: syncModeBinding) {
                        Text("Local").tag(LibrarySyncMode.localOnly)
                        Text("iCloud").tag(LibrarySyncMode.iCloudShared)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    .disabled(isRefreshingSharedWorkspace)
                }

                if hasConfiguredICloudLibraries {
                    Button {
                        refreshSharedWorkspaceNow()
                    } label: {
                        if isRefreshingSharedWorkspace {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                                .frame(width: 28, height: 28)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.accentColor)
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.1))
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshingSharedWorkspace)
                }
            }
        }
    }

    private var documentSectionSubtitle: String {
        if let activeLibrary {
            let documentLabel = filteredDocuments.count == 1 ? "document" : "documents"
            return "\(filteredDocuments.count) \(documentLabel) in \(activeLibrary.name)"
        }

        let documentLabel = ragService.documents.count == 1 ? "document" : "documents"
        return "\(ragService.documents.count) \(documentLabel) in this workspace"
    }

    private var documentActionStrip: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: .infinity), spacing: 8)], spacing: 8) {
            DocumentActionChip(
                title: "Add Document",
                systemImage: "plus"
            ) {
                presentDocumentPickerOrUpgrade()
            }

            DocumentActionChip(
                title: "Cached Docs",
                systemImage: "doc.on.doc"
            ) {
                showCachedDocs = true
            }

            DocumentActionChip(
                title: "Manage Library",
                systemImage: "gearshape"
            ) {
                showingContainerSettings = true
            }

            DocumentActionChip(
                title: "Semantic Search",
                systemImage: "text.magnifyingglass",
                isEnabled: !ragService.documents.isEmpty
            ) {
                showingSemanticSearch = true
            }

            DocumentActionChip(
                title: "Visualize",
                systemImage: "cube.transparent",
                isEnabled: !filteredDocuments.isEmpty && onViewVisualizations != nil
            ) {
                onViewVisualizations?()
            }

            DocumentActionChip(
                title: activeLibrary?.syncMode == .iCloudShared ? "Remove Local Copies" : "Clear All",
                systemImage: "trash",
                tint: .red,
                isEnabled: !ragService.documents.isEmpty
            ) {
                showingClearAllConfirmation = true
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var sharedWorkspaceBanner: some View {
        if let bootstrapConflict = workspaceSyncService.pendingBootstrapConflict,
           hasConfiguredICloudLibraries {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "icloud.trianglebadge.exclamationmark")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)

                    Text(
                        !bootstrapConflict.localOnlyLibraryNames.isEmpty && bootstrapConflict.sharedOnlyLibraryNames.isEmpty
                            ? "Libraries were removed from iCloud"
                            : (bootstrapConflict.localOnlyLibraryNames.isEmpty && !bootstrapConflict.sharedOnlyLibraryNames.isEmpty
                                ? "New iCloud libraries are available"
                                : "Review iCloud library changes")
                    )
                        .font(.subheadline.weight(.semibold))

                    Spacer()
                }

                Text(
                    !bootstrapConflict.localOnlyLibraryNames.isEmpty && bootstrapConflict.sharedOnlyLibraryNames.isEmpty
                        ? "These libraries still exist on this device, but they no longer exist in iCloud."
                        : (bootstrapConflict.localOnlyLibraryNames.isEmpty && !bootstrapConflict.sharedOnlyLibraryNames.isEmpty
                            ? "iCloud has libraries that are not on this device yet."
                            : "This device currently has \(bootstrapConflict.localLibraryCount) libraries marked iCloud Sync / \(bootstrapConflict.localDocumentCount) docs, and iCloud already has \(bootstrapConflict.sharedLibraryCount) shared librar\(bootstrapConflict.sharedLibraryCount == 1 ? "y" : "ies") / \(bootstrapConflict.sharedDocumentCount) docs.")
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if !bootstrapConflict.localOnlyLibraryNames.isEmpty {
                    Text("Only on this device: \(bootstrapConflict.localOnlyLibraryNames.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !bootstrapConflict.sharedOnlyLibraryNames.isEmpty {
                    Text("Only in iCloud: \(bootstrapConflict.sharedOnlyLibraryNames.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if bootstrapConflict.localOnlyLibraryNames.isEmpty && !bootstrapConflict.sharedOnlyLibraryNames.isEmpty {
                    Button {
                        resolvePendingBootstrap(.useICloudWorkspace)
                    } label: {
                        Text("Add iCloud Libraries Here")
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.9)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRefreshingSharedWorkspace)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            Button {
                                resolvePendingBootstrap(.mergeLibraries)
                            } label: {
                                Text(
                                    !bootstrapConflict.localOnlyLibraryNames.isEmpty && bootstrapConflict.sharedOnlyLibraryNames.isEmpty
                                        ? "Restore These to iCloud"
                                        : "Sync Both Directions"
                                )
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.9)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRefreshingSharedWorkspace)

                            Button {
                                resolvePendingBootstrap(.useICloudWorkspace)
                            } label: {
                                Text(
                                    !bootstrapConflict.localOnlyLibraryNames.isEmpty && bootstrapConflict.sharedOnlyLibraryNames.isEmpty
                                        ? "Keep Them Local Here"
                                        : "Use iCloud State Here"
                                )
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.9)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRefreshingSharedWorkspace)
                        }

                        VStack(spacing: 10) {
                            Button {
                                resolvePendingBootstrap(.mergeLibraries)
                            } label: {
                                Text(
                                    !bootstrapConflict.localOnlyLibraryNames.isEmpty && bootstrapConflict.sharedOnlyLibraryNames.isEmpty
                                        ? "Restore These to iCloud"
                                        : "Sync Both Directions"
                                )
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.9)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRefreshingSharedWorkspace)

                            Button {
                                resolvePendingBootstrap(.useICloudWorkspace)
                            } label: {
                                Text(
                                    !bootstrapConflict.localOnlyLibraryNames.isEmpty && bootstrapConflict.sharedOnlyLibraryNames.isEmpty
                                        ? "Keep Them Local Here"
                                        : "Use iCloud State Here"
                                )
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.9)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRefreshingSharedWorkspace)
                        }
                    }
                }

                Text(
                    !bootstrapConflict.localOnlyLibraryNames.isEmpty && bootstrapConflict.sharedOnlyLibraryNames.isEmpty
                        ? "Restore These to iCloud puts the deleted libraries back into iCloud. Keep Them Local Here removes their iCloud status on this device and leaves them stored locally."
                        : (bootstrapConflict.localOnlyLibraryNames.isEmpty && !bootstrapConflict.sharedOnlyLibraryNames.isEmpty
                            ? "Add iCloud Libraries Here pulls the libraries listed as only in iCloud onto this device."
                            : "Sync Both Directions publishes libraries listed as only on this device and pulls in libraries listed as only in iCloud. Use iCloud State Here keeps the iCloud libraries here and demotes unmatched device-only iCloud libraries to Local Only.")
                )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(DSColors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.accentColor.opacity(0.16), lineWidth: 1)
            )
        } else if shouldShowCompactSharedWorkspaceBanner {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: workspaceSyncService.isUsingSharedWorkspace ? "icloud.fill" : "icloud")
                        .font(.subheadline)
                        .foregroundStyle(workspaceSyncService.isUsingSharedWorkspace ? .green : .accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("iCloud Libraries")
                            .font(.subheadline.weight(.semibold))
                        Text(compactSharedWorkspaceSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    Text(sharedWorkspaceModeLabel)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(sharedWorkspaceModeColor.opacity(0.15))
                        .foregroundStyle(sharedWorkspaceModeColor)
                        .clipShape(Capsule())
                }

                if let detail = compactSharedWorkspaceDetail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(compactSharedWorkspaceDetailColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(DSColors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke((workspaceSyncService.isUsingSharedWorkspace ? Color.green : Color.accentColor).opacity(0.16), lineWidth: 1)
            )
        }
    }

    private var shouldShowCompactSharedWorkspaceBanner: Bool {
        workspaceSyncService.isUsingSharedWorkspace
            || hasConfiguredICloudLibraries
            || workspaceSyncService.syncCompatibilityMessage != nil
            || workspaceSyncService.lastErrorMessage != nil
            || sharedWorkspaceRefreshMessage != nil
    }

    private var compactSharedWorkspaceSummary: String {
        if hasConfiguredICloudLibraries {
            return "\(iCloudLibraryCount) iCloud • \(localOnlyLibraryCount) local"
        }

        return "No iCloud libraries configured"
    }

    private var compactSharedWorkspaceDetail: String? {
        if let compatibilityMessage = workspaceSyncService.syncCompatibilityMessage {
            return compatibilityMessage
        }

        if let lastErrorMessage = workspaceSyncService.lastErrorMessage {
            return lastErrorMessage
        }

        if let sharedWorkspaceRefreshMessage {
            return sharedWorkspaceRefreshMessage
        }

        if let syncActivitySummary {
            return syncActivitySummary
        }

        if hasConfiguredICloudLibraries || workspaceSyncService.isUsingSharedWorkspace {
            return workspaceSyncService.statusMessage
        }

        return nil
    }

    private var compactSharedWorkspaceDetailColor: Color {
        if workspaceSyncService.syncCompatibilityMessage != nil || workspaceSyncService.lastErrorMessage != nil {
            return .orange
        }

        return .secondary
    }

    private var workspaceSyncHeadline: String {
        if workspaceSyncService.isUsingSharedWorkspace {
            return "iCloud Sync is the shared copy for libraries marked iCloud Sync. There is no main device."
        }

        if hasConfiguredICloudLibraries {
            if workspaceSyncService.requiresBootstrapDecision {
                return "Choose whether to combine this device's iCloud libraries with the ones already in iCloud. Local Only libraries are not affected."
            }

            if workspaceSyncService.syncCompatibilityMessage != nil {
                return "At least one iCloud library needs the Standard Vector Store before it can sync."
            }

            if workspaceSyncService.lastErrorMessage != nil {
                return "This device has iCloud libraries configured, but iCloud Sync is not active yet."
            }

            return "Preparing your iCloud libraries for sync."
        }

        return "Local Only means the library stays on this device until you explicitly choose iCloud Sync as the shared copy."
    }

    private var sharedWorkspaceSummary: String {
        if hasConfiguredICloudLibraries {
            return "\(iCloudLibraryCount) iCloud • \(localOnlyLibraryCount) local. Libraries marked iCloud Sync use iCloud as the shared copy. Local Only libraries stay on just this device."
        }

        return "All libraries are Local Only right now. Turn iCloud Sync on per library when you want it on another device."
    }

    private var sharedWorkspaceModeLabel: String {
        if workspaceSyncService.isUsingSharedWorkspace {
            return "iCloud Sync"
        }

        if !hasConfiguredICloudLibraries {
            return "Local Only"
        }

        if workspaceSyncService.requiresBootstrapDecision {
            return "Choose"
        }

        if workspaceSyncService.syncCompatibilityMessage != nil {
            return "Unsupported"
        }

        if workspaceSyncService.lastErrorMessage != nil {
            return "Unavailable"
        }

        return "Preparing"
    }

    private var sharedWorkspaceModeColor: Color {
        if workspaceSyncService.isUsingSharedWorkspace {
            return .green
        }

        if !hasConfiguredICloudLibraries {
            return .secondary
        }

        if workspaceSyncService.requiresBootstrapDecision {
            return .accentColor
        }

        if workspaceSyncService.syncCompatibilityMessage != nil || workspaceSyncService.lastErrorMessage != nil {
            return .orange
        }

        return .accentColor
    }

    private var syncActivitySummary: String? {
        if let lastSuccessfulSyncAt = workspaceSyncService.lastSuccessfulSyncAt {
            let relativeDescription = Self.sharedWorkspaceRelativeFormatter.localizedString(
                for: lastSuccessfulSyncAt,
                relativeTo: Date()
            )
            return "Last synced \(relativeDescription)."
        }

          guard hasConfiguredICloudLibraries,
              let lastSyncAttemptAt = workspaceSyncService.lastSyncAttemptAt
        else {
            return nil
        }

        let relativeDescription = Self.sharedWorkspaceRelativeFormatter.localizedString(
            for: lastSyncAttemptAt,
            relativeTo: Date()
        )
        return "Last checked \(relativeDescription)."
    }

    @ViewBuilder
    private func syncBenefitRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @MainActor
    private func resolvePendingBootstrap(_ choice: WorkspaceSyncService.BootstrapChoice) {
        guard hasICloudSyncAccess else {
            presentPlanSheet(for: .iCloudSync)
            return
        }

        Task { @MainActor in
            guard !isRefreshingSharedWorkspace else { return }
            isRefreshingSharedWorkspace = true
            sharedWorkspaceRefreshMessage = nil
            defer { isRefreshingSharedWorkspace = false }

            _ = await workspaceSyncService.resolvePendingBootstrap(using: choice)

            guard workspaceSyncService.isUsingSharedWorkspace else {
                sharedWorkspaceRefreshMessage = workspaceSyncService.lastErrorMessage ?? workspaceSyncService.statusMessage
                return
            }

            containerService.reloadFromDisk()
            ragService.reloadWorkspaceData()
            sharedWorkspaceRefreshMessage = choice == .mergeLibraries
                ? "This device's iCloud-marked libraries were shared to iCloud, and iCloud libraries were pulled in here."
                : "Libraries already in iCloud were added here. Any unmatched iCloud-marked libraries on this device were kept as Local Only."
        }
    }

    @MainActor
    private func refreshSharedWorkspaceNow() {
        guard hasICloudSyncAccess else {
            presentPlanSheet(for: .iCloudSync)
            return
        }

        Task { @MainActor in
            await performSharedWorkspaceRefresh(isManual: true)
        }
    }

    @MainActor
    private func connectExistingICloudLibraries() {
        guard hasICloudSyncAccess else {
            presentPlanSheet(for: .iCloudSync)
            return
        }

        Task { @MainActor in
            guard !isRefreshingSharedWorkspace else { return }
            isRefreshingSharedWorkspace = true
            sharedWorkspaceRefreshMessage = nil
            defer { isRefreshingSharedWorkspace = false }

            _ = await workspaceSyncService.connectExistingICloudLibraries()

            guard workspaceSyncService.isUsingSharedWorkspace else {
                sharedWorkspaceRefreshMessage = workspaceSyncService.lastErrorMessage ?? workspaceSyncService.statusMessage
                return
            }

            containerService.reloadFromDisk()
            ragService.reloadWorkspaceData()
            sharedWorkspaceRefreshMessage = "Existing iCloud libraries were connected to this device."
        }
    }

    @MainActor
    private func autoRefreshSharedWorkspaceIfNeeded() async {
        guard hasConfiguredICloudLibraries else { return }
        guard !isRefreshingSharedWorkspace else { return }

        let minimumRefreshInterval: TimeInterval = 15
        if let lastSyncAttemptAt = workspaceSyncService.lastSyncAttemptAt,
           Date().timeIntervalSince(lastSyncAttemptAt) < minimumRefreshInterval {
            return
        }

        await performSharedWorkspaceRefresh(isManual: false)
    }

    @MainActor
    private func handleObservedSharedWorkspaceChange() async {
        guard hasConfiguredICloudLibraries else { return }
        await performSharedWorkspaceRefresh(isManual: false)
    }

    @MainActor
    private func performSharedWorkspaceRefresh(isManual: Bool) async {
        guard hasConfiguredICloudLibraries else { return }
        guard !isRefreshingSharedWorkspace else { return }

        isRefreshingSharedWorkspace = true
        if isManual {
            sharedWorkspaceRefreshMessage = nil
        }

        defer { isRefreshingSharedWorkspace = false }

        _ = await workspaceSyncService.reconfigureIfNeeded()

        guard workspaceSyncService.isUsingSharedWorkspace else {
            presentSharedSyncReviewIfNeeded()
            if isManual {
                sharedWorkspaceRefreshMessage = workspaceSyncService.pendingBootstrapConflict != nil
                    ? workspaceSyncService.statusMessage
                    : (workspaceSyncService.lastErrorMessage ?? "Shared workspace is still unavailable on this device.")
            }
            return
        }

        let hasActiveIngestion = ragService.ingestionItems.contains { !$0.stage.isTerminal }
        guard !hasActiveIngestion else {
            if isManual {
                sharedWorkspaceRefreshMessage = "Finish the current import before reloading iCloud Sync."
            }
            return
        }

        containerService.reloadFromDisk()
        ragService.reloadWorkspaceData()

        if isManual {
            sharedWorkspaceRefreshMessage = "Shared workspace reloaded from iCloud Sync."
        }
    }

    @MainActor
    private func presentSharedSyncReviewIfNeeded() {
        showingSharedSyncReviewDialog = pendingSharedSyncConflict != nil
    }

    var body: some View {
        libraryAlertView
    }

    private var libraryAlertView: some View {
        librarySheetView
            .alert("Sample Import Failed", isPresented: sampleImportErrorBinding) {
                Button("OK", role: .cancel) { sampleImportError = nil }
            } message: {
                if let message = sampleImportError {
                    Text(message)
                }
            }
            .alert("Error Processing Document", isPresented: ragServiceErrorBinding) {
                Button("OK", role: .cancel) {
                    ragService.lastError = nil
                }
            } message: {
                if let error = ragService.lastError {
                    Text(error)
                }
            }
            .alert("Billing Error", isPresented: entitlementErrorBinding) {
                Button("OK", role: .cancel) {
                    Task { @MainActor in
                        entitlementStore.lastError = nil
                    }
                }
            } message: {
                if let error = entitlementStore.lastError {
                    Text(error)
                }
            }
            .alert("New Library", isPresented: $showingNewLibraryPrompt) {
                TextField("Library name", text: $newLibraryName)
                Button("Cancel", role: .cancel) {
                    newLibraryName = ""
                    pendingNewLibraryName = ""
                }
                Button("Create") {
                    pendingNewLibraryName = newLibraryName.trimmingCharacters(in: .whitespacesAndNewlines)
                    showingNewLibraryStorageChoice = true
                }
            } message: {
                Text("Enter a name for your new library")
            }
            .confirmationDialog("Choose Library Storage", isPresented: $showingNewLibraryStorageChoice, titleVisibility: .visible) {
                Button("Local Only") {
                    createNewLibrary(syncMode: .localOnly)
                }
                Button("iCloud Sync") {
                    createNewLibrary(syncMode: .iCloudShared)
                }
                Button("Cancel", role: .cancel) {
                    pendingNewLibraryName = ""
                }
            } message: {
                Text("Local Only keeps the library only on this device. iCloud Sync makes iCloud the shared copy for that library across your devices.")
            }
            .alert("Delete Library?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    libraryToDelete = nil
                }
                if libraryToDelete?.syncMode == .iCloudShared {
                    Button("Delete from iCloud", role: .destructive) {
                        confirmDeleteLibrary()
                    }
                } else {
                    Button("Delete Locally", role: .destructive) {
                        confirmDeleteLibrary()
                    }
                }
            } message: {
                if let lib = libraryToDelete {
                    let docCount = ragService.documents.filter { $0.containerId == lib.id }.count
                    if lib.syncMode == .iCloudShared {
                        Text("This will permanently delete \"\(lib.name)\" from iCloud Sync and remove it from every device using that shared library, along with all \(docCount) document\(docCount == 1 ? "" : "s"). This cannot be undone.")
                    } else {
                        Text("This will permanently delete \"\(lib.name)\" only on this device, along with all \(docCount) document\(docCount == 1 ? "" : "s") inside it. This cannot be undone.")
                    }
                } else {
                    Text("This will permanently delete this library and all documents inside it.")
                }
            }
            .alert(activeLibrary?.syncMode == .iCloudShared ? "Remove Local Documents?" : "Clear Library?", isPresented: $showingClearAllConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button(activeLibrary?.syncMode == .iCloudShared ? "Remove Local Copies" : "Clear All", role: .destructive) {
                    Task {
                        try? await ragService.clearAllDocuments()
                    }
                }
            } message: {
                if let activeLibrary {
                    if activeLibrary.syncMode == .iCloudShared {
                        Text("This removes the documents currently stored on this device for \"\(activeLibrary.name)\". If those documents still exist in iCloud Sync, Sync Now can bring them back.")
                    } else {
                        Text("This permanently deletes every document in \"\(activeLibrary.name)\" on this device. This cannot be undone.")
                    }
                } else {
                    Text("This will remove all documents in the current library.")
                }
            }
            .alert("Review Import", isPresented: $showingImportReview) {
                Button("Cancel", role: .cancel) {
                    discardPendingImportFiles()
                    pendingImportReview = nil
                }
                Button("Import Anyway") {
                    confirmPendingImport()
                }
            } message: {
                if let review = pendingImportReview {
                    Text(review.message)
                }
            }
            .confirmationDialog(sharedSyncReviewTitle, isPresented: $showingSharedSyncReviewDialog, titleVisibility: .visible) {
                if isDeletionOnlySharedConflict, let conflict = pendingSharedSyncConflict {
                    Button("Delete Here Too", role: .destructive) {
                        deleteConflictedLocalLibraries(conflict)
                    }

                    Button("Keep Them Local Here") {
                        resolvePendingBootstrap(.useICloudWorkspace)
                    }

                    Button("Restore Them to iCloud") {
                        resolvePendingBootstrap(.mergeLibraries)
                    }
                } else if isAdditionOnlySharedConflict {
                    Button("Add iCloud Libraries Here") {
                        resolvePendingBootstrap(.useICloudWorkspace)
                    }
                } else {
                    Button("Sync Both Directions") {
                        resolvePendingBootstrap(.mergeLibraries)
                    }

                    Button("Use iCloud State Here") {
                        resolvePendingBootstrap(.useICloudWorkspace)
                    }
                }

                Button("Not Now", role: .cancel) {}
            } message: {
                Text(sharedSyncReviewMessage)
            }
            .userActivity("com.openintelligence.documents") { activity in
                activity.title = "Browse Document Library"
                activity.isEligibleForSearch = true
                activity.isEligibleForHandoff = true
                if let containerId = containerService.activeContainerId as UUID? {
                    activity.userInfo = ["containerId": containerId]
                }
            }
    }

    private var librarySheetView: some View {
        libraryChromeView
            .sheet(isPresented: $showingFilePicker) {
                DocumentPicker { urls in
                    reviewAndEnqueueDocuments(urls)
                }
            }
            .sheet(isPresented: $showingContainerSettings) {
                ContainerSettingsSheet(containerService: containerService, ragService: ragService)
            }
            .sheet(isPresented: $showingSemanticSearch) {
                SemanticSearchView(
                    ragService: ragService,
                    containerService: containerService
                )
            }
            .sheet(isPresented: $showingPlanSheet) {
                PlanUpgradeSheet(entryPoint: activePaywallEntryPoint)
                    .environmentObject(entitlementStore)
            }
            .sheet(isPresented: $showCachedDocs) {
                CachedDocsView(ragService: ragService)
            }
    }

    private var libraryChromeView: some View {
        libraryContentView
            .navigationTitle("Documents")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .onAppear {
                Task { @MainActor in
                    await autoRefreshSharedWorkspaceIfNeeded()
                }
            }
            .onChange(of: workspaceSyncService.observedWorkspaceChangeCount) {
                Task { @MainActor in
                    await handleObservedSharedWorkspaceChange()
                }
            }
            .overlay(alignment: .bottomTrailing) {
                IngestionQueueOverlay(
                    items: ragService.ingestionItems,
                    onCancelItem: { ragService.cancelIngestionItem($0) },
                    onCancelAll: { ragService.cancelAllIngestion() }
                )
                .padding(.trailing, 16)
                .padding(.bottom, 16)
            }
    }

    private var libraryContentView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    DSColors.background,
                    DSColors.surface.opacity(0.3),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if filteredDocuments.isEmpty {
                emptyStateView
            } else {
                documentListView
            }

            if settings.showSiliconHUD {
                HardwareXRayOverlay()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    private var sampleImportErrorBinding: Binding<Bool> {
        Binding(
            get: { sampleImportError != nil },
            set: { if !$0 { sampleImportError = nil } }
        )
    }

    private var ragServiceErrorBinding: Binding<Bool> {
        Binding(
            get: { ragService.lastError != nil },
            set: { if !$0 { ragService.lastError = nil } }
        )
    }

    private var entitlementErrorBinding: Binding<Bool> {
        Binding(
            get: { entitlementStore.lastError != nil },
            set: { newValue in
                if !newValue {
                    Task { @MainActor in
                        entitlementStore.lastError = nil
                    }
                }
            }
        )
    }

    /// Launches the file picker if the user still has document quota remaining.
    @MainActor
    private func presentDocumentPickerOrUpgrade() {
        if !entitlementStore.canAddDocument(currentCount: ragService.documents.count) {
            presentPlanSheet(for: .documentLimit)
        } else {
            showingFilePicker = true
        }
    }

    /// Ingests a picked document and unlocks the onboarding step once any content exists.
    private func enqueueDocumentIngestion(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        DSHaptics.drop()  // Files dropped/selected feedback
        ragService.enqueueDocuments(urls)
        Task { @MainActor in
            onboardingStore.markSamplesImported()
        }
    }

    @MainActor
    private func reviewAndEnqueueDocuments(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        let review = DocumentImportReview(urls: urls)
        if review.needsReview {
            pendingImportURLs = urls
            pendingImportReview = review
            showingImportReview = true
            return
        }

        enqueueDocumentIngestion(urls)
    }

    @MainActor
    private func confirmPendingImport() {
        let urls = pendingImportURLs
        pendingImportURLs = []
        pendingImportReview = nil
        enqueueDocumentIngestion(urls)
    }

    @MainActor
    private func discardPendingImportFiles() {
        let fileManager = FileManager.default
        for url in pendingImportURLs {
            try? fileManager.removeItem(at: url)
        }
        pendingImportURLs = []
    }

    /// Imports the curated onboarding workspace so the document list is not empty.
    @MainActor
    private func importSampleWorkspace() {
        guard !isImportingSamples else { return }
        sampleImportError = nil
        sampleImportStatusMessage = nil

        let currentCount = ragService.documents.count
        let sampleCount = SampleDocumentManager.shared.sampleCount
        let remainingSlots = documentLimit - currentCount

        guard remainingSlots > 0 else {
            sampleImportStatusMessage =
                "Current workspace supports up to \(documentLimit) documents. Remove a document or upgrade to import the sample workspace."
            presentPlanSheet(for: .sampleImport)
            return
        }

        guard remainingSlots >= sampleCount else {
            let needed = sampleCount - remainingSlots
            sampleImportStatusMessage =
                "Importing the curated workspace requires \(sampleCount) slots, but only \(remainingSlots) remain. Remove \(needed) document\(needed == 1 ? "" : "s") or upgrade to proceed."
            presentPlanSheet(for: .sampleImport)
            return
        }

        isImportingSamples = true

        Task {
            defer { isImportingSamples = false }
            do {
                try await SampleDocumentManager.shared.importSamples(into: ragService)
                onboardingStore.markSamplesImported()
                sampleImportStatusMessage = "Sample workspace imported successfully."
            } catch {
                sampleImportError = "Could not import the sample workspace. Please try again."
            }
        }
    }

    @MainActor
    private func handleNewLibraryTapped() {
        let currentCount = containerService.containers.count
        guard entitlementStore.canAddLibrary(currentCount: currentCount) else {
            presentPlanSheet(for: .libraryCreation)
            return
        }

        // Suggest a default name but let user customize
        newLibraryName = "Library \(currentCount + 1)"
        pendingNewLibraryName = ""
        showingNewLibraryPrompt = true
    }

    @MainActor
    private func createNewLibrary(syncMode: LibrarySyncMode) {
        if syncMode == .iCloudShared, !hasICloudSyncAccess {
            pendingNewLibraryName = ""
            presentPlanSheet(for: .iCloudSync)
            return
        }

        let trimmedName = pendingNewLibraryName.isEmpty
            ? newLibraryName.trimmingCharacters(in: .whitespacesAndNewlines)
            : pendingNewLibraryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let libraryName = trimmedName.isEmpty ? "Library \(containerService.containers.count + 1)" : trimmedName

        let embeddingService = EmbeddingService.forProvider(
            id: settings.defaultEmbeddingProvider,
            allowFallback: true
        )

        let newContainer: KnowledgeContainer
        do {
            newContainer = try containerService.createContainer(
                name: libraryName,
                embeddingProviderId: embeddingService.actualProviderId,
                embeddingDim: embeddingService.outputDimension,
                syncMode: syncMode
            )
        } catch is LibraryQuotaError {
            pendingNewLibraryName = ""
            presentPlanSheet(for: .libraryCreation)
            return
        } catch {
            pendingNewLibraryName = ""
            return
        }

        containerService.setActive(newContainer.id)
        newLibraryName = "" // Reset for next time
        pendingNewLibraryName = ""

        if syncMode == .iCloudShared {
            Task { @MainActor in
                await publishExplicitICloudOptIn(libraryName: newContainer.name)
            }
        }
    }

    @MainActor
    private func handleSetLibrarySyncMode(_ container: KnowledgeContainer, _ syncMode: LibrarySyncMode) {
        guard container.syncMode != syncMode else { return }

        if syncMode == .iCloudShared, !hasICloudSyncAccess {
            presentPlanSheet(for: .iCloudSync)
            return
        }

        var updatedContainer = container
        updatedContainer.syncMode = syncMode
        containerService.updateContainer(updatedContainer)

        Task { @MainActor in
            if syncMode == .iCloudShared {
                await publishExplicitICloudOptIn(libraryName: updatedContainer.name)
            } else {
                isRefreshingSharedWorkspace = true
                defer { isRefreshingSharedWorkspace = false }

                _ = await workspaceSyncService.reconfigureIfNeeded()
                containerService.reloadFromDisk()
                ragService.reloadWorkspaceData()

                sharedWorkspaceRefreshMessage = "\(updatedContainer.name) is now Local Only and stays on this device."
            }
        }
    }

    @MainActor
    private func publishExplicitICloudOptIn(libraryName: String) async {
        guard !isRefreshingSharedWorkspace else { return }

        isRefreshingSharedWorkspace = true
        sharedWorkspaceRefreshMessage = nil
        defer { isRefreshingSharedWorkspace = false }

        _ = await workspaceSyncService.reconfigureForExplicitICloudOptIn()

        containerService.reloadFromDisk()
        ragService.reloadWorkspaceData()

        if workspaceSyncService.isUsingSharedWorkspace {
            sharedWorkspaceRefreshMessage = "\(libraryName) now syncs through iCloud Sync."
        } else {
            sharedWorkspaceRefreshMessage = workspaceSyncService.lastErrorMessage ?? workspaceSyncService.statusMessage
        }
    }

    @MainActor
    private func deleteConflictedLocalLibraries(_ conflict: WorkspaceSyncService.PendingBootstrapConflict) {
        let targetContainerIDs = Set(conflict.localOnlyLibraryIDs)
        guard !targetContainerIDs.isEmpty else { return }

        Task {
            await MainActor.run {
                showingSharedSyncReviewDialog = false
                isRefreshingSharedWorkspace = true
                sharedWorkspaceRefreshMessage = nil
            }

            let docsToRemove = await MainActor.run {
                ragService.documents.filter { document in
                    guard let containerId = document.containerId else { return false }
                    return targetContainerIDs.contains(containerId)
                }
            }

            for doc in docsToRemove {
                try? await ragService.removeDocument(doc)
            }

            await MainActor.run {
                for containerId in targetContainerIDs {
                    containerService.deleteContainer(id: containerId)
                    LibraryVisualizationEngine.shared.invalidateCache(for: containerId)
                }
            }

            for containerId in targetContainerIDs {
                await EntityIndexService.shared.removeContainer(containerId)
            }

            _ = await workspaceSyncService.reconfigureIfNeeded()

            await MainActor.run {
                containerService.reloadFromDisk()
                ragService.reloadWorkspaceData()
                isRefreshingSharedWorkspace = false
                sharedWorkspaceRefreshMessage = targetContainerIDs.count == 1
                    ? "Deleted the library removed from iCloud on this device too."
                    : "Deleted the libraries removed from iCloud on this device too."
            }
        }
    }

    @MainActor
    private func handleDeleteLibrary(_ container: KnowledgeContainer) {
        // Can't delete the last library
        guard containerService.containers.count > 1 else { return }
        libraryToDelete = container
        showingDeleteConfirmation = true
    }

    @MainActor
    private func confirmDeleteLibrary() {
        guard let container = libraryToDelete else { return }

        // Haptic for destructive action
        DSHaptics.delete()
        libraryToDelete = nil

        Task {
            if container.syncMode == .iCloudShared {
                await MainActor.run {
                    isRefreshingSharedWorkspace = true
                    sharedWorkspaceRefreshMessage = nil
                }

                do {
                    try await workspaceSyncService.deleteSharedLibrary(container)
                } catch {
                    await MainActor.run {
                        isRefreshingSharedWorkspace = false
                        sharedWorkspaceRefreshMessage = error.localizedDescription
                    }
                    return
                }
            }

            let localContainerIDsToDelete = await MainActor.run {
                resolvedLocalDeletionContainerIDs(for: container)
            }

            for containerId in localContainerIDsToDelete {
                await ragService.cancelAndPurgeIngestion(for: containerId)
            }

            let docsToRemove = await MainActor.run {
                ragService.documents.filter { document in
                    guard let containerId = document.containerId else { return false }
                    return localContainerIDsToDelete.contains(containerId)
                }
            }

            for doc in docsToRemove {
                try? await ragService.removeDocument(doc)
            }

            await MainActor.run {
                for containerId in localContainerIDsToDelete {
                    containerService.deleteContainer(id: containerId)
                    LibraryVisualizationEngine.shared.invalidateCache(for: containerId)
                }
                containerService.reloadFromDisk()
                ragService.reloadWorkspaceData()
                if container.syncMode == .iCloudShared {
                    isRefreshingSharedWorkspace = false
                    sharedWorkspaceRefreshMessage = "\(container.name) was removed from this device and iCloud Sync."
                }
            }

            for containerId in localContainerIDsToDelete {
                await EntityIndexService.shared.removeContainer(containerId)
            }
        }
    }

    @MainActor
    private func resolvedLocalDeletionContainerIDs(for targetContainer: KnowledgeContainer) -> Set<UUID> {
        let currentContainers = containerService.containers

        if currentContainers.contains(where: { $0.id == targetContainer.id }) {
            return [targetContainer.id]
        }

        guard targetContainer.syncMode == .iCloudShared,
              let targetMergeKey = containerDeletionMergeKey(for: targetContainer)
        else {
            return []
        }

        let matchingIDs = currentContainers.compactMap { container -> UUID? in
            guard container.syncMode == .iCloudShared else { return nil }
            return containerDeletionMergeKey(for: container) == targetMergeKey ? container.id : nil
        }

        return Set(matchingIDs)
    }

    private func containerDeletionMergeKey(for container: KnowledgeContainer) -> String? {
        guard container.syncMode == .iCloudShared else { return nil }

        return container.id.uuidString.lowercased()
    }

    @MainActor
    private func presentPlanSheet(for entryPoint: PlanUpgradeEntryPoint) {
        activePaywallEntryPoint = entryPoint
        showingPlanSheet = true
        TelemetryCenter.emitBillingEvent(
            "Paywall presented",
            metadata: ["entryPoint": entryPoint.analyticsValue]
        )
    }
}

private struct DocumentActionChip: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(isEnabled ? tint : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill((isEnabled ? tint : Color.secondary).opacity(0.1))
                    .overlay(
                        Capsule()
                            .stroke((isEnabled ? tint : Color.secondary).opacity(0.18), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.7)
    }
}

private struct DocumentUtilityChipLabel: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor
    var showsProgress: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
            }

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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

private struct DocumentImportReview {
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
             "docx", "xlsx", "pptx",
             "png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp":
            return .strong
        case "m4a", "aac", "mp3", "wav", "wave", "aiff", "aif", "caf", "mp4", "m4v", "mov":
            return .transcriptOnly
        case "doc", "xls", "ppt", "pages", "numbers", "key":
            return .convertFirst
        case "xml", "json", "jsonc", "html", "htm", "yaml", "yml", "css", "scss", "sass", "less",
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
