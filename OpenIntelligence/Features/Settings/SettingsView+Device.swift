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
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(Color.accentColor)
                Text("Active Device")
                    .font(.headline)
                Spacer()

                // Device tier badge
                Text(deviceService.tier.displayName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.xs)
                    .background(tierColor(for: deviceService.tier).opacity(0.15))
                    .foregroundStyle(tierColor(for: deviceService.tier))
                    .clipShape(Capsule())
            }

            // Chip & Memory info (dynamic)
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: "cpu")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    Text(deviceService.chipName)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(String(format: "%.0f", deviceService.memoryGB)) GB RAM")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // The first figure a curious user meets in Settings, and the one most
                // likely to be mistaken for a live measurement. Its definition says
                // plainly that it is a per-chip lookup rather than something the app
                // measured here.
                if settings.showTechnicalDetails {
                    HStack(spacing: DSSpacing.xs) {
                        Text("Neural Engine: \(deviceService.npuTops) TOPS • \(coolingDescription)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        GlossaryInfoButton(termID: .tops, size: .caption2)
                        Spacer(minLength: 0)
                    }
                }

                HStack(spacing: DSSpacing.md) {
                    // Was "\(maxSteps) max sessions": 5 on an iPhone 15 Pro and 13 on an 18 GB M3 Pro, while Deep Think's
                    // chain stops at 8 sessions on every device (`AgenticPolicyService.maxSessionsForMode`). What does
                    // differ by device is the confidence it aims for (`optimizedAgenticConfig`) (5.7).
                    deviceCapabilityPill(icon: "brain.head.profile", label: "Deep Think", value: "aims for \(Int(deviceService.optimizedAgenticConfig().confidenceThreshold * 100))%")
                    deviceCapabilityPill(icon: "flame", label: "Thermal", value: deviceService.hasThermalHeadroom ? "High" : "Standard")
                }
            }
            .padding(DSSpacing.md)
            .background(DSColors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))

            Divider()

            // Device ID, Metal ceilings and Core ML routes: internals, with Technical Details on (5.7).
            if settings.showTechnicalDetails {
                hardwareEnvelopeSection(deviceService: deviceService)

                Divider()
            }

            // Context Window
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: "ruler")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    Text(settings.showTechnicalDetails ? "Context Window" : "How Much the Model Reads")
                        .font(.subheadline.weight(.medium))
                }

                // Dynamic explanation based on mode
                let agenticConfig = DeviceCapabilityService.shared.optimizedAgenticConfig()
                if settings.ragQualityMode.canonical == .maximum {
                    // Corrected 2026-10-15: the window is the one this device reports (8,192 on the owner's Mac,
                    // not 4K), "exhaustive Neural Engine synthesis" named hardware the app can't see, and Self-RAG 2.0
                    // is Maximum's check of the answer against its sources (`AgenticOrchestrator`), not what passes
                    // between sessions.
                    Text(
                        settings.showTechnicalDetails
                            ? "Maximum chains several reasoning sessions on Apple's model, each with a fresh window (\(onDeviceWindowDescription) on this device) carrying compressed findings from the last, and then checks the answer against its sources (Self-RAG 2.0)."
                            : "Maximum asks Apple's model several times in a row, each time with room for \(onDeviceWindowDescription) on this device and a summary of what it found before, then checks the answer against your documents.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if settings.ragQualityMode.canonical == .deepThink {
                    Text(
                        settings.showTechnicalDetails
                            ? "Deep Think's reasoning chain runs up to 8 sessions in a row on Apple's model, each with a fresh window (\(onDeviceWindowDescription) on this device) carrying compressed insights from the last, and research rounds can follow it when parts of the question are still uncovered. On the \(DeviceCapabilityService.shared.chipName) it aims for \(Int(agenticConfig.confidenceThreshold * 100))% confidence, and from the fifth session it can stop early once it has that confidence, has covered the question's parts and stops finding anything new."
                            : "Deep Think asks Apple's model up to 8 times in a row, each time with room for \(onDeviceWindowDescription) on this device and a summary of what it found before, and it can search again for parts of the question it hasn't covered. On the \(DeviceCapabilityService.shared.chipName) it aims to be \(Int(agenticConfig.confidenceThreshold * 100))% sure, and from the fifth time it can stop once it is, has covered the question and isn't finding anything new.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(
                        settings.showTechnicalDetails
                            ? "Standard runs one pass of Apple's model over the passages that fit its window (\(onDeviceWindowDescription) on this device), with verification gates and graph context packing. Use Deep Think or Maximum when you want several reasoning sessions."
                            : "Standard asks Apple's model once, with the passages that fit in \(onDeviceWindowDescription) on this device, and checks the answer against them. Deep Think and Maximum ask several times.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: DSSpacing.md) {
                    if settings.ragQualityMode.canonical == .maximum {
                        contextInfoPill(icon: "square.3.layers.3d", label: settings.showTechnicalDetails ? "Per Session" : "Each Time", value: onDeviceWindowDescription)
                        contextInfoPill(icon: "checkmark.seal", label: "Answer Check", value: settings.showTechnicalDetails ? "Self-RAG 2.0" : "Against your documents")
                    } else if settings.ragQualityMode.canonical == .deepThink {
                        contextInfoPill(icon: "square.3.layers.3d", label: settings.showTechnicalDetails ? "Per Session" : "Each Time", value: onDeviceWindowDescription)
                        contextInfoPill(icon: "arrow.trianglehead.2.clockwise.rotate.90", label: settings.showTechnicalDetails ? "Chain" : "Times", value: settings.showTechnicalDetails ? "up to 8 sessions" : "up to 8")
                    } else {
                        // "If Complex: 3 sessions (12K)" was untrue: Standard chains sessions only when a developer
                        // turns on `forceReasoningChain` (RAGService, `useReasoningChain`).
                        contextInfoPill(icon: "square.3.layers.3d", label: settings.showTechnicalDetails ? "Single Pass" : "Room", value: onDeviceWindowDescription)
                        contextInfoPill(icon: "arrow.trianglehead.2.clockwise.rotate.90", label: settings.showTechnicalDetails ? "Sessions" : "Times", value: "1")
                    }
                }
            }
            .padding(DSSpacing.md)
            .background(DSColors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
            .animation(DSAnimations.fastEase, value: settings.ragQualityMode)

            Divider()

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

    private func tierColor(for tier: DeviceCapabilityTier) -> Color {
        switch tier {
        case .unsupported: return .secondary
        case .baseline: return .secondary
        case .enhanced: return .accentColor
        case .advanced: return .accentColor
        case .ultraAdvanced: return .accentColor
        }
    }

    @ViewBuilder
    private func deviceCapabilityPill(icon: String, label: String, value: String) -> some View {
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

            @ViewBuilder
            private func hardwareEnvelopeSection(deviceService: DeviceCapabilityService) -> some View {
                let envelope = deviceService.hardwareExecutionEnvelope
                let minImageBudgetMB = envelope.pdfPageMemory360MB * envelope.pdfRenderSlots
                let maxImageBudgetMB = envelope.pdfPageMemory432MB * envelope.pdfRenderSlots
                let imageBudgetText = "\(envelope.pdfRenderSlots) pages • ~\(minImageBudgetMB)-\(maxImageBudgetMB) MB @ adaptive 360-432 DPI"
                let gpuCeilingText: String = {
                    if envelope.activeGPUAccelerationLevel < envelope.requestedGPUAccelerationLevel {
                        return "\(Int(envelope.activeGPUAccelerationLevel * 100))% active of \(Int(envelope.requestedGPUAccelerationLevel * 100))% requested"
                    }
                    return "Up to \(Int(envelope.maxSafeGPUAccelerationLevel * 100))% safe on this device"
                }()

                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    HStack(spacing: DSSpacing.sm) {
                        Image(systemName: "cpu.fill")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                        Text("Hardware Envelope")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("Core ML + Metal")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, DSSpacing.sm)
                            .padding(.vertical, DSSpacing.xxs)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    Text("These ceilings come from public hardware signals the app can inspect safely: device ID, chip mapping, RAM, Metal working-set budget, threadgroup limits, and crash-tested Vision/Core ML guardrails. Apple does not expose live Neural Engine occupancy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // This is the densest jargon in the app, and it is reached by anyone
                    // curious enough to open Device & Performance rather than only by
                    // developers. The rows that name a concept carry its definition; the
                    // rows that report a raw system value do not, because there is nothing
                    // to define about a Metal device name.
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        hardwareLimitRow(icon: "number", label: "Device ID", value: envelope.deviceIdentifier, term: .chip)
                        hardwareLimitRow(icon: "memorychip", label: "Metal Device", value: envelope.metal.deviceName)
                        hardwareLimitRow(icon: "square.stack.3d.up", label: "Unified Memory", value: "\(envelope.metal.hasUnifiedMemory ? "Yes" : "No") • \(envelope.metal.workingSetDescription) working set", term: .unifiedMemory)
                        hardwareLimitRow(icon: "square.grid.3x3.fill", label: "Threadgroup Ceiling", value: "\(envelope.metal.maxThreadsPerThreadgroup) threads • \(envelope.metal.maxThreadgroupMemoryKB) KB shared")
                        hardwareLimitRow(icon: "gauge.with.needle", label: "GPU Ceiling", value: gpuCeilingText, term: .gpuProfile)
                        hardwareLimitRow(icon: "cpu", label: "CoreML Route", value: envelope.coreMLRoute, term: .neuralEngine)
                        hardwareLimitRow(icon: "text.badge.checkmark", label: "Embedding Route", value: envelope.embeddingRoute, term: .vector)
                        hardwareLimitRow(icon: "eye.fill", label: "Vision / ADM 3 Ceiling", value: "\(envelope.visionOperationConcurrency) ops • \(envelope.visionCooldownMilliseconds) ms cooldown", term: .ocr)
                        hardwareLimitRow(icon: "photo.stack", label: "Adaptive PDF Budget", value: imageBudgetText, term: .ocr)
                        hardwareLimitRow(icon: "function", label: "Vector Search Ceiling", value: "\(envelope.vectorBatchSize) batch • matrix @ \(envelope.batchMatrixMultiplyThreshold)+", term: .searchBatch)
                    }
                }
                .padding(DSSpacing.md)
                .background(DSColors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
            }

            @ViewBuilder
            private func hardwareLimitRow(icon: String, label: String, value: String, term: GlossaryTermID? = nil) -> some View {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: icon)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(label)
                        .font(.caption.weight(.medium))
                    if let term {
                        GlossaryInfoButton(termID: term, size: .caption2)
                    }
                    Spacer()
                    Text(value)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
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

    @ViewBuilder
    private func neuralEngineInfoRow(icon: String, label: String) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - Silicon-Native RAG Engine Section

    @ViewBuilder
    private func siliconNativeRAGSection(deviceService: DeviceCapabilityService) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            // Header
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "bolt.horizontal.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Text("Silicon-Native RAG Engine")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("Accelerate")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.xxs)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
            }

            // "4x faster" removed 2026-08-06. No benchmark supporting it exists in
            // `Benchmarks/` or the evaluation docs, same class as the `1,000x` dedup and
            // `240x` scrolling figures withdrawn in this release. The GPU path is real;
            // the multiplier was never measured.
            // "GPU level ≥ 60%" named a percentage the GPU setting no longer shows; the gate is
            // `searchesLargeLibrariesOnGPU(for:)` with the stores' own thresholds (5.7).
            Text("Vector math uses Apple's Accelerate framework (vDSP/BLAS) on the CPU. With the GPU setting on Performance or Maximum, Metal shaders take over cosine similarity for a library of 1,000 passages or more and the diversity step for more than 50 results. Batch sizes are set for the \(deviceService.chipName).")
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
                    detail: "3-tier: threadgroup/SIMD4/scalar"
                )
                siliconFeatureRow(
                    icon: "text.line.first.and.arrowtriangle.forward",
                    label: "Semantic Chunking",
                    detail: "Topic boundaries via embeddings"
                )
                siliconFeatureRow(
                    icon: "lock.fill",
                    label: "Library Isolation",
                    detail: "Queries stay scoped to the active library"
                )
            }

            // Batch size info
            HStack(spacing: DSSpacing.md) {
                siliconInfoPill(
                    icon: "square.stack.3d.up",
                    label: "Vector Batch",
                    value: "\(deviceService.vectorBatchSize)",
                    term: .searchBatch
                )
                siliconInfoPill(
                    icon: "text.badge.checkmark",
                    label: "Embed Batch",
                    value: "\(deviceService.embeddingBatchSize)",
                    term: .embedBatch
                )
                siliconInfoPill(
                    icon: "square.grid.3x3.fill",
                    label: "Matrix @",
                    value: "\(deviceService.batchMatrixMultiplyThreshold)+"
                )
            }
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

    @ViewBuilder
    private func siliconInfoPill(icon: String, label: String, value: String, term: GlossaryTermID? = nil) -> some View {
        let pill = HStack(spacing: DSSpacing.xs) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2)
            Text(value)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .background(Color.accentColor.opacity(0.15))
        .clipShape(Capsule())

        if let term {
            pill
                .contentShape(Capsule())
                .definedTerm(term)
        } else {
            pill
        }
    }

    // MARK: - GPU Acceleration Section


    private func gpuAccelerationSection(deviceService: DeviceCapabilityService) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            // Header
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "cpu")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                // "GPU Acceleration" until 5.8: the profiles move work between the CPU, the Neural Engine and the GPU.
                Text("Compute Profile")
                    .font(.subheadline.weight(.medium))
                Spacer()

                // Mode badge
                Text(gpuModeName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(gpuModeColor)
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.xxs)
                    .background(gpuModeColor.opacity(0.15))
                    .clipShape(Capsule())
            }

            // Until 5.7: "Choose how OpenIntelligence schedules GPU-capable work...". The profiles cover the Core ML
            // embedding model, the Core Image cleanup of scanned pages and Metal vector search, never Apple's model.

            if deviceService.activeGPUExecutionProfile != gpuProfile {
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.caption)
                        .foregroundStyle(DSColors.readable(.orange))
                    Text("On the \(deviceService.chipName), \(gpuProfile.displayName) runs as \(deviceService.activeGPUExecutionProfile.displayName), to keep long imports stable.")
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
                    chipName: deviceService.chipName,
                    backgroundGPUProfiles: computeBackgroundGPUProfiles(deviceService),
                    systemOffersBackgroundGPU: computeSystemOffersBackgroundGPU,
                    deviceNoun: computeDeviceNoun(deviceService),
                    backgroundNote: { backgroundImportNote(for: $0, deviceService: deviceService) },
                    concurrency: ComputeProfileCard.Concurrency(
                        visionParsingPages: deviceService.visionParsingConcurrency,
                        ocrPages: deviceService.ocrExtractionConcurrency,
                        renderSlots: deviceService.pdfRenderingConcurrency,
                        embeddingParallel: deviceService.embeddingConcurrency),
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
            Text("Applies from the next import, and to searching from the next launch.")
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
                        ? "PDFs and images now use one automatic source-preservation strategy. The engine raises OCR detail, structure recovery, and visual analysis when pages are garbled, table-heavy, columnar, image-heavy, or small-text risky, and stays lighter on clean text-native pages."
                        : "A PDF page or an image gets a closer reading when it needs one: text that comes out garbled, tables, columns, pictures or small print. A page whose text is already clean gets a lighter one."
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
                    value: deviceService.preferredComputeUnitsDescription
                )
                gpuSettingRow(
                    icon: "cube.transparent",
                    label: "Embedding, importing",
                    value: deviceService.embeddingComputeUnitsDescription
                )
                gpuSettingRow(
                    icon: "doc.text.image",
                    label: "Extra PDF page pass",
                    value: deviceService.useGPUForPDFRendering ? "On, Core Image on the GPU" : "Off"
                )
                gpuSettingRow(
                    icon: "function",
                    label: "Large searches",
                    value: deviceService.useMetalForVectorOps ? "Metal on the GPU" : "Accelerate on the CPU"
                )
            }
            .animation(DSAnimations.fastEase, value: gpuProfile)

            Divider()
                .padding(.vertical, DSSpacing.xxs)

            // Pipeline concurrency remains tier-based rather than profile-controlled.
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text("Pipeline Concurrency")
                    .font(.subheadline.weight(.medium))
                Text("Set by the \(deviceService.chipName). Maximum holds fewer pages at once, to fit full-detail pages.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                gpuSettingRow(
                    icon: "doc.text.image",
                    label: "Vision Parsing",
                    value: "\(deviceService.visionParsingConcurrency) pages"
                )
                gpuSettingRow(
                    icon: "waveform",
                    label: "OCR Extraction",
                    value: "\(deviceService.ocrExtractionConcurrency) pages"
                )
                gpuSettingRow(
                    icon: "photo.stack",
                    label: "PDF Render Slots",
                    value: "\(deviceService.pdfRenderingConcurrency) concurrent "
                        + (deviceService.isMaximumFidelityActive ? "(432 DPI)" : "(adaptive 360/432 DPI)")
                )
                gpuSettingRow(
                    icon: "cube.transparent",
                    label: "Embedding",
                    value: "\(deviceService.embeddingConcurrency) parallel"
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
            guard BackgroundTaskService.shared.systemOffersBackgroundGPU else {
                return "In the background, iOS doesn't offer this \(noun) the GPU, so an import goes on there without it."
            }
            guard !admitting.isEmpty else {
                return "In the background, no profile asks iOS to keep the GPU for an import on this \(noun)."
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
                return "In the background, \(profile.displayName) doesn't ask iOS to keep the GPU for an import on this \(noun). \(names) \(verb), \(when)."
            }
            return "In the background, an import asks iOS to keep the GPU \(when), unless Low Power Mode is on, the \(noun) is hot, memory is short or iOS has asked apps to use less."
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
