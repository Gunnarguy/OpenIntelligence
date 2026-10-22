//
//  SFSymbolPicker.swift
//  OpenIntelligence
//
//  A visual SF Symbol picker for selecting icons.
//

import SwiftUI

struct SFSymbolPicker: View {
    @Binding var selectedSymbol: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedCategory: SymbolCategory = .all

    /// Optional suggested icons based on library content (shown at top when provided)
    var suggestedIcons: [String] = []

    /// Whether to show the "Suggested for you" section
    private var showSuggestions: Bool {
        !suggestedIcons.isEmpty && searchText.isEmpty && selectedCategory == .all
    }

    // Common symbols organized by category
    enum SymbolCategory: String, CaseIterable {
        case all = "All"
        case documents = "Documents"
        case folders = "Folders"
        case books = "Books"
        case science = "Science"
        case tech = "Tech"
        case nature = "Nature"
        case shapes = "Shapes"
        case misc = "Misc"

        var symbols: [String] {
            switch self {
            case .all:
                return SymbolCategory.allCases.filter { $0 != .all }.flatMap { $0.symbols }
            case .documents:
                return [
                    "doc", "doc.fill", "doc.text", "doc.text.fill",
                    "doc.richtext", "doc.richtext.fill", "doc.plaintext", "doc.plaintext.fill",
                    "doc.append", "doc.append.fill", "doc.text.magnifyingglass",
                    "doc.on.doc", "doc.on.doc.fill", "doc.on.clipboard", "doc.on.clipboard.fill",
                    "note", "note.text", "note.text.badge.plus",
                    "list.bullet", "list.bullet.rectangle", "list.bullet.clipboard",
                    "checklist", "checklist.checked", "text.document", "text.document.fill",
                ]
            case .folders:
                return [
                    "folder", "folder.fill", "folder.badge.plus", "folder.fill.badge.plus",
                    "folder.badge.gear", "folder.fill.badge.gear", "folder.badge.questionmark",
                    "folder.badge.person.crop", "folder.fill.badge.person.crop",
                    "square.grid.2x2", "square.grid.2x2.fill", "square.grid.3x3",
                    "rectangle.stack", "rectangle.stack.fill", "tray", "tray.fill",
                    "tray.2", "tray.2.fill", "tray.full", "tray.full.fill",
                    "archivebox", "archivebox.fill", "externaldrive", "externaldrive.fill",
                ]
            case .books:
                return [
                    "book", "book.fill", "book.closed", "book.closed.fill",
                    "books.vertical", "books.vertical.fill", "book.pages", "book.pages.fill",
                    "bookmark", "bookmark.fill", "bookmark.circle", "bookmark.circle.fill",
                    "text.book.closed", "text.book.closed.fill", "character.book.closed",
                    "magazine", "magazine.fill", "newspaper", "newspaper.fill",
                    "graduationcap", "graduationcap.fill", "backpack", "backpack.fill",
                ]
            case .science:
                return [
                    "atom", "brain", "brain.head.profile", "brain.filled.head.profile",
                    "waveform", "waveform.circle", "waveform.circle.fill",
                    "chart.bar", "chart.bar.fill", "chart.pie", "chart.pie.fill",
                    "chart.line.uptrend.xyaxis", "function", "sum", "percent",
                    "x.squareroot", "number", "number.circle", "number.circle.fill",
                    "testtube.2", "flask", "flask.fill", "microscope",
                ]
            case .tech:
                return [
                    "cpu", "cpu.fill", "memorychip", "memorychip.fill",
                    "server.rack", "externaldrive.connected.to.line.below",
                    "network", "wifi", "antenna.radiowaves.left.and.right",
                    "bolt.horizontal", "bolt.horizontal.fill", "bolt", "bolt.fill",
                    "gearshape", "gearshape.fill", "gearshape.2", "gearshape.2.fill",
                    "wrench", "wrench.fill", "hammer", "hammer.fill",
                    "terminal", "terminal.fill", "chevron.left.forwardslash.chevron.right",
                ]
            case .nature:
                return [
                    "leaf", "leaf.fill", "leaf.arrow.triangle.circlepath",
                    "tree", "tree.fill", "mountain.2", "mountain.2.fill",
                    "sun.max", "sun.max.fill", "moon", "moon.fill",
                    "star", "star.fill", "star.circle", "star.circle.fill",
                    "sparkle", "sparkles", "cloud", "cloud.fill",
                    "flame", "flame.fill", "drop", "drop.fill",
                ]
            case .shapes:
                return [
                    "circle", "circle.fill", "square", "square.fill",
                    "triangle", "triangle.fill", "diamond", "diamond.fill",
                    "hexagon", "hexagon.fill", "pentagon", "pentagon.fill",
                    "seal", "seal.fill", "shield", "shield.fill",
                    "heart", "heart.fill", "suit.heart", "suit.heart.fill",
                    "cube", "cube.fill", "cylinder", "cylinder.fill",
                ]
            case .misc:
                return [
                    "lightbulb", "lightbulb.fill", "lightbulb.max", "lightbulb.max.fill",
                    "puzzlepiece", "puzzlepiece.fill", "puzzlepiece.extension",
                    "flag", "flag.fill", "tag", "tag.fill",
                    "pin", "pin.fill", "mappin", "mappin.circle.fill",
                    "gift", "gift.fill", "trophy", "trophy.fill",
                    "medal", "medal.fill", "rosette", "crown", "crown.fill",
                    "wand.and.stars", "sparkle.magnifyingglass", "eyes",
                ]
            }
        }

        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .documents: return "doc.text"
            case .folders: return "folder"
            case .books: return "book"
            case .science: return "atom"
            case .tech: return "cpu"
            case .nature: return "leaf"
            case .shapes: return "square.on.circle"
            case .misc: return "sparkles"
            }
        }
    }

    private var filteredSymbols: [String] {
        let symbols = selectedCategory.symbols
        if searchText.isEmpty {
            return symbols
        }
        return symbols.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 50, maximum: 60), spacing: DSSpacing.sm),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.sm) {
                        ForEach(SymbolCategory.allCases, id: \.self) { category in
                            categoryTab(category)
                        }
                    }
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.vertical, DSSpacing.sm)
                }
                .background(DSColors.surface)

                Divider()

                // Search
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search symbols...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
                .background(DSColors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
                .padding(.horizontal, DSSpacing.lg)
                .padding(.vertical, DSSpacing.sm)

                // Symbol grid
                ScrollView {
                    VStack(alignment: .leading, spacing: DSSpacing.lg) {
                        // Suggested icons section (when available)
                        if showSuggestions {
                            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                                HStack(spacing: DSSpacing.xs) {
                                    Image(systemName: "sparkles")
                                        .font(.caption)
                                        .foregroundStyle(Color.accentColor)
                                    Text("Suggested for your content")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                }
                                .padding(.horizontal, DSSpacing.lg)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: DSSpacing.sm) {
                                        ForEach(suggestedIcons, id: \.self) { symbol in
                                            suggestedSymbolButton(symbol)
                                        }
                                    }
                                    .padding(.horizontal, DSSpacing.lg)
                                }
                            }
                            .padding(.top, DSSpacing.sm)

                            Divider()
                                .padding(.horizontal, DSSpacing.lg)
                        }

                        // All symbols grid
                        LazyVGrid(columns: columns, spacing: DSSpacing.sm) {
                            ForEach(filteredSymbols, id: \.self) { symbol in
                                symbolButton(symbol)
                            }
                        }
                        .padding(.horizontal, DSSpacing.lg)
                        .padding(.bottom, DSSpacing.lg)
                    }
                }

                // Current selection preview
                HStack(spacing: DSSpacing.md) {
                    Image(systemName: selectedSymbol)
                        .font(.title)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 50, height: 50)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))

                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text("Selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(selectedSymbol)
                            .font(.subheadline.weight(.medium).monospaced())
                    }

                    Spacer()

                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(DSSpacing.lg)
                .background(DSColors.surface)
            }
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func categoryTab(_ category: SymbolCategory) -> some View {
        Button {
            withAnimation(DSAnimations.fastEase) {
                selectedCategory = category
            }
        } label: {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: category.icon)
                    .font(.caption)
                Text(category.rawValue)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(selectedCategory == category ? .white : .primary)
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            .background(
                selectedCategory == category
                    ? Color.accentColor
                    : DSColors.surfaceElevated
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func symbolButton(_ symbol: String) -> some View {
        Button {
            selectedSymbol = symbol
            DSHaptics.selection()
        } label: {
            VStack(spacing: DSSpacing.xs) {
                Image(systemName: symbol)
                    .font(.title2)
                    .frame(width: DSSpacing.tapTarget, height: DSSpacing.tapTarget)
                    .foregroundStyle(selectedSymbol == symbol ? .white : .primary)
                    .background(
                        selectedSymbol == symbol
                            ? Color.accentColor
                            : DSColors.surfaceElevated
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func suggestedSymbolButton(_ symbol: String) -> some View {
        Button {
            selectedSymbol = symbol
            DSHaptics.selection()
        } label: {
            VStack(spacing: DSSpacing.xs) {
                ZStack {
                    Circle()
                        .fill(
                            selectedSymbol == symbol
                                ? Color.accentColor
                                : Color.accentColor.opacity(0.15)
                        )
                        .frame(width: 56, height: 56)

                    Image(systemName: symbol)
                        .font(.title)
                        .foregroundStyle(
                            selectedSymbol == symbol
                                ? .white
                                : Color.accentColor
                        )
                }
                .overlay(
                    Circle()
                        .strokeBorder(
                            selectedSymbol == symbol ? Color.accentColor : Color.accentColor.opacity(0.3),
                            lineWidth: selectedSymbol == symbol ? 0 : 2
                        )
                )
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compact inline picker for settings

struct SFSymbolPickerButton: View {
    @Binding var selectedSymbol: String
    /// Document names for smart icon suggestions
    var documentNames: [String] = []
    @State private var showingPicker = false

    /// Computed suggested icons based on document content
    private var suggestedIcons: [String] {
        guard !documentNames.isEmpty else { return [] }
        return LibraryIconSuggestionService.suggestIcons(documentNames: documentNames, limit: 6)
    }

    var body: some View {
        Button {
            showingPicker = true
        } label: {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: selectedSymbol)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))

                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text("Icon")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text(selectedSymbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, DSSpacing.xs)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingPicker) {
            SFSymbolPicker(selectedSymbol: $selectedSymbol, suggestedIcons: suggestedIcons)
        }
    }
}

#if DEBUG
#Preview {
    SFSymbolPicker(selectedSymbol: .constant("folder.fill"))
}
#endif
