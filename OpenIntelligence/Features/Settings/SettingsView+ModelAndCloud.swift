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

    /// The Model & Privacy page. One page since 2026-11-16 (Apple Intelligence and Private Cloud Compute were two), and
    /// since 2026-11-17 in Intelligence Mode's language (the owner: it "should kind of look similar to the other pages
    /// that we have revamped"). Two cards: answers, then the Apple Intelligence features. It was four cards of prose
    /// rows: the panel sat inside the third card, the quota was a list ("Status belowLimit", then "Context 32768
    /// tokens", the figure the panel already showed), the permission's name stood twice beside its menu, and the
    /// model's 33 languages were one paragraph. Every control and stored key is the one it was: `fmPreference`,
    /// `pccSetting`, the four feature switches and the reply count.
    @ViewBuilder
    var modelAndPrivacyPage: some View {
        answersCard
        appleIntelligenceFeaturesCard
    }

    /// The panel, where answers are written, the Private Cloud Compute permission, then the model folded.
    private var answersCard: some View {
        SurfaceCard {
            modelPrivacyPanel
            if let reason = pccUnavailableLine {
                Text(reason)
                    .scaledFont(size: 11)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            answerRouteSection
            permissionSection
            modelDetails
        }
    }

    /// Why Private Cloud Compute can't be used here, as the system reports it; nil while it can, or before it reports.
    private var pccUnavailableLine: String? {
        guard let capability = pccCapability, !capability.pccAvailable else { return nil }
        return capability.unavailabilityReason ?? "Private Cloud Compute is unavailable on this device."
    }

    // MARK: Where answers are written

    /// The routes on the ladder, from staying on the device to the cloud: On-Device, Hybrid, PCC. The chat's model
    /// button lists the same three (`FoundationModelPreference.availableCases`); PCC only on iOS and macOS 27.
    private var answerRoutes: [FoundationModelPreference] {
        [.core3B, .automatic, .privateCloudCompute].filter { route in
            FoundationModelPreference.availableCases.contains { $0.canonical == route }
        }
    }

    private static func answerRouteColor(_ preference: FoundationModelPreference) -> Color {
        switch preference.canonical {
        case .core3B, .advanced20B: .blue
        case .automatic: .indigo
        case .privateCloudCompute: .cyan
        }
    }

    private static func answerRouteTitle(_ preference: FoundationModelPreference) -> String {
        switch preference.canonical {
        case .core3B, .advanced20B: "On-Device"
        case .automatic: "Hybrid"
        case .privateCloudCompute: "Private Cloud Compute"
        }
    }

    private func answerRouteWording(_ preference: FoundationModelPreference) -> SettingsLadderNote.Wording {
        let available = preference.canonical != .privateCloudCompute || pccEntitled
        return SettingsLadderNote.Wording(
            symbol: Self.answerRouteIcon(preference),
            title: available ? Self.answerRouteTitle(preference) : "\(Self.answerRouteTitle(preference)) (not in this build)",
            detail: Self.answerRouteDescription(preference))
    }

    /// The answer route, bound to `settings.fmPreference`, the setting the chat's model pill (`ModelStatusIndicator`)
    /// sets. A ladder since 2026-11-17; three paragraph rows with a checkmark before.
    private var answerRouteSection: some View {
        let selected = settings.fmPreference.canonical
        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            // The caption under the label, not beside it: on a 375-point iPhone the two wrapped into each other.
            VStack(alignment: .leading, spacing: 1) {
                SettingsGroupLabel(text: "WHERE ANSWERS ARE WRITTEN")
                Text("Same as the chat's model button")
                    .scaledFont(size: SettingsStatusPanel.minimumTextSize)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsLadder(
                rungs: answerRoutes.map { route in
                    .init(
                        item: route, name: route.pickerDisplayName, color: Self.answerRouteColor(route),
                        enabled: route != .privateCloudCompute || pccEntitled,
                        accessibilityLabel: "\(Self.answerRouteTitle(route)) answer route")
                },
                selected: selected
            ) { route in
                settings.fmPreference = route
            }
            SettingsLadderNote(
                wordings: answerRoutes.map(answerRouteWording),
                current: answerRouteWording(selected),
                color: Self.answerRouteColor(selected))
        }
    }

    private var pccEntitled: Bool {
        #if canImport(FoundationModels)
            EntitlementChecker.hasEntitlement("com.apple.developer.private-cloud-compute")
        #else
            false
        #endif
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

    // MARK: Private Cloud Compute permission

    private static func permissionName(_ setting: PCCSettings) -> String {
        switch setting {
        case .never: "Never"
        case .ask: "Ask"
        case .allow: "Allow"
        }
    }

    private static func permissionColor(_ setting: PCCSettings) -> Color {
        switch setting {
        case .never: .secondary
        case .ask: .orange
        case .allow: .green
        }
    }

    private static func permissionWording(_ setting: PCCSettings) -> SettingsLadderNote.Wording {
        switch setting {
        case .never:
            .init(symbol: "hand.raised", title: setting.displayName, detail: "Every answer is written on this device, whatever the route above says.")
        case .ask:
            .init(symbol: "questionmark.bubble", title: setting.displayName, detail: "Before an answer goes to Private Cloud Compute, the app asks: Just Once for that question, Always Allow, or Deny, which sets this to Never.")
        case .allow:
            .init(symbol: "checkmark.shield", title: setting.displayName, detail: "An answer goes to Private Cloud Compute when the route above sends it, without asking.")
        }
    }

    /// `settings.pccSetting` as a ladder (2026-11-17): it was a menu with the setting's name printed beside it twice.
    /// The menu's full names ("Never use", "Ask when needed", "Allow without asking") are the note's title.
    private var permissionSection: some View {
        let supported = deviceCapabilities.supportsPrivateCloudCompute
        // Corrected 2026-10-15: "after you approve each request" is untrue of Allow without asking, and on iOS and
        // macOS 26 the reason it's off is the system, not the build.
        let caption = supported
            ? "Apple's servers, for the writing step only, with your permission"
            : DeviceCapabilities.pccRoutingCompiledIn
                ? "Needs iOS or macOS 27. Every answer is written on this device."
                : "Not in this build. Every answer is written on this device."
        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            VStack(alignment: .leading, spacing: 1) {
                SettingsGroupLabel(text: "PRIVATE CLOUD COMPUTE")
                Text(caption)
                    .scaledFont(size: SettingsStatusPanel.minimumTextSize)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsLadder(
                rungs: PCCSettings.allCases.map { setting in
                    .init(
                        item: setting, name: Self.permissionName(setting), color: Self.permissionColor(setting),
                        accessibilityLabel: "Private Cloud Compute: \(setting.displayName)")
                },
                selected: settings.pccSetting,
                disabled: !supported
            ) { setting in
                settings.pccSetting = setting
            }
            // Where Private Cloud Compute can't be used the ladder is off, and the note says so instead of
            // describing a stored setting that has no effect here.
            let unsupported = SettingsLadderNote.Wording(
                symbol: "iphone.gen3", title: "On this device only", detail: caption)
            SettingsLadderNote(
                wordings: PCCSettings.allCases.map(Self.permissionWording) + [unsupported],
                current: supported ? Self.permissionWording(settings.pccSetting) : unsupported,
                color: supported ? Self.permissionColor(settings.pccSetting) : .secondary)
            Text("OpenIntelligence does not operate its own servers. Nothing is sent anywhere else. Reading, indexing and searching your documents all happen here regardless of this setting; only the final answer can ever leave.")
                .scaledFont(size: SettingsStatusPanel.minimumTextSize)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: The model, folded

    /// The model's name and what it does, its capabilities and its languages, folded like Intelligence Mode's "Same
    /// in every mode". They were the page's first card, and the languages a paragraph of 33 names.
    private var modelDetails: some View {
        let languages = modelLanguageNames ?? []
        return FoldedDetails(title: languages.isEmpty ? "The model" : "The model and its \(languages.count) languages") {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                // The model card's caption until 2026-11-17, kept: whether this device has Apple Intelligence, and
                // Apple's name for the model it runs (`onDeviceModelName`, iOS and macOS 27), read from the device.
                Label(
                    deviceCapabilities.supportsAppleIntelligence
                        ? (onDeviceModelName.map { "Apple Intelligence is available: this device runs \($0)" }
                            ?? "Apple Intelligence is available")
                        : "Apple Intelligence isn't available on this device",
                    systemImage: deviceCapabilities.supportsAppleIntelligence ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .scaledFont(size: 11, weight: .semibold)
                .foregroundStyle(DSColors.readable(deviceCapabilities.supportsAppleIntelligence ? .green : .orange))
                VStack(alignment: .leading, spacing: 1) {
                    // The card's nickname (Apple's model name, read from the device) and tagline with
                    // Technical Details on; plain words otherwise (5.7 UI cleanup).
                    Text(settings.showTechnicalDetails ? settings.selectedModel.capabilityCard.nickname : plainModelName)
                        .scaledFont(size: 12, weight: .semibold)
                    Text(settings.showTechnicalDetails ? settings.selectedModel.capabilityCard.tagline : plainModelTagline)
                        .scaledFont(size: 11)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: DSSpacing.xs) {
                    modelCapabilityPill(icon: "text.bubble", label: "Text Generation")
                    // The model's name only with Technical Details on (5.7 UI cleanup).
                    modelCapabilityPill(icon: "photo", label: settings.showTechnicalDetails ? "Image Playground" : "Images")
                    modelCapabilityPill(icon: "doc.text", label: settings.showTechnicalDetails ? "RAG-Ready" : "Your documents")
                }
                SettingsGroupLabel(text: "LANGUAGES")
                // The languages this device's model reports (`SystemLanguageModel.supportedLanguages`, iOS and macOS
                // 26), named in the person's own language. Through the first 5.7 builds this was a list of 19 typed in
                // by hand, which nothing checked against the device (2026-10-20).
                if languages.isEmpty {
                    Text("Apple's model hasn't said which languages it answers in on this device.")
                        .scaledFont(size: 11)
                        .foregroundStyle(.secondary)
                } else {
                    Text(settings.showTechnicalDetails ? "SystemLanguageModel.supportedLanguages on this device:" : "Apple's model on this device answers in:")
                        .scaledFont(size: SettingsStatusPanel.minimumTextSize)
                        .foregroundStyle(.secondary)
                    Text(languages.joined(separator: " · "))
                        .scaledFont(size: 11)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func modelCapabilityPill(icon: String, label: String) -> some View {
        Label(label, systemImage: icon)
            .chipStyle(tint: .accentColor)
    }

    func refreshPCCCapability() async {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            pccCapability = await LiveFoundationModelCapabilityProvider().snapshot()
        }
        #endif
        TourContext.privateCloudAvailable = pccCapability?.pccAvailable ?? deviceCapabilities.supportsPrivateCloudCompute
    }

    /// The page's panel (5.8; "Reads at once" inside the Private Cloud Compute card until 2026-11-17): the model and
    /// route in its title, then how much each model reads at once, the permission, and the quota Apple reports. The
    /// quota was a list under the menu that read "Status belowLimit".
    private var modelPrivacyPanel: some View {
        let device = pccCapability?.onDeviceContextSize ?? 0
        let onDevice = device > 0 ? device : FoundationModelTokenBudget.contextSize(isAppleFMOnDevice: true)
        let reported = pccCapability?.pccContextSize ?? 0
        let cloud = reported > 0 ? reported : FoundationModelTokenBudget.contextSize(isAppleFMOnDevice: false)
        let cloudOn = deviceCapabilities.supportsPrivateCloudCompute
        let largest = Double(max(1, max(onDevice, cloudOn ? cloud : 0)))
        let available = pccCapability?.pccAvailable ?? cloudOn
        let model = settings.showTechnicalDetails ? settings.selectedModel.capabilityCard.nickname : plainModelName
        return SettingsStatusPanel(
            symbol: "apple.intelligence",
            // The route only where a model writes: Quotes only answers with sentences from the documents.
            title: settings.selectedModel == .onDeviceAnalysis
                ? model : "\(model) · \(settings.fmPreference.canonical.pickerDisplayName)",
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
                quotaBlock,
            ])
    }

    /// Apple's Private Cloud Compute quota for this app, as the system reports it (`PCCQuotaState`), in words.
    private var quotaBlock: SettingsStatusPanel.Block {
        let symbol = "gauge.with.dots.needle.67percent"
        guard let capability = pccCapability else {
            return .init(symbol: symbol, name: "Quota", color: .orange, figure: "Reading", share: 0, caption: "from the system")
        }
        guard capability.pccAvailable else {
            // On iOS or macOS 27 with the entitlement, unavailable can be for now (`.unavailable(reason)`); the reason
            // is the line under the panel.
            return deviceCapabilities.supportsPrivateCloudCompute
                ? .init(symbol: symbol, name: "Quota", color: .orange, figure: "Unavailable", share: 0, caption: "right now")
                : .init(symbol: symbol, name: "Quota", color: .orange, figure: "None", share: 0, caption: "no cloud here")
        }
        switch capability.pccQuota {
        case .belowLimit:
            return .init(symbol: symbol, name: "Quota", color: .orange, figure: "Below limit", share: 0.25, caption: "Apple's limit")
        case .approachingLimit:
            return .init(symbol: symbol, name: "Quota", color: .orange, figure: "Near limit", share: 0.8, caption: "Apple's limit")
        case .limitReached:
            return .init(symbol: symbol, name: "Quota", color: .red, figure: "Reached", share: 1, caption: "Apple's limit")
        case .unknown, .unsupported:
            return .init(symbol: symbol, name: "Quota", color: .orange, figure: "Not reported", share: 0, caption: "by the system")
        }
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
