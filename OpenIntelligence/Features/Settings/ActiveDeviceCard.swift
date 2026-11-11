//
//  ActiveDeviceCard.swift
//  OpenIntelligence
//
//  The Active Device card in Device & Performance (5.8): what this device is and what it reports, every value with
//  where it came from, and under a fold what the app sets for it.
//
//  Through 5.7 this card showed a Neural Engine figure for every chip (Apple publishes one for ten: A14, A15, A16, M1, M1 Ultra, M2, M2 Pro, M2 Max, M2 Ultra, M4), "Active
//  cooling" on an iPad Pro, a "Thermal: High" pill that was a fixed guess by device type, a capability tier named
//  like the answer modes, memory rounded to a whole number the device never reported, and a Hardware Envelope with
//  two batch sizes nothing reads, a per-page memory figure for a page much larger than a letter page and a "GPU
//  Ceiling" percentage the Compute Profile no longer has. Each tile now names its source: the hardware (Metal, the
//  system), Apple's published figure, Xcode's device database, or the live state.
//

import SwiftUI

#if canImport(FoundationModels)
    import FoundationModels
#endif

struct ActiveDeviceCard: View {
    /// Whether the fold of what the app sets is offered (Technical Details on).
    let showsInternals: Bool

    @State private var thermalState = ProcessInfo.processInfo.thermalState

    private var device: DeviceCapabilityService { .shared }

    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
            true
        #else
            false
        #endif
    }

    /// The system that reported a value, in its own name.
    private var systemName: String {
        #if os(macOS)
            return "macOS"
        #else
            if ProcessInfo.processInfo.isiOSAppOnMac { return "macOS" }
            return device.isIPad ? "iPadOS" : "iOS"
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            header
            tiles
            if showsInternals {
                FoldedDetails(title: "What the app sets for this device") {
                    internals
                }
            }
        }
        .padding(DSSpacing.md)
        .background(DSColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            thermalState = ProcessInfo.processInfo.thermalState
        }
    }

    // MARK: Header

    private var header: some View {
        // The shared section header, its badge Apple Intelligence's live state (5.8), then the model.
        let (text, ready) = Self.intelligenceState()
        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            SettingsSectionHeader(
                icon: device.isMac ? "laptopcomputer" : (device.isIPad ? "ipad" : "iphone"), title: "Active Device",
                badge: text, badgeColor: ready ? .accentColor : .secondary)
            Text(device.modelName ?? device.formFactor.deviceNoun)
                .scaledFont(size: 12, weight: .bold, design: .monospaced)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityLabel("Model: \(device.modelName ?? device.formFactor.deviceNoun)")
        }
    }

    /// Apple Intelligence as the model reports it now (`SystemLanguageModel.default.availability`), not the device's
    /// tier: the badge used to show the app's own tier name ("Standard", "Enhanced", "Ultimate").
    static func intelligenceState() -> (String, Bool) {
        #if canImport(FoundationModels)
            switch SystemLanguageModel.default.availability {
            case .available:
                return ("Apple Intelligence", true)
            case .unavailable(.deviceNotEligible):
                return ("Not supported", false)
            case .unavailable(.appleIntelligenceNotEnabled):
                return ("Apple Intelligence off", false)
            case .unavailable(.modelNotReady):
                return ("Model not ready", false)
            case .unavailable:
                return ("Model unavailable", false)
            }
        #else
            return ("Model unavailable", false)
        #endif
    }

    // MARK: Tiles

    private struct Tile: Identifiable {
        let id: String
        let icon: String
        let value: String
        let source: String
    }

    private var tileList: [Tile] {
        // Each caption names the source actually used (5.8 reviews). In the Simulator, memory, CPU and the GPU are the
        // Mac's, and the captions say so.
        let fromMetal = AppleDeviceCatalog.chipName(fromMetalDeviceName: device.metalSnapshot.deviceName) == device.chipName
        let chipSource: String = {
            if isSimulator { return "simulated device" }
            if !device.chipIdentified { return "not reported" }
            return fromMetal ? "Metal reports" : (device.isMac ? "macOS reports" : "Apple's specs")
        }()
        let hostSource = isSimulator ? "the Mac running it" : "\(systemName) reports"
        let clusters = device.cpuClusters
        let cpuValue =
            clusters.isEmpty
            ? "\(ProcessInfo.processInfo.processorCount) threads"
            : clusters.map { "\($0.cores)" }.joined(separator: " + ") + " cores"
        let cpuSource = isSimulator ? hostSource : (clusters.isEmpty ? hostSource : clusters.map(\.name).joined(separator: " + "))
        let tops = device.npuTopsDescription
        let intel = device.chipName.contains("Intel")
        let workingSet = device.metalSnapshot.recommendedWorkingSetMB > 0 ? device.metalSnapshot.workingSetDescription : "Unavailable"
        return [
            Tile(id: "Chip", icon: "cpu", value: device.chipDisplayName, source: chipSource),
            Tile(id: "Memory", icon: "memorychip", value: device.memoryDescription, source: hostSource),
            Tile(id: "CPU", icon: "square.grid.2x2", value: cpuValue, source: cpuSource),
            Tile(
                id: "Neural Engine", icon: "brain", value: intel ? "None" : (tops ?? "No figure"),
                source: intel ? "Intel chip" : (tops == nil ? "Apple publishes none" : "Apple's figure")),
            Tile(
                id: "GPU budget", icon: "square.stack.3d.up", value: workingSet,
                source: isSimulator ? "the Mac's GPU" : "Metal's working set"),
            // Thermals moved to the Live System Monitor below (5.8): this card is what the hardware is, that one what
            // it is doing.
            Tile(
                id: "GPU family", icon: "square.grid.3x3",
                value: device.metalSnapshot.highestAppleFamily.map { "Apple \($0)" } ?? "None",
                source: isSimulator ? "the Mac's GPU" : (device.metalSnapshot.highestAppleFamily == nil ? "no Apple GPU family" : "Metal reports")),
        ]
    }

    private var tiles: some View {
        LazyVGrid(columns: SpecTile.columns, spacing: DSSpacing.xs) {
            ForEach(tileList) { tile in
                SpecTile(name: tile.id, value: tile.value, icon: tile.icon, caption: tile.source)
            }
        }
    }

    private var internals: some View {
        let envelope = device.hardwareExecutionEnvelope
        let metal = envelope.metal
        let maximum = device.isMaximumFidelityActive
        // The thermal limit applies on a Mac only (`VisionOCRThrottle.currentVisionConcurrencyLimit`).
        let textRecognition = device.isMac
            ? DeviceCapabilityService.thermallyLimitedVisionConcurrency(
                ceiling: envelope.visionOperationConcurrency, thermalState: thermalState)
            : envelope.visionOperationConcurrency
        let coreAI = EmbeddingProviderDefaults.preferredSentenceProviderId == EmbeddingProviderDefaults.coreAI
        let deepThink = Int(device.optimizedAgenticConfig().confidenceThreshold * 100)
        return VStack(alignment: .leading, spacing: DSSpacing.sm) {
            section("THE HARDWARE REPORTS") {
                row("Device ID", device.isMac && !isSimulator ? (DeviceCapabilityService.macModelIdentifier() ?? envelope.deviceIdentifier) : envelope.deviceIdentifier)
                row("Metal device", metal.deviceName)
                row("Unified memory", metal.hasUnifiedMemory ? "Yes" : "No")
                row("Threadgroup", "\(metal.maxThreadsPerThreadgroup) threads • \(metal.maxThreadgroupMemoryKB) KB")
            }
            section("THE APP SETS") {
                // The embedding model's request; the reranker always asks for the CPU and Neural Engine (5.8 review).
                row("Search embedding asks for", coreAI ? "Core AI, GPU" : envelope.coreMLRoute)
                row("Import embedding asks for", coreAI ? "Core AI, GPU" : envelope.embeddingRoute)
                row("Reranker asks for", "CPU + Neural Engine")
                row("Text recognition", "up to \(textRecognition) at once • \(envelope.visionCooldownMilliseconds) ms pause")
                row("Page images held", "up to \(envelope.pdfRenderSlots)")
                row("Page detail", maximum ? "432 DPI for recognised pages" : "360 DPI, 432 for hard pages")
                row("Search", envelope.batchMatrixMultiplyThreshold == Int.max
                    ? "one passage at a time" : "one matrix pass from \(envelope.batchMatrixMultiplyThreshold) passages")
                row("Reranked", "up to \(device.activeDepth.rerankCeiling) per pass")
                row("Deep Think's chain aims for", "\(deepThink)% confidence")
            }
            Text(
                "Core ML decides where each layer runs; the app states a preference. Apple offers no way to read Neural Engine use."
            )
            .scaledFont(size: 9, weight: .regular)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .scaledFont(size: 9, weight: .semibold, design: .monospaced)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.sm) {
            Text(label)
                .scaledFont(size: 11, weight: .medium)
                .lineLimit(1)
            Spacer(minLength: DSSpacing.xs)
            Text(value)
                .scaledFont(size: 10, weight: .regular, design: .monospaced)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }
}
