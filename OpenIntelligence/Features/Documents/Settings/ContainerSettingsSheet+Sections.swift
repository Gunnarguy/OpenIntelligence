//
//  ContainerSettingsSheet+Sections.swift
//  OpenIntelligence
//
//  Extracted view sections to reduce body complexity for Swift compiler.
//

import NaturalLanguage
import SwiftUI

// MARK: - Extracted Form Sections

extension ContainerSettingsSheet {
    /// Document names for smart icon suggestions
    private var documentNamesForIconSuggestion: [String] {
        activeContainerDocuments.map { $0.filename }
    }

    @ViewBuilder
    var identitySection: some View {
        Section(header: Text("Library")) {
            Text("The name, icon and color this library shows across the app.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Name", text: $name)

            // SF Symbol Picker with smart suggestions based on library content
            SFSymbolPickerButton(
                selectedSymbol: $icon,
                documentNames: documentNamesForIconSuggestion
            )

            // Color Picker
            ColorPickerButton(selectedColorHex: $colorHex, label: "Color")
        }
    }

}



// MARK: - Separate evaluation

/// Builds its content in its own `body`, so the sheet's `body` holds a small closure instead of the whole section.
///
/// 5.8 build 150 crashed on an iPhone opening Library Settings with Technical Details on: the main thread ran out of
/// stack inside `ContainerSettingsSheet.body` while it built the Library Deep Dive card, because one `body` built
/// every section's value at once and a Debug build gives each of those values its own stack slot. Each section in
/// this wrapper is built later, in its own update, after the sheet's `body` has returned.
struct SeparatelyBuilt<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View { content() }
}

// MARK: - Date Extension for Relative Description

private extension Date {
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
