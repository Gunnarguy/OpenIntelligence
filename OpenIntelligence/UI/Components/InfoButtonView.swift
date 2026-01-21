//  InfoButtonView.swift
//  OpenIntelligence
//
//  Created by Cline on 10/30/25.
//

import SwiftUI

struct InfoButtonView: View {
    let title: String
    let explanation: String
    
    @State private var showingPopover = false
    
    var body: some View {
        Button(action: {
            showingPopover = true
        }) {
            Image(systemName: "info.circle")
                .font(.body)
                .foregroundColor(.accentColor)
        }
        .popover(isPresented: $showingPopover) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)
                
                Text(explanation)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: 300)
        }
    }
}
