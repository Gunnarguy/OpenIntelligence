//
//  ColorPicker.swift
//  OpenIntelligence
//
//  A visual color picker for selecting library and accent colors.
//  Supports preset palettes and custom hex input.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Color Palette Definition

enum LibraryColorPalette: String, CaseIterable {
    case vibrant = "Vibrant"
    case pastel = "Pastel"
    case earth = "Earth"
    case neon = "Neon"
    case neutral = "Neutral"
    case gradient = "Gradient"

    var colors: [String] {
        switch self {
        case .vibrant:
            return [
                "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#00C7BE",
                "#30B0C7", "#007AFF", "#5856D6", "#AF52DE", "#FF2D55",
                "#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FFEAA7",
            ]
        case .pastel:
            return [
                "#FFB3BA", "#FFDFBA", "#FFFFBA", "#BAFFC9", "#BAE1FF",
                "#E0BBE4", "#D4A5A5", "#A8D8EA", "#AA96DA", "#FCBAD3",
                "#C9CCD5", "#F8B500", "#FFE5B4", "#B5EAD7", "#C7CEEA",
            ]
        case .earth:
            return [
                "#8B4513", "#A0522D", "#CD853F", "#DEB887", "#D2691E",
                "#BC8F8F", "#F4A460", "#DAA520", "#B8860B", "#556B2F",
                "#6B8E23", "#808000", "#BDB76B", "#9ACD32", "#8FBC8F",
            ]
        case .neon:
            return [
                "#FF0080", "#FF00FF", "#8000FF", "#0080FF", "#00FFFF",
                "#00FF80", "#00FF00", "#80FF00", "#FFFF00", "#FF8000",
                "#39FF14", "#FF073A", "#00FFEF", "#FF61A6", "#7DF9FF",
            ]
        case .neutral:
            return [
                "#2C3E50", "#34495E", "#7F8C8D", "#95A5A6", "#BDC3C7",
                "#1A1A2E", "#16213E", "#0F3460", "#533483", "#4A4E69",
                "#22223B", "#4A4A4A", "#6C757D", "#495057", "#343A40",
            ]
        case .gradient:
            // Starting colors for gradient pairs
            return [
                "#667eea", "#f093fb", "#4facfe", "#43e97b", "#fa709a",
                "#a8edea", "#ff9a9e", "#ffecd2", "#667db6", "#0cebeb",
                "#ff6a88", "#ff99ac", "#a18cd1", "#fbc2eb", "#84fab0",
            ]
        }
    }

    var icon: String {
        switch self {
        case .vibrant: return "paintpalette.fill"
        case .pastel: return "cloud.fill"
        case .earth: return "leaf.fill"
        case .neon: return "bolt.fill"
        case .neutral: return "circle.lefthalf.filled"
        case .gradient: return "circle.hexagongrid.fill"
        }
    }
}

// MARK: - Library Color Picker Sheet

struct LibraryColorPicker: View {
    @Binding var selectedColorHex: String
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPalette: LibraryColorPalette = .vibrant
    @State private var customHex: String = ""
    @State private var showCustomInput = false

    private let columns = [
        GridItem(.adaptive(minimum: 44, maximum: 52), spacing: DSSpacing.sm),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Palette tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.sm) {
                        ForEach(LibraryColorPalette.allCases, id: \.self) { palette in
                            paletteTab(palette)
                        }
                    }
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.vertical, DSSpacing.sm)
                }
                .background(DSColors.surface)

                Divider()

                // Color grid
                ScrollView {
                    LazyVGrid(columns: columns, spacing: DSSpacing.sm) {
                        ForEach(selectedPalette.colors, id: \.self) { hex in
                            colorButton(hex: hex)
                        }
                    }
                    .padding(DSSpacing.lg)

                    // Custom hex input section
                    VStack(alignment: .leading, spacing: DSSpacing.sm) {
                        Button {
                            withAnimation(DSAnimations.snappySpring) {
                                showCustomInput.toggle()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "number")
                                Text("Custom Hex Color")
                                Spacer()
                                Image(systemName: showCustomInput ? "chevron.up" : "chevron.down")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)

                        if showCustomInput {
                            HStack(spacing: DSSpacing.md) {
                                TextField("#RRGGBB", text: $customHex)
                                    .textFieldStyle(.roundedBorder)
                                    #if os(iOS)
                                    .autocapitalization(.allCharacters)
                                    #endif
                                    .onChange(of: customHex) { _, newValue in
                                        // Auto-add # prefix
                                        if !newValue.hasPrefix("#") && !newValue.isEmpty {
                                            customHex = "#" + newValue
                                        }
                                    }

                                if Color(hex: customHex) != nil {
                                    Button("Apply") {
                                        selectedColorHex = customHex.uppercased()
                                        DSHaptics.selection()
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }

                            if let color = Color(hex: customHex) {
                                HStack(spacing: DSSpacing.sm) {
                                    Circle()
                                        .fill(color)
                                        .frame(width: 24, height: 24)
                                    Text("Preview")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(DSSpacing.lg)
                    .background(DSColors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.bottom, DSSpacing.lg)
                }

                // Current selection preview
                selectionPreview
            }
            .navigationTitle("Choose Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                customHex = selectedColorHex
            }
        }
    }

    @ViewBuilder
    private var selectionPreview: some View {
        HStack(spacing: DSSpacing.md) {
            if let color = Color(hex: selectedColorHex) {
                Circle()
                    .fill(color)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(0.3), lineWidth: 2)
                    )
                    .shadow(color: color.opacity(0.4), radius: 6, y: 2)
            }

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text("Selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(selectedColorHex.uppercased())
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

    @ViewBuilder
    private func paletteTab(_ palette: LibraryColorPalette) -> some View {
        Button {
            withAnimation(DSAnimations.fastEase) {
                selectedPalette = palette
            }
        } label: {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: palette.icon)
                    .font(.caption)
                Text(palette.rawValue)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(selectedPalette == palette ? .white : .primary)
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            .background(
                selectedPalette == palette
                    ? Color.accentColor
                    : DSColors.surfaceElevated
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func colorButton(hex: String) -> some View {
        Button {
            selectedColorHex = hex
            DSHaptics.selection()
        } label: {
            if let color = Color(hex: hex) {
                Circle()
                    .fill(color)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                selectedColorHex.uppercased() == hex.uppercased()
                                    ? Color.white
                                    : Color.clear,
                                lineWidth: 3
                            )
                    )
                    .shadow(
                        color: selectedColorHex.uppercased() == hex.uppercased()
                            ? color.opacity(0.5)
                            : .clear,
                        radius: 4,
                        y: 2
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compact Color Picker Button (for settings rows)

struct ColorPickerButton: View {
    @Binding var selectedColorHex: String
    var label: String = "Color"
    @State private var showingPicker = false

    var body: some View {
        Button {
            showingPicker = true
        } label: {
            HStack(spacing: DSSpacing.sm) {
                if let color = Color(hex: selectedColorHex) {
                    Circle()
                        .fill(color)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .strokeBorder(.primary.opacity(0.1), lineWidth: 1)
                        )
                } else {
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 28, height: 28)
                }

                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(label)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text(selectedColorHex.uppercased())
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
            LibraryColorPicker(selectedColorHex: $selectedColorHex)
        }
    }
}

// MARK: - App Accent Color Picker

struct AccentColorPicker: View {
    @Binding var selectedAccentHex: String?
    @Environment(\.dismiss) private var dismiss

    // Curated accent colors (ChatGPT-style)
    private let accentColors: [(name: String, hex: String)] = [
        ("System Default", ""),
        ("Ocean Blue", "#007AFF"),
        ("Mint Green", "#00C7BE"),
        ("Coral", "#FF6B6B"),
        ("Sunset Orange", "#FF9500"),
        ("Rose", "#FF2D55"),
        ("Lavender", "#AF52DE"),
        ("Indigo", "#5856D6"),
        ("Teal", "#30B0C7"),
        ("Emerald", "#34C759"),
        ("Amber", "#FFCC00"),
        ("Slate", "#64748B"),
    ]

    private let columns = [
        GridItem(.adaptive(minimum: 70, maximum: 90), spacing: DSSpacing.md),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: DSSpacing.lg) {
                    ForEach(accentColors, id: \.hex) { item in
                        accentButton(name: item.name, hex: item.hex)
                    }
                }
                .padding(DSSpacing.lg)
            }
            .navigationTitle("Accent Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func accentButton(name: String, hex: String) -> some View {
        let isSelected = (hex.isEmpty && selectedAccentHex == nil) ||
            (selectedAccentHex?.uppercased() == hex.uppercased())

        Button {
            selectedAccentHex = hex.isEmpty ? nil : hex
            DSHaptics.selection()
        } label: {
            VStack(spacing: DSSpacing.sm) {
                ZStack {
                    if hex.isEmpty {
                        // System default - show gradient
                        Circle()
                            .fill(
                                AngularGradient(
                                    colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                                    center: .center
                                )
                            )
                            .frame(width: 48, height: 48)
                    } else if let color = Color(hex: hex) {
                        Circle()
                            .fill(color)
                            .frame(width: 48, height: 48)
                    }

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                .overlay(
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.primary : Color.clear,
                            lineWidth: 2
                        )
                        .frame(width: 54, height: 54)
                )

                Text(name)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Accent Color Settings Row

struct AccentColorSettingsRow: View {
    @Binding var accentColorHex: String?
    @State private var showingPicker = false

    private var displayColor: Color {
        if let hex = accentColorHex, let color = Color(hex: hex) {
            return color
        }
        return .accentColor
    }

    private var displayName: String {
        accentColorHex == nil ? "System Default" : (accentColorHex ?? "")
    }

    var body: some View {
        Button {
            showingPicker = true
        } label: {
            HStack(spacing: DSSpacing.md) {
                Circle()
                    .fill(displayColor)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .strokeBorder(.primary.opacity(0.1), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text("Accent Color")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text(displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            AccentColorPicker(selectedAccentHex: $accentColorHex)
        }
    }
}

// MARK: - Color Extension (Hex Support)

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6 else { return nil }

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }

    func toHex() -> String? {
        #if canImport(UIKit)
        guard let components = UIColor(self).cgColor.components else { return nil }
        #elseif canImport(AppKit)
        guard let components = NSColor(self).cgColor.components else { return nil }
        #else
        return nil
        #endif

        let r = components.count > 0 ? components[0] : 0
        let g = components.count > 1 ? components[1] : 0
        let b = components.count > 2 ? components[2] : 0

        return String(format: "#%02X%02X%02X",
                      Int(r * 255),
                      Int(g * 255),
                      Int(b * 255))
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Library Color Picker") {
    LibraryColorPicker(selectedColorHex: .constant("#007AFF"))
}

#Preview("Accent Color Picker") {
    AccentColorPicker(selectedAccentHex: .constant(nil))
}

#Preview("Settings Rows") {
    Form {
        ColorPickerButton(selectedColorHex: .constant("#FF3B30"))
        AccentColorSettingsRow(accentColorHex: .constant("#007AFF"))
    }
}
#endif
