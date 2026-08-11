//
//  GlossaryViews.swift
//  OpenIntelligence
//
//  The affordances that put `Glossary` definitions next to the words they explain.
//
//  The design problem these solve. A definition hidden in Settings is a definition nobody
//  reads, because the moment a user needs one is the moment the unexplained figure is in
//  front of them. So the primitive here is a modifier rather than a screen: any label,
//  chip or number becomes tappable in place, and the full glossary screen is the index
//  rather than the only route in.
//
//  Two registers, one switch. `plain` is always visible. `technical` sits behind a
//  disclosure whose state is stored in `AppStorage`, so a technical user opens it once and
//  every definition in the app stays open for them afterwards, while a non-technical user
//  never has jargon put in front of them. That shared preference is the whole reason both
//  registers can live on the same screen without one of them being noise.
//
//  Dark and light variants exist because onboarding is a dark full-screen gradient and
//  Settings is a standard grouped list. They differ only in tint.
//

import SwiftUI

// MARK: - Shared preference

/// Whether the technical register is expanded, shared by every definition in the app.
enum GlossaryPreference {
    static let technicalDetailKey = "glossary.showsTechnicalDetail"
}

// MARK: - Term detail

/// One term, both registers, and its related words.
///
/// Used in three places without variation: the sheet a tappable label opens, a pushed
/// screen inside the glossary, and the glossary's own search results.
struct GlossaryTermDetail: View {
    let termID: GlossaryTermID

    @AppStorage(GlossaryPreference.technicalDetailKey) private var showsTechnical = false

    private var term: GlossaryTerm { termID.definition }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                header
                plainCard
                technicalCard
                if !term.seeAlso.isEmpty {
                    relatedCard
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(DSColors.background.ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .center, spacing: DSSpacing.md) {
            Image(systemName: term.icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(DSColors.accent)
                .frame(width: 34, height: 34)
                .background(DSColors.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(term.term)
                    .font(.title3.bold())
                Text(term.section.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var plainCard: some View {
        SurfaceCard {
            SectionHeader(icon: "text.alignleft", title: "In plain words")
            Text(term.plain)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The technical register, collapsed by default and remembered once opened.
    ///
    /// A `DisclosureGroup` bound to `AppStorage` rather than to local state on purpose:
    /// opening it here opens it for every other definition in the app too. Someone who
    /// wants the mechanism wants it everywhere, and having to expand it once per term
    /// would read as friction aimed at them specifically.
    private var technicalCard: some View {
        SurfaceCard {
            DisclosureGroup(isExpanded: $showsTechnical) {
                Text(term.technical)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DSSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DSColors.accent)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("THE TECHNICAL VERSION")
                            .font(.footnote.weight(.semibold))
                            .tracking(0.8)
                        Text(showsTechnical ? "Shown for every term" : "Names, models and numbers")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .tint(DSColors.accent)
            .accessibilityHint("Shows the technical definition for this and every other term")
        }
    }

    /// Related terms, as value-based links rather than a callback.
    ///
    /// This started as a `Button` plus an `onSelectRelated` closure so the host could
    /// choose between pushing and replacing. That was a mistake with one shape and two
    /// consequences: `GlossaryView` reached this screen through its own
    /// `navigationDestination` and had nowhere to pass the closure, so it defaulted to a
    /// no-op and every related row in the Settings route was a button that did nothing,
    /// while the same rows worked from a tapped label. `NavigationLink(value:)` resolves
    /// against whichever stack registered `GlossaryTermID`, which both hosts already do,
    /// so there is no host-specific wiring left to forget.
    private var relatedCard: some View {
        SurfaceCard {
            SectionHeader(icon: "arrow.triangle.branch", title: "Related")
            VStack(spacing: 0) {
                ForEach(term.seeAlso, id: \.self) { related in
                    NavigationLink(value: related) {
                        HStack(spacing: DSSpacing.md) {
                            Image(systemName: related.definition.icon)
                                .font(.footnote)
                                .foregroundStyle(DSColors.accent)
                                .frame(width: 20)
                            Text(related.definition.term)
                                .font(.callout.weight(.medium))
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, DSSpacing.sm)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Sheet

/// The presentation a tappable label opens.
///
/// A `NavigationStack` rather than swapping content in place, so following a related term
/// keeps a back button and the user cannot get lost two hops from where they tapped.
struct GlossaryTermSheet: View {
    let startingTerm: GlossaryTermID
    @Environment(\.dismiss) private var dismiss
    @State private var path: [GlossaryTermID] = []

    var body: some View {
        NavigationStack(path: $path) {
            GlossaryTermDetail(termID: startingTerm)
                .navigationTitle(startingTerm.definition.term)
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: GlossaryTermID.self) { id in
                    GlossaryTermDetail(termID: id)
                        .navigationTitle(id.definition.term)
                        .navigationBarTitleDisplayMode(.inline)
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }
}

// MARK: - Tappable label modifier

/// Makes any view open a definition when tapped.
///
/// The reason this is a modifier and not a wrapper view: the labels that need explaining
/// are already styled for where they sit, from a 9pt capsule on a dark gradient to a row
/// in a grouped list. Anything that imposed its own appearance would have to be
/// reimplemented per surface, and would drift.
private struct DefinedTermModifier: ViewModifier {
    let termID: GlossaryTermID
    @State private var showing = false

    func body(content: Content) -> some View {
        Button {
            DSHaptics.light()
            showing = true
        } label: {
            content
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Explains what \(termID.definition.term.lowercased()) means")
        .sheet(isPresented: $showing) {
            GlossaryTermSheet(startingTerm: termID)
        }
    }
}

extension View {
    /// Opens the definition of `term` when this view is tapped.
    func definedTerm(_ term: GlossaryTermID) -> some View {
        modifier(DefinedTermModifier(termID: term))
    }
}

// MARK: - Info button

/// The `info.circle` affordance for light surfaces, matching `InfoButtonView`'s footprint
/// so it can sit in the same rows without changing their layout.
struct GlossaryInfoButton: View {
    let termID: GlossaryTermID
    var size: Font = .footnote

    @State private var showing = false

    var body: some View {
        Button {
            DSHaptics.light()
            showing = true
        } label: {
            Image(systemName: "info.circle")
                .font(size)
                .foregroundStyle(DSColors.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What \(termID.definition.term.lowercased()) means")
        .sheet(isPresented: $showing) {
            GlossaryTermSheet(startingTerm: termID)
        }
    }
}

// MARK: - Dotted underline

/// A single line along the bottom edge, so the dash pattern can be stroked exactly rather
/// than approximated by masking a filled rectangle with a row of small ones.
private struct BottomEdge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

/// Marks a word as having a definition behind it.
///
/// A dotted underline rather than an icon per label. The onboarding completion card puts
/// seven of these in a 40pt band, and seven info glyphs there would compete with the
/// figures they are meant to support.
struct DefinitionUnderline: ViewModifier {
    var color: Color

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            BottomEdge()
                .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [1.5, 2]))
                .frame(height: 1)
                .offset(y: 2)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    /// Hints that a definition is available, without spending an icon on it.
    func definitionUnderline(_ color: Color = .white.opacity(0.35)) -> some View {
        modifier(DefinitionUnderline(color: color))
    }
}

#Preview("Term detail") {
    NavigationStack {
        GlossaryTermDetail(termID: .tops)
            .navigationTitle("TOPS")
    }
}

#Preview("Sheet") {
    Text("Host")
        .sheet(isPresented: .constant(true)) {
            GlossaryTermSheet(startingTerm: .chunk)
        }
}
