//
//  SettingsView+ModelAndCloud.swift
//  OpenIntelligence
//
//  Part of SettingsView, moved from SettingsView.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import AppIntents
import SwiftUI
import TipKit

#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(AppKit)
import AppKit
#endif

extension SettingsView {
    // MARK: - Model Selection Card

    @ViewBuilder
    var modelSelectionCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack {
                Image(systemName: "apple.logo")
                    .foregroundStyle(Color.accentColor)
                Text("Apple Intelligence")
                    .font(.headline)
                Spacer()

                // Availability indicator
                if deviceCapabilities.supportsAppleIntelligence {
                    HStack(spacing: DSSpacing.xs) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Available")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(DSColors.readable(.green))
                    }
                }
            }

            // Model info (not a button since there's only one option)
            HStack {
                Image(systemName: "brain.head.profile.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    // The card's own nickname and tagline ("AFM 3 Ecosystem", "Evidence-first routing ...") with
                    // Technical Details on; plain words otherwise (5.7 UI cleanup).
                    Text(settings.showTechnicalDetails ? settings.selectedModel.capabilityCard.nickname : plainModelName)
                        .font(.subheadline.weight(.medium))
                    Text(settings.showTechnicalDetails ? settings.selectedModel.capabilityCard.tagline : plainModelTagline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(DSSpacing.md)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))

            // Model capabilities
            HStack(spacing: DSSpacing.md) {
                modelCapabilityPill(icon: "text.bubble.fill", label: "Text Generation")
                // The model's name only with Technical Details on (5.7 UI cleanup).
                modelCapabilityPill(icon: "photo.fill", label: settings.showTechnicalDetails ? "ADM 3 Visuals" : "Images")
                modelCapabilityPill(icon: "doc.text.fill", label: settings.showTechnicalDetails ? "RAG-Ready" : "Your documents")
            }
        }
        .padding(DSSpacing.lg)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    @ViewBuilder
    private func modelCapabilityPill(icon: String, label: String) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2)
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .background(Color.accentColor.opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - Private Cloud Compute Card

    @ViewBuilder
    var privateCloudComputeCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            HStack {
                Image(systemName: "cloud.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text("Private Cloud Compute")
                        .font(.headline)
                    // Corrected 2026-10-15: "after you approve each request" is untrue of Allow without asking,
                    // and on iOS and macOS 26 the reason it's off is the system, not the build.
                    Text(deviceCapabilities.supportsPrivateCloudCompute
                        ? "Apple's servers, for the writing step only, with your permission"
                        : DeviceCapabilities.pccRoutingCompiledIn
                            ? "Needs iOS or macOS 27. Every answer is written on this device."
                            : "Not in this build. Every answer is written on this device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                // Status indicator. The live snapshot decides once it has loaded: `supportsPrivateCloudCompute`
                // is only "compiled in and iOS or macOS 27", so the Simulator said Available above a quota line
                // saying Private Cloud Compute is unavailable there (2026-10-15).
                let pccAvailable = pccCapability?.pccAvailable ?? deviceCapabilities.supportsPrivateCloudCompute
                HStack(spacing: DSSpacing.xs) {
                    Circle()
                        .fill(pccAvailable ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(pccAvailable ? "Available" : "Unavailable")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(DSColors.readable(pccAvailable ? .green : .orange))
                }
            }

            // The paragraph this replaces read "Apple's Private Cloud Compute (PCC) allows
            // OpenIntelligence to process complex queries with a massive 32,768 token
            // context window...". Three problems. It framed PCC as the thing that makes
            // the app work, which is backwards: `FoundationModelRoutePolicy` returns
            // `.onDevice` on every branch of the automatic path unless a prompt exceeds
            // the device window. "Massive" is doing work that a number should do. And the
            // 32,768 was hardcoded directly above a block that renders the *live* figure,
            // so the same screen could show two different numbers.
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                // Corrected 2026-10-15: the sentence named only the answer too large for the device.
                // `ModelExecutionPlanner` also sends a Deep Think or Maximum answer drawn from more than one
                // document (`complexityRequestsPCC`), and the model picker's Private Cloud Compute sends every one.
                Text("Answers are written on this device unless Private Cloud Compute is allowed: with Hybrid, for an answer whose passages don't fit in this device's model, or a Deep Think or Maximum answer drawn from more than one document; with Private Cloud Compute chosen in the model picker, for every answer drawn from your documents.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    pccWindowRow(
                        icon: "iphone",
                        label: "On this device",
                        value: onDeviceWindowDescription
                    )
                    Divider().padding(.leading, DSSpacing.xxl)
                    pccWindowRow(
                        icon: "cloud",
                        label: "Private Cloud Compute",
                        value: pccWindowDescription
                    )
                }
                .padding(.vertical, DSSpacing.xs)
                .background(DSColors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))

                HStack {
                    Text("When to allow it")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Picker("When to allow it", selection: $settings.pccSetting) {
                        ForEach(PCCSettings.allCases, id: \.self) { setting in
                            Text(setting.displayName).tag(setting)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!deviceCapabilities.supportsPrivateCloudCompute)
                }

                Text("OpenIntelligence does not operate its own servers. Nothing is sent anywhere else. Reading, indexing and searching your documents all happen here regardless of this setting; only the final answer can ever leave.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                Divider()
                
                // PCC Quota Status
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    HStack(spacing: DSSpacing.sm) {
                        Image(systemName: "chart.bar.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("PCC Quota Status")
                            .font(.subheadline.weight(.medium))
                    }
                    
                    if let capability = pccCapability, capability.pccAvailable {
                        HStack {
                            Text("Status:")
                                .font(.caption)
                            Spacer()
                            Text(capability.pccQuota == .limitReached ? "Limit Reached" : capability.pccQuota.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DSColors.readable(capability.pccQuota == .limitReached ? .red : .green))
                        }
                        if let contextSize = capability.pccContextSize {
                            LabeledContent("Context", value: "\(contextSize) tokens")
                                .font(.caption)
                        }
                    } else if pccCapability == nil {
                        ProgressView("Reading PCC capability…")
                            .font(.caption)
                    } else {
                        Text(pccCapability?.unavailabilityReason ?? "PCC is currently unavailable on this device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, DSSpacing.xs)
                .padding(.top, DSSpacing.xs)
            }
            #endif
        }
        .padding(DSSpacing.lg)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    func refreshPCCCapability() async {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            pccCapability = await LiveFoundationModelCapabilityProvider().snapshot()
        }
        #endif
        TourContext.privateCloudAvailable = pccCapability?.pccAvailable ?? deviceCapabilities.supportsPrivateCloudCompute
    }

    @ViewBuilder
    var sharedWorkspaceCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack {
                Image(systemName: "icloud.and.arrow.up.fill")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text("iCloud Libraries")
                        .font(.headline)
                    Text("Each library chooses Local Only or iCloud Sync")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Text(sharedWorkspaceModeLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.xs)
                    .background(sharedWorkspaceModeColor.opacity(0.15))
                    .foregroundStyle(sharedWorkspaceModeColor)
                    .clipShape(Capsule())
            }

            Text(sharedWorkspaceSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let compatibilityMessage = workspaceSyncService.syncCompatibilityMessage,
               hasConfiguredICloudLibraries {
                Text(compatibilityMessage)
                    .font(.caption)
                    .foregroundStyle(DSColors.readable(.orange))
                    .padding(DSSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let bootstrapConflict = workspaceSyncService.pendingBootstrapConflict,
               hasConfiguredICloudLibraries {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                        Text("Review iCloud library changes")
                        .font(.subheadline.weight(.semibold))

                        Text("Only libraries marked iCloud Sync are involved here. This device currently has \(bootstrapConflict.localLibraryCount) libraries marked iCloud Sync / \(bootstrapConflict.localDocumentCount) documents, and iCloud already has \(bootstrapConflict.sharedLibraryCount) shared librar\(bootstrapConflict.sharedLibraryCount == 1 ? "y" : "ies") / \(bootstrapConflict.sharedDocumentCount) documents.")
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

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: DSSpacing.sm) {
                            Button {
                                resolvePendingBootstrap(.mergeLibraries)
                            } label: {
                                Text("Share Device Libraries to iCloud")
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
                                Text("Add iCloud Libraries Here")
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.9)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRefreshingSharedWorkspace)
                        }

                        VStack(spacing: DSSpacing.sm) {
                            Button {
                                resolvePendingBootstrap(.mergeLibraries)
                            } label: {
                                Text("Share Device Libraries to iCloud")
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
                                Text("Add iCloud Libraries Here")
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.9)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRefreshingSharedWorkspace)
                        }
                    }

                    Text("Share Device Libraries to iCloud publishes the libraries listed as only on this device. Add iCloud Libraries Here pulls in the libraries listed as only in iCloud, while any unmatched iCloud-marked libraries on this device are kept as Local Only so they are not deleted.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(DSSpacing.md)
                .background(Color.accentColor.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
            }

            if !workspaceSyncService.requiresBootstrapDecision {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    Button {
                        openURL(OpenIntelligenceDeepLink.documentsURL)
                    } label: {
                        HStack(spacing: DSSpacing.sm) {
                            Image(systemName: "folder")
                                .font(.caption.weight(.semibold))
                            Text("Manage in Documents")
                                .font(.caption.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)

                    Text("Change Local Only or iCloud Sync per library, and refresh shared libraries, from the Documents screen.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // This was four unlabelled grey paragraphs stacked on each other, followed by
            // a raw container path (/private/var/mobile/Library/Mobile Documents/...)
            // shown to every user. Nothing said which line was status, which was activity,
            // or what the path was for. They are labelled rows now, and the path moved
            // behind a disclosure since it exists for support and debugging rather than
            // for reading.
            VStack(spacing: 0) {
                syncDetailRow(label: "Status", value: workspaceSyncService.statusMessage)

                if let syncActivitySummary {
                    Divider().padding(.leading, DSSpacing.md)
                    syncDetailRow(label: "Last synced", value: syncActivitySummary)
                }

                if let sharedWorkspaceRefreshMessage {
                    Divider().padding(.leading, DSSpacing.md)
                    syncDetailRow(label: "Last action", value: sharedWorkspaceRefreshMessage)
                }
            }
            .background(DSColors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))

            if let rootDescription = workspaceSyncService.workspaceRootDescription,
               workspaceSyncService.isUsingSharedWorkspace {
                // Plain words first, the path after (5.8): the owner read the bare path as a folder he could open
                // in Files (2026-11-04). The container is not published to iCloud Drive (`Info.plist` has no
                // `NSUbiquitousContainers`), so Files does not show it.
                DisclosureGroup("Where your libraries are kept") {
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text(
                            "In OpenIntelligence's own iCloud folder, which iCloud keeps the same on your devices that have the app. The Files app doesn't show it, so its files can't be moved or deleted there by accident. Your original files stay wherever you imported them from."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        Text("Technical details")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, DSSpacing.xxs)
                        Text(rootDescription)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, DSSpacing.xs)
                }
                .font(.caption.weight(.medium))
                .tint(.secondary)
            }

            if let lastErrorMessage = workspaceSyncService.lastErrorMessage {
                Text(lastErrorMessage)
                    .font(.caption)
                    .foregroundStyle(DSColors.readable(.orange))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DSSpacing.lg)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
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

    private var sharedWorkspaceSummary: String {
        if !hasICloudSyncAccess {
            return "iCloud library sync is available on Pro and Lifetime. Local Only keeps each library device-specific."
        }

        if hasConfiguredICloudLibraries {
            return "\(iCloudLibraryCount) iCloud • \(localOnlyLibraryCount) local. Libraries marked iCloud Sync use iCloud as the shared copy. Local Only libraries stay on just this device."
        }

        return "All libraries are Local Only right now. Turn iCloud Sync on per library when you want it on another device."
    }

    @MainActor
    private func resolvePendingBootstrap(_ choice: WorkspaceSyncService.BootstrapChoice) {
        guard hasICloudSyncAccess else {
            planEntryPoint = .iCloudSync
            showPlanSheet = true
            return
        }

        guard hasConfiguredICloudLibraries else { return }
        guard !isRefreshingSharedWorkspace else { return }

        isRefreshingSharedWorkspace = true
        sharedWorkspaceRefreshMessage = nil

        Task { @MainActor in
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

    @ViewBuilder
    private func routingFactorPill(icon: String, label: String) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .background(Color.secondary.opacity(0.1))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func pccBenefitRow(icon: String, text: String, color: Color) -> some View {
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

    @ViewBuilder
    private func processingModeCompare(icon: String, title: String, pros: String, cons: String, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(isActive ? Color.accentColor : .secondary)

            Text(pros)
                .font(.caption2)
                .foregroundStyle(DSColors.readable(.green))
            Text(cons)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .background(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
    }

}
