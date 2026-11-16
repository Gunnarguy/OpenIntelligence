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



// MARK: - Date Extension for Relative Description

private extension Date {
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
