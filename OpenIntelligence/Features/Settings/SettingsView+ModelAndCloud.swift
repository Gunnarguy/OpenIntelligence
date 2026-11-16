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
    /// The symbol of the device the app runs on, for "On this device" blocks: it was always an iPhone (audit 2026-11-16).
    static var thisDeviceSymbol: String {
        #if os(macOS)
            // A Mac with an internal battery is a laptop; Mac identifiers no longer say which.
            return SystemStateMonitor.macBattery().level >= 0 ? "laptopcomputer" : "desktopcomputer"
        #else
            return UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        #endif
    }

    // MARK: - Model & Privacy

    /// The Model & Privacy page (2026-11-16): Apple Intelligence and Private Cloud Compute were two pages, and where an
    /// answer is written (On-Device, Hybrid or PCC) could be chosen only from the chat's model pill. One page now: the
    /// model and its languages, where answers are written, the Private Cloud Compute permission and quota, then the
    /// Apple Intelligence features. Every control and stored key is the one it was.
    @ViewBuilder
    var modelAndPrivacyPage: some View {
        modelSelectionCard
        answerRouteCard
        privateCloudComputeCard
        appleIntelligenceFeaturesCard
    }

    // MARK: - Model Selection Card

    @ViewBuilder
    var modelSelectionCard: some View {
        SurfaceCard {
            SectionHeader(
                icon: "apple.intelligence", title: "Model",
                caption: deviceCapabilities.supportsAppleIntelligence ? "Apple Intelligence is available" : nil)

            // Model info (not a button since there's only one option)
            HStack(alignment: .top, spacing: DSSpacing.md) {
                Image(systemName: "brain.head.profile")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    // The card's own nickname and tagline ("AFM 3 Ecosystem", "Evidence-first routing ...") with
                    // Technical Details on; plain words otherwise (5.7 UI cleanup).
                    Text(settings.showTechnicalDetails ? settings.selectedModel.capabilityCard.nickname : plainModelName)
                        .font(.subheadline.weight(.medium))
                    Text(settings.showTechnicalDetails ? settings.selectedModel.capabilityCard.tagline : plainModelTagline)
                        .font(.caption)
                        .foregroundStyle(DSColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            // Model capabilities
            HStack(spacing: DSSpacing.xs) {
                modelCapabilityPill(icon: "text.bubble", label: "Text Generation")
                // The model's name only with Technical Details on (5.7 UI cleanup).
                modelCapabilityPill(icon: "photo", label: settings.showTechnicalDetails ? "ADM 3 Visuals" : "Images")
                modelCapabilityPill(icon: "doc.text", label: settings.showTechnicalDetails ? "RAG-Ready" : "Your documents")
            }

            Divider()

            // Moved from Device & Performance (2026-11-16).
            languageSupportSection
        }
    }

    @ViewBuilder
    private func modelCapabilityPill(icon: String, label: String) -> some View {
        Label(label, systemImage: icon)
            .chipStyle(tint: .accentColor)
    }

    // MARK: - Where answers are written

    /// The answer route, bound to `settings.fmPreference`, the setting the chat's model pill
    /// (`ModelStatusIndicator`) sets (2026-11-16). Three rows in the shape of this page's other rows, a checkmark on
    /// the chosen one, where the pill's menu was the only place to choose. Private Cloud Compute is offered on iOS and
    /// macOS 27 (`FoundationModelPreference.availableCases`), and shown but not choosable in a build without its
    /// entitlement, as in the pill's menu.
    @ViewBuilder
    var answerRouteCard: some View {
        SurfaceCard {
            SectionHeader(
                icon: "arrow.triangle.branch", title: "Where answers are written",
                caption: "The same choice as the model button in the chat")

            VStack(spacing: 0) {
                ForEach(Array(FoundationModelPreference.availableCases.enumerated()), id: \.element) { index, preference in
                    if index > 0 { Divider().padding(.leading, 40) }
                    answerRouteRow(preference)
                }
            }

            Text("Private Cloud Compute is used only as the permission below allows. Searching your documents always happens on this device.")
                .font(.caption)
                .foregroundStyle(DSColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pccEntitled: Bool {
        #if canImport(FoundationModels)
            EntitlementChecker.hasEntitlement("com.apple.developer.private-cloud-compute")
        #else
            false
        #endif
    }

    @ViewBuilder
    private func answerRouteRow(_ preference: FoundationModelPreference) -> some View {
        let selected = settings.fmPreference.canonical == preference.canonical
        let enabled = preference != .privateCloudCompute || pccEntitled
        Button {
            guard enabled, !selected else { return }
            DSHaptics.selection()
            settings.fmPreference = preference
        } label: {
            HStack(alignment: .top, spacing: DSSpacing.md) {
                Image(systemName: Self.answerRouteIcon(preference))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selected ? Color.accentColor : DSColors.secondaryText)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(enabled ? preference.pickerDisplayName : "\(preference.pickerDisplayName) (not available)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(enabled ? DSColors.primaryText : DSColors.secondaryText)
                    Text(Self.answerRouteDescription(preference))
                        .font(.caption)
                        .foregroundStyle(DSColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DSSpacing.sm)
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .opacity(selected ? 1 : 0)
            }
            .padding(.vertical, DSSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The pill's icons for the three routes (`ModelStatusIndicator.preferenceIcon`).
    private static func answerRouteIcon(_ preference: FoundationModelPreference) -> String {
        switch preference.canonical {
        case .automatic: "arrow.triangle.branch"
        case .core3B, .advanced20B: "iphone.gen3"
        case .privateCloudCompute: "cloud"
        }
    }

    /// What each route does, from `ModelExecutionPlanner`: Hybrid sends an answer whose passages don't fit this
    /// device's model, or a Deep Think or Maximum answer drawn from more than one document (`complexityRequestsPCC`);
    /// PCC sends every answer drawn from your documents. This was a 70-word paragraph on the Private Cloud Compute page
    /// that named "the model picker" without the picker being there (2026-11-16).
    private static func answerRouteDescription(_ preference: FoundationModelPreference) -> String {
        switch preference.canonical {
        case .core3B, .advanced20B:
            "Every answer is written on this device."
        case .automatic:
            "On this device, and on Private Cloud Compute, as the permission below allows, for an answer too large for this device's model or a Deep Think or Maximum answer drawn from more than one document."
        case .privateCloudCompute:
            "Private Cloud Compute writes every answer drawn from your documents, as the permission below allows."
        }
    }

    // MARK: - Private Cloud Compute Card

    @ViewBuilder
    var privateCloudComputeCard: some View {
        SurfaceCard {
            // Corrected 2026-10-15: "after you approve each request" is untrue of Allow without asking,
            // and on iOS and macOS 26 the reason it's off is the system, not the build.
            SectionHeader(
                icon: "cloud", title: "Private Cloud Compute",
                caption: deviceCapabilities.supportsPrivateCloudCompute
                    ? "Apple's servers, for the writing step only, with your permission"
                    : DeviceCapabilities.pccRoutingCompiledIn
                        ? "Needs iOS or macOS 27. Every answer is written on this device."
                        : "Not in this build. Every answer is written on this device.")

            // The paragraph this replaces read "Apple's Private Cloud Compute (PCC) allows
            // OpenIntelligence to process complex queries with a massive 32,768 token
            // context window...". Three problems. It framed PCC as the thing that makes
            // the app work, which is backwards: `FoundationModelRoutePolicy` returns
            // `.onDevice` on every branch of the automatic path unless a prompt exceeds
            // the device window. "Massive" is doing work that a number should do. And the
            // 32,768 was hardcoded directly above a block that renders the *live* figure,
            // so the same screen could show two different numbers. The panel's badge states the live availability
            // (`pccCapability`), which the header's Available or Unavailable dot repeated until 2026-11-16.
            contextWindowPanel

            HStack(spacing: DSSpacing.sm) {
                Text("When to allow it")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: DSSpacing.xs)
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
                .foregroundStyle(DSColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                Divider()

                // The quota, as the system reports it ("PCC Quota Status" until 2026-11-16).
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    Text("Quota")
                        .font(.subheadline.weight(.medium))

                    if let capability = pccCapability, capability.pccAvailable {
                        HStack {
                            Text("Status")
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
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }
            }
            #endif
        }
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
    /// How much each model can read at once, side by side (5.8): the two figures the rows below this used to
    /// state, with each bar lit in proportion to the larger window.
    private var contextWindowPanel: some View {
        let device = pccCapability?.onDeviceContextSize ?? 0
        let onDevice = device > 0 ? device : FoundationModelTokenBudget.contextSize(isAppleFMOnDevice: true)
        let reported = pccCapability?.pccContextSize ?? 0
        let cloud = reported > 0 ? reported : FoundationModelTokenBudget.contextSize(isAppleFMOnDevice: false)
        let cloudOn = deviceCapabilities.supportsPrivateCloudCompute
        let largest = Double(max(1, max(onDevice, cloudOn ? cloud : 0)))
        let available = pccCapability?.pccAvailable ?? cloudOn
        return SettingsStatusPanel(
            symbol: "text.viewfinder",
            title: "Reads at once",
            badge: available ? "Cloud ready" : "On device only",
            badgeColor: available ? .green : Color.secondary,
            blocks: [
                .init(
                    symbol: Self.thisDeviceSymbol, name: "On this device", color: .blue,
                    figure: onDevice > 0 ? onDevice.formatted() : "Unavailable",
                    share: Double(onDevice) / largest, caption: onDevice > 0 ? "tokens" : "no model"),
                .init(
                    // "In the cloud", as on Intelligence Mode (2026-11-16): the full name was cut to "Private Cloud C...".
                    symbol: "cloud.fill", name: "In the cloud", color: .cyan,
                    figure: cloudOn ? cloud.formatted() : "Unavailable",
                    share: cloudOn ? Double(cloud) / largest : 0, caption: cloudOn ? "tokens" : "not on this system"),
                permissionBlock,
            ])
    }

    /// The permission setting as a block: what the picker below it is set to.
    private var permissionBlock: SettingsStatusPanel.Block {
        switch settings.pccSetting {
        case .never:
            .init(symbol: "hand.raised.fill", name: "Permission", color: .green, figure: "Never", share: 0, caption: "stays here")
        case .ask:
            .init(symbol: "hand.raised.fill", name: "Permission", color: .green, figure: "Asks", share: 0.5, caption: "each time")
        case .allow:
            .init(symbol: "hand.raised.fill", name: "Permission", color: .green, figure: "Allowed", share: 1, caption: "without asking")
        }
    }

    /// Where the libraries live, as lit blocks (5.8): how many stay on this device, how many sync, how many watch a folder.
    private var librariesPanel: some View {
        let own = containerService.containers.filter { !containerService.isGuideLibrary($0.id) }
        let synced = own.filter { $0.syncMode == .iCloudShared }.count
        let local = own.count - synced
        let watched = WatchedFolderService.shared.folders.count
        let total = Double(max(1, own.count))
        let documents = SettingsStatusPanel.used(ragService.countedDocumentCount, of: entitlementStore.documentLimit)
        return SettingsStatusPanel(
            symbol: "books.vertical",
            title: own.count == 1 ? "1 library" : "\(own.count) libraries",
            badge: synced > 0 ? "Syncing" : "Local only",
            badgeColor: synced > 0 ? .green : Color.secondary,
            blocks: [
                .init(
                    symbol: "internaldrive", name: "On this device", color: .blue, figure: "\(local)",
                    share: Double(local) / total, caption: "local only"),
                .init(
                    symbol: "icloud.fill", name: "In iCloud", color: .cyan, figure: "\(synced)",
                    share: Double(synced) / total, caption: "on your devices"),
                .init(
                    symbol: "folder", name: "Watched", color: .green, figure: "\(watched)",
                    share: Double(watched) / total, caption: watched == 1 ? "folder" : "folders"),
                .init(
                    symbol: "doc.text", name: "Documents", color: .orange, figure: documents.figure,
                    share: documents.share, caption: documents.caption),
            ])
    }

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

            librariesPanel

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
