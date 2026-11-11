//
//  IntelligenceModeCard.swift
//  OpenIntelligence
//
//  The Intelligence Mode page (5.8), in the Compute Profile card's language: a panel, a ladder of three steps, what
//  each step adds, the steps that differ by mode with a dot per mode, How Much, and what every mode shares.
//
//  Every row and figure was traced to the code on 2026-11-10, then checked by a refuting review the same evening,
//  which found 31 overstatements in the first version (searches "at once" that run first alone and then two at a
//  time, Maximum's chain path missing, a withholding rule that held for one check of two) and they were corrected.
//  The list this replaced named four techniques that run in no mode (HyDE and contextual compression sit on
//  Standard's path after Deep Think and Maximum leave it, and Standard has both off; nothing fills the entity index;
//  extractive summarization needs `.summarize` to be extract-first, which it is not), listed Standard-only steps under
//  Deep Think and Maximum (graph context packing, confidence calibration), and named import steps as mode features.
//  The Context Window section moved here from Device & Performance: the window is how much each answer can read.
//
//  Deep Think and Maximum branch on how good their first search was (`AgenticOrchestrator`, `retrievalQuality`):
//  the strongest search sends Deep Think to its chain and research rounds and Maximum to its 50-session loop; a good
//  one sends both to the chain; a weaker one gets one synthesis or drafts; a lookup goes to its passage.
//

import SwiftUI

struct IntelligenceModeCard: View {
    let mode: RAGQualityMode
    /// The on-device window Apple's model reports, in tokens (`SystemLanguageModel.contextSize`), and as words.
    let windowTokens: Int
    let windowDescription: String
    /// Deep Think's stopping confidence on this device (`optimizedAgenticConfig().confidenceThreshold`).
    let deepThinkTarget: Int
    /// "2 of 3 left" on a free plan; nil when Maximum has no daily limit.
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

    /// The steps that differ between modes, each traced to its call site and reviewed (2026-11-10).
    var steps: [Step] {
        let chainPassages = windowTokens >= 8_000 ? "up to 7" : "4"
        return [
            Step(
                id: "again", name: "Searches again if the first finds little", icon: "arrow.clockwise",
                stage: .search, modes: [.standard],
                engine: "Retrieval cascade, RetrievalPolicyService",
                detail:
                    "When the first search's best scores are weak, or it finds fewer passages than it needs, Standard "
                    + "searches once more and then retries with the question's plain keywords. Deep Think and Maximum "
                    + "retry in their own ways, in the row below."),
            Step(
                id: "phrasings", name: "Searches up to 5 phrasings", icon: "square.stack.3d.down.right",
                stage: .search, modes: [.deepThink, .maximum],
                engine: "Multi-query expansion, AgenticOrchestrator+Retrieval",
                detail:
                    "Up to 5 phrasings of the question are searched, the first alone and then two at a time; Apple's "
                    + "model writes some when the planner has fewer than 3. If they find nothing, the question's own "
                    + "words are searched. After a weak search the model names up to 3 terms from the passages and each "
                    + "is searched once; after a good one the question is reworded and searched again. After the "
                    + "strongest searches Maximum adds a broad search and up to 3 variants, one after another."),
            Step(
                id: "turns", name: "Reads earlier turns of the chat", icon: "bubble.left.and.bubble.right",
                stage: .answer, modes: [.standard],
                engine: "Conversation memory, query rewriting",
                detail:
                    "Standard reads the recent turns when it answers, and rewrites a vague follow-up from them with "
                    + "Apple's model when query rewriting is on, except for simple lookups. Deep Think and Maximum record "
                    + "the turn but answer from the question alone."),
            Step(
                id: "arrange", name: "Puts the best passages where the model reads", icon: "rectangle.compress.vertical",
                stage: .answer, modes: [.standard],
                engine: "Lost-in-the-middle order, graph context packing",
                detail:
                    "When four or more whole passages fit, the best goes first and the second best last (not for "
                    + "step-by-step instructions or lookups). For questions that investigate, compare or ask for findings "
                    + "it adds each passage's section, the passages either side and passages one link away, within the "
                    + "window. Deep Think's chain reads first the sections Apple's model picks from the titles."),
            Step(
                id: "chain", name: "Reasons in a chain of sessions", icon: "link",
                stage: .answer, modes: [.deepThink, .maximum],
                engine: "Reasoning chain, AgenticOrchestrator+ReasoningChain",
                detail:
                    "After a strong search in Deep Think, or a good one in either mode, sessions on Apple's model each "
                    + "read \(chainPassages) passages and the findings so far. Deep Think stops at 8 sessions; after four "
                    + "it can stop once it is \(deepThinkTarget)% sure, has covered the question, and has stopped learning "
                    + "or read most of the sources. Maximum's chain runs until it has read every distinct part, up to 50. "
                    + "A weaker search gets one synthesis, or three drafts and then a broader or split search; a lookup "
                    + "goes straight to its passage."),
            Step(
                id: "research", name: "Searches again for what it missed", icon: "arrow.triangle.branch",
                stage: .answer, modes: [.deepThink],
                engine: "Research rounds, AgenticOrchestrator+Research",
                detail:
                    "After the strongest searches, when parts of the question are still uncovered or the answer reads "
                    + "as a miss, up to 5 rounds of searching and answering again."),
            Step(
                id: "fifty", name: "Up to 50 sessions over every passage", icon: "infinity",
                stage: .answer, modes: [.maximum],
                engine: "Maximum's loop, AgenticOrchestrator+Maximum",
                detail:
                    "After the strongest searches only. Each session reads the relevant sentences of 3 passages, up to "
                    + "2,500 characters, enough sessions to cover the passages found one and a half times (8 to 50), "
                    + "with a running summary every fifth. The answer is written from everything found, it stops early "
                    + "when its findings stop changing, and these sessions stay on the device."),
            Step(
                id: "withhold", name: "Its checks can withhold the answer", icon: "hand.raised",
                stage: .check, modes: [.standard],
                engine: "Verification gates A to I, VerificationGateService",
                detail:
                    "In Standard a failed critical check (A retrieval confidence, C numbers, E meaning) can withhold the "
                    + "answer. In Deep Think and Maximum the checks only label it, and they are skipped when the "
                    + "source-only check has run. In every mode that check, on lookups, can withhold an answer the "
                    + "passages do not support."
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
                StageFigure(title: "SEARCH", symbol: "magnifyingglass", value: "up to 5, 2 at a time", lit: 4),
                StageFigure(title: "REASON", symbol: "brain", value: "up to 8 sessions", lit: 4),
                StageFigure(title: "CHECK", symbol: "checkmark.seal", value: "9 checks, labels", lit: 4),
            ]
        case .maximum:
            return [
                StageFigure(title: "SEARCH", symbol: "magnifyingglass", value: "up to 5, then up to 4", lit: 6),
                StageFigure(title: "REASON", symbol: "brain", value: "up to 50 sessions", lit: 6),
                StageFigure(title: "CHECK", symbol: "checkmark.seal", value: "9 checks, labels", lit: 4),
            ]
        default:
            return [
                StageFigure(title: "SEARCH", symbol: "magnifyingglass", value: "1, again if thin", lit: 2),
                StageFigure(title: "REASON", symbol: "brain", value: "1 answer", lit: 1),
                StageFigure(title: "CHECK", symbol: "checkmark.seal", value: "9 checks, can withhold", lit: 6),
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
            let extra = mode.canonical == .maximum ? ["A broad search and up to 3 variants, neighbours ±5"] : ["Neighbours ±3"]
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
        /// One line under the value, so every tile in every mode has the same height.
        var caption: String = ""
    }

    /// The same six tiles in the same places for every mode, only the values change (the owner, 2026-11-10: three
    /// tiles changed name from one mode to the next). Lit where a mode goes further than Standard.
    private var tiles: [Tile] {
        let chainPassages = windowTokens >= 8_000 ? "up to 7 passages" : "up to 4 passages"
        let reads: String
        let neighbours: String
        let sessions: String
        let stops: String
        let stopsCaption: String
        let readsCaption: String
        let chat: String
        switch mode.canonical {
        case .deepThink:
            reads = chainPassages
            neighbours = "±3"
            sessions = "up to 8"
            stops = "\(deepThinkTarget)% sure, covered"
            stopsCaption = "and nothing new to read"
            readsCaption = "each session"
            chat = "Not read"
        case .maximum:
            reads = "up to 2,500 chars"
            neighbours = "±5"
            sessions = "up to 50"
            stops = "findings settle"
            stopsCaption = "or at 50 sessions"
            readsCaption = "best sentences, each session"
            chat = "Not read"
        default:
            reads = "up to 10,000 chars"
            neighbours = "±2 to ±8"
            sessions = "1"
            stops = "one answer"
            stopsCaption = "after its checks"
            readsCaption = "of passages, on this device"
            chat = "Read"
        }
        let deeper = mode.canonical != .standard
        return [
            Tile(name: "Window", value: windowDescription, icon: "ruler", up: false, caption: "Apple's model reports"),
            Tile(name: "Reads each pass", value: reads, icon: "doc.text", up: false, caption: readsCaption),
            Tile(name: "Neighbours", value: neighbours, icon: "arrow.left.and.right", up: deeper, caption: "passages either side"),
            Tile(name: "Sessions", value: sessions, icon: "link", up: deeper, caption: "on Apple's model"),
            Tile(name: "Stops when", value: stops, icon: "flag.checkered", up: false, caption: stopsCaption),
            Tile(name: "Chat history", value: chat, icon: "bubble.left.and.bubble.right", up: false, caption: "earlier turns"),
        ]
    }

    private var howMuch: some View {
        let tint = Self.color(for: mode)
        return VStack(alignment: .leading, spacing: DSSpacing.xs) {
            SettingsGroupLabel(text: "HOW MUCH")
            LazyVGrid(columns: SpecTile.columns, spacing: DSSpacing.xs) {
                ForEach(tiles, id: \.name) { tile in
                    SpecTile(
                        name: tile.name, value: tile.value, icon: tile.icon, caption: tile.caption,
                        tint: tile.up ? tint : nil, marker: tile.up ? "bolt.fill" : nil)
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
                "±2 in Standard (±5 across topics, ±8 for step-by-step instructions), ±3 in Deep Think, ±5 in Maximum, within a token budget."
            ),
            ("Document summaries for overview questions", "When query routing is on and the library has summaries."),
            (
                "Nine checks on the answer",
                "Gates A to I: confidence, coverage, numbers, contradiction, meaning, quotes, quality, completeness and mixed-domain isolation. In Standard completeness and isolation pass without a check, and the meaning check needs the passages' vectors."
            ),
            (
                "A confidence score",
                "Standard's from the top score, the margin and the number of passages; Deep Think's from relevance and citations; Maximum's loop from its sessions' progress blended with its self-check."
            ),
        ]
        if privateCloudComputeCompiledIn {
            rows.append(
                (
                    "Private Cloud Compute, with your permission",
                    "When you choose it, or for an answer too large for this device; Maximum's loop sessions stay on the device. The app plans for a 32,768-token window there, and Standard then reads up to 45,000 characters of your documents."
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
