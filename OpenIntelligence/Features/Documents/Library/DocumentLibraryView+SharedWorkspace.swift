//
//  DocumentLibraryView+SharedWorkspace.swift
//  OpenIntelligence
//
//  Part of DocumentLibraryView, moved from DocumentLibraryView.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import AppIntents
import StoreKit
import SwiftUI
import UniformTypeIdentifiers

extension DocumentLibraryView {
    @ViewBuilder
    var sharedWorkspaceBanner: some View {
        if let bootstrapConflict = workspaceSyncService.pendingBootstrapConflict,
           hasConfiguredICloudLibraries {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack(spacing: DSSpacing.sm) {
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
                            .frame(maxWidth: .infinity, minHeight: DSSpacing.tapTarget)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRefreshingSharedWorkspace)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: DSSpacing.sm) {
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
                                    .frame(maxWidth: .infinity, minHeight: DSSpacing.tapTarget)
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
                                    .frame(maxWidth: .infinity, minHeight: DSSpacing.tapTarget)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRefreshingSharedWorkspace)
                        }

                        VStack(spacing: DSSpacing.sm) {
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
                                    .frame(maxWidth: .infinity, minHeight: DSSpacing.tapTarget)
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
                                    .frame(maxWidth: .infinity, minHeight: DSSpacing.tapTarget)
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
            .padding(DSSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .fill(DSColors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.16), lineWidth: 1)
            )
        } else if shouldShowCompactSharedWorkspaceBanner {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: compactSharedWorkspaceBannerIcon)
                        .font(.subheadline)
                        .foregroundStyle(compactSharedWorkspaceBannerIconColor)

                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text(compactSharedWorkspaceBannerTitle)
                            .font(.subheadline.weight(.semibold))
                        Text(compactSharedWorkspaceSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    Text(compactSharedWorkspaceModeLabel)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, DSSpacing.sm)
                        .padding(.vertical, DSSpacing.xs)
                        .background(compactSharedWorkspaceModeColor.opacity(0.15))
                        .foregroundStyle(compactSharedWorkspaceModeColor)
                        .clipShape(Capsule())
                }

                if let detail = compactSharedWorkspaceDetail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(compactSharedWorkspaceDetailColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(DSSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .fill(DSColors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .stroke(compactSharedWorkspaceBannerIconColor.opacity(0.16), lineWidth: 1)
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

    private var isDisplayingLocalTransitionMessage: Bool {
        sharedWorkspaceRefreshMessage?.contains("is now Local Only") == true
    }

    private var compactSharedWorkspaceBannerTitle: String {
        isDisplayingLocalTransitionMessage ? "Library Storage" : "iCloud Libraries"
    }

    private var compactSharedWorkspaceBannerIcon: String {
        if isDisplayingLocalTransitionMessage {
            return "folder.fill"
        }
        return workspaceSyncService.isUsingSharedWorkspace ? "icloud.fill" : "icloud"
    }

    private var compactSharedWorkspaceBannerIconColor: Color {
        if isDisplayingLocalTransitionMessage {
            return .accentColor
        }
        return workspaceSyncService.isUsingSharedWorkspace ? .green : .accentColor
    }

    private var compactSharedWorkspaceModeLabel: String {
        if isDisplayingLocalTransitionMessage {
            return "Local Only"
        }
        return sharedWorkspaceModeLabel
    }

    private var compactSharedWorkspaceModeColor: Color {
        if isDisplayingLocalTransitionMessage {
            return .secondary
        }
        return sharedWorkspaceModeColor
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
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @MainActor
    func resolvePendingBootstrap(_ choice: WorkspaceSyncService.BootstrapChoice) {
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
    func refreshSharedWorkspaceNow() {
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
    func autoRefreshSharedWorkspaceIfNeeded() async {
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
    func handleObservedSharedWorkspaceChange() async {
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

}
