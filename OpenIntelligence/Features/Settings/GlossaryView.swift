//
//  GlossaryView.swift
//  OpenIntelligence
//
//  The index of every word the app uses, in both registers.
//
//  This screen is not the primary way anyone reads a definition. Each term is tappable
//  where it already appears, which is where the question actually occurs. This exists for
//  the other case: someone who read a word an hour ago, cannot remember which screen it
//  was on, and wants to look it up by name.
//
//  It shares `Glossary` with every popover in the app, so there is one definition of each
//  word rather than one per surface. `HowItWorksView` is the narrative companion to this
//  screen and deliberately is not a copy of it: that one explains the pipeline in order,
//  this one explains individual words out of order.
//

import SwiftUI

struct GlossaryView: View {
    @State private var query = ""
    @AppStorage(GlossaryPreference.technicalDetailKey) private var showsTechnical = false

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var results: [GlossaryTerm] {
        Glossary.search(trimmed)
    }

    // `.navigationDestination(for:)` sits on this wrapper rather than directly on the `List`
    // below, and the reason is `.searchable`. Both modifiers attach machinery to the surrounding
    // navigation controller — `.searchable` installs a `UISearchController` on it, and
    // `.navigationDestination` installs a destination provider on it — and putting both on the
    // exact same view is a known collision point: a push fired by `NavigationLink(value:)` from
    // inside a searchable list can fail to resolve cleanly against a destination registered on
    // that same list, so the transition animates but does not land on new content, and the stack
    // is left in a state a subsequent pop does not recover from correctly. Declaring
    // `.navigationDestination` one level up, on a plain `Group` the search controller has no
    // reason to touch, removes the collision regardless of the exact mechanism.
    var body: some View {
        Group {
            List {
                if trimmed.isEmpty {
                    Section {
                        intro
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }

                    ForEach(GlossarySection.allCases) { section in
                        Section {
                            ForEach(Glossary.terms(in: section)) { term in
                                row(term)
                            }
                        } header: {
                            Label(section.title, systemImage: section.icon)
                        }
                    }
                } else {
                    Section {
                        ForEach(results) { term in
                            row(term)
                        }
                    } header: {
                        Text("\(results.count) \(results.count == 1 ? "term" : "terms")")
                    }
                }
            }
            .searchable(text: $query, prompt: "Search these words")
            .overlay {
                if !trimmed.isEmpty, results.isEmpty {
                    ContentUnavailableView.search(text: trimmed)
                }
            }
        }
        .navigationTitle("Plain English")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: GlossaryTermID.self) { id in
            GlossaryTermDetail(termID: id)
                .navigationTitle(id.definition.term)
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// Says what the screen is and puts the register switch at the top.
    ///
    /// The toggle is here rather than only inside each definition because a user who wants
    /// the technical register wants it before reading the first term, not after expanding
    /// one and discovering the setting exists.
    private var intro: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text("Every word this app puts on screen, explained twice. Plain first, and the mechanism underneath if you want it.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $showsTechnical) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Always show the technical version")
                        .font(.subheadline.weight(.medium))
                    Text("Applies to every definition in the app, including the ones you tap from other screens")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(DSColors.accent)
        }
        .padding(DSSpacing.lg)
    }

    private func row(_ term: GlossaryTerm) -> some View {
        NavigationLink(value: term.id) {
            HStack(alignment: .top, spacing: DSSpacing.md) {
                Image(systemName: term.icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DSColors.accent)
                    .frame(width: 22)
                    .padding(.top, 2)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(term.term)
                        .font(.body.weight(.medium))
                    // One line of the plain register, so the list is scannable without
                    // opening anything. The full definition and the technical register
                    // are both one tap away.
                    Text(term.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityLabel(term.term)
        .accessibilityHint(term.plain)
    }
}

#Preview {
    NavigationStack {
        GlossaryView()
    }
}
