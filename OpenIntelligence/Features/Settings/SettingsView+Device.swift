//
//  SettingsView+Device.swift
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
    // MARK: - Context Window Card

    @ViewBuilder
    var contextWindowCard: some View {
        let deviceService = DeviceCapabilityService.shared

        VStack(alignment: .leading, spacing: DSSpacing.md) {
            // What this device is and reports, each value with its source; with Technical Details on, a fold of what
            // the app sets for it (5.8). Replaced the tier badge, the TOPS and cooling line, the Deep Think and Thermal
            // pills and the Hardware Envelope (`ActiveDeviceCard`).
            ActiveDeviceCard(showsInternals: settings.showTechnicalDetails)

            Divider()

            // Context Window moved to the Intelligence Mode page (5.8): how much each answer can read is a fact about
            // the answer modes, and it sat here between the device and the compute profile.

            // Silicon-Native RAG Engine: vDSP, Metal shaders and batch sizes, with Technical Details on (5.7).
            if settings.showTechnicalDetails {
                siliconNativeRAGSection(deviceService: deviceService)

                Divider()
            }

            // GPU Acceleration Controls
            gpuAccelerationSection(deviceService: deviceService)

            Divider()

            // Live System Monitor: thermal state, memory, cores and the pipeline's own adjustments, with Technical
            // Details on (5.7).
            if settings.showTechnicalDetails {
                LiveSystemMonitorWrapper()

                Divider()
            }

            // Language Support
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: "globe")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    Text("Language Support")
                        .font(.subheadline.weight(.medium))
                }

                // The languages this device's model reports (`SystemLanguageModel.supportedLanguages`, iOS and macOS 26),
                // named in the person's own language. Through the first 5.7 builds this was a list of 19 typed in by
                // hand as "verified Apple Intelligence languages as of iOS 26.0+", which nothing checked against the
                // device, with "Apple routes automatically" under it, which no code here does (2026-10-20).
                if let languages = modelLanguageNames, !languages.isEmpty {
                    Text(settings.showTechnicalDetails ? "SystemLanguageModel.supportedLanguages on this device:" : "Apple's model on this device answers in:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(languages.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Apple's model hasn't said which languages it answers in on this device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(DSSpacing.md)
            .background(DSColors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
        }
        .padding(DSSpacing.lg)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    @ViewBuilder
    private func contextInfoPill(icon: String, label: String, value: String) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2)
            Text(value)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .background(Color.secondary.opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - Silicon-Native RAG Engine Section

    @ViewBuilder
    private func siliconNativeRAGSection(deviceService: DeviceCapabilityService) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            SettingsSectionHeader(icon: "bolt.horizontal.fill", title: "Silicon-Native RAG Engine", badge: "Accelerate")

            // "4x faster" removed 2026-08-06. No benchmark supporting it exists in
            // `Benchmarks/` or the evaluation docs, same class as the `1,000x` dedup and
            // `240x` scrolling figures withdrawn in this release. The GPU path is real;
            // the multiplier was never measured.
            // "GPU level ≥ 60%" named a percentage the GPU setting no longer shows; the gate is
            // `searchesLargeLibrariesOnGPU(for:)` with the stores' own thresholds (5.7).
            // 5.8 review: no BLAS call exists; the diversity step's GPU part compares candidates, and its picking is CPU work.
            Text(
                "Vector math uses Apple's Accelerate framework (vDSP) on the CPU. With the Compute Profile on Performance or Maximum, Metal shaders score a library of 1,000 passages or more, and the diversity step compares more than 50 candidates on the GPU before picking on the CPU. "
                    + (deviceService.batchMatrixMultiplyThreshold == Int.max
                        ? "On the CPU, passages are scored one at a time."
                        : "On the CPU, from \(deviceService.batchMatrixMultiplyThreshold) passages a library is scored in one matrix pass.")
            )
                .font(.caption)
                .foregroundStyle(.secondary)

            // Optimizations grid
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                siliconFeatureRow(
                    icon: "function",
                    label: "vDSP Vector Math",
                    detail: "CPU SIMD-accelerated similarity"
                )
                siliconFeatureRow(
                    icon: "square.grid.3x3.fill",
                    label: "Metal GPU Shaders",
                    detail: "Threadgroup kernel; SIMD4 for long vectors"
                )
                siliconFeatureRow(
                    icon: "text.line.first.and.arrowtriangle.forward",
                    label: "Section Boundaries",
                    detail: "Headings, tables, sentence ends"
                )
                siliconFeatureRow(
                    icon: "lock.fill",
                    label: "Library Isolation",
                    detail: "In the app, the active library; Siri and Shortcuts name theirs"
                )
            }

            // "Vector Batch" and "Embed Batch" pills removed (5.8): nothing reads either value. The CPU's one-pass
            // threshold is in the text above.
        }
        .padding(DSSpacing.md)
        .background(DSColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    @ViewBuilder
    private func siliconFeatureRow(icon: String, label: String, detail: String) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.caption.weight(.medium))
            Spacer()
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - GPU Acceleration Section


    private func gpuAccelerationSection(deviceService: DeviceCapabilityService) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            // "GPU Acceleration" until 5.8: the profiles move work between the CPU, the Neural Engine and the GPU.
            SettingsSectionHeader(icon: "cpu", title: "Compute Profile", badge: gpuModeName, badgeColor: gpuModeColor)

            // Until 5.7: "Choose how OpenIntelligence schedules GPU-capable work...". The profiles cover the Core ML
            // embedding model, the Core Image cleanup of scanned pages and Metal vector search, never Apple's model.

            if deviceService.activeGPUExecutionProfile != gpuProfile {
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.caption)
                        .foregroundStyle(DSColors.readable(.orange))
                    Text("On the \(deviceService.chipDisplayName), \(gpuProfile.displayName) runs as \(deviceService.activeGPUExecutionProfile.displayName), to keep long imports stable\(gpuProfile == .maximum ? "; it still loads its Core ML models for prediction speed" : "").")
                        .font(.caption2)
                        .foregroundStyle(DSColors.readable(.orange))
                }
                .padding(DSSpacing.sm)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
            }

            // Discrete profiles avoid implying a precise GPU percentage that Core ML cannot promise. The chip, the
            // ladder and the grid of jobs replaced four buttons and a list of sentences (5.8).
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                ComputeProfileCard(
                    profile: $gpuProfile,
                    chipName: deviceService.chipDisplayName,
                    backgroundGPUProfiles: computeBackgroundGPUProfiles(deviceService),
                    systemOffersBackgroundGPU: computeSystemOffersBackgroundGPU,
                    deviceNoun: computeDeviceNoun(deviceService),
                    backgroundNote: { backgroundImportNote(for: $0, deviceService: deviceService) },
                    concurrencyFor: { profile in
                        let pace = deviceService.concurrency(for: profile)
                        return ComputeProfileCard.Concurrency(
                            visionParsingPages: pace.visionParsing, ocrPages: pace.ocr, renderSlots: pace.render,
                            embeddingParallel: pace.embedding)
                    },
                    onSelect: { profile in
                        withAnimation(DSAnimations.snappySpring) { gpuProfile = profile }
                        DeviceCapabilityService.shared.gpuExecutionProfile = profile
                    }
                )

                // One line (5.8): the background rule now sits in its job's row on the card, and "Same in every profile"
                // says what the setting does not cover; three paragraphs here repeated both (the owner, 2026-11-10).
            }
            .padding(DSSpacing.sm)
            .background(DSColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
            .animation(DSAnimations.fastEase, value: gpuProfile)

            // Everything under the card is folded into one row (5.8): it repeated the card in a second layout and
            // pushed the section past one screen on an iPhone 16 Pro Max (the owner, 2026-11-10).
            FoldedDetails(title: "More detail") {
            // 5.8 review: depth and pacing are read at each use; only the embedding model's chips wait for it to load.
            Text("Depth and pacing apply at once; the embedding model's chips change with the next import and for searching from the next launch, as does Maximum's prediction-speed loading.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack(spacing: DSSpacing.sm) {
                    Text(settings.showTechnicalDetails ? "Adaptive Visual Ingestion" : "Reading PDFs and Images")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("Automatic")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, DSSpacing.sm)
                        .padding(.vertical, DSSpacing.xxs)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                }

                Text(
                    settings.showTechnicalDetails
                        ? "Each PDF page is analysed first: the engine raises OCR detail, structure recovery and visual analysis when a page is garbled, table-heavy, columnar, image-heavy or small-text risky, and stays lighter on clean text-native pages; Maximum reads every page it recognises at full detail. A standalone image gets one fixed reading."
                        : "A PDF page gets a closer reading when it needs one: text that comes out garbled, tables, columns, pictures or small print. A page whose text is already clean gets a lighter one, and an image gets one fixed reading."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(DSSpacing.md)
            .background(DSColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))

            // The live policy, read from the same properties the execution paths consult, so it shows the
            // device's ceiling, a background import and the Simulator's CPU-only Core ML as they are (5.7: behind
            // Technical Details; the "Thermal Impact" row is gone, it ranked Maximum hotter than Performance when in
            // the foreground the two run the same rules).
            if settings.showTechnicalDetails {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                gpuSettingRow(
                    icon: "cpu",
                    label: "Embedding, searching",
                    value: EmbeddingProviderDefaults.preferredSentenceProviderId == EmbeddingProviderDefaults.coreAI
                        ? "Core AI on the GPU (new libraries)" : deviceService.preferredComputeUnitsDescription
                )
                gpuSettingRow(
                    icon: "cube.transparent",
                    label: "Embedding, importing",
                    value: EmbeddingProviderDefaults.preferredSentenceProviderId == EmbeddingProviderDefaults.coreAI
                        ? "Core AI on the GPU (new libraries)" : deviceService.embeddingComputeUnitsDescription
                )
                gpuSettingRow(
                    icon: "doc.text.image",
                    label: "Extra PDF page pass",
                    value: deviceService.useGPUForPDFRendering ? "On, Core Image on the GPU" : "Off"
                )
                gpuSettingRow(
                    icon: "function",
                    label: "Large searches",
                    value: deviceService.useMetalForVectorOps ? "Metal on the GPU from 1,000 passages" : "Accelerate on the CPU"
                )
            }
            .animation(DSAnimations.fastEase, value: gpuProfile)

            Divider()
                .padding(.vertical, DSSpacing.xxs)

            // Pipeline concurrency remains tier-based rather than profile-controlled.
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text("Pipeline Concurrency")
                    .font(.subheadline.weight(.medium))
                // The profile paces these since 5.8: Efficiency does half as much at once.
                Text("Set by the \(deviceService.chipDisplayName) and its memory, and lower in a background import. Efficiency does about half as much at once, and Maximum can hold fewer pages, to fit full-detail pages.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                gpuSettingRow(
                    icon: "doc.text.image",
                    label: "Pages per batch",
                    value: "\(deviceService.visionParsingConcurrency) pages"
                )
                gpuSettingRow(
                    icon: "waveform",
                    label: "Older OCR path",
                    value: "\(deviceService.ocrExtractionConcurrency) pages"
                )
                gpuSettingRow(
                    icon: "photo.stack",
                    label: "Page images",
                    value: "up to \(deviceService.pdfRenderingConcurrency) held "
                        + (deviceService.isMaximumFidelityActive ? "(432 DPI)" : "(360-432 DPI)")
                )
                gpuSettingRow(
                    icon: "cube.transparent",
                    label: "Embedding",
                    value: EmbeddingProviderDefaults.preferredSentenceProviderId == EmbeddingProviderDefaults.coreAI
                        ? "one at a time (Core AI)" : "up to \(deviceService.embeddingConcurrency) at a time"
                )
            }
            .animation(DSAnimations.fastEase, value: gpuProfile)
            }
            }
            // Until 5.7 a warning here said Maximum "may cause device heating during large document ingestion".
            // An import runs the same rules in Balanced, Performance and Maximum while the app is open, so the
            // warning singled out a profile that imports no differently.
        }
        .padding(DSSpacing.md)
        .background(DSColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
        .onAppear {
            gpuProfile = DeviceCapabilityService.shared.gpuExecutionProfile
        }
    }

    /// What an import does in the background with `profile` on this device (5.7). The rule is `BackgroundGPUAllowance`,
    /// the one `BackgroundTaskService` applies when it asks iOS to let the import go on.
    private func backgroundImportNote(for profile: GPUExecutionProfile, deviceService: DeviceCapabilityService) -> String {
        // The policy is worked out when the import is handed to iOS, in the foreground, and kept
        // (`BackgroundTaskService.continuedProcessingPolicy`), so the conditions read "when it starts". What the GPU grant
        // changes is what the import may use; a file already being embedded keeps the model it loaded.
        #if os(iOS) && !targetEnvironment(macCatalyst)
            let noun = deviceService.formFactor.deviceNoun
            let allowance = deviceService.backgroundGPUAllowance
            let admitting = deviceService.backgroundGPUProfiles
            let system = noun == "iPad" ? "iPadOS" : "iOS"
            // 5.8 review: a file already being embedded keeps the model it loaded, so "without it" was too strong.
            guard BackgroundTaskService.shared.systemOffersBackgroundGPU else {
                return "In the background, \(system) doesn't offer this \(noun) the GPU, so an import there doesn't ask for it; a file already being embedded keeps the model it loaded."
            }
            guard !admitting.isEmpty else {
                return "In the background, no profile asks \(system) to keep the GPU for an import on this \(noun)."
            }
            let when: String
            if allowance.chargingOnly {
                when = "when the \(noun) is charging as the import starts"
            } else if allowance.minimumBatteryPercent > 0 {
                when = "when the \(noun) is charging or has \(allowance.minimumBatteryPercent)% battery or more as the import starts"
            } else {
                when = "at any battery level"
            }
            guard admitting.contains(profile) else {
                let names = ListFormatter.localizedString(byJoining: admitting.map(\.displayName))
                let verb = admitting.count == 1 ? "does" : "do"
                return "In the background, \(profile.displayName) doesn't ask \(system) to keep the GPU for an import on this \(noun). \(names) \(verb), \(when)."
            }
            return "In the background, an import asks \(system) to keep the GPU \(when), unless Low Power Mode is on, the \(noun) is hot, memory is critically low or, from \(system) 27, the system asks apps to use less. \(system) decides whether to grant it."
        #else
            return "On a Mac, this setting works the same way while the app is in the background."
        #endif
    }

    private func computeBackgroundGPUProfiles(_ deviceService: DeviceCapabilityService) -> [GPUExecutionProfile] {
        #if os(iOS) && !targetEnvironment(macCatalyst)
            return deviceService.backgroundGPUProfiles
        #else
            return []
        #endif
    }

    private var computeSystemOffersBackgroundGPU: Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst)
            return BackgroundTaskService.shared.systemOffersBackgroundGPU
        #else
            return false
        #endif
    }

    private func computeDeviceNoun(_ deviceService: DeviceCapabilityService) -> String {
        #if os(iOS) && !targetEnvironment(macCatalyst)
            return deviceService.formFactor.deviceNoun
        #else
            return "Mac"
        #endif
    }

    private var gpuModeName: String {
        DeviceCapabilityService.shared.activeGPUExecutionProfile.displayName
    }

    private var gpuModeColor: Color {
        gpuModeColor(for: DeviceCapabilityService.shared.activeGPUExecutionProfile)
    }

    private func gpuModeColor(for profile: GPUExecutionProfile) -> Color {
        switch profile {
        case .efficiency: return .secondary
        case .balanced: return .accentColor
        case .performance: return .orange
        case .maximum: return .red
        }
    }

    @ViewBuilder
    private func gpuSettingRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            // One line each, shrinking before wrapping (5.8): "Embedding model, searching" and its value wrapped to two
            // lines in some profiles and one in others, so the rows under the Compute Profile card moved when the
            // profile changed (the owner's iPhone, 2026-11-10).
            Text(label)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)
            Spacer(minLength: DSSpacing.sm)
            Text(value)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(height: 20)
    }

}
