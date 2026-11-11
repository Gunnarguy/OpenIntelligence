//
//  ComputeProfileCard.swift
//  OpenIntelligence
//
//  The compute profile as a chip whose parts light up, a four-step ladder, what each step adds, and every job the
//  setting covers with exactly what runs it (5.8). It replaced a "GPU Acceleration" card of four buttons and a list of
//  sentences: the setting moves work between the CPU, the Neural Engine and the GPU, not only onto the GPU, and the
//  owner asked (2026-11-10) to see each step turn more on and to be shown exactly what the code does in each mode.
//
//  Every cell and every line under the hood is read from the rules the app runs on
//  (`DeviceCapabilityService.coreMLComputeUnits(for:)`, `embeddingComputeUnits(for:)`, `cleansScannedPagesOnGPU(for:)`,
//  `searchesLargeLibrariesOnGPU(for:)`, the background GPU allowance) or restates a fixed rule with its source
//  (`BNNSVectorDatabase`'s 1,000-passage Metal threshold, `RAGEngine.applyMMR`'s 50, the reranker's
//  `.cpuAndNeuralEngine`), so the card cannot say more than the code does.
//

import CoreML
import SwiftUI

struct ComputeProfileCard: View {
    @Binding var profile: GPUExecutionProfile
    let chipName: String
    /// Profiles that ask iOS to keep the GPU for an import in the background on this device.
    let backgroundGPUProfiles: [GPUExecutionProfile]
    /// Whether iOS offers this device the GPU in the background at all.
    let systemOffersBackgroundGPU: Bool
    let deviceNoun: String
    /// What an import in the background does with a profile on this device, in words (Settings' own rule text).
    let backgroundNote: (GPUExecutionProfile) -> String
    /// Pages and passages a job does at once under each profile (`DeviceCapabilityService.concurrency(for:)`): Efficiency
    /// takes half the chip's ceiling (5.8).
    let concurrencyFor: (GPUExecutionProfile) -> Concurrency
    var onSelect: (GPUExecutionProfile) -> Void

    struct Concurrency {
        let visionParsingPages: Int
        let ocrPages: Int
        let renderSlots: Int
        let embeddingParallel: Int
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded: String?
    @State private var showsFixed = false
    /// Bumped on every profile change, for the chip's sweep.
    @State private var sweep = 0

    // MARK: - Model

    enum Chip: String, CaseIterable, Identifiable {
        case cpu, neuralEngine, gpu
        var id: String { rawValue }

        var name: String {
            switch self {
            case .cpu: return "CPU"
            case .neuralEngine: return "Neural Engine"
            case .gpu: return "GPU"
            }
        }

        var shortName: String {
            switch self {
            case .cpu: return "CPU"
            case .neuralEngine: return "ANE"
            case .gpu: return "GPU"
            }
        }

        var symbol: String {
            switch self {
            case .cpu: return "cpu"
            case .neuralEngine: return "brain"
            case .gpu: return "square.grid.3x3.fill"
            }
        }

        /// The X-Ray's and the Silicon HUD's colors, so one chip reads the same everywhere.
        var color: Color {
            switch self {
            case .cpu: return HardwareComponent.cpu.color
            case .neuralEngine: return HardwareComponent.neuralEngine.color
            case .gpu: return HardwareComponent.gpu.color
            }
        }
    }

    struct Workload: Identifiable, Equatable {
        let id: String
        let name: String
        let icon: String
        let chips: Set<Chip>
        /// One line on what runs it, under the hood: framework and setting.
        let engine: String
        /// What it does in this profile, in plain words, with the code's thresholds.
        let detail: String
        /// Shown under the row, when the row cannot apply on this device.
        let note: String?
    }

    static func chips(_ units: MLComputeUnits) -> Set<Chip> {
        switch units {
        case .all: return [.cpu, .neuralEngine, .gpu]
        case .cpuAndNeuralEngine: return [.cpu, .neuralEngine]
        case .cpuAndGPU: return [.cpu, .gpu]
        case .cpuOnly: return [.cpu]
        @unknown default: return [.cpu]
        }
    }

    static func unitsName(_ units: MLComputeUnits) -> String {
        switch units {
        case .all: return ".all"
        case .cpuAndNeuralEngine: return ".cpuAndNeuralEngine"
        case .cpuAndGPU: return ".cpuAndGPU"
        case .cpuOnly: return ".cpuOnly"
        @unknown default: return "unknown"
        }
    }

    func workloads(for profile: GPUExecutionProfile) -> [Workload] {
        let concurrency = concurrencyFor(profile)
        let depth = DeviceCapabilityService.Depth.forProfile(profile)
        let deeper = depth != .standard
        let searching = DeviceCapabilityService.coreMLComputeUnits(for: profile)
        let importing = DeviceCapabilityService.embeddingComputeUnits(for: profile)
        let cleanup = DeviceCapabilityService.cleansScannedPagesOnGPU(for: profile)
        let large = DeviceCapabilityService.searchesLargeLibrariesOnGPU(for: profile)
        let backgroundGPU = systemOffersBackgroundGPU && backgroundGPUProfiles.contains(profile)
        return [
            Workload(
                id: "search", name: "Search by meaning", icon: "magnifyingglass", chips: Self.chips(searching),
                engine: "Core ML, MLComputeUnits \(Self.unitsName(searching))",
                detail: "Each question is turned into a 384-number embedding by the app's embedding model. Core ML may "
                    + "place each of its layers on \(GPUExecutionProfile.chipNames(searching)), and picks the fastest."
                    + (deeper
                        ? " \(profile.displayName) also reranks up to \(depth.rerankCeiling) passages (250 in Balanced) and takes up to \(depth.keywordLimit) keyword results (60)"
                            + (profile == .maximum ? ", and loads its models for prediction speed." : ".")
                        : ""),
                note: nil),
            Workload(
                id: "import", name: "Import documents", icon: "square.and.arrow.down", chips: Self.chips(importing),
                engine: "Core ML, MLComputeUnits \(Self.unitsName(importing))",
                detail: "Every passage of a new document is embedded, \(concurrency.embeddingParallel) at a time, on "
                    + "\(GPUExecutionProfile.chipNames(importing)). How many at a time is set by the \(chipName)"
                    + (profile == .efficiency ? "; Efficiency takes half, so an import runs cooler and slower with the same result." : ".")
                    + (profile == .performance
                        ? " Performance re-reads up to \(depth.rescueRegions) hard regions a page (12 in Balanced). It steps down while the device is hot, in Low Power Mode or in the background."
                        : "")
                    + (profile == .maximum
                        ? " Maximum draws every page that text recognition reads at 432 DPI (360 otherwise, 432 only for hard pages), runs the layout pass at full size, re-reads up to \(depth.rescueRegions) hard regions a page (12 in Balanced), and holds \(concurrency.renderSlots) pages at once to fit them. It steps down while the device is hot, in Low Power Mode or in the background."
                        : ""),
                note: nil),
            Workload(
                id: "cleanup", name: "Scanned-page cleanup", icon: "doc.viewfinder",
                chips: cleanup ? [.gpu] : [],
                engine: cleanup ? "Core Image on a Metal context" : "Off",
                detail: cleanup
                    ? "After a PDF page is drawn (on the CPU), Core Image runs an extra cleanup on the GPU: sharpening and "
                        + "contrast chosen for the page, before text recognition reads it."
                    : "No extra pass: a page goes to text recognition as drawn. Text recognition still prepares each "
                        + "page on the GPU, as in every profile.",
                note: nil),
            Workload(
                id: "large", name: "Large searches (1,000+)", icon: "square.stack.3d.up",
                chips: large ? [.gpu] : [.cpu],
                engine: large ? "Metal compute on the GPU" : "Accelerate on the CPU",
                detail: large
                    ? "The vector search runs on the GPU once a library holds 1,000 passages or more, and so does the "
                        + "diversity step once a search keeps more than 50 results. Smaller ones stay on the CPU."
                    : "Every vector search and diversity step runs on the CPU with Accelerate, however large the library.",
                note: nil),
            Workload(
                id: "background", name: "GPU in the background", icon: "moon.zzz",
                chips: backgroundGPU ? [.gpu] : [],
                engine: backgroundGPU ? "Continued processing task with the GPU resource" : "No GPU in the background",
                detail: backgroundNote(profile),
                note: systemOffersBackgroundGPU ? nil : "iOS doesn't offer this \(deviceNoun) the GPU in the background."
            ),
        ]
    }

    private var current: [Workload] { workloads(for: profile) }

    /// The profile one step down, whose chips this one adds to.
    private var previous: GPUExecutionProfile? {
        let all = GPUExecutionProfile.allCases
        guard let index = all.firstIndex(of: profile), index > 0 else { return nil }
        return all[index - 1]
    }

    /// Per row, the chips this profile turns on that the one below it does not.
    private var added: [String: Set<Chip>] {
        guard let previous else { return [:] }
        let before = Dictionary(uniqueKeysWithValues: workloads(for: previous).map { ($0.id, $0.chips) })
        var result: [String: Set<Chip>] = [:]
        for row in current {
            let new = row.chips.subtracting(before[row.id] ?? [])
            if !new.isEmpty { result[row.id] = new }
        }
        return result
    }

    /// How many of the jobs a chip may run in this profile.
    private func jobs(on chip: Chip) -> Int {
        current.filter { $0.chips.contains(chip) }.count
    }

    static func color(for profile: GPUExecutionProfile) -> Color {
        switch profile {
        case .efficiency: return .secondary
        case .balanced: return .accentColor
        case .performance: return .orange
        case .maximum: return .red
        }
    }

    // MARK: - Body

    var body: some View {
        // Every part keeps its height from one profile to the next, so switching moves nothing on screen and only
        // what changes, changes (the owner, 2026-11-10: "it jumps around when I tap each different mode").
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            die
            ladder
            Text(profile.engagement.summary)
                .scaledFont(size: 11)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
            addsBanner
            jobsList
            intensityGrid
            sameEverywhere
        }
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82), value: profile)
        .animation(reduceMotion ? nil : .snappy, value: expanded)
        .onChange(of: profile) { sweep += 1 }
    }

    // MARK: The chip

    /// The chip itself: three parts that glow with how many of the jobs each one may run.
    private var die: some View {
        VStack(spacing: DSSpacing.xs) {
            HStack {
                Image(systemName: "memorychip")
                    .scaledFont(size: 11, weight: .semibold)
                Text(chipName)
                    .scaledFont(size: 12, weight: .bold, design: .monospaced)
                Spacer()
                Text(profile.displayName.uppercased())
                    .scaledFont(size: 10, weight: .heavy, design: .monospaced)
                    .foregroundStyle(
                        Self.color(for: profile) == .secondary ? Color.white.opacity(0.7) : Self.color(for: profile)
                    )
                    .contentTransition(.interpolate)
            }
            .foregroundStyle(Color.white.opacity(0.85))

            HStack(spacing: DSSpacing.sm) {
                ForEach(Chip.allCases) { chip in
                    chipBlock(chip)
                }
            }
        }
        .padding(DSSpacing.sm)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .fill(Color(white: 0.07))
                // Fine traces, like the die's wiring.
                Canvas { context, size in
                    var path = Path()
                    stride(from: 0, through: size.height, by: 9).forEach { y in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(path, with: .color(Color.white.opacity(0.035)), lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: Chip.allCases.filter { jobs(on: $0) > 0 }.map(\.color),
                        startPoint: .leading, endPoint: .trailing),
                    lineWidth: 1.2
                )
                .opacity(0.8)
        )
        .phaseAnimator(reduceMotion ? [0.0] : [0.0, 1.0, 0.0], trigger: sweep) { view, phase in
            view.brightness(phase * 0.08).scaleEffect(1 + phase * 0.01)
        } animation: { _ in
            .easeInOut(duration: 0.25)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(chipName), \(profile.displayName): "
                + Chip.allCases.map { "\($0.name) may run \(jobs(on: $0)) of \(current.count) jobs" }
                .joined(separator: ", "))
    }

    private func chipBlock(_ chip: Chip) -> some View {
        let count = jobs(on: chip)
        let share = Double(count) / Double(max(1, current.count))
        let on = count > 0
        return VStack(spacing: 3) {
            Image(systemName: chip.symbol)
                .scaledFont(size: 15, weight: .semibold)
                .foregroundStyle(on ? Color.white : chip.color.opacity(0.35))
                .symbolEffect(.bounce, value: count)
            Text(chip.name)
                .scaledFont(size: 10, weight: .bold)
                .foregroundStyle(on ? Color.white : Color.white.opacity(0.35))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            // One segment per job: lit for each job this chip may run.
            HStack(spacing: 2) {
                ForEach(0..<current.count, id: \.self) { index in
                    Capsule()
                        .fill(index < count ? chip.color : Color.white.opacity(0.12))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, DSSpacing.xs)
            Text("\(count) of \(current.count) jobs")
                .scaledFont(size: 9, weight: .semibold, design: .monospaced)
                .foregroundStyle(on ? Color.white.opacity(0.85) : Color.white.opacity(0.3))
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            chip.color.opacity(on ? 0.30 + 0.45 * share : 0.05), chip.color.opacity(on ? 0.10 : 0.02),
                        ],
                        center: .center, startRadius: 2, endRadius: 70))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                .strokeBorder(chip.color.opacity(on ? 0.95 : 0.2), lineWidth: 1)
        )
        .shadow(color: chip.color.opacity(on ? 0.25 + 0.5 * share : 0), radius: on ? 4 + 12 * share : 0)
    }

    // MARK: The ladder

    /// Four steps that rise and fill from left to right.
    private var ladder: some View {
        let all = GPUExecutionProfile.allCases
        let selectedIndex = all.firstIndex(of: profile) ?? 0
        return HStack(alignment: .bottom, spacing: DSSpacing.xs) {
            ForEach(Array(all.enumerated()), id: \.element) { index, step in
                let filled = index <= selectedIndex
                let isSelected = step == profile
                Button {
                    guard step != profile else { return }
                    DSHaptics.light()
                    onSelect(step)
                } label: {
                    VStack(spacing: DSSpacing.xxs) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(
                                filled
                                    ? AnyShapeStyle(
                                        LinearGradient(
                                            colors: [Self.color(for: step).opacity(0.55), Self.color(for: step)],
                                            startPoint: .bottom, endPoint: .top))
                                    : AnyShapeStyle(Color.secondary.opacity(0.14))
                            )
                            .frame(height: 6 + CGFloat(index) * 4)
                            .shadow(color: isSelected ? Self.color(for: step).opacity(0.6) : .clear, radius: 6)
                        Text(step.displayName)
                            .scaledFont(size: 10, weight: isSelected ? .bold : .medium)
                            .foregroundStyle(isSelected ? Self.color(for: step) : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(step.displayName) compute profile")
                .accessibilityHint(step.engagement.summary)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .sensoryFeedback(.selection, trigger: profile)
    }

    // MARK: What this step adds

    /// What this step adds over the one below, always shown and always the same height: a title and two lines.
    private var addsBanner: some View {
        let addedNow = added
        let lines = current.compactMap { row -> String? in
            guard let chips = addedNow[row.id] else { return nil }
            return "\(row.name): "
                + ListFormatter.localizedString(byJoining: Chip.allCases.filter { chips.contains($0) }.map(\.name))
        }
        let title: String
        let detail: String
        let symbol: String
        if profile == .maximum {
            // Maximum's extra is how hard each job runs, not which chips run it.
            title = "Maximum adds to Performance"
            detail = "Every page read at 432 DPI, layout at full size\nDeeper search: up to \(DeviceCapabilityService.MaximumFidelity.rerankCeiling) passages reranked"
            symbol = "bolt.circle.fill"
        } else if let previous {
            // What this step adds beyond chips (5.8): Balanced does twice Efficiency's work at once, Performance
            // searches and re-reads deeper. Two lines at most, chips first.
            let depth = DeviceCapabilityService.Depth.forProfile(profile)
            var extras: [String] = []
            if previous == .efficiency, concurrencyFor(profile).renderSlots > concurrencyFor(previous).renderSlots
                || concurrencyFor(profile).embeddingParallel > concurrencyFor(previous).embeddingParallel
            {
                extras.append("Twice as much at once: faster imports")
            }
            if depth != DeviceCapabilityService.Depth.forProfile(previous) {
                extras.append("Deeper search: up to \(depth.rerankCeiling) reranked, \(depth.rescueRegions) regions re-read")
            }
            let all = Array((lines + extras).prefix(2))
            title =
                all.isEmpty
                ? "On this \(deviceNoun), \(profile.displayName) runs exactly like \(previous.displayName)"
                : "\(profile.displayName) adds to \(previous.displayName)"
            detail =
                all.isEmpty
                ? "Every job uses the same chips and the same depth."
                : all.joined(separator: "\n")
            symbol = all.isEmpty ? "equal.circle.fill" : "plus.circle.fill"
        } else {
            title = "The base step"
            detail = "The CPU and the Neural Engine only. Each step to the right adds to it."
            symbol = "circle.dashed"
        }
        return HStack(alignment: .top, spacing: DSSpacing.sm) {
            Image(systemName: symbol)
                .foregroundStyle(Self.color(for: profile))
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .scaledFont(size: 11, weight: .semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .scaledFont(size: 11)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                .fill(Self.color(for: profile).opacity(0.10))
        )
    }

    // MARK: The jobs

    /// The jobs in two groups, when you ask and when you import, so it is plain which ones change answering and
    /// which ones change importing (the owner asked, 2026-11-10, whether the setting was for importing only).
    private var jobsList: some View {
        let addedNow = added
        let asking: Set<String> = ["search", "large"]
        return VStack(spacing: DSSpacing.xs) {
            phaseHeader("WHEN YOU ASK", showsChips: true)
            ForEach(current.filter { asking.contains($0.id) }) { row in
                jobRow(row, added: addedNow[row.id] ?? [])
            }
            phaseHeader("WHEN YOU IMPORT", showsChips: false)
            ForEach(current.filter { !asking.contains($0.id) }) { row in
                jobRow(row, added: addedNow[row.id] ?? [])
            }
        }
    }

    private func phaseHeader(_ title: String, showsChips: Bool) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Chip.allCases) { chip in
                Text(showsChips ? chip.shortName : "").frame(width: 36)
            }
        }
        .scaledFont(size: 9, weight: .semibold, design: .monospaced)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    private func jobRow(_ row: Workload, added: Set<Chip>) -> some View {
        let isOpen = expanded == row.id
        // In Maximum these two jobs run harder on the same chips.
        let deeper = profile == .maximum && (row.id == "search" || row.id == "import")
        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Button {
                expanded = isOpen ? nil : row.id
            } label: {
                HStack(spacing: 0) {
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: row.icon)
                            .scaledFont(size: 11)
                            .foregroundStyle(row.chips.isEmpty ? Color.secondary : Color.primary)
                            .frame(width: 16)
                        // One line per job in every profile: what a step adds shows as the ring and the tint.
                        Text(row.name)
                            .scaledFont(size: 12, weight: .semibold)
                            .foregroundStyle(row.chips.isEmpty ? Color.secondary : Color.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Image(systemName: "chevron.down")
                            .scaledFont(size: 8, weight: .bold)
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                        Image(systemName: "bolt.fill")
                            .scaledFont(size: 9, weight: .bold)
                            .foregroundStyle(Self.color(for: .maximum))
                            .opacity(deeper ? 1 : 0)
                            .accessibilityLabel(deeper ? "Runs harder in Maximum" : "")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Chip.allCases) { chip in
                        cell(chip, on: row.chips.contains(chip), isNew: added.contains(chip))
                            .frame(width: 36)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Label(row.engine, systemImage: "gearshape.2")
                        .scaledFont(size: 10, weight: .semibold, design: .monospaced)
                        .foregroundStyle(
                            Self.color(for: profile) == .secondary ? Color.primary : Self.color(for: profile))
                    Text(row.detail)
                        .scaledFont(size: 11)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let previous, let before = workloads(for: previous).first(where: { $0.id == row.id }),
                        before.chips != row.chips
                    {
                        Text(
                            "In \(previous.displayName): "
                                + (before.chips.isEmpty
                                    ? "off"
                                    : ListFormatter.localizedString(
                                        byJoining: Chip.allCases.filter { before.chips.contains($0) }.map(\.name)))
                        )
                        .scaledFont(size: 10, weight: .medium)
                        .foregroundStyle(.tertiary)
                    }
                }
                .padding(DSSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, DSSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                .fill(Self.color(for: profile).opacity(added.isEmpty && !deeper ? 0 : 0.10))
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint(isOpen ? row.detail : "Shows what runs it")
    }

    private func cell(_ chip: Chip, on: Bool, isNew: Bool) -> some View {
        ZStack {
            Circle()
                .fill(on ? chip.color : Color.secondary.opacity(0.12))
                .frame(width: 12, height: 12)
                .shadow(color: on ? chip.color.opacity(0.6) : .clear, radius: 3)
            if isNew {
                Circle()
                    .strokeBorder(chip.color, lineWidth: 1.5)
                    .frame(width: 20, height: 20)
                    .phaseAnimator(reduceMotion ? [1.0] : [1.0, 1.3, 1.0]) { ring, scale in
                        ring.scaleEffect(scale).opacity(2.3 - scale * 1.3)
                    } animation: { _ in
                        .easeInOut(duration: 0.9)
                    }
            }
        }
        .frame(height: 22)
        .accessibilityHidden(true)
    }

    // MARK: How hard

    /// How hard each job runs, as six tiles in the dots' language (5.8): the value in force now, lit where the
    /// profile turns it up. Only Maximum does; the tiles show that at a glance instead of a second list under the card.
    private var intensityGrid: some View {
        let depth = DeviceCapabilityService.Depth.forProfile(profile)
        let base = DeviceCapabilityService.Depth.standard
        let pages = concurrencyFor(profile).renderSlots
        let basePages = concurrencyFor(.balanced).renderSlots
        // Each tile against Balanced: 1 deeper or more at once, -1 fewer at once, 0 the same.
        let tiles: [(String, String, String, Int)] = [
            ("Page detail", depth.fullDetailPages ? "432 DPI" : "360-432", "doc.viewfinder", depth.fullDetailPages ? 1 : 0),
            ("Layout pass", depth.fullDetailPages ? "Full size" : "Half", "rectangle.split.2x2", depth.fullDetailPages ? 1 : 0),
            ("Pages at once", "\(pages)", "square.stack", pages > basePages ? 1 : (pages < basePages ? -1 : 0)),
            ("Re-read", "\(depth.rescueRegions) regions", "arrow.clockwise", depth.rescueRegions > base.rescueRegions ? 1 : 0),
            ("Reranked", "up to \(depth.rerankCeiling)", "arrow.up.arrow.down", depth.rerankCeiling > base.rerankCeiling ? 1 : 0),
            ("Keywords", "up to \(depth.keywordLimit)", "textformat", depth.keywordLimit > base.keywordLimit ? 1 : 0),
        ]
        let tint = Self.color(for: profile)
        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("HOW HARD")
                .scaledFont(size: 9, weight: .semibold, design: .monospaced)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DSSpacing.xs), count: 3), spacing: DSSpacing.xs) {
                ForEach(tiles, id: \.0) { tile in
                    let up = tile.3 > 0
                    let down = tile.3 < 0
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 3) {
                            Image(systemName: up ? "bolt.fill" : (down ? "tortoise.fill" : tile.2))
                                .scaledFont(size: 8, weight: .bold)
                                .foregroundStyle(up ? tint : .secondary)
                            Text(tile.0)
                                .scaledFont(size: 9, weight: .medium)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Text(tile.1)
                            .scaledFont(size: 12, weight: .bold, design: .rounded)
                            .foregroundStyle(up ? tint : (down ? .secondary : .primary))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .contentTransition(.numericText())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                            .fill(up ? tint.opacity(0.10) : Color.secondary.opacity(0.07))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                            .strokeBorder(tint.opacity(up ? 0.5 : 0), lineWidth: 1)
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(up ? "more than Balanced" : (down ? "fewer than Balanced" : "same as Balanced"))
                }
            }
        }
    }

    // MARK: Same in every profile

    private var sameEverywhere: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Button {
                showsFixed.toggle()
            } label: {
                HStack {
                    Text("SAME IN EVERY PROFILE")
                        .scaledFont(size: 9, weight: .semibold, design: .monospaced)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .scaledFont(size: 8, weight: .bold)
                        .rotationEffect(.degrees(showsFixed ? 180 : 0))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showsFixed {
                fixedRow(
                    "Reranking passages", chips: [.cpu, .neuralEngine],
                    detail:
                        "Core ML, MLComputeUnits .cpuAndNeuralEngine: the reranker scores each passage against your question."
                )
                fixedRow(
                    "Writing the answer", chips: [],
                    detail:
                        "Apple's own model, on the device or in Private Cloud Compute as your route allows. Not set here.")
                fixedRow(
                    "Reading text in images and scans", chips: [.gpu],
                    detail: "Vision; each page is prepared for recognition on the GPU.")
                // "Pages at a time" left this list in 5.8: Efficiency halves it, and How Hard shows it per profile.
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: showsFixed)
    }

    private func fixedRow(_ name: String, chips: Set<Chip>, detail: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name).scaledFont(size: 11, weight: .semibold)
                Text(detail)
                    .scaledFont(size: 10)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Chip.allCases) { chip in
                Circle()
                    .fill(chips.contains(chip) ? chip.color.opacity(0.7) : Color.secondary.opacity(0.10))
                    .frame(width: 8, height: 8)
                    .frame(width: 36, height: 16)
            }
        }
        .padding(.horizontal, DSSpacing.xs)
        .accessibilityElement(children: .combine)
    }
}

/// A row that opens what is under it, closed at first (5.8): the detail under the Compute Profile card.
struct FoldedDetails<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @State private var isOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Button {
                isOpen.toggle()
            } label: {
                HStack {
                    Text(title)
                        .font(.caption.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen {
                content()
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: isOpen)
    }
}
