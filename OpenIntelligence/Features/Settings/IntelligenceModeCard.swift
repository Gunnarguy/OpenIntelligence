//
//  IntelligenceModeCard.swift
//  OpenIntelligence
//
//  The Intelligence Mode page (5.8), in the Compute Profile card's language: a panel, a ladder of three steps, what
//  each step adds, the steps that differ by mode with a dot per mode, How Much, and what every mode shares.
//
//  Every row and figure was traced to the code on 2026-11-10. The list this replaced named four techniques that
//  run in no mode (HyDE and contextual compression sit on Standard's path after Deep Think and Maximum leave it, and
//  Standard has both off; nothing fills the entity index; extractive summarization needs `.summarize` to be
//  extract-first, which it is not), listed Standard-only steps under Deep Think and Maximum (graph context packing,
//  confidence calibration), and named import steps as mode features. The Context Window section moved here from
//  Device & Performance: the window is how much of the documents each answer can read.
//

import SwiftUI

struct IntelligenceModeCard: View {
    let mode: RAGQualityMode
    /// The on-device window Apple's model reports, in tokens (`SystemLanguageModel.contextSize`), and as words.
    let windowTokens: Int
    let windowDescription: String
    /// Deep Think's stopping confidence on this device (`optimizedAgenticConfig().confidenceThreshold`).
    let deepThinkTarget: Int
    /// "3 a day, 2 left today" on a free plan; nil when Maximum has no daily limit.
    let maximumLimit: String?
    /// Whether this build can route an answer to Private Cloud Compute.
    let privateCloudComputeCompiledIn: Bool
    let callout: (RAGQualityMode) -> String
    var onSelect: (RAGQualityMode) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded: String?
    @State private var showsShared = false
    @State private var sweep = 0

    static let modes: [RAGQualityMode] = [.standard, .deepThink, .maximum]

    static func color(for mode: RAGQualityMode) -> Color {
        switch mode.canonical {
        case .deepThink: return .purple
        case .maximum: return .orange
        default: return .accentColor
        }
    }

    static func shortName(_ mode: RAGQualityMode) -> String {
        switch mode.canonical {
        case .deepThink: return "DEEP"
        case .maximum: return "MAX"
        default: return "STD"
        }
    }

    private var previous: RAGQualityMode? {
        guard let index = Self.modes.firstIndex(of: mode), index > 0 else { return nil }
        return Self.modes[index - 1]
    }

    // MARK: - Model

    enum Stage: String { case search, answer, check }

    struct Step: Identifiable {
        let id: String
        let name: String
        let icon: String
        let stage: Stage
        let modes: Set<RAGQualityMode>
        /// The code that runs it.
        let engine: String
        let detail: String
    }

    /// The steps that differ between modes, each traced to its call site (2026-11-10).
    var steps: [Step] {
        let chainPassages = windowTokens >= 8_000 ? 7 : 4
        return [
            Step(
                id: "again", name: "Searches again if the first finds little", icon: "arrow.clockwise",
                stage: .search, modes: [.standard],
                engine: "Retrieval cascade, RetrievalPolicyService",
                detail:
                    "When the first search's best scores are weak, or it finds fewer passages than it needs, Standard "
                    + "searches once more and then retries with the question's plain keywords. Deep Think and Maximum "
                    + "search several ways from the start."),
            Step(
                id: "phrasings", name: "Searches several phrasings at once", icon: "square.stack.3d.down.right",
                stage: .search, modes: [.deepThink, .maximum],
                engine: "Multi-query expansion, AgenticOrchestrator+Retrieval",
                detail:
                    "Up to 5 phrasings of the question are searched in parallel; Apple's model writes some when the "
                    + "planner has fewer than 3. After a weak search the model names up to 3 terms from the passages and "
                    + "each is searched once, and a thin result is reworded and searched again. Maximum adds one broad "
                    + "search and up to 3 variant searches."),
            Step(
                id: "turns", name: "Reads earlier turns of the chat", icon: "bubble.left.and.bubble.right",
                stage: .answer, modes: [.standard],
                engine: "Conversation memory, query rewriting",
                detail:
                    "Standard rewrites a vague follow-up from the recent turns with Apple's model and reads them when "
                    + "it answers. Deep Think and Maximum record the turn but answer from the question alone."),
            Step(
                id: "arrange", name: "Arranges the passages for the model", icon: "rectangle.compress.vertical",
                stage: .answer, modes: [.standard],
                engine: "Lost-in-the-middle order, graph context packing",
                detail: "The best passage goes first and the second best last (not for step-by-step instructions). For questions that investigate, compare or ask for findings it "
                    + "adds each passage's section, its neighbours and one related passage, within the window. Deep "
                    + "Think and Maximum order passages by score."),
            Step(
                id: "chain", name: "Reasons in a chain of sessions", icon: "link",
                stage: .answer, modes: [.deepThink],
                engine: "Reasoning chain, AgenticOrchestrator+ReasoningChain",
                detail: "After a strong search, up to 8 sessions on Apple's model, each reading up to \(chainPassages) "
                    + "passages and the findings so far. From the fifth it can stop once it is \(deepThinkTarget)% sure, "
                    + "has covered the question and stops finding anything new. If parts are still uncovered, up to 5 "
                    + "research rounds search again. A weaker search gets one synthesis or three drafts, and a lookup goes "
                    + "straight to its passage."),
            Step(
                id: "fifty", name: "Up to 50 sessions over every passage", icon: "infinity",
                stage: .answer, modes: [.maximum],
                engine: "Maximum's loop, AgenticOrchestrator+Maximum",
                detail:
                    "After a strong search, sessions read 3 passages each, enough to cover the passages found one and "
                    + "a half times (8 to 50 sessions), with a running summary every fifth session. The answer is written "
                    + "from everything found, and it stops early when its findings stop changing."),
            Step(
                id: "withhold", name: "Holds back an answer that fails its checks", icon: "hand.raised",
                stage: .check, modes: [.standard],
                engine: "Verification gates A to I, VerificationGateService",
                detail:
                    "Every mode runs the nine checks after it answers. Only Standard withholds an answer that fails "
                    + "them; Deep Think and Maximum show the result as a label."
            ),
        ]
    }

    private var current: [Step] { steps.filter { $0.modes.contains(mode) } }

    /// Steps this mode runs and the one below does not.
    private var added: [Step] {
        guard let previous else { return [] }
        return steps.filter { $0.modes.contains(mode) && !$0.modes.contains(previous) }
    }

    // MARK: - Body

    var body: some View {
        // Every part keeps its height from one mode to the next, as on the Compute Profile card.
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            panel
            ladder
            Text(callout(mode))
                .scaledFont(size: 11)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
            addsBanner
            stepsList
            howMuch
            shared
        }
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82), value: mode)
        .animation(reduceMotion ? nil : .snappy, value: expanded)
        .onChange(of: mode) { sweep += 1 }
    }

    // MARK: The panel

    private struct StageFigure {
        let title: String
        let symbol: String
        let value: String
        /// Lit segments of six: a picture of the scale, the number beside it is the fact.
        let lit: Int
    }

    private var stageFigures: [StageFigure] {
        switch mode.canonical {
        case .deepThink:
            return [
                StageFigure(title: "SEARCH", symbol: "magnifyingglass", value: "up to 5 at once", lit: 4),
                StageFigure(title: "REASON", symbol: "brain", value: "up to 8 sessions", lit: 4),
                StageFigure(title: "CHECK", symbol: "checkmark.seal", value: "9 checks, labels", lit: 4),
            ]
        case .maximum:
            return [
                StageFigure(title: "SEARCH", symbol: "magnifyingglass", value: "5 at once, then 4", lit: 6),
                StageFigure(title: "REASON", symbol: "brain", value: "up to 50 sessions", lit: 6),
                StageFigure(title: "CHECK", symbol: "checkmark.seal", value: "9 checks, labels", lit: 4),
            ]
        default:
            return [
                StageFigure(title: "SEARCH", symbol: "magnifyingglass", value: "1, again if thin", lit: 2),
                StageFigure(title: "REASON", symbol: "brain", value: "1 answer", lit: 1),
                StageFigure(title: "CHECK", symbol: "checkmark.seal", value: "9 checks, holds back", lit: 6),
            ]
        }
    }

    /// Each stage keeps its colour in every mode, as the CPU, Neural Engine and GPU do on the Compute Profile card.
    static func stageColor(_ title: String) -> Color {
        switch title {
        case "SEARCH": return .cyan
        case "REASON": return .pink
        default: return .green
        }
    }

    private var panel: some View {
        let tint = Self.color(for: mode)
        return VStack(spacing: DSSpacing.xs) {
            HStack {
                Image(systemName: mode.icon)
                    .scaledFont(size: 11, weight: .semibold)
                // The same header as the Compute Profile's chip: the thing at work, then the step in its colour.
                Text("Apple's model · \(windowDescription)")
                    .scaledFont(size: 12, weight: .bold, design: .monospaced)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Text(mode.displayName.uppercased())
                    .scaledFont(size: 10, weight: .heavy, design: .monospaced)
                    .foregroundStyle(tint)
                    .contentTransition(.interpolate)
            }
            .foregroundStyle(Color.white.opacity(0.85))

            HStack(spacing: DSSpacing.sm) {
                ForEach(stageFigures, id: \.title) { figure in
                    let color = Self.stageColor(figure.title)
                    let share = Double(figure.lit) / 6
                    VStack(spacing: 3) {
                        Image(systemName: figure.symbol)
                            .scaledFont(size: 15, weight: .semibold)
                            .foregroundStyle(Color.white)
                            .symbolEffect(.bounce, value: sweep)
                        Text(figure.title.capitalized)
                            .scaledFont(size: 10, weight: .bold)
                            .foregroundStyle(Color.white)
                        HStack(spacing: 2) {
                            ForEach(0..<6, id: \.self) { index in
                                Capsule()
                                    .fill(index < figure.lit ? color : Color.white.opacity(0.12))
                                    .frame(height: 4)
                            }
                        }
                        .padding(.horizontal, DSSpacing.xs)
                        Text(figure.value)
                            .scaledFont(size: 9, weight: .semibold, design: .monospaced)
                            .foregroundStyle(Color.white.opacity(0.9))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .contentTransition(.interpolate)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DSSpacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                            .fill(
                                RadialGradient(
                                    colors: [color.opacity(0.30 + 0.45 * share), color.opacity(0.10)],
                                    center: .center, startRadius: 2, endRadius: 70))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                            .strokeBorder(color.opacity(0.95), lineWidth: 1)
                    )
                    .shadow(color: color.opacity(0.25 + 0.5 * share), radius: 4 + 12 * share)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(figure.title.capitalized): \(figure.value)")
                }
            }
        }
        .padding(DSSpacing.sm)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .fill(Color(white: 0.07))
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
                        colors: ["SEARCH", "REASON", "CHECK"].map(Self.stageColor), startPoint: .leading, endPoint: .trailing),
                    lineWidth: 1.2
                )
                .opacity(0.8)
        )
        .phaseAnimator(reduceMotion ? [0.0] : [0.0, 1.0, 0.0], trigger: sweep) { view, phase in
            view.brightness(phase * 0.08).scaleEffect(1 + phase * 0.01)
        } animation: { _ in
            .easeInOut(duration: 0.25)
        }
    }

    // MARK: The ladder

    private var ladder: some View {
        let selectedIndex = Self.modes.firstIndex(of: mode) ?? 0
        return HStack(alignment: .bottom, spacing: DSSpacing.xs) {
            ForEach(Array(Self.modes.enumerated()), id: \.element) { index, step in
                let filled = index <= selectedIndex
                let isSelected = step == mode
                Button {
                    guard step != mode else { return }
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
                            .frame(height: 6 + CGFloat(index) * 5)
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
                .accessibilityLabel("\(step.displayName) intelligence mode")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .sensoryFeedback(.selection, trigger: mode)
    }

    // MARK: What this step adds

    private var addsBanner: some View {
        let title: String
        let detail: String
        let symbol: String
        if let previous {
            title = "\(mode.displayName) adds to \(previous.displayName)"
            // Steps first, then what How Much turns up, two lines at most, as on the Compute Profile card.
            let extra = mode.canonical == .maximum ? ["A broad search and 3 variants, neighbours ±5"] : ["Neighbours ±3"]
            detail = Array((added.map(\.name) + extra).prefix(2)).joined(separator: "\n")
            symbol = "plus.circle.fill"
        } else {
            title = "The base step"
            detail =
                "One answer, checked against your documents. Each step to the right searches more ways and reasons longer."
            symbol = "circle.dashed"
        }
        return HStack(alignment: .top, spacing: DSSpacing.sm) {
            Image(systemName: symbol)
                .foregroundStyle(Self.color(for: mode))
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
                .fill(Self.color(for: mode).opacity(0.10))
        )
    }

    // MARK: The steps

    private var stepsList: some View {
        VStack(spacing: DSSpacing.xs) {
            phaseHeader("WHEN IT SEARCHES", showsModes: true)
            ForEach(steps.filter { $0.stage == .search }) { stepRow($0) }
            phaseHeader("WHEN IT ANSWERS", showsModes: false)
            ForEach(steps.filter { $0.stage == .answer }) { stepRow($0) }
            phaseHeader("WHEN IT CHECKS", showsModes: false)
            ForEach(steps.filter { $0.stage == .check }) { stepRow($0) }
        }
    }

    private func phaseHeader(_ title: String, showsModes: Bool) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Self.modes, id: \.self) { column in
                Text(showsModes ? Self.shortName(column) : "")
                    .foregroundStyle(column == mode ? Self.color(for: column) : .secondary)
                    .frame(width: 36)
            }
        }
        .scaledFont(size: 9, weight: .semibold, design: .monospaced)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    private func stepRow(_ step: Step) -> some View {
        let isOpen = expanded == step.id
        let runsHere = step.modes.contains(mode)
        let isNew = added.contains(where: { $0.id == step.id })
        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Button {
                expanded = isOpen ? nil : step.id
            } label: {
                HStack(spacing: 0) {
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: step.icon)
                            .scaledFont(size: 11)
                            .foregroundStyle(runsHere ? Color.primary : Color.secondary)
                            .frame(width: 16)
                        Text(step.name)
                            .scaledFont(size: 12, weight: .semibold)
                            .foregroundStyle(runsHere ? Color.primary : Color.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Image(systemName: "chevron.down")
                            .scaledFont(size: 8, weight: .bold)
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Self.modes, id: \.self) { column in
                        dot(
                            on: step.modes.contains(column), color: Self.color(for: column),
                            ring: isNew && column == mode, selectedColumn: column == mode
                        )
                        .frame(width: 36)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Label(step.engine, systemImage: "gearshape.2")
                        .scaledFont(size: 10, weight: .semibold, design: .monospaced)
                        .foregroundStyle(Self.color(for: mode))
                    Text(step.detail)
                        .scaledFont(size: 11)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
                .fill(Self.color(for: mode).opacity(isNew ? 0.10 : 0))
        )
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            "Runs in "
                + ListFormatter.localizedString(
                    byJoining: Self.modes.filter { step.modes.contains($0) }.map(\.displayName))
        )
        .accessibilityHint(isOpen ? step.detail : "Shows how it works")
    }

    private func dot(on: Bool, color: Color, ring: Bool, selectedColumn: Bool) -> some View {
        ZStack {
            Circle()
                .fill(on ? color.opacity(selectedColumn ? 1 : 0.45) : Color.secondary.opacity(0.12))
                .frame(width: 12, height: 12)
                .shadow(color: on && selectedColumn ? color.opacity(0.6) : .clear, radius: 3)
            if ring {
                Circle()
                    .strokeBorder(color, lineWidth: 1.5)
                    .frame(width: 20, height: 20)
                    .phaseAnimator(reduceMotion ? [1.0] : [1.0, 1.3, 1.0]) { view, scale in
                        view.scaleEffect(scale).opacity(2.3 - scale * 1.3)
                    } animation: { _ in
                        .easeInOut(duration: 0.9)
                    }
            }
        }
        .frame(height: 22)
        .accessibilityHidden(true)
    }

    // MARK: How much

    private struct Tile {
        let name: String
        let value: String
        let icon: String
        /// Above Standard's value.
        let up: Bool
    }

    private var tiles: [Tile] {
        let chainPassages = windowTokens >= 8_000 ? 7 : 4
        switch mode.canonical {
        case .deepThink:
            return [
                Tile(name: "Window", value: windowDescription, icon: "ruler", up: false),
                Tile(name: "Each session", value: "up to \(chainPassages) passages", icon: "doc.text", up: false),
                Tile(name: "Neighbours", value: "±3", icon: "arrow.left.and.right", up: true),
                Tile(name: "Sessions", value: "up to 8", icon: "link", up: true),
                Tile(name: "Aims for", value: "\(deepThinkTarget)% sure", icon: "flag.checkered", up: false),
                Tile(name: "Chat history", value: "Not read", icon: "bubble.left.and.bubble.right", up: false),
            ]
        case .maximum:
            return [
                Tile(name: "Window", value: windowDescription, icon: "ruler", up: false),
                Tile(name: "Each session", value: "3 passages", icon: "doc.text", up: false),
                Tile(name: "Neighbours", value: "±5", icon: "arrow.left.and.right", up: true),
                Tile(name: "Sessions", value: "up to 50", icon: "infinity", up: true),
                Tile(name: "Stops", value: "when settled", icon: "flag.checkered", up: false),
                Tile(name: "Daily use", value: maximumLimit ?? "No limit", icon: "calendar", up: false),
            ]
        default:
            return [
                Tile(name: "Window", value: windowDescription, icon: "ruler", up: false),
                Tile(name: "Evidence", value: "up to 10,000 chars", icon: "doc.text", up: false),
                Tile(name: "Neighbours", value: "±2", icon: "arrow.left.and.right", up: false),
                Tile(name: "Sessions", value: "1", icon: "link", up: false),
                Tile(name: "Stops", value: "after one answer", icon: "flag.checkered", up: false),
                Tile(name: "Chat history", value: "Read", icon: "bubble.left.and.bubble.right", up: false),
            ]
        }
    }

    private var howMuch: some View {
        let tint = Self.color(for: mode)
        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            SettingsGroupLabel(text: "HOW MUCH")
            LazyVGrid(columns: SpecTile.columns, spacing: DSSpacing.xs) {
                ForEach(tiles, id: \.name) { tile in
                    SpecTile(
                        name: tile.name, value: tile.value, icon: tile.icon, tint: tile.up ? tint : nil,
                        marker: tile.up ? "bolt.fill" : nil)
                }
            }
        }
    }

    // MARK: Same in every mode

    private var sharedSteps: [(String, String)] {
        var rows: [(String, String)] = [
            ("Search by meaning and by keyword", "Two searches merged by reciprocal rank fusion (k = 60)."),
            (
                "Sorts the question into one of 8 kinds",
                "Lookup, table lookup, procedure, compare, summarize, investigate, findings or compute; the kind steers the search."
            ),
            (
                "Reranks the passages found",
                "IBM's Granite cross-encoder scores each passage against the question; Core ML is asked for the CPU and Neural Engine."
            ),
            (
                "Keeps the results varied",
                "Maximal marginal relevance, so near-duplicate passages do not crowd out others."
            ),
            (
                "Adds neighbouring passages",
                "±2 in Standard, ±3 in Deep Think, ±5 in Maximum, more for step-by-step instructions, within a token budget."
            ),
            ("Document summaries for overview questions", "When summaries are on for the library."),
            (
                "Nine checks on the answer",
                "Gates A to I: confidence, coverage, numbers, contradiction, meaning, quotes, quality, completeness and library isolation."
            ),
            (
                "A confidence score",
                "Standard's from the top score, the margin and the number of passages; Deep Think's and Maximum's from relevance and citations."
            ),
        ]
        if privateCloudComputeCompiledIn {
            rows.append(
                (
                    "Private Cloud Compute, with your permission",
                    "For an answer too large for this device. Its window is 32,768 tokens, and Standard then reads up to 45,000 characters of your documents."
                ))
        }
        return rows
    }

    private var importSteps: [(String, String)] {
        [
            (
                "The embedding model",
                "all-MiniLM-L6-v2 on the device; each passage is embedded with its file name and section in front."
            ),
            ("Tables", "Read with Vision's document recognition, captions kept."),
            ("Spotlight", "Your documents are indexed for system search, when that setting is on."),
        ]
    }

    private var shared: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Button {
                showsShared.toggle()
            } label: {
                HStack {
                    SettingsGroupLabel(text: "SAME IN EVERY MODE")
                    Spacer()
                    Image(systemName: "chevron.down")
                        .scaledFont(size: 8, weight: .bold)
                        .rotationEffect(.degrees(showsShared ? 180 : 0))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showsShared {
                ForEach(sharedSteps, id: \.0) { row in sharedRow(row.0, row.1) }
                Text("SET WHEN YOU IMPORT, NOT BY THE MODE")
                    .scaledFont(size: 9, weight: .semibold, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .padding(.top, DSSpacing.xs)
                ForEach(importSteps, id: \.0) { row in sharedRow(row.0, row.1) }
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: showsShared)
    }

    private func sharedRow(_ name: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name).scaledFont(size: 11, weight: .semibold)
            Text(detail)
                .scaledFont(size: 10)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
