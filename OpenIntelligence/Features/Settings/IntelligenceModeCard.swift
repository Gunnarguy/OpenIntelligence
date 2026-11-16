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
    /// Apple's name for the on-device model this device runs (`SystemLanguageModel.variant.displayName`, iOS 27: "AFM 3
    /// Core" or "AFM 3 Core Advanced"), or nil where the model isn't available.
    var modelName: String? = nil
    /// Private Cloud Compute's window ("32,768 tokens", the live `contextSize` when known), or nil where this device
    /// can't use it.
    var cloudWindow: String? = nil
    /// Deep Think's stopping confidence on this device (`optimizedAgenticConfig().confidenceThreshold`).
    let deepThinkTarget: Int
    /// "2 of 3 left" on a free plan; nil when Maximum has no daily limit.
    let maximumLimit: String?
    /// Whether this build can route an answer to Private Cloud Compute.
    let privateCloudComputeCompiledIn: Bool
    let callout: (RAGQualityMode) -> String
    var onSelect: (RAGQualityMode) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
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

    private var previous: RAGQualityMode? { previous(of: mode) }

    private func previous(of step: RAGQualityMode) -> RAGQualityMode? {
        guard let index = Self.modes.firstIndex(of: step), index > 0 else { return nil }
        return Self.modes[index - 1]
    }

    /// Draws `content` for every mode, hidden, and the current mode's on top, so a part takes the height of its
    /// longest version and nothing below it moves when the mode changes (5.8, 2026-11-16, the owner: "The UI jumps
    /// around bc of word wrapping ... I don't want it to jump around"). Each mode's words wrapped to their own number of
    /// lines, so the panel, the ladder and everything under them shifted with each tap.
    private func stable<Content: View>(
        alignment: Alignment = .topLeading, @ViewBuilder _ content: @escaping (RAGQualityMode) -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            ForEach(Self.modes, id: \.self) { step in
                content(step).hidden().accessibilityHidden(true)
            }
            content(mode)
        }
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
        let chainPassages = windowTokens >= 8_000 ? "up to 7" : "up to 4"
        return [
            Step(
                id: "again", name: "Searches again if the first finds little", icon: "arrow.clockwise",
                stage: .search, modes: [.standard],
                engine: "Retrieval cascade, RetrievalPolicyService",
                detail:
                    "When the first search's best scores are weak or it finds too few passages, Standard can search once "
                    + "more (not for a trivial question or a long, specific lookup), and if the best match is still weak, "
                    + "again with the question's keywords weighted up. For lookups it can also add the passages a "
                    + "found passage points to and table rows with the question's words and numbers, and a keyword "
                    + "search can replace a weak set, even after a strong search."),
            Step(
                id: "phrasings", name: "Searches up to 5 phrasings", icon: "square.stack.3d.down.right",
                stage: .search, modes: [.deepThink, .maximum],
                engine: "Multi-query expansion, AgenticOrchestrator+Retrieval",
                detail:
                    "Up to 5 phrasings of the question are searched, the first alone and then two at a time; Apple's "
                    + "model writes some when the planner has fewer than 3, except for a direct lookup. Up to 3 "
                    + "cross-reference searches can follow. After a moderate or weak search up to 3 terms from the "
                    + "passages, named by Apple's model or picked by rule, are each searched once; after a good or moderate one the "
                    + "question can be reworded and searched again. After the strongest searches Maximum adds a broad "
                    + "search and up to 3 variants, and its loop can search more when its findings stall."),
            Step(
                id: "turns", name: "Reads earlier turns of the chat", icon: "bubble.left.and.bubble.right",
                stage: .answer, modes: [.standard],
                engine: "Conversation memory, query rewriting",
                detail:
                    "Standard reads the recent turns when it answers (from Conversation Memory, or the last four "
                    + "messages when that is off). With query rewriting on, it can rewrite a follow-up that points back "
                    + "(\"it\", \"that\", \"what about\") with Apple's model, or by rule when the model can't; a simple "
                    + "lookup is kept as typed. Deep Think and Maximum answer from the question alone, unless they fall "
                    + "back to Standard."),
            Step(
                id: "arrange", name: "Packs the passages into one prompt", icon: "rectangle.compress.vertical",
                stage: .answer, modes: [.standard],
                engine: "Lost-in-the-middle order, graph context packing",
                detail:
                    "When four or more whole passages fit, Standard puts the best first and the second best last "
                    + "(not for step-by-step instructions or lookups, which it reads sentence by sentence), and for questions that investigate, compare or ask for findings adds section "
                    + "context where the document has it, nearby passages and linked passages, within the window. Deep "
                    + "Think's and Maximum's chains read first the sections Apple's model picks from the titles."),
            Step(
                id: "chain", name: "Reasons in a chain of sessions", icon: "link",
                stage: .answer, modes: [.deepThink, .maximum],
                engine: "Reasoning chain, AgenticOrchestrator+ReasoningChain",
                detail:
                    "After a strong search in Deep Think, or a good one in either mode, sessions on Apple's model each "
                    + "read \(chainPassages) passages (or their key sentences when they don't fit) and the findings so "
                    + "far. Deep Think runs up to 8: it can stop sooner when the model reports the answer complete or "
                    + "not found, or starts repeating itself, and after four it stops once it is \(deepThinkTarget)% sure, "
                    + "has covered the question, and has stopped learning or read most of the sources. Maximum's chain "
                    + "can run up to 50 and stops early when the answer is complete or its findings settle. A moderate "
                    + "search gets a reworded search and one synthesis; a weak one gets three drafts, then a broader or "
                    + "split search if they fall short; a lookup can go straight to its passage when one passage holds the exact value."),
            Step(
                id: "research", name: "Searches again for what it missed", icon: "arrow.triangle.branch",
                stage: .answer, modes: [.deepThink],
                engine: "Research rounds, AgenticOrchestrator+Research",
                detail:
                    "After the strongest searches, when parts of the question are still uncovered or the answer reads "
                    + "as a miss, up to 5 rounds of searching before one final answer; after a strong or good search, "
                    + "further rounds can check the answer."),
            Step(
                id: "fifty", name: "Up to 50 sessions over the passages found", icon: "infinity",
                stage: .answer, modes: [.maximum],
                engine: "Maximum's loop, AgenticOrchestrator+Maximum",
                detail:
                    "After the strongest searches only. Each session reads the relevant sentences of 3 passages, up to "
                    + "2,500 characters; it plans enough sessions to cover the passages found one and a half times (8 to "
                    + "50), with a running summary every fifth, and stops sooner when its findings stop changing, it "
                    + "repeats itself, or sessions keep failing. The answer is written from its fact bank (about 1,500 "
                    + "characters) and its last findings. These sessions stay on the device unless you've chosen "
                    + "Private Cloud Compute."),
            Step(
                id: "withhold", name: "Its checks can withhold the answer", icon: "hand.raised",
                stage: .check, modes: [.standard],
                engine: "Verification gates A to I, VerificationGateService",
                detail:
                    "In Standard an answer that fails a check is withheld when its confidence is under the bar or the "
                    + "library does not allow an unchecked answer. In Deep Think and Maximum the checks only label it, and "
                    + "they are skipped when the source-only check has run. Every mode declines when nothing relevant is "
                    + "found, checks a lookup's answer against its passages alone, and can withhold an answer about a "
                    + "state or an exact value that they don't support."
            ),
        ]
    }

    private var current: [Step] { steps.filter { $0.modes.contains(mode) } }

    /// Steps this mode runs and the one below does not.
    private var added: [Step] { added(for: mode) }

    private func added(for step: RAGQualityMode) -> [Step] {
        guard let previous = previous(of: step) else { return [] }
        return steps.filter { $0.modes.contains(step) && !$0.modes.contains(previous) }
    }

    // MARK: - Body

    var body: some View {
        // Every part keeps its height from one mode to the next, as on the Compute Profile card.
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            panel
            ladder
            stable { step in
                Text(callout(step))
                    .scaledFont(size: 11)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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

    private var stageFigures: [StageFigure] { stageFigures(for: mode) }

    private func stageFigures(for step: RAGQualityMode) -> [StageFigure] {
        switch step.canonical {
        case .deepThink:
            return [
                StageFigure(title: "SEARCH", symbol: "magnifyingglass", value: "5 first, more if needed", lit: 4),
                StageFigure(title: "REASON", symbol: "brain", value: "up to 8 sessions", lit: 4),
                StageFigure(title: "CHECK", symbol: "checkmark.seal", value: "9 checks, labels", lit: 4),
            ]
        case .maximum:
            return [
                StageFigure(title: "SEARCH", symbol: "magnifyingglass", value: "5 first, more after", lit: 6),
                StageFigure(title: "REASON", symbol: "brain", value: "up to 50 sessions", lit: 6),
                StageFigure(title: "CHECK", symbol: "checkmark.seal", value: "9 checks, labels", lit: 4),
            ]
        default:
            return [
                StageFigure(title: "SEARCH", symbol: "magnifyingglass", value: "1, more if thin", lit: 2),
                StageFigure(title: "REASON", symbol: "brain", value: "usually 1 answer", lit: 1),
                StageFigure(title: "CHECK", symbol: "checkmark.seal", value: "up to 9, can withhold", lit: 6),
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
                Text("\(modelName ?? "Apple's model") · \(windowDescription)")
                    .scaledFont(size: 15, weight: .semibold, relativeTo: .subheadline)
                    .lineLimit(2)
                    .minimumScaleFactor(SettingsStatusPanel.floorScale(for: 15))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text(mode.displayName)
                    .scaledFont(size: SettingsStatusPanel.minimumTextSize + 1, weight: .semibold, relativeTo: .caption)
                    .foregroundStyle(DSColors.readable(tint))
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(tint.opacity(colorScheme == .dark ? 0.20 : 0.12)))
                    .contentTransition(.interpolate)
            }
            .foregroundStyle(.secondary)

            HStack(spacing: DSSpacing.sm) {
                ForEach(0..<stageFigures.count, id: \.self) { column in
                    let figure = stageFigures[column]
                    let color = Self.stageColor(figure.title)
                    VStack(spacing: 3) {
                        Image(systemName: figure.symbol)
                            .scaledFont(size: 15, weight: .semibold)
                            .foregroundStyle(DSColors.readable(color))
                            .symbolEffect(.bounce, value: sweep)
                        Text(figure.title.capitalized)
                            .scaledFont(size: SettingsStatusPanel.minimumTextSize, weight: .medium)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 2) {
                            ForEach(0..<6, id: \.self) { index in
                                Capsule()
                                    .fill(index < figure.lit ? color : color.opacity(colorScheme == .dark ? 0.22 : 0.15))
                                    .frame(height: 4)
                            }
                        }
                        .padding(.horizontal, DSSpacing.xs)
                        stable(alignment: .top) { step in
                            Text(stageFigures(for: step)[column].value)
                                .scaledFont(size: SettingsStatusPanel.minimumTextSize + 2, weight: .semibold, design: .rounded)
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .contentTransition(.interpolate)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DSSpacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: DSCorners.chip + 2, style: .continuous)
                            .fill(SettingsStatusPanel.blockFill(dark: colorScheme == .dark))
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(figure.title.capitalized): \(figure.value)")
                }
            }
        }
        .padding(DSSpacing.sm)
        .settingsPanelSurface(dark: colorScheme == .dark)
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
                    DSHaptics.selection()
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
                            .scaledFont(size: SettingsStatusPanel.minimumTextSize + 1, weight: .semibold)
                            .lineLimit(1)
                            // Never below Apple's minimum text size (5.8 premium pass); it could shrink to 7 points.
                            .minimumScaleFactor(SettingsStatusPanel.floorScale(for: SettingsStatusPanel.minimumTextSize + 1))
                            .ladderChoice(selected: isSelected, color: Self.color(for: step))
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(step.displayName) intelligence mode")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }

    // MARK: What this step adds

    private var addsBanner: some View {
        stable { step in addsBanner(for: step) }
    }

    private func addsBanner(for mode: RAGQualityMode) -> some View {
        let title: String
        let detail: String
        let symbol: String
        let added = added(for: mode)
        if let previous = previous(of: mode) {
            title = "\(mode.displayName) adds to \(previous.displayName)"
            // Steps first, then what How Much turns up, two lines at most, as on the Compute Profile card.
            let extra = mode.canonical == .maximum ? ["After its strongest searches, a broad search and up to 3 variants"] : ["Neighbours ±3"]
            detail = Array((added.map(\.name) + extra).prefix(2)).joined(separator: "\n")
            symbol = "plus.circle.fill"
        } else {
            title = "The base step"
            detail =
                "One answer, checked against your documents. Each step to the right can search more ways and reason longer."
            symbol = "circle.dashed"
        }
        return HStack(alignment: .top, spacing: DSSpacing.sm) {
            Image(systemName: symbol)
                .foregroundStyle(Self.color(for: mode))
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .scaledFont(size: 11, weight: .semibold)
                    // Whole, on as many lines as it needs, never cut off or shrunk (5.8 premium pass).
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .scaledFont(size: 11)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        .scaledFont(size: SettingsStatusPanel.minimumTextSize, weight: .semibold, design: .monospaced)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    private func stepRow(_ step: Step) -> some View {
        let isOpen = expanded == step.id
        let runsHere = step.modes.contains(mode)
        // Every step a mode above Standard runs is lit, not only what it adds to the mode below (owner, 2026-11-13:
        // Maximum lit one row where Deep Think lit three, though it runs the phrasings and the chain too).
        let isNew = runsHere && previous != nil
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
                        // Two lines and one size (5.8): a single line cut long titles off ("Searches again if the
                        // first find…") and its shrink-to-fit drew short titles larger than long ones.
                        Text(step.name)
                            .scaledFont(size: 12, weight: .semibold)
                            .foregroundStyle(runsHere ? Color.primary : Color.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "chevron.down")
                            .scaledFont(size: SettingsStatusPanel.minimumTextSize, weight: .bold)
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
                        .scaledFont(size: SettingsStatusPanel.minimumTextSize, weight: .semibold, design: .monospaced)
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

    /// The same six tiles, with the same names and units, in every mode; only the values change (the owner, 2026-11-10
    /// and 2026-11-13: "they should kind of say the same thing"). Each answers one question about one step, a step being
    /// one call to Apple's model. Values traced to the code on 2026-11-13:
    /// - On this device: the live window (`FoundationModelTokenBudget.contextSize`), the same for every mode.
    /// - In the cloud: Private Cloud Compute's window; Standard sends an answer too long for the device there, Deep Think
    ///   and Maximum their final write-up (their steps stay on the device, `RAGService+Agentic.swift`), both after consent.
    /// - Reads per step: Standard's character budget, (window − 420) × 0.88 × 1.4, capped at 10,000
    ///   (`RAGService+QueryContext.swift`); Deep Think's 4 passages, up to 7 from an 8,000-token window
    ///   (`SessionEvidencePlan`); Maximum's 3 passages as sentences, 2,500 characters (`AgenticOrchestrator+Maximum`).
    /// - Steps: Deep Think's chain runs 4 to 8 (early stop is checked from the fifth); Maximum's loop runs
    ///   min(50, max(8, ...)) and only after a strong first search (`AgenticOrchestrator.swift`, `.excellent`).
    /// - Beside each match: `RAGQualityMode`'s neighbour radius, Standard's from `ParentDocumentService`.
    /// Chat history left the tiles: the "Reads earlier turns of the chat" row says it, correctly.
    private var tiles: [Tile] { tiles(for: mode) }

    private func tiles(for mode: RAGQualityMode) -> [Tile] {
        let standardChars = min(10_000, max(0, Int(Double(windowTokens - 420) * 0.88 * 1.4)))
        let standardReads = "up to \((standardChars / 100 * 100).formatted()) characters"
        let reads: String
        let readsCaption: String
        let steps: String
        let stepsCaption: String
        let stops: String
        let stopsCaption: String
        let beside: String
        let besideCaption: String
        let cloudCaption: String
        switch mode.canonical {
        case .deepThink:
            reads = windowTokens >= 8_000 ? "4 to 7 passages" : "4 passages"
            readsCaption = "or their key sentences"
            steps = "4 to 8"
            stepsCaption = "then one write-up"
            stops = "\(deepThinkTarget)% sure"
            stopsCaption = "and covered, from step 5"
            beside = "3 passages"
            besideCaption = "each side, while they fit"
            cloudCaption = "the write-up, with your OK"
        case .maximum:
            reads = "3 passages"
            readsCaption = "their key sentences, 2,500 chars"
            steps = "8 to 50"
            stepsCaption = "when its first search is strong"
            stops = "nothing new turns up"
            stopsCaption = "from step 6, or at its limit"
            beside = "5 passages"
            besideCaption = "each side, while they fit"
            cloudCaption = "the write-up, with your OK"
        default:
            reads = "all that fit"
            readsCaption = standardReads
            steps = "1"
            stepsCaption = "then its checks"
            stops = "it has an answer"
            stopsCaption = "checked, rewritten once at most"
            beside = "2 passages"
            besideCaption = "each side; 5 across topics, 8 how-to"
            cloudCaption = "a long answer, with your OK"
        }
        let deeper = mode.canonical != .standard
        return [
            Tile(name: "On this device", value: windowDescription, icon: "cpu", up: false,
                caption: "\(modelName ?? "Apple's model"), each step"),
            Tile(name: "In the cloud", value: cloudWindow ?? "Not used", icon: "cloud", up: false,
                caption: cloudWindow == nil ? "Private Cloud Compute is off here" : cloudCaption),
            Tile(name: "Reads per step", value: reads, icon: "doc.text", up: false, caption: readsCaption),
            Tile(name: "Steps", value: steps, icon: "link", up: deeper, caption: stepsCaption),
            Tile(name: "Stops when", value: stops, icon: "flag.checkered", up: false, caption: stopsCaption),
            // Not lit: Standard goes to 5 or 8 for some questions, beyond Deep Think's 3.
            Tile(name: "Beside each match", value: beside, icon: "arrow.left.and.right", up: false, caption: besideCaption),
        ]
    }

    private var howMuch: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            SettingsGroupLabel(text: "HOW MUCH")
            SpecTileGrid() {
                ForEach(0..<tiles.count, id: \.self) { index in
                    stable { step in
                        let tile = tiles(for: step)[index]
                        SpecTile(
                            name: tile.name, value: tile.value, icon: tile.icon, caption: tile.caption,
                            tint: tile.up ? Self.color(for: step) : nil, marker: tile.up ? "bolt.fill" : nil)
                    }
                }
            }
        }
    }

    // MARK: Same in every mode

    private var sharedSteps: [(String, String)] {
        var rows: [(String, String)] = [
            ("Search by meaning and by keyword", "Two searches merged by reciprocal rank fusion (k = 60); a search inside one document weighs the two instead."),
            (
                "Sorts the question into one of 8 kinds",
                "Lookup, table lookup, procedure, compare, summarize, investigate, findings or compute; the kind steers the search."
            ),
            (
                "Reranks the top candidates",
                "IBM's Granite cross-encoder scores the top candidates against the question; Core ML is asked for the CPU and Neural Engine. Passages added afterwards (neighbours, summaries, cross-references) skip it, and a simpler ranking runs while the model hasn't loaded."
            ),
            (
                "Keeps the results varied",
                "Maximal marginal relevance, within each search: when there are more candidates than places, near-duplicates give way to other passages."
            ),
            (
                "Adds neighbouring passages",
                "Up to ±2 in Standard (±5 across topics, ±8 for step-by-step instructions), ±3 in Deep Think, ±5 in Maximum, within a token budget: none once it is full."
            ),
            ("Document summaries for overview questions", "When query routing is on and the library has summaries."),
            (
                "Nine checks on the answer",
                "Gates A to I: confidence, coverage, numbers, contradiction, meaning, abbreviations, quality, completeness and mixed-domain isolation. The meaning check needs vectors for the passages and the answer."
            ),
            (
                "A confidence score",
                "Standard's from the top score, the number of passages and sources, and the question; a reasoning chain's from its progress and a self-check; Maximum's loop from its sessions' progress blended with that check; other routes from relevance and citations."
            ),
        ]
        if privateCloudComputeCompiledIn {
            rows.append(
                (
                    "Private Cloud Compute, with your permission",
                    "When you choose it, or for an answer too large for this device, and in Deep Think and Maximum a synthesis drawn from several documents can go there; Maximum's loop sessions stay on the device unless you chose it. The app plans for a 32,768-token window there, and a Standard answer planned for it reads up to 45,000 characters."
                ))
        }
        return rows
    }

    private var importSteps: [(String, String)] {
        [
            (
                "The embedding model",
                "IBM's Granite small english r2, bundled, by default, on the device (a library can use Apple's word vectors instead); each passage is embedded with its file name and, where it has one, its section in front."
            ),
            ("Tables", "In PDFs and scans, read with Vision's document recognition, with captions where Vision finds them; spreadsheets, CSV and other formats are read from their own structure."),
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
                        .scaledFont(size: SettingsStatusPanel.minimumTextSize, weight: .bold)
                        .rotationEffect(.degrees(showsShared ? 180 : 0))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showsShared {
                ForEach(sharedSteps, id: \.0) { row in sharedRow(row.0, row.1) }
                Text("SET WHEN YOU IMPORT, NOT BY THE MODE")
                    .scaledFont(size: SettingsStatusPanel.minimumTextSize, weight: .semibold, design: .monospaced)
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
                .scaledFont(size: SettingsStatusPanel.minimumTextSize)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
